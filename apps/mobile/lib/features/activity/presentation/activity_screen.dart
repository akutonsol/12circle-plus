import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/domain/auth_provider.dart';
import '../../nutrition/domain/nutrition_provider.dart';
import '../../coach/domain/coach_ecosystem_provider.dart';
import '../../dashboard/domain/dashboard_provider.dart';
import '../../challenges/domain/challenge_provider.dart';
import '../../challenges/data/models/challenge_model.dart';
import '../../community/domain/community_provider.dart';
import '../../home/domain/home_session_card.dart';
import '../../workout/domain/workout_provider.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
class _C {
  static const bg           = Color(0xFF0A0A0B);
  static const surfContHigh = Color(0xFF222A3D);
  static const primary      = Color(0xFFDDB7FF);
  static const brand        = Color(0xFFA855F7);
  static const onSurface    = Color(0xFFDAE2FD);
  static const onSurfVar    = Color(0xFFCFC2D6);
  static const tertiary     = Color(0xFFF8ACFF);
  static const green        = Color(0xFF4ADE80);
  static const teal         = Color(0xFF6FFBBE);
  static const blue         = Color(0xFF93C5FD);
  static const error        = Color(0xFFFFB4AB);
}

// ── Activity Screen ───────────────────────────────────────────────────────────
class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});
  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
        SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent));
    final topPad = MediaQuery.of(context).padding.top;
    final userName = ref.watch(currentFirstNameProvider);

    return Scaffold(
      backgroundColor: _C.bg,
      body: Stack(fit: StackFit.expand, children: [
            SingleChildScrollView(
              padding: EdgeInsets.only(top: topPad + 64 + 16, left: 20, right: 20, bottom: 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Activity',
                  style: TextStyle(color: _C.onSurface, fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 16),

                // ── Daily Workout Card ─────────────────────────────────────────
                _DailyWorkoutCard(),
                const SizedBox(height: 16),

                // ── Streak + Water row ─────────────────────────────────────────
                Row(children: [
                  Expanded(child: _StreakCard()),
                  const SizedBox(width: 12),
                  Expanded(child: _WaterTrackerCard()),
                ]),
                const SizedBox(height: 16),

                // ── Performance ring card ──────────────────────────────────────
                _PerformanceCard(),
                const SizedBox(height: 16),

                // ── Daily steps + Macros row ───────────────────────────────────
                Row(children: [
                  Expanded(child: _StepsCard()),
                  const SizedBox(width: 12),
                  Expanded(child: _CaloriesCard()),
                ]),
                const SizedBox(height: 16),

                // ── Nutrition 2×2 grid ─────────────────────────────────────────
                _NutritionGrid(),
                const SizedBox(height: 16),

                // ── Motivational Quote ─────────────────────────────────────────
                _MotivationalQuoteCard(),
                const SizedBox(height: 16),

                // ── Challenge section ──────────────────────────────────────────
                _ChallengeSection(),
                const SizedBox(height: 16),

                // ── Community section ──────────────────────────────────────────
                _CommunitySection(),
              ]),
            ),

            // Fixed blur header
            Positioned(
              top: 0, left: 0, right: 0,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    height: topPad + 64,
                    padding: EdgeInsets.only(top: topPad, left: 20, right: 20),
                    decoration: BoxDecoration(
                      color: _C.bg.withValues(alpha: 0.6),
                      border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)))),
                    child: Row(children: [
                      GestureDetector(
                        onTap: () => context.go('/profile'),
                        child: _Avatar()),
                      const SizedBox(width: 12),
                      Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Good Morning',
                          style: TextStyle(color: _C.onSurfVar.withValues(alpha: 0.6),
                            fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.5)),
                        Text(userName,
                          style: const TextStyle(color: _C.onSurface, fontSize: 20, fontWeight: FontWeight.w700)),
                      ]),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => context.go('/messages'),
                        child: _HeaderBtn(icon: Icons.chat_bubble_outline_rounded)),
                      const SizedBox(width: 8),
                      _ShakingBell(),
                    ]),
                  ),
                ),
              ),
            ),
      ]),
    );
  }
}

