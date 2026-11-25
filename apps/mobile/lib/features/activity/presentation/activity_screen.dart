import 'dart:async' show Timer;
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/observability/app_failure.dart';
import '../../../core/observability/network_failure.dart';
import '../../auth/domain/auth_provider.dart';
import '../../nutrition/domain/nutrition_provider.dart';
import '../../coach/domain/coach_ecosystem_provider.dart';
import '../../dashboard/domain/dashboard_provider.dart';
import '../../challenges/domain/challenge_provider.dart';
import '../../challenges/data/models/challenge_model.dart';
import '../../community/domain/community_provider.dart';
import '../../home/domain/home_session_card.dart';
import '../../workout/domain/workout_provider.dart';
import '../../workout/presentation/widgets/section_load_failure.dart';

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

// ── Fit and touch helpers (P0-FL-58) ──────────────────────────────────────────

/// Text is scaled past 1.3×: side-by-side pieces go under one another instead
/// of being squeezed, clipped or shrunk.
bool _largeText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(12) > 12 * 1.3;

/// How wide [text] is on one line, as it will be drawn (style and scale).
double _lineWidth(BuildContext context, String text, TextStyle style) {
  final p = TextPainter(
    // bodyMedium: what a Scaffold's Text inherits.
    text: TextSpan(text: text,
      style: Theme.of(context).textTheme.bodyMedium?.merge(style) ?? style),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context))..layout();
  final w = p.width;
  p.dispose();
  return w;
}

/// A >= 44px button around [child], which keeps its own look. [label] names
/// the action AND the item; a screen reader can press it (`onTap`).
class _TapTarget extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Widget child;
  const _TapTarget({required this.label, required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    label: label,
    onTap: onTap,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        child: Center(widthFactor: 1, heightFactor: 1, child: child))));
}

/// The content of a card that is one button: the whole row is pressed, and is
/// announced as [label]. [trailing] (its own button, or a badge) goes beside
/// it, or under it at large text.
class _RowButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Widget leading;
  final Widget body;
  final Widget trailing;
  const _RowButton({required this.label, required this.onTap,
    required this.leading, required this.body, required this.trailing});

  @override
  Widget build(BuildContext context) {
    final large = _largeText(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true, // announced by the Semantics below
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Semantics(
            container: true,
            button: true,
            label: label,
            onTap: onTap,
            excludeSemantics: true,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(children: [
                leading,
                const SizedBox(width: 14),
                Expanded(child: body),
              ])))),
          if (!large) ...[const SizedBox(width: 10), trailing],
        ]),
        if (large) ...[const SizedBox(height: 10), trailing],
      ]));
  }
}

/// A 48px emoji tile that grows with the emoji instead of clipping it.
class _EmojiTile extends StatelessWidget {
  final String emoji;
  final Color color;
  final double tint;
  const _EmojiTile({required this.emoji, required this.color, required this.tint});

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      color: color.withValues(alpha: tint),
      border: Border.all(color: color.withValues(alpha: 0.2))),
    child: Center(widthFactor: 1, heightFactor: 1,
      child: Text(emoji, style: const TextStyle(fontSize: 22))));
}

/// [title] with [action] at the right; under it at large text.
class _SectionHeader extends StatelessWidget {
  final Widget title;
  final Widget action;
  const _SectionHeader({required this.title, required this.action});

  @override
  Widget build(BuildContext context) => _largeText(context)
    ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [title, action])
    : Row(children: [Expanded(child: title), const SizedBox(width: 8), action]);
}

/// An icon, two lines and an action beside them (under them at large text).
class _NoticeRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String message;
  final Widget action;
  const _NoticeRow({required this.icon, required this.color,
    required this.title, required this.message, required this.action});

  @override
  Widget build(BuildContext context) {
    final large = _largeText(context);
    return Row(children: [
      Container(width: 44, height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle, color: color.withValues(alpha: 0.12)),
        child: Icon(icon, color: color, size: 22)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
          style: const TextStyle(color: _C.onSurface, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 3),
        Text(message,
          style: const TextStyle(color: _C.onSurfVar, fontSize: 11, height: 1.4)),
        if (large) ...[const SizedBox(height: 10), action],
      ])),
      if (!large) ...[const SizedBox(width: 8), action],
    ]);
  }
}

