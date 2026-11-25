import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

/// The signed-in uid, or null when signed out: what everything below is keyed
/// by. The uid and not the whole `User`, which a token refresh or a profile
/// edit replaces for the same member (P0-FL-59c).
///
/// Null, too, where Supabase was never started (a screen test with every read
/// replaced): nobody is signed in there. `Supabase.instance` says so by
/// assertion, and nothing else is caught.
final checkinUidProvider = Provider<String?>((ref) {
  try {
    return ref.watch(currentUserProvider.select((u) => u?.id));
  } on AssertionError {
    return null;
  }
});

/// Who is signed in at this instant, for a guard before a write. A provider
/// learns of a switch a moment later, and not at all in a hidden tab, where no
/// frame runs.
String? checkinUidNow() {
  try {
    return Supabase.instance.client.auth.currentUser?.id;
  } on AssertionError {
    return null;
  }
}

/// The check-in the client opened. Cleared when the signed-in account changes:
/// it outlived sign-out, so the next account could open the last one's week.
final selectedCheckinProvider = StateProvider<WeeklyCheckin?>((ref) {
  ref.watch(checkinUidProvider);
  return null;
});

/// The coach's pending review queue. Auto-disposed so that opening Check-ins,
/// by any route, reads it again: kept for the session, it was re-read only by
/// the coach dashboard, and a coach who opened Check-ins after a client
/// submitted was shown the queue as it was before (C8). A new check-in that
/// arrives while it is open is re-read by `refreshForNotification`.
///
/// Read again when another coach signs in (P0-FL-59c): nothing re-read it, so
/// they were shown the last coach's clients. Signed out has no queue.
final coachSubmittedCheckinsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  if (ref.watch(checkinUidProvider) == null) return const [];
  return ref.watch(weeklyCheckinServiceProvider).getSubmittedCheckinsForCoach();
});

/// Auto-disposed with the queue: PD7 is that every way into Check-ins opens
/// the oldest submitted check-in, and a selection kept from the last visit is a
/// copy of a row as it was then — after a send, one no longer in the queue.
/// Cleared when another account signs in, like the queue.
final selectedCoachCheckinProvider =
    StateProvider.autoDispose<Map<String, dynamic>?>((ref) {
  ref.watch(checkinUidProvider);
  return null;
});