// ── Daily Workout Card ────────────────────────────────────────────────────────
class _DailyWorkoutCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The same session, described the same way, as Home's Today card — see
    // `home/domain/home_session_card.dart`. This card read `name`,
    // `duration_minutes` and `calories_burned` off a program_workouts row, which
    // has none of them (`title`, `estimated_minutes`, and no energy figure), so
    // every client — with a plan, on a rest day, or with no coach — was shown
    // "Full Body Strength · 45 min · ~380 kcal". That is F-20 again.
    final session = homeSession(ref.watch(assignedWorkoutsProvider));
    final badges = homeSessionBadges(session.workout);
    final title = session.title ?? session.emptyLine;

    return GestureDetector(
      onTap: () => context.go('/train'),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF2D1260), Color(0xFF1A1035)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _C.brand.withValues(alpha: 0.4)),
          boxShadow: [BoxShadow(color: _C.brand.withValues(alpha: 0.15), blurRadius: 20)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _C.brand.withValues(alpha: 0.25)),
              child: const Icon(Icons.fitness_center_rounded, color: _C.primary, size: 22)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("TODAY'S WORKOUT",
                style: TextStyle(color: _C.primary.withValues(alpha: 0.7),
                  fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
              const SizedBox(height: 3),
              Text(title,
                style: const TextStyle(color: _C.onSurface, fontSize: 16, fontWeight: FontWeight.w700)),
            ])),
            if (session.canBegin)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _C.brand,
                borderRadius: BorderRadius.circular(999),
                boxShadow: [BoxShadow(color: _C.brand.withValues(alpha: 0.4), blurRadius: 12)]),
              child: const Text('Start', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700))),
          ]),
          // Nothing to begin: the title line already says why. No badges, no
          // progress bar for a session that does not exist.
          if (session.canBegin) ...[
          if (badges.isNotEmpty) ...[
          const SizedBox(height: 14),
          Row(children: [
            for (final (i, b) in badges.indexed) ...[
              if (i > 0) const SizedBox(width: 10),
              _WorkoutBadge(
                icon: b.endsWith(' min') ? Icons.schedule_rounded : Icons.fitness_center_rounded,
                text: b, color: _C.teal),
            ],
          ]),
          ],
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: 0.0,
              minHeight: 5,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: const AlwaysStoppedAnimation<Color>(_C.brand))),
          const SizedBox(height: 6),
          Text('Not started yet', style: TextStyle(color: _C.onSurfVar.withValues(alpha: 0.5), fontSize: 11)),
          ],
        ]),
      ),
    );
  }
}

class _WorkoutBadge extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _WorkoutBadge({required this.icon, required this.text, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: 0.25))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: color, size: 12),
      const SizedBox(width: 5),
      Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    ]));
}

// ── Streak Card ───────────────────────────────────────────────────────────────
class _StreakCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streakAsync = ref.watch(streakProvider);
    final streak = streakAsync.valueOrNull ?? 0;
    return _GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _C.brand.withValues(alpha: 0.2)),
            child: const Icon(Icons.local_fire_department_rounded, color: _C.primary, size: 18)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _C.brand.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(999)),
            child: Text(streak >= 7 ? '🔥 Hot' : 'Active',
              style: TextStyle(color: _C.primary, fontSize: 9, fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 12),
        Text('$streak',
          style: const TextStyle(color: _C.onSurface, fontSize: 36, fontWeight: FontWeight.w800, height: 1)),
        Text('day streak', style: TextStyle(color: _C.onSurfVar.withValues(alpha: 0.7), fontSize: 12)),
        const SizedBox(height: 10),
        Text(streak == 0 ? 'Start today!' : streak >= 7 ? 'Keep it up!' : 'Building momentum',
          style: TextStyle(color: _C.primary.withValues(alpha: 0.8), fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ── Water Tracker Card ────────────────────────────────────────────────────────
class _WaterTrackerCard extends ConsumerWidget {
  static const _goal = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(waterIntakeProvider);
    return _GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF38BDF8).withValues(alpha: 0.2)),
            child: const Icon(Icons.water_drop_rounded, color: Color(0xFF38BDF8), size: 18)),
          const Spacer(),
          Text('$current/$_goal', style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 12),
        Text('$current',
          style: const TextStyle(color: _C.onSurface, fontSize: 36, fontWeight: FontWeight.w800, height: 1)),
        const Text('glasses', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12)),
        const SizedBox(height: 12),
        // Tap dots to log water
        Row(children: List.generate(_goal, (i) => Expanded(
          child: GestureDetector(
            onTap: () => ref.read(waterIntakeProvider.notifier).state =
              (i + 1 == current) ? i : i + 1,
            child: Container(
              height: 8,
              margin: EdgeInsets.only(right: i < _goal - 1 ? 3 : 0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: i < current
                  ? const Color(0xFF38BDF8)
                  : Colors.white.withValues(alpha: 0.08)))))),
        ),
      ]),
    );
  }
}

