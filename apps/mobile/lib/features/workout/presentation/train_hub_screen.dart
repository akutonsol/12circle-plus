import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../auth/domain/auth_provider.dart';
import '../../coaching_mode/domain/coaching_mode_provider.dart';
import '../../exercise_database/data/exercise_database_service.dart';
import '../../exercise_database/data/models/exercise_detail_model.dart';
import '../../exercise_database/domain/exercise_database_provider.dart';
import '../data/models/workout_model.dart';
import '../domain/plan_summary.dart';
import 'train_palette.dart';
import 'widgets/week_row_tile.dart';
import '../domain/workout_provider.dart';
import '../../coach/domain/coach_name.dart';
import '../../coach/domain/coach_provider.dart';
import '../data/workout_session_store.dart';

/// The palette moved to `train_palette.dart` so `WeekRowTile` could be
/// extracted without copying it into a 21st per-screen private palette.
typedef _C = TrainColors;

const _muscleCategories = [
  ('ALL',       Icons.grid_4x4_rounded),
  ('CHEST',     Icons.sports_gymnastics_rounded),
  ('BACK',      Icons.accessibility_new_rounded),
  ('LEGS',      Icons.directions_run_rounded),
  ('CORE',      Icons.radio_button_checked_rounded),
  ('SHOULDERS', Icons.expand_rounded),
  ('ARMS',      Icons.fitness_center_rounded),
];

class TrainHubScreen extends ConsumerStatefulWidget {
  const TrainHubScreen({super.key});
  @override
  ConsumerState<TrainHubScreen> createState() => _TrainHubScreenState();
}

class _TrainHubScreenState extends ConsumerState<TrainHubScreen> {
  int _selectedCategory = 0;
  final _searchCtrl = TextEditingController();
  String _search = '';
  final _exerciseService = ExerciseDatabaseService();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final streakAsync       = ref.watch(currentStreakProvider);
    final weeklyAsync       = ref.watch(weeklyWorkoutCountProvider);
    final totalAsync        = ref.watch(totalWorkoutCountProvider);
    final activeSession     = ref.watch(activeSessionProvider);
    final prsAsync          = ref.watch(personalRecordsProvider);
    final completionAsync   = ref.watch(completionRateProvider);
    final profileAsync      = ref.watch(currentUserProfileProvider);
    final isCoach           = profileAsync.whenOrNull(data: (p) => p?['role'] == 'coach') ?? false;
    final mode              = ref.watch(coachingModeProvider);
    // "My Program" origin differs by mode — only coach-guided is coach-assigned.
    final programSub = switch (mode) {
      CoachingMode.coachGuided => 'Coach assigned',
      CoachingMode.aiGuided    => 'AI generated',
      CoachingMode.selfGuided  => 'Your plan',
    };

    final allExercises = _exerciseService.getAllExercises();
    final catLabel = _muscleCategories[_selectedCategory].$1;
    final filtered = _exerciseService.filterExercises(
      exercises: allExercises,
      muscleGroup: catLabel == 'ALL' ? 'All'
          : catLabel[0] + catLabel.substring(1).toLowerCase(),
      search: _search,
    );

