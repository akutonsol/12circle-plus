import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/animations/app_animations.dart';
import '../domain/challenge_provider.dart';
import '../../classes/domain/whats_on.dart';
import '../data/models/challenge_model.dart';
import '../../../shared/theme/app_background.dart';
import 'widgets/challenge_card.dart';
import '../../../core/widgets/back_leading.dart';

class ChallengesScreen extends ConsumerStatefulWidget {
  const ChallengesScreen({super.key});

  @override
  ConsumerState<ChallengesScreen> createState() => _ChallengesScreenState();
}

class _ChallengesScreenState extends ConsumerState<ChallengesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeChallengesProvider);
    final upcoming = ref.watch(upcomingChallengesProvider);
    final completed = ref.watch(completedChallengesProvider);
    final joined = ref.watch(challengeNotifierProvider).where((c) => c.isJoined && c.status == ChallengeStatus.active).toList();

    // F-15: the three lists above are derived from a StateNotifier that is
    // populated by `liveChallengesProvider`. Its AsyncError was never consumed
    // anywhere, so a failed read left the notifier empty and every tab said
    // "No challenges here" — a failure rendered as a definite answer about what
    // exists. The source is watched here so the failure can be told apart from
    // an empty month.
    final source = ref.watch(liveChallengesProvider);
    final failed = source is AsyncError;

    return AppGradientBackground(
      child: Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // FIT-075/078/079 draw a Back control; this screen is
                    // declared `hasBottomNav: false` by the design and had no
                    // back affordance at all. A custom header, so the control
                    // sits beside the title rather than in an AppBar.
                    Row(children: [
                      backLeading(context),
                      const SizedBox(width: 4),
                      const Expanded(
                        child: Text('Challenges',
                            style: TextStyle(
                                color: AppColors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold)),
                      ),
                    ]).fadeSlideIn(),
                    const SizedBox(height: 4),
                    // F-15: on a failed read this said "0 active challenges" —
                    // a number the screen cannot support, the same class as
                    // /train's "0 workouts" and /home's "0%". An em dash says
                    // the count is unknown and needs no new copy to do it.
                    Text(failed ? '— active challenges' : '${joined.length} active challenges',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 14))
                        .fadeSlideIn(delay: 100.ms),
                    const SizedBox(height: 24),
                    if (joined.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.purple, AppColors.purpleDark],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [BoxShadow(color: AppColors.purple.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 8))],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Text('🏆', style: TextStyle(fontSize: 20)),
                                SizedBox(width: 8),
                                Text('My Active Challenges', style: TextStyle(color: Colors.white70, fontSize: 13)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ...joined.map((c) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('${c.emoji} ${c.title}',
                                          style: const TextStyle(color: AppColors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                                      Text('${(c.progressPercent * 100).toInt()}%',
                                          style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: c.progressPercent,
                                      backgroundColor: Colors.white24,
                                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                                      minHeight: 6,
                                    ),
                                  ),
                                ],
                              ),
                            )),
                          ],
                        ),
                      ).fadeSlideIn(delay: 200.ms),
                      const SizedBox(height: 24),
                    ],
                    TabBar(
                      controller: _tabController,
                      indicatorColor: AppColors.purple,
                      labelColor: AppColors.white,
                      unselectedLabelColor: AppColors.textTertiary,
                      indicatorSize: TabBarIndicatorSize.label,
                      tabs: [
                        Tab(text: 'Active (${active.length})'),
                        Tab(text: 'Upcoming (${upcoming.length})'),
                        Tab(text: 'Completed (${completed.length})'),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildList(active, failed: failed),
              _buildList(upcoming, failed: failed),
              _buildList(completed, failed: failed),
            ],
          ),
        ),
      ),
    ));
  }

  Widget _buildList(List<Challenge> challenges, {required bool failed}) {
    if (failed) {
      // The line `/classes` already renders for the same source (FIT-027), so
      // no new product copy is introduced for this screen.
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_rounded, color: Color(0xFFFFB4AB), size: 40),
            const SizedBox(height: 14),
            Text(failureLine(WhatsOnKind.challenges),
              style: const TextStyle(color: Color(0xFFFFB4AB), fontSize: 15,
                fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),
            Semantics(
              button: true,
              child: GestureDetector(
                onTap: () => ref.invalidate(liveChallengesProvider),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.12))),
                  // The package's own label, 16 declarations.
                  child: const Text('Try again',
                    style: TextStyle(color: AppColors.white, fontSize: 13,
                      fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (challenges.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🏁', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            const Text('No challenges here', style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: challenges.length,
      itemBuilder: (context, index) => ChallengeCard(challenge: challenges[index], index: index),
    );
  }
}
