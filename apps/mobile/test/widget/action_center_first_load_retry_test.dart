// P0-FL-63d · the client Action Center says a failed first load and offers a
// Try again that reads again; the coach-side action-item read no longer turns
// a failure into an empty list.
//
// (1) /action-items drew a failed first load as one grey line — "Could not
//     load your action items" — with nothing to press: the only way back was
//     to leave the screen. It now draws the shared [SectionLoadFailure] card,
//     whose Try again re-reads `myActionItemsProvider` and is busy (and
//     disabled) while that read is in flight.
// (2) `ActionItemService.getClientActionItems` caught every error and
//     returned `[]`, so `clientActionItemsProvider` answered "none" and
//     `actionCompletionProvider` "0 of 0" for a coach whose read failed. It
//     now records the failure and rethrows.
//
// The real screen, no PaywallGate, no AccountScope; real auth transitions.
//
// HOW TO SEE IT FAIL:
//   git checkout 7b9ce5c -- lib/features/action_items/presentation/action_center_screen.dart \
//       lib/features/action_items/data/action_item_service.dart
// The first-load tests fail (no "Couldn't load your action items", no Try
// again); the coach-side tests fail (the read answers [] / (0, 0), and no
// failure is recorded). The controls pass on both.
import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/action_items/domain/action_item_provider.dart';
import 'package:circle_fitness/features/action_items/presentation/action_center_screen.dart';
import 'package:circle_fitness/features/nutrition/domain/nutrition_provider.dart'
    show ownRead;
import 'package:circle_fitness/features/workout/presentation/widgets/section_load_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/member_switch_server.dart';

const _failed = "Couldn't load your action items";
const _none = 'No action items yet';
const _key = 'GET action_items';
const _client = 'client-x';

