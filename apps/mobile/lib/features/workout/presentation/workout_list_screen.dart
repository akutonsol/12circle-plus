import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../data/models/workout_model.dart';
import '../domain/workout_provider.dart';

class _C {
  static const surfaceContainer    = Color(0xFF201F20);
  static const surfaceContainerHigh= Color(0xFF2A2A2B);
  static const glassCard           = Color(0x99201F20);
  static const primary             = Color(0xFFDDB7FF);
  static const primaryContainer    = Color(0xFFB76DFF);
  static const inversePrimary      = Color(0xFF842BD2);
  static const onSurface           = Color(0xFFE5E2E3);
  static const onSurfaceVar        = Color(0xFFCDC3D0);
  static const outline             = Color(0xFF968E99);
  static const outlineVar          = Color(0xFF4B444F);
  static const tertiary            = Color(0xFF6FFBBE);
  static const amber               = Color(0xFFFFD580);
  static const error               = Color(0xFFEF4444);
}

// ── Static sample items (browse section) ─────────────────────────────────────
class _WorkoutItem {
  final String title;
  final String image;
  final String tag;
  final Color tagColor;
  final String category;
  final String tab;
  final String coach;
  final String duration;
  final IconData categoryIcon;
  final String? exercises;
  final String? kcal;
  final double? intensity;
  final String? intensityLabel;
  /// The domain `Workout.id` this card stands for, or null when no workout
  /// exists behind it.
  ///
  /// This replaces matching on `title`. Title matching was not merely fragile,
  /// it was already broken: this list's `'Glute & Hamstring\nFocus'` can never
  /// equal the domain's `'Glute and Hamstring Focus'`, so that card always fell
  /// through to a detail screen with no identity and showed a workout the user
  /// had not chosen.
  ///
  /// Four of the five cards below have no domain workout at all — they are
  /// presentation samples. `null` states that honestly instead of resolving to
  /// whichever workout happens to share a word.
  final String? workoutId;

  const _WorkoutItem({
    required this.title, required this.image, required this.tag,
    required this.tagColor, required this.category, required this.tab,
    required this.coach, required this.duration, required this.categoryIcon,
    this.workoutId,
    this.exercises, this.kcal, this.intensity, this.intensityLabel,
  });
}

const _tabs = ['All', 'Strength', 'Cardio', 'HIIT', 'Recovery'];

const _sampleWorkouts = [
  _WorkoutItem(
    title: 'Full Body Strength',
    workoutId: '1', // domain Workout id, workout_service.getSampleWorkouts()
    image: 'assets/images/workout-full-body.jpg',
    tag: 'INTERMEDIATE', tagColor: _C.primary,
    category: 'STRENGTH PROGRAM', tab: 'Strength',
    coach: '12 Circle', duration: '45 min',
    categoryIcon: Icons.fitness_center_outlined,
    exercises: '8 EXERCISES', kcal: '420 KCAL',
  ),
  _WorkoutItem(
    title: 'Glute & Hamstring\nFocus',
    workoutId: '2', // domain title is 'Glute and Hamstring Focus' — ids, not titles
    image: 'assets/images/workout-glute.jpg',
    tag: 'BEGINNER FRIENDLY', tagColor: _C.tertiary,
    category: 'LOWER BODY', tab: 'Strength',
    coach: '12 Circle', duration: '50 min',
    categoryIcon: Icons.directions_run_outlined,
  ),
  _WorkoutItem(
    title: 'Metabolic Overdrive',
    image: 'assets/images/workout-hiit.jpg',
    tag: 'HIIT BURN', tagColor: _C.tertiary,
    category: 'HIIT', tab: 'HIIT',
    coach: 'Coach Mike', duration: '30 min',
    categoryIcon: Icons.bolt_outlined,
    intensity: 0.9, intensityLabel: 'INTENSITY: 9/10',
  ),
  _WorkoutItem(
    title: 'Morning Cardio Blast',
    image: 'assets/images/workout-full-body.jpg',
    tag: 'BEGINNER', tagColor: _C.tertiary,
    category: 'CARDIO', tab: 'Cardio',
    coach: '12 Circle', duration: '25 min',
    categoryIcon: Icons.directions_run_outlined,
    exercises: '6 EXERCISES', kcal: '280 KCAL',
  ),
  _WorkoutItem(
    title: 'Active Recovery Flow',
    image: 'assets/images/workout-glute.jpg',
    tag: 'ALL LEVELS', tagColor: _C.primary,
    category: 'RECOVERY', tab: 'Recovery',
    coach: '12 Circle', duration: '20 min',
    categoryIcon: Icons.self_improvement_outlined,
    exercises: '5 EXERCISES', kcal: '120 KCAL',
  ),
];