    return AppScaffold(
      body: Stack(children: [
        // Atmospheric background
        Positioned.fill(
          child: Image.asset('assets/images/background.png',
            fit: BoxFit.cover,
            color: Colors.black.withValues(alpha: 0.58),
            colorBlendMode: BlendMode.darken,
            errorBuilder: (_, __, ___) => Container(color: _C.bg))),

        // Scrollable content
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 120),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── Modality Banner ──────────────────────────────────────────────
            Builder(builder: (ctx) {
              final mode = ref.watch(coachingModeProvider);
              if (mode == CoachingMode.aiGuided) {
                return GestureDetector(
                  onTap: () => context.go('/ai-coach'),
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF06B6D4).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF06B6D4).withValues(alpha: 0.3))),
                    child: Row(children: [
                      const Icon(Icons.auto_awesome, color: Color(0xFF06B6D4), size: 16),
                      const SizedBox(width: 10),
                      const Expanded(child: Text(
                        'AI-Guided mode — tap here for personalised AI workout recommendations',
                        style: TextStyle(color: Color(0xFF06B6D4), fontSize: 12, height: 1.4))),
                      const Icon(Icons.chevron_right_rounded, color: Color(0xFF06B6D4), size: 18),
                    ])));
              }
              if (mode == CoachingMode.coachGuided) {
                return GestureDetector(
                  onTap: () => context.push('/workouts'),
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: _C.tertiary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _C.tertiary.withValues(alpha: 0.25))),
                    child: Row(children: [
                      Icon(Icons.assignment_outlined, color: _C.tertiary, size: 16),
                      const SizedBox(width: 10),
                      Expanded(child: Text(
                        'Coach-Guided mode — tap to view your coach-assigned workouts',
                        style: TextStyle(color: _C.tertiary, fontSize: 12, height: 1.4))),
                      Icon(Icons.chevron_right_rounded, color: _C.tertiary, size: 18),
                    ])));
              }
              return const SizedBox.shrink();
            }),

            // ── Header ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('TRAIN',
                    style: TextStyle(color: _C.onSurface, fontSize: 32,
                      fontWeight: FontWeight.w900, letterSpacing: -1)),
                  Row(children: [
                    _IconBtn(
                      icon: Icons.history_rounded,
                      onTap: () => context.push('/workout-history'),
                      tooltip: 'History'),
                    const SizedBox(width: 8),
                    _IconBtn(
                      icon: Icons.library_books_outlined,
                      onTap: () => context.push('/exercise-library'),
                      tooltip: 'Exercise Library'),
                  ]),
                ])),
            const SizedBox(height: 20),

            // ── Assigned plan · FIT-014 / FIT-015 ───────────────────────────
            // Two states of one route. FIT-014 is the coach-guided content
            // state; FIT-015 is what the package calls "the empty state that
            // matters most" — a member with no plan previously saw a hub of
            // zeros with no explanation of why.
            const _PlanSurface(),

            // ── Resume Workout Banner ────────────────────────────────────────
            activeSession.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (session) {
                if (session == null) return const SizedBox.shrink();
                final title = session.workoutTitle.isNotEmpty
                    ? session.workoutTitle
                    : 'Workout';
                final elapsed = DateTime.now().difference(session.startedAt);
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: GestureDetector(
                    onTap: () => _resumeWorkout(session),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [_C.inversePrimary.withValues(alpha: 0.3),
                            _C.primaryContainer.withValues(alpha: 0.15)],
                          begin: Alignment.centerLeft, end: Alignment.centerRight),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _C.primary.withValues(alpha: 0.4))),
                      child: Row(children: [
                        Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: _C.inversePrimary.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.play_arrow_rounded,
                            color: _C.primary, size: 26)),
                        const SizedBox(width: 14),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('RESUME WORKOUT',
                            style: TextStyle(color: _C.primary, fontSize: 10,
                              fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                          const SizedBox(height: 2),
                          Text(title,
                            style: const TextStyle(color: _C.onSurface, fontSize: 16,
                              fontWeight: FontWeight.w700)),
                          Text(_formatElapsed(elapsed),
                            style: TextStyle(
                              color: _C.onSurfaceVar.withValues(alpha: 0.6), fontSize: 12)),
                        ])),
                        const Icon(Icons.chevron_right, color: _C.primary, size: 22),
                      ]))));
              }),

            // ── Stats Row ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                _StatCard(
                  label: 'STREAK',
                  icon: Icons.local_fire_department_rounded,
                  iconColor: _C.amber,
                  // A failed load is NOT a streak of zero. '—' is this
                  // widget's own established "no figure" placeholder — DONE
                  // RATE already uses it for exactly this case — so nothing is
                  // invented here. Showing '0' told the member their streak was
                  // broken when the app had simply failed to ask.
                  value: streakAsync.when(
                    data: (v) => '$v', loading: () => '—', error: (_, __) => '—')),
                const SizedBox(width: 10),
                _StatCard(
                  label: 'THIS WEEK',
                  icon: Icons.calendar_today_outlined,
                  iconColor: _C.tertiary,
                  value: weeklyAsync.when(
                    data: (v) => '$v', loading: () => '—', error: (_, __) => '—')),
                const SizedBox(width: 10),
                _StatCard(
                  label: 'TOTAL',
                  icon: Icons.fitness_center_rounded,
                  iconColor: _C.primary,
                  value: totalAsync.when(
                    data: (v) => '$v', loading: () => '—', error: (_, __) => '—')),
                const SizedBox(width: 10),
                _StatCard(
                  label: 'DONE RATE',
                  icon: Icons.check_circle_outline_rounded,
                  iconColor: _C.primaryContainer,
                  value: completionAsync.when(
                    data: (v) => '${(v * 100).toStringAsFixed(0)}%',
                    loading: () => '—', error: (_, __) => '—')),
              ])),
            const SizedBox(height: 24),

            // ── Nav Tiles ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                Expanded(child: _NavTile(
                  icon: Icons.assignment_rounded,
                  label: 'My Program',
                  sub: programSub,
                  color: _C.primary,
                  onTap: () => context.push('/workouts'))),
                const SizedBox(width: 12),
                Expanded(child: _NavTile(
                  icon: Icons.menu_book_rounded,
                  label: 'Exercise Library',
                  sub: 'Browse all exercises',
                  color: _C.tertiary,
                  onTap: () => context.push('/exercise-library'))),
              ])),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                Expanded(child: _NavTile(
                  icon: Icons.history_rounded,
                  label: 'Workout History',
                  sub: 'Past sessions & PRs',
                  color: _C.amber,
                  onTap: () => context.push('/workout-history'))),
                const SizedBox(width: 12),
                Expanded(child: _NavTile(
                  icon: Icons.storage_rounded,
                  label: 'Exercise Database',
                  sub: 'Global library',
                  color: _C.primaryContainer,
                  onTap: () => context.push('/exercise-database'))),
              ])),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                Expanded(child: _NavTile(
                  icon: Icons.show_chart_rounded,
                  label: 'Strength Progress',
                  sub: 'Track your PRs over time',
                  color: _C.tertiary,
                  onTap: () => context.push('/strength-progression'))),
                const SizedBox(width: 12),
                // Coach-only tools stay behind the coach role; clients get a
                // client-appropriate tile (they must never reach the coach's
                // "Client Workout Stats" screen — that was the inverted branch).
                if (isCoach)
                  Expanded(child: _NavTile(
                    icon: Icons.add_circle_outline_rounded,
                    label: 'Create Exercise',
                    sub: 'Add to your library',
                    color: _C.primary,
                    onTap: () => context.push('/create-exercise')))
                else
                  Expanded(child: _NavTile(
                    icon: Icons.check_circle_outline_rounded,
                    label: 'Habits',
                    sub: 'Build daily habits',
                    color: _C.tertiary,
                    onTap: () => context.push('/habits'))),
              ])),
            const SizedBox(height: 28),

            // ── Personal Records ─────────────────────────────────────────────
            prsAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (prs) {
                if (prs.isEmpty) return const SizedBox.shrink();
                final top = prs.take(3).toList();
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('PERSONAL RECORDS',
                          style: TextStyle(color: _C.onSurface, fontSize: 16,
                            fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                        GestureDetector(
                          onTap: () => context.push('/workout-history'),
                          child: const Text('SEE ALL',
                            style: TextStyle(color: _C.primary, fontSize: 11,
                              fontWeight: FontWeight.w700, letterSpacing: 1.5))),
                      ])),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: top.map((pr) => _PRRow(pr: pr)).toList())),
                  const SizedBox(height: 24),
                ]);
              }),

            // ── Search bar ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  color: _C.surfaceContainerHigh.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
                child: Row(children: [
                  const SizedBox(width: 14),
                  Icon(Icons.search, color: _C.outline.withValues(alpha: 0.5), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      style: const TextStyle(color: _C.onSurface, fontSize: 14),
                      onChanged: (v) => setState(() => _search = v),
                      decoration: const InputDecoration(
                        hintText: 'Search exercises...',
                        hintStyle: TextStyle(color: _C.outline, fontSize: 14),
                        border: InputBorder.none, isDense: true,
                        contentPadding: EdgeInsets.zero))),
                ]))),
            const SizedBox(height: 20),

            // ── Category tabs ────────────────────────────────────────────────
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _muscleCategories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) {
                  final active = i == _selectedCategory;
                  final cat = _muscleCategories[i];
                  return GestureDetector(
                    onTap: () => setState(() => _selectedCategory = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: 72,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: active
                            ? _C.primary.withValues(alpha: 0.2)
                            : _C.glassCard,
                        border: Border.all(
                          color: active
                              ? _C.primary.withValues(alpha: 0.6)
                              : Colors.white.withValues(alpha: 0.08)),
                        boxShadow: active ? [
                          BoxShadow(color: _C.primary.withValues(alpha: 0.25),
                            blurRadius: 12)
                        ] : null),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(cat.$2,
                          color: active ? _C.primary : _C.onSurfaceVar, size: 22),
                        const SizedBox(height: 4),
                        Text(cat.$1.length > 6 ? cat.$1.substring(0, 5) : cat.$1,
                          style: TextStyle(
                            color: active ? _C.primary : _C.onSurfaceVar,
                            fontSize: 8,
                            fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                            letterSpacing: 1)),
                      ])));
                })),
            const SizedBox(height: 24),

            // ── Exercise header ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(catLabel == 'ALL' ? 'ALL EXERCISES' : catLabel,
                    style: const TextStyle(color: _C.onSurface, fontSize: 20,
                      fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                  GestureDetector(
                    onTap: () => context.push('/exercise-library'),
                    child: const Text('BROWSE ALL',
                      style: TextStyle(color: _C.primary, fontSize: 11,
                        fontWeight: FontWeight.w700, letterSpacing: 1.5))),
                ])),
            const SizedBox(height: 16),

            // ── Exercise hero cards ──────────────────────────────────────────
            ...filtered.take(5).map((ex) => _ExerciseHeroCard(
              exercise: ex,
              onTap: () {
                ref.read(selectedExerciseDetailProvider.notifier).state = ex;
                context.push('/exercise-detail');
              })),

            if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
                child: Center(
                  child: Text('No exercises found',
                    style: TextStyle(
                      color: _C.onSurfaceVar.withValues(alpha: 0.4), fontSize: 15)))),
          ]),
        ),
      ]),
    );
  }

  /// Opens the Workout Zone bound to the active session's own workout.
  ///
  /// The workout comes from the session (its snapshot, or its id) rather than
  /// from whatever happens to be in `selectedWorkoutProvider`, so resuming can
  /// never land on a different workout than the card advertises.
  Future<void> _resumeWorkout(WorkoutSessionRecord session) async {
    final workout = await bindSessionToSelectedWorkout(ref, session);
    if (!mounted) return;
    if (workout == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('That workout is no longer available.')));
      return;
    }
    context.go('/active-workout');
  }

  String _formatElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return 'Started ${h}h ${m}m ago';
    if (m > 0) return 'Started ${m}m ago';
    return 'Just started';
  }
}