// ── Performance Card ──────────────────────────────────────────────────────────
class _PerformanceCard extends ConsumerStatefulWidget {
  @override
  ConsumerState<_PerformanceCard> createState() => _PerformanceCardState();
}

class _PerformanceCardState extends ConsumerState<_PerformanceCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;
  double _targetProgress = 0;
  int _targetActivities = 0;
  int _percentInt = 0;
  int _ptsDiff = 0;
  bool _improving = true;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _startAnimation(double progress, int activities, int pct, int diff, bool up) {
    _targetProgress = progress;
    _targetActivities = activities;
    _percentInt = pct;
    _ptsDiff = diff;
    _improving = up;
    Future.delayed(const Duration(milliseconds: 200), () { if (mounted) _ctrl.forward(from: 0); });
  }

  @override
  Widget build(BuildContext context) {
    final monthAsync = ref.watch(monthScoresProvider);
    final weekAsync = ref.watch(weekScoresProvider);

    return monthAsync.when(
      loading: () => _GlassCard(
        glowBorder: true,
        padding: const EdgeInsets.all(20),
        child: const SizedBox(height: 120, child: Center(
          child: CircularProgressIndicator(color: _C.primary, strokeWidth: 2)))),
      error: (_, __) => const SizedBox.shrink(),
      data: (monthRows) {
        const maxPerDay = 100;
        final daysInMonth = DateTime.now().day;
        final maxMonthPossible = daysInMonth * maxPerDay;
        final monthTotal = monthRows.fold<int>(
          0, (sum, r) => sum + ((r['total_score'] as num?)?.toInt() ?? 0));
        final pct = maxMonthPossible > 0
            ? (monthTotal / maxMonthPossible * 100).round().clamp(0, 100)
            : 0;
        final activitiesCompleted = monthRows.where(
          (r) => ((r['workout_points'] as num?)?.toInt() ?? 0) > 0).length;
        final progress = pct / 100.0;

        int diff = 0;
        bool improving = true;
        weekAsync.whenData((weekRows) {
          if (weekRows.length >= 2) {
            final latest = (weekRows.last['total_score'] as num?)?.toInt() ?? 0;
            final oldest = (weekRows.first['total_score'] as num?)?.toInt() ?? 0;
            diff = latest - oldest;
            improving = diff >= 0;
          }
        });

        if (_targetProgress != progress || _targetActivities != activitiesCompleted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _startAnimation(progress, activitiesCompleted, pct, diff.abs(), improving);
          });
        }

        final headline = pct >= 80 ? "You're Crushing it"
            : pct >= 50 ? "Keep Going!"
            : "Let's Pick It Up";

        return _GlassCard(
          glowBorder: true,
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _C.brand.withValues(alpha: 0.2)),
                child: const Icon(Icons.bar_chart_rounded, color: _C.primary, size: 22)),
              const SizedBox(width: 14),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(headline,
                  style: const TextStyle(color: _C.onSurface, fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                AnimatedBuilder(animation: _anim, builder: (_, __) {
                  final d = (_anim.value * _ptsDiff).round();
                  return Row(children: [
                    Icon(
                      _improving ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                      color: _improving ? _C.green : _C.error, size: 12),
                    const SizedBox(width: 3),
                    Text('$d pts vs last week',
                      style: TextStyle(
                        color: _improving ? _C.green : _C.error,
                        fontSize: 11, fontWeight: FontWeight.w600)),
                  ]);
                }),
              ]),
            ]),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                AnimatedBuilder(animation: _anim, builder: (_, __) => Text(
                  '${(_anim.value * _percentInt).round()}%',
                  style: const TextStyle(color: _C.onSurface, fontSize: 48,
                    fontWeight: FontWeight.w800, height: 1, letterSpacing: -2))),
                const SizedBox(height: 6),
                Text('Total this month',
                  style: TextStyle(color: _C.onSurfVar.withValues(alpha: 0.7), fontSize: 12)),
              ]),
              SizedBox(width: 120, height: 120,
                child: AnimatedBuilder(animation: _anim, builder: (_, __) => Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(120, 120),
                      painter: _RingPainter(progress: _anim.value * _targetProgress)),
                    Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('${(_anim.value * _targetActivities).round()}',
                        style: const TextStyle(color: _C.onSurface, fontSize: 26, fontWeight: FontWeight.w800, height: 1)),
                      const SizedBox(height: 3),
                      Text('WORKOUT\nDAYS',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _C.onSurfVar.withValues(alpha: 0.7),
                          fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 1, height: 1.4)),
                    ]),
                  ]))),
            ]),
          ]),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  const _RingPainter({required this.progress});
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;
    canvas.drawCircle(center, radius,
      Paint()..color = const Color(0x1FA855F7)..strokeWidth = 9..style = PaintingStyle.stroke);
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2, 2 * math.pi * progress, false,
        Paint()
          ..shader = SweepGradient(
            startAngle: -math.pi / 2, endAngle: -math.pi / 2 + 2 * math.pi,
            colors: const [Color(0xFFDDB7FF), Color(0xFF842BD2)],
          ).createShader(Rect.fromCircle(center: center, radius: radius))
          ..strokeWidth = 9..style = PaintingStyle.stroke..strokeCap = StrokeCap.round);
    }
  }
  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}

