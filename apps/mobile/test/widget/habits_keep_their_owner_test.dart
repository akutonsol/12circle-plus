// P0-FL-59e · a habit of one member's is never logged, or added, as another's.
//
// `HabitCard` reads the notifier at the TAP. Once the next member's habits have
// loaded, that is THEIR notifier: its owner check passed, and an id it did not
// have was logged anyway ("orElse: habits.first"). The add sheet (W28) saved as
// whoever was signed in by then.
//
// The real provider, card, screen and sheet; real auth transitions; no
// AccountScope. The request log says whose token wrote which row.
//
// HOW TO SEE IT FAIL: put back 5f8b7f3's habit_provider, habit_card and
// habit_screen; every test fails but the POSITIVE CONTROLs and these, which
// hold there and fail on a82f993: "A's value answers after B signed in", "A's
// tick fails after B signed in". ("nobody is signed in" with the add sheet
// holds on both: addCustomHabit sends nothing signed out.)
import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/habits/data/models/habit_model.dart';
import 'package:circle_fitness/features/habits/domain/habit_provider.dart';
import 'package:circle_fitness/features/habits/presentation/habit_screen.dart';
import 'package:circle_fitness/features/habits/presentation/widgets/habit_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/member_switch_server.dart';

void main() {
  final server = MemberSwitchServer();
  final reported = <AppFailure>[];
  late ProviderContainer c;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dexterous.com/flutter/local_notifications'),
            (call) async => call.method == 'initialize' ? true : null);
    await initTwoMemberSupabase(server);
    watchAuthChanges();
  });

  setUp(() async {
    server.reset();
    await signInAs(memberA);
    reported.clear();
    setFailureSink(reported.add);
    Map<String, Object?> habit(String id, {int target = 1}) =>
        {'id': id, 'name': 'Walk $id', 'target_value': target};
    server.rows['client_habits'] = {
      memberA: [habit('a1'), habit('a8', target: 8)],
      memberB: [habit('b1'), habit('b8', target: 8)],
    };
  });
  tearDown(resetFailureSink);

  Iterable<String> origins() => reported.map((f) => f.origin);
  Iterable<SeenRequest> asB() => server.writes().where((w) => w.who == memberB);

  Future<void> settle(WidgetTester t, [int n = 8]) async {
    for (var i = 0; i < n; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 12));
  }

  Future<void> until(bool Function() done, String what) async {
    final clock = Stopwatch()..start();
    while (!done()) {
      if (clock.elapsed > const Duration(seconds: 10)) fail('never: $what');
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
  }

  List<Habit>? shown() => c.read(liveHabitNotifierProvider).valueOrNull;

  ProviderContainer listened() {
    c = ProviderContainer();
    addTearDown(c.dispose);
    c.listen(liveHabitNotifierProvider, (_, __) {});
    return c;
  }

  /// B signs in and B's own habits are loaded; no frame is drawn.
  Future<void> bLoaded() async {
    await signInAs(memberB);
    await until(() => shown()?.first.id == 'b1', "B's habits");
  }

  group('through the provider', () {
    for (final toggle in [true, false]) {
      test(
          "${toggle ? 'toggleComplete' : 'updateValue'}: A's habit, asked of "
          "B's notifier: nothing is sent, not called saved, recorded, B's own "
          'list untouched', () async {
        listened();
        await until(() => shown()?.length == 2, "A's habits");
        await bLoaded();
        reported.clear();
        server.seen.clear();
        final n = c.read(liveHabitNotifierProvider.notifier);
        final saved = toggle
            ? await n.toggleComplete('a1')
            : await n.updateValue('a8', 3);
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(server.writes(), isEmpty,
            reason: "A's habit logged as B: ${server.writes().toList()}");
        expect(saved, isFalse);
        expect(origins(), ['LiveHabitNotifier.unknownHabit']);
        expect(shown()!.map((h) => (h.id, h.currentValue)),
            [('b1', 0), ('b8', 0)]);
      });
    }

    test('increment / decrement of a habit that is not there: nothing is sent, '
        'nothing is thrown', () async {
      listened();
      await until(() => shown()?.length == 2, "A's habits");
      await bLoaded();
      server.seen.clear();
      final n = c.read(liveHabitNotifierProvider.notifier);
      n.incrementValue('a8');
      n.decrementValue('a8');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(server.writes(), isEmpty);
    });

    test('a tick before the list is loaded: nothing is sent, nothing is thrown',
        () async {
      final hold = server.holds['GET client_habits:$memberA'] = Completer();
      listened();
      expect(
          await c.read(liveHabitNotifierProvider.notifier).toggleComplete('a1'),
          isFalse);
      expect(server.writes(), isEmpty);
      hold.complete();
    });

    test("updateValue: A's value answers after B signed in: theirs, nothing as "
        'B, not said', () async {
      listened();
      await until(() => shown()?.length == 2, "A's habits");
      final n = c.read(liveHabitNotifierProvider.notifier);
      final hold = server.holds['POST habit_logs:$memberA'] = Completer();
      server.fails.add('POST habit_logs:$memberA');
      final update = n.updateValue('a8', 3);
      await until(() => server.writes('habit_logs').isNotEmpty, 'the log');
      await signInAs(memberB);
      hold.complete();
      expect(await update, isTrue, reason: 'false is said to B');
      expect(server.writes('habit_logs').single.row['user_id'], memberA);
      expect(asB(), isEmpty);
      expect(origins(), contains('LiveHabitNotifier.updateValue'));
    });

    test('POSITIVE CONTROL: the same member after a token refresh: a counted '
        'habit is saved as theirs', () async {
      listened();
      await until(() => shown()?.length == 2, "A's habits");
      await refreshSession();
      expect(
          await c.read(liveHabitNotifierProvider.notifier).updateValue('a8', 3),
          isTrue);
      final w = server.writes('habit_logs').single;
      expect((w.who, w.row['user_id'], w.row['habit_id'], w.row['value']),
          (memberA, memberA, 'a8', 3));
      expect(shown()!.last.currentValue, 3);
      expect(reported, isEmpty);
    });
  });

  group('HabitCard', () {
    Future<void> open(WidgetTester t) async {
      listened();
      await t.runAsync(() => until(() => shown()?.length == 2, "A's habits"));
      await t.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                  children: [for (final h in shown()!) HabitCard(habit: h)]),
            ),
          ),
        ),
      ));
      await settle(t);
      server.seen.clear();
    }

    testWidgets("A's card, tapped with B's habits loaded and no frame drawn: "
        'nothing is sent, nothing celebrated or said to B', (t) async {
      await open(t);
      await t.runAsync(bLoaded);
      reported.clear();
      server.seen.clear();
      await t.tap(find.text('Walk a1'));
      await settle(t);
      expect(server.writes(), isEmpty,
          reason: "A's habit logged as B: ${server.writes().toList()}");
      expect(find.byType(SnackBar), findsNothing);
      expect(origins(), ['HabitCard.identity']);
      await close(t);
    });

    testWidgets("A's slider, moved with B's habits loaded and no frame drawn: "
        'nothing is sent or said', (t) async {
      await open(t);
      await t.runAsync(bLoaded);
      server.seen.clear();
      final slider = t.widget<Slider>(find.byType(Slider));
      reported.clear();
      slider.onChanged!(4);
      slider.onChangeEnd!(8);
      await settle(t);
      expect(server.writes(), isEmpty);
      expect(origins(), ['HabitCard.identity'], reason: 'refused at the card');
      expect(find.byType(SnackBar), findsNothing);
      await close(t);
    });

    testWidgets("A's tick fails after B signed in: B is not told", (t) async {
      await open(t);
      final hold = server.holds['POST habit_logs:$memberA'] = Completer();
      server.fails.add('POST habit_logs:$memberA');
      await t.tap(find.text('Walk a1'));
      await settle(t, 2);
      await t.runAsync(() => signInAs(memberB));
      hold.complete();
      await settle(t);
      expect(origins(), contains('LiveHabitNotifier.toggleComplete'));
      expect(find.byType(SnackBar), findsNothing);
      expect(asB(), isEmpty);
      await close(t);
    });

    for (final offline in [false, true]) {
      testWidgets(
          'a tick that is not saved (${offline ? 'no connection' : 'refused'}) '
          'is put back and says the right next step', (t) async {
        await open(t);
        (offline ? server.offline : server.fails)
            .add('POST habit_logs:$memberA');
        await t.tap(find.text('Walk a1'));
        await settle(t);
        expect(
            find.text(offline
                ? "Couldn't save that — check your connection and try again."
                : "Couldn't save that — try again in a moment. If it keeps "
                    'happening, contact support.'),
            findsOneWidget);
        expect(shown()!.first.isCompletedToday, isFalse);
        expect(origins(), ['LiveHabitNotifier.toggleComplete']);
        await close(t);
      });
    }

    testWidgets('same member, a habit that is no longer theirs: not saved is '
        'said, nothing is sent', (t) async {
      await open(t);
      server.rows['client_habits']![memberA] = [];
      await t.runAsync(
          () => c.read(liveHabitNotifierProvider.notifier).reload());
      server.seen.clear();
      await t.tap(find.text('Walk a1'));
      await settle(t);
      expect(server.writes(), isEmpty);
      expect(
          find.text("Couldn't save that — it may already have changed. Check "
              'your list of habits.'),
          findsOneWidget);
      expect(find.textContaining('ry again'), findsNothing,
          reason: 'trying again cannot help');
      await close(t);
    });

    testWidgets("invalidated before the account change is flushed: A's habits "
        "are not drawn while B's are read", (t) async {
      c = ProviderContainer();
      addTearDown(c.dispose);
      await t.pumpWidget(UncontrolledProviderScope(
          container: c, child: const MaterialApp(home: HabitScreen())));
      await settle(t);
      expect(find.text('Walk a1'), findsOneWidget, reason: 'premise');
      final hold = server.holds['GET client_habits:$memberB'] = Completer();
      await t.runAsync(() => signInAs(memberB));
      c.invalidate(liveHabitNotifierProvider);
      await settle(t);
      expect(find.text('Walk a1'), findsNothing);
      expect(c.read(liveHabitNotifierProvider).hasValue, isFalse);
      hold.complete();
      await settle(t);
      expect(find.text('Walk b1'), findsOneWidget);
      await close(t);
    });

    testWidgets('POSITIVE CONTROL: after a token refresh a tap is saved and '
        'awarded as its member', (t) async {
      await open(t);
      await t.runAsync(refreshSession);
      await t.tap(find.text('Walk a1'));
      await settle(t);
      final w = server.writes('habit_logs').single;
      expect((w.who, w.row['user_id'], w.row['habit_id']),
          (memberA, memberA, 'a1'));
      expect(server.writes('daily_scores').single.row['user_id'], memberA);
      expect(find.byType(SnackBar), findsNothing);
      expect(reported, isEmpty);
      await close(t);
    });

    testWidgets("POSITIVE CONTROL: B's own card, redrawn in the same place, is "
        'saved as B', (t) async {
      await open(t);
      await t.runAsync(bLoaded);
      await t.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                  children: [for (final h in shown()!) HabitCard(habit: h)]),
            ),
          ),
        ),
      ));
      await settle(t);
      await t.tap(find.text('Walk b1'));
      await settle(t);
      final w = server.writes('habit_logs').single;
      expect((w.who, w.row['habit_id']), (memberB, 'b1'));
      await close(t);
    });
  });

  group('New Habit (W28)', () {
    Future<void> openSheet(WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(500, 1600));
      addTearDown(() => t.binding.setSurfaceSize(null));
      listened();
      await t.pumpWidget(UncontrolledProviderScope(
          container: c, child: const MaterialApp(home: HabitScreen())));
      await settle(t);
      await t.tap(find.byIcon(Icons.add).first);
      await settle(t);
      expect(find.text('Create Habit'), findsOneWidget, reason: 'premise');
      await t.enterText(find.byType(TextField).first, "A's habit");
      await t.pump();
      server.seen.clear();
    }

    for (final signedOut in [false, true]) {
      testWidgets(
          "saved in A's undrawn sheet once ${signedOut ? 'nobody' : 'B'} is "
          'signed in: no habit, the sheet goes', (t) async {
        await openSheet(t);
        await t.runAsync(() => signedOut ? signOut() : signInAs(memberB));
        await t.tap(find.text('Create Habit'), warnIfMissed: false);
        await settle(t);
        expect(server.writes('client_habits'), isEmpty,
            reason: '${server.writes().toList()}');
        expect(find.text('Create Habit'), findsNothing);
        expect(find.text("A's habit"), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        await close(t);
      });
    }

    testWidgets('saved the instant the account changes: nothing is sent, '
        'recorded', (t) async {
      await openSheet(t);
      final save = t
          .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Create Habit'))
          .onPressed!;
      await t.runAsync(() => switchAnd(memberB, save));
      await settle(t);
      expect(server.writes('client_habits'), isEmpty);
      expect(origins(), contains('AddHabitSheet.identity'));
      await close(t);
    });

    testWidgets('opened, and switched before its first frame: never drawn for '
        'B, and it goes', (t) async {
      await openSheet(t);
      t.state<NavigatorState>(find.byType(Navigator).first).pop();
      await settle(t);
      await t.tap(find.byIcon(Icons.add).first);
      await t.runAsync(() => signInAs(memberB));
      await t.pump();
      expect(find.text('Create Habit'), findsNothing);
      await settle(t);
      expect(find.byType(ModalBarrier), findsOneWidget, reason: 'only the page');
      await close(t);
    });

    testWidgets('it closes on a switch', (t) async {
      await openSheet(t);
      await t.runAsync(() => signInAs(memberB));
      await settle(t);
      expect(find.text('Create Habit'), findsNothing);
      expect(find.byType(HabitScreen), findsOneWidget);
      await close(t);
    });

    testWidgets("A's save fails after B signed in: recorded, B is not told",
        (t) async {
      await openSheet(t);
      final hold = server.holds['POST client_habits:$memberA'] = Completer();
      server.fails.add('POST client_habits:$memberA');
      await t.tap(find.text('Create Habit'));
      await settle(t, 2);
      await t.runAsync(() => signInAs(memberB));
      hold.complete();
      await settle(t);
      expect(origins(), contains('AddHabitSheet.save'));
      expect(find.byType(SnackBar), findsNothing);
      expect(asB(), isEmpty);
      await close(t);
    });

    testWidgets('POSITIVE CONTROL: after a token refresh it is saved as its '
        'member and the list is read again', (t) async {
      await openSheet(t);
      await t.runAsync(refreshSession);
      await settle(t);
      await t.tap(find.text('Create Habit'));
      await settle(t);
      final w = server.writes('client_habits').single;
      expect((w.who, w.row['client_id'], w.row['name']),
          (memberA, memberA, "A's habit"));
      expect(find.text('Create Habit'), findsNothing);
      expect(server.reads('client_habits', memberA), isNotEmpty);
      await close(t);
    });

    testWidgets('a failed save is still said to its member, and kept',
        (t) async {
      await openSheet(t);
      server.fails.add('POST client_habits:$memberA');
      await t.tap(find.text('Create Habit'));
      await settle(t);
      expect(find.text('Failed to add habit. Please try again.'),
          findsOneWidget);
      expect(find.text("A's habit"), findsOneWidget);
      expect(origins(), ['AddHabitSheet.save']);
      await close(t);
    });
  });
}