// ── Stat Card ─────────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color iconColor;
  final String value;
  const _StatCard({required this.label, required this.icon,
    required this.iconColor, required this.value});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: _C.glassCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06))),
      child: Column(children: [
        Icon(icon, color: iconColor, size: 18),
        const SizedBox(height: 6),
        Text(value,
          style: const TextStyle(color: _C.onSurface, fontSize: 18,
            fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label,
          style: const TextStyle(color: _C.outline, fontSize: 8,
            fontWeight: FontWeight.w600, letterSpacing: 1)),
      ])));
}

// ── Nav Tile ──────────────────────────────────────────────────────────────────
class _NavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final Color color;
  final VoidCallback onTap;
  const _NavTile({required this.icon, required this.label, required this.sub,
    required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25))),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 18)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: color, fontSize: 13,
            fontWeight: FontWeight.w700)),
          Text(sub, style: TextStyle(color: color.withValues(alpha: 0.6),
            fontSize: 10)),
        ])),
        Icon(Icons.chevron_right, color: color.withValues(alpha: 0.5), size: 18),
      ])));
}

// ── PR Row ────────────────────────────────────────────────────────────────────
class _PRRow extends StatelessWidget {
  final Map<String, dynamic> pr;
  const _PRRow({required this.pr});

  @override
  Widget build(BuildContext context) {
    final name   = pr['exercise_name'] as String? ?? '';
    final weight = (pr['weight_kg'] as num?)?.toDouble() ?? 0;
    final reps   = pr['reps'] as int? ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _C.glassCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _C.amber.withValues(alpha: 0.2))),
      child: Row(children: [
        const Icon(Icons.emoji_events_rounded, color: _C.amber, size: 18),
        const SizedBox(width: 12),
        Expanded(child: Text(name,
          style: const TextStyle(color: _C.onSurface, fontSize: 13,
            fontWeight: FontWeight.w600))),
        Text('${weight.toStringAsFixed(1)} kg × $reps',
          style: const TextStyle(color: _C.amber, fontSize: 13,
            fontWeight: FontWeight.w700)),
      ]));
  }
}