class WorkoutListScreen extends ConsumerStatefulWidget {
  const WorkoutListScreen({super.key});

  @override
  ConsumerState<WorkoutListScreen> createState() => _WorkoutListScreenState();
}

class _WorkoutListScreenState extends ConsumerState<WorkoutListScreen> {
  int _selectedTab = 0;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  List<_WorkoutItem> get _filteredWorkouts {
    return _sampleWorkouts.where((w) {
      final matchTab = _selectedTab == 0 || w.tab == _tabs[_selectedTab];
      final q = _searchQuery.toLowerCase();
      final matchSearch = q.isEmpty ||
          w.title.toLowerCase().contains(q) ||
          w.coach.toLowerCase().contains(q) ||
          w.category.toLowerCase().contains(q);
      return matchTab && matchSearch;
    }).toList();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _startWorkout(Workout workout) {
    ref.read(selectedWorkoutProvider.notifier).state = workout;
    context.go('/active-workout');
  }

  /// Open FIT-016 for [item]. The design calls `/workout-detail` "review before
  /// committing", so a tap reviews the session; starting it is the detail
  /// screen's own "Begin session".
  ///
  /// Identity is resolved by `Workout.id`, never by title. When the card has no
  /// domain workout behind it, the selection is CLEARED rather than left
  /// pointing at whatever was opened last — otherwise the previous workout's
  /// data would appear under this card's name, which is the defect this whole
  /// change exists to remove.
  void _openDetail(_WorkoutItem item, List<Workout> catalogue) {
    final id = item.workoutId;
    final resolved = id == null
        ? null
        : catalogue.where((w) => w.id == id).firstOrNull;
    ref.read(selectedWorkoutProvider.notifier).state = resolved;
    // `push`, not `go`: the detail screen is a review step the user comes back
    // from, so it must leave a pop-able entry. With `go` the route replaces the
    // list, `canPop()` is false, and the detail screen's Back button falls back
    // to /train instead of returning to the list the user came from. Verified
    // on-device. This matches the convention already used for /workouts
    // (train_hub_screen.dart:123).
    context.push('/workout-detail');
  }

  bool _generatingAi = false;
  Future<void> _generateAiWorkout() async {
    setState(() => _generatingAi = true);
    Workout? workout;
    Object? failure;
    try {
      workout = await generateAiWorkout();
    } catch (e) {
      failure = e;
    }
    if (!mounted) return;
    setState(() => _generatingAi = false);
    if (workout != null) {
      _startWorkout(workout);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(failure == null
          ? 'The generator had nothing to suggest right now.'
          : 'Could not generate a workout: $failure')));
  }

