import '../../classes/domain/class_provider.dart' show refreshClassesProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/dashboard_service.dart';
import '../../auth/domain/auth_provider.dart';
import '../../../core/observability/app_failure.dart';
import '../../../core/realtime/realtime.dart';

final dashboardServiceProvider = Provider<DashboardService>((ref) => DashboardService());

final dashboardDataProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final service = ref.watch(dashboardServiceProvider);
  return service.getDashboardData();
});

/// Glasses tapped today on this device, for whoever is signed in now. It did
/// not watch the user, so a second account on the same device started with the
/// first one's glasses. By uid only (P0-FL-60b): watching the whole user reset
/// the SAME member's glasses when their sign-up details were edited.
final waterIntakeProvider = StateProvider<int>((ref) {
  ref.watch(currentUserProvider.select((u) => u?.id));
  return 0;
});

/// Steps today — unknown: nothing in the app counts steps. This was a constant
/// 6240, shown to every member as their own steps with a 62% bar.
final stepsProvider = StateProvider<int?>((ref) => null);

// ── Streak (consecutive active days from daily_scores) ────────────────────────
final streakProvider = FutureProvider<int>((ref) async {
  // QAX-SES-01: recompute for whoever is signed in now, not whoever was.
  final uid = ref.watch(currentUserProvider.select((u) => u?.id));
  // Live on `daily_scores` (037's publication): see todayScoreProvider.
  ref.watch(tableTickerProvider('daily_scores'));
  if (uid == null) return 0;
  try {
    final rows = await Supabase.instance.client
        .from('daily_scores')
        .select('score_date, total_score')
        .eq('user_id', uid)
        .gt('total_score', 0)
        .order('score_date', ascending: false)
        .limit(90);
    if ((rows as List).isEmpty) return 0;
    int streak = 0;
    var expected = DateTime.now();
    for (final row in rows) {
      final d = DateTime.parse(row['score_date'] as String);
      final diff = expected.difference(d).inDays;
      if (diff == 0 || diff == 1) {
        streak++;
        expected = d;
      } else {
        break;
      }
    }
    return streak;
  } catch (e, st) {
    // P0-FL-60b · was `return 0`: a failed read told the member their streak
    // was gone.
    reportError('streakProvider', e, st);
    rethrow;
  }
});

/// P0-FL-60b · [streakProvider], for the member signed in NOW. Riverpod keeps
/// the previous member's value (and error) while the next one's read is in
/// flight or after it failed; neither is shown here. A failed refresh for the
/// same member keeps their number, beside the error.
typedef MemberStreak = ({int? streak, Object? error, bool busy});

/// Whose answer [streakProvider] last gave, and whose the last number was.
class _StreakOwner {
  bool settled = false;
  String? settledFor;
  int? streak;
  String? streakOf;
}

final _streakOwnerProvider = Provider<_StreakOwner>((ref) => _StreakOwner());

final memberStreakProvider = Provider<MemberStreak>((ref) {
  final uid = ref.watch(currentUserProvider.select((u) => u?.id));
  final read = ref.watch(streakProvider);
  final owner = ref.watch(_streakOwnerProvider);
  if (!read.isLoading) {
    owner
      ..settled = true
      ..settledFor = uid;
    if (!read.hasError) {
      owner
        ..streak = read.requireValue
        ..streakOf = uid;
    }
  }
  return (
    streak: owner.streakOf == uid ? owner.streak : null,
    error: owner.settled && owner.settledFor == uid && read.hasError
        ? read.error
        : null,
    busy: read.isLoading,
  );
});

// ── Upcoming Classes (next 5 from Supabase) ───────────────────────────────────
//
// "Next" needs both halves of the query. `.order()` sorts DESCENDING unless
// told otherwise (postgrest-dart), so with `limit(5)` these were the five
// FURTHEST away, latest first; and a local time sent with no zone is read by
// Postgres as UTC, which moved "now" by the UTC offset. Same for events below.
final upcomingClassesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  // Read again when a coach creates or cancels a class (the bump Classes
  // already follows). Nothing re-read this, so the Directory's and Activity's
  // Upcoming kept the old five until the app restarted.
  ref.watch(refreshClassesProvider);
  try {
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = await Supabase.instance.client
        .from('classes')
        .select('*, public_profiles!coach_id(first_name, last_name)')
        .gte('scheduled_at', now)
        .order('scheduled_at', ascending: true)
        .limit(5);
    return List<Map<String, dynamic>>.from(rows as List);
  } catch (e, st) {
    // P0-FL-60b · was `return []`: a failed read was "no upcoming classes".
    reportError('upcomingClassesProvider', e, st);
    rethrow;
  }
});

// ── Upcoming Events (next 5 from Supabase) ────────────────────────────────────
final upcomingEventsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  try {
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = await Supabase.instance.client
        .from('events')
        .select()
        .gte('event_date', now)
        .order('event_date', ascending: true)
        .limit(5);
    return List<Map<String, dynamic>>.from(rows as List);
  } catch (e, st) {
    reportError('upcomingEventsProvider', e, st);
    rethrow;
  }
});

// ── Motivational quotes (rotates daily) ──────────────────────────────────────
const _quotes = [
  ('The only bad workout is the one that didn\'t happen.', 'Unknown'),
  ('Push yourself because no one else is going to do it for you.', 'Unknown'),
  ('Success starts with self-discipline.', 'Unknown'),
  ('Your body can stand almost anything. It\'s your mind that you have to convince.', 'Unknown'),
  ('Don\'t stop when you\'re tired. Stop when you\'re done.', 'Unknown'),
  ('The harder you work, the better you get.', 'Unknown'),
  ('Train insane or remain the same.', 'Unknown'),
];

final motivationalQuoteProvider = Provider<({String quote, String author})>((ref) {
  final idx = DateTime.now().day % _quotes.length;
  final q = _quotes[idx];
  return (quote: q.$1, author: q.$2);
});