// ── Exercise Hero Card ────────────────────────────────────────────────────────
class _ExerciseHeroCard extends StatelessWidget {
  final ExerciseDetail exercise;
  final VoidCallback onTap;
  const _ExerciseHeroCard({required this.exercise, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final levelColor = _levelColor(exercise.difficulty);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 340,
        margin: const EdgeInsets.only(bottom: 12),
        child: Stack(fit: StackFit.expand, children: [
          _heroImg(exercise),

          const DecoratedBox(decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.transparent, Color(0xCC131314), Color(0xFF131314)],
              stops: [0.3, 0.7, 1.0],
              begin: Alignment.topCenter, end: Alignment.bottomCenter))),

          // Level chip
          Positioned(
            top: 20, left: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: levelColor.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: levelColor.withValues(alpha: 0.5))),
              child: Text(exercise.difficulty.toUpperCase(),
                style: TextStyle(color: levelColor, fontSize: 9,
                  fontWeight: FontWeight.w700, letterSpacing: 1.5)))),

          // Bottom content
          Positioned(
            bottom: 20, left: 20, right: 20,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min, children: [
                Text(exercise.name,
                  style: const TextStyle(color: Colors.white, fontSize: 26,
                    fontWeight: FontWeight.w800, height: 1.1, letterSpacing: -0.5)),
                const SizedBox(height: 6),
                Row(children: [
                  Icon(Icons.adjust, color: _C.primary, size: 14),
                  const SizedBox(width: 4),
                  Text(exercise.muscleGroup.toUpperCase(),
                    style: const TextStyle(color: _C.onSurfaceVar, fontSize: 10,
                      fontWeight: FontWeight.w600, letterSpacing: 1)),
                  const SizedBox(width: 8),
                  Container(width: 3, height: 3,
                    decoration: BoxDecoration(shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.3))),
                  const SizedBox(width: 8),
                  Text(exercise.equipment.toUpperCase(),
                    style: const TextStyle(color: _C.onSurfaceVar, fontSize: 10,
                      fontWeight: FontWeight.w600, letterSpacing: 1)),
                ]),
              ])),
              const SizedBox(width: 16),
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [_C.inversePrimary, _C.primaryContainer],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                  boxShadow: const [BoxShadow(color: Color(0x55842BD2), blurRadius: 16)]),
                child: const Icon(Icons.arrow_forward_rounded,
                  color: Colors.white, size: 22)),
            ])),
        ])));
  }

  Widget _heroImg(ExerciseDetail ex) {
    if (ex.imageAssetPath != null) {
      return Image.asset(ex.imageAssetPath!, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _gradientHero(ex.muscleGroup));
    }
    if (ex.imageUrl != null) {
      return CachedNetworkImage(
        imageUrl: ex.imageUrl!, fit: BoxFit.cover,
        errorWidget: (_, __, ___) => _gradientHero(ex.muscleGroup),
        placeholder: (_, __) => _gradientHero(ex.muscleGroup));
    }
    return _gradientHero(ex.muscleGroup);
  }

  Color _levelColor(String d) {
    switch (d.toLowerCase()) {
      case 'beginner': return const Color(0xFFADC6FF);
      case 'advanced': return _C.tertiary;
      case 'elite': return _C.primary;
      default: return _C.onSurfaceVar;
    }
  }

  Widget _gradientHero(String muscle) {
    final colors = {
      'Chest': [const Color(0xFF2A1A4E), const Color(0xFF0E0E0F)],
      'Back': [const Color(0xFF0B2E1A), const Color(0xFF0E0E0F)],
      'Quads': [const Color(0xFF1A2E0B), const Color(0xFF0E0E0F)],
      'Glutes': [const Color(0xFF2E1A0B), const Color(0xFF0E0E0F)],
      'Hamstrings': [const Color(0xFF2E200B), const Color(0xFF0E0E0F)],
      'Core': [const Color(0xFF1A0B2E), const Color(0xFF0E0E0F)],
      'Shoulders': [const Color(0xFF0B1A2E), const Color(0xFF0E0E0F)],
    };
    final pair = colors[muscle] ?? [const Color(0xFF1A1A2E), const Color(0xFF0E0E0F)];
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: pair,
          begin: Alignment.topLeft, end: Alignment.bottomRight)));
  }
}