/// The small tinted pill the notices' actions are drawn as.
class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  final double tint;
  const _Pill({required this.text, required this.color, required this.tint});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: tint),
      borderRadius: BorderRadius.circular(8)),
    child: Text(text,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)));
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
    // P0-FL-60b · a failure and its Try again need the whole width.
    final streakFailed =
        ref.watch(memberStreakProvider.select((s) => s.error != null));
    // P0-FL-58 · the bar is 64px, between the buttons: a greeting that does
    // not fit it on one line each (past 1.3×, or a long name on a narrow
    // phone) moves to the top of the page, where it wraps. The buttons stay.
    final large = _largeText(context);
    final helloStyle = TextStyle(color: _C.onSurfVar.withValues(alpha: 0.6),
        fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.5);
    const nameStyle = TextStyle(color: _C.onSurface, fontSize: 20, fontWeight: FontWeight.w700);
    const barTaken = 20 + 44 + 10 + 8 + 44 + 4 + 44 + 20; // padding, buttons, gaps
    final barRoom = MediaQuery.sizeOf(context).width - barTaken;
    final greetingInBar = !large &&
        _lineWidth(context, 'Good Morning', helloStyle) <= barRoom &&
        _lineWidth(context, userName, nameStyle) <= barRoom;
    final greeting = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Good Morning', style: helloStyle),
      Text(userName, style: nameStyle),
    ]);

    return Scaffold(
      backgroundColor: _C.bg,
      body: Stack(fit: StackFit.expand, children: [
            SingleChildScrollView(
              padding: EdgeInsets.only(top: topPad + 64 + 16, left: 20, right: 20, bottom: 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (!greetingInBar) ...[greeting, const SizedBox(height: 16)],
                const Text('Activity',
                  style: TextStyle(color: _C.onSurface, fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 16),

                // ── Daily Workout Card ─────────────────────────────────────────
                _DailyWorkoutCard(),
                const SizedBox(height: 16),

                // ── Streak + Water row ─────────────────────────────────────────
                if (large || streakFailed) ...[
                  SizedBox(width: double.infinity, child: _StreakCard()),
                  const SizedBox(height: 12),
                  SizedBox(width: double.infinity, child: _WaterTrackerCard()),
                ] else
                  IntrinsicHeight(child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(child: _StreakCard()),
                    const SizedBox(width: 12),
                    Expanded(child: _WaterTrackerCard()),
                  ])),
                const SizedBox(height: 16),

                // ── Performance ring card ──────────────────────────────────────
                _PerformanceCard(),
                const SizedBox(height: 16),

                // ── Daily steps + Macros row ───────────────────────────────────
                if (large) ...[
                  SizedBox(width: double.infinity, child: _StepsCard()),
                  const SizedBox(height: 12),
                  SizedBox(width: double.infinity, child: _CaloriesCard()),
                ] else
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
                      // P0-FL-58 · 40px discs in 44px, named targets.
                      _TapTarget(
                        label: 'Open your profile',
                        onTap: () => context.go('/profile'),
                        child: _Avatar()),
                      const SizedBox(width: 10),
                      Expanded(child: greetingInBar ? greeting : const SizedBox.shrink()),
                      const SizedBox(width: 8),
                      _TapTarget(
                        label: 'Open messages',
                        onTap: () => context.go('/messages'),
                        child: _HeaderBtn(icon: Icons.chat_bubble_outline_rounded)),
                      const SizedBox(width: 4),
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
    final large = _largeText(context);
    // The pill is a picture of the card's own action, not a second target.
    final start = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _C.brand,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [BoxShadow(color: _C.brand.withValues(alpha: 0.4), blurRadius: 12)]),
      child: const Text('Start', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)));

    return Semantics(
      container: true,
      button: true,
      label: session.canBegin
          ? ["Open today's workout: $title", ...badges, 'Not started yet'].join(', ')
          : 'Open Train: $title',
      onTap: () => context.go('/train'),
      excludeSemantics: true,
      child: GestureDetector(
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
            if (session.canBegin && !large) start,
          ]),
          // Nothing to begin: the title line already says why. No badges, no
          // progress bar for a session that does not exist.
          if (session.canBegin) ...[
          if (large) ...[const SizedBox(height: 14), start],
          if (badges.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(spacing: 10, runSpacing: 8, children: [
            for (final b in badges)
              _WorkoutBadge(
                icon: b.endsWith(' min') ? Icons.schedule_rounded : Icons.fitness_center_rounded,
                text: b, color: _C.teal),
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
    ));
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
      Flexible(child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600))),
    ]));
}

