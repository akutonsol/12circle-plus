import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/notifications/data/notification_model.dart';
import 'package:circle_fitness/features/notifications/domain/notification_provider.dart';
import 'package:circle_fitness/features/notifications/presentation/notifications_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/owned_rows_postgrest.dart';
import '../support/quiet_realtime.dart';
import '../support/settled.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-60c round 2 (B1) · A control drawn for member A acted for member B when
// B had signed in and no frame had run yet: it read the notifier at the tap, and
// that is B's. "Mark all read" marked B's notifications read.
//
// The RENDERED callbacks are invoked, with no frame after the switch, so nothing
// here depends on a rebuild or on AccountScope.
//
// HOW TO SEE IT FAIL: `git checkout fd5d076 --` lib/features/notifications.

const _t = 'notifications';

Map<String, Object?> _n(String id, String uid, String title) => {
      'id': id, 'recipient_id': uid, 'type': 'general', 'title': title,
      'body': 'Body', 'read': false,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };

void main() {
  final server = OwnedRowsPostgrest();
  final reported = <AppFailure>[];
  late ProviderContainer c;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabaseQuietly(server);
  });

  setUp(() async {
    server.reset();
    server.rows[_t] = [
      _n('a-1', memberA, 'For A one'),
      _n('a-2', memberA, 'For A two'),
      _n('b-1', memberB, 'For B'),
    ];
    reported.clear();
    setFailureSink(reported.add);
    await signInAs(memberA);
    c = ProviderContainer();
  });

  tearDown(() {
    c.dispose();
    resetFailureSink();
  });

  Finder text(String s) => find.text(s);
  String? signedIn() => Supabase.instance.client.auth.currentUser?.id;
  Map<String, Object?> row(String id) =>
      server.rows[_t]!.firstWhere((r) => r['id'] == id);
  Iterable<AppFailure> accountChanged() => reported
      .where((f) => '${f.error}'.contains('the signed-in account changed'));

  Future<void> settle(WidgetTester tester) => settledFrames(tester, server,
      step: const Duration(milliseconds: 50));

  /// Real time passes and answers land; no frame runs.
  Future<void> noFrame(WidgetTester tester) => settledNoFrame(tester, server);

  Future<void> create(WidgetTester tester) => tester.runAsync(() async {
        if (!c.exists(notificationsProvider)) {
          c.listen(notificationsProvider, (_, __) {});
        }
        c.read(notificationsProvider);
        await settled(server);
      });

  Future<void> show(WidgetTester tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 1800);
    addTearDown(tester.view.reset);
    await create(tester);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c, child: const MaterialApp(home: NotificationsScreen())));
    await settle(tester);
  }

  Future<void> become(WidgetTester tester, String? uid) async {
    await tester.runAsync(() async {
      await (uid == null ? signOut() : signInAs(uid));
      await eventually(() => c.read(currentUserProvider)?.id, uid,
          reason: 'premise');
    });
    await create(tester);
    await settle(tester);
  }

  Future<void> done(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
    await tester.runAsync(() async {
      c.dispose();
      await settled(server);
    });
    await tester.pump(const Duration(minutes: 2));
  }

  // What is on screen, as it was built.
  GestureTapCallback tapOf(WidgetTester tester, String label) => tester
      .widget<GestureDetector>(find
          .ancestor(of: text(label), matching: find.byType(GestureDetector))
          .first)
      .onTap!;
  ConfirmDismissCallback swipeOf(WidgetTester tester, String title) => tester
      .widget<Dismissible>(
          find.ancestor(of: text(title), matching: find.byType(Dismissible)))
      .confirmDismiss!;

  /// The three rendered controls: how to press each, and what it sends.
  final controls = <(
    String,
    void Function(WidgetTester),
    String,
    bool Function(),
  )>[
    ('Mark all read', (t) => tapOf(t, 'Mark all read')(), 'PATCH',
        () => row('a-1')['read']! as bool),
    ('a row', (t) => tapOf(t, 'For A one')(), 'PATCH',
        () => row('a-1')['read']! as bool),
    ('a swipe', (t) => swipeOf(t, 'For A one')(DismissDirection.endToStart),
        'DELETE', () => server.rows[_t]!.every((r) => r['id'] != 'a-1')),
  ];

  Future<void> press(
          WidgetTester tester, void Function(WidgetTester) control) =>
      tester.runAsync(() async {
        control(tester);
        await settled(server);
      });

  for (final (name, control, method, took) in controls) {
    for (final to in [memberB, null]) {
      testWidgets(
          "$name, drawn for A, pressed with ${to == null ? 'nobody' : 'B'} "
          'signed in and no frame since: nothing is sent, nothing is said',
          (tester) async {
        await show(tester);
        await tester.runAsync(() => to == null ? signOut() : signInAs(to));
        expect(signedIn(), to, reason: 'premise');
        expect(text('For A one'), findsOneWidget, reason: 'premise: no frame');

        await press(tester, control);
        expect(server.writes(_t), isEmpty,
            reason: 'THE defect: a control of A acted for B');
        expect(row('b-1')['read'], isFalse);
        expect(accountChanged(), hasLength(1), reason: 'recorded');

        await create(tester);
        await settle(tester);
        expect(find.textContaining("Couldn't"), findsNothing,
            reason: "THE defect: B was told about A's row");
        expect(text('For A one'), findsNothing);
        if (to == memberB) expect(text('For B'), findsOneWidget);
        await done(tester);
      });
    }

    testWidgets('control: $name works for the same member, across a token refresh',
        (tester) async {
      await show(tester);
      final before = c.read(currentUserProvider);
      await tester.runAsync(() async {
        await refreshSession();
        await eventually(
            () => identical(c.read(currentUserProvider), before), isFalse,
            reason: 'premise: the event arrived');
      });
      await press(tester, control);
      await settle(tester);
      expect(server.writes(_t).map((w) => '${w.method} ${w.who}'),
          ['$method $memberA']);
      expect(took(), isTrue);
      expect(row('b-1')['read'], isFalse);
      expect(find.textContaining("Couldn't"), findsNothing);
      await done(tester);
    });

    testWidgets("$name in flight, failing, across A->B with no frame: B is not told",
        (tester) async {
      final hold = server.holds['$method $_t:$memberA'] = Completer<void>();
      server.fails.add('$method $_t:$memberA');
      await show(tester);
      await press(tester, control);
      expect(server.writes(_t), hasLength(1), reason: 'premise');
      await tester.runAsync(() => signInAs(memberB));
      hold.complete();
      await noFrame(tester);
      await create(tester);
      await settle(tester);
      expect(find.textContaining("Couldn't"), findsNothing);
      expect(reported.map((f) => f.origin),
          contains(startsWith('NotificationsNotifier.')));
      expect(server.writes(_t).map((w) => w.who), [memberA]);
      expect(text('For B'), findsOneWidget);
      await done(tester);
    });

    testWidgets("$name in flight, taken, across A->B: B's list is B's",
        (tester) async {
      final hold = server.holds['$method $_t:$memberA'] = Completer<void>();
      await show(tester);
      await press(tester, control);
      await become(tester, memberB);
      hold.complete();
      await settle(tester);
      expect(took(), isTrue);
      expect(row('b-1')['read'], isFalse);
      expect(server.writes(_t).map((w) => w.who), [memberA]);
      expect(text('For B'), findsOneWidget);
      expect(find.textContaining('Unread'), findsOneWidget);
      expect(find.textContaining("Couldn't"), findsNothing);
      await done(tester);
    });
  }

  // Lead mutant 60c-9: `_saySo` without its owner check (`if (!ok) {`). A's
  // change is SENT as A and held; B signs in; A's write then fails. The
  // failure is A's: it is recorded, and B is told nothing of it — with frames
  // between (B's list built) and with none. The control: the same failure with
  // no switch is said, once.
  final ops = <(String, void Function(WidgetTester), String, String)>[
    ('mark read', (t) => tapOf(t, 'For A one')(), 'PATCH', 'markRead'),
    ('mark all read', (t) => tapOf(t, 'Mark all read')(), 'PATCH', 'markAllRead'),
    ('delete',
        (t) => swipeOf(t, 'For A one')(DismissDirection.endToStart),
        'DELETE', 'delete'),
  ];
  for (final (name, control, method, origin) in ops) {
    for (final frames in [true, false]) {
      testWidgets(
          "A's $name sent, held, B signs in ${frames ? 'with frames' : 'with no frame'}, "
          "then A's write fails: recorded, and B sees nothing of it",
          (tester) async {
        final hold = server.holds['$method $_t:$memberA'] = Completer<void>();
        server.fails.add('$method $_t:$memberA');
        await show(tester);
        await press(tester, control);
        expect(server.writes(_t).map((w) => '${w.method} ${w.who}'),
            ['$method $memberA'], reason: 'premise: sent as A');
        if (frames) {
          await become(tester, memberB);
          expect(text('For B'), findsOneWidget, reason: "premise: B's list");
        } else {
          await tester.runAsync(() => signInAs(memberB));
        }
        expect(signedIn(), memberB, reason: 'premise');
        hold.complete();
        if (frames) {
          await settle(tester);
        } else {
          await noFrame(tester);
          await create(tester);
          await settle(tester);
        }
        expect(reported.map((f) => f.origin),
            contains('NotificationsNotifier.$origin'),
            reason: 'the failure is still recorded');
        expect(find.byType(SnackBar), findsNothing,
            reason: "THE defect: B was shown A's failure");
        expect(find.textContaining("Couldn't"), findsNothing,
            reason: "THE defect: B was told A's change failed");
        expect(text('For A one'), findsNothing);
        expect(text('For B'), findsOneWidget);
        expect(row('b-1')['read'], isFalse);
        expect(server.writes(_t).map((w) => w.who), [memberA]);
        await done(tester);
      });
    }

    testWidgets("control: A's $name held then failing, no switch, is said once",
        (tester) async {
      final hold = server.holds['$method $_t:$memberA'] = Completer<void>();
      server.fails.add('$method $_t:$memberA');
      await show(tester);
      await press(tester, control);
      hold.complete();
      await settle(tester);
      expect(reported.map((f) => f.origin),
          contains('NotificationsNotifier.$origin'));
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining("Couldn't"), findsOneWidget,
          reason: 'the same failure, for its owner, is said once');
      expect(text('For A one'), findsOneWidget, reason: 'still there');
      await done(tester);
    });
  }

  testWidgets("mark all: the re-count after no row changed is not asked as B",
      (tester) async {
    server.filtered.add('PATCH $_t:$memberA');
    final hold = server.holds['PATCH $_t:$memberA'] = Completer<void>();
    await show(tester);
    await press(tester, (t) => tapOf(t, 'Mark all read')());
    final before = server.log.length;
    await tester.runAsync(() => signInAs(memberB));
    hold.complete();
    await noFrame(tester);
    expect(
        server.log.skip(before).where((a) =>
            a.query['recipient_id'] == 'eq.$memberA' && a.who == memberB),
        isEmpty,
        reason: "THE defect: A's rows were asked for with B's session");
    expect(accountChanged(), hasLength(1));
    await create(tester);
    await done(tester);
  });

  for (final afterB in [false, true]) {
    testWidgets("A's held read landing ${afterB ? 'after' : 'before'} B's is dropped",
        (tester) async {
      final holdA = server.holds['GET $_t:$memberA'] = Completer<void>();
      final holdB = server.holds['GET $_t:$memberB'] = Completer<void>();
      await show(tester);
      await become(tester, memberB);
      if (afterB) {
        holdB.complete();
        await settle(tester);
        expect(text('For B'), findsOneWidget);
      }
      holdA.complete();
      await settle(tester);
      expect(text('For A one'), findsNothing);
      if (!afterB) {
        expect(text('For B'), findsNothing);
        holdB.complete();
      }
      await settle(tester);
      expect(text('For B'), findsOneWidget);
      expect(text('For A one'), findsNothing);
      await done(tester);
    });
  }

  testWidgets("A's refresh in flight when B signs in, B's read pending: "
      "nothing of A's, and A's late answer changes nothing", (tester) async {
    Iterable<Asked> reads(String uid) =>
        server.log.where((a) => a.method == 'GET' && a.who == uid);
    await show(tester);
    expect(text('For A one'), findsOneWidget, reason: 'premise');
    final holdA = server.holds['GET $_t:$memberA'] = Completer<void>();
    final holdB = server.holds['GET $_t:$memberB'] = Completer<void>();
    final asked = reads(memberA).length;
    await tester.runAsync(() async {
      unawaited(c.read(notificationsProvider.notifier).refresh());
      await settled(server);
    });
    await settle(tester);
    expect(reads(memberA).length, greaterThan(asked),
        reason: 'premise: in flight');
    expect(text('For A one'), findsOneWidget, reason: 'control: A keeps it');
    await become(tester, memberB);
    expect(text('For A one'), findsNothing,
        reason: "THE defect: A's notifications were shown to B");
    expect(reads(memberB), isNotEmpty, reason: "premise: B's is pending");
    holdA.complete();
    await settle(tester);
    expect(text('For A one'), findsNothing);
    expect(find.textContaining("Couldn't"), findsNothing);
    holdB.complete();
    await settle(tester);
    expect(text('For B'), findsOneWidget);
    expect(text('For A one'), findsNothing);
    await done(tester);
  });

  testWidgets("A's held reads landing with B signed in and nothing flushed",
      (tester) async {
    // The list's own read and the live feed's: both are A's, both are dropped.
    final hold = server.holds['GET $_t:$memberA'] = Completer<void>();
    await show(tester);
    late AsyncValue<List<AppNotification>> kept;
    c.read(notificationsProvider.notifier).addListener((s) => kept = s);
    await tester.runAsync(() => signInAs(memberB));
    hold.complete();
    await noFrame(tester);
    expect(kept.hasValue, isFalse,
        reason: "A's rows were published with B signed in");
    await create(tester);
    await settle(tester);
    expect(text('For B'), findsOneWidget);
    await done(tester);
  });

  testWidgets("a list invalidated before the switch is flushed is B's",
      (tester) async {
    await show(tester);
    final hold = server.holds['GET $_t:$memberB'] = Completer<void>();
    await tester.runAsync(() async {
      await signInAs(memberB);
      c.invalidate(notificationsProvider); // no frame, nothing flushed
      final AsyncValue<List<AppNotification>> s = c.read(notificationsProvider);
      expect(s.hasValue, isFalse);
      await settled(server);
    });
    await settle(tester);
    expect(text('For A one'), findsNothing);
    hold.complete();
    await settle(tester);
    expect(text('For B'), findsOneWidget);
    await done(tester);
  });

  testWidgets('a mark read that worked keeps the "couldn\'t load" notice',
      (tester) async {
    await show(tester);
    server.fails.add('GET $_t:$memberA');
    await tester.runAsync(() => c.read(notificationsProvider.notifier).refresh());
    await settle(tester);
    expect(text("Couldn't load your latest notifications"), findsOneWidget,
        reason: 'premise');
    await tester.tap(text('For A one'));
    await settle(tester);
    expect(find.textContaining('Unread'), findsOneWidget);
    expect(text("Couldn't load your latest notifications"), findsOneWidget,
        reason: 'THE defect: the list is as old as it was');
    server.fails.clear();
    await tester.tap(text('Try again'));
    await settle(tester);
    expect(find.textContaining("Couldn't"), findsNothing);
    await done(tester);
  });

  testWidgets('"Mark all read" is a named button of 44px, and sends once',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final hold = server.holds['PATCH $_t:$memberA'] = Completer<void>();
    await show(tester);
    final target = find
        .ancestor(of: text('Mark all read'), matching: find.byType(GestureDetector))
        .first;
    expect(tester.getSize(target).height, greaterThanOrEqualTo(44),
        reason: 'THE defect: about 28px');
    expect(tester.getSemantics(target),
        matchesSemantics(label: 'Mark all read', isButton: true, hasTapAction: true));
    final tap = tapOf(tester, 'Mark all read');
    tap();
    tap(); // the same frame
    await settle(tester);
    await tester.tap(text('Mark all read'));
    await settle(tester);
    expect(server.writes(_t), hasLength(1),
        reason: 'THE defect: every tap sent another change');
    expect(find.bySemanticsLabel('Marking all read'), findsOneWidget);
    hold.complete();
    await settle(tester);
    expect(row('a-2')['read'], isTrue);
    await tester.tap(text('Mark all read'));
    await settle(tester);
    expect(server.writes(_t), hasLength(2), reason: 'and it can be used again');
    semantics.dispose();
    await done(tester);
  });

  testWidgets("A's mark all on its way does not hold B's control", (tester) async {
    final hold = server.holds['PATCH $_t:$memberA'] = Completer<void>();
    await show(tester);
    await tester.tap(text('Mark all read'));
    await settle(tester);
    await become(tester, memberB);
    await tester.tap(text('Mark all read'));
    await settle(tester);
    expect(server.writes(_t).map((w) => w.who), [memberA, memberB]);
    expect(row('b-1')['read'], isTrue);
    hold.complete();
    await settle(tester);
    await done(tester);
  });
}