// ── Icon Button ───────────────────────────────────────────────────────────────
class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  const _IconBtn({required this.icon, required this.onTap, required this.tooltip});

  /// `tooltip` is required, and until now it was accepted and discarded: the
  /// build returned a bare GestureDetector, so the string reached neither a
  /// Tooltip nor the semantics tree and both call sites were unlabelled
  /// controls. Tooltip carries the message into semantics as well, so wiring
  /// the existing parameter labels them without inventing any copy.
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: _C.glassCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08))),
        child: Icon(icon, color: _C.onSurfaceVar, size: 20))));
}

// ═══════════════════════════════════════════════════════════════════════════
// FIT-014 · Workouts hub (coach-guided content state)
// FIT-015 · Workouts — no plan yet ("the empty state that matters most")
//
// Both are the SAME route, /train, distinguished by whether a plan exists.
// The hub previously rendered neither: it never read `assignedWorkoutsProvider`,
// so a member with an assigned plan was not shown it, and a member WITHOUT one
// saw a screen of zeros with no explanation.
//
// ── WHY `.when` AND NOT `.valueOrNull ?? []` ───────────────────────────────
// QA_CLOSURE_STANDARD §4: "`[]` from a failed read and `[]` from 'this member
// has none' are the same value at review time and different values in
// production." Collapsing them is the error→empty defect recorded as F-15.
// `assignedWorkoutsProvider` is a FutureProvider, so the three outcomes stay
// distinguishable — and this widget keeps them distinguishable.
// ═══════════════════════════════════════════════════════════════════════════
class _PlanSurface extends ConsumerWidget {
  const _PlanSurface();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assigned = ref.watch(assignedWorkoutsProvider);

