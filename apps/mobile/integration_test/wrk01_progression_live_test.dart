// I-WRK-01 · VERIFIED LIVE — the real strength-progression read path, against QA.
//
// WHY THIS EXISTS
// ---------------
// `QA_CLOSURE_STANDARD.md` §2.1 puts I-WRK-01 in the **Data contract / schema**
// class, whose fourth rung is "VERIFIED LIVE where a read path exists". §2
// defines that rung as "a real request against QA reproduces the correct
// behaviour, **and the same probe demonstrably failed before the fix**".
//
// Nothing else in this repository can supply it. `npm run test:contract` is
// offline by construction (`supabase/tests/contract/run.mjs:5` — "Offline.
// Contacts no environment"); the SQL evidence suites roll back, so their rows
// are invisible to a separate PostgREST client; and the Node suites cannot
// execute Dart. Only a Flutter integration test reaches
// `WorkoutService.getExerciseProgression()` itself.
//
// This file is the probe for BOTH legs. The harness
// (`tool/negative_control/wrk01_live_probe.sh`) runs it against the fixed tree
// and, unchanged, against the recoverable parent `654b09c^` (`acd2cc5`), where
// the same method still selects `created_at`.
//
// FIXTURE — F-1, owner-authorized 2026-08-27
// ------------------------------------------
// Rows are created by the fixture identity's OWN authenticated permissions.
// `001_full_ecosystem.sql:370` — "users manage own set logs" FOR ALL TO
// authenticated USING (user_id = auth.uid()); with no WITH CHECK, PostgreSQL
// applies USING to INSERT as well. No service-role key is used, and none is
// needed.
//
// The fixture is scoped by a run-unique `exercise_name` (PROBE_RUN_ID), so
// concurrent runs cannot see or delete each other's rows and cleanup never
// needs a broad predicate.
//
// WEIGHTS DESCEND, AND THAT IS DELIBERATE.
// `trg_detect_pr` (049) is AFTER INSERT FOR EACH ROW and SECURITY DEFINER: when
// a row beats the prior best for the same user+exercise it INSERTs into
// `notifications` — for the client and, if one exists, for their coach. A
// coach's notification is owned by the coach and could not be removed without
// service-role, which this authorization forbids. Descending weights inserted
// highest-first mean `NEW.weight_kg <= v_prior` every time after the first, and
// the first has no prior, so the trigger returns early on every row and writes
// nothing. The fixture is therefore residue-free by construction, not by
// cleanup. Do not "fix" these weights into an ascending series.
//
// CREDENTIAL: `p1-victim@qa.12circle.test` is the existing QA-only, is_demo
// fixture identity created by `supabase/tests/security/setup-identities.mjs`.
// Its password is already committed at `supabase/tests/security/lib.mjs:34`;
// restating it here introduces no new exposure, and mirrors the convention
// `integration_test/service_logic_test.dart` already uses. It is not a secret,
// it is not a GitHub secret, and it reaches nothing but QA.
//
//   flutter test integration_test/wrk01_progression_live_test.dart -d linux \
//     --dart-define-from-file=dart_defines/qa.json \
//     --dart-define=PROBE_RUN_ID=<unique> --dart-define=PROBE_MODE=<mode>
//
// MODES
//   seed-and-read — create the fixture, then assert the full progression (post-fix leg)
//   read-only     — assert the fixture is present, then read it (pre-fix leg)
//   cleanup       — delete the fixture and prove zero rows remain
//
// The WRK01-MARK lines are the harness's discrimination channel. Every one of
// them must appear, in order, for a run to count as evidence rather than as an
// infrastructure failure. Do not remove or reword them without updating the
// harness.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:circle_fitness/core/constants/app_constants.dart';
import 'package:circle_fitness/features/workout/data/workout_service.dart';

// ── The fixture identity (see header) ────────────────────────────────────────
const _email = 'p1-victim@qa.12circle.test';
const _pass = 'P1-Probe-Victim-2026!';

const _runId = String.fromEnvironment('PROBE_RUN_ID');
const _mode = String.fromEnvironment('PROBE_MODE', defaultValue: 'seed-and-read');

SupabaseClient get _db => Supabase.instance.client;
String get _uid => _db.auth.currentUser!.id;

/// The exercise name IS the fixture's identity. Run-unique, so two concurrent
/// CI runs never share, read or delete each other's rows.
String get _exercise => 'WRK01-PROBE-$_runId';

/// Deterministic fixture. Weights DESCEND — see the header note on trg_detect_pr.
/// Expected progression, grouped by date and sorted ascending:
///   2026-08-01 → max 60.0, volume 600.0, sets 1
///   2026-08-08 → max 57.5, volume 460.0, sets 1
///   2026-08-15 → max 55.0, volume 540.0, sets 2
const _rows = <Map<String, dynamic>>[
  {'logged_at': '2026-08-01T10:00:00Z', 'weight_kg': 60.0, 'reps': 10, 'set_number': 1},
  {'logged_at': '2026-08-08T10:00:00Z', 'weight_kg': 57.5, 'reps': 8, 'set_number': 2},
  {'logged_at': '2026-08-15T10:00:00Z', 'weight_kg': 55.0, 'reps': 6, 'set_number': 3},
  {'logged_at': '2026-08-15T11:30:00Z', 'weight_kg': 52.5, 'reps': 4, 'set_number': 4},
];

void _mark(String line) => print('WRK01-MARK $line');

Future<int> _fixtureCount() async {
  final rows = await _db
      .from('workout_set_logs')
      .select('id')
      .eq('user_id', _uid)
      .eq('exercise_name', _exercise);
  return (rows as List).length;
}

