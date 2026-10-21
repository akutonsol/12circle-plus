import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/checkin_service.dart';
import '../data/weekly_checkin_service.dart';
import '../data/models/checkin_model.dart';
import 'checkin_known.dart';

final checkinServiceProvider = Provider<CheckinService>((ref) => CheckinService());

/// `null` when the read failed — CON-01. A `0` here was a number the screen
/// could not support.
final checkinStreakProvider = FutureProvider<int?>((ref) async {
  return ref.watch(checkinServiceProvider).getCheckinStreak();
});

final recentCheckinsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(checkinServiceProvider).getRecentCheckins();
});

/// Three states, not two — CON-01. `false` used to mean both "no" and
/// "we could not find out".
final hasCheckedInTodayProvider = FutureProvider<CheckinKnown>((ref) async {
  return ref.watch(checkinServiceProvider).hasCheckedInToday();
});

final weeklyCheckinServiceProvider =
    Provider<WeeklyCheckinService>((ref) => WeeklyCheckinService());

final weeklyCheckinsProvider = FutureProvider<List<WeeklyCheckin>>((ref) async {
  return ref.watch(weeklyCheckinServiceProvider).getWeeklyCheckins();
});

final currentWeekCheckinProvider = FutureProvider<WeeklyCheckin>((ref) async {
  return ref.watch(weeklyCheckinServiceProvider).getCurrentWeekCheckin();
});

final selectedCheckinProvider = StateProvider<WeeklyCheckin?>((ref) => null);

final coachSubmittedCheckinsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(weeklyCheckinServiceProvider).getSubmittedCheckinsForCoach();
});

final selectedCoachCheckinProvider =
    StateProvider<Map<String, dynamic>?>((ref) => null);