    return assigned.when(
      loading: () => const _PlanLoading(),
      // Reuses the treatment this provider ALREADY has in
      // workout_list_screen.dart — "Your program could not be loaded" with a
      // Try again that invalidates the provider. EC-G8's sibling assertions
      // pin that copy, so it is approved in-repo; inventing a second phrasing
      // for the same failure would have been a new product voice.
      error: (_, __) => _PlanUnavailable(
          onRetry: () => ref.invalidate(assignedWorkoutsProvider)),
      data: (workouts) => workouts.isEmpty
          // The coach's name is deliberately NOT read here. Fetching it needs
          // an AsyncValue read whose failure would collapse to null — the
          // pattern EC-G8 ratchets — and a name is not worth an error swallow.
          // The neutral noun carries the same meaning.
          ? const _NoPlanYet()
          : _PlanContent(workouts: workouts),
    );
  }
}

/// No loading state is declared for /train in the authoritative package
/// (FIT-014 states: `default`; FIT-015: `empty`, `no plan`). Rather than invent
/// one, this reuses the app's existing quiet placeholder so the surface does
/// not flash content — and, critically, does not look like an empty plan.
class _PlanLoading extends StatelessWidget {
  const _PlanLoading();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: SizedBox(
          height: 64,
          child: Center(
            child: SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: _C.primary)),
          ),
        ),
      );
}