// ── Streak Card ───────────────────────────────────────────────────────────────
class _StreakCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // P0-FL-60b · a failed read was "0 day streak"; it is said instead, and a
    // number already read for this member stays beside it.
    final read = ref.watch(memberStreakProvider);
    final streak = read.value;
    return _GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Wraps: the badge goes under the icon when they do not fit a line.
        SizedBox(width: double.infinity, child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 8, children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _C.brand.withValues(alpha: 0.2)),
            child: const Icon(Icons.local_fire_department_rounded, color: _C.primary, size: 18)),
          if (streak != null) Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _C.brand.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(999)),
            child: Text(streak >= 7 ? '🔥 Hot' : 'Active',
              style: TextStyle(color: _C.primary, fontSize: 9, fontWeight: FontWeight.w700))),
        ])),
        const SizedBox(height: 12),
        if (streak != null) ...[
        Text('$streak',
          style: const TextStyle(color: _C.onSurface, fontSize: 36, fontWeight: FontWeight.w800, height: 1)),
        Text('day streak', style: TextStyle(color: _C.onSurfVar.withValues(alpha: 0.7), fontSize: 12)),
        const SizedBox(height: 10),
        Text(streak == 0 ? 'Start today!' : streak >= 7 ? 'Keep it up!' : 'Building momentum',
          style: TextStyle(color: _C.primary.withValues(alpha: 0.8), fontSize: 11, fontWeight: FontWeight.w600)),
        ] else if (read.error == null)
          // Loading: no claim either way about the streak.
          Semantics(
            label: 'Loading your streak',
            child: const SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: _C.primary))),
        if (read.error != null) ...[
          if (streak != null) const SizedBox(height: 10),
          SectionLoadFailure(
            what: 'your streak',
            error: read.error,
            busy: read.busy,
            onRetry: () => ref.invalidate(streakProvider),
            accent: _C.primary, textColor: _C.onSurface, mutedColor: _C.onSurfVar),
        ],
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
    void set(int v) => ref.read(waterIntakeProvider.notifier).state = v;
    void tapDot(int i) => set((i + 1 == current) ? i : i + 1);
    return _GlassCard(
      // No bottom padding: the dots' 44px target reaches the card's edge.
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: double.infinity, child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 8, children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF38BDF8).withValues(alpha: 0.2)),
            child: const Icon(Icons.water_drop_rounded, color: Color(0xFF38BDF8), size: 18)),
          Text('$current/$_goal', style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.w700)),
        ])),
        const SizedBox(height: 12),
        Text('$current',
          style: const TextStyle(color: _C.onSurface, fontSize: 36, fontWeight: FontWeight.w800, height: 1)),
        const Text('glasses', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12)),
        // Tap dots to log water. P0-FL-58 · the eight 8px dots cannot each be
        // 44px in this card, so they are ONE 44px control: a touch sets the
        // dot it lands on, exactly as before; a screen reader adjusts it.
        Semantics(
          container: true,
          slider: true,
          label: 'Glasses of water today',
          value: '$current of $_goal',
          increasedValue: current < _goal ? '${current + 1} of $_goal' : null,
          decreasedValue: current > 0 ? '${current - 1} of $_goal' : null,
          onIncrease: current < _goal ? () => set(current + 1) : null,
          onDecrease: current > 0 ? () => set(current - 1) : null,
          excludeSemantics: true,
          child: Builder(builder: (dots) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) {
              final width = dots.size?.width ?? 0;
              if (width <= 0) return;
              tapDot((d.localPosition.dx / width * _goal).floor().clamp(0, _goal - 1));
            },
            child: Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 22),
              child: Row(children: List.generate(_goal, (i) => Expanded(
                child: Container(
                  height: 8,
                  margin: EdgeInsets.only(right: i < _goal - 1 ? 3 : 0),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: i < current
                      ? const Color(0xFF38BDF8)
                      : Colors.white.withValues(alpha: 0.08)))))))))),
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
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                    Flexible(child: Text('$d pts vs last week',
                      style: TextStyle(
                        color: _improving ? _C.green : _C.error,
                        fontSize: 11, fontWeight: FontWeight.w600))),
                  ]);
                }),
              ])),
            ]),
            const SizedBox(height: 20),
            LayoutBuilder(builder: (context, box) {
              // P0-FL-58 · the ring row overflowed at large text, and the
              // label overflowed the 120px ring. The ring goes under the
              // percentage when the two do not fit side by side, and past
              // 1.3× its label goes under it. Measured with the FINAL
              // percentage, so the layout does not jump while it counts up.
              const pctStyle = TextStyle(color: _C.onSurface, fontSize: 48,
                fontWeight: FontWeight.w800, height: 1, letterSpacing: -2);
              final large = _largeText(context);
              final stacked = large ||
                  _lineWidth(context, '$pct%', pctStyle) > box.maxWidth - 120 - 12;
              final total = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                AnimatedBuilder(animation: _anim, builder: (_, __) => Text(
                  '${(_anim.value * _percentInt).round()}%', style: pctStyle)),
                const SizedBox(height: 6),
                Text('Total this month',
                  style: TextStyle(color: _C.onSurfVar.withValues(alpha: 0.7), fontSize: 12)),
              ]);
              final ring = AnimatedBuilder(animation: _anim, builder: (_, __) {
                final disc = CustomPaint(
                  size: const Size(120, 120),
                  painter: _RingPainter(progress: _anim.value * _targetProgress));
                final days = Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: large ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                  children: [
                    Text('${(_anim.value * _targetActivities).round()}',
                      style: const TextStyle(color: _C.onSurface, fontSize: 26, fontWeight: FontWeight.w800, height: 1)),
                    const SizedBox(height: 3),
                    Text(large ? 'WORKOUT DAYS' : 'WORKOUT\nDAYS',
                      textAlign: large ? TextAlign.start : TextAlign.center,
                      style: TextStyle(color: _C.onSurfVar.withValues(alpha: 0.7),
                        fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 1, height: 1.4)),
                  ]);
                return large
                  ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      disc, const SizedBox(height: 10), days])
                  : SizedBox(width: 120, height: 120,
                      child: Stack(alignment: Alignment.center, children: [disc, days]));
              });
              return stacked
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    total, const SizedBox(height: 16), ring])
                : Row(children: [Expanded(child: total), const SizedBox(width: 12), ring]);
            }),
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
        Text(steps == null ? '—' : '$steps',
          style: const TextStyle(color: _C.onSurface, fontSize: 24, fontWeight: FontWeight.w800, height: 1)),
        Text('steps', style: TextStyle(color: _C.teal.withValues(alpha: 0.8), fontSize: 12)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: ((steps ?? 0) / 10000).clamp(0.0, 1.0),
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
      _SectionHeader(
        title: Row(children: [
          Container(width: 3, height: 14, decoration: BoxDecoration(color: _C.brand, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Expanded(child: Text("TODAY'S MACROS", style: TextStyle(color: _C.primary, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5))),
        ]),
        action: _TapTarget(
          label: "Log food for today's macros",
          onTap: () => context.go('/nutrition'),
          child: Text('Log food', style: TextStyle(color: _C.onSurfVar.withValues(alpha: 0.5), fontSize: 11)))),
      // P0-FL-58 · a fixed 2.4:1 grid cell cut its text off at large text. The
      // same cell is now a MINIMUM: it grows; past 1.3× there is one per line.
      LayoutBuilder(builder: (context, box) {
        final large = _largeText(context);
        final width = large ? box.maxWidth : (box.maxWidth - 10) / 2;
        return Wrap(spacing: 10, runSpacing: 10, children: items.map((item) => ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: width, maxWidth: width, minHeight: large ? 0 : width / 2.4),
          child: _GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(children: [
                Icon(item.$1, color: item.$4, size: 13),
                const SizedBox(width: 5),
                Expanded(child: Text(item.$2, style: TextStyle(color: _C.onSurfVar.withValues(alpha: 0.6),
                  fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1))),
              ]),
              Text(item.$3,
                style: TextStyle(color: item.$4, fontSize: 14, fontWeight: FontWeight.w700)),
            ]),
          ))).toList());
      }),
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
          Expanded(child: Text('DAILY MOTIVATION', style: TextStyle(
            color: _C.primary.withValues(alpha: 0.7),
            fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.5))),
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
class _ChallengeSection extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ChallengeSection> createState() => _ChallengeSectionState();
}

