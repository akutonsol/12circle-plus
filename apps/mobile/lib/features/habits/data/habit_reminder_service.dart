import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'package:timezone/timezone.dart' as tz;
import '../../../core/observability/app_failure.dart';
import '../../../core/utils/web_notif.dart';
import 'models/habit_model.dart';

class HabitReminderService {
  static final HabitReminderService _instance = HabitReminderService._();
  factory HabitReminderService() => _instance;
  HabitReminderService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Bumped by every [scheduleHabitReminders] and [cancelAll]: the newest one
  /// is what the device should end up with, so an older one still running
  /// stops (P0-FL-59a, A-22).
  int _run = 0;

  /// The newest run is a [cancelAll].
  bool _cancelled = false;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'habit_reminders',
      'Habit Reminders',
      channelDescription: 'Daily reminders for your habit goals',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
  );

  Future<void> initialize() async {
    if (_initialized || kIsWeb) return;
    tz_data.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );

    // Android 13+ requires a runtime POST_NOTIFICATIONS grant
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _initialized = true;
  }

  // Fires an immediate notification — no scheduling, no exact-alarm permission needed.
  // On web uses the browser Notification API; on mobile uses flutter_local_notifications.
  Future<void> sendTestNow() async {
    if (kIsWeb) {
      await showBrowserNotification(
        '🔔 Habit Reminder Test',
        'Notifications are working! Your daily reminders are all set.',
      );
      return;
    }
    await initialize();
    await _plugin.show(
      9999,
      '🔔 Habit Reminder Test',
      'Notifications are working! Your daily reminders are all set.',
      _details,
    );
  }

  // Schedule a daily reminder for each habit that has a reminderTime set.
  // Cancels all previous habit reminders first so stale ones don't accumulate.
  //
  // They carry the member's habit names: they are scheduled only while the
  // account signed in when this was called still is.
  Future<void> scheduleHabitReminders(List<Habit> habits) async {
    if (kIsWeb) return; // browser notifications are one-shot only, no daily scheduling
    final run = ++_run;
    final owner = _signedIn;
    bool stale() => run != _run || _signedIn != owner;
    _cancelled = false;
    await initialize();
    for (int i = 1000; i < 2000; i++) {
      if (stale()) return;
      await _plugin.cancel(i);
    }

    final habitsWithReminders = habits
        .where((h) => h.reminderTime != null && h.reminderTime!.isNotEmpty)
        .toList();

    for (int i = 0; i < habitsWithReminders.length; i++) {
      final habit = habitsWithReminders[i];
      final parts = habit.reminderTime!.split(':');
      if (parts.length != 2) continue;
      final hour   = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour == null || minute == null) continue;

      await _scheduleDaily(
        id: 1000 + i,
        title: '${habit.emoji} Time for ${habit.name}!',
        body: _reminderBody(habit),
        hour: hour,
        minute: minute,
      );
      if (stale()) {
        // The one just placed went to the device as the account left. A newer
        // schedule clears every id itself (and may have reused this one).
        if (run == _run || _cancelled) await _plugin.cancel(1000 + i);
        return;
      }
    }
  }

  Future<void> _scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduled,
      _details,
      androidScheduleMode: AndroidScheduleMode.inexact,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  String _reminderBody(Habit habit) {
    if (habit.currentStreak > 0) {
      return 'Keep your ${habit.currentStreak}-day streak alive! '
          'Goal: ${habit.targetValue} ${habit.unit}';
    }
    return 'Daily goal: ${habit.targetValue} ${habit.unit}. You\'ve got this!';
  }

  String? get _signedIn => Supabase.instance.client.auth.currentUser?.id;

  /// Takes every habit reminder off this device: they are the account's that
  /// set them, and it has left (AccountScope). One that cannot be cancelled
  /// does not keep the rest; failures are recorded, never thrown. Stops when a
  /// newer schedule has begun — that one clears them all itself.
  Future<void> cancelAll() async {
    if (kIsWeb) return; // nothing is ever scheduled on web
    final run = ++_run;
    _cancelled = true;
    Object? failure;
    StackTrace? trace;
    try {
      await initialize();
      for (int i = 1000; i < 2000; i++) {
        if (run != _run) break;
        try {
          await _plugin.cancel(i);
        } catch (e, st) {
          failure ??= e;
          trace ??= st;
        }
      }
    } catch (e, st) {
      failure = e;
      trace = st;
    }
    if (failure != null) {
      reportError('HabitReminderService.cancelAll', failure, trace);
    }
  }
}
