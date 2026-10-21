import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/theme/app_background.dart';
import '../domain/score_provider.dart';
import '../../../core/widgets/back_leading.dart';

const _card  = Color(0xFF0E0B16);
const _brd   = Color(0xFF1A1020);
const _brand = Color(0xFFA855F7);
const _white = Colors.white;
const _muted = Color(0xFFCFC2D6);
const _gold  = Color(0xFFFFD479);

Color _rankColor(String r) => switch (r) {
  'Diamond' => const Color(0xFF6FE0FF),
  'Platinum' => const Color(0xFFCDE3FF),
  'Gold' => _gold,
  'Silver' => const Color(0xFFC0C0C8),
  _ => const Color(0xFFCD7F32),
};

class ScoreScreen extends ConsumerWidget {
  const ScoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppGradientBackground(
      child: DefaultTabController(
        length: 3,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent, elevation: 0,
            leading: backLeading(context),
            iconTheme: const IconThemeData(color: _white),
            title: const Text('12 Circle Score',
                style: TextStyle(color: _white, fontWeight: FontWeight.w700)),
            bottom: const TabBar(
              labelColor: _white, unselectedLabelColor: _muted, indicatorColor: _brand,
              labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              tabs: [Tab(text: 'My Score'), Tab(text: 'Badges'), Tab(text: 'Leaderboard')],
            ),
          ),
          body: TabBarView(children: [
            _MyScoreTab(),
            _BadgesTab(),
            _LeaderboardTab(),
          ]),
        ),
      ),
    );
  }
}

// ── My Score ──────────────────────────────────────────────────────────────────
class _MyScoreTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final score = ref.watch(myScoreProvider).valueOrNull;
    final events = ref.watch(recentScoreEventsProvider).valueOrNull ?? [];
    final cycle = (score?['current_cycle_score'] as num?)?.toInt() ?? 0;
    final lifetime = (score?['lifetime_score'] as num?)?.toInt() ?? 0;
    final level = (score?['level'] as num?)?.toInt() ?? 1;
    final rank = score?['rank'] as String? ?? 'Bronze';
    // Progress to next level (every 500 lifetime pts).
    final intoLevel = lifetime % 500;
    final pct = intoLevel / 500.0;

    return RefreshIndicator(
      onRefresh: () async => ref.read(scoreRefreshProvider.notifier).state++,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          // Hero
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [_rankColor(rank).withValues(alpha: 0.22), _card]),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: _rankColor(rank).withValues(alpha: 0.4)),
            ),
            child: Column(children: [
              Text('THIS MONTH', style: TextStyle(color: _muted, fontSize: 11,
                fontWeight: FontWeight.w700, letterSpacing: 1.5)),
              const SizedBox(height: 6),
              Text('$cycle', style: const TextStyle(color: _white, fontSize: 52, fontWeight: FontWeight.w900, height: 1)),
              const Text('points', style: TextStyle(color: _muted, fontSize: 13)),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.workspace_premium_rounded, color: _rankColor(rank), size: 18),
                const SizedBox(width: 6),
                Text('$rank · Level $level',
                  style: TextStyle(color: _rankColor(rank), fontSize: 15, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: pct, minHeight: 8,
                  backgroundColor: _brd, valueColor: AlwaysStoppedAnimation<Color>(_rankColor(rank))),
              ),
              const SizedBox(height: 6),
              Text('${500 - intoLevel} pts to Level ${level + 1}',
                style: const TextStyle(color: _muted, fontSize: 11)),
            ]),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _stat('Lifetime', '$lifetime', Icons.all_inclusive_rounded)),
            const SizedBox(width: 12),
            Expanded(child: _stat('Badges', '${ref.watch(myBadgeIdsProvider).valueOrNull?.length ?? 0}', Icons.military_tech_rounded)),
          ]),
          const SizedBox(height: 20),
          const Text('RECENT POINTS', style: TextStyle(color: _muted, fontSize: 11,
            fontWeight: FontWeight.w700, letterSpacing: 1)),
          const SizedBox(height: 10),
          if (events.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('Complete activities to start earning points!',
                style: TextStyle(color: _muted, fontSize: 13))))
          else ...events.map((e) => _EventRow(e)),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, IconData icon) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16), border: Border.all(color: _brd)),
    child: Row(children: [
      Icon(icon, color: _brand, size: 22),
      const SizedBox(width: 12),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: const TextStyle(color: _white, fontSize: 20, fontWeight: FontWeight.w800)),
        Text(label, style: const TextStyle(color: _muted, fontSize: 11)),
      ]),
    ]),
  );
}

