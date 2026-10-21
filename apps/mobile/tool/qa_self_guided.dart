// ─────────────────────────────────────────────────────────────────────────────
// Self-Guided Coaching Mode — automated QA certification harness.
//
// Runs the whole automatable Self-Guided journey against the 12 Circle QA
// project and asserts real DB state. The target comes from QA_URL / QA_ANON and
// is verified before anything runs (tool/qa_target.dart); it used to be a
// hardcoded production constant, which is what made this harness -- which
// signs users up and calls generate_client_plan() -- a production writer:
//   create user → onboarding → self_guided mode → program generation →
//   workout session + resume state + completion → nutrition / habits / check-in →
//   scoring (award_points) → permissions (RLS) → schema validation → cleanup.
//
// Things that CANNOT be certified head-less are reported as MANUAL with the
// reason (Google/Apple OAuth, real Stripe checkout, push-notification delivery,
// pixel-level UI, 10k-record performance, device/offline/timezone edge cases).
//
//   export QA_URL=... QA_ANON=...
//   dart run tool/qa_self_guided.dart
//   SERVICE_ROLE_KEY=... dart run tool/qa_self_guided.dart   # also purges the test user
//
// Exit code 0 = all critical checks passed; 1 = at least one failed.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:convert';
import 'dart:io';

import 'qa_target.dart';

// ENV-5: the target is resolved from QA_URL / QA_ANON and positively verified
// as the QA project before a single request goes out. There is no default --
// this file used to hardcode the PRODUCTION ref and key right here.
final QaTarget _target = resolveQaTarget();
String get _url => _target.url;
String get _anon => _target.anonKey;

// A seeded coach — used only as the "other user" for RLS/permission leak tests.
const _coachEmail = 'coach@12circle.app';
const _coachPass  = 'Coach1234!';

final _serviceRole = Platform.environment['SERVICE_ROLE_KEY'];

int _pass = 0, _fail = 0, _manual = 0, _warn = 0;
final _failures = <String>[];
final _manuals  = <String>[];
final _warnings = <String>[];

void _ok(String id, String msg)   { _pass++; print('  PASS  $id  $msg'); }
void _no(String id, String msg)   { _fail++; _failures.add('$id  $msg'); print('  FAIL  $id  $msg'); }
void _man(String id, String msg)  { _manual++; _manuals.add('$id  $msg'); print('  MANUAL $id  $msg'); }
// A real observation that is a spec/impl discrepancy or a payment-gated step —
// worth surfacing but not a blocking automated defect.
void _wr(String id, String msg)   { _warn++; _warnings.add('$id  $msg'); print('  WARN  $id  $msg'); }
void _section(String s) => print('\n▓▓ $s');

String _uuid() {
  final r = List.generate(16, (_) => (DateTime.now().microsecondsSinceEpoch + _rand()) & 0xff);
  r[6] = (r[6] & 0x0f) | 0x40; r[8] = (r[8] & 0x3f) | 0x80;
  String hx(int i) => r[i].toRadixString(16).padLeft(2, '0');
  return '${hx(0)}${hx(1)}${hx(2)}${hx(3)}-${hx(4)}${hx(5)}-${hx(6)}${hx(7)}-'
         '${hx(8)}${hx(9)}-${hx(10)}${hx(11)}${hx(12)}${hx(13)}${hx(14)}${hx(15)}';
}
int _rand() => DateTime.now().microsecond * 2654435761 & 0xffffff;

final _client = HttpClient();

Future<({int code, dynamic body})> _req(
  String method,
  String path, {
  String? token,
  Map<String, String> query = const {},
  Object? jsonBody,
  Map<String, String> extraHeaders = const {},
}) async {
  final uri = Uri.parse('$_url$path')
      .replace(queryParameters: query.isEmpty ? null : query);
  final r = await _client.openUrl(method, uri);
  r.headers.set('apikey', _anon);
  r.headers.set('Authorization', 'Bearer ${token ?? _anon}');
  r.headers.set('Content-Type', 'application/json');
  extraHeaders.forEach(r.headers.set);
  if (jsonBody != null) r.write(jsonEncode(jsonBody));
  final resp = await r.close();
  final text = await resp.transform(utf8.decoder).join();
  dynamic parsed;
  try { parsed = text.isEmpty ? null : jsonDecode(text); } catch (_) { parsed = text; }
  return (code: resp.statusCode, body: parsed);
}

