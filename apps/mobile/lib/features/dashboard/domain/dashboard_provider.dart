import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/dashboard_service.dart';
import '../../auth/domain/auth_provider.dart';

final dashboardServiceProvider = Provider<DashboardService>((ref) => DashboardService());

final dashboardDataProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final service = ref.watch(dashboardServiceProvider);
  return service.getDashboardData();
});

final waterIntakeProvider = StateProvider<int>((ref) => 0);
final stepsProvider = StateProvider<int>((ref) => 6240);

// ── Streak (consecutive active days from daily_scores) ────────────────────────
final streakProvider = FutureProvider<int>((ref) async {
  // QAX-SES-01: recompute for whoever is signed in now, not whoever was.
  ref.watch(currentUserProvider);
  final uid = Supabase.instance.client.auth.currentUser?.id;
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
  } catch (_) {
    return 0;
  }
});

// ── Upcoming Classes (next 5 from Supabase) ───────────────────────────────────
final upcomingClassesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  try {
    final now = DateTime.now().toIso8601String();
    final rows = await Supabase.instance.client
        .from('classes')
        .select('*, public_profiles!coach_id(first_name, last_name)')
        .gte('scheduled_at', now)
        .order('scheduled_at')
        .limit(5);
    return List<Map<String, dynamic>>.from(rows as List);
  } catch (_) {
    return [];
  }
});

// ── Upcoming Events (next 5 from Supabase) ────────────────────────────────────
final upcomingEventsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  try {
    final now = DateTime.now().toIso8601String();
    final rows = await Supabase.instance.client
        .from('events')
        .select()
        .gte('event_date', now)
        .order('event_date')
        .limit(5);
    return List<Map<String, dynamic>>.from(rows as List);
  } catch (_) {
    return [];
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