class _ChallengeSectionState extends ConsumerState<_ChallengeSection> {
  // P0-FL-53b · the last list this section showed, and for whom. A failed
  // refresh keeps it on screen under the failure notice; a list read for
  // another member (Riverpod holds A's value while B's read fails) is never
  // shown.
  List<Challenge>? _held;
  String? _heldFor;

  @override
  Widget build(BuildContext context) {
    // P0-FL-49 · the preference of the member signed in NOW. Riverpod keeps the
    // previous member's row through a re-read, so the held value showed (or
    // hid) the prompt on A's `notif_challenges` while B's read was in flight
    // or had failed. Unconfirmed (loading / failed / another member's row)
    // claims nothing: no prompt, the challenges show as for an enabled member.
    final profile       = ref.watch(confirmedCurrentProfileProvider);
    final showPrompt    =
        profile != null && (profile['notif_challenges'] as bool?) != true;
    final challengesAsync = ref.watch(liveChallengesProvider);
    final uid = ref.watch(currentUserProvider)?.id;
    if (challengesAsync is AsyncData<List<Challenge>>) {
      _held = challengesAsync.value;
      _heldFor = uid;
    }
    final held = _heldFor == uid ? _held : null;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionHeader(
        title: const Text('Challenges',
          style: TextStyle(color: _C.onSurface, fontSize: 20, fontWeight: FontWeight.w800)),
        // U5 · was 13px text with no role: < 44px and announced as plain text.
        // P0-FL-58 · and a screen reader had no tap action on it.
        action: _TapTarget(
          label: 'See all challenges',
          onTap: () => context.go('/challenges'),
          child: const Text('See All',
            style: TextStyle(color: _C.primary, fontSize: 13, fontWeight: FontWeight.w600)))),
      const SizedBox(height: 12),

      if (showPrompt)
        _GlassCard(
          padding: const EdgeInsets.all(18),
          // U5 · "Enable" goes under the message at large text.
          child: _NoticeRow(
            icon: Icons.notifications_off_outlined,
            color: _C.primary,
            title: 'Enable challenge alerts',
            message: 'Turn on notifications to track challenges here.',
            action: _TapTarget(
              label: 'Enable challenge alerts',
              onTap: () => context.push('/notification-preferences'),
              child: const _Pill(text: 'Enable', color: _C.primary, tint: 0.15))))
      else if (challengesAsync.hasError) ...[
        // P0-FL-53b · a failed read said "No active challenges": a claim about
        // what exists that the app could not make. The failure is recorded
        // once, by LiveChallengeService.getActiveChallenges. What this member
        // was last shown stays, under the notice.
        _GlassCard(
          padding: const EdgeInsets.all(18),
          child: SectionLoadFailure(
            what: 'challenges',
            error: challengesAsync.error,
            busy: challengesAsync.isLoading,
            onRetry: () => ref.invalidate(liveChallengesProvider),
            textColor: _C.onSurface,
            mutedColor: _C.onSurfVar,
            detail: held != null && held.any((c) => c.status == ChallengeStatus.active)
                ? 'Showing the challenges loaded earlier.'
                : null)),
        if (held != null && held.any((c) => c.status == ChallengeStatus.active)) ...[
          const SizedBox(height: 10),
          _challengeList(context, held),
        ],
      ]
      else
        challengesAsync.when(
          loading: () => _GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: const Center(
              child: CircularProgressIndicator(color: _C.primary, strokeWidth: 2))),
          // Unreachable: `hasError` is handled above.
          error: (_, __) => const SizedBox.shrink(),
          data: (all) => _challengeList(context, all),
        ),
    ]);
  }

  Widget _challengeList(BuildContext context, List<Challenge> all) {
            final active = all
                .where((c) => c.status == ChallengeStatus.active)
                .take(3)
                .toList();
            if (active.isEmpty) {
              return _GlassCard(
                padding: const EdgeInsets.all(18),
                child: _NoticeRow(
                  icon: Icons.emoji_events_outlined,
                  color: _C.primary,
                  title: 'No active challenges',
                  message: 'Check back soon for new challenges to join.',
                  action: _TapTarget(
                    label: 'Browse challenges',
                    onTap: () => context.go('/challenges'),
                    child: const _Pill(text: 'Browse', color: _C.primary, tint: 0.15))));
            }
            final large = _largeText(context);
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
                    child: _RowButton(
                        label: 'Open ${c.title}, ${c.participantCount} joined, '
                            '$daysLeft days left${c.isJoined ? ', joined' : ''}',
                        onTap: () => context.go('/challenges'),
                        leading: _EmojiTile(emoji: c.emoji, color: _C.brand, tint: 0.15),
                        body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(c.title,
                            style: const TextStyle(color: _C.onSurface, fontSize: 13, fontWeight: FontWeight.w700),
                            maxLines: large ? null : 1,
                            overflow: large ? null : TextOverflow.ellipsis),
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
                          Wrap(spacing: 8, children: [
                            Text('${c.participantCount} joined',
                              style: TextStyle(color: _C.onSurfVar.withValues(alpha: 0.8), fontSize: 10)),
                            Text('$daysLeft days left',
                              style: TextStyle(color: _C.onSurfVar.withValues(alpha: 0.5), fontSize: 10)),
                          ]),
                        ]),
                        trailing: c.isJoined
                          ? ExcludeSemantics(child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _C.green.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6)),
                            child: const Text('JOINED',
                              style: TextStyle(color: _C.green,
                                fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5))))
                          : _TapTarget(
                            label: 'Join ${c.title}',
                            onTap: () async {
                              final ok = await ref.read(challengeNotifierProvider.notifier)
                                  .joinChallenge(c.id);
                              if (!context.mounted) return;
                              if (ok) {
                                ref.invalidate(liveChallengesProvider);
                              } else {
                                // P0-FL-53b · recorded by the notifier; said in
                                // the one voice, announced.
                                final err = ref.read(challengeNotifierProvider.notifier)
                                    .lastJoinError;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Semantics(liveRegion: true,
                                      child: Text(couldntMessage('join this challenge', err)))));
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
                    ),
                  ),
                );
              }),
            );
  }
}