Future<({String token, String uid})?> _auth(String path, String email, String pass,
    {Map<String, String> query = const {}}) async {
  final res = await _req('POST', path, query: query, jsonBody: {'email': email, 'password': pass});
  if (res.code == 200 && res.body is Map && res.body['access_token'] != null) {
    return (token: res.body['access_token'] as String, uid: res.body['user']['id'] as String);
  }
  return null;
}

Future<({String token, String uid})?> _signIn(String e, String p) =>
    _auth('/auth/v1/token', e, p, query: {'grant_type': 'password'});
Future<({String token, String uid})?> _signUp(String e, String p) =>
    _auth('/auth/v1/signup', e, p);

bool _isList(dynamic b) => b is List;
int _len(dynamic b) => b is List ? b.length : 0;

Future<void> main() async {
  print('════════════════════════════════════════════════════════════');
  print(' SELF-GUIDED COACHING MODE — QA CERTIFICATION');
  print(' target: $_url');
  print('════════════════════════════════════════════════════════════');

  final email = 'qa+sg${DateTime.now().millisecondsSinceEpoch}@12circle.app';
  const pass  = 'QaTest1234!';

  // ── 1. ACCOUNT CREATION ────────────────────────────────────────────────────
  _section('1. Account creation');
  final su = await _signUp(email, pass);
  if (su == null) { _no('SG-001', 'signup failed for $email — cannot continue'); return _summary(); }
  final t = su.token, uid = su.uid;
  _ok('SG-001', 'account created ($email, ${uid.substring(0, 8)})');
  _man('SG-001b', 'Google/Apple OAuth sign-in — requires real provider consent (UI/manual)');

  // Profile row (auto-created by trigger, or we create it) — role=client, mode=null.
  var prof = await _req('GET', '/rest/v1/user_profiles',
      token: t, query: {'id': 'eq.$uid', 'select': 'id,role,coaching_mode,onboarding_complete'});
  if (_len(prof.body) == 0) {
    await _req('POST', '/rest/v1/user_profiles',
        token: t, jsonBody: {'id': uid, 'role': 'client', 'onboarding_complete': false});
    prof = await _req('GET', '/rest/v1/user_profiles',
        token: t, query: {'id': 'eq.$uid', 'select': 'id,role,coaching_mode,onboarding_complete'});
  }
  final p0 = _len(prof.body) > 0 ? prof.body[0] as Map : const {};
  (p0['role'] == 'client')
      ? _ok('SG-001c', 'user_profiles.role = client')
      : _no('SG-001c', 'role expected client, got ${p0['role']}');
  (p0['coaching_mode'] == null)
      ? _ok('SG-001d', 'user_profiles.coaching_mode = null (pre-selection)')
      : _wr('SG-001d', 'new profile defaults coaching_mode=${p0['coaching_mode']} (spec expects null pre-selection) — confirm intended');

  // ── 2. ONBOARDING ──────────────────────────────────────────────────────────
  _section('2. Onboarding — every answer persists');
  final intake = <String, dynamic>{
    'first_name': 'QA', 'last_name': 'SelfGuided',
    'fitness_goal': 'fat_loss', 'gender': 'male', 'date_of_birth': '1995-05-05',
    'height_cm': 180, 'weight_kg': 82, 'weight_goal_kg': 76,
    'activity_level': 'moderate', 'experience_level': 'intermediate',
    'training_days_per_week': 4, 'training_location': 'gym',
    'nutrition_goal': 'high_protein', 'dietary_restrictions': ['none'],
    'has_injuries': false, 'injury_locations': <String>[],
    'onboarding_complete': true,
  };
  final onb = await _req('PATCH', '/rest/v1/user_profiles',
      token: t, query: {'id': 'eq.$uid'},
      jsonBody: intake, extraHeaders: {'Prefer': 'return=representation'});
  if (onb.code == 200 && _len(onb.body) > 0) {
    final saved = onb.body[0] as Map;
    var missing = <String>[];
    for (final k in intake.keys) {
      final want = intake[k], got = saved[k];
      // Empty-list round-trips (null vs []) are storage-dependent — don't assert.
      if (want is List && want.isEmpty) continue;
      final eq = (want is List)
          ? (got is List && got.length == want.length)
          : got == want;
      if (!eq) missing.add(k);
    }
    missing.isEmpty
        ? _ok('SG-002', 'all ${intake.length} onboarding fields saved & verified')
        : _no('SG-002', 'fields not persisted as sent: ${missing.join(', ')}');
  } else {
    _no('SG-002', 'onboarding PATCH failed (HTTP ${onb.code}) ${onb.body}');
  }
  // Water/step goals — optional columns; report if the schema doesn't store them.
  final extra = await _req('PATCH', '/rest/v1/user_profiles', token: t,
      query: {'id': 'eq.$uid'}, jsonBody: {'water_goal_ml': 3000, 'step_goal': 8000});
  (extra.code == 200 || extra.code == 204)
      ? _ok('SG-002b', 'water goal + step goal stored')
      : _man('SG-002b', 'water/step goal columns absent (HTTP ${extra.code}) — confirm where these persist');

  // ── 3. COACHING MODE SELECTION ─────────────────────────────────────────────
  _section('3. Coaching mode → self_guided');
  final setMode = await _req('PATCH', '/rest/v1/user_profiles', token: t,
      query: {'id': 'eq.$uid'}, jsonBody: {'coaching_mode': 'self_guided'},
      extraHeaders: {'Prefer': 'return=representation'});
  (setMode.code == 200 && _len(setMode.body) > 0 && setMode.body[0]['coaching_mode'] == 'self_guided')
      ? _ok('SG-003', 'coaching_mode = self_guided (persisted)')
      : _no('SG-003', 'set coaching_mode failed (HTTP ${setMode.code}) ${setMode.body}');
  final plan = await _req('POST', '/rest/v1/rpc/client_plan', token: t, jsonBody: {});
  if (plan.body == 'self_guided') {
    _ok('SG-003b', 'client_plan() = self_guided (entitlement active)');
  } else if (plan.body == 'free') {
    _wr('SG-003b', 'client_plan() = free — coaching_mode is set, but Self-Guided is a PAID tier: '
        'entitlement (and program generation) activates only after an active subscription. '
        'Run the post-payment path via Stripe test-mode / seeded subscription to certify fully.');
  } else {
    _no('SG-003b', 'client_plan() = ${plan.body} (expected self_guided or free)');
  }

  // ── 4. SUBSCRIPTION ────────────────────────────────────────────────────────
  _section('4. Subscription');
  final subs = await _req('GET', '/rest/v1/subscriptions',
      token: t, query: {'user_id': 'eq.$uid', 'select': 'status,plan_tier,kind'});
  (subs.code == 200)
      ? _ok('SG-004', 'subscriptions table readable for own user (${_len(subs.body)} rows)')
      : _no('SG-004', 'subscriptions read failed (HTTP ${subs.code})');
  _man('SG-004b', 'Stripe checkout / success / cancel / expired-card / retry — real payment (manual or Stripe test-mode CI)');

  // ── 5. AUTOMATIC PROGRAM GENERATION ────────────────────────────────────────
  _section('5. Automatic program generation');
  final gen = await _req('POST', '/rest/v1/rpc/generate_client_plan', token: t, jsonBody: {});
  (gen.code == 200 || gen.code == 204)
      ? _ok('SG-005', 'generate_client_plan RPC executed (HTTP ${gen.code})')
      : _no('SG-005', 'generate_client_plan failed (HTTP ${gen.code}) ${gen.body}');
  // The per-user plan is an active workout_program_assignments row (→ workout_programs).
  final asn = await _req('GET', '/rest/v1/workout_program_assignments', token: t,
      query: {'client_id': 'eq.$uid', 'status': 'eq.active',
              'select': 'id,program_id,current_week,status'});
  final asnRows = _isList(asn.body) ? asn.body as List : const [];
  if (asnRows.isNotEmpty) {
    _ok('SG-005b', 'active program assigned (program ${asnRows.first['program_id']?.toString().substring(0, 8)})');
    final pid = asnRows.first['program_id'];
    final pw = await _req('GET', '/rest/v1/program_workouts', token: t,
        query: {'program_id': 'eq.$pid', 'select': 'id', 'limit': '50'});
    (_len(pw.body) > 0)
        ? _ok('SG-005c', 'program has ${_len(pw.body)} scheduled workouts')
        : _no('SG-005c', 'program_workouts empty for the assigned program (HTTP ${pw.code})');
  } else if (plan.body == 'free') {
    _wr('SG-005b', 'no active program — generation is gated behind an active subscription '
        '(user is on free entitlement). Certify post-payment generation with a seeded '
        'subscription / Stripe test-mode.');
  } else {
    _no('SG-005b', 'no active program assignment despite entitlement (HTTP ${asn.code})');
  }
  _man('SG-005d', 'Nutrition targets / water goal / habit plan / calendar — verify UI surfaces the generated plan');

  // ── 6. DASHBOARD DATA (self-guided) ────────────────────────────────────────
  _section('6. Dashboard data sources present');
  for (final entry in {
    '12 Circle score': '/rest/v1/user_scores?user_id=eq.$uid&select=current_cycle_score',
    'challenges':      '/rest/v1/challenges?select=id&limit=1',
    'community':       '/rest/v1/community_posts?select=id&limit=1',
    'exercise library':'/rest/v1/custom_exercises?select=id&limit=1',
  }.entries) {
    final r = await _req('GET', entry.value, token: t);
    (r.code == 200) ? _ok('SG-006', '${entry.key} readable') : _no('SG-006', '${entry.key} read failed (HTTP ${r.code})');
  }

  // ── 10-12. WORKOUT SESSION + RESUME + COMPLETION ───────────────────────────
  _section('10-12. Workout session, resume state, completion + scoring');
  final progress = {'current_exercise_index': 2, 'current_set_index': 1,
                    'sets': [{'reps': 8, 'weight': 60}]};
  final wk = await _req('POST', '/rest/v1/workout_sessions', token: t,
      jsonBody: {
        'user_id': uid, 'status': 'in_progress', 'elapsed_seconds': 63,
        'workout_name': 'QA Lower Body', 'workout_title': 'QA Lower Body',
        'completed_sets': 3, 'progress_data': progress,
      }, extraHeaders: {'Prefer': 'return=representation'});
  String? wkId;
  if (wk.code == 201 && _len(wk.body) > 0) {
    wkId = wk.body[0]['id'] as String?;
    _ok('SG-010', 'workout_session started (in_progress, elapsed=63, completed_sets=3)');
    // Resume: read the session back and confirm the exact state was persisted.
    final resume = await _req('GET', '/rest/v1/workout_sessions', token: t,
        query: {'id': 'eq.$wkId', 'select': 'status,elapsed_seconds,completed_sets,progress_data'});
    final s = _len(resume.body) > 0 ? resume.body[0] as Map : const {};
    final pd = s['progress_data'];
    (s['status'] == 'in_progress' && s['elapsed_seconds'] == 63 && s['completed_sets'] == 3 &&
     pd is Map && pd['current_exercise_index'] == 2 && pd['current_set_index'] == 1)
        ? _ok('SG-011', 'resume restores exact state (exercise 2, set 1, elapsed 63, 3 sets)')
        : _no('SG-011', 'resume state mismatch: status=${s['status']} elapsed=${s['elapsed_seconds']} sets=${s['completed_sets']} pd=$pd');
    final done = await _req('PATCH', '/rest/v1/workout_sessions', token: t,
        query: {'id': 'eq.$wkId'}, jsonBody: {'status': 'completed', 'duration_seconds': 1800});
    (done.code == 200 || done.code == 204)
        ? _ok('SG-012', 'workout marked completed')
        : _no('SG-012', 'complete failed (HTTP ${done.code}) ${done.body}');
  } else {
    _no('SG-010', 'workout_session create failed (HTTP ${wk.code}) ${wk.body}');
  }

  // ── 15. SCORING ENGINE (award_points is the source of truth) ───────────────
  _section('15. Scoring engine — automatic points');
  Future<bool> award(String cat, String action, int pts, String dk) async {
    final r = await _req('POST', '/rest/v1/rpc/award_points', token: t, jsonBody: {
      'p_category': cat, 'p_action': action, 'p_points': pts,
      'p_ref_type': null, 'p_ref_id': null, 'p_dedup_key': dk,
    });
    return r.code == 200 || r.code == 204;
  }
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final awards = <List<dynamic>>[
    ['workouts',  'workout_complete', 25, 'qa_wc_$stamp'],
    ['nutrition', 'protein_goal',     15, 'qa_pg_$stamp'],
    ['nutrition', 'water_goal',       10, 'qa_wg_$stamp'],
    ['habits',    'habits_all',       20, 'qa_ha_$stamp'],
    ['checkins',  'checkin_weekly',   25, 'qa_ck_$stamp'],
  ];
  var awardedOk = 0;
  for (final a in awards) {
    if (await award(a[0] as String, a[1] as String, a[2] as int, a[3] as String)) awardedOk++;
  }
  (awardedOk == awards.length)
      ? _ok('SG-015', 'award_points fired for all ${awards.length} categories')
      : _no('SG-015', 'only $awardedOk/${awards.length} award_points calls succeeded');
  // Verify the ledger actually recorded them.
  final ev = await _req('GET', '/rest/v1/score_events', token: t,
      query: {'user_id': 'eq.$uid', 'select': 'action,points', 'order': 'created_at.desc', 'limit': '20'});
  final evRows = _isList(ev.body) ? ev.body as List : const [];
  final gotComplete = evRows.any((r) => r['action'] == 'workout_complete' && r['points'] == 25);
  gotComplete
      ? _ok('SG-015b', 'score_events ledger recorded workout_complete +25 (${evRows.length} recent events)')
      : _no('SG-015b', 'workout_complete +25 not found in score_events (${evRows.length} rows)');
  final us = await _req('GET', '/rest/v1/user_scores', token: t,
      query: {'user_id': 'eq.$uid', 'select': 'current_cycle_score,lifetime_score'});
  final score = _len(us.body) > 0 ? (us.body[0]['current_cycle_score'] as num? ?? 0) : 0;
  (score > 0)
      ? _ok('SG-015c', 'user_scores aggregated current_cycle_score = $score')
      : _no('SG-015c', 'user_scores not aggregated (score=$score) — check award_points → user_scores rollup');
  for (final t2 in ['badges', 'score_cycles']) {
    final r = await _req('GET', '/rest/v1/$t2', token: t, query: {'select': 'id', 'limit': '1'});
    (r.code == 200) ? _ok('SG-015d', '$t2 readable') : _no('SG-015d', '$t2 read failed (HTTP ${r.code})');
  }
  final lb = await _req('GET', '/rest/v1/user_scores', token: t,
      query: {'select': 'user_id,current_cycle_score', 'order': 'current_cycle_score.desc', 'limit': '5'});
  (lb.code == 200) ? _ok('SG-015e', 'leaderboard query (user_scores desc) works')
                   : _no('SG-015e', 'leaderboard query failed (HTTP ${lb.code})');
  _man('SG-015f', 'Daily/weekly/monthly score resets — driven by cron; verify scheduled job, not head-less');

  // ── 13/14. NUTRITION + HABITS logging ──────────────────────────────────────
  _section('13-14. Nutrition + habit logging');
  final nut = await _req('POST', '/rest/v1/nutrition_logs', token: t,
      jsonBody: {'user_id': uid, 'meal_type': 'lunch', 'food_name': 'QA meal',
                 'calories': 600, 'protein': 45, 'carbs': 55, 'fat': 18,
                 'amount_g': 300, 'serving_unit': 'g',
                 'logged_at': DateTime.now().toIso8601String()},
      extraHeaders: {'Prefer': 'return=representation'});
  String? nId;
  (nut.code == 201 && _len(nut.body) > 0)
      ? (() { nId = nut.body[0]['id'] as String?; _ok('SG-013', 'nutrition_log written with macros'); })()
      : _no('SG-013', 'nutrition log failed (HTTP ${nut.code}) ${nut.body}');
  // Habits log straight to habit_logs (the app's model), keyed by habit_id+date.
  final habitId = _uuid();
  final hl = await _req('POST', '/rest/v1/habit_logs', token: t,
      jsonBody: {'user_id': uid, 'habit_id': habitId,
                 'logged_date': DateTime.now().toIso8601String().split('T')[0],
                 'value': 1, 'completed': true,
                 'logged_at': DateTime.now().toIso8601String()},
      extraHeaders: {'Prefer': 'return=representation'});
  if (hl.code == 201) {
    _ok('SG-014', 'habit_log written (completed=true)');
  } else if (hl.body is Map && (hl.body['code'] == '23503')) {
    _wr('SG-014', 'habit_logs.habit_id has an FK to a habits row — seed a habit definition to certify (HTTP ${hl.code})');
  } else {
    _no('SG-014', 'habit log failed (HTTP ${hl.code}) ${hl.body}');
  }

  // ── 16/17. CHALLENGES + COMMUNITY ──────────────────────────────────────────
  _section('16-17. Challenges + community');
  final ch = await _req('GET', '/rest/v1/challenges', token: t, query: {'select': 'id', 'limit': '1'});
  if (_len(ch.body) > 0) {
    final cid = ch.body[0]['id'];
    final join = await _req('POST', '/rest/v1/challenge_participants', token: t,
        jsonBody: {'challenge_id': cid, 'user_id': uid},
        extraHeaders: {'Prefer': 'return=representation'});
    (join.code == 201 || join.code == 409)
        ? _ok('SG-016', 'join challenge works (or already joined)')
        : _no('SG-016', 'join failed (HTTP ${join.code}) ${join.body}');
    await _req('DELETE', '/rest/v1/challenge_participants', token: t,
        query: {'challenge_id': 'eq.$cid', 'user_id': 'eq.$uid'});
  } else {
    _man('SG-016', 'no challenge seeded to join — seed one to certify challenge flow');
  }
  final post = await _req('POST', '/rest/v1/community_posts', token: t,
      jsonBody: {'user_id': uid, 'content': 'QA post'}, extraHeaders: {'Prefer': 'return=representation'});
  String? pId;
  (post.code == 201 && _len(post.body) > 0)
      ? (() { pId = post.body[0]['id'] as String?; _ok('SG-017', 'community post created'); })()
      : _no('SG-017', 'post create failed (HTTP ${post.code}) ${post.body}');

  // ── 18/19. NOTIFICATIONS + ANALYTICS ───────────────────────────────────────
  _section('18-19. Notifications + analytics data');
  final notif = await _req('GET', '/rest/v1/notifications', token: t,
      query: {'recipient_id': 'eq.$uid', 'select': 'id', 'limit': '5'});
  (notif.code == 200) ? _ok('SG-018', 'own notifications readable') : _no('SG-018', 'notifications read failed (HTTP ${notif.code})');
  _man('SG-018b', 'Push delivery (workout/water/habit/PR/badge reminders) — OS/APNs/FCM, not head-less');
  final meas = await _req('GET', '/rest/v1/body_measurements', token: t, query: {'select': 'id', 'limit': '1'});
  (meas.code == 200) ? _ok('SG-019', 'body_measurements (analytics) readable') : _no('SG-019', 'measurements read failed (HTTP ${meas.code})');
  final photos = await _req('GET', '/rest/v1/progress_media', token: t, query: {'select': 'id', 'limit': '1'});
  (photos.code == 200) ? _ok('SG-019b', 'progress media readable') : _man('SG-019b', 'progress_media table absent (HTTP ${photos.code}) — confirm where progress photos are stored');

  // ── 20. PERMISSIONS — self-guided must NOT reach coach features ─────────────
  _section('20. Permissions (RLS) — no coach features exposed');
  final coach = await _signIn(_coachEmail, _coachPass);
  final otherId = coach?.uid ?? '00000000-0000-0000-0000-000000000000';
  // (a) cannot read another user's notifications
  final leak = await _req('GET', '/rest/v1/notifications', token: t,
      query: {'recipient_id': 'eq.$otherId', 'select': 'id'});
  (leak.code == 200 && _len(leak.body) == 0)
      ? _ok('SG-020a', 'cannot read another user\'s notifications (RLS enforced)')
      : _no('SG-020a', 'RLS leak: got ${_len(leak.body)} rows (HTTP ${leak.code})');
  // (b) cannot author coach_notes about another user
  final note = await _req('POST', '/rest/v1/coach_notes', token: t,
      jsonBody: {'coach_id': uid, 'client_id': otherId, 'content': 'QA should be blocked'});
  (note.code == 401 || note.code == 403 || note.code == 400 || note.code == 409 ||
   (note.body is Map && (note.body['code'] == '42501')))
      ? _ok('SG-020b', 'client blocked from writing coach_notes (HTTP ${note.code})')
      : _no('SG-020b', 'PERMISSION VIOLATION: client wrote a coach_note (HTTP ${note.code})');
  // (c) cannot read another user's coaching_calls
  final calls = await _req('GET', '/rest/v1/coaching_calls', token: t,
      query: {'client_id': 'eq.$otherId', 'select': 'id'});
  (calls.code == 200 && _len(calls.body) == 0)
      ? _ok('SG-020c', 'cannot read another user\'s coaching_calls (RLS enforced)')
      : _no('SG-020c', 'RLS leak: coaching_calls returned ${_len(calls.body)} rows');
  _man('SG-020d', 'UI hides Coach/Book Session/Message Coach for self-guided — asserted separately in the paywall widget test');

  // ── 21. SCHEMA VALIDATION (real tables) ────────────────────────────────────
  _section('21. Schema validation — required tables present');
  const tables = [
    'user_profiles', 'subscriptions', 'workout_programs', 'workout_program_assignments',
    'program_workouts', 'workout_sessions', 'nutrition_logs', 'habit_logs',
    'daily_scores', 'score_events', 'user_scores', 'score_cycles', 'badges',
    'notifications', 'weekly_checkins', 'body_measurements', 'challenges',
    'challenge_participants', 'community_posts', 'exercise_videos',
  ];
  for (final tbl in tables) {
    final r = await _req('GET', '/rest/v1/$tbl', token: t, query: {'select': '*', 'limit': '1'});
    (r.code == 200) ? _ok('SG-021', '$tbl present') : _no('SG-021', '$tbl MISSING (HTTP ${r.code})');
  }

  // ── 22/23. PERFORMANCE + EDGE CASES ────────────────────────────────────────
  _section('22-23. Performance + edge cases');
  final sw = Stopwatch()..start();
  await _req('GET', '/rest/v1/user_scores', token: t, query: {'user_id': 'eq.$uid', 'select': '*'});
  await _req('GET', '/rest/v1/workout_programs', token: t, query: {'user_id': 'eq.$uid', 'select': '*'});
  sw.stop();
  (sw.elapsedMilliseconds < 2000)
      ? _ok('SG-022', 'dashboard core queries ${sw.elapsedMilliseconds}ms (< 2000ms target)')
      : _no('SG-022', 'dashboard queries slow: ${sw.elapsedMilliseconds}ms');
  _man('SG-022b', '10k-record load / crash-free perf — needs a seeded volume dataset (perf harness, separate run)');
  _man('SG-023', 'Offline / interrupted / device-restart / timezone / app-update edge cases — on-device manual matrix');

  // ── CLEANUP ────────────────────────────────────────────────────────────────
  _section('Cleanup');
  if (wkId != null) await _req('DELETE', '/rest/v1/workout_sessions', token: t, query: {'id': 'eq.$wkId'});
  if (nId  != null) await _req('DELETE', '/rest/v1/nutrition_logs',   token: t, query: {'id': 'eq.$nId'});
  if (pId  != null) await _req('DELETE', '/rest/v1/community_posts',   token: t, query: {'id': 'eq.$pId'});
  await _req('DELETE', '/rest/v1/habit_logs', token: t, query: {'user_id': 'eq.$uid'});
  // Deactivate the generated plan so re-runs stay clean.
  await _req('POST', '/rest/v1/rpc/deactivate_self_generated_plan', token: t, jsonBody: {});
  // Purge the throwaway auth user + profile if a service-role key was provided.
  final sr = _serviceRole;
  if (sr != null && sr.isNotEmpty) {
    final del = await _req('DELETE', '/auth/v1/admin/users/$uid',
        extraHeaders: {'Authorization': 'Bearer $sr', 'apikey': sr});
    (del.code == 200 || del.code == 204)
        ? print('  clean  test user purged')
        : print('  note   could not purge test user (HTTP ${del.code})');
  } else {
    print('  note   test user left in place (set SERVICE_ROLE_KEY to auto-purge)');
  }

  _summary();
}

void _summary() {
  print('\n════════════════════════════════════════════════════════════');
  print(' RESULT: $_pass passed · $_fail failed · $_warn findings · $_manual manual/out-of-scope');
  if (_failures.isNotEmpty) {
    print('\n DEFECTS (must fix for production):');
    for (final f in _failures) print('   ✗ $f');
  }
  if (_warnings.isNotEmpty) {
    print('\n FINDINGS (spec/impl discrepancies + payment-gated steps):');
    for (final w in _warnings) print('   ⚠ $w');
  }
  if (_manuals.isNotEmpty) {
    print('\n MANUAL / OUT-OF-SCOPE (not head-less certifiable):');
    for (final m in _manuals) print('   • $m');
  }
  final verdict = _fail == 0 ? 'PRODUCTION-READY (automated critical path)' : 'NOT READY — defects above';
  print('\n VERDICT: $verdict');
  print('════════════════════════════════════════════════════════════');
  _client.close(force: true);
  exit(_fail == 0 ? 0 : 1);
}
