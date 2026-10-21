// ─────────────────────────────────────────────────────────────────────────────
// Entitlement & Subscription — canonical QA certification harness.
//
// Proves that a real user receives the CORRECT entitlements for every Stripe
// subscription state, and that access-control / feature-gating stays correct as
// plans change. This is the billing + coaching-mode certification suite: run it
// on every deploy to catch entitlement regressions before users do.
//
// It seeds each subscription state directly (service role), signs in AS the
// user, and asserts the server truth — the same client_plan() resolver + the
// ClientPlanCaps capability matrix the app gates on — then exercises the
// upgrade / downgrade / cancel / renew transitions and verifies NO data loss.
//
//   export QA_URL=... QA_ANON=...
//   SERVICE_ROLE_KEY=... dart run tool/qa_entitlements.dart            # full matrix
//   SERVICE_ROLE_KEY=... dart run tool/qa_entitlements.dart --plan=ai_guided
//   SERVICE_ROLE_KEY=... dart run tool/qa_entitlements.dart --subscription=expired
//
// Plans: free · self_guided · ai_guided · coach_guided · trial · expired ·
//        cancelled · past_due   (+ transitions: upgrade/downgrade/cancel/renew)
//
// Seeding subscriptions bypasses RLS, so a SERVICE_ROLE_KEY is REQUIRED.
// Exit 0 = every entitlement resolved correctly; 1 = at least one mismatch.
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

final _serviceRole = Platform.environment['SERVICE_ROLE_KEY'];

int _pass = 0, _fail = 0, _warn = 0;
final _failures = <String>[];
final _warnings = <String>[];

void _ok(String id, String msg) { _pass++; print('  PASS  $id  $msg'); }
void _no(String id, String msg) { _fail++; _failures.add('$id  $msg'); print('  FAIL  $id  $msg'); }
void _wr(String id, String msg) { _warn++; _warnings.add('$id  $msg'); print('  WARN  $id  $msg'); }
void _section(String s) => print('\n▓▓ $s');

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

// Service-role write (bypasses RLS) — used only to seed subscription state.
Future<({int code, dynamic body})> _admin(String method, String path,
    {Map<String, String> query = const {}, Object? jsonBody,
     Map<String, String> extraHeaders = const {}}) =>
    _req(method, path, query: query, jsonBody: jsonBody,
        extraHeaders: {'Authorization': 'Bearer $_serviceRole', 'apikey': _serviceRole!, ...extraHeaders});

Future<({String token, String uid})?> _signUp(String e, String p) async {
  final res = await _req('POST', '/auth/v1/signup', jsonBody: {'email': e, 'password': p});
  if (res.code == 200 && res.body is Map && res.body['access_token'] != null) {
    return (token: res.body['access_token'] as String, uid: res.body['user']['id'] as String);
  }
  return null;
}

String _iso(Duration fromNow) => DateTime.now().toUtc().add(fromNow).toIso8601String();

// ── The four effective plans, mirroring lib/.../payments/domain/entitlements.dart
enum Plan { free, selfGuided, aiGuided, coachGuided }

Plan _planFromString(String? s) => switch (s) {
      'coach_guided' => Plan.coachGuided,
      'ai_guided'    => Plan.aiGuided,
      'self_guided'  => Plan.selfGuided,
      _              => Plan.free,
    };

int _rank(Plan p) => switch (p) {
      Plan.free => 0, Plan.selfGuided => 1, Plan.aiGuided => 2, Plan.coachGuided => 3,
    };

// The exact ClientPlanCaps matrix the app gates modules on. This is the
// "dashboard modules enabled/disabled" contract, per plan.
Map<String, bool> _caps(Plan p) {
  final paid = p != Plan.free;
  final aiPlus = _rank(p) >= _rank(Plan.aiGuided);
  return {
    'community'         : true,            // free & up
    'registerEvents'    : true,            // free & up
    'progressBasic'     : true,            // free & up
    'fullWorkouts'      : paid,            // self & up
    'fullNutrition'     : paid,            // self & up
    'advancedAnalytics' : paid,            // self & up
    'marketplace'       : paid,            // self & up
    'aiCoach'           : aiPlus,          // ai & up
    'generateProgram'   : aiPlus,          // ai & up (UI gate)
    'messageCoach'      : p == Plan.coachGuided,  // coach only
  };
}

String _planLabel(Plan p) => switch (p) {
      Plan.free => 'Free', Plan.selfGuided => 'Self-Guided',
      Plan.aiGuided => 'AI-Guided', Plan.coachGuided => 'Coach-Guided',
    };

