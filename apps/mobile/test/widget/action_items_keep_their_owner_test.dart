// P0-FL-59e round 4 · one member's action items are drawn for nobody else.
//
// Action Center drew whatever the provider held: riverpod 2.6.1 does not notify
// a refresh in flight that becomes the next member's read, so A's tasks stayed
// on B's screen until something else redrew it. Its tile also spoke through a
// messenger that may be gone by then.
//
// The real screen, no PaywallGate, no AccountScope; real auth transitions.
//
// HOW TO SEE IT FAIL: put back e0736a6's action_item_provider and
// action_center_screen: "frames pumped", "a token refresh", "one that fails
// keeps it too" and "(and it fails), the tile's container disposed" fail. The
// others pin what held there by riverpod's notifications alone (and, for the
// container, that invalidate is a no-op on a disposed one).
import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/action_items/domain/action_item_provider.dart';
import 'package:circle_fitness/features/action_items/presentation/action_center_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/member_switch_server.dart';

const _couldNot = "Couldn't load your action items"; // P0-FL-63d: SectionLoadFailure
const _none = 'No action items yet';

void main() {
  final server = MemberSwitchServer();
  final reported = <AppFailure>[];
  late ProviderContainer container;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(server);
    watchAuthChanges();
  });

  setUp(() async {
    server.reset();
    await signInAs(memberA);
    reported.clear();
    setFailureSink(reported.add);
    Map<String, Object?> item(String who, String title) => {
          'id': 'i-$title', 'client_id': who, 'title': title,
          'status': 'pending', 'created_at': '2026-11-20T08:00:00Z',
        };
    server.rows['action_items'] = {
      memberA: [item(memberA, 'Walk')],
      memberB: [item(memberB, 'Swim')],
    };
  });
  tearDown(resetFailureSink);

  Future<void> settle(WidgetTester t, [int n = 8]) async {
    for (var i = 0; i < n; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> noFrame(WidgetTester t) => t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)));

  Future<void> switchTo(WidgetTester t, String uid) =>
      t.runAsync(() => signInAs(uid));

  Future<void> open(WidgetTester t) async {
    container = ProviderContainer();
    addTearDown(container.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ActionCenterScreen())));
    await settle(t);
    expect(find.text('Walk'), findsOneWidget, reason: 'premise');
    server.seen.clear();
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 12));
  }

  Future<void> pull(WidgetTester t) async {
    await t.drag(find.byType(ListView), const Offset(0, 400));
    await settle(t);
  }

  const key = 'GET action_items';

  for (final frames in [true, false]) {
    testWidgets("A's refresh in flight at the switch, "
        "${frames ? 'frames pumped' : 'no frame'}, B pending: nothing of A's, "
        "nor when A's lands; then B's", (t) async {
      await open(t);
      final holdA = server.holds['$key:$memberA'] = Completer();
      final holdB = server.holds['$key:$memberB'] = Completer();
      if (frames) {
        await pull(t);
        expect(server.reads('action_items', memberA), hasLength(1),
            reason: 'premise');
        expect(find.text('Walk'), findsOneWidget, reason: 'premise');
      } else {
        container.invalidate(myActionItemsProvider);
        unawaited(container
            .read(myActionItemsProvider.future)
            .then((_) {}, onError: (_) {}));
        await noFrame(t);
      }
      await switchTo(t, memberB);
      await settle(t);
      for (final hold in [holdA, holdB]) {
        expect(find.text('Walk'), findsNothing);
        expect(find.text(_none), findsNothing);
        expect(find.text(_couldNot), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsWidgets);
        hold.complete();
        await settle(t);
      }
      expect(find.text('Swim'), findsOneWidget);
      expect(find.text('Walk'), findsNothing);
      await close(t);
    });
  }

  testWidgets("invalidated before the switch is flushed; B's read fails: "
      "nothing of A's; B's failure is said", (t) async {
    await open(t);
    final hold = server.holds['$key:$memberB'] = Completer();
    server.fails.add('$key:$memberB');
    await switchTo(t, memberB);
    container.invalidate(myActionItemsProvider);
    await settle(t);
    expect(find.text('Walk'), findsNothing);
    hold.complete();
    await settle(t);
    expect(find.text('Walk'), findsNothing);
    expect(find.text(_couldNot), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    await close(t);
  });

  testWidgets("A's failure is not B's while B's read is pending", (t) async {
    server.fails.add('$key:$memberA');
    container = ProviderContainer();
    addTearDown(container.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ActionCenterScreen())));
    await settle(t);
    expect(find.text(_couldNot), findsOneWidget, reason: 'premise');
    final hold = server.holds['$key:$memberB'] = Completer();
    await switchTo(t, memberB);
    container.invalidate(myActionItemsProvider);
    await settle(t);
    expect(find.text(_couldNot), findsNothing);
    hold.complete();
    await settle(t);
    expect(find.text('Swim'), findsOneWidget);
    await close(t);
  });

  testWidgets("A's none is not B's while B's read is pending", (t) async {
    server.rows['action_items']!.remove(memberA);
    container = ProviderContainer();
    addTearDown(container.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ActionCenterScreen())));
    await settle(t);
    expect(find.text(_none), findsOneWidget, reason: 'premise');
    final hold = server.holds['$key:$memberB'] = Completer();
    await switchTo(t, memberB);
    container.invalidate(myActionItemsProvider);
    await settle(t);
    expect(find.text(_none), findsNothing);
    hold.complete();
    await settle(t);
    expect(find.text('Swim'), findsOneWidget);
    await close(t);
  });

  testWidgets("A -> B -> A with no frame, read as B meanwhile: A's, never B's",
      (t) async {
    await open(t);
    await t.runAsync(() => switchAnd(memberB, () {
          container.invalidate(myActionItemsProvider);
          unawaited(container.read(myActionItemsProvider.future));
        }));
    expect(server.reads('action_items', memberB), isNotEmpty,
        reason: 'premise');
    await switchTo(t, memberA);
    await t.pump();
    expect(find.text('Swim'), findsNothing);
    await settle(t);
    expect(find.text('Walk'), findsOneWidget);
    await close(t);
  });

  testWidgets("the same member's refresh keeps the list up; one that fails "
      'keeps it too, and says so', (t) async {
    await open(t);
    final hold = server.holds['$key:$memberA'] = Completer();
    await pull(t);
    expect(find.text('Walk'), findsOneWidget);
    hold.complete();
    await settle(t);
    server.fails.add('$key:$memberA');
    await pull(t);
    expect(find.text('Walk'), findsOneWidget);
    expect(
        find.text("Couldn't refresh your action items — try again in a moment. "
            'If it keeps happening, contact support.'),
        findsOneWidget);
    await close(t);
  });

  testWidgets('a token refresh keeps the list up and reads nothing again',
      (t) async {
    await open(t);
    await t.runAsync(refreshSession);
    await settle(t);
    expect(find.text('Walk'), findsOneWidget);
    expect(server.reads('action_items'), isEmpty);
    await close(t);
  });

  testWidgets("POSITIVE CONTROL (old too): B's own, then A's again", (t) async {
    await open(t);
    await switchTo(t, memberB);
    await settle(t);
    expect(find.text('Swim'), findsOneWidget);
    await switchTo(t, memberA);
    await settle(t);
    expect(find.text('Walk'), findsOneWidget);
    expect(find.text('Swim'), findsNothing);
    await close(t);
  });

  for (final fails in [false, true]) {
    testWidgets(
        'the same member signed out and in again while a task is marked done'
        "${fails ? ' (and it fails)' : ''}, the tile's container disposed: "
        'nothing is thrown', (t) async {
      await open(t);
      final hold = server.holds['PATCH action_items:$memberA'] = Completer();
      if (fails) server.fails.add('PATCH action_items:$memberA');
      await t.tap(find
          .descendant(
              of: find.ancestor(
                  of: find.text('Walk'), matching: find.byType(Row)),
              matching: find.byType(GestureDetector))
          .last);
      await noFrame(t);
      expect(server.writes('action_items'), hasLength(1), reason: 'premise');
      await t.runAsync(signOut);
      await switchTo(t, memberA);
      await t.pumpWidget(const SizedBox()); // as AccountScope replaces it
      container.dispose();
      hold.complete();
      await settle(t);
      expect(t.takeException(), isNull);
      expect(reported.map((f) => f.origin),
          fails ? ['ActionItemService.completeActionItem'] : isEmpty);
      await close(t);
    });
  }
}