String _actionLabel(String a) => switch (a) {
  'idle_penalty' => 'Rest overrun penalty',
  'workout_complete' => 'Workout completed',
  'workout_start' => 'Workout started',
  'workout_week_bonus' => 'All workouts this week',
  'meal_log' => 'Meal logged',
  'protein_goal' => 'Protein goal hit',
  'water_goal' => 'Water goal hit',
  'nutrition_day' => 'Full day tracked',
  'habit_complete' => 'Habit completed',
  'habits_all' => 'All habits today',
  'habit_streak_7' => '7-day habit streak',
  'checkin_weekly' => 'Weekly check-in',
  'photos_upload' => 'Progress photos',
  'assessment' => 'Assessment completed',
  'event_attend' => 'Attended event',
  'challenge_join' => 'Joined challenge',
  'challenge_complete' => 'Completed challenge',
  'community_post' => 'Community post',
  'action_item_complete' => 'Action item done',
  'message_coach' => 'Messaged coach',
  'review_feedback' => 'Reviewed feedback',
  'book_session' => 'Booked session',
  'attend_session' => 'Attended session',
  _ => a.replaceAll('_', ' '),
};

class _EventRow extends StatelessWidget {
  final Map<String, dynamic> e;
  const _EventRow(this.e);
  @override
  Widget build(BuildContext context) {
    final pts = (e['points'] as num?)?.toInt() ?? 0;
    final when = (e['created_at'] as String? ?? '').split('T').first;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12), border: Border.all(color: _brd)),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_actionLabel(e['action'] as String? ?? ''),
            style: const TextStyle(color: _white, fontSize: 13, fontWeight: FontWeight.w600)),
          Text(when, style: const TextStyle(color: _muted, fontSize: 11)),
        ])),
        Text('+$pts', style: const TextStyle(color: _gold, fontSize: 16, fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

// ── Badges ────────────────────────────────────────────────────────────────────
class _BadgesTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badges = ref.watch(allBadgesProvider).valueOrNull ?? [];
    final earned = ref.watch(myBadgeIdsProvider).valueOrNull ?? {};
    if (badges.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: _brand));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.8),
      itemCount: badges.length,
      itemBuilder: (_, i) {
        final b = badges[i];
        final has = earned.contains(b['id']);
        return Opacity(
          opacity: has ? 1 : 0.4,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _card, borderRadius: BorderRadius.circular(16),
              border: Border.all(color: has ? _gold.withValues(alpha: 0.5) : _brd)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(b['icon'] as String? ?? '🏅', style: const TextStyle(fontSize: 30)),
              const SizedBox(height: 6),
              Text(b['name'] as String? ?? '', textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _white, fontSize: 11, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(b['description'] as String? ?? '', textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _muted, fontSize: 9, height: 1.2)),
            ]),
          ),
        );
      },
    );
  }
}

// ── Leaderboard ───────────────────────────────────────────────────────────────
class _LeaderboardTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(globalLeaderboardProvider).valueOrNull ?? [];
    final myId = Supabase.instance.client.auth.currentUser?.id;
    if (rows.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(32),
        child: Text('No scores this month yet — be the first on the board!',
          textAlign: TextAlign.center, style: TextStyle(color: _muted))));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: rows.length,
      itemBuilder: (_, i) {
        final r = rows[i];
        final me = r['user_id'] == myId;
        final name = '${r['first_name'] ?? ''} ${r['last_name'] ?? ''}'.trim();
        final medal = i == 0 ? '🥇' : i == 1 ? '🥈' : i == 2 ? '🥉' : '${i + 1}';
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: me ? _brand.withValues(alpha: 0.15) : _card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: me ? _brand : _brd)),
          child: Row(children: [
            SizedBox(width: 30, child: Text(medal, style: const TextStyle(color: _white, fontSize: 16, fontWeight: FontWeight.w800))),
            const SizedBox(width: 6),
            Expanded(child: Text(name.isEmpty ? 'Member' : name,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: me ? _white : _muted, fontSize: 14, fontWeight: FontWeight.w600))),
            Text('${(r['cycle_score'] as num?)?.toInt() ?? 0}',
              style: const TextStyle(color: _gold, fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(width: 4),
            const Text('pts', style: TextStyle(color: _muted, fontSize: 11)),
          ]),
        );
      },
    );
  }
}
