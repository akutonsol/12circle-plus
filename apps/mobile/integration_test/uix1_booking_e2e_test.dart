// UIX-1 / M-03 · VERIFIED END-TO-END — the real booking surface, against QA.
//
// WHY THIS EXISTS
// ---------------
// `QA_CLOSURE_STANDARD.md` §2.1 puts UIX-1 in the **Product integrity / UI
// reachability** class (owner ruling 2026-08-28, registry §7.16), whose third
// rung is VERIFIED END-TO-END — "a human or a driver reached the surface". §2
// defines it as the full chain: UI → state → service → authorization →
// API/function → database → persistence → response → UI state.
//
// Nothing else in this repository supplies it. `npm run test:contract` is
// offline and inspects source; `uix1_negative_control.sh` proves the guard
// discriminates; neither renders a widget. The defect was invisible to both
// until it was written: PostgREST answered PGRST200 for the `coach:coach_id(…)`
// embed before reading a row, and `_load()`'s catch turned that into a
// confident "no slots".
//
// SURFACE REACHABILITY — owner ruling 2026-08-28, ruling 1.
// The driver reaches BookingScreen through the REAL route: the real
// `CircleFitnessApp` → `MaterialApp.router` → `routerProvider` → `/appointments`
// → `PaywallGate(required: ClientPlan.coachGuided)` → `BookingScreen`. Mounting
// BookingScreen directly is explicitly NOT the acceptance path: authorization is
// a named link in §2's chain, and a direct mount skips it.
//
// THE ENTITLEMENT IS NOT A SEPARATE FIXTURE.
// `client_plan()` (036_client_plan_and_coach_media.sql:9-12) returns
// 'coach_guided' from an ACTIVE `coach_client_relationships` row — the same row
// the surface needs. Passing the paywall therefore costs no extra QA state.
//
// FIXTURE, AND WHY IT NEEDS NO SERVICE ROLE
//  * `coach_client_relationships` INSERT — policy "relationship parties create"
//    (113:271-286) lets a CLIENT enrol itself: client_id = auth.uid(),
//    initiated_by = 'client', status IN ('pending','active'), and
//    is_coach_profile(coach_id). p1-coach carries role='coach'
//    (setup-identities.mjs:13-16), so p1-victim inserts its own active row.
//  * `coach_availability` INSERT/DELETE — policy "coach_manage_availability"
//    (011:47) is FOR ALL USING (auth.uid() = coach_id), so p1-coach manages its
//    own slots.
//  * `coaching_calls` is NOT seeded: `ready` needs only a non-empty slot list.
//
// TEARDOWN — owner ruling 2026-08-28, ruling 2.
// 113:306-308 is deliberate: "No DELETE policy and no DELETE grant: ending a
// relationship is status = 'cancelled' … Hard deletion stays with service_role."
// The relationship is therefore CANCELLED, never hard-deleted, and the read-back
// verifies that no ACTIVE relationship remains. Availability rows are run-tagged
// and deleted by the coach identity, and the read-back requires zero. Altering
// that RLS to permit deletion is forbidden: the table's own COMMENT calls it the
// AUTHORIZATION SOURCE.
//
// A4 IS NOT ASSERTED, AND THAT IS A RECORDED LIMITATION, NOT AN OVERSIGHT.
// `_LoadFailedState` cannot be reached honestly from here: `_load()` returns at
// `uid == null` before its try/catch (booking_screen.dart:50), so an unreachable
// URL yields `noCoach`, not `error`. Reaching it would need a production-code
// edit, an RLS change, or a mock — all forbidden by the owner ruling. The
// failure path stays unverified end-to-end and must be recorded as such.
//
// CREDENTIALS: `p1-victim@qa.12circle.test` and `p1-coach@qa.12circle.test` are
// the committed QA-only, is_demo fixture identities from
// `supabase/tests/security/setup-identities.mjs`; their passwords are already at
// `supabase/tests/security/lib.mjs:34,36`. Restating them introduces no new
// exposure and mirrors `wrk01_progression_live_test.dart`. No GitHub secret, no
// service-role key, and they reach nothing but QA.
//
//   flutter test integration_test/uix1_booking_e2e_test.dart -d linux \
//     --dart-define-from-file=dart_defines/qa.json \
//     --dart-define=PROBE_RUN_ID=<unique> --dart-define=PROBE_MODE=<mode>
//
// MODES
//   e2e     — seed, drive the real route, assert A1/A2/A3, then tear down
//   cleanup — tear down only, and prove nothing remains
//
// The UIX1-MARK lines are the harness's discrimination channel. Every one must
// appear for a run to count as evidence rather than an infrastructure failure.
// Do not remove or reword them without updating the harness.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:circle_fitness/core/constants/app_constants.dart';
import 'package:circle_fitness/core/router/app_router.dart';
import 'package:circle_fitness/main.dart';

