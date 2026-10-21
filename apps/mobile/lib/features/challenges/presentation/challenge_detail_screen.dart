import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/animations/app_animations.dart';
import '../domain/challenge_provider.dart';
import '../data/models/challenge_model.dart';
import 'widgets/leaderboard_tile.dart';

class ChallengeDetailScreen extends ConsumerWidget {
  const ChallengeDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final challenge = ref.watch(selectedChallengeProvider);
    if (challenge == null) {
      return const Scaffold(backgroundColor: AppColors.bgDark,
          body: Center(child: Text('No challenge selected', style: TextStyle(color: AppColors.white))));
    }

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: AppColors.bgDark,
            expandedHeight: 220,
            pinned: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.white),
              tooltip: 'Back',
              onPressed: () => context.pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.purple.withValues(alpha: 0.8), AppColors.bgDark],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 40),
                      Text(challenge.emoji, style: const TextStyle(fontSize: 56))
                          .animate().scale(duration: 400.ms, curve: Curves.elasticOut),
                      const SizedBox(height: 8),
                      Text(challenge.title,
                          style: const TextStyle(color: AppColors.white, fontSize: 20, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center),
                      Text('by ${challenge.coachName}',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _buildStatCard('${challenge.participantCount}', 'Participants', Icons.people_outline),
                      const SizedBox(width: 12),
                      _buildStatCard('${challenge.daysLeft > 0 ? challenge.daysLeft : 0}', 'Days Left', Icons.schedule),
                      const SizedBox(width: 12),
                      _buildStatCard('${(challenge.progressPercent * 100).toInt()}%', 'My Progress', Icons.trending_up),
                    ],
                  ).animate(delay: 200.ms).fadeIn(duration: 400.ms),
                  const SizedBox(height: 24),
                  if (challenge.isJoined && challenge.status == ChallengeStatus.active) ...[
                    const Text('Your Progress', style: TextStyle(color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceDark,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.purple.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('${challenge.myProgress.toInt()} ${challenge.unit}',
                                  style: const TextStyle(color: AppColors.purple, fontSize: 22, fontWeight: FontWeight.bold)),
                              Text('Goal: ${challenge.targetValue} ${challenge.unit}',
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: challenge.progressPercent,
                              backgroundColor: AppColors.surfaceDarkElevated,
                              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.purple),
                              minHeight: 12,
                            ),
                          ),
                        ],
                      ),
                    ).animate(delay: 300.ms).fadeIn(duration: 400.ms),
                    const SizedBox(height: 24),
                  ],
                  const Text('About', style: TextStyle(color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(challenge.description,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.6))
                      .animate(delay: 400.ms).fadeIn(duration: 400.ms),
                  const SizedBox(height: 24),
                  const Text('Rewards', style: TextStyle(color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  ...challenge.rewards.asMap().entries.map((entry) =>
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceDark,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.surfaceDarkElevated),
                      ),
                      child: Row(
                        children: [
                          Text(entry.value.emoji, style: const TextStyle(fontSize: 24)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(entry.value.title,
                                    style: const TextStyle(color: AppColors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                                Text(entry.value.description,
                                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceDarkElevated,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text('Rank #${entry.value.requiredRank}',
                                style: const TextStyle(color: AppColors.textTertiary, fontSize: 11)),
                          ),
                        ],
                      ),
                    ).animate(delay: Duration(milliseconds: 500 + (entry.key * 80))).fadeIn(duration: 300.ms),
                  ),
                  const SizedBox(height: 24),
                  const Text('Badges', style: TextStyle(color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  Row(
                    children: challenge.badges.map((badge) => Expanded(
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceDark,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.surfaceDarkElevated),
                        ),
                        child: Column(
                          children: [
                            Text(badge.emoji, style: const TextStyle(fontSize: 28)),
                            const SizedBox(height: 6),
                            Text(badge.name,
                                style: const TextStyle(color: AppColors.white, fontSize: 11, fontWeight: FontWeight.w600),
                                textAlign: TextAlign.center),
                            const SizedBox(height: 2),
                            Text(badge.description,
                                style: const TextStyle(color: AppColors.textTertiary, fontSize: 10),
                                textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    )).toList(),
                  ).animate(delay: 600.ms).fadeIn(duration: 400.ms),
                  if (challenge.leaderboard.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Text('Leaderboard', style: TextStyle(color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    ...challenge.leaderboard.asMap().entries.map((entry) =>
                      LeaderboardTile(entry: entry.value, index: entry.key)),
                  ],
                  const SizedBox(height: 24),
                  if (!challenge.isJoined && challenge.status != ChallengeStatus.completed)
                    ElevatedButton(
                      onPressed: () {
                        ref.read(challengeNotifierProvider.notifier).joinChallenge(challenge.id);
                        AppAnimations.hapticSuccess();
                        context.pop();
                      },
                      child: const Text('Join Challenge'),
                    ).animate(delay: 700.ms).fadeIn(duration: 400.ms),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String value, String label, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.surfaceDarkElevated),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.purple, size: 20),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(color: AppColors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            Text(label, style: const TextStyle(color: AppColors.textTertiary, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}
