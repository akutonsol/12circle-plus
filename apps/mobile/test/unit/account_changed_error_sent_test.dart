import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/coach/data/coach_relationship_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/coach_change_server.dart';
import '../support/two_member_postgrest.dart';

// P0-RM-1 · C14-62b-04 + C15-63b-03.
//
// (a) AccountChangedError says whether a step of the action had already been
//     SENT and done before the switch was noticed (a first
//     `cancel-subscription` answered ok): then something happened, and the
//     screens record its outcome as not shown. It did not say so, so nobody
//     could.
// (b) No fallback shows its text. `refusalToSay` is the one way a caller turns
//     an error into words, and fails closed for it; the static guard below
//     catches a caller of a refusing service method that shows a StateError's
//     message without it.
//
// HOW TO SEE IT FAIL: `git checkout 6d1611d --
// lib/features/coach/data/coach_relationship_service.dart` — this file then
// does not compile (no `sent`, no `refusalToSay`); the screens' behaviour that
// depends on it fails in test/widget/coach_flows_outcome_after_switch_test.dart.

const _a = memberA;
const _b = memberB;

void main() {
  final server = CoachChangeServer();
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(server);
  });

  setUp(() async {
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
    await signInAs(_a);
    server.paid[_a] = ['sub-a-1', 'sub-a-2'];
    server.paid[_b] = ['sub-b-1'];
  });
  tearDown(resetFailureSink);

  Future<void> turns() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> until(bool Function() ok, String what) async {
    final clock = Stopwatch()..start();
    while (!ok()) {
      if (clock.elapsed > const Duration(seconds: 20)) fail('never: $what');
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
  }

  List<(String, Object?)> invoked() => [
        for (final r in server.invokes)
          (r.who, (jsonDecode(r.body) as Map)['subscriptionId'])
      ];

  group('cancelCoach: AccountChangedError.sent', () {
    for (final (what, change) in <(String, Future<void> Function())>[
      ('B signs in', () => signInAs(_b)),
      ('A signs out', signOut),
    ]) {
      test('$what while the FIRST of two cancellations is in flight: stops '
          'before the second, sent == true', () async {
        final gate = server.gates['POST cancel-subscription:$_a'] = Completer();
        final run = CoachRelationshipService()
            .cancelCoach(CoachChangeServer.coach, 'r', null, expectedUid: _a);
        await until(() => server.invokes.isNotEmpty, 'the first cancellation');
        await change();
        gate.complete();
        Object? thrown;
        try {
          await run;
        } catch (e) {
          thrown = e;
        }
        expect(thrown, isA<AccountChangedError>());
        expect((thrown! as AccountChangedError).sent, isTrue,
            reason: "THE defect: A's first subscription WAS cancelled, and the "
                'error did not say so');
        expect(invoked(), [(_a, 'sub-a-1')], reason: 'only the first went out, as A');
        expect(server.restWrites, isEmpty);
        expect(server.log.where((r) => r.body.contains('sub-b')), isEmpty);
        // The stop is the service's single record.
        expect(reported.where((f) => '${f.error}'.contains('account changed')),
            hasLength(1));
      });

      test('$what while the subscriptions read is in flight: nothing sent, '
          'sent == false', () async {
        final gate = server.gates['GET subscriptions/coach:$_a'] = Completer();
        final run = CoachRelationshipService()
            .cancelCoach(CoachChangeServer.coach, 'r', null, expectedUid: _a);
        await until(() => server.named('subscriptions').isNotEmpty, 'the read');
        await change();
        gate.complete();
        Object? thrown;
        try {
          await run;
        } catch (e) {
          thrown = e;
        }
        expect(thrown, isA<AccountChangedError>());
        expect((thrown! as AccountChangedError).sent, isFalse);
        expect(server.invokes, isEmpty);
        expect(server.restWrites, isEmpty);
      });
    }

    test('unpaid: the relationship update matched no row, then B: sent == false '
        '(nothing changed)', () async {
      server.paid.clear();
      final key = 'PATCH coach_client_relationships:$_a';
      server.noRows.add(key);
      final gate = server.gates[key] = Completer();
      final run = CoachRelationshipService()
          .cancelCoach(CoachChangeServer.coach, 'r', null, expectedUid: _a);
      await until(() => server.restWrites.isNotEmpty, 'the update');
      await signInAs(_b);
      gate.complete();
      await expectLater(
          run,
          throwsA(isA<AccountChangedError>()
              .having((e) => e.sent, 'sent', isFalse)));
    });

    test('A -> B -> A during the first cancellation: A is signed in at every '
        'step, so both go out as A and it returns', () async {
      final gate = server.gates['POST cancel-subscription:$_a'] = Completer();
      final run = CoachRelationshipService()
          .cancelCoach(CoachChangeServer.coach, 'r', null, expectedUid: _a);
      await until(() => server.invokes.isNotEmpty, 'the first cancellation');
      await signInAs(_b);
      await signInAs(_a);
      gate.complete();
      final end = await run;
      expect(end.scheduled, isTrue);
      expect(invoked(), [(_a, 'sub-a-1'), (_a, 'sub-a-2')]);
    });

    test('control: a token refresh during the first cancellation changes '
        'nothing', () async {
      final gate = server.gates['POST cancel-subscription:$_a'] = Completer();
      final run = CoachRelationshipService()
          .cancelCoach(CoachChangeServer.coach, 'r', null, expectedUid: _a);
      await until(() => server.invokes.isNotEmpty, 'the first cancellation');
      await refreshSession();
      gate.complete();
      final end = await run;
      expect(end.scheduled, isTrue);
      expect(invoked(), [(_a, 'sub-a-1'), (_a, 'sub-a-2')]);
      expect(reported, isEmpty);
    });
  });

  group('approve / decline', () {
    for (final (name, call) in <(String,
        Future<void> Function(CoachRelationshipService))>[
      ('approveRequest', (s) => s.approveRequest('rel-1', 'client-1', expectedUid: _a)),
      ('declineRequest', (s) => s.declineRequest('rel-1', 'client-1', expectedUid: _a)),
    ]) {
      test('$name: matched no row, then B: sent == false', () async {
        final key = 'PATCH coach_client_relationships:$_a';
        server.noRows.add(key);
        final gate = server.gates[key] = Completer();
        final run = call(CoachRelationshipService());
        await until(() => server.restWrites.isNotEmpty, 'the answer');
        await signInAs(_b);
        gate.complete();
        await expectLater(
            run,
            throwsA(isA<AccountChangedError>()
                .having((e) => e.sent, 'sent', isFalse)));
      });

      test('$name: answered, then B: returns (its outcome is the caller\'s to '
          'drop), no notification goes out as anyone', () async {
        final key = 'PATCH coach_client_relationships:$_a';
        final gate = server.gates[key] = Completer();
        final run = call(CoachRelationshipService());
        await until(() => server.restWrites.isNotEmpty, 'the answer');
        await signInAs(_b);
        gate.complete();
        await run;
        await turns();
        expect(server.named('notifications'), isEmpty);
        expect(server.restWrites.map((r) => (r.method, r.name, r.who)),
            [('PATCH', 'coach_client_relationships', _a)]);
      });
    }
  });

  group('refusalToSay (fails closed)', () {
    test('an AccountChangedError is never words, whether or not sent', () {
      expect(refusalToSay(AccountChangedError('Ending coaching'), 'x'), isNull);
      expect(
          refusalToSay(AccountChangedError('Ending coaching', sent: true), 'x'),
          isNull);
    });
    test('nor is any StateError that only says the account changed', () {
      expect(
          refusalToSay(
              StateError('end coaching: the signed-in account changed'), 'x'),
          isNull);
    });
    test('a refusal written to be shown is shown; anything else is otherwise',
        () {
      expect(
          refusalToSay(
              StateError('No active coaching with this coach — nothing was changed.'),
              'x'),
          'No active coaching with this coach — nothing was changed.');
      expect(refusalToSay(Exception('SECRET_TABLE'), 'Could not.'), 'Could not.');
    });
  });

  // ── Static guard ────────────────────────────────────────────────────────────
  //
  // A source-shape test, on purpose: the defect is a FUTURE caller, which no
  // behaviour test of today's screens can see. A file that calls a service
  // method that can refuse with AccountChangedError must turn a StateError into
  // words through `refusalToSay` only — never `e is StateError ? e.message`
  // (which shows "Not done: the signed-in account changed", possibly to the
  // next account, when the AccountChangedError catch before it is forgotten).
  group('static guard: no caller shows an AccountChangedError', () {
    // Methods that throw AccountChangedError (coach_relationship_service.dart).
    final refusing = RegExp(
        r'\.(cancelCoach|approveRequest|declineRequest|requestCoach|sendInvite|setGlobalPrice)\(');
    // `x is StateError ? x.message`, `if (x is StateError) return x.message`.
    final showsMessage = RegExp(
        r'(\w+)\s+is\s+StateError\s*(\?|\)\s*return)\s*\1\.message');

    // Callers in files outside RM-1's package that still do it; each is a
    // follow-up (see the RM-1 report). This list may only SHRINK: a file that
    // is fixed must be taken off it.
    const knownElsewhere = {
      'lib/features/coach/presentation/coach_marketplace_screen.dart',
      'lib/features/coach/presentation/coach_pricing_sheet.dart',
    };

    test('every caller goes through refusalToSay', () {
      final offenders = <String>{};
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.path.endsWith('coach_relationship_service.dart')) continue;
        final src = f.readAsStringSync();
        if (!refusing.hasMatch(src)) continue;
        if (showsMessage.hasMatch(src)) offenders.add(f.path);
      }
      expect(offenders.difference(knownElsewhere), isEmpty,
          reason: 'these show a StateError message without refusalToSay');
      expect(knownElsewhere.difference(offenders), isEmpty,
          reason: 'fixed — take them off knownElsewhere');
    });

    test('the guard sees the shape it forbids (negative control)', () {
      expect(showsMessage.hasMatch('m = e is StateError ? e.message : g;'), isTrue);
      expect(showsMessage.hasMatch('if (err is StateError) return err.message;'),
          isTrue);
      expect(showsMessage.hasMatch('m = refusalToSay(e, g);'), isFalse);
    });

    test('the RM-1 callers use it', () {
      for (final p in [
        'lib/features/profile/presentation/profile_screen.dart',
        'lib/features/payments/presentation/manage_subscription_screen.dart',
        'lib/features/dashboard/presentation/coach_dashboard_screen.dart',
      ]) {
        expect(File(p).readAsStringSync(), contains('refusalToSay('), reason: p);
      }
    });
  });
}