// ── Steps + Calories row cards ────────────────────────────────────────────────
class _StepsCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final steps = ref.watch(stepsProvider);
    return _GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _C.teal.withValues(alpha: 0.15)),
          child: const Icon(Icons.directions_walk_rounded, color: _C.teal, size: 18)),
        const SizedBox(height: 10),
        Text('$steps',
          style: const TextStyle(color: _C.onSurface, fontSize: 24, fontWeight: FontWeight.w800, height: 1)),
        Text('steps', style: TextStyle(color: _C.teal.withValues(alpha: 0.8), fontSize: 12)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: (steps / 10000).clamp(0.0, 1.0),
            minHeight: 4,
            backgroundColor: Colors.white.withValues(alpha: 0.07),
            valueColor: const AlwaysStoppedAnimation<Color>(_C.teal))),
        const SizedBox(height: 4),
        Text('Goal: 10,000', style: TextStyle(color: _C.onSurfVar.withValues(alpha: 0.5), fontSize: 10)),
      ]),
    );
  }
}

class _CaloriesCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totals = ref.watch(todayNutritionProvider).valueOrNull;
    final calories = ((totals?['calories'] ?? 0.0) as num).toInt();
    const goal = 2000;
    return _GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _C.error.withValues(alpha: 0.15)),
          child: const Icon(Icons.local_fire_department_rounded, color: _C.error, size: 18)),
        const SizedBox(height: 10),
        Text(calories == 0 ? '0' : '$calories',
          style: const TextStyle(color: _C.onSurface, fontSize: 24, fontWeight: FontWeight.w800, height: 1)),
        const Text('kcal', style: TextStyle(color: _C.error, fontSize: 12)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: (calories / goal).clamp(0.0, 1.0),
            minHeight: 4,
            backgroundColor: Colors.white.withValues(alpha: 0.07),
            valueColor: const AlwaysStoppedAnimation<Color>(_C.error))),
        const SizedBox(height: 4),
        Text('Goal: $goal kcal', style: TextStyle(color: _C.onSurfVar.withValues(alpha: 0.5), fontSize: 10)),
      ]),
    );
  }
}