// ── Community Section ─────────────────────────────────────────────────────────
class _CommunitySection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Respect the user's Community notification/visibility preference.
    // P0-FL-49 · only a preference CONFIRMED for the member signed in now
    // hides the section — never the previous member's (Riverpod holds A's row
    // while B's read is in flight or has failed). Unconfirmed shows it, as
    // with no preference.
    final profile = ref.watch(confirmedCurrentProfileProvider);
    if (profile != null && profile['notif_community'] == false) {
      return const SizedBox.shrink();
    }
    // P0-FL-10 · a failed groups read was `[]` here, shown as "No communities
    // joined yet". Loading claims nothing; a failure says so with a retry
    // (recorded once by the provider, not here).
    final groupsAsync = ref.watch(groupNotifierProvider);
    // Null until the groups are loaded (and while a failure is shown).
    final joined = groupsAsync.whenOrNull(
        data: (groups) => groups.where((g) => g.isJoined).toList());
    final large = _largeText(context);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionHeader(
        title: const Text('Community',
          style: TextStyle(color: _C.onSurface, fontSize: 20, fontWeight: FontWeight.w800)),
        action: _TapTarget(
          label: 'Explore the community',
          onTap: () => context.go('/community'),
          child: const Text('Explore',
            style: TextStyle(color: _C.primary, fontSize: 13, fontWeight: FontWeight.w600)))),
      const SizedBox(height: 12),

      if (groupsAsync.hasError)
        _GroupsFailureCard(
          network: isNetworkFailure(groupsAsync.error),
          busy: groupsAsync.isLoading,
          onRetry: () => ref.invalidate(liveGroupsProvider),
        )
      else if (joined == null)
        // Loading: no claim either way about which groups are joined.
        Semantics(
          label: 'Loading your groups',
          child: const SizedBox(
            height: 44,
            child: Center(
              child: SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: _C.tertiary)))),
        )
      else if (joined.isEmpty)
        _GlassCard(
          padding: const EdgeInsets.all(18),
          child: _NoticeRow(
            icon: Icons.group_outlined,
            color: _C.tertiary,
            title: 'No communities joined yet',
            message: 'Join a group to see it here.',
            action: _TapTarget(
              label: 'Browse community groups',
              onTap: () => context.go('/community'),
              child: const _Pill(text: 'Browse', color: _C.tertiary, tint: 0.12))))
      else
        Column(
          children: List.generate(joined.take(3).length, (i) {
            final g = joined[i];
            return Padding(
              padding: EdgeInsets.only(bottom: i < joined.take(3).length - 1 ? 10 : 0),
              child: _GlassCard(
                padding: const EdgeInsets.all(14),
                child: _RowButton(
                    label: 'Open ${g.name}, ${g.memberCount} members, joined',
                    onTap: () => context.go('/community'),
                    leading: _EmojiTile(emoji: g.emoji, color: _C.tertiary, tint: 0.12),
                    body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(g.name,
                        style: const TextStyle(color: _C.onSurface, fontSize: 13, fontWeight: FontWeight.w700),
                        maxLines: large ? null : 1,
                        overflow: large ? null : TextOverflow.ellipsis),
                      const SizedBox(height: 3),
                      Text('${g.memberCount} members',
                        style: TextStyle(color: _C.onSurfVar.withValues(alpha: 0.7), fontSize: 10)),
                    ]),
                    trailing: ExcludeSemantics(child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _C.tertiary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6)),
                      child: Text('JOINED',
                        style: TextStyle(color: _C.tertiary,
                          fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5)))),
                ),
              ),
            );
          }),
        ),
    ]);
  }
}