// ── The fixture identities (see header) ──────────────────────────────────────
const _clientEmail = 'p1-victim@qa.12circle.test';
const _clientPass = 'P1-Probe-Victim-2026!';
const _coachEmail = 'p1-coach@qa.12circle.test';
const _coachPass = 'P1-Probe-Coach-2026!';

/// The coach's rendered name. setup-identities.mjs writes
/// first_name = 'P1', last_name = <key>, so p1-coach renders as 'Coach P1 coach'
/// through booking_screen.dart:98.
const _expectedCoachName = 'Coach P1 coach';

const _runId = String.fromEnvironment('PROBE_RUN_ID');
const _mode = String.fromEnvironment('PROBE_MODE', defaultValue: 'e2e');

SupabaseClient get _db => Supabase.instance.client;

/// Run scoping. `coach_availability.type` is CHECK-constrained and the table has
/// no free-text column, so the run tag lives in `duration_minutes` — an INTEGER
/// with no constraint. Every insert carries it and every delete filters on it,
/// so two concurrent runs can neither see nor remove each other's rows, and no
/// schema change is needed. 600-699 is far outside any real booking duration.
int get _runTag => 600 + (_runId.hashCode.abs() % 100);

/// Slots are placed far enough out that no real QA data shares the window, and
/// inside the screen's own 14-day horizon (booking_screen.dart:174-175).
List<DateTime> get _slotTimes {
  final base = DateTime.now().toUtc().add(const Duration(days: 3));
  return [
    DateTime.utc(base.year, base.month, base.day, 9, 0),
    DateTime.utc(base.year, base.month, base.day, 10, 0),
  ];
}

void _mark(String line) => print('UIX1-MARK $line');

Future<void> _signIn(String email, String pass) async {
  await _db.auth.signOut();
  await _db.auth.signInWithPassword(email: email, password: pass);
  if (_db.auth.currentUser == null) {
    throw StateError('authentication failed for $email');
  }
}

// ── Fixture ─────────────────────────────────────────────────────────────────

Future<String> _coachId() async {
  await _signIn(_coachEmail, _coachPass);
  return _db.auth.currentUser!.id;
}

Future<void> _seedAvailability(String coachId) async {
  for (final t in _slotTimes) {
    await _db.from('coach_availability').insert({
      'coach_id': coachId,
      'slot_time': t.toIso8601String(),
      'duration_minutes': _runTag,
      'type': 'check_in',
      'is_booked': false,
    });
  }
  final rows = await _db
      .from('coach_availability')
      .select('id')
      .eq('coach_id', coachId)
      .eq('duration_minutes', _runTag);
  _mark('FIXTURE availability rows=${(rows as List).length} tag=$_runTag');
}

Future<void> _seedRelationship(String coachId) async {
  await _signIn(_clientEmail, _clientPass);
  final uid = _db.auth.currentUser!.id;

  // Isolation: never overwrite pre-existing state (owner ruling 2026-08-28,
  // ruling 9). A relationship we did not create is a collision, not a fixture.
  final existing = await _db
      .from('coach_client_relationships')
      .select('status')
      .eq('client_id', uid)
      .eq('coach_id', coachId);
  final prior = (existing as List)
      .where((r) => (r as Map)['status'] == 'active')
      .length;
  if (prior > 0) {
    throw StateError(
      'FIXTURE COLLISION: an active coach_client_relationship already exists '
      'between the fixture identities. This probe will not overwrite state it '
      'did not create. Resolve the residue and re-run.',
    );
  }
  _mark('FIXTURE collision-check clean prior-active=0');

  await _db.from('coach_client_relationships').insert({
    'client_id': uid,
    'coach_id': coachId,
    'initiated_by': 'client',
    'status': 'active',
  });
  final active = await _activeRelationshipCount(uid, coachId);
  _mark('FIXTURE relationship active=$active');
  if (active != 1) {
    throw StateError('the active relationship fixture was not created');
  }
}

Future<int> _activeRelationshipCount(String uid, String coachId) async {
  final rows = await _db
      .from('coach_client_relationships')
      .select('id')
      .eq('client_id', uid)
      .eq('coach_id', coachId)
      .eq('status', 'active');
  return (rows as List).length;
}

// ── Teardown ────────────────────────────────────────────────────────────────

Future<void> _teardown() async {
  // 1 · Availability, removed by the coach that owns it.
  final coachId = await _coachId();
  await _db
      .from('coach_availability')
      .delete()
      .eq('coach_id', coachId)
      .eq('duration_minutes', _runTag);
  final slotsLeft = await _db
      .from('coach_availability')
      .select('id')
      .eq('coach_id', coachId)
      .eq('duration_minutes', _runTag);
  final nSlots = (slotsLeft as List).length;

  // 2 · The relationship is CANCELLED, not deleted — 113:306-308.
  await _signIn(_clientEmail, _clientPass);
  final uid = _db.auth.currentUser!.id;
  await _db
      .from('coach_client_relationships')
      .update({'status': 'cancelled'})
      .eq('client_id', uid)
      .eq('coach_id', coachId)
      .eq('status', 'active');
  final nActive = await _activeRelationshipCount(uid, coachId);

  _mark('CLEANUP verified availability=$nSlots active-relationships=$nActive');
  if (nSlots != 0 || nActive != 0) {
    throw StateError('the probe left QA fixture state behind');
  }
}

