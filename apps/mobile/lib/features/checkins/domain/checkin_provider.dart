import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/domain/auth_provider.dart';
import '../data/weekly_checkin_service.dart';
import '../data/models/checkin_model.dart';

final weeklyCheckinServiceProvider =
    Provider<WeeklyCheckinService>((ref) => WeeklyCheckinService());

final weeklyCheckinsProvider = FutureProvider<List<WeeklyCheckin>>((ref) async {
  ref.watch(currentUserProvider.select((u) => u?.id));
  ref.watch(checkinUidProvider);
  return ref.watch(weeklyCheckinServiceProvider).getWeeklyCheckins();
});

final currentWeekCheckinProvider = FutureProvider<WeeklyCheckin>((ref) async {
  ref.watch(currentUserProvider.select((u) => u?.id));
  ref.watch(checkinUidProvider);
  return ref.watch(weeklyCheckinServiceProvider).getCurrentWeekCheckin();
});

/// The signed-in uid, or null when signed out: what everything below is keyed
/// by. The uid and not the whole `User`, which a token refresh or a profile
/// edit replaces for the same member (P0-FL-59c).
///
/// WATCH THIS, not `currentUserProvider.select(...)`, in a provider: a select is
/// not flushed with a provider's own dependencies, so a read invalidated after
/// an account change but before the next frame counts as a refresh by the same
/// member (riverpod 2.6.1) and hands the last one's value over as data.
final checkinUidProvider = Provider<String?>(
    (ref) => ref.watch(currentUserProvider.select((u) => u?.id)));

/// Who is signed in at this instant, for a guard before a write. A provider
/// learns of a switch a moment later, and not at all in a hidden tab, where no
/// frame runs.
String? checkinUidNow() => Supabase.instance.client.auth.currentUser?.id;

/// Rows, and the account that read them. Riverpod keeps a provider's last value
/// through a re-read and through a failure, whoever asked for it, so whose rows
/// they are is carried with them (P0-FL-59c).
class OwnedRows<T> extends UnmodifiableListView<T> {
  OwnedRows(super.source, this.owner);
  final String? owner;
}

/// [read]'s rows, tagged with the account signed in when the read was made.
Future<List<T>> ownedRead<T>(Future<List<T>> Function() read) async {
  final owner = checkinUidNow();
  return OwnedRows(await read(), owner);
}

/// [state], with the rows it holds only if they were read by [uid]'s account —
/// in any state: loading, loaded or failed. Rows that carry no owner were put
/// there by a test; [uid] is not asked for them.
AsyncValue<List<T>> heldFor<T>(
    AsyncValue<List<T>> state, String? Function() uid) {
  if (!state.hasValue) return state;
  final rows = state.requireValue;
  if (rows is! OwnedRows<T> || rows.owner == uid()) return state;
  return switch (state) {
    AsyncError(:final error, :final stackTrace) =>
      AsyncError<List<T>>(error, stackTrace),
    _ => AsyncLoading<List<T>>(),
  };
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
/// they were shown the last coach's clients. Signed out has no queue. The rows
/// carry the coach who read them ([OwnedRows]).
final coachSubmittedCheckinsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  if (ref.watch(checkinUidProvider) == null) return const [];
  final service = ref.watch(weeklyCheckinServiceProvider);
  return ownedRead(service.getSubmittedCheckinsForCoach);
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
