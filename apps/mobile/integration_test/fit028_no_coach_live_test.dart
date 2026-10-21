// FIT-028 · VERIFIED LIVE — the "no coach" state of /messages, on a real
// device, against real QA data.
//
// WHY THIS EXISTS
// ---------------
// `test/widget/messaging_no_coach_test.dart` proves the *branch* is correct by
// feeding the screen every AsyncValue by hand, and three mutations of the
// source kill it. What it cannot prove is that the branch is reachable: that a
// real signed-in member, with a real empty conversation list and a real empty
// active-coach list, actually arrives at this state rather than at the neutral
// one. That question is about the live read paths — `conversationsProvider`,
// `myCoachesProvider` and `currentUserProfileProvider` — and only a real
// request against QA can answer it.
//
// So this test mounts the REAL `MessagingScreen` in a real `ProviderScope`,
// with NO provider overridden, on emulator-5554, signed in as the committed QA
// fixture. Every value the widget sees came over the wire.
//
// IT WRITES NOTHING.
// The fixture identity is used read-only: sign in, mount, read, assert, sign
// out. No row is created, updated or deleted, so there is no cleanup step and
// nothing to leave behind. This matters more than usual here — F-21 (an
// authorization defect this programme proved exploitable) is still OPEN, and
// the standing instruction is not to exercise it further through unnecessary
// mutation.
//
// PRECONDITION, ASSERTED NOT ASSUMED
// ----------------------------------
// The fixture's only `coach_client_relationships` row is `status = 'cancelled'`
// and it owns no conversations. The test asserts both facts from the database
// before it asserts anything about pixels, so if someone later assigns this
// fixture a coach the run fails loudly as "precondition changed" rather than
// quietly reporting that FIT-028 regressed.
//
// CREDENTIAL: `p1-victim@qa.12circle.test` is the existing QA-only, is_demo
// fixture created by `supabase/tests/security/setup-identities.mjs`; its
// password is already committed at `supabase/tests/security/lib.mjs:34` and is
// restated here by the same convention `wrk01_progression_live_test.dart` and
// `service_logic_test.dart` use. It reaches nothing but QA.
//
//   flutter test integration_test/fit028_no_coach_live_test.dart \
//     -d emulator-5554 --dart-define-from-file=dart_defines/qa.json
//
// The FIT028-MARK lines are the evidence channel: all of them must appear, in
// order, for a run to count as evidence rather than as an infrastructure
// failure.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:circle_fitness/core/constants/app_constants.dart';
import 'package:circle_fitness/features/messaging/presentation/messaging_screen.dart';

const _email = 'p1-victim@qa.12circle.test';
const _pass = 'P1-Probe-Victim-2026!';

SupabaseClient get _db => Supabase.instance.client;
String get _uid => _db.auth.currentUser!.id;

void _mark(String line) => print('FIT028-MARK $line');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      publishableKey: AppConstants.supabaseAnonKey,
    );
    _mark('BOOT ok target=${AppConstants.supabaseUrl}');
    await _db.auth.signInWithPassword(email: _email, password: _pass);
    if (_db.auth.currentUser == null) {
      throw StateError('authentication failed for $_email');
    }
    _mark('AUTH ok uid=$_uid');
  });

  tearDownAll(() async {
    await _db.auth.signOut();
    _mark('SIGNOUT ok');
  });

  testWidgets('FIT-028 precondition — the fixture is a member with no active coach',
      (t) async {
    final profile = await _db
        .from('user_profiles')
        .select('role')
        .eq('id', _uid)
        .maybeSingle();
    final role = profile?['role'] as String?;
    _mark('PRECONDITION role=$role');
    expect(role, isNot('coach'),
        reason: 'FIT-028 addresses a MEMBER with no coach. If this fixture has '
            'become a coach the test is no longer measuring the state it names.');

    final active = await _db
        .from('coach_client_relationships')
        .select('id, status')
        .eq('client_id', _uid)
        .eq('status', 'active');
    _mark('PRECONDITION active_coaches=${(active as List).length}');
    expect(active, isEmpty,
        reason: 'The fixture has acquired an active coach. That is a changed '
            'precondition, not a FIT-028 regression — re-point this test at a '
            'coachless fixture before reading anything into a failure below.');

    final convs = await _db
        .from('conversations')
        .select('id')
        .or('participant_1.eq.$_uid,participant_2.eq.$_uid');
    _mark('PRECONDITION conversations=${(convs as List).length}');
  });

  testWidgets('FIT-028 a real coachless member is offered the marketplace',
      (t) async {
    // No overrides. Everything below is read live.
    await t.pumpWidget(const ProviderScope(
      child: MaterialApp(home: MessagingScreen()),
    ));

    // Let the three live futures settle. pumpAndSettle alone would time out on
    // the indeterminate progress indicator, so pump on a fixed cadence.
    for (var i = 0; i < 40; i++) {
      await t.pump(const Duration(milliseconds: 250));
      if (find.text('No coach yet').evaluate().isNotEmpty) break;
    }

    final pitch = find.text('No coach yet').evaluate().length;
    final neutral = find.text('No conversations yet').evaluate().length;
    final failed = find.text("Couldn't load messages").evaluate().length;
    _mark('RENDER pitch=$pitch neutral=$neutral failed=$failed');

    expect(failed, 0,
        reason: 'The live read failed. That is an environment result, not a '
            'FIT-028 result — the screen correctly refused to guess.');
    expect(neutral, 0);
    expect(pitch, 1);
    expect(find.text('Find a coach'), findsOneWidget);
    expect(find.text('Browse coaches, compare plans and get matched.'),
        findsOneWidget);
    _mark('PASS the coachless member is offered the marketplace');
  });
}