// ── Nutrition 2×2 Grid ────────────────────────────────────────────────────────
class _NutritionGrid extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totals   = ref.watch(todayNutritionProvider).valueOrNull;
    final calories = ((totals?['calories'] ?? 0.0) as num).toInt();
    final protein  = ((totals?['protein']  ?? 0.0) as num).toInt();
    final carbs    = ((totals?['carbs']    ?? 0.0) as num).toInt();
    final fat      = ((totals?['fat']      ?? 0.0) as num).toInt();

    final items = [
      (Icons.local_fire_department_outlined, 'CALORIES', calories == 0 ? '0 kcal' : '$calories kcal', _C.error),
      (Icons.egg_outlined,                   'PROTEIN',  '${protein}g', _C.teal),
      (Icons.grain_rounded,                  'CARBS',    '${carbs}g',   _C.primary),
      (Icons.water_drop_outlined,            'FAT',      '${fat}g',     _C.blue),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 3, height: 14, decoration: BoxDecoration(color: _C.brand, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text("TODAY'S MACROS", style: TextStyle(color: _C.primary, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
        const Spacer(),
        GestureDetector(
          onTap: () => context.go('/nutrition'),
          child: Text('Log food', style: TextStyle(color: _C.onSurfVar.withValues(alpha: 0.5), fontSize: 11))),
      ]),
      const SizedBox(height: 10),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 2.4,
        children: items.map((item) => _GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              Icon(item.$1, color: item.$4, size: 13),
              const SizedBox(width: 5),
              Text(item.$2, style: TextStyle(color: _C.onSurfVar.withValues(alpha: 0.6),
                fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1)),
            ]),
            Text(item.$3,
              style: TextStyle(color: item.$4, fontSize: 14, fontWeight: FontWeight.w700)),
          ]),
        )).toList(),
      ),
    ]);
  }
}

