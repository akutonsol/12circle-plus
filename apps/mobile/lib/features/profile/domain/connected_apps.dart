import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/domain/auth_provider.dart';

/// FIT-029 · the `Connected apps` row's count.
///
/// The board draws it as a trailing figure:
///
///     Connected apps                                    2  ›
///
/// ── WHERE THE NUMBER COMES FROM ────────────────────────────────────────────
/// `user_integrations`, filtered to `connected = true`. That is the same
/// source `integrations_screen.dart` already reads to decide which providers
/// show as linked, so the row and the screen behind it cannot disagree.
///
/// The table is self-scoped — `011_coaching_calls.sql:57`,
/// `FOR ALL USING (auth.uid() = user_id)` — so this reads the caller's own
/// rows and nobody else's. No coach/client boundary is involved and nothing
/// is written.
///
/// ── AND THE ERROR IS NOT A ZERO ────────────────────────────────────────────
/// `integrations_screen.dart` ends its read `catch (_)`, so a failure there
/// shows every provider as disconnected. This does not repeat that: the
/// provider throws, the row renders **no badge**, and the client is not told
/// they have zero connected apps by a failed network call.
final connectedAppsCountProvider = FutureProvider<int>((ref) async {
  // QAX-SES-01: recompute for whoever is signed in now, not whoever was.
  ref.watch(currentUserProvider);
  final db = Supabase.instance.client;
  final uid = db.auth.currentUser?.id;
  // Signed out is a real answer, not a failure.
  if (uid == null) return 0;

  final rows = await db
      .from('user_integrations')
      .select('provider')
      .eq('user_id', uid)
      .eq('connected', true);
  return (rows as List).length;
});

/// What the row's trailing badge shows, or null for no badge.
///
/// Null in three different situations that share one correct answer:
///
///   * **nothing connected** — the board draws a count, not a `0`, and a row
///     reading `Connected apps 0` tells the client something they can already
///     see by opening it;
///   * **still loading** — a number that appears a moment later is worse than
///     one that appears once;
///   * **the read failed** — the client has no idea how many apps are
///     connected, and neither do we. Showing `0` would be a fabricated fact of
///     exactly the kind F-15 records.
String? connectedAppsBadge(AsyncValue<int> count) => switch (count) {
      AsyncData(:final value) when value > 0 => '$value',
      _ => null,
    };
