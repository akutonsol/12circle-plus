import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/domain/auth_provider.dart';
import '../data/weekly_checkin_service.dart';
import '../data/models/checkin_model.dart';

final weeklyCheckinServiceProvider =
    Provider<WeeklyCheckinService>((ref) => WeeklyCheckinService());

final weeklyCheckinsProvider = FutureProvider<List<WeeklyCheckin>>((ref) async {
  ref.watch(currentUserProvider);
  return ref.watch(weeklyCheckinServiceProvider).getWeeklyCheckins();
});

final currentWeekCheckinProvider = FutureProvider<WeeklyCheckin>((ref) async {
  ref.watch(currentUserProvider);
  return ref.watch(weeklyCheckinServiceProvider).getCurrentWeekCheckin();
});

final selectedCheckinProvider = StateProvider<WeeklyCheckin?>((ref) => null);

/// The coach's pending review queue. Auto-disposed so that opening Check-ins,
/// by any route, reads it again: kept for the session, it was re-read only by
/// the coach dashboard, and a coach who opened Check-ins after a client
/// submitted was shown the queue as it was before (C8). A new check-in that
/// arrives while it is open is re-read by `refreshForNotification`.
final coachSubmittedCheckinsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(weeklyCheckinServiceProvider).getSubmittedCheckinsForCoach();
});

/// Auto-disposed with the queue: PD7 is that every way into Check-ins opens
/// the oldest submitted check-in, and a selection kept from the last visit is a
/// copy of a row as it was then — after a send, one no longer in the queue.
final selectedCoachCheckinProvider =
    StateProvider.autoDispose<Map<String, dynamic>?>((ref) => null);