/// A plan that could not be loaded is NOT "no plan". Telling a member their
/// coach has not written them a programme when the request merely failed is the
/// same class of lie as the fabricated "0" streak.
///
/// The phrasing follows the pattern already shipped in
/// `booking_screen.dart:627-635` — "this is a connection problem, not an empty
/// schedule" — which is the one place in this repository that names the
/// distinction. No new product voice is invented.
class _PlanUnavailable extends StatelessWidget {
  final VoidCallback onRetry;
  const _PlanUnavailable({required this.onRetry});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _C.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _C.outline.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            Icon(Icons.wifi_off_rounded, color: _C.outline, size: 18),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Your program could not be loaded',
                style: TextStyle(color: _C.onSurfaceVar, fontSize: 13, height: 1.45)),
            ),
            const SizedBox(width: 8),
            Semantics(
              button: true,
              child: GestureDetector(
                onTap: onRetry,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
                  alignment: Alignment.center,
                  child: const Text('Try again',
                    style: TextStyle(color: _C.primary, fontSize: 13, fontWeight: FontWeight.w500)),
                ),
              ),
            ),
          ]),
        ),
      );
}

/// FIT-015. Copy is the board's, with one deliberate adaptation recorded in
/// docs/QA_EVIDENCE.md: the board reads "as soon as she publishes it", which
/// asserts a gender for whoever the member's coach happens to be. The sentence
/// is rephrased to carry the same meaning without that assertion.
class _NoPlanYet extends ConsumerWidget {
  const _NoPlanYet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // FIT-015 addresses the coach by name ("Message Nadia"). The name is real
    // data, and `coachAddressed` is the one place that decides whether it is
    // safe to use it — see that function for why a failed read must not
    // produce a name.
    final coach = ref.watch(assignedCoachProvider);
    final who = coachAddressed(coach,
        withName: (name) => name,
        // Already shipping in this block before the change.
        fallback: 'Your coach');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // `state` + `sico` — the empty-state block with its icon disc.
        Center(
          child: Column(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: _C.surfaceContainerHigh, shape: BoxShape.circle),
              child: Icon(Icons.fitness_center, color: _C.outline, size: 22),
            ),
            const SizedBox(height: 14),
            const Text('No workout assigned yet',
                style: TextStyle(color: _C.onSurface, fontSize: 20, fontWeight: FontWeight.w500)),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300), // board: max-width 30ch
              child: Text(
                "$who is building your first week. It'll appear here as soon as "
                "it's published — usually within a day of your intake.",
                textAlign: TextAlign.center,
                style: const TextStyle(color: _C.onSurfaceVar, fontSize: 13, height: 1.5)),
            ),
            const SizedBox(height: 22),
            // `fc-btn2` — secondary, auto width.
            Semantics(
              button: true,
              child: GestureDetector(
                onTap: () => context.push('/exercise-library'),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 52),
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _C.outline),
                  ),
                  child: const Text('Browse the exercise library',
                      style: TextStyle(color: _C.onSurface, fontSize: 15, fontWeight: FontWeight.w500)),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 24),
        // "In the meantime" — the board's two escape hatches, above a hairline.
        Container(
          padding: const EdgeInsets.only(top: 20),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: _C.outline.withValues(alpha: 0.4)))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('IN THE MEANTIME', style: _micStyle),
            const SizedBox(height: 6),
            _MeantimeRow(
              label: 'Log something you did yourself',
              onTap: () => context.push('/workouts')),
            _MeantimeRow(
              // FIT-015 declares "Message Nadia" — the client's coach, by name.
              label: coachAddressed(coach,
                  withName: (name) => 'Message $name',
                  // The wording this row already shipped, true with no coach.
                  fallback: 'Message your coach'),
              showDivider: false,
              onTap: () => context.go('/messages')),
          ]),
        ),
        const SizedBox(height: 8),
      ]),
    );
  }

  static const _micStyle = TextStyle(
      color: _C.outline, fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 1.54);
}