// ── Motivational Quote ────────────────────────────────────────────────────────
class _MotivationalQuoteCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quote = ref.watch(motivationalQuoteProvider);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_C.brand.withValues(alpha: 0.08), Colors.transparent],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _C.brand.withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _C.primary.withValues(alpha: 0.15)),
            child: const Icon(Icons.format_quote_rounded, color: _C.primary, size: 18)),
          const SizedBox(width: 10),
          Text('DAILY MOTIVATION', style: TextStyle(
            color: _C.primary.withValues(alpha: 0.7),
            fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
        ]),
        const SizedBox(height: 14),
        Text('"${quote.quote}"',
          style: const TextStyle(
            color: _C.onSurface, fontSize: 15, fontStyle: FontStyle.italic, height: 1.6)),
        const SizedBox(height: 8),
        Text('— ${quote.author}',
          style: TextStyle(color: _C.primary.withValues(alpha: 0.8),
            fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ── Challenge Section ─────────────────────────────────────────────────────────
class _ChallengeSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile       = ref.watch(currentUserProfileProvider).valueOrNull;
    final notifEnabled  = profile?['notif_challenges'] as bool? ?? false;
    final challengesAsync = ref.watch(liveChallengesProvider);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('Challenges',
          style: TextStyle(color: _C.onSurface, fontSize: 20, fontWeight: FontWeight.w800)),
        GestureDetector(
          onTap: () => context.go('/challenges'),
          child: const Text('See All',
            style: TextStyle(color: _C.primary, fontSize: 13, fontWeight: FontWeight.w600))),
      ]),
      const SizedBox(height: 12),

      if (!notifEnabled)
        _GlassCard(
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            Container(width: 44, height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle, color: _C.brand.withValues(alpha: 0.12)),
              child: const Icon(Icons.notifications_off_outlined, color: _C.primary, size: 22)),
            const SizedBox(width: 12),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Enable challenge alerts',
                style: TextStyle(color: _C.onSurface, fontSize: 13, fontWeight: FontWeight.w600)),
              SizedBox(height: 3),
              Text('Turn on notifications to track challenges here.',
                style: TextStyle(color: _C.onSurfVar, fontSize: 11, height: 1.4)),
            ])),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => context.push('/notification-preferences'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _C.brand.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8)),
                child: const Text('Enable',
                  style: TextStyle(color: _C.primary, fontSize: 12, fontWeight: FontWeight.w600)))),
          ]))
      else
        challengesAsync.when(
          loading: () => _GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: const Center(
              child: CircularProgressIndicator(color: _C.primary, strokeWidth: 2))),
          error: (_, __) => _GlassCard(
            padding: const EdgeInsets.all(18),
            child: Row(children: [
              Container(width: 44, height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle, color: _C.brand.withValues(alpha: 0.12)),
                child: const Icon(Icons.emoji_events_outlined, color: _C.primary, size: 22)),
              const SizedBox(width: 12),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('No active challenges',
                  style: TextStyle(color: _C.onSurface, fontSize: 13, fontWeight: FontWeight.w600)),
                SizedBox(height: 3),
                Text('Check back soon for new challenges.',
                  style: TextStyle(color: _C.onSurfVar, fontSize: 11, height: 1.4)),
              ])),
            ])),
          data: (all) {
            final active = all
                .where((c) => c.status == ChallengeStatus.active)
                .take(3)
                .toList();
            if (active.isEmpty) {
              return _GlassCard(
                padding: const EdgeInsets.all(18),
                child: Row(children: [
                  Container(width: 44, height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle, color: _C.brand.withValues(alpha: 0.12)),
                    child: const Icon(Icons.emoji_events_outlined, color: _C.primary, size: 22)),
                  const SizedBox(width: 12),
                  const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('No active challenges',
                      style: TextStyle(color: _C.onSurface, fontSize: 13, fontWeight: FontWeight.w600)),
                    SizedBox(height: 3),
                    Text('Check back soon for new challenges to join.',
                      style: TextStyle(color: _C.onSurfVar, fontSize: 11, height: 1.4)),
                  ])),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => context.go('/challenges'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _C.brand.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8)),
                      child: const Text('Browse',
                        style: TextStyle(color: _C.primary, fontSize: 12, fontWeight: FontWeight.w600)))),
                ]));
            }
            return Column(
              children: List.generate(active.length, (i) {
                final c = active[i];
                final daysLeft = c.endDate.difference(DateTime.now()).inDays.clamp(0, 999);
                final rawProgress = c.targetValue > 0
                    ? (c.myProgress / c.targetValue).clamp(0.0, 1.0)
                    : 0.0;
                return Padding(
                  padding: EdgeInsets.only(bottom: i < active.length - 1 ? 10 : 0),
                  child: _GlassCard(
                    padding: const EdgeInsets.all(14),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => context.go('/challenges'),
                      child: Row(children: [
                        Container(
                          width: 48, height: 48,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: _C.brand.withValues(alpha: 0.15),
                            border: Border.all(color: _C.brand.withValues(alpha: 0.2))),
                          child: Center(
                            child: Text(c.emoji,
                              style: const TextStyle(fontSize: 22)))),
                        const SizedBox(width: 14),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(c.title,
                            style: const TextStyle(color: _C.onSurface, fontSize: 13, fontWeight: FontWeight.w700),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 4),
                          if (c.isJoined) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: rawProgress,
                                backgroundColor: _C.brand.withValues(alpha: 0.15),
                                valueColor: const AlwaysStoppedAnimation<Color>(_C.primary),
                                minHeight: 3)),
                            const SizedBox(height: 3),
                          ],
                          Row(children: [
                            Text('${c.participantCount} joined',
                              style: TextStyle(color: _C.onSurfVar.withValues(alpha: 0.8), fontSize: 10)),
                            const SizedBox(width: 8),
                            Text('$daysLeft days left',
                              style: TextStyle(color: _C.onSurfVar.withValues(alpha: 0.5), fontSize: 10)),
                          ]),
                        ])),
                        const SizedBox(width: 10),
                        if (c.isJoined)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _C.green.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6)),
                            child: const Text('JOINED',
                              style: TextStyle(color: _C.green,
                                fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5)))
                        else
                          GestureDetector(
                            onTap: () async {
                              final ok = await ref.read(challengeNotifierProvider.notifier)
                                  .joinChallenge(c.id);
                              if (!context.mounted) return;
                              if (ok) {
                                ref.invalidate(liveChallengesProvider);
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Unable to join — please try again.')));
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFA855F7), Color(0xFF7C3AED)]),
                                borderRadius: BorderRadius.circular(8)),
                              child: const Text('Join',
                                style: TextStyle(color: Colors.white,
                                  fontSize: 12, fontWeight: FontWeight.w700)))),
                      ]),
                    ),
                  ),
                );
              }),
            );
          },
        ),
    ]);
  }
}