  @override
  Widget build(BuildContext context) {
    final assignedAsync = ref.watch(assignedWorkoutsProvider);
    final sampleWorkouts = ref.watch(workoutsProvider);

    return AppScaffold(
      showBackButton: true,
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 160),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── Header row ──
                Row(children: [
                  const Expanded(
                    child: Text('Workouts',
                      style: TextStyle(color: _C.onSurface, fontSize: 32,
                        fontWeight: FontWeight.w800, letterSpacing: -1))),
                  GestureDetector(
                    onTap: () => context.go('/workout-history'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _C.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _C.outlineVar.withValues(alpha: 0.3))),
                      child: const Row(children: [
                        Icon(Icons.history, color: _C.primary, size: 16),
                        SizedBox(width: 6),
                        Text('History', style: TextStyle(color: _C.primary,
                          fontSize: 12, fontWeight: FontWeight.w600)),
                      ]))),
                ]),
                const SizedBox(height: 16),

                // ── AI coach adjustment for today ──
                ref.watch(coachAdjustmentProvider).maybeWhen(
                  data: (adj) => adj == null ? const SizedBox.shrink() : _CoachAdjustmentBanner(adj: adj),
                  orElse: () => const SizedBox.shrink()),

                // ── Search ──
                Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: _C.surfaceContainerHigh.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _C.outlineVar.withValues(alpha: 0.2))),
                  child: Row(children: [
                    const SizedBox(width: 14),
                    const Icon(Icons.search, color: _C.outline, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        style: const TextStyle(color: _C.onSurface, fontSize: 14),
                        onChanged: (v) => setState(() => _searchQuery = v),
                        decoration: const InputDecoration(
                          hintText: 'Search programs or trainers...',
                          hintStyle: TextStyle(color: _C.outline, fontSize: 14),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero),
                      )),
                  ])),
                const SizedBox(height: 14),

                // ── Generate an AI session for today ──
                GestureDetector(
                  onTap: _generatingAi ? null : _generateAiWorkout,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF842BD2), Color(0xFFB76DFF)]),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: _C.inversePrimary.withValues(alpha: 0.35),
                        blurRadius: 16, offset: const Offset(0, 6))]),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      if (_generatingAi)
                        const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      else
                        const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Text(_generatingAi ? 'Building your session…' : 'Generate AI Workout',
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                    ]))),
                const SizedBox(height: 20),

                // ── Assigned program section ──
                assignedAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.only(bottom: 24),
                    child: _AssignedLoadingCard()),
                  // Named, with a retry. Rendering nothing here is what turned
                  // "your program could not be read" into "you have no
                  // program" — the client then reasonably concludes their coach
                  // never assigned one.
                  error: (e, __) => _AssignedErrorCard(
                      error: e,
                      onRetry: () => ref.invalidate(assignedWorkoutsProvider)),
                  data: (workouts) => workouts.isEmpty
                      ? const SizedBox.shrink()
                      : _AssignedProgramSection(
                          workouts: workouts,
                          sampleWorkouts: sampleWorkouts,
                          onStart: _startWorkout)),

                // ── Filter tabs ──
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _tabs.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final active = i == _selectedTab;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedTab = i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          decoration: BoxDecoration(
                            color: active
                                ? _C.primary.withValues(alpha: 0.15)
                                : _C.surfaceContainerHigh.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: active
                                  ? _C.primary.withValues(alpha: 0.5)
                                  : _C.outlineVar.withValues(alpha: 0.2))),
                          alignment: Alignment.center,
                          child: Text(_tabs[i],
                            style: TextStyle(
                              color: active ? _C.primary : _C.onSurfaceVar,
                              fontSize: 13,
                              fontWeight: active ? FontWeight.w700 : FontWeight.w400))));
                    })),
                const SizedBox(height: 16),

                // ── Browse section header ──
                const Text('BROWSE WORKOUTS',
                  style: TextStyle(color: _C.onSurfaceVar, fontSize: 11,
                    fontWeight: FontWeight.w700, letterSpacing: 1.5)),
                const SizedBox(height: 12),

                // ── Sample workout cards ──
                ..._filteredWorkouts.isEmpty
                    ? [const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(child: Text('No workouts match your search.',
                          style: TextStyle(color: _C.outline, fontSize: 14))))]
                    : _filteredWorkouts.map((w) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _WorkoutCard(
                          workout: w,
                          onTap: () => _openDetail(w, sampleWorkouts)))),
              ],
            ),
          ),

          // ── Floating Exercise Library button ──
          Positioned(
            bottom: 100,
            left: 20, right: 20,
            child: GestureDetector(
              onTap: () => context.go('/exercise-database'),
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: const LinearGradient(
                    colors: [_C.primaryContainer, _C.inversePrimary],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight),
                  boxShadow: const [
                    BoxShadow(color: Color(0x73842BD2), blurRadius: 24, offset: Offset(0, 8))],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.menu_book_outlined, color: Colors.white, size: 20),
                    SizedBox(width: 10),
                    Text('EXERCISE LIBRARY',
                      style: TextStyle(color: Colors.white, fontSize: 13,
                        fontWeight: FontWeight.w700, letterSpacing: 2)),
                  ]),
              ))),
        ],
      ),
    );
  }
}

// ── Assigned program section ──────────────────────────────────────────────────
class _AssignedProgramSection extends StatelessWidget {
  final List<Workout> workouts;
  final List<Workout> sampleWorkouts;
  final void Function(Workout) onStart;
  const _AssignedProgramSection({
    required this.workouts, required this.sampleWorkouts, required this.onStart});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _C.amber.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _C.amber.withValues(alpha: 0.3))),
          child: const Row(children: [
            Icon(Icons.star_rounded, color: _C.amber, size: 13),
            SizedBox(width: 4),
            Text('MY PROGRAM', style: TextStyle(color: _C.amber, fontSize: 10,
              fontWeight: FontWeight.w700, letterSpacing: 1)),
          ])),
      ]),
      const SizedBox(height: 12),
      ...workouts.map((w) => _AssignedWorkoutCard(workout: w, onStart: () => onStart(w))),
      const SizedBox(height: 8),
      const Divider(color: Color(0xFF2A2A2B)),
      const SizedBox(height: 16),
    ]);
  }
}

