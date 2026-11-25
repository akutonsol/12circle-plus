import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../../core/identity/account_scope.dart' show signedInUid;
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

  /// The device's note of whose reminders are on it. See [sweepAtLaunch].
  static const ownerStorageKey = 'habit_reminders_owner';

  Future<void> _rememberOwner(String? uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      uid == null
          ? await prefs.remove(ownerStorageKey)
          : await prefs.setString(ownerStorageKey, uid);
    } catch (e, st) {
      reportError('HabitReminderService.rememberOwner', e, st);
    }
  }

  // Schedule a daily reminder for each habit that has a reminderTime set.
  // Cancels all previous habit reminders first so stale ones don't accumulate.
  //
  // They carry the member's habit names: they are scheduled only while the
  // account signed in when this was called still is. With nobody signed in they
  // are nobody's: none is scheduled, and any left on the device is taken off.
  // [forUid]: whose habits these are. Someone else signed in (or nobody) means
  // they came too late, and nothing is done; what is running carries on.
  Future<void> scheduleHabitReminders(List<Habit> habits, {String? forUid}) async {
    if (kIsWeb) return; // browser notifications are one-shot only, no daily scheduling
    final owner = signedInUid();
    if (forUid != null && forUid != owner) {
      reportError('HabitReminderService.schedule',
          StateError('schedule reminders: the signed-in account changed'));
      return;
    }
    if (owner == null) return cancelAll();
    final run = ++_run;
    _cancelled = false;
    await initialize();
    await _clear(run, 'HabitReminderService.schedule', owner: owner);
    if (run != _run || signedInUid() != owner) return _leave(run);

    final habitsWithReminders = habits
        .where((h) => h.reminderTime != null && h.reminderTime!.isNotEmpty)
        .toList();
    await _rememberOwner(habitsWithReminders.isEmpty ? null : owner);
    if (run != _run || signedInUid() != owner) return _leave(run);

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
      if (run != _run || signedInUid() != owner) {
        return _leave(run, placed: 1000 + i);
      }
    }
  }

  /// The end of a schedule whose account has left, or that a newer run replaced.
  /// A newer schedule clears every id itself (and may have reused [placed], the
  /// reminder that went to the device meanwhile).
  Future<void> _leave(int run, {int? placed}) async {
    if (run == _run) return cancelAll();
    if (placed == null || !_cancelled) return;
    await _cancel(placed, 'HabitReminderService.schedule');
  }

  /// Cancels every id this service uses; true when all are gone. Stops when a
  /// newer run has begun, or [owner] (if given) has left. One that cannot be
  /// cancelled does not keep the rest; the first failure is recorded.
  Future<bool> _clear(int run, String origin, {String? owner}) async {
    var all = true;
    for (int i = 1000; i < 2000; i++) {
      if (run != _run || (owner != null && signedInUid() != owner)) return false;
      if (!await _cancel(i, all ? origin : null)) all = false;
    }
    return all;
  }

  /// Recorded under [origin] (null: not again).
  Future<bool> _cancel(int id, String? origin) async {
    try {
      await _plugin.cancel(id);
      return true;
    } catch (e, st) {
      if (origin != null) reportError(origin, e, st);
      return false;
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

  /// Takes every habit reminder off this device: they are the account's that
  /// set them, and it has left (AccountScope). Failures are recorded, never
  /// thrown. Stops when a newer schedule has begun — that one clears them all
  /// itself.
  Future<void> cancelAll() async {
    if (kIsWeb) return; // nothing is ever scheduled on web
    final run = ++_run;
    _cancelled = true;
    try {
      await initialize();
      // Kept after a failure: the next launch tries again.
      if (await _clear(run, 'HabitReminderService.cancelAll') && run == _run) {
        await _rememberOwner(null);
      }
    } catch (e, st) {
      reportError('HabitReminderService.cancelAll', e, st);
    }
  }

  /// What an earlier run of the app left on the device: the hook that takes an
  /// account's reminders off ([cancelAll]) never ran, or not to its end, when
  /// the app was killed meanwhile, the device refused, or the app was started
  /// by a link that signed another account in. Reminders with no note of whose
  /// they are (from a build before it) are kept for whoever is signed in.
  Future<void> sweepAtLaunch() async {
    if (kIsWeb) return;
    final run = _run;
    String? noted;
    try {
      final prefs = await SharedPreferences.getInstance();
      noted = prefs.getString(ownerStorageKey);
    } catch (e, st) {
      reportError('HabitReminderService.sweepAtLaunch', e, st);
    }
    if (run != _run) return; // a schedule or a cancel has begun since
    final now = signedInUid();
    if (now == null || (noted != null && noted != now)) await cancelAll();
  }
}