// ── Community Section ─────────────────────────────────────────────────────────
class _CommunitySection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Respect the user's Community notification/visibility preference.
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    if (profile != null && profile['notif_community'] == false) {
      return const SizedBox.shrink();
    }
    final groups  = ref.watch(groupNotifierProvider);
    final joined  = groups.where((g) => g.isJoined).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('Community',
          style: TextStyle(color: _C.onSurface, fontSize: 20, fontWeight: FontWeight.w800)),
        GestureDetector(
          onTap: () => context.go('/community'),
          child: const Text('Explore',
            style: TextStyle(color: _C.primary, fontSize: 13, fontWeight: FontWeight.w600))),
      ]),
      const SizedBox(height: 12),

      if (joined.isEmpty)
        _GlassCard(
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            Container(width: 44, height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle, color: _C.tertiary.withValues(alpha: 0.12)),
              child: const Icon(Icons.group_outlined, color: _C.tertiary, size: 22)),
            const SizedBox(width: 12),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('No communities joined yet',
                style: TextStyle(color: _C.onSurface, fontSize: 13, fontWeight: FontWeight.w600)),
              SizedBox(height: 3),
              Text('Join a group to see it here.',
                style: TextStyle(color: _C.onSurfVar, fontSize: 11, height: 1.4)),
            ])),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => context.go('/community'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _C.tertiary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8)),
                child: Text('Browse',
                  style: TextStyle(color: _C.tertiary, fontSize: 12, fontWeight: FontWeight.w600)))),
          ]))
      else
        Column(
          children: List.generate(joined.take(3).length, (i) {
            final g = joined[i];
            return Padding(
              padding: EdgeInsets.only(bottom: i < joined.take(3).length - 1 ? 10 : 0),
              child: _GlassCard(
                padding: const EdgeInsets.all(14),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => context.go('/community'),
                  child: Row(children: [
                    Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: _C.tertiary.withValues(alpha: 0.12),
                        border: Border.all(color: _C.tertiary.withValues(alpha: 0.2))),
                      child: Center(
                        child: Text(g.emoji, style: const TextStyle(fontSize: 22)))),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(g.name,
                        style: const TextStyle(color: _C.onSurface, fontSize: 13, fontWeight: FontWeight.w700),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 3),
                      Text('${g.memberCount} members',
                        style: TextStyle(color: _C.onSurfVar.withValues(alpha: 0.7), fontSize: 10)),
                    ])),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _C.tertiary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6)),
                      child: Text('JOINED',
                        style: TextStyle(color: _C.tertiary,
                          fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5))),
                  ]),
                ),
              ),
            );
          }),
        ),
    ]);
  }
}

// ── Header helpers ────────────────────────────────────────────────────────────
class _Avatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 40, height: 40,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: _C.primary.withValues(alpha: 0.3), width: 2)),
    child: ClipOval(child: Container(
      color: _C.surfContHigh,
      child: const Icon(Icons.person_rounded, color: _C.primary, size: 20))));
}

class _HeaderBtn extends StatelessWidget {
  final IconData icon;
  const _HeaderBtn({required this.icon});
  @override
  Widget build(BuildContext context) => Container(
    width: 40, height: 40,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: const Color(0x08FFFFFF),
      border: Border.all(color: const Color(0x0DFFFFFF))),
    child: Icon(icon, color: _C.onSurfVar, size: 20));
}

class _ShakingBell extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ShakingBell> createState() => _ShakingBellState();
}
class _ShakingBellState extends ConsumerState<_ShakingBell> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _shake;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _shake = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.2), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.2, end: -0.2), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -0.2, end: 0.15), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 0.15, end: -0.1), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -0.1, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    Future.delayed(const Duration(seconds: 1), _loop);
  }
  void _loop() {
    if (!mounted) return;
    _ctrl.forward(from: 0).then((_) => Future.delayed(const Duration(seconds: 3), _loop));
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _showNotifications() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NotificationsPanel(),
    );
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: _showNotifications,
    child: AnimatedBuilder(
      animation: _shake,
      builder: (_, child) => Transform.rotate(angle: _shake.value, child: child),
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0x08FFFFFF),
          border: Border.all(color: const Color(0x0DFFFFFF))),
        child: Stack(alignment: Alignment.center, children: [
          Icon(Icons.notifications_outlined, color: _C.onSurfVar, size: 20),
          Positioned(top: 8, right: 8,
            child: Container(width: 7, height: 7,
              decoration: BoxDecoration(shape: BoxShape.circle, color: _C.error,
                boxShadow: [BoxShadow(color: _C.error.withValues(alpha: 0.6), blurRadius: 4)]))),
        ]))));
}

