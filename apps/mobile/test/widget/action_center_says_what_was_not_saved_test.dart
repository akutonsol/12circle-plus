// P0-FL-59e · Action Center: a complete or reopen that changed nothing is said,
// and only to the member whose task it is.
//
// `_toggle` dropped the result (S6) and a thrown reopen was an uncaught error.
//
// HOW TO SEE IT FAIL: put back 5f8b7f3's action_center_screen; every test but
// the POSITIVE CONTROL fails.
import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/action_items/presentation/action_center_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/member_switch_server.dart';

const _notDone = "Couldn't mark that action item done — it may already have "
    'changed. Pull down to refresh.';
const _notReopened = "Couldn't reopen that action item — it may already have "
    'changed. Pull down to refresh.';

void main() {
  final server = MemberSwitchServer();
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(server);
  });

  setUp(() async {
    server.reset();
    await signInAs(memberA);
    reported.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  Iterable<String> origins() => reported.map((f) => f.origin);

  Future<void> settle(WidgetTester t, [int n = 8]) async {
    for (var i = 0; i < n; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(WidgetTester t, {bool done = false}) async {
    Map<String, Object?> item(String who) => {
          'id': 'i1', 'client_id': who, 'title': 'Walk of $who',
          'status': done ? 'completed' : 'pending',
          'created_at': '2026-11-20T08:00:00Z',
        };
    server.rows['action_items'] = {
      memberA: [item(memberA)],
      memberB: [item(memberB)],
    };
    await t.pumpWidget(
        const ProviderScope(child: MaterialApp(home: ActionCenterScreen())));
    await settle(t);
    expect(find.text('Walk of $memberA'), findsOneWidget, reason: 'premise');
    server.seen.clear();
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 12));
  }

  /// The tile's tick.
  Finder tick() => find
      .descendant(
          of: find.ancestor(
              of: find.text('Walk of $memberA'), matching: find.byType(Row)),
          matching: find.byType(GestureDetector))
      .last;

  for (final done in [false, true]) {
    final what = done ? 'reopen' : 'complete';
    testWidgets('$what: 0 rows: said, and the list is read again', (t) async {
      await open(t, done: done);
      server.zeroRows.add('PATCH action_items:$memberA');
      await t.tap(tick());
      await settle(t);
      expect(find.text(done ? _notReopened : _notDone), findsOneWidget);
      expect(server.reads('action_items', memberA), hasLength(1));
      await close(t);
    });

    testWidgets('$what: A\'s answer lands after B signed in: B is not told',
        (t) async {
      await open(t, done: done);
      final hold = server.holds['PATCH action_items:$memberA'] = Completer();
      server.zeroRows.add('PATCH action_items:$memberA');
      await t.tap(tick());
      await settle(t, 2);
      await t.runAsync(() => signInAs(memberB));
      hold.complete();
      await settle(t);
      expect(origins(), isNotEmpty);
      expect(find.byType(SnackBar), findsNothing);
      await close(t);
    });

    testWidgets("$what: A's undrawn tile tapped once B is signed in: nothing is "
        'sent, nothing is said, recorded', (t) async {
      await open(t, done: done);
      await t.runAsync(() => signInAs(memberB));
      await t.tap(tick());
      await settle(t);
      expect(server.writes(), isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      expect(origins(), ['ActionCenter.identity']);
      await close(t);
    });

    testWidgets('POSITIVE CONTROL: $what: saved, nothing said, read again',
        (t) async {
      await open(t, done: done);
      await t.runAsync(refreshSession);
      await settle(t);
      server.seen.clear();
      await t.tap(tick());
      await settle(t);
      final w = server.writes('action_items').single;
      expect((w.who, w.query['client_id'], w.row['status']),
          (memberA, 'eq.$memberA', done ? 'pending' : 'completed'));
      expect(find.byType(SnackBar), findsNothing);
      expect(server.reads('action_items', memberA), hasLength(1));
      expect(reported, isEmpty);
      await close(t);
    });
  }

  for (final offline in [false, true]) {
    testWidgets(
        'reopen throws (${offline ? 'no connection' : 'refused'}): said with '
        'its next step, recorded, read again', (t) async {
      await open(t, done: true);
      (offline ? server.offline : server.fails)
          .add('PATCH action_items:$memberA');
      await t.tap(tick());
      await settle(t);
      expect(
          find.text(offline
              ? "Couldn't reopen that action item — check your connection and "
                  'try again.'
              : "Couldn't reopen that action item — try again in a moment. If "
                  'it keeps happening, contact support.'),
          findsOneWidget);
      expect(origins(), ['ActionCenter.toggle']);
      expect(server.reads('action_items', memberA), hasLength(1));
      expect(t.takeException(), isNull);
      await close(t);
    });
  }
}