class _MeantimeRow extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool showDivider;
  const _MeantimeRow({required this.label, required this.onTap, this.showDivider = true});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44), // `tap` floor
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: showDivider
                ? BoxDecoration(
                    border: Border(
                        bottom: BorderSide(color: _C.outline.withValues(alpha: 0.4))))
                : null,
            child: Row(children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        color: _C.onSurface, fontSize: 15, fontWeight: FontWeight.w500))),
              Icon(Icons.arrow_forward, color: _C.primary, size: 14),
            ]),
          ),
        ),
      );
}

/// FIT-014's content state: today's session as a hero card, then the week.
///
/// The hero is shown ONLY when a session is actually scheduled for today. The
/// board's pill reads "Today · assigned by …", so rendering a different day's
/// workout under it would state something untrue. FIT-014 declares a single
/// `default` state and the package draws no "plan exists but nothing today"
/// frame, so that case falls through to the week list alone — recorded as a
/// design gap rather than invented.
class _PlanContent extends StatelessWidget {
  final List<Workout> workouts;
  const _PlanContent({required this.workouts});

  @override
  Widget build(BuildContext context) {
    final today = todaysSession(workouts);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (today != null) _TodayHeroCard(workout: today),
      _ThisWeek(workouts: workouts),
    ]);
  }
}

/// FIT-014 `fc-card` — today's assigned session.
///
/// Every value is read from the Workout: title, exercise count, duration, the
/// heaviest prescribed load, the coach's name and the scheduled date. Nothing
/// is hardcoded and nothing is estimated.
///
/// The hero image is the asset the design declares for this frame
/// (`img/exercise-deadlift.jpg`, already present in assets/). `Workout` carries
/// no image field, so per-workout photography is a real gap of the GAP-03
/// class ("photography ... Wave 2 placeholders intentional") and is recorded as
/// such — the single declared asset is used rather than inventing a mapping
/// from category to picture.
class _TodayHeroCard extends ConsumerWidget {
  final Workout workout;
  const _TodayHeroCard({required this.workout});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = workoutSummaryLine(workout);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16), // `fc-card`
        child: Container(
          decoration: BoxDecoration(
            color: _C.surfaceContainerHigh,
            border: Border.all(color: _C.outline.withValues(alpha: 0.18)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Image.asset('assets/images/exercise-deadlift.jpg',
                height: 132, width: double.infinity,
                fit: BoxFit.cover,
                alignment: const Alignment(0, -0.36), // board: object-position 50% 32%
                errorBuilder: (_, __, ___) =>
                    Container(height: 132, color: _C.surfaceContainerHigh)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // `pill` — violet-muted fill, accent text.
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _C.primaryContainer.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(todayPillLabel(workout),
                      style: const TextStyle(
                          color: _C.primary, fontSize: 11, fontWeight: FontWeight.w500)),
                ),
                const SizedBox(height: 14),
                Text(workout.title,
                    style: const TextStyle(
                        color: _C.onSurface, fontSize: 24,
                        fontWeight: FontWeight.w500, letterSpacing: -0.6, height: 1.1)),
                if (summary.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(summary,
                      style: const TextStyle(color: _C.onSurfaceVar, fontSize: 13, height: 1.5)),
                ],
                const SizedBox(height: 18),
                Semantics(
                  button: true,
                  child: GestureDetector(
                    onTap: () {
                      // The established identity mechanism — the same one
                      // workout_list_screen and active_workout_screen use. No
                      // second identity path is introduced.
                      ref.read(selectedWorkoutProvider.notifier).state = workout;
                      context.go('/active-workout');
                    },
                    child: Container(
                      height: 52, // `fc-btn`
                      width: double.infinity,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _C.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('Begin session',
                          style: TextStyle(
                              color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
                    ),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// FIT-014's "This week" list.
///
/// Every rule the rows follow lives in `domain/week_row.dart`, with the board
/// markup they came from quoted beside them. Status is derived from the
/// workout itself — `isCompleted` and `scheduledDate` — never from a hardcoded
/// position in the list.
class _ThisWeek extends ConsumerWidget {
  final List<Workout> workouts;
  const _ThisWeek({required this.workouts});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('THIS WEEK', style: _NoPlanYet._micStyle),
          const SizedBox(height: 8),
          ...workouts.map((w) => WeekRowTile(workout: w)),
        ]),
      );
}