Future<void> _seed() async {
  if (await _fixtureCount() == _rows.length) {
    _mark('FIXTURE already-present rows=${_rows.length}');
    return;
  }
  for (var i = 0; i < _rows.length; i++) {
    final r = _rows[i];
    await _db.from('workout_set_logs').insert({
      // session_id is deliberately omitted (nullable): a session row would be a
      // second fixture to clean up, and the read path never filters on it.
      'user_id': _uid,
      'exercise_name': _exercise,
      'set_number': r['set_number'],
      'reps': r['reps'],
      'weight_kg': r['weight_kg'],
      'logged_at': r['logged_at'],
      // Required by trg_workout_set_logs_require_identity (migration 120):
      // "a logged set must carry the identity of the set it records".
      'set_id': '$_exercise:s${r['set_number']}',
      'completed': true,
    });
  }
  final n = await _fixtureCount();
  if (n != _rows.length) {
    throw StateError('fixture seed incomplete: expected ${_rows.length}, found $n');
  }
  _mark('FIXTURE seeded rows=$n');
}

Future<void> _cleanup() async {
  await _db
      .from('workout_set_logs')
      .delete()
      .eq('user_id', _uid)
      .eq('exercise_name', _exercise);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (_runId.isEmpty) {
      throw StateError('PROBE_RUN_ID is required — the fixture must be run-scoped');
    }
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      publishableKey: AppConstants.supabaseAnonKey,
    );
    _mark('BOOT ok target=${AppConstants.supabaseUrl}');
    await _db.auth.signInWithPassword(email: _email, password: _pass);
    if (_db.auth.currentUser == null) {
      throw StateError('authentication failed for $_email');
    }
    _mark('AUTH ok uid=$_uid mode=$_mode exercise=$_exercise');
  });

  tearDownAll(() async {
    // Layer A. `seed-and-read` deliberately KEEPS the fixture so the pre-fix leg
    // reads exactly the same rows; the harness then runs `cleanup`, and the
    // workflow's if:always() step is Layer B behind both.
    if (_mode == 'read-only') {
      try {
        await _cleanup();
        _mark('CLEANUP layer-A done');
      } catch (e) {
        _mark('CLEANUP layer-A failed: $e');
      }
    }
    await _db.auth.signOut();
  });

  // ── POST-FIX LEG ──────────────────────────────────────────────────────────
  group('I-WRK-01 · the real progression read path returns the fixture', () {
    testWidgets('getExerciseProgression() returns the seeded progression',
        (_) async {
      if (_mode != 'seed-and-read') return;
      await _seed();

      // The real service. Not mocked, not re-implemented, not a REST replica.
      _mark('SERVICE-CALLED getExerciseProgression');
      final result = await WorkoutService().getExerciseProgression(_exercise);
      _mark('RESULT len=${result.length}');

      // The assertion whose failure IS the pre-fix signature.
      final nonEmpty = result.isNotEmpty;
      _mark('ASSERT-NONEMPTY ${nonEmpty ? 'PASS' : 'FAIL'}');
      expect(result, isNotEmpty,
          reason: 'I-WRK-01: getExerciseProgression() returned no rows for a '
              'fixture that demonstrably exists. Pre-fix this is exactly what '
              'happens — the query names created_at, PostgREST answers 42703, '
              'and the service catch returns [].');

      expect(result.length, 3, reason: 'three distinct logged_at dates');

      final dates = result.map((r) => r['date'] as String).toList();
      expect(dates, ['2026-08-01', '2026-08-08', '2026-08-15'],
          reason: 'dates must be extracted from logged_at and sorted ascending');

      expect(result[0]['max_weight'], 60.0);
      expect(result[0]['total_volume'], 600.0);
      expect(result[0]['sets_count'], 1);

      expect(result[1]['max_weight'], 57.5);
      expect(result[1]['total_volume'], 460.0);
      expect(result[1]['sets_count'], 1);

      // Two sets on one date: proves grouping, not just row pass-through.
      expect(result[2]['max_weight'], 55.0);
      expect(result[2]['total_volume'], 540.0);
      expect(result[2]['sets_count'], 2);

      _mark('ASSERT-ALL PASS');
    });
  });

  // ── PRE-FIX LEG ───────────────────────────────────────────────────────────
  group('I-WRK-01 · pre-fix leg reads the same fixture', () {
    testWidgets('the fixture is present, and the service still must return it',
        (_) async {
      if (_mode != 'read-only') return;

      // Prove the fixture exists over REST BEFORE calling the service, so an
      // empty service result cannot be blamed on a missing fixture.
      final n = await _fixtureCount();
      _mark('FIXTURE present rows=$n');
      expect(n, _rows.length,
          reason: 'the pre-fix leg must read the SAME fixture the post-fix leg '
              'asserted against; if it is absent this run is an infrastructure '
              'failure, not pre-fix evidence');

      _mark('SERVICE-CALLED getExerciseProgression');
      final result = await WorkoutService().getExerciseProgression(_exercise);
      _mark('RESULT len=${result.length}');

      final nonEmpty = result.isNotEmpty;
      _mark('ASSERT-NONEMPTY ${nonEmpty ? 'PASS' : 'FAIL'}');
      expect(result, isNotEmpty,
          reason: 'Against the fixed tree this passes. Against 654b09c^ it must '
              'fail with [] — that failure is the VERIFIED LIVE pre-fix leg.');
    });
  });

  // ── CLEANUP ───────────────────────────────────────────────────────────────
  group('I-WRK-01 · fixture cleanup', () {
    testWidgets('the fixture is deleted and provably absent', (_) async {
      if (_mode != 'cleanup') return;
      await _cleanup();
      final n = await _fixtureCount();
      _mark('CLEANUP verified remaining=$n');
      expect(n, 0, reason: 'the probe must leave no QA data behind');
    });
  });
}
