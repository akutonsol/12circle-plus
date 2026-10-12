// 12 Circle Fitness — Live integration smoke test
// Runs against the 12 Circle QA project as the seeded test accounts. The
// target comes from QA_URL / QA_ANON and is verified before anything runs --
// see tool/qa_target.dart. It used to be a hardcoded production constant.
// Validates schema presence, RLS, and CRUD round-trips for the built modules
// (Modules 1–14). Maps each check to a QA spec ID.
//
//   export QA_URL=... QA_ANON=...
//   dart run tool/live_integration_test.dart
//
// NOTE: service-layer logic (12 Circle Score awarding, in-app notifications)
// executes inside the Flutter app, not in the DB, so it is covered by the unit
// suite — this script verifies the data layer those services write to.

import 'dart:convert';
import 'dart:io';

import 'qa_target.dart';

// ENV-5: the target is resolved from QA_URL / QA_ANON and positively verified
// as the QA project before a single request goes out. There is no default --
// this file used to hardcode the PRODUCTION ref and key right here.
final QaTarget _target = resolveQaTarget();
String get _url => _target.url;
String get _anon => _target.anonKey;

const _clientEmail = 'test@12circle.app';
const _clientPass = 'Test1234!';
const _coachEmail = 'coach@12circle.app';
const _coachPass = 'Coach1234!';

int _pass = 0, _fail = 0;
final _failures = <String>[];

void _ok(String id, String msg) {
  _pass++;
  print('  PASS  $id  $msg');
}

void _no(String id, String msg) {
  _fail++;
  _failures.add('$id  $msg');
  print('  FAIL  $id  $msg');
}

final _client = HttpClient();

Future<({int code, dynamic body})> _req(
  String method,
  String path, {
  String? token,
  Map<String, String> query = const {},
  Object? jsonBody,
  Map<String, String> extraHeaders = const {},
}) async {
  final uri = Uri.parse('$_url$path').replace(queryParameters: {
    if (query.isNotEmpty) ...query,
  });
  final r = await _client.openUrl(method, uri);
  r.headers.set('apikey', _anon);
  r.headers.set('Authorization', 'Bearer ${token ?? _anon}');
  r.headers.set('Content-Type', 'application/json');
  extraHeaders.forEach(r.headers.set);
  if (jsonBody != null) r.write(jsonEncode(jsonBody));
  final resp = await r.close();
  final text = await resp.transform(utf8.decoder).join();
  dynamic parsed;
  try {
    parsed = text.isEmpty ? null : jsonDecode(text);
  } catch (_) {
    parsed = text;
  }
  return (code: resp.statusCode, body: parsed);
}

Future<({String token, String uid})?> _signIn(String email, String pass) async {
  final res = await _req('POST', '/auth/v1/token',
      query: {'grant_type': 'password'},
      jsonBody: {'email': email, 'password': pass});
  if (res.code == 200 && res.body is Map && res.body['access_token'] != null) {
    return (
      token: res.body['access_token'] as String,
      uid: res.body['user']['id'] as String,
    );
  }
  return null;
}