/// P0-FL-10 · the groups read failed: a compact card in the place of the
/// groups, with the next step and a busy-aware Try again. Announced when it
/// appears; wraps at large text.
class _GroupsFailureCard extends StatelessWidget {
  final bool network;
  final bool busy;
  final VoidCallback onRetry;
  const _GroupsFailureCard({
    required this.network,
    required this.busy,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final retry = TextButton(
      onPressed: busy ? null : onRetry,
      style: TextButton.styleFrom(
        foregroundColor: _C.tertiary,
        backgroundColor: _C.tertiary.withValues(alpha: 0.12),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: const Size(48, 44), // U5 · 44px tap target
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
      child: busy
          ? Semantics(
              label: 'Retrying',
              child: const SizedBox(width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: _C.tertiary)))
          : const Text('Try again',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
    // At large text a trailing Try again is wider than the room beside the
    // icon: the text column was squeezed to nothing and the row overflowed
    // (2x, 320 wide). There it goes under the message instead.
    final stacked = MediaQuery.textScalerOf(context).scale(12) > 12 * 1.3;
    return _GlassCard(
        padding: const EdgeInsets.all(18),
        child: Semantics(
          liveRegion: true,
          container: true,
          child: Row(children: [
            Container(width: 44, height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle, color: _C.tertiary.withValues(alpha: 0.12)),
              child: const Icon(Icons.error_outline, color: _C.tertiary, size: 22)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text("Couldn't load your groups",
                style: TextStyle(color: _C.onSurface, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(
                network
                    ? 'Check your connection and try again.'
                    : 'Try again in a moment. If it keeps happening, contact support.',
                style: const TextStyle(color: _C.onSurfVar, fontSize: 11, height: 1.4)),
              if (stacked) ...[const SizedBox(height: 10), retry],
            ])),
            if (!stacked) ...[const SizedBox(width: 8), retry],
          ]),
        ),
      );
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
  }

  /// P0-FL-60b · the next shake. None while animations are turned off.
  Timer? _next;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _next?.cancel();
      _next = null;
      _ctrl.reset();
    } else {
      _next ??= Timer(const Duration(seconds: 1), _loop);
    }
  }
  void _loop() {
    _ctrl.forward(from: 0);
    _next = Timer(const Duration(milliseconds: 3500), _loop);
  }
  @override
  void dispose() { _next?.cancel(); _ctrl.dispose(); super.dispose(); }