class _AssignedWorkoutCard extends ConsumerWidget {
  final Workout workout;
  final VoidCallback onStart;
  const _AssignedWorkoutCard({required this.workout, required this.onStart});

  static const _amber = Color(0xFFFFD479);
  static const _mint  = Color(0xFF6FFBBE);

  static String _date(String? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${m[d.month - 1]} ${d.day}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusMap = ref.watch(programSessionStatusProvider).valueOrNull ?? const {};
    final s = sessionStatusFor(statusMap, workout);
    final status = s?['status'] as String?;
    final inProgress = status == 'in_progress';
    final completed = status == 'completed';

    final totalSets = workout.exercises.fold<int>(0, (sum, e) => sum + e.sets.length);
    final loggedSets = (s?['logged_sets'] as int?) ?? 0;
    final pct = (inProgress && totalSets > 0)
        ? (loggedSets / totalSets).clamp(0.0, 1.0) : 0.0;

    final accent = inProgress ? _amber : completed ? _mint : _C.inversePrimary;
    final btnLabel = inProgress ? 'RESUME' : completed ? 'AGAIN' : 'START';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _C.glassCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.25))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12)),
            child: Icon(
              inProgress ? Icons.play_circle_outline
                : completed ? Icons.check_circle_outline
                : Icons.fitness_center,
              color: accent, size: 24)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(workout.title,
                style: const TextStyle(color: _C.onSurface, fontSize: 15,
                  fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              if (inProgress)
                Text('In progress · Started ${_date(s?['started_at'] as String?)} · ~${workout.estimatedDuration} min',
                  style: const TextStyle(color: _amber, fontSize: 12, fontWeight: FontWeight.w600))
              else if (completed)
                Text('Completed · ${_date(s?['completed_at'] as String?)} · ~${workout.estimatedDuration} min',
                  style: const TextStyle(color: _mint, fontSize: 12, fontWeight: FontWeight.w600))
              else
                Row(children: [
                  const Icon(Icons.list_alt_outlined, color: _C.onSurfaceVar, size: 13),
                  const SizedBox(width: 4),
                  Text('${workout.exercises.length} exercises',
                    style: const TextStyle(color: _C.onSurfaceVar, fontSize: 12)),
                  const SizedBox(width: 10),
                  const Icon(Icons.timer_outlined, color: _C.onSurfaceVar, size: 13),
                  const SizedBox(width: 4),
                  Text('~${workout.estimatedDuration} min',
                    style: const TextStyle(color: _C.onSurfaceVar, fontSize: 12)),
                ]),
            ])),
          GestureDetector(
            onTap: onStart,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: inProgress
                      ? [_amber, const Color(0xFFFFB14B)]
                      : completed
                          ? [_mint, const Color(0xFF35C58E)]
                          : const [_C.inversePrimary, _C.primaryContainer],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(10)),
              child: Text(btnLabel,
                style: TextStyle(
                  color: (inProgress || completed) ? Colors.black87 : Colors.white,
                  fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1)))),
        ]),
        // Progress bar for an in-progress program.
        if (inProgress) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 6,
                  backgroundColor: _C.outlineVar.withValues(alpha: 0.25),
                  valueColor: const AlwaysStoppedAnimation<Color>(_amber)),
              ),
            ),
            const SizedBox(width: 10),
            Text('${(pct * 100).round()}%',
              style: const TextStyle(color: _amber, fontSize: 12, fontWeight: FontWeight.w800)),
          ]),
        ],
      ]));
  }
}

class _AssignedLoadingCard extends StatelessWidget {
  const _AssignedLoadingCard();
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: _C.glassCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.outlineVar.withValues(alpha: 0.2))),
      child: const Center(
        child: SizedBox(width: 20, height: 20,
          child: CircularProgressIndicator(color: _C.primary, strokeWidth: 2))));
  }
}