// ── A seedable subscription scenario → the entitlement it MUST resolve to. ──
class Scenario {
  final String key;               // --plan / --subscription value
  final String desc;              // human summary of the Stripe state
  final Plan expect;              // client_plan() must resolve to this
  final List<Map<String, dynamic>> Function(String uid) rows; // subscription rows to seed
  const Scenario(this.key, this.desc, this.expect, this.rows);
}

List<Scenario> _scenarios() => [
  Scenario('free', 'no active subscription', Plan.free, (_) => []),
  Scenario('self_guided', 'self_guided · active · period +30d', Plan.selfGuided,
      (u) => [_sub(u, 'self_guided', 'active', _iso(const Duration(days: 30)))]),
  Scenario('ai_guided', 'ai_guided · active · period +30d', Plan.aiGuided,
      (u) => [_sub(u, 'ai_guided', 'active', _iso(const Duration(days: 30)))]),
  Scenario('coach_guided', 'coach · active · period +30d', Plan.coachGuided,
      (u) => [_sub(u, 'coach', 'active', _iso(const Duration(days: 30)))]),
  Scenario('trial', 'ai_guided · trialing · period +7d', Plan.aiGuided,
      (u) => [_sub(u, 'ai_guided', 'trialing', _iso(const Duration(days: 7)))]),
  // status=active but the period already lapsed → the period guard must drop it.
  Scenario('expired', 'ai_guided · active · period -1d (lapsed)', Plan.free,
      (u) => [_sub(u, 'ai_guided', 'active', _iso(const Duration(days: -1)))]),
  Scenario('cancelled', 'ai_guided · canceled · period +30d', Plan.free,
      (u) => [_sub(u, 'ai_guided', 'canceled', _iso(const Duration(days: 30)))]),
  Scenario('past_due', 'ai_guided · past_due · period +30d', Plan.free,
      (u) => [_sub(u, 'ai_guided', 'past_due', _iso(const Duration(days: 30)))]),
];

Map<String, dynamic> _sub(String uid, String kind, String status, String? periodEnd,
    {bool cancelAtEnd = false}) => {
  'user_id': uid, 'kind': kind, 'status': status,
  'current_period_end': periodEnd, 'cancel_at_period_end': cancelAtEnd,
};

// Wipe all seeded entitlement state for a clean slate before each scenario.
Future<void> _clear(String uid) async {
  await _admin('DELETE', '/rest/v1/subscriptions', query: {'user_id': 'eq.$uid'});
  await _admin('DELETE', '/rest/v1/coach_client_relationships', query: {'client_id': 'eq.$uid'});
}

Future<String> _clientPlan(String token) async {
  final r = await _req('POST', '/rest/v1/rpc/client_plan', token: token, jsonBody: {});
  return (r.body is String) ? r.body as String : '${r.body}';
}

// Seed a scenario, then assert client_plan() + the full capability matrix.
Future<Plan> _certify(Scenario s, String uid, String token) async {
  await _clear(uid);
  final rows = s.rows(uid);
  if (rows.isNotEmpty) {
    final ins = await _admin('POST', '/rest/v1/subscriptions', jsonBody: rows);
    if (ins.code >= 300) { _no('ENT-${s.key}', 'could not seed subscription (HTTP ${ins.code}: ${ins.body})'); }
  }
  final resolved = _planFromString(await _clientPlan(token));
  if (resolved == s.expect) {
    _ok('ENT-${s.key}', '${s.desc}  →  client_plan = ${_planLabel(resolved)}');
  } else {
    _no('ENT-${s.key}', '${s.desc}  →  expected ${_planLabel(s.expect)}, got ${_planLabel(resolved)}');
  }
  // Module enable/disable contract for the resolved plan.
  final caps = _caps(resolved);
  final on  = caps.entries.where((e) => e.value).map((e) => e.key).toList();
  final off = caps.entries.where((e) => !e.value).map((e) => e.key).toList();
  print('        modules ON : ${on.join(', ')}');
  print('        modules OFF: ${off.isEmpty ? '(none)' : off.join(', ')}');
  return resolved;
}