Future<void> main() async {
  print('\n=== 12 Circle Fitness — Live Integration Test ===\n');

  // ── AUTH ────────────────────────────────────────────────────────────────
  print('AUTH');
  final client = await _signIn(_clientEmail, _clientPass);
  client == null
      ? _no('AUTH-001', 'client sign-in failed')
      : _ok('AUTH-001', 'client signed in (${client.uid.substring(0, 8)})');
  final coach = await _signIn(_coachEmail, _coachPass);
  coach == null
      ? _no('AUTH-002', 'coach sign-in failed')
      : _ok('AUTH-002', 'coach signed in (${coach.uid.substring(0, 8)})');
  if (client == null) {
    print('\nCannot continue without client session.');
    _summary();
    return;
  }
  final t = client.token;
  final uid = client.uid;

  // ── SCHEMA (the 5 objects the audit flagged) ────────────────────────────
  print('\nSCHEMA  (expected PASS only after APPLY_MISSING.sql is run)');
  for (final tbl in [
    'custom_exercises',
    'coach_client_workout_stats',
    'user_integrations',
    'community_groups',
    'community_group_members',
    'action_items',
    'goals',
    'coach_notes',
  ]) {
    final r = await _req('GET', '/rest/v1/$tbl',
        token: t, query: {'limit': '1'});
    r.code == 200
        ? _ok('SCHEMA', '$tbl present')
        : _no('SCHEMA', '$tbl MISSING (HTTP ${r.code}) — run APPLY_MISSING.sql');
  }

  // ── Module 1/2: profile self-read (RLS) ─────────────────────────────────
  print('\nPROFILE / DASHBOARD');
  final prof = await _req('GET', '/rest/v1/user_profiles',
      token: t, query: {'id': 'eq.$uid', 'select': '*'});
  (prof.code == 200 && prof.body is List && (prof.body as List).isNotEmpty)
      ? _ok('ONB/RLS', 'own profile readable')
      : _no('ONB/RLS', 'own profile not readable (HTTP ${prof.code})');

  // ── Module 3: Workout session create → complete → cleanup ───────────────
  print('\nWORKOUT (Module 3)');
  final wk = await _req('POST', '/rest/v1/workout_sessions',
      token: t,
      extraHeaders: {'Prefer': 'return=representation'},
      jsonBody: {
        'user_id': uid,
        'workout_title': '__itest workout',
        'status': 'in_progress',
        'elapsed_seconds': 42,
      });
  String? wkId;
  if (wk.code >= 200 && wk.code < 300 && wk.body is List && (wk.body as List).isNotEmpty) {
    wkId = (wk.body as List).first['id'] as String?;
    _ok('WKT-001', 'session created (in_progress, elapsed=42)');
    final upd = await _req('PATCH', '/rest/v1/workout_sessions',
        token: t,
        query: {'id': 'eq.$wkId'},
        jsonBody: {'status': 'completed', 'completed_at': DateTime.now().toUtc().toIso8601String()});
    (upd.code >= 200 && upd.code < 300)
        ? _ok('WKT-002', 'session marked completed (workout-complete trigger OK)')
        : _no('WKT-002', 'complete failed (HTTP ${upd.code}) ${upd.body}');
    await _req('DELETE', '/rest/v1/workout_sessions', token: t, query: {'id': 'eq.$wkId'});
  } else {
    _no('WKT-001', 'session create failed (HTTP ${wk.code}) ${wk.body}');
  }

  // ── Module 5: Nutrition log create → read → cleanup ─────────────────────
  print('\nNUTRITION (Module 5)');
  final nut = await _req('POST', '/rest/v1/nutrition_logs',
      token: t,
      extraHeaders: {'Prefer': 'return=representation'},
      jsonBody: {
        'user_id': uid,
        'meal_type': 'breakfast',
        'food_name': '__itest oats',
        'calories': 300, 'protein': 12, 'carbs': 50, 'fat': 6,
        'amount_g': 80, 'serving_unit': 'g',
        'logged_at': DateTime.now().toUtc().toIso8601String(),
      });
  if (nut.code >= 200 && nut.code < 300 && nut.body is List && (nut.body as List).isNotEmpty) {
    final nId = (nut.body as List).first['id'];
    _ok('NUT-001', 'meal logged + macros stored');
    await _req('DELETE', '/rest/v1/nutrition_logs', token: t, query: {'id': 'eq.$nId'});
  } else {
    _no('NUT-001', 'meal log failed (HTTP ${nut.code}) ${nut.body}');
  }

  // ── 12 Circle Score table writable (SCR plumbing) ───────────────────────
  print('\n12 CIRCLE SCORE');
  final today = DateTime.now().toUtc().toIso8601String().split('T')[0];
  final sc = await _req('POST', '/rest/v1/daily_scores',
      token: t,
      query: {'on_conflict': 'user_id,score_date'},
      extraHeaders: {'Prefer': 'resolution=merge-duplicates,return=representation'},
      jsonBody: {
        'user_id': uid, 'score_date': today,
        'workout_points': 0, 'nutrition_points': 0, 'habits_points': 0,
        'checkin_points': 0, 'community_points': 0, 'total_score': 0,
      });
  (sc.code >= 200 && sc.code < 300)
      ? _ok('SCR', 'daily_scores upsert OK (score plumbing live)')
      : _no('SCR', 'daily_scores upsert failed (HTTP ${sc.code}) ${sc.body}');

  // ── Module 9: Weekly check-in upsert ────────────────────────────────────
  print('\nCHECK-INS (Module 9)');
  final monday = DateTime.now().toUtc();
  final weekStart = monday.subtract(Duration(days: monday.weekday - 1));
  final jan1 = DateTime(monday.year, 1, 1);
  final weekNumber = ((monday.difference(jan1).inDays + jan1.weekday - 1) / 7).floor() + 1;
  final ck = await _req('POST', '/rest/v1/weekly_checkins',
      token: t,
      query: {'on_conflict': 'user_id,week_start_date'},
      extraHeaders: {'Prefer': 'resolution=merge-duplicates,return=representation'},
      jsonBody: {
        'user_id': uid,
        'week_number': weekNumber,
        'week_start_date': weekStart.toIso8601String().split('T')[0],
        'status': 'submitted', 'mood': 4, 'energy': 4, 'stress_level': 2,
        'sleep_hours_avg': 7.5, 'notes': '__itest', 'overall_score': 8.0,
        'submitted_at': DateTime.now().toUtc().toIso8601String(),
      });
  (ck.code >= 200 && ck.code < 300)
      ? _ok('CHK-001', 'weekly check-in saved')
      : _no('CHK-001', 'check-in save failed (HTTP ${ck.code}) ${ck.body}');

  // ── Module 10: Messaging read ───────────────────────────────────────────
  print('\nMESSAGING (Module 10)');
  final conv = await _req('GET', '/rest/v1/conversations', token: t, query: {
    'or': '(participant_1.eq.$uid,participant_2.eq.$uid)', 'select': 'id,last_message', 'limit': '5',
  });
  conv.code == 200
      ? _ok('MSG-004', 'conversations readable (${(conv.body as List).length})')
      : _no('MSG-004', 'conversation read failed (HTTP ${conv.code})');

  // ── Module 11: Community post + comment + cleanup ───────────────────────
  print('\nCOMMUNITY (Module 11)');
  final post = await _req('POST', '/rest/v1/community_posts',
      token: t,
      extraHeaders: {'Prefer': 'return=representation'},
      jsonBody: {'user_id': uid, 'content': '__itest post', 'post_type': 'general'});
  if (post.code >= 200 && post.code < 300 && post.body is List && (post.body as List).isNotEmpty) {
    final pId = (post.body as List).first['id'];
    _ok('COM-001', 'post created');
    final cm = await _req('POST', '/rest/v1/post_comments',
        token: t, jsonBody: {'post_id': pId, 'user_id': uid, 'content': '__itest comment'});
    (cm.code >= 200 && cm.code < 300)
        ? _ok('COM-002', 'comment created')
        : _no('COM-002', 'comment failed (HTTP ${cm.code}) ${cm.body}');
    await _req('DELETE', '/rest/v1/community_posts', token: t, query: {'id': 'eq.$pId'});
  } else {
    _no('COM-001', 'post create failed (HTTP ${post.code}) ${post.body}');
  }

  // ── Module 12: Challenges read + join + cleanup ─────────────────────────
  print('\nCHALLENGES (Module 12)');
  final chs = await _req('GET', '/rest/v1/challenges', token: t, query: {'select': 'id,title', 'limit': '1'});
  if (chs.code == 200 && chs.body is List && (chs.body as List).isNotEmpty) {
    final cId = (chs.body as List).first['id'];
    _ok('CHL-list', 'challenges readable');
    final join = await _req('POST', '/rest/v1/challenge_participants',
        token: t,
        extraHeaders: {'Prefer': 'resolution=merge-duplicates'},
        jsonBody: {'challenge_id': cId, 'user_id': uid, 'current_progress': 0});
    (join.code >= 200 && join.code < 300)
        ? _ok('CHL-001', 'joined challenge')
        : _no('CHL-001', 'join failed (HTTP ${join.code}) ${join.body}');
    await _req('DELETE', '/rest/v1/challenge_participants',
        token: t, query: {'challenge_id': 'eq.$cId', 'user_id': 'eq.$uid'});
  } else {
    _no('CHL-list', 'no challenges seeded / read failed (HTTP ${chs.code})');
  }

  // ── Module 13: Classes / coach availability read ────────────────────────
  print('\nCALENDAR / CLASSES (Module 13)');
  final avail = await _req('GET', '/rest/v1/coach_availability', token: t, query: {'select': 'id', 'limit': '1'});
  avail.code == 200
      ? _ok('CAL-001', 'coach availability readable')
      : _no('CAL-001', 'availability read failed (HTTP ${avail.code})');
  final cls = await _req('GET', '/rest/v1/classes', token: t, query: {'select': 'id,max_capacity', 'limit': '1'});
  if (cls.code == 200 && cls.body is List && (cls.body as List).isNotEmpty) {
    final clsId = (cls.body as List).first['id'];
    _ok('CLASS', 'classes readable');
    // Exercises trg_notify_on_class_booking (was reading classes.starts_at).
    await _req('DELETE', '/rest/v1/class_bookings',
        token: t, query: {'class_id': 'eq.$clsId', 'user_id': 'eq.$uid'});
    final bk = await _req('POST', '/rest/v1/class_bookings',
        token: t, jsonBody: {'class_id': clsId, 'user_id': uid, 'status': 'confirmed'});
    (bk.code >= 200 && bk.code < 300)
        ? _ok('CAL-book', 'class booked (class-booking trigger OK)')
        : _no('CAL-book', 'class booking failed (HTTP ${bk.code}) ${bk.body}');
    await _req('DELETE', '/rest/v1/class_bookings',
        token: t, query: {'class_id': 'eq.$clsId', 'user_id': 'eq.$uid'});
  } else {
    _no('CLASS', 'classes read failed (HTTP ${cls.code})');
  }

  // ── Module 14: Events register + QR ticket + cleanup ────────────────────
  print('\nEVENTS (Module 14)');
  final evs = await _req('GET', '/rest/v1/events', token: t, query: {'select': 'id,title', 'limit': '1'});
  if (evs.code == 200 && evs.body is List && (evs.body as List).isNotEmpty) {
    final eId = (evs.body as List).first['id'];
    final code = '12C-${DateTime.now().millisecondsSinceEpoch}';
    // Clear any pre-existing registration (seed data) so the test is clean.
    await _req('DELETE', '/rest/v1/event_registrations',
        token: t, query: {'event_id': 'eq.$eId', 'user_id': 'eq.$uid'});
    final reg = await _req('POST', '/rest/v1/event_registrations',
        token: t,
        extraHeaders: {'Prefer': 'return=representation'},
        jsonBody: {'event_id': eId, 'user_id': uid, 'ticket_code': code});
    if (reg.code >= 200 && reg.code < 300) {
      _ok('EVT-001', 'event registered + ticket_code generated');
      await _req('DELETE', '/rest/v1/event_registrations',
          token: t, query: {'event_id': 'eq.$eId', 'user_id': 'eq.$uid'});
    } else {
      _no('EVT-001', 'registration failed (HTTP ${reg.code}) ${reg.body}');
    }
  } else {
    _no('EVT-list', 'no events seeded / read failed (HTTP ${evs.code})');
  }

  // ── Action Items: client self-insert → complete → cleanup ──────────────
  print('\nACTION ITEMS (coach OS)');
  final ai = await _req('POST', '/rest/v1/action_items',
      token: t,
      extraHeaders: {'Prefer': 'return=representation'},
      jsonBody: {
        'client_id': uid,
        'title': '__itest task',
        'category': 'daily',
        'created_by': 'system',
        'status': 'pending',
        'points': 10,
      });
  if (ai.code >= 200 && ai.code < 300 && ai.body is List && (ai.body as List).isNotEmpty) {
    final aId = (ai.body as List).first['id'];
    _ok('ACT-001', 'action item created');
    final done = await _req('PATCH', '/rest/v1/action_items',
        token: t,
        query: {'id': 'eq.$aId'},
        jsonBody: {'status': 'completed', 'completed_at': DateTime.now().toUtc().toIso8601String()});
    (done.code >= 200 && done.code < 300)
        ? _ok('ACT-002', 'action item completed')
        : _no('ACT-002', 'complete failed (HTTP ${done.code}) ${done.body}');
    await _req('DELETE', '/rest/v1/action_items', token: t, query: {'id': 'eq.$aId'});
  } else {
    _no('ACT-001', 'create failed (HTTP ${ai.code}) ${ai.body}');
  }

  // ── Goals (Module 34): create → update → complete → cleanup ────────────
  print('\nGOALS (Module 34)');
  final g = await _req('POST', '/rest/v1/goals',
      token: t,
      extraHeaders: {'Prefer': 'return=representation'},
      jsonBody: {
        'client_id': uid, 'title': '__itest goal', 'type': 'weight_loss',
        'start_value': 82, 'current_value': 82, 'target_value': 77, 'unit': 'kg',
        'status': 'active',
      });
  if (g.code >= 200 && g.code < 300 && g.body is List && (g.body as List).isNotEmpty) {
    final gId = (g.body as List).first['id'];
    _ok('GOAL-001', 'goal created');
    final up = await _req('PATCH', '/rest/v1/goals',
        token: t, query: {'id': 'eq.$gId'}, jsonBody: {'current_value': 79.5});
    (up.code >= 200 && up.code < 300)
        ? _ok('GOAL-002', 'goal progress updated')
        : _no('GOAL-002', 'update failed (HTTP ${up.code}) ${up.body}');
    await _req('DELETE', '/rest/v1/goals', token: t, query: {'id': 'eq.$gId'});
  } else {
    _no('GOAL-001', 'create failed (HTTP ${g.code}) ${g.body}');
  }

  // ── Coach Notes (Module 29): coach writes a private note; client CANNOT read it
  print('\nCOACH NOTES (Module 29)');
  if (coach != null) {
    final note = await _req('POST', '/rest/v1/coach_notes',
        token: coach.token,
        extraHeaders: {'Prefer': 'return=representation'},
        jsonBody: {
          'coach_id': coach.uid, 'client_id': uid,
          'body': '__itest private note', 'tag': 'general',
        });
    if (note.code >= 200 && note.code < 300 && note.body is List && (note.body as List).isNotEmpty) {
      final nId = (note.body as List).first['id'];
      _ok('NOTE-001', 'coach created private note');
      // Privacy: the client must NOT be able to read notes about themselves.
      final leak = await _req('GET', '/rest/v1/coach_notes',
          token: t, query: {'client_id': 'eq.$uid', 'select': 'id'});
      (leak.code == 200 && leak.body is List && (leak.body as List).isEmpty)
          ? _ok('NOTE-SEC', 'client cannot read coach notes about themselves (RLS)')
          : _no('NOTE-SEC', 'PRIVACY LEAK: client read ${leak.body is List ? (leak.body as List).length : '?'} notes');
      await _req('DELETE', '/rest/v1/coach_notes', token: coach.token, query: {'id': 'eq.$nId'});
    } else {
      _no('NOTE-001', 'coach note create failed (HTTP ${note.code}) ${note.body}');
    }
  }

  // ── Program Builder (Module 31): coach creates a program, adds a workout, reads it
  print('\nPROGRAM BUILDER (Module 31)');
  if (coach != null) {
    final prog = await _req('POST', '/rest/v1/workout_programs',
        token: coach.token,
        extraHeaders: {'Prefer': 'return=representation'},
        jsonBody: {
          'coach_id': coach.uid,
          'name': '__itest program',
          'goal': 'test',
          'difficulty': 'intermediate',
          'duration_weeks': 4,
        });
    if (prog.code >= 200 && prog.code < 300 && prog.body is List && (prog.body as List).isNotEmpty) {
      final pid = (prog.body as List).first['id'];
      _ok('PRG-001', 'coach created program');
      // PRG-002: add a workout with a jsonb exercises array.
      final wkt = await _req('POST', '/rest/v1/program_workouts',
          token: coach.token,
          extraHeaders: {'Prefer': 'return=representation'},
          jsonBody: {
            'program_id': pid,
            'week_number': 1,
            'day_of_week': 'Monday',
            'title': 'Upper Push',
            'estimated_minutes': 45,
            // Canonical prescription contract — see
            // docs/WORKOUT_DOMAIN_CONTRACT.md §3. This probe used to write
            // `reps` as a String and `rest` instead of `rest_seconds`, i.e. it
            // asserted the round trip using a shape the client cannot read.
            'exercises': [
              {
                'exercise_instance_id': 'probe-bench-press',
                'name': 'Bench Press',
                'position': 0,
                'sets': 3,
                'reps': 10,
                'weight_kg': null,
                'rest_seconds': 60,
              }
            ],
            'sort_order': 0,
          });
      final wktOk = wkt.code >= 200 && wkt.code < 300;
      // PRG-003: read it back and confirm the exercises round-tripped.
      final read = await _req('GET', '/rest/v1/program_workouts',
          token: coach.token,
          query: {'program_id': 'eq.$pid', 'select': 'title,exercises'});
      final readOk = read.code == 200 &&
          read.body is List &&
          (read.body as List).isNotEmpty &&
          ((read.body as List).first['exercises'] as List?)?.isNotEmpty == true;
      wktOk
          ? _ok('PRG-002', 'workout added to program')
          : _no('PRG-002', 'add workout failed (HTTP ${wkt.code}) ${wkt.body}');
      readOk
          ? _ok('PRG-003', 'program workouts + exercises round-trip readable')
          : _no('PRG-003', 'workout read-back failed (HTTP ${read.code})');
      // Cleanup (workouts cascade on program delete).
      await _req('DELETE', '/rest/v1/workout_programs',
          token: coach.token, query: {'id': 'eq.$pid'});
    } else {
      _no('PRG-001', 'program create failed (HTTP ${prog.code}) ${prog.body}');
    }
  }

  // ── Compliance Dashboard (Module 30): coach aggregates active-client adherence
  print('\nCOMPLIANCE DASHBOARD (Module 30)');
  if (coach != null) {
    // CMP-001: coach can read their active roster.
    final roster = await _req('GET', '/rest/v1/coach_client_relationships',
        token: coach.token,
        query: {
          'coach_id': 'eq.${coach.uid}',
          'status': 'eq.active',
          'select': 'client_id'
        });
    if (roster.code == 200 && roster.body is List) {
      _ok('CMP-001', 'coach roster readable (${(roster.body as List).length} active)');
      // CMP-002: every aggregation source the dashboard reads is reachable as coach.
      final sources = {
        'daily_scores': 'user_id',
        'workout_logs': 'user_id',
        'weekly_checkins': 'user_id',
        'action_items': 'client_id',
        'goals': 'client_id',
      };
      var allOk = true;
      String? bad;
      for (final entry in sources.entries) {
        final r = await _req('GET', '/rest/v1/${entry.key}',
            token: coach.token, query: {'select': entry.value, 'limit': '1'});
        if (r.code != 200) {
          allOk = false;
          bad = '${entry.key} (HTTP ${r.code})';
          break;
        }
      }
      allOk
          ? _ok('CMP-002', 'all 5 compliance aggregation sources readable by coach')
          : _no('CMP-002', 'compliance source unreadable: $bad');
    } else {
      _no('CMP-001', 'coach roster read failed (HTTP ${roster.code})');
    }
  }

  // ── Vendor Portal (Module 15): role-gated event ownership RLS
  print('\nVENDOR PORTAL (Module 15)');
  // VND-READ: events carry a vendor_id column now and remain publicly readable.
  final evRead = await _req('GET', '/rest/v1/events',
      token: t, query: {'select': 'id,vendor_id', 'limit': '1'});
  (evRead.code == 200 && evRead.body is List)
      ? _ok('VND-READ', 'events readable with vendor_id column')
      : _no('VND-READ', 'events read failed (HTTP ${evRead.code}) — run migration 020');
  // VND-SEC: a client (non-vendor) must NOT be able to create an event, even
  // setting vendor_id to themselves — the role check in the policy blocks it.
  final evCreate = await _req('POST', '/rest/v1/events',
      token: t,
      extraHeaders: {'Prefer': 'return=representation'},
      jsonBody: {
        'title': '__itest illegal event',
        'event_date': DateTime.now().toIso8601String(),
        'vendor_id': uid,
      });
  if (evCreate.code == 401 || evCreate.code == 403) {
    _ok('VND-SEC', 'non-vendor blocked from creating events (RLS role-gated)');
  } else if (evCreate.code >= 200 && evCreate.code < 300) {
    // Clean up the leak so the table isn't polluted, then fail loudly.
    final created = (evCreate.body is List && (evCreate.body as List).isNotEmpty)
        ? (evCreate.body as List).first['id'] : null;
    if (created != null) {
      await _req('DELETE', '/rest/v1/events', token: t, query: {'id': 'eq.$created'});
    }
    _no('VND-SEC', 'SECURITY HOLE: a client created an event (HTTP ${evCreate.code})');
  } else {
    _no('VND-SEC', 'unexpected HTTP ${evCreate.code} ${evCreate.body}');
  }

  // ── Event Sessions / Agenda (Module 14): public read, vendor-owned write
  print('\nEVENT SESSIONS (Module 14)');
  final sesRead = await _req('GET', '/rest/v1/event_sessions',
      token: t, query: {'select': 'id,event_id,title', 'limit': '1'});
  (sesRead.code == 200 && sesRead.body is List)
      ? _ok('SES-READ', 'event agenda publicly readable')
      : _no('SES-READ', 'event_sessions read failed (HTTP ${sesRead.code}) — run migration 021');
  // SES-SEC: a client who owns no event cannot add a session to one. Use any
  // existing event id; the RLS check is on event ownership, not existence.
  final anyEvent = await _req('GET', '/rest/v1/events',
      token: t, query: {'select': 'id', 'limit': '1'});
  if (anyEvent.code == 200 && anyEvent.body is List && (anyEvent.body as List).isNotEmpty) {
    final eid = (anyEvent.body as List).first['id'];
    final ins = await _req('POST', '/rest/v1/event_sessions',
        token: t,
        extraHeaders: {'Prefer': 'return=representation'},
        jsonBody: {'event_id': eid, 'title': '__itest illegal session'});
    if (ins.code == 401 || ins.code == 403) {
      _ok('SES-SEC', 'non-owner blocked from adding sessions (RLS)');
    } else if (ins.code >= 200 && ins.code < 300) {
      final id = (ins.body is List && (ins.body as List).isNotEmpty)
          ? (ins.body as List).first['id'] : null;
      if (id != null) {
        await _req('DELETE', '/rest/v1/event_sessions', token: t, query: {'id': 'eq.$id'});
      }
      _no('SES-SEC', 'SECURITY HOLE: non-owner added a session (HTTP ${ins.code})');
    } else {
      _no('SES-SEC', 'unexpected HTTP ${ins.code} ${ins.body}');
    }
  }

  // ── Payments (Module 16): tables + entitlement RPC + RLS isolation
  print('\nPAYMENTS (Module 16)');
  final mem = await _req('POST', '/rest/v1/rpc/active_membership', token: t, jsonBody: {});
  if (mem.code == 200) {
    _ok('PAY-MEM', 'active_membership() callable (tier=${mem.body})');
  } else if (mem.code == 404) {
    _no('PAY-MEM', 'active_membership not found — run migration 022');
  } else {
    _no('PAY-MEM', 'active_membership failed (HTTP ${mem.code}) ${mem.body}');
  }
  // PAY-PLAN: the unified client-plan resolver returns a tier (free by default).
  final cp = await _req('POST', '/rest/v1/rpc/client_plan', token: t, jsonBody: {});
  if (cp.code == 200) {
    _ok('PAY-PLAN', 'client_plan() callable (plan=${cp.body})');
  } else if (cp.code == 404) {
    _no('PAY-PLAN', 'client_plan not found — run migration 024');
  } else {
    _no('PAY-PLAN', 'client_plan failed (HTTP ${cp.code}) ${cp.body}');
  }
  // PAY-CPLAN: the coach platform-plan entitlement RPC is callable.
  final cplan = await _req('POST', '/rest/v1/rpc/coach_plan_tier', token: t, jsonBody: {});
  if (cplan.code == 200) {
    _ok('PAY-CPLAN', 'coach_plan_tier() callable (tier=${cplan.body})');
  } else if (cplan.code == 404) {
    _no('PAY-CPLAN', 'coach_plan_tier not found — run migration 023');
  } else {
    _no('PAY-CPLAN', 'coach_plan_tier failed (HTTP ${cplan.code}) ${cplan.body}');
  }
  // PAY-SEC: a client cannot read another user's payment rows (RLS own-only).
  final otherPay = await _req('GET', '/rest/v1/payments',
      token: t, query: {'user_id': 'eq.${coach?.uid ?? uid}', 'select': 'id'});
  if (otherPay.code == 404) {
    _no('PAY-SEC', 'payments table missing — run migration 022');
  } else if (otherPay.code == 200 && otherPay.body is List &&
      (coach == null || (otherPay.body as List).isEmpty)) {
    _ok('PAY-SEC', 'payments are read-isolated per user (RLS)');
  } else {
    _no('PAY-SEC', 'payments RLS leak/err: HTTP ${otherPay.code} ${otherPay.body}');
  }

  // ── Coach relationships: per-client price + specialty columns (migration 025)
  print('\nCOACH RELATIONSHIPS (pricing + specialty)');
  final relCols = await _req('GET', '/rest/v1/coach_client_relationships',
      token: t, query: {'select': 'monthly_price,specialty', 'limit': '1'});
  (relCols.code == 200 && relCols.body is List)
      ? _ok('REL-COLS', 'relationship monthly_price + specialty columns present')
      : _no('REL-COLS', 'missing relationship columns (HTTP ${relCols.code}) — run migration 025');

  // ── Admin Dashboard (Module 25): SECURITY DEFINER guard rejects non-admins
  print('\nADMIN DASHBOARD (Module 25)');
  if (coach != null) {
    final stats = await _req('POST', '/rest/v1/rpc/admin_platform_stats',
        token: coach.token, jsonBody: {});
    // A coach (non-admin) must be denied: PostgREST surfaces the RAISE as 4xx.
    if (stats.code == 401 || stats.code == 403 ||
        (stats.code >= 400 && '${stats.body}'.toLowerCase().contains('not authorized'))) {
      _ok('ADM-SEC', 'admin_platform_stats denies non-admin (guard enforced)');
    } else if (stats.code == 404) {
      _no('ADM-SEC', 'admin_platform_stats not found — run migration 019');
    } else {
      _no('ADM-SEC', 'SECURITY HOLE: non-admin got HTTP ${stats.code} ${stats.body}');
    }
  }

  // ── SEC: client cannot read another user's notifications ────────────────
  print('\nSECURITY (RLS)');
  final otherId = coach?.uid ?? 'f626acd9-f76c-43ca-be4c-54d028ae09db';
  final leak = await _req('GET', '/rest/v1/notifications',
      token: t, query: {'recipient_id': 'eq.$otherId', 'select': 'id'});
  (leak.code == 200 && leak.body is List && (leak.body as List).isEmpty)
      ? _ok('SEC-001', 'client cannot read another user\'s notifications (RLS enforced)')
      : _no('SEC-001', 'RLS leak: got ${leak.body is List ? (leak.body as List).length : '?'} rows');

  _summary();
}

void _summary() {
  print('\n=== RESULT: $_pass passed, $_fail failed ===');
  if (_failures.isNotEmpty) {
    print('Failures:');
    for (final f in _failures) {
      print('  - $f');
    }
  }
  _client.close(force: true);
  exit(_fail == 0 ? 0 : 1);
}