  void _showNotifications() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NotificationsPanel(),
    );
  }

  @override
  Widget build(BuildContext context) => _TapTarget(
    label: 'Show upcoming classes and events',
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
    final classesAsync = ref.watch(memberUpcomingClassesProvider);
    final eventsAsync  = ref.watch(memberUpcomingEventsProvider);
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
          child: SizedBox(width: double.infinity, child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 8, children: [
            const Text('Upcoming', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _C.brand.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999)),
              child: Text('Today & beyond', style: TextStyle(color: _C.primary, fontSize: 11, fontWeight: FontWeight.w600))),
          ])),
        ),
        const SizedBox(height: 16),
        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 0, 20, bottom + 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Classes
              ..._upcomingSection(
                classesAsync,
                what: 'upcoming classes',
                onRetry: () => ref.invalidate(upcomingClassesProvider),
                loading: const SizedBox(height: 60, child: Center(child: CircularProgressIndicator(color: _C.primary, strokeWidth: 2))),
                rows: (classes) {
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
              ..._upcomingSection(
                eventsAsync,
                what: 'upcoming events',
                onRetry: () => ref.invalidate(upcomingEventsProvider),
                loading: const SizedBox.shrink(),
                rows: (events) {
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

  /// P0-FL-60b · a failed read was a section that vanished. The failure is
  /// said in its place; rows already read stay under it. Read and empty still
  /// shows nothing.
  static List<Widget> _upcomingSection(
    MemberRead<List<Map<String, dynamic>>> read, {
    required String what,
    required VoidCallback onRetry,
    required Widget loading,
    required Widget Function(List<Map<String, dynamic>> rows) rows,
  }) => [
    if (read.error != null)
      SectionLoadFailure(
        what: what, error: read.error, busy: read.busy, onRetry: onRetry,
        accent: _C.primary, textColor: _C.onSurface, mutedColor: _C.onSurfVar)
    else if (read.value == null)
      loading,
    if (read.value case final kept? when kept.isNotEmpty) ...[
      if (read.error != null) const SizedBox(height: 10),
      rows(kept),
    ],
  ];

  String _formatDate(String? iso) {
    if (iso == null) return '';
    try {
      final d = DateTime.parse(iso).toLocal();
      final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
      final m = d.minute.toString().padLeft(2, '0');
      final ampm = d.hour < 12 ? 'AM' : 'PM';
      return '${months[d.month - 1]} ${d.day} • $h:$m $ampm';
    } catch (e, st) {
      // Was blank, as if the class or event had no time.
      reportError('activity.upcoming.date', e, st);
      return 'Date unavailable';
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
    Expanded(child: Text(label.toUpperCase(), style: TextStyle(color: _C.primary, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5))),
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
  Widget build(BuildContext context) {
    final large = _largeText(context);
    // The badge is an event's location, of any length: it wraps within a
    // third of the width, and goes under the text at large text.
    final badgeView = badge.isEmpty ? null : ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: large ? double.infinity : MediaQuery.sizeOf(context).width / 3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(large ? 12 : 999),
          border: Border.all(color: iconColor.withValues(alpha: 0.2))),
        child: Text(badge, style: TextStyle(color: iconColor, fontSize: 10, fontWeight: FontWeight.w600))));
    return Semantics(
      container: true,
      button: true,
      label: ['Open $title', subtitle, badge].where((s) => s.isNotEmpty).join(', '),
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
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
              if (large && badgeView != null) ...[const SizedBox(height: 8), badgeView],
            ])),
            if (!large && badgeView != null) badgeView,
          ]),
        ),
      ),
    );
  }
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