// ── Notifications Panel ───────────────────────────────────────────────────────
class _NotificationsPanel extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classesAsync = ref.watch(upcomingClassesProvider);
    final eventsAsync  = ref.watch(upcomingEventsProvider);
    final bottom = MediaQuery.of(context).padding.bottom;

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      decoration: const BoxDecoration(
        color: Color(0xFF0C0911),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 12),
        Container(width: 40, height: 4,
          decoration: BoxDecoration(color: const Color(0xFF4D4354), borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            const Text('Upcoming', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _C.brand.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999)),
              child: Text('Today & beyond', style: TextStyle(color: _C.primary, fontSize: 11, fontWeight: FontWeight.w600))),
          ]),
        ),
        const SizedBox(height: 16),
        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 0, 20, bottom + 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Classes
              classesAsync.when(
                loading: () => const SizedBox(height: 60, child: Center(child: CircularProgressIndicator(color: _C.primary, strokeWidth: 2))),
                error: (_, __) => const SizedBox.shrink(),
                data: (classes) {
                  if (classes.isEmpty) return const SizedBox.shrink();
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _PanelSectionLabel(label: 'Classes'),
                    const SizedBox(height: 10),
                    ...classes.map((c) => _UpcomingItem(
                      icon: Icons.fitness_center_rounded,
                      iconColor: _C.primary,
                      // `classes` and `events` have `title` and `max_capacity`; there is no
                      // `name` or `capacity`, so every row read "Class · 0 spots".
                      title: c['title'] as String? ?? 'Class',
                      subtitle: _formatDate(c['scheduled_at'] as String?),
                      badge: '${c['max_capacity'] as int? ?? 0} spots',
                      onTap: () { Navigator.pop(context); context.go('/appointments'); },
                    )),
                  ]);
                },
              ),
              const SizedBox(height: 16),
              // Events
              eventsAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (events) {
                  if (events.isEmpty) return const SizedBox.shrink();
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _PanelSectionLabel(label: 'Events'),
                    const SizedBox(height: 10),
                    ...events.map((e) => _UpcomingItem(
                      icon: Icons.event_rounded,
                      iconColor: _C.teal,
                      title: e['title'] as String? ?? 'Event',
                      subtitle: _formatDate(e['event_date'] as String?),
                      badge: e['location'] as String? ?? '',
                      onTap: () { Navigator.pop(context); context.go('/directory'); },
                    )),
                  ]);
                },
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    try {
      final d = DateTime.parse(iso).toLocal();
      final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
      final m = d.minute.toString().padLeft(2, '0');
      final ampm = d.hour < 12 ? 'AM' : 'PM';
      return '${months[d.month - 1]} ${d.day} • $h:$m $ampm';
    } catch (_) {
      return '';
    }
  }
}

class _PanelSectionLabel extends StatelessWidget {
  final String label;
  const _PanelSectionLabel({required this.label});
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 3, height: 14, decoration: BoxDecoration(color: _C.brand, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 8),
    Text(label.toUpperCase(), style: TextStyle(color: _C.primary, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
  ]);
}

class _UpcomingItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title, subtitle, badge;
  final VoidCallback onTap;
  const _UpcomingItem({required this.icon, required this.iconColor, required this.title,
    required this.subtitle, required this.badge, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x08FFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x1AFFFFFF))),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: iconColor.withValues(alpha: 0.15)),
          child: Icon(icon, color: iconColor, size: 22)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(subtitle, style: TextStyle(color: _C.onSurfVar.withValues(alpha: 0.6), fontSize: 12)),
        ])),
        if (badge.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: iconColor.withValues(alpha: 0.2))),
            child: Text(badge, style: TextStyle(color: iconColor, fontSize: 10, fontWeight: FontWeight.w600))),
      ]),
    ),
  );
}

// ── Shared Glass Card ─────────────────────────────────────────────────────────
class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final bool glowBorder;
  const _GlassCard({required this.child, this.padding, this.glowBorder = false});

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: const Color(0x0DFFFFFF),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: glowBorder
          ? const Color(0xFFA855F7).withValues(alpha: 0.3)
          : Colors.white.withValues(alpha: 0.1)),
      boxShadow: glowBorder
        ? [BoxShadow(color: const Color(0xFFA855F7).withValues(alpha: 0.08), blurRadius: 16)]
        : null),
    child: child);
}
