import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/coach/domain/coach_provider.dart';
import 'package:circle_fitness/features/profile/presentation/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/account_app.dart';

// P0-FL-59a round 2, item 9 (59d N-1/N-2) — Profile's "Cancel Coach" ends the
// coaching of the account that opened it. Confirmed after A -> B it ended B's
// with that coach, and an answer to A's was told to B.
//
// Mounted WITHOUT AccountScope: the guard is this flow's own.

const _coach = {'id': 'coach-a', 'first_name': 'Avery', 'last_name': 'Stone'};
final _server = AccountServer();
final _realtime = FakeRealtime();
final _failures = <AppFailure>[];

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initAccountSupabase(_server, _realtime, MemoryStore());
  });

  setUp(() {
    _server.reset();
    _failures.clear();
    setFailureSink(_failures.add);
    addTearDown(resetFailureSink);
  });

  late int refreshed;

  Future<void> open(WidgetTester t) async {
    refreshed = 0;
    t.view.physicalSize = const Size(900, 2000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.runAsync(signOut);
    await t.runAsync(() => signInAs(acctA));
    await t.pumpWidget(ProviderScope(
      overrides: [
        assignedCoachProvider.overrideWith((ref) async => _coach),
        clientRelationshipProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
              child: MyCoachSection(onCoachCancelled: () => refreshed++)),
        ),
      ),
    ));
    await settleApp(t, 4);
    await t.tap(find.text('Cancel Coach'));
    await settleApp(t, 8);
    await t.tap(find.text('Not a good fit'));
    await t.pump();
    _server.sent.clear();
  }

  Future<void> end(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.runAsync(signOut);
    await t.pump(const Duration(seconds: 5));
  }

  Future<void> confirm(WidgetTester t) async {
    await t.tap(find.text('Cancel Coach').last);
    await settleApp(t, 8);
  }

  Iterable<Sent> writes() => _server.sent
      .where((s) => s.url.path.contains('/rest/') && s.method != 'GET');

  void expectNothingSaid() {
    expect(find.byType(SnackBar), findsNothing);
    expect(refreshed, 0);
    expect(
        _failures.where((f) =>
            f.origin == 'MyCoachSection.cancelCoach' &&
            '${f.error}'.contains('account changed')),
        isNotEmpty);
  }

  for (final (what, change) in [
    ('A -> B', () => signInAs(acctB)),
    ('A signed out', signOut),
    ("A's session ended remotely", () => expire(_server)),
  ]) {
    testWidgets('$what, confirmed with no frame between: nothing sent, nothing '
        'said', (t) async {
      await open(t);
      final button = t.widget<GestureDetector>(find
          .ancestor(
              of: find.text('Cancel Coach').last,
              matching: find.byType(GestureDetector))
          .first);
      await t.runAsync(() async {
        await change();
        _server.sent.clear();
        button.onTap!();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await settleApp(t, 8);
      expect(_server.sent.where((s) => s.url.path.contains('/rest/')), isEmpty);
      expectNothingSaid();
      await end(t);
    });

    for (final ok in [true, false]) {
      testWidgets(
          '$what while ending it, which then ${ok ? 'answers' : 'fails'}: '
          'nothing said', (t) async {
        await open(t);
        final hold = _server
            .holds['PATCH coach_client_relationships:$acctA'] = Completer<void>();
        if (!ok) {
          _server.fails['PATCH coach_client_relationships:$acctA'] = 403;
        }
        await confirm(t);
        expect(writes().map((s) => (s.name, s.who)),
            [('coach_client_relationships', acctA)],
            reason: 'premise: out, as A');
        await t.runAsync(change);
        hold.complete();
        await settleApp(t, 8);
        expectNothingSaid();
        await end(t);
      });
    }
  }

  testWidgets('cancelCoach itself says the account changed (59d): never shown, '
      'recorded', (t) async {
    await open(t);
    _server.throws['PATCH coach_client_relationships:$acctA'] =
        StateError('Ending coaching: the signed-in account changed');
    await confirm(t);
    expect(writes(), hasLength(1), reason: 'premise');
    expect(find.byType(SnackBar), findsNothing);
    expect(find.textContaining('account changed'), findsNothing);
    expect(_failures.map((f) => f.origin), ['MyCoachSection.cancelCoach']);
    await end(t);
  });

  testWidgets('"the signed-in account changed" is never shown (A -> B -> A too)',
      (t) async {
    await open(t);
    final hold =
        _server.holds['GET subscriptions:$acctA'] = Completer<void>();
    await confirm(t);
    await t.runAsync(() async {
      await signInAs(acctB);
      await signInAs(acctA);
    });
    hold.complete();
    await settleApp(t, 8);
    expect(find.textContaining('account changed'), findsNothing);
    await end(t);
  });

  for (final (what, noRow, said) in [
    ('ended', false, 'Coaching ended. Your coach has been notified.'),
    (
      'no row matched',
      true,
      'No active coaching with this coach — nothing was changed.'
    ),
  ]) {
    testWidgets('control: one account, through a token refresh ($what): as before',
        (t) async {
      _server.emptyWrites = noRow;
      await open(t);
      final hold = _server
          .holds['PATCH coach_client_relationships:$acctA'] = Completer<void>();
      await confirm(t);
      await t.runAsync(renewToken);
      hold.complete();
      await settleApp(t, 8);
      expect(find.text(said), findsOneWidget);
      expect(refreshed, 1);
      final patch = _server
          .of('coach_client_relationships', method: 'PATCH')
          .single;
      expect(patch.url.query, contains('client_id=eq.$acctA'));
      expect(patch.body, contains('Not a good fit'));
      await end(t);
    });
  }

  testWidgets('control: swiped away — nothing sent, nothing said', (t) async {
    await open(t);
    await t.tapAt(const Offset(450, 20));
    await settleApp(t, 8);
    expect(find.text('Cancel Your Coach'), findsNothing);
    expect(_server.sent.where((s) => s.url.path.contains('/rest/')), isEmpty);
    expect(find.byType(SnackBar), findsNothing);
    expect(_failures, isEmpty);
    await end(t);
  });
}
