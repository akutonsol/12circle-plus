import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/domain/auth_provider.dart';
import '../../challenges/domain/challenge_provider.dart';
import '../../dashboard/domain/still_reading.dart' show hasAuthClient, ownerOfHeld;
import 'class_provider.dart';
import 'whats_on.dart';

/// FIT-027 · the wiring for "What's on".
///
/// The rules live in `whats_on.dart`, which is pure and tested. This file only
/// reads three providers and hands their states to those rules.

/// Upcoming events.
///
/// **F-16: the error propagates.** This read used to live privately inside
/// `events_screen.dart` ending `catch (_) { return []; }` — which made
/// `/events`' own `error:` branch, and the "Could not load events" string it
/// already renders, **unreachable**. A failed read arrived as an empty list and
/// the screen said there were no events. The copy for the failure was written;
/// the catch made sure nobody ever saw it.
final whatsOnEventsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  // A UTC instant, as Home's Upcoming panel sends it (#89): zoneless is read as UTC.
  final now = DateTime.now().toUtc().toIso8601String();
  final data = await Supabase.instance.client
      .from('events')
      .select()
      .eq('status', 'upcoming')
      .gte('event_date', now)
      // The 30 SOONEST: a bare `order()` is descending, so the limit kept the
      // furthest 30 and dropped this week's events (as #89 found on Home).
      .order('event_date', ascending: true)
      .limit(30);
  return List<Map<String, dynamic>>.from(data as List);
});

/// Which segment of the design's `All / Classes / Events / Challenges` row is
/// selected. 0 = All.
final whatsOnSegmentProvider = StateProvider<int>((ref) => 0);

/// The merged list, plus which sources failed.
///
/// ── IT WAITS FOR ALL THREE TO SETTLE ───────────────────────────────────────
/// A source that is still in flight contributes no rows, which is
/// indistinguishable from a source that returned none. Rendering before
/// everything has settled would show a list that is briefly, silently wrong —
/// and on a fast connection nobody would ever see it happen. So the screen
/// holds its loading state until every source has either a value or an error.
///
/// A refresh keeps its previous value, so `hasValue` stays true and the list
/// does not flash back to a spinner.
///
/// ── AND NOBODY ELSE'S ANSWER COUNTS (P0-FL-59f, A-25) ──────────────────────
/// Riverpod also keeps the PREVIOUS MEMBER's answer, and their failure, through
/// a sign-in switch: "Booked" and "Joined" are theirs. While a source re-reads,
/// what it holds counts only when it last settled for the member signed in now
/// — by id, so a token refresh or a live re-read still holds the list steady.
final whatsOnProvider = Provider<AsyncValue<WhatsOn>>((ref) {
  final uid = hasAuthClient
      ? ref.watch(currentUserProvider.select((u) => u?.id))
      : null;
  final settledFor = ref.read(_settledForProvider);
  AsyncValue<T> own<T>(Object source, AsyncValue<T> v) {
    if (!v.isLoading) {
      settledFor[source] = uid;
      return v;
    }
    return settledFor.containsKey(source) && settledFor[source] == uid
        ? v
        : AsyncLoading<T>();
  }

  var classes =
      own(liveClassesFromDbProvider, ref.watch(liveClassesFromDbProvider));
  // The class rows also carry whose they are.
  final owner = ownerOfHeld(classes);
  if (owner != null && owner != uid && !classes.hasError) {
    classes = const AsyncLoading();
  }
  return combineWhatsOn(
    classes: classes,
    // The same for everybody signed in.
    events: ref.watch(whatsOnEventsProvider),
    challenges: own(liveChallengesProvider, ref.watch(liveChallengesProvider)),
  );
});

/// Which member each personal source last settled for, an answer or a failure.
final _settledForProvider = Provider((_) => <Object, String?>{});