// ── Workout Card (browse) ─────────────────────────────────────────────────────
class _WorkoutCard extends StatelessWidget {
  final _WorkoutItem workout;
  final VoidCallback onTap;
  const _WorkoutCard({required this.workout, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: _C.glassCard,
          border: Border.all(color: const Color(0x0DFFFFFF))),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Image
          SizedBox(
            height: 200,
            child: Stack(fit: StackFit.expand, children: [
              Image.asset(workout.image, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(color: _C.surfaceContainer)),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Color(0x88000000)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter))),
              Positioned(
                top: 12, right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: workout.tagColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: workout.tagColor.withValues(alpha: 0.5))),
                  child: Text(workout.tag,
                    style: TextStyle(color: workout.tagColor, fontSize: 9,
                      fontWeight: FontWeight.w700, letterSpacing: 1.5)))),
              Positioned(
                bottom: 12, left: 12,
                child: Row(children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: _C.glassCard, borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _C.outlineVar.withValues(alpha: 0.3))),
                    child: Icon(workout.categoryIcon, color: _C.primary, size: 16)),
                  const SizedBox(width: 8),
                  Text(workout.category, style: const TextStyle(color: _C.primary,
                    fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
                ])),
            ])),

          // Info
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(workout.title,
                style: const TextStyle(color: _C.onSurface, fontSize: 20,
                  fontWeight: FontWeight.w700, height: 1.2)),
              const SizedBox(height: 6),
              Text('${workout.coach} • ${workout.duration}',
                style: const TextStyle(color: _C.onSurfaceVar, fontSize: 13)),
              if (workout.exercises != null) ...[
                const SizedBox(height: 10),
                Row(children: [
                  const Icon(Icons.list_alt_outlined, color: _C.onSurfaceVar, size: 16),
                  const SizedBox(width: 6),
                  Text(workout.exercises!, style: const TextStyle(color: _C.onSurfaceVar,
                    fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1)),
                  const SizedBox(width: 16),
                  const Icon(Icons.local_fire_department_outlined, color: _C.onSurfaceVar, size: 16),
                  const SizedBox(width: 6),
                  Text(workout.kcal!, style: const TextStyle(color: _C.onSurfaceVar,
                    fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1)),
                ]),
              ],
              if (workout.intensity != null) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: workout.intensity,
                    backgroundColor: _C.surfaceContainerHigh,
                    valueColor: const AlwaysStoppedAnimation<Color>(_C.tertiary),
                    minHeight: 4)),
                const SizedBox(height: 6),
                Text(workout.intensityLabel!,
                  style: const TextStyle(color: _C.tertiary, fontSize: 10,
                    fontWeight: FontWeight.w700, letterSpacing: 1.5)),
              ],
            ])),
        ])));
  }
}

// ── Today's AI coach adjustment banner ────────────────────────────────────────
class _CoachAdjustmentBanner extends StatelessWidget {
  final CoachAdjustment adj;
  const _CoachAdjustmentBanner({required this.adj});

  String _humanize(String s) => s.split(RegExp(r'[_\s]+'))
      .where((w) => w.isNotEmpty).map((w) => '${w[0].toUpperCase()}${w.substring(1)}').join(' ');

  @override
  Widget build(BuildContext context) {
    final d = adj.intensityDelta;
    final downshift = d < 0;
    final accent = d == 0 ? _C.primary : (downshift ? _C.amber : _C.tertiary);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          accent.withValues(alpha: 0.14), _C.surfaceContainerHigh.withValues(alpha: 0.5)],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.35))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.auto_awesome_rounded, color: accent, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text('COACH: ${adj.title.toUpperCase()}',
            style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8),
            maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 8),
        Text(adj.body, style: const TextStyle(color: _C.onSurfaceVar, fontSize: 13, height: 1.4)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (d != 0)
            _tag(downshift ? Icons.trending_down_rounded : Icons.trending_up_rounded,
              'Intensity ${d > 0 ? '+' : ''}$d%', accent),
          if (adj.focus != null && adj.focus!.isNotEmpty)
            _tag(Icons.center_focus_strong_rounded, 'Focus: ${_humanize(adj.focus!)}', _C.primary),
        ]),
      ]),
    );
  }

  Widget _tag(IconData icon, String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.35))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: color, size: 13), const SizedBox(width: 5),
      Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    ]));
}

/// The assigned program could not be read.
///
/// Distinct from having no program: the request or the decode failed, the
/// program is still there, and the client is offered a retry rather than a
/// silent absence.
class _AssignedErrorCard extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const _AssignedErrorCard({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _C.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.error.withValues(alpha: 0.4))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.error_outline_rounded, color: _C.error, size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Your program could not be loaded',
              style: TextStyle(color: _C.onSurface, fontSize: 14,
                fontWeight: FontWeight.w700))),
        ]),
        // ERR-2: this second line printed the raw exception beneath the
        // sentence above. A PostgREST error carries table, column and
        // constraint text; the human sentence already says what happened, so
        // the detail line is removed rather than reworded.
        const SizedBox(height: 10),
        TextButton(
          onPressed: onRetry,
          child: const Text('Try again',
            style: TextStyle(color: _C.primary, fontWeight: FontWeight.w700))),
      ]));
  }
}
