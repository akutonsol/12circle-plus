import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/habits/data/habit_reminder_service.dart';
import 'package:circle_fitness/features/habits/data/models/habit_model.dart';
import 'package:circle_fitness/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/account_app.dart';
import '../support/pump_until.dart';

// P0-FL-59a (d) — a member's habit reminders leave the device with them
// (A-22 / E15).
//
// `HabitReminderService.cancelAll()` had no caller: after A signed out, A's
// habit names and streak kept arriving as daily OS notifications on B's device
// until B opened Habits. And a schedule still running when the account changed
// carried on putting A's reminders back.

const _channel = MethodChannel('dexterous.com/flutter/local_notifications');

final _server = AccountServer();
final _realtime = FakeRealtime();
final _failures = <AppFailure>[];

/// The device: what is scheduled, and what it was asked.
final _scheduled = <int, String>{};
final _calls = <String>[];

/// Runs on the nth call of a method.
Future<void> Function(String method, int nth)? _onCall;

Habit _habit(String name) => Habit(
      id: name,
      name: name,
      emoji: 'x',
      category: HabitCategory.health,
      targetValue: 1,
      unit: 'times',
      currentStreak: 3,
      longestStreak: 3,
      completedDates: const [],
      isCompletedToday: false,
      currentValue: 0,
      reminderTime: '08:30',
    );

final _threeOfA = [for (final n in ['A-one', 'A-two', 'A-three']) _habit(n)];

void main() {
  final service = HabitReminderService();

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    final counts = <String, int>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      _calls.add(call.method);
      await _onCall?.call(
          call.method, counts.update(call.method, (n) => n + 1, ifAbsent: () => 1));
      switch (call.method) {
        case 'initialize':
        case 'requestNotificationsPermission':
          return true;
        case 'cancel':
          final id = (call.arguments as Map)['id'] as int;
          _scheduled.remove(id);
        case 'zonedSchedule':
          final args = call.arguments as Map;
          _scheduled[args['id'] as int] = args['title'] as String;
      }
      return null;
    });
    await initAccountSupabase(_server, _realtime, MemoryStore());
    await service.initialize();
  });

  setUp(() async {
    _server.reset();
    _scheduled.clear();
    _calls.clear();
    _failures.clear();
    _onCall = null;
    setFailureSink(_failures.add);
    addTearDown(resetFailureSink);
    await signInAs(acctA);
  });

  tearDown(() async {
    _onCall = null;
    await signOut();
  });

  test('control: the same account\'s reminders are scheduled, each once',
      () async {
    await service.scheduleHabitReminders(_threeOfA);
    expect(_scheduled.values.map((t) => t.split(' ').last),
        ['A-one!', 'A-two!', 'A-three!']);
    expect(_calls.where((c) => c == 'zonedSchedule'), hasLength(3));
  });

  test('control: no habits leaves none scheduled, and records no failure',
      () async {
    await service.scheduleHabitReminders(_threeOfA);
    await service.scheduleHabitReminders(const []);
    expect(_scheduled, isEmpty);
    expect(_failures, isEmpty);
  });

  for (final (what, change) in [
    ('A -> B', () => signInAs(acctB)),
    ('A signs out', signOut),
  ]) {
    test('$what mid-schedule: the rest of A\'s are not scheduled', () async {
      var done = false;
      _onCall = (method, _) async {
        if (method != 'zonedSchedule' || done) return;
        done = true;
        await change();
      };
      await service.scheduleHabitReminders(_threeOfA);
      expect(_scheduled, isEmpty,
          reason: 'the one already on its way is taken back too');
      expect(_calls.where((c) => c == 'zonedSchedule'), hasLength(1));
    });
  }

  test('cancelAll while A\'s schedule runs: nothing of A\'s ends up scheduled '
      '(A -> out -> A included)', () async {
    var done = false;
    Future<void>? cancelling;
    _onCall = (method, _) async {
      if (method != 'zonedSchedule' || done) return;
      done = true;
      await signOut();
      cancelling = service.cancelAll();
      await signInAs(acctA); // A again: the uid check alone would carry on
    };
    await service.scheduleHabitReminders(_threeOfA);
    await cancelling;
    expect(_scheduled, isEmpty,
        reason: 'the one already on its way is cancelled too');
    expect(_calls.where((c) => c == 'zonedSchedule'), hasLength(1));
  });

  test("B's schedule while A's cancelAll still runs: B's reminders survive",
      () async {
    await service.scheduleHabitReminders(_threeOfA);
    await signInAs(acctB);
    final cancelling = service.cancelAll();
    await service.scheduleHabitReminders([_habit('B-one'), _habit('B-two')]);
    await cancelling;
    expect(_scheduled.values.map((t) => t.split(' ').last),
        ['B-one!', 'B-two!']);
  });

  test('one that cannot be cancelled: the rest are, and it is recorded once',
      () async {
    await service.scheduleHabitReminders(_threeOfA);
    var first = true;
    _onCall = (method, _) async {
      if (method == 'cancel' && first) {
        first = false;
        throw PlatformException(code: 'nope');
      }
    };
    await service.cancelAll();
    expect(_scheduled.values.map((t) => t.split(' ').last), ['A-one!']);
    expect(_failures.map((f) => f.origin), ['HabitReminderService.cancelAll']);
  });

  for (final (what, change) in [
    ('A -> B', () => signInAs(acctB)),
    ('A signs out', signOut),
    ("A's session ends remotely", () => expire(_server)),
  ]) {
    testWidgets('the app root: $what takes A\'s reminders off the device',
        (t) async {
      try {
        await t.runAsync(() => signInAs(acctA));
        await t.runAsync(() => service.scheduleHabitReminders(_threeOfA));
        expect(_scheduled, hasLength(3), reason: 'premise');
        await t.pumpWidget(CircleFitnessRoot(theme: ThemeData.dark()));
        await settleApp(t, 3);
        await t.runAsync(_refresh);
        await settleApp(t, 3);
        expect(_scheduled, hasLength(3), reason: 'control: same member');
        await t.runAsync(change);
        await pumpUntil(t, () => _scheduled.isEmpty,
            what: "A's reminders to be cancelled");
        expect(_failures.where((f) => f.origin.contains('Habit')), isEmpty);
      } finally {
        await unmountApp(t, _server);
      }
    });
  }
}

Future<void> _refresh() => signInAs(acctA);
