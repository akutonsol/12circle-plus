import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/auth/domain/auth_provider.dart';
import '../domain/dashboard_provider.dart';
import 'widgets/daily_workout_card.dart';
import 'widgets/water_tracker_card.dart';
import 'widgets/macro_tracker_card.dart';
import 'widgets/step_tracker_card.dart';
import 'widgets/streak_card.dart';
import 'widgets/motivational_quote_card.dart';
import 'widgets/upcoming_class_card.dart';
import 'widgets/upcoming_event_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(dashboardDataProvider);
    final user = ref.watch(currentUserProvider);
    final firstName = user?.userMetadata?['first_name'] ?? 'there';

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        child: dashboardAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.purple),
          ),
          error: (e, _) => Center(
            child: Text('Could not load your dashboard.', style: const TextStyle(color: AppColors.error)),
          ),
          data: (data) => CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Good morning, $firstName! 👋',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Let\'s crush today!',
                            style: TextStyle(
                              color: AppColors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => ref.read(authNotifierProvider.notifier).signOut(),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceDark,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.surfaceDarkElevated),
                          ),
                          child: const Icon(Icons.person_outline, color: AppColors.white, size: 22),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.all(24),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    StreakCard(
                      currentStreak: data['streak']['current'],
                      longestStreak: data['streak']['longest'],
                    ),
                    const SizedBox(height: 16),
                    MotivationalQuoteCard(
                      quote: data['quote']['text'],
                      author: data['quote']['author'],
                    ),
                    const SizedBox(height: 16),
                    DailyWorkoutCard(
                      title: data['workout']['title'],
                      duration: data['workout']['duration'],
                      calories: data['workout']['calories'],
                      completed: data['workout']['completed'],
                      progress: data['workout']['progress'],
                      onTap: () {},
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: StepTrackerCard(
                            currentSteps: data['steps']['current'],
                            goalSteps: data['steps']['goal'],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const WaterTrackerCard(),
                    const SizedBox(height: 16),
                    MacroTrackerCard(macros: data['macros']),
                    const SizedBox(height: 16),
                    UpcomingClassCard(
                      title: data['upcoming_class']['title'],
                      coach: data['upcoming_class']['coach'],
                      time: data['upcoming_class']['time'],
                      date: data['upcoming_class']['date'],
                      spots: data['upcoming_class']['spots'],
                    ),
                    const SizedBox(height: 16),
                    UpcomingEventCard(
                      title: data['upcoming_event']['title'],
                      date: data['upcoming_event']['date'],
                      location: data['upcoming_event']['location'],
                      registered: data['upcoming_event']['registered'],
                    ),
                    const SizedBox(height: 32),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