void main() {
  final server = MemberSwitchServer();
  final reported = <AppFailure>[];
  late ProviderContainer container;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(server);
    watchAuthChanges();
  });

  Map<String, Object?> item(String who, String title,
          [String status = 'pending']) =>
      {
        'id': 'i-$title', 'client_id': who, 'title': title,
        'status': status, 'created_at': '2026-11-20T08:00:00Z',
      };

  setUp(() async {
    server.reset();
    await signInAs(memberA);
    reported.clear();
    setFailureSink(reported.add);
    server.rows['action_items'] = {
      memberA: [item(memberA, 'Walk')],
      memberB: [item(memberB, 'Swim')],
    };
  });
  tearDown(() {
    for (final h in server.holds.values) {
      if (!h.isCompleted) h.complete();
    }
    resetFailureSink();
  });

  Future<void> settle(WidgetTester t, [int n = 8]) async {
    for (var i = 0; i < n; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> mount(WidgetTester t) async {
    container = ProviderContainer();
    addTearDown(container.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ActionCenterScreen())));
    await settle(t);
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 12));
  }

  Finder tryAgain() => find.widgetWithText(TextButton, 'Try again');
  int readsOf(String who) => server.reads('action_items', who).length;

  group('client Action Center — a failed first load', () {
    testWidgets('says so with a Try again: not empty, not a spinner forever',
        (t) async {
      server.fails.add('$_key:$memberA');
      await mount(t);
      expect(find.text(_failed), findsOneWidget,
          reason: 'THE defect: a failed first load had no failure card');
      expect(find.byType(SectionLoadFailure), findsOneWidget);
      expect(tryAgain(), findsOneWidget,
          reason: 'THE defect: nothing to press but leaving the screen');
      expect(find.bySemanticsLabel('Try again: load your action items'),
          findsOneWidget);
      expect(find.text(_none), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(t.getSize(tryAgain()).height, greaterThanOrEqualTo(44));
      // Never the exception's text.
      expect(find.textContaining('SECRET'), findsNothing);
      expect(reported.map((f) => f.origin),
          contains('ActionItemService.getMyActionItems'));
      await close(t);
    });

    testWidgets('Try again reads again, busy and disabled while it is in '
        'flight; then the items', (t) async {
      server.fails.add('$_key:$memberA');
      await mount(t);
      expect(readsOf(memberA), 1, reason: 'premise');
      server.fails.clear();
      final hold = server.holds['$_key:$memberA'] = Completer();
      await t.tap(tryAgain());
      await settle(t);
      expect(readsOf(memberA), 2, reason: 'the retry really reads again');
      // Busy: the card stays, its button says Retrying and cannot fire again.
      expect(find.text(_failed), findsOneWidget);
      expect(find.bySemanticsLabel('Retrying'), findsOneWidget);
      expect(
          t.widget<TextButton>(find.descendant(
              of: find.byType(SectionLoadFailure),
              matching: find.byType(TextButton))).onPressed,
          isNull);
      await t.tap(find.bySemanticsLabel('Retrying'), warnIfMissed: false);
      await settle(t);
      expect(readsOf(memberA), 2, reason: 'a busy retry does not double fire');
      expect(find.text('Walk'), findsNothing);
      hold.complete();
      await settle(t);
      expect(find.text('Walk'), findsOneWidget);
      expect(find.text(_failed), findsNothing);
      expect(find.text(_none), findsNothing);
      await close(t);
    });

    testWidgets('a retry that fails again keeps the failure, ready to retry',
        (t) async {
      server.fails.add('$_key:$memberA');
      await mount(t);
      await t.tap(tryAgain());
      await settle(t);
      expect(readsOf(memberA), 2);
      expect(find.text(_failed), findsOneWidget);
      expect(find.bySemanticsLabel('Retrying'), findsNothing);
      expect(tryAgain(), findsOneWidget);
      expect(find.text(_none), findsNothing);
      expect(find.byType(SnackBar), findsNothing,
          reason: 'nothing was shown, so there is no refresh to say failed');
      await close(t);
    });

    testWidgets('loading and failure are distinct', (t) async {
      final hold = server.holds['$_key:$memberA'] = Completer();
      server.fails.add('$_key:$memberA');
      await mount(t);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(_failed), findsNothing);
      expect(tryAgain(), findsNothing);
      hold.complete();
      await settle(t);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text(_failed), findsOneWidget);
      await close(t);
    });

    testWidgets("A's failure, A's retry in flight at the switch to B: nothing "
        "of A's on B's screen; then B's own", (t) async {
      server.fails.add('$_key:$memberA');
      await mount(t);
      final holdA = server.holds['$_key:$memberA'] = Completer();
      final holdB = server.holds['$_key:$memberB'] = Completer();
      await t.tap(tryAgain());
      await settle(t);
      await t.runAsync(() => signInAs(memberB));
      await settle(t);
      expect(find.text(_failed), findsNothing, reason: "A's failure is not B's");
      expect(find.text('Walk'), findsNothing);
      holdA.complete();
      await settle(t);
      expect(find.text(_failed), findsNothing);
      holdB.complete();
      await settle(t);
      expect(find.text('Swim'), findsOneWidget);
      expect(find.text('Walk'), findsNothing);
      await close(t);
    });

    // P0-FL-63d r2 (UX should-fix 1): the failure card is several lines; at
    // 3x text on a 320x568 phone it was taller than the screen and pushed
    // Try again (the only way back) off it. Only RenderFlex overflow reports
    // are caught (anything else still fails the test as usual), and only
    // those of a Flex inside the Action Center count.
    testWidgets('a failed first load fits at 320x568 and 3x text: no '
        'overflow, Try again on screen and at least 44 high', (t) async {
      final seen = <String>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (d) {
        final text = d.toString();
        if (d.exception is FlutterError &&
            d.library == 'rendering library' &&
            text.contains('A RenderFlex overflowed by')) {
          seen.add(text);
        } else {
          previous?.call(d);
        }
      };
      addTearDown(() => FlutterError.onError = previous);
      t.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(320, 568);
      t.platformDispatcher.textScaleFactorTestValue = 3.0;
      addTearDown(t.view.reset);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);

      server.fails.add('$_key:$memberA');
      await mount(t);
      expect(find.text(_failed), findsOneWidget, reason: 'premise');
      final ids = t
          .renderObjectList(find.descendant(
              of: find.byType(ActionCenterScreen),
              matching: find.bySubtype<Flex>()))
          .map(describeIdentity)
          .toSet();
      final mine = [
        for (final e in seen)
          if (ids.any((id) =>
              e.contains('$id ') || e.contains('$id\n') || e.contains('$id:')))
            e
      ];
      expect(mine, isEmpty,
          reason: 'the failure card does not overflow at 3x on 320dp');
      await t.ensureVisible(tryAgain());
      await settle(t, 2);
      final r = t.getRect(tryAgain());
      expect(r.top, greaterThanOrEqualTo(0));
      expect(r.bottom, lessThanOrEqualTo(568),
          reason: 'Try again can be brought on screen');
      expect(tryAgain().hitTestable(), findsOneWidget);
      expect(r.height, greaterThanOrEqualTo(44));
      // It still works from there.
      await t.tap(tryAgain());
      await settle(t);
      expect(readsOf(memberA), 2);
      await close(t);
    });

    testWidgets('POSITIVE CONTROL: a normal load, then completing a task '
        'writes once, for this member, and reads again', (t) async {
      await mount(t);
      expect(find.text('Walk'), findsOneWidget);
      expect(find.byType(SectionLoadFailure), findsNothing);
      server.seen.clear();
      await t.tap(find
          .descendant(
              of: find.ancestor(
                  of: find.text('Walk'), matching: find.byType(Row)),
              matching: find.byType(GestureDetector))
          .last);
      await settle(t);
      final writes = server.writes('action_items').toList();
      expect(writes, hasLength(1));
      expect(writes.single.method, 'PATCH');
      expect(writes.single.who, memberA);
      expect(writes.single.query['client_id'], 'eq.$memberA');
      expect(writes.single.query['id'], 'eq.i-Walk');
      expect(readsOf(memberA), 1, reason: 'the list is read again after it');
      expect(find.byType(SnackBar), findsNothing);
      await close(t);
    });

    testWidgets('POSITIVE CONTROL: a refresh that fails after a load keeps '
        'the items and says so (unchanged)', (t) async {
      await mount(t);
      server.fails.add('$_key:$memberA');
      await t.drag(find.byType(ListView), const Offset(0, 400));
      await settle(t);
      expect(find.text('Walk'), findsOneWidget);
      expect(find.byType(SectionLoadFailure), findsNothing);
      expect(find.textContaining("Couldn't refresh your action items"),
          findsOneWidget);
      await close(t);
    });
  });

  group('coach side — a failed read is not an empty list', () {
    late ProviderContainer c;
    setUp(() {
      server.rows['action_items'] = {
        memberA: [item(_client, 'Walk'), item(_client, 'Row', 'completed')],
      };
      c = ProviderContainer();
    });
    tearDown(() => c.dispose());

    Future<void> settled() =>
        Future<void>.delayed(const Duration(milliseconds: 120));

    test('the items read fails: a failure, recorded once, never []', () async {
      server.fails.add('$_key:$memberA');
      final p = clientActionItemsProvider(_client);
      c.listen(p, (_, __) {});
      await settled();
      final own = ownRead(c.read(p));
      expect(own.value, isNull,
          reason: 'THE defect: the failure was answered as no items');
      expect(own.error, isNotNull);
      expect(own.error.toString(), isNot(contains('[]')));
      expect(
          reported
              .where((f) => f.origin == 'ActionItemService.getClientActionItems'),
          hasLength(1));
    });

    test('the completion read fails: a failure, not "0 of 0"', () async {
      server.fails.add('$_key:$memberA');
      final p = actionCompletionProvider(_client);
      c.listen(p, (_, __) {});
      await settled();
      final own = ownRead(c.read(p));
      expect(own.value, isNull,
          reason: 'THE defect: a failed read was "0 assigned, 0 completed"');
      expect(own.error, isNotNull);
    });

    test('a re-read after the failure gives the items', () async {
      server.fails.add('$_key:$memberA');
      final p = clientActionItemsProvider(_client);
      c.listen(p, (_, __) {});
      await settled();
      server.fails.clear();
      c.invalidate(p);
      await settled();
      expect(ownRead(c.read(p)).value?.map((i) => i.title), ['Walk', 'Row']);
    });

    // P0-FL-63d r2 (QA should-fix 2): the coach read can now really fail, so
    // coach A's failure is an AsyncError Riverpod keeps through coach B's
    // read of the same client. It is A's (tagged with A): drawn through
    // ownRead it is nothing for B — not a failure, not data — and B then
    // gets B's own answer, read as B.
    List<SeenRequest> readsAs(String who) => server.seen
        .where((r) => r.isRead && r.target == 'action_items' && r.who == who)
        .toList();

    test("coach A's failure is not drawn for coach B reading the same "
        "client; B gets B's own answer", () async {
      server.rows['action_items']![memberB] = [item(_client, 'Swim')];
      server.fails.add('$_key:$memberA');
      final p = clientActionItemsProvider(_client);
      final s = actionCompletionProvider(_client);
      c.listen(p, (_, __) {});
      c.listen(s, (_, __) {});
      await settled();
      expect(ownRead(c.read(p)).error, isNotNull,
          reason: "premise: A's read failed (on base it was answered [])");
      expect(ownRead(c.read(s)).error, isNotNull, reason: 'premise');
      int recorded() => reported
          .where((f) => f.origin == 'ActionItemService.getClientActionItems')
          .length;
      final beforeB = recorded();
      expect(beforeB, greaterThan(0), reason: "A's failure was recorded");
      final holdB = server.holds['$_key:$memberB'] = Completer();
      await signInAs(memberB);
      await settled();
      // B's read is in flight: Riverpod still holds A's AsyncError.
      expect(c.read(p).error, isNotNull,
          reason: "premise: Riverpod keeps A's failure through B's read");
      for (final read in [ownRead(c.read(p)), ownRead(c.read(s))]) {
        expect(read.error, isNull, reason: "A's failure is not B's");
        expect(read.value, isNull, reason: 'and B has no answer yet');
      }
      holdB.complete();
      await settled();
      expect(ownRead(c.read(p)).value?.map((i) => i.title), ['Swim']);
      expect(ownRead(c.read(p)).error, isNull);
      final stats = ownRead(c.read(s)).value!;
      expect((stats.assigned, stats.completed), (1, 0));
      final asB = readsAs(memberB);
      expect(asB, isNotEmpty, reason: 'B read as B');
      expect(asB.every((r) => r.query['client_id'] == 'eq.$_client'), isTrue);
      expect(recorded(), beforeB, reason: "B's reads succeeded: nothing more");
    });

    test("coach A's failure landing after the switch to B is not B's",
        () async {
      server.rows['action_items']![memberB] = [item(_client, 'Swim')];
      server.fails.add('$_key:$memberA');
      final holdA = server.holds['$_key:$memberA'] = Completer();
      final holdB = server.holds['$_key:$memberB'] = Completer();
      final p = clientActionItemsProvider(_client);
      c.listen(p, (_, __) {});
      await settled();
      expect(readsAs(memberA), hasLength(1), reason: 'premise');
      await signInAs(memberB);
      await settled();
      holdA.complete();
      await settled();
      expect(ownRead(c.read(p)).error, isNull,
          reason: "A's late failure is not drawn for B");
      expect(ownRead(c.read(p)).value, isNull);
      holdB.complete();
      await settled();
      expect(ownRead(c.read(p)).value?.map((i) => i.title), ['Swim']);
    });

    test('POSITIVE CONTROL: a normal read and its completion', () async {
      final p = clientActionItemsProvider(_client);
      final s = actionCompletionProvider(_client);
      c.listen(p, (_, __) {});
      c.listen(s, (_, __) {});
      await settled();
      expect(ownRead(c.read(p)).value, hasLength(2));
      final stats = ownRead(c.read(s)).value!;
      expect((stats.assigned, stats.completed), (2, 1));
      expect(reported, isEmpty);
    });
  });
}