// ── Bounded pump: the tree talks to a live backend, so pumpAndSettle can
//    legitimately never settle. Pump in slices until the finder matches.
Future<bool> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 45),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    // OBSERVABILITY ONLY (run #48 gate). A rendering exception escaping this
    // pump aborted run #47 before the finder, the marker and the expect could
    // run, and the raw CI job log is not retrievable from this environment.
    // The catch below READS the exception and re-throws it UNCHANGED: nothing
    // is swallowed, nothing becomes a boolean, no pump is added, no retry is
    // introduced, and the loop's timeout, interval, finder evaluation and
    // return behaviour are byte-for-byte the behaviour they were before.
    // `rethrow` preserves both the original exception object and its original
    // stack trace. `FlutterError.toString()` renders its full diagnostics tree,
    // so printing the caught object captures FlutterError detail without
    // assuming the exception is one.
    try {
      await tester.pump(const Duration(milliseconds: 250));
    } catch (error, stack) {
      print('UIX1-DIAG pump-exception-begin');
      print('UIX1-DIAG type=${error.runtimeType}');
      print('UIX1-DIAG detail-begin');
      print(error);
      print('UIX1-DIAG detail-end');
      print('UIX1-DIAG stack-begin');
      print(stack);
      print('UIX1-DIAG stack-end');
      print('UIX1-DIAG pump-exception-end');
      rethrow;
    }
    if (finder.evaluate().isNotEmpty) return true;
  }
  return false;
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
    _mark('BOOT ok target=${AppConstants.supabaseUrl} mode=$_mode');
  });

  tearDownAll(() async {
    await _db.auth.signOut();
  });

  // ── THE END-TO-END LEG ────────────────────────────────────────────────────
  group('UIX-1 · the real booking surface, reached through the real route', () {
    testWidgets('/appointments passes the paywall and renders the real coach',
        (tester) async {
      if (_mode != 'e2e') return;

      final coachId = await _coachId();
      await _seedAvailability(coachId);
      await _seedRelationship(coachId);
      _mark('AUTH ok client-session=${_db.auth.currentUser != null}');

      try {
        // The REAL app: real ProviderScope container, real CircleFitnessApp,
        // real MaterialApp.router, real routerProvider and its redirect.
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const CircleFitnessApp(),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));

        // The authoritative BookingScreen route (app_router.dart:290-291).
        final GoRouter router = container.read(routerProvider);
        router.go('/appointments');
        _mark('ROUTE navigated=/appointments');

        // A1 · the paywall let a legitimately entitled client through.
        final appBar = find.text('Book a Call');
        final reached = await _pumpUntil(tester, appBar);
        _mark('A1 surface-reached=$reached');
        expect(reached, isTrue,
            reason: 'UIX-1 A1: /appointments did not render BookingScreen. '
                'client_plan() returns coach_guided from the active '
                'relationship, so PaywallGate must not lock this client out.');

        final locked = find.textContaining('Upgrade your plan').evaluate().isNotEmpty;
        _mark('A1 paywall-locked=$locked');
        expect(locked, isFalse, reason: 'UIX-1 A1: the paywall locked the surface');

        // A2 · the real coach identity, obtained through public_profiles.
        final coachName = find.textContaining(_expectedCoachName);
        final rendered = await _pumpUntil(tester, coachName);
        _mark('A2 coach-rendered=$rendered expected="$_expectedCoachName"');
        expect(rendered, isTrue,
            reason: 'UIX-1 A2: the coach name never reached the widget tree. '
                'Pre-fix this is exactly what happens — the coach:coach_id '
                'embed answers PGRST200 and _load() catches it.');

        // A3 · the meaningful state, not noCoach / noSlots / error.
        final slots = find.text('Available Slots');
        final ready = await _pumpUntil(tester, slots);
        _mark('A3 ready-state=$ready');
        expect(ready, isTrue, reason: 'UIX-1 A3: the surface never reached ready');

        for (final wrong in const [
          'No Coach Selected Yet',
          "Couldn't load your bookings",
          'No Slots Available',
        ]) {
          final present = find.textContaining(wrong).evaluate().isNotEmpty;
          _mark('A3 not-$wrong=${!present}');
          expect(present, isFalse,
              reason: 'UIX-1 A3: the surface resolved to "$wrong"');
        }

        _mark('ASSERT-ALL PASS');
      } finally {
        // Layer A. The workflow's if:always() step is Layer B behind it.
        await _teardown();
      }
    });
  });

  // ── CLEANUP-ONLY MODE ─────────────────────────────────────────────────────
  group('UIX-1 · fixture cleanup', () {
    testWidgets('the fixture is retired and provably absent', (_) async {
      if (_mode != 'cleanup') return;
      await _teardown();
    });
  });
}