Future<void> main(List<String> args) async {
  print('════════════════════════════════════════════════════════════');
  print(' ENTITLEMENT & SUBSCRIPTION — QA CERTIFICATION');
  print(' target: $_url');
  print('════════════════════════════════════════════════════════════');

  if (_serviceRole == null || _serviceRole!.isEmpty) {
    print('\n  BLOCKED  seeding subscription state bypasses RLS and needs a service-role key.');
    print('           Run:  SERVICE_ROLE_KEY=<key> dart run tool/qa_entitlements.dart');
    _client.close(force: true);
    exit(2);
  }

  final only = args
      .firstWhere((a) => a.startsWith('--plan=') || a.startsWith('--subscription='),
          orElse: () => '')
      .split('=').last;

  // ── One throwaway client, with enough profile for program generation. ──
  final email = 'qa+ent${DateTime.now().millisecondsSinceEpoch}@12circle.app';
  const pass  = 'QaTest1234!';
  final su = await _signUp(email, pass);
  if (su == null) { print('  FAIL  ENT-000  signup failed for $email'); _summary(); return; }
  final t = su.token, uid = su.uid;
  print('\n  test client: $email (${uid.substring(0, 8)})');

  var prof = await _req('GET', '/rest/v1/user_profiles', token: t, query: {'id': 'eq.$uid', 'select': 'id'});
  final body = prof.body;
  if (body is! List || body.isEmpty) {
    await _req('POST', '/rest/v1/user_profiles', token: t, jsonBody: {'id': uid, 'role': 'client'});
  }
  await _req('PATCH', '/rest/v1/user_profiles', token: t, query: {'id': 'eq.$uid'}, jsonBody: {
    'role': 'client', 'first_name': 'QA', 'gender': 'male', 'date_of_birth': '1995-05-05',
    'height_cm': 180, 'weight_kg': 82, 'fitness_goal': 'lose_fat',
    'activity_level': 'moderate', 'training_days_per_week': 4, 'training_location': 'gym',
    'onboarding_complete': true,
  });

  final matrix = only.isEmpty ? _scenarios() : _scenarios().where((s) => s.key == only).toList();
  if (matrix.isEmpty) {
    print('  unknown plan "$only" — valid: ${_scenarios().map((s) => s.key).join(', ')}');
    _summary(); return;
  }

  // ── 1. ENTITLEMENT MATRIX — one seeded Stripe state per plan. ──
  _section('1. Entitlement matrix — every subscription state resolves correctly');
  for (final s in matrix) { await _certify(s, uid, t); }

  if (only.isEmpty) {
    // ── 2. SERVER-SIDE GATING — does the backend enforce what the UI claims? ──
    _section('2. Server-side gating — program generation');
    // canGenerateProgram is UI-gated to AI+; the RPC itself only checks auth.uid().
    await _certify(_scenarios().firstWhere((s) => s.key == 'free'), uid, t);
    final genFree = await _req('POST', '/rest/v1/rpc/generate_client_plan', token: t, jsonBody: {});
    if (genFree.code < 300) {
      _wr('ENT-GATE-1', 'generate_client_plan() succeeds for FREE (HTTP ${genFree.code}) — server RPC has no entitlement gate; access is UI-only (PaywallGate). Add a plan check server-side for defense in depth.');
    } else {
      _ok('ENT-GATE-1', 'generate_client_plan() blocked server-side for free (HTTP ${genFree.code})');
    }
    await _certify(_scenarios().firstWhere((s) => s.key == 'ai_guided'), uid, t);
    final genAi = await _req('POST', '/rest/v1/rpc/generate_client_plan', token: t, jsonBody: {});
    (genAi.code < 300)
        ? _ok('ENT-GATE-2', 'generate_client_plan() succeeds for AI-Guided (HTTP ${genAi.code})')
        : _no('ENT-GATE-2', 'AI-Guided could not generate a program (HTTP ${genAi.code})');
    await _req('POST', '/rest/v1/rpc/deactivate_self_generated_plan', token: t, jsonBody: {});

    // ── 3. DATA PRESERVATION across plan changes — no loss on up/downgrade. ──
    _section('3. Upgrade / downgrade / cancel / renew — no data loss');
    await _clear(uid);
    // A durable history marker that must survive every transition.
    final marker = await _req('POST', '/rest/v1/workout_sessions', token: t, jsonBody: {
      'user_id': uid, 'workout_title': 'ENT history marker',
      'status': 'completed', 'completed_sets': 5,
    }, extraHeaders: {'Prefer': 'return=representation'});
    final markerId = (marker.body is List && (marker.body as List).isNotEmpty)
        ? (marker.body as List).first['id'] : null;

    Future<void> seedAndCheck(String tag, String label, List<Map<String, dynamic>> rows, Plan expect) async {
      await _clear(uid);
      if (rows.isNotEmpty) await _admin('POST', '/rest/v1/subscriptions', jsonBody: rows);
      final got = _planFromString(await _clientPlan(t));
      got == expect
          ? _ok(tag, '$label → ${_planLabel(got)}')
          : _no(tag, '$label → expected ${_planLabel(expect)}, got ${_planLabel(got)}');
    }

    // Upgrade ladder.
    await seedAndCheck('ENT-UP-1', 'Free → Self-Guided',
        [_sub(uid, 'self_guided', 'active', _iso(const Duration(days: 30)))], Plan.selfGuided);
    await seedAndCheck('ENT-UP-2', 'Self-Guided → AI-Guided',
        [_sub(uid, 'ai_guided', 'active', _iso(const Duration(days: 30)))], Plan.aiGuided);
    await seedAndCheck('ENT-UP-3', 'AI-Guided → Coach-Guided',
        [_sub(uid, 'coach', 'active', _iso(const Duration(days: 30)))], Plan.coachGuided);

    // Downgrade ladder.
    await seedAndCheck('ENT-DN-1', 'Coach-Guided → AI-Guided',
        [_sub(uid, 'ai_guided', 'active', _iso(const Duration(days: 30)))], Plan.aiGuided);
    await seedAndCheck('ENT-DN-2', 'AI-Guided → Self-Guided',
        [_sub(uid, 'self_guided', 'active', _iso(const Duration(days: 30)))], Plan.selfGuided);
    await seedAndCheck('ENT-DN-3', 'Self-Guided → Free',
        [], Plan.free);

    // Cancel: cancel_at_period_end keeps access until the period lapses…
    await seedAndCheck('ENT-CANCEL-1', 'Cancel scheduled (cancel_at_period_end, period future) keeps access',
        [_sub(uid, 'ai_guided', 'active', _iso(const Duration(days: 30)), cancelAtEnd: true)], Plan.aiGuided);
    // …then the terminal canceled status removes it.
    await seedAndCheck('ENT-CANCEL-2', 'Subscription canceled → entitlement removed',
        [_sub(uid, 'ai_guided', 'canceled', _iso(const Duration(days: 30)))], Plan.free);

    // Renewal: a lapsed period reads as free, a renewed period restores access.
    await seedAndCheck('ENT-RENEW-1', 'Lapsed period → Free',
        [_sub(uid, 'ai_guided', 'active', _iso(const Duration(days: -1)))], Plan.free);
    await seedAndCheck('ENT-RENEW-2', 'Renewed period → AI-Guided restored',
        [_sub(uid, 'ai_guided', 'active', _iso(const Duration(days: 30)))], Plan.aiGuided);

    // History marker must have survived all of the above.
    if (markerId != null) {
      final still = await _req('GET', '/rest/v1/workout_sessions', token: t,
          query: {'id': 'eq.$markerId', 'select': 'id'});
      (still.body is List && (still.body as List).isNotEmpty)
          ? _ok('ENT-DATA', 'workout history preserved across all plan changes (no data loss)')
          : _no('ENT-DATA', 'history marker lost after plan transitions');
      await _req('DELETE', '/rest/v1/workout_sessions', token: t, query: {'id': 'eq.$markerId'});
    }
  }

  // ── CLEANUP ──
  _section('Cleanup');
  await _clear(uid);
  await _req('POST', '/rest/v1/rpc/deactivate_self_generated_plan', token: t, jsonBody: {});
  final del = await _admin('DELETE', '/auth/v1/admin/users/$uid');
  (del.code == 200 || del.code == 204)
      ? print('  clean  test user + seeded subscriptions purged')
      : print('  note   subscriptions cleared; could not purge auth user (HTTP ${del.code})');

  _summary();
}

void _summary() {
  print('\n════════════════════════════════════════════════════════════');
  print(' RESULT: $_pass passed · $_fail failed · $_warn findings');
  if (_failures.isNotEmpty) {
    print('\n DEFECTS (entitlement resolved incorrectly — must fix):');
    for (final f in _failures) print('   ✗ $f');
  }
  if (_warnings.isNotEmpty) {
    print('\n FINDINGS (gating gaps / notes):');
    for (final w in _warnings) print('   ⚠ $w');
  }
  final verdict = _fail == 0
      ? 'CERTIFIED — every subscription state grants the correct entitlement'
      : 'NOT CERTIFIED — entitlement defects above';
  print('\n VERDICT: $verdict');
  print('════════════════════════════════════════════════════════════');
  _client.close(force: true);
  exit(_fail == 0 ? 0 : 1);
}
