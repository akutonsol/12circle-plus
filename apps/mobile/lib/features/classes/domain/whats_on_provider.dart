import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../challenges/domain/challenge_provider.dart';
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
  final now = DateTime.now().toIso8601String();
  final data = await Supabase.instance.client
      .from('events')
      .select()
      .eq('status', 'upcoming')
      .gte('event_date', now)
      .order('event_date')
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
final whatsOnProvider = Provider<AsyncValue<WhatsOn>>((ref) => combineWhatsOn(
      classes: ref.watch(liveClassesFromDbProvider),
      events: ref.watch(whatsOnEventsProvider),
      challenges: ref.watch(liveChallengesProvider),
    ));
