import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/domain/auth_provider.dart';
import '../../workout/domain/workout_provider.dart';
import '../../coach/domain/coach_provider.dart';
import '../../coach/domain/coach_ecosystem_provider.dart';
import '../../workout/presentation/resume_workout_banner.dart';
import '../../coaching_mode/domain/coaching_mode_provider.dart';
import '../../womens_health/domain/cycle_provider.dart';
import '../../womens_health/domain/cycle_phase.dart';
import '../../scoring/domain/score_provider.dart';
import '../../ai_coach/domain/ai_insights.dart';
import '../../ai_coach/presentation/ai_briefing_sheet.dart';
import '../../../core/widgets/app_top_nav.dart';
import '../../../core/widgets/blood_drop.dart';
import '../domain/home_session_card.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
class _C {
  static const bg           = Color(0xFF0A0A0B);
  static const surfContHigh = Color(0xFF222A3D);
  static const primary      = Color(0xFFDDB7FF);
  static const brand        = Color(0xFFA855F7);
  static const onSurface    = Color(0xFFDAE2FD);
  static const onSurfVar    = Color(0xFFCFC2D6);
  static const tertiary     = Color(0xFF6FFBBE);
}

// 7-day activity bars: each value 0.0–1.0 representing relative activity that day.
// Pulls from nutrition_logs (meal count) + coaching_calls (scheduled calls).
// Returns List<double> length 7, index 0 = Monday of current week.
//
// F-15 · ERRORS PROPAGATE. This used to end `catch (_) { return List.filled(7,
// 0.0); }`, so a failed read was indistinguishable from a week with nothing in
// it — and the card does not merely look empty, it answers. A client who had
// logged six meals was shown **"0%"** over seven flat bars and the line "Log
// meals or workouts to see progress". A failure presented as a confident wrong
// number, with a nudge blaming the client for it.
//
// `assignedWorkoutsProvider` in the workout feature carries the same note for
// the same reason; `train_hub_screen`'s three `error: (_, __) => '0'` stats were
// corrected to '—' on the same grounds.
final weeklyActivityProvider = FutureProvider<List<double>>((ref) async {
  // QAX-SES-01: recompute for whoever is signed in now, not whoever was.
  ref.watch(currentUserProvider);
  final uid = Supabase.instance.client.auth.currentUser?.id;
  // Signed out is not a failure — there is genuinely nothing to show.
  if (uid == null) return List.filled(7, 0.0);
  {
    final now    = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final weekStart = DateTime(monday.year, monday.month, monday.day);
    final weekEnd   = weekStart.add(const Duration(days: 7));

    // Nutrition logs this week
    final nutrition = await Supabase.instance.client
        .from('nutrition_logs')
        .select('logged_at')
        .eq('user_id', uid)
        .gte('logged_at', weekStart.toIso8601String())
        .lt('logged_at', weekEnd.toIso8601String());

    // Coaching calls this week (any status)
    final calls = await Supabase.instance.client
        .from('coaching_calls')
        .select('scheduled_at')
        .eq('client_id', uid)
        .gte('scheduled_at', weekStart.toIso8601String())
        .lt('scheduled_at', weekEnd.toIso8601String());

    // Count activity per weekday (0=Mon … 6=Sun)
    final counts = List<int>.filled(7, 0);
    for (final r in (nutrition as List)) {
      final dt = DateTime.tryParse(r['logged_at'] as String? ?? '')?.toLocal();
      if (dt == null) continue;
      final dayIdx = dt.weekday - 1;
      counts[dayIdx] += 1;
    }
    for (final r in (calls as List)) {
      final dt = DateTime.tryParse(r['scheduled_at'] as String? ?? '')?.toLocal();
      if (dt == null) continue;
      final dayIdx = dt.weekday - 1;
      counts[dayIdx] += 3; // calls count more
    }

    // Normalize to 0.0–1.0 (cap at ~10 actions per day)
    final maxCount = counts.reduce((a, b) => a > b ? a : b);
    if (maxCount == 0) return List.filled(7, 0.0);
    return counts.map((c) => (c / maxCount).clamp(0.05, 1.0)).toList();
  }
});

/// What "This Week's Progress" should say, derived from the read's state rather
/// than from a value the read never produced.
///
/// Extracted because `home_screen.dart` reaches `Supabase.instance` at the top
/// level, so the card cannot be mounted in a widget test. Same reason
/// `plan_summary.dart` and `extendRest()` were extracted.
typedef WeekProgress = ({
  /// What goes where the percentage goes. `'—'` when the read failed: the
  /// screen does not know, and a number would be a claim it cannot support.
  String headline,

  /// The nudge under the title, or null when there is nothing honest to say.
  /// **Null on failure is the point** — "Log meals or workouts to see progress"
  /// told a client who had logged meals that they had not.
  String? nudge,

  /// Bar heights, 0.0–1.0.
  List<double> bars,

  /// True when the read failed, so the card can render the bars as unknown
  /// rather than as zero.
  bool failed,
});

WeekProgress weekProgressFrom(AsyncValue<List<double>> activity) {
  final bars = activity.valueOrNull ?? List.filled(7, 0.0);
  if (activity.hasError) {
    return (headline: '—', nudge: null, bars: List.filled(7, 0.0), failed: true);
  }
  final activeDays = bars.where((v) => v > 0.05).length;
  final pct = (activeDays / 7 * 100).round();
  return (
    headline: '$pct%',
    nudge: pct == 0
        ? 'Log meals or workouts to see progress'
        : pct >= 70
            ? 'Excellent consistency!'
            : 'Keep building your streak',
    bars: bars,
    failed: false,
  );
}

// ── Home Screen ───────────────────────────────────────────────────────────────
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

// Home session-card hero images — rotates on each visit (first two as requested).
const _heroImages = [
  'assets/images/workout_hero.png',
  'assets/images/workout-glute.jpg',
  'assets/images/workout-full-body.jpg',
  'assets/images/workout-hiit.jpg',
  'assets/images/train-squat.jpg',
];

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _panelCtrl;
  late final Animation<double> _panelAnim;
  // Picked once when the home screen is (re)entered, so it changes each visit.
  final String _heroImage = _heroImages[math.Random().nextInt(_heroImages.length)];

  @override
  void initState() {
    super.initState();
    _panelCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 420));
    _panelAnim = CurvedAnimation(
      parent: _panelCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic);
  }

  @override
  void dispose() { _panelCtrl.dispose(); super.dispose(); }

  void _openPanel() {
    HapticFeedback.mediumImpact();
    _panelCtrl.forward();
  }

  void _closePanel() => _panelCtrl.reverse();

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent));
    final topPad  = MediaQuery.of(context).padding.top;
    final screenH = MediaQuery.of(context).size.height;

    final headerH    = topPad + 64.0;
    final panelH     = screenH * 0.86;

    return Scaffold(
      backgroundColor: _C.bg,
      body: Stack(fit: StackFit.expand, children: [

        // ── Static body — fills the space below header, no scrolling ─────
        Positioned(
          top: headerH,
          left: 16, right: 16, bottom: 0,
          child: Builder(builder: (context) {
            final mode = ref.watch(coachingModeProvider);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),
                const ResumeWorkoutBanner(),
                // Hero — Today's Session (image + badges + title/Start section).
                Expanded(child: _FitnessSessionCard(mode: mode, heroImage: _heroImage)),
                const SizedBox(height: 11),
                // 12 Circle Score — chevron pulls down the Wellness Pulse panel.
                _ScoreCard(onExpand: _openPanel),
                const SizedBox(height: 11),
                // Quick actions — 2×2 grid.
                const _QuickGrid(),
                const SizedBox(height: 11),
                // Mode-specific bottom card
                if (mode == CoachingMode.coachGuided) ...[
                  _CoachTipCard(),
                  const SizedBox(height: 10),
                ] else if (mode == CoachingMode.aiGuided) ...[
                  _AIInsightCard(),
                  const SizedBox(height: 10),
                ] else if (mode == CoachingMode.selfGuided) ...[
                  _MyPlanCard(),
                  const SizedBox(height: 10),
                ],
              ],
            );
          }),
        ),

        // ── Fixed header ───────────────────────────────────────────────────
        Positioned(top: 0, left: 0, right: 0,
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                height: headerH,
                padding: EdgeInsets.only(top: topPad, left: 16, right: 16),
                decoration: BoxDecoration(
                  color: _C.bg.withValues(alpha: 0.6),
                  border: Border(bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.06)))),
                child: const Center(child: AppTopNavRow()),
              ),
            ),
          )),

        // ── Scrim ──────────────────────────────────────────────────────────
        AnimatedBuilder(
          animation: _panelAnim,
          builder: (_, __) => IgnorePointer(
            ignoring: _panelAnim.value < 0.05,
            child: GestureDetector(
              onTap: _closePanel,
              child: Container(
                color: Colors.black.withValues(
                  alpha: 0.55 * _panelAnim.value))))),

        // ── Slide-down panel ───────────────────────────────────────────────
        AnimatedBuilder(
          animation: _panelAnim,
          builder: (_, child) => Transform.translate(
            offset: Offset(0, panelH * (_panelAnim.value - 1)),
            child: child!),
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: panelH,
              child: _WellnessPulsePanel(onClose: _closePanel)))),
      ]),
    );
  }
}

// ── 12 Circle Score Card ──────────────────────────────────────────────────────
// Lives in the body now; the chevron pulls down the full Wellness Pulse panel.
class _ScoreCard extends ConsumerWidget {
  final VoidCallback onExpand;
  const _ScoreCard({required this.onExpand});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s     = ref.watch(myScoreProvider).valueOrNull;
    final total = (s?['current_cycle_score'] as num?)?.toInt() ?? 0;

    return GestureDetector(
      onTap: onExpand,
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 80) onExpand();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [
              _C.brand.withValues(alpha: 0.14),
              Colors.white.withValues(alpha: 0.03),
            ]),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFB06BFF).withValues(alpha: 0.18))),
        child: Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.16), width: 2)),
            alignment: Alignment.center,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$total',
                style: const TextStyle(color: Colors.white, fontSize: 16,
                  fontWeight: FontWeight.w800, height: 1)),
              Text('PTS',
                style: TextStyle(color: _C.onSurfVar.withValues(alpha: 0.5),
                  fontSize: 8.5, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
            ])),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('12 CIRCLE SCORE',
              style: TextStyle(color: _C.primary, fontSize: 13,
                fontWeight: FontWeight.w700, letterSpacing: 0.9)),
            const SizedBox(height: 2),
            Text("Complete today's goals to earn points.",
              style: TextStyle(color: _C.onSurfVar.withValues(alpha: 0.72), fontSize: 12.5)),
          ])),
          Icon(Icons.keyboard_arrow_down_rounded,
            color: _C.onSurfVar.withValues(alpha: 0.55), size: 22),
        ])));
  }
}

// ── Wellness Pulse Panel ──────────────────────────────────────────────────────
class _WellnessPulsePanel extends ConsumerWidget {
  final VoidCallback onClose;
  const _WellnessPulsePanel({required this.onClose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final score     = ref.watch(todayScoreProvider).valueOrNull ?? {};
    final total     = score['total_score']      as int? ?? 0;
    final workout   = score['workout_points']   as int? ?? 0;
    final nutrition = score['nutrition_points'] as int? ?? 0;
    final habits    = score['habits_points']    as int? ?? 0;
    final checkins  = score['checkin_points']   as int? ?? 0;
    final community = score['community_points'] as int? ?? 0;
    final streak    = ref.watch(currentStreakProvider).valueOrNull ?? 0;
    final cScore    = ref.watch(myScoreProvider).valueOrNull;
    final cCycle    = (cScore?['current_cycle_score'] as num?)?.toInt() ?? 0;
    final cLevel    = (cScore?['level'] as num?)?.toInt() ?? 1;
    final cRank     = cScore?['rank'] as String? ?? 'Bronze';
    final topPad    = MediaQuery.of(context).padding.top;
    final now       = DateTime.now();
    const months    = ['JAN','FEB','MAR','APR','MAY','JUN',
      'JUL','AUG','SEP','OCT','NOV','DEC'];
    final dateStr   = '${months[now.month - 1]} ${now.day}';

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(44)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xF0131B2E),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(44)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.7),
                blurRadius: 50, offset: const Offset(0, 20)),
              BoxShadow(color: _C.brand.withValues(alpha: 0.12), blurRadius: 80),
            ]),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, topPad + 20, 24, 32),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              // Header
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end, children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('DAILY FOCUS',
                    style: TextStyle(color: _C.primary, fontSize: 10,
                      fontWeight: FontWeight.w700, letterSpacing: 2.5)),
                  const Text('Wellness Pulse',
                    style: TextStyle(color: _C.onSurface, fontSize: 28,
                      fontWeight: FontWeight.w900, letterSpacing: -0.5, height: 1.1)),
                ]),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(dateStr,
                    style: TextStyle(color: _C.onSurfVar.withValues(alpha: 0.5),
                      fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1)),
                  if (streak > 0)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      const _StreakFlame(),
                      const SizedBox(width: 3),
                      Text('STREAK: $streak DAYS',
                        style: const TextStyle(color: _C.primary, fontSize: 10,
                          fontWeight: FontWeight.w700, letterSpacing: 1)),
                    ]),
                ]),
              ]),
              const SizedBox(height: 16),

              // 12 Circle Score — tap for full dashboard, badges & leaderboard.
              GestureDetector(
                onTap: () => context.push('/score'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      const Color(0xFFFFD479).withValues(alpha: 0.18), const Color(0xFF0C0911)]),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFFD479).withValues(alpha: 0.35))),
                  child: Row(children: [
                    const Icon(Icons.military_tech_rounded, color: Color(0xFFFFD479), size: 26),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('12 CIRCLE SCORE', style: TextStyle(color: Color(0xFFFFD479),
                        fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                      Text('$cCycle pts · $cRank · Level $cLevel',
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                    ])),
                    const Icon(Icons.chevron_right_rounded, color: Color(0xFFFFD479), size: 22),
                  ]),
                ),
              ),
              const SizedBox(height: 16),

              Text('TODAY’S ACTIVITY', style: TextStyle(color: _C.primary.withValues(alpha: 0.6),
                fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 2)),
              const SizedBox(height: 10),
              // Daily wellness ring (today's points by category)
              _PanelScoreSection(total: total,
                workout: workout, nutrition: nutrition, habits: habits),
              const SizedBox(height: 14),

              // Mini cards
              Row(children: [
                Expanded(child: _MiniMetricCard(
                  icon: Icons.event_available_rounded,
                  label: 'CHECK-INS',
                  value: checkins, max: 10, color: _C.primary)),
                const SizedBox(width: 12),
                Expanded(child: _MiniMetricCard(
                  icon: Icons.groups_rounded,
                  label: 'COMMUNITY',
                  value: community, max: 10, color: _C.tertiary)),
              ]),
              const SizedBox(height: 14),

              // Week bars
              const _PanelWeekProgress(),
              const SizedBox(height: 20),

              // Close handle
              GestureDetector(
                onTap: onClose,
                onVerticalDragEnd: (d) {
                  if ((d.primaryVelocity ?? 0) < -80) onClose();
                },
                child: Column(children: [
                  Center(child: Container(
                    width: 44, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 6),
                  Center(child: Text('SWIPE UP TO CLOSE',
                    style: TextStyle(color: _C.onSurfVar.withValues(alpha: 0.25),
                      fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 2))),
                ])),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Animated streak flame (flickers/pulses next to the streak count) ──────────
class _StreakFlame extends StatefulWidget {
  const _StreakFlame();
  @override
  State<_StreakFlame> createState() => _StreakFlameState();
}

class _StreakFlameState extends State<_StreakFlame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 850))
      ..repeat(reverse: true);
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = Curves.easeInOut.transform(_c.value);
        return Transform.scale(
          scale: 0.9 + t * 0.22, // gentle swell
          child: Opacity(
            opacity: 0.7 + t * 0.3,
            child: Icon(Icons.local_fire_department_rounded,
              color: Color.lerp(const Color(0xFFFF8A3D), const Color(0xFFFFC24B), t),
              size: 13),
          ),
        );
      },
    );
  }
}

// ── Panel Score Section ───────────────────────────────────────────────────────
class _PanelScoreSection extends StatelessWidget {
  final int total, workout, nutrition, habits;
  const _PanelScoreSection({required this.total, required this.workout,
    required this.nutrition, required this.habits});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
    decoration: BoxDecoration(
      color: _C.brand.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: Colors.white.withValues(alpha: 0.07))),
    child: Column(children: [
      SizedBox(
        width: 180, height: 180,
        child: Stack(alignment: Alignment.center, children: [
          CustomPaint(
            size: const Size(180, 180),
            painter: _ScoreRingPainter(progress: total / 100.0)),
          Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('12Circle Score',
              style: TextStyle(color: Color(0xFFCFC2D6),
                fontSize: 11, fontWeight: FontWeight.w500)),
            ShaderMask(
              shaderCallback: (b) => const LinearGradient(
                colors: [Color(0xFFDDB7FF), Color(0xFFB76DFF)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ).createShader(b),
              child: Text('$total',
                style: const TextStyle(color: Colors.white,
                  fontSize: 52, fontWeight: FontWeight.w900, height: 1.0))),
            Row(mainAxisSize: MainAxisSize.min, children: const [
              Icon(Icons.trending_up_rounded, color: Color(0xFF6FFBBE), size: 14),
              SizedBox(width: 2),
              Text('+4%', style: TextStyle(color: Color(0xFF6FFBBE),
                fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
          ]),
          _RingDot(progress: total / 100.0),
        ])),
      const SizedBox(height: 20),
      Row(children: [
        Expanded(child: _SubMetric(
          icon: Icons.fitness_center_rounded, label: 'WORKOUT', value: workout)),
        Container(width: 0.5, height: 52,
          color: Colors.white.withValues(alpha: 0.07)),
        Expanded(child: _SubMetric(
          icon: Icons.local_dining_rounded, label: 'NUTRITION', value: nutrition)),
        Container(width: 0.5, height: 52,
          color: Colors.white.withValues(alpha: 0.07)),
        Expanded(child: _SubMetric(
          icon: Icons.task_alt_rounded, label: 'HABITS', value: habits)),
      ]),
    ]));
}

// ── Score Ring Painter ────────────────────────────────────────────────────────
class _ScoreRingPainter extends CustomPainter {
  final double progress;
  const _ScoreRingPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;
    final rect   = Rect.fromCircle(center: center, radius: radius);

    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi, false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.05)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10);

    if (progress > 0) {
      canvas.drawArc(rect, -math.pi / 2, progress * 2 * math.pi, false,
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFFDDB7FF), Color(0xFFB76DFF)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ).createShader(rect)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(_ScoreRingPainter old) => old.progress != progress;
}

// ── Ring Dot ──────────────────────────────────────────────────────────────────
class _RingDot extends StatelessWidget {
  final double progress;
  const _RingDot({required this.progress});

  @override
  Widget build(BuildContext context) {
    const r = 80.0;
    final angle = -math.pi / 2 + progress * 2 * math.pi;
    return Transform.translate(
      offset: Offset(r * math.cos(angle), r * math.sin(angle)),
      child: Container(
        width: 14, height: 14,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          boxShadow: [
            BoxShadow(color: Colors.white.withValues(alpha: 0.9), blurRadius: 10),
            BoxShadow(color: _C.primary.withValues(alpha: 0.7), blurRadius: 20),
          ])));
  }
}

// ── Sub Metric ────────────────────────────────────────────────────────────────
class _SubMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  const _SubMetric({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(children: [
    Icon(icon, color: _C.onSurfVar.withValues(alpha: 0.6), size: 22),
    const SizedBox(height: 6),
    Text('$value',
      style: const TextStyle(color: _C.onSurface, fontSize: 26,
        fontWeight: FontWeight.w900)),
    Text(label,
      style: TextStyle(color: _C.onSurfVar.withValues(alpha: 0.45),
        fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
  ]);
}

// ── Mini Metric Card ──────────────────────────────────────────────────────────
class _MiniMetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value, max;
  final Color color;
  const _MiniMetricCard({required this.icon, required this.label,
    required this.value, required this.max, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withValues(alpha: 0.07))),
    child: Row(children: [
      Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: color, size: 18)),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
          style: TextStyle(color: _C.onSurfVar.withValues(alpha: 0.5),
            fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 1)),
        Text('$value / $max',
          style: TextStyle(color: color, fontSize: 15,
            fontWeight: FontWeight.w800)),
      ])),
    ]));
}

// ── Panel Week Progress ───────────────────────────────────────────────────────
class _PanelWeekProgress extends ConsumerWidget {
  static const _days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  const _PanelWeekProgress();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final barsAsync = ref.watch(weeklyActivityProvider);
    final week      = weekProgressFrom(barsAsync);
    final bars      = week.bars;
    final todayIdx  = (DateTime.now().weekday - 1).clamp(0, 6);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06))),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // FIT-001 folds Activity into Home — "Activity folded in ·
            // Directory moved to the top bar" — and the bottom bar no longer
            // carries an Activity tab. That tab was `/activity`'s ONLY
            // entrance, and a 1,089-line screen losing its last door is not
            // what "folded in" means (OD-15). This panel IS the activity
            // content on Home, so it is where the full screen opens from.
            Semantics(
              button: true,
              label: "This Week's Progress",
              hint: 'Opens your activity',
              excludeSemantics: true,
              onTap: () => context.go('/activity'),
              child: GestureDetector(
                onTap: () => context.go('/activity'),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  alignment: Alignment.centerLeft,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text("This Week's Progress",
                      style: TextStyle(color: _C.onSurfVar.withValues(alpha: 0.8),
                        fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right,
                        color: _C.onSurfVar.withValues(alpha: 0.5), size: 16),
                  ]),
                ),
              ),
            ),
            if (week.nudge != null) ...[
              const SizedBox(height: 2),
              Text(week.nudge!,
                style: TextStyle(color: _C.onSurfVar.withValues(alpha: 0.35), fontSize: 11)),
            ],
          ]),
          if (barsAsync.isLoading)
            const SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: _C.primary))
          else
            Text(week.headline,
              style: TextStyle(
                color: week.failed
                    ? _C.onSurfVar.withValues(alpha: 0.5)
                    : _C.primary,
                fontSize: 28,
                fontWeight: FontWeight.w900, letterSpacing: -1, height: 1)),
        ]),
        const SizedBox(height: 16),
        SizedBox(
          height: 72,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(7, (i) {
              // On failure every bar is the flat unknown track and nothing is
              // highlighted — a lit "today" bar over a failed read reads as
              // "you did nothing today", which is exactly the claim the screen
              // cannot make.
              final isToday  = !week.failed && i == todayIdx;
              final isPast   = i < todayIdx;
              final height   = 72 * (bars[i] > 0 ? bars[i] : (isToday ? 0.15 : 0.04));
              return Expanded(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Container(
                  height: height,
                  decoration: BoxDecoration(
                    color: isToday ? _C.brand
                      : bars[i] > 0.05
                        ? _C.brand.withValues(alpha: isPast ? 0.55 : 0.2)
                        : Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: isToday ? [
                      BoxShadow(color: _C.brand.withValues(alpha: 0.4), blurRadius: 14)
                    ] : null))));
            })),
        ),
        const SizedBox(height: 8),
        Row(children: List.generate(7, (i) => Expanded(
          child: Center(
            child: Text(_days[i],
              style: TextStyle(
                color: i == todayIdx
                    ? _C.primary
                    : _C.onSurfVar.withValues(alpha: 0.25),
                fontSize: 9, fontWeight: FontWeight.w700)))))),
      ]));
  }
}

// ── Quick actions — 2×2 grid ──────────────────────────────────────────────────
class _QuickGrid extends ConsumerWidget {
  const _QuickGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Weekly check-in points (matches the +pts shown on the check-in flow).
    const checkinPts = 10;

    // Women's Health tile adapts to the user's cycle data when available.
    final profile  = ref.watch(currentUserProfileProvider).valueOrNull;
    final isFemale = (profile?['gender'] as String?)?.toLowerCase() == 'female';
    final status   = ref.watch(cycleStatusProvider).valueOrNull;
    final guide    = status != null ? phaseGuides[status.phase] : null;
    final whColor  = guide?.color ?? const Color(0xFFFF5D7A);
    final whHasData = isFemale && status != null && status.hasData;
    final whSub    = whHasData
        ? '${guide!.label} · Day ${status.cycleDay}'
        : 'Track your cycle';

    Widget tile({
      required String title, required String subtitle,
      required Widget icon, required List<Color> gradient,
      required Color subColor, required VoidCallback onTap,
      List<Color>? bgGradient, Color? borderColor,
    }) => _HomeTile(
        title: title, subtitle: subtitle, icon: icon,
        gradient: gradient, subColor: subColor, onTap: onTap,
        bgGradient: bgGradient, borderColor: borderColor);

    final wh = tile(
      title: "Women's Health", subtitle: whSub,
      icon: BloodDrop(size: 19, color: Colors.white),
      gradient: const [Color(0xFFFF6B8A), Color(0xFFE84D6A)],
      subColor: whColor,
      // Restore the phase-tinted card background from the old WH banner.
      bgGradient: [whColor.withValues(alpha: 0.16), const Color(0xFF281018)],
      borderColor: whColor.withValues(alpha: 0.28),
      onTap: () => context.push('/womens-health'));

    final aiCoach = tile(
      title: 'AI Coach', subtitle: 'Ask anything',
      icon: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
      gradient: const [Color(0xFF7CC4FF), Color(0xFFB06BFF)],
      subColor: _C.onSurfVar.withValues(alpha: 0.55),
      onTap: () => context.push('/ai-coach'));

    return Column(children: [
      Row(children: [
        Expanded(child: tile(
          title: 'Weekly Check-In', subtitle: '+$checkinPts pts',
          icon: const Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 21),
          gradient: const [Color(0xFFB06BFF), Color(0xFF8A3DF0)],
          subColor: _C.primary,
          onTap: () => context.push('/daily-checkin'))),
        const SizedBox(width: 11),
        Expanded(child: wh),
      ]),
      const SizedBox(height: 11),
      Row(children: [
        Expanded(child: aiCoach),
        const SizedBox(width: 11),
        Expanded(child: tile(
          title: 'Book a Call', subtitle: 'With your coach',
          icon: const Icon(Icons.videocam_rounded, color: Colors.white, size: 21),
          gradient: const [Color(0xFF34D399), Color(0xFF10B981)],
          subColor: _C.onSurfVar.withValues(alpha: 0.55),
          onTap: () => context.push('/book-call'))),
      ]),
    ]);
  }
}

class _HomeTile extends StatelessWidget {
  final String title, subtitle;
  final Widget icon;
  final List<Color> gradient;
  final Color subColor;
  final VoidCallback onTap;
  // Optional tinted card background (e.g. the Women's Health phase colour) — when
  // null the tile uses the default flat translucent surface.
  final List<Color>? bgGradient;
  final Color? borderColor;
  const _HomeTile({
    required this.title, required this.subtitle, required this.icon,
    required this.gradient, required this.subColor, required this.onTap,
    this.bgGradient, this.borderColor});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 62),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: bgGradient == null ? Colors.white.withValues(alpha: 0.035) : null,
        gradient: bgGradient == null ? null : LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight, colors: bgGradient!),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor ?? Colors.white.withValues(alpha: 0.08))),
      child: Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: gradient),
            borderRadius: BorderRadius.circular(13),
            boxShadow: [BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 12, offset: const Offset(0, 4))]),
          alignment: Alignment.center,
          child: icon),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min, children: [
          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 13.5,
              fontWeight: FontWeight.w700, height: 1.12)),
          const SizedBox(height: 3),
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: subColor, fontSize: 11,
              fontWeight: FontWeight.w600, height: 1.2)),
        ])),
      ]),
    ),
  );
}

// ── My Plan Card (Self Guided) ────────────────────────────────────────────────
class _MyPlanCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => context.go('/train'),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0B16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.primary.withValues(alpha: 0.25))),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: _C.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle),
          child: const Icon(Icons.grid_view_rounded,
            color: _C.primary, size: 20)),
        const SizedBox(width: 12),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Text('My Plan', style: TextStyle(color: Colors.white,
            fontSize: 14, fontWeight: FontWeight.w700)),
          Text('View your personalised program and goals',
            style: TextStyle(color: Color(0xFFCFC2D6), fontSize: 12)),
        ])),
        Icon(Icons.chevron_right_rounded,
          color: _C.primary.withValues(alpha: 0.7), size: 20),
      ]),
    ),
  );
}

// ── AI Insight Card (AI Guided) ───────────────────────────────────────────────
class _AIInsightCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Data-driven progress insight + a count of today's generated suggestions.
    // Tapping opens the full AI briefing (suggestions + weekly review).
    final insightText  = ref.watch(aiProgressInsightProvider);
    final suggestCount = ref.watch(aiDailySuggestionsProvider).length;
    return GestureDetector(
      onTap: () => showAiBriefingSheet(context),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF6FFBBE).withValues(alpha: 0.08),
              _C.brand.withValues(alpha: 0.06),
            ],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF6FFBBE).withValues(alpha: 0.2))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF6FFBBE).withValues(alpha: 0.15)),
            child: const Icon(Icons.auto_awesome,
              color: Color(0xFF6FFBBE), size: 18)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            const Text('AI BRIEFING',
              style: TextStyle(color: Color(0xFF6FFBBE), fontSize: 9,
                fontWeight: FontWeight.w800, letterSpacing: 1.5)),
            const SizedBox(height: 4),
            Text(insightText,
              style: TextStyle(
                color: _C.onSurfVar.withValues(alpha: 0.9),
                fontSize: 12, height: 1.45)),
            const SizedBox(height: 4),
            Text('$suggestCount suggestion${suggestCount == 1 ? '' : 's'} today · tap for weekly review ›',
              style: const TextStyle(color: Color(0xFF6FFBBE), fontSize: 11,
                fontWeight: FontWeight.w600)),
          ])),
        ]),
      ),
    );
  }
}

// ── Fitness Session Card ──────────────────────────────────────────────────────
class _FitnessSessionCard extends ConsumerWidget {
  final CoachingMode mode;
  final String heroImage;
  const _FitnessSessionCard({required this.mode, required this.heroImage});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAI = mode == CoachingMode.aiGuided;

    // FIT-001's Today card. The rules — and the four defects they replace —
    // are in `domain/home_session_card.dart`. The short version: this read
    // `assigned.isNotEmpty ? assigned : sample` and captioned a DEMO workout
    // "Assigned by your coach", which is F-20 on the front door.
    final session = homeSession(ref.watch(assignedWorkoutsProvider));
    final badges = homeSessionBadges(session.workout);

    final title    = session.title ?? session.emptyLine;
    final subtitle = session.context ??
        (isAI ? 'Personalised by your AI coach' : 'Today');
    // One label, because it is one action. The board gives it on FIT-001 and
    // FIT-014 alike; the card had three words depending on coaching mode.
    const btnLabel = HomeSession.beginLabel;

    void onStart() {
      // A session that exists is started. Nothing else is invented: with no
      // assignment the card sends the client to their plan rather than
      // starting a workout that is not theirs.
      final w = session.workout;
      if (w != null) {
        ref.read(selectedWorkoutProvider.notifier).state = w;
        context.go('/active-workout');
        return;
      }
      context.go(isAI ? '/ai-coach' : '/train');
    }

    // Start button gradient — purple in the design (blue tint for AI mode).
    final btnGradient = isAI
        ? const [Color(0xFF22B8D6), Color(0xFF0E8FB0)]
        : const [Color(0xFFB06BFF), Color(0xFF8A3DF0)];

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Image area — hero photo, gradient scrim, stat badges.
          Expanded(child: Stack(fit: StackFit.expand, children: [
            ColorFiltered(
              colorFilter: ColorFilter.matrix(isAI
                ? [0.0, 0.0, 0.4, 0, 0,   // AI: tint blue
                   0.0, 0.2, 0.3, 0, 0,
                   0.0, 0.4, 0.6, 0, 0,
                   0,   0,   0,   1, 0,]
                : [1, 0, 0, 0, 0,         // non-AI: actual colour (identity)
                   0, 1, 0, 0, 0,
                   0, 0, 1, 0, 0,
                   0, 0, 0, 1, 0,]),
              child: Image.asset(heroImage,
                fit: BoxFit.cover, alignment: const Alignment(0, -0.5),
                errorBuilder: (_, __, ___) => Container(
                  decoration: BoxDecoration(gradient: LinearGradient(
                    colors: isAI
                      ? [const Color(0xFF003040), const Color(0xFF060814)]
                      : [const Color(0xFF1A0030), const Color(0xFF0A0612)],
                    begin: Alignment.topRight, end: Alignment.bottomLeft))))),
            const DecoratedBox(decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, Color(0x000A0A0B), Color(0xB80C0911)],
                stops: [0.0, 0.5, 1.0],
                begin: Alignment.topCenter, end: Alignment.bottomCenter))),
            // Only what the workout states. `45 min`, `550 kcal` and
            // `2.0K steps` were literals presented as this session's stats;
            // duration is a real field, the other two are recorded nowhere.
            if (badges.isNotEmpty)
              Positioned(left: 14, right: 14, bottom: 13,
                child: Row(children: [
                  for (final b in badges) ...[
                    _SessionBadge(
                      icon: b.contains('min')
                          ? Icons.schedule_rounded
                          : Icons.fitness_center_rounded,
                      text: b,
                      iconColor: _C.primary),
                    const SizedBox(width: 8),
                  ],
                ])),
          ])),
          // Title + Start section.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min, children: [
                Text(subtitle.toUpperCase(),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _C.primary, fontSize: 11,
                    fontWeight: FontWeight.w700, letterSpacing: 0.9)),
                const SizedBox(height: 4),
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 23,
                    fontWeight: FontWeight.w800, height: 1.05, letterSpacing: -0.2)),
              ])),
              const SizedBox(width: 12),
              Semantics(
                button: true,
                label: session.canBegin ? btnLabel : 'Go to your plan',
                excludeSemantics: true,
                onTap: onStart,
                child: GestureDetector(
                onTap: onStart,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(19, 11, 16, 11),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: btnGradient),
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [BoxShadow(
                      color: btnGradient.last.withValues(alpha: 0.45),
                      blurRadius: 18, offset: const Offset(0, 6))]),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(session.canBegin ? btnLabel : 'Go to your plan',
                      style: const TextStyle(color: Colors.white, fontSize: 15,
                        fontWeight: FontWeight.w700)),
                    const SizedBox(width: 6),
                    const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18),
                  ])))),
            ])),
        ]),
      ),
    );
  }
}

class _SessionBadge extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color iconColor;
  const _SessionBadge({required this.icon, required this.text,
    required this.iconColor});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: Colors.white.withValues(alpha: 0.12))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: iconColor, size: 11),
      const SizedBox(width: 4),
      Text(text, style: const TextStyle(color: Colors.white, fontSize: 10,
        fontWeight: FontWeight.w600)),
    ]));
}

// ── Coach Tip Card ────────────────────────────────────────────────────────────
class _CoachTipCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coachAsync = ref.watch(assignedCoachProvider);
    final tipAsync   = ref.watch(coachTipProvider);
    final coach      = coachAsync.valueOrNull;
    final tip        = tipAsync.valueOrNull;
    final coachName  = coach == null ? null
        : '${coach['first_name'] ?? ''} ${coach['last_name'] ?? ''}'.trim();
    final avatarUrl  = coach?['avatar_url'] as String?;
    final tipText    = tip?['content'] as String?
        ?? 'Stay consistent. Small daily actions create lasting results.';

    if (coachAsync.isLoading || coach == null) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07))),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 3, color: const Color(0xFFB06BFF)),
            Expanded(child: Padding(
              padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _C.brand.withValues(alpha: 0.14),
                      border: Border.all(
                        color: _C.brand.withValues(alpha: 0.3), width: 1)),
                    child: ClipOval(child: avatarUrl != null
                      ? Image.network(avatarUrl, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _CoachAvatar())
                      : _CoachAvatar())),
                  const SizedBox(width: 11),
                  Expanded(child: Row(children: [
                    Flexible(child: Text(
                      coachName != null ? 'Coach $coachName' : 'Your Coach',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white,
                        fontSize: 14.5, fontWeight: FontWeight.w700))),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _C.brand.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10)),
                      child: const Text('TIP',
                        style: TextStyle(color: _C.primary, fontSize: 10,
                          fontWeight: FontWeight.w700, letterSpacing: 0.5))),
                  ])),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _showRateCoachDialog(context, coach['id'] as String),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.10))),
                      child: Row(mainAxisSize: MainAxisSize.min, children: const [
                        Icon(Icons.star_rounded, color: Color(0xFFFFD34D), size: 14),
                        SizedBox(width: 6),
                        Text('Rate', style: TextStyle(color: Colors.white,
                          fontSize: 12.5, fontWeight: FontWeight.w600)),
                      ]))),
                ]),
                const SizedBox(height: 10),
                Text('"$tipText"',
                  style: TextStyle(
                    color: _C.onSurfVar.withValues(alpha: 0.72),
                    fontSize: 12.5, height: 1.4, fontStyle: FontStyle.italic)),
              ]),
            )),
          ]),
        ),
      ),
    );
  }
}

void _showRateCoachDialog(BuildContext context, String coachId) {
  int selectedStars = 5;
  final textCtrl = TextEditingController();
  bool saving = false;
  showDialog(
    context: context,
    useRootNavigator: true,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (dialogCtx, setSt) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Rate Your Coach',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('How has your coaching experience been?',
            style: TextStyle(color: Color(0xFFCFC2D6), fontSize: 13)),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) => GestureDetector(
              onTap: () => setSt(() => selectedStars = i + 1),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  i < selectedStars
                    ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: const Color(0xFFA855F7), size: 36))))),
          const SizedBox(height: 16),
          TextField(
            controller: textCtrl,
            maxLines: 3,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Share your experience (optional)',
              hintStyle: const TextStyle(color: Color(0xFF666666)),
              filled: true,
              fillColor: const Color(0xFF0B0B0D),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF2A2A3D))),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF2A2A3D))))),
        ]),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dialogCtx, rootNavigator: true).pop(),
            child: const Text('Cancel',
              style: TextStyle(color: Color(0xFF666666)))),
          TextButton(
            onPressed: saving ? null : () async {
              setSt(() => saving = true);
              try {
                final uid =
                    Supabase.instance.client.auth.currentUser?.id;
                if (uid == null) return;
                await Supabase.instance.client.from('coach_reviews').upsert({
                  'coach_id': coachId, 'client_id': uid,
                  'rating': selectedStars,
                  'review_text': textCtrl.text.trim().isEmpty
                    ? null : textCtrl.text.trim(),
                  'created_at': DateTime.now().toIso8601String(),
                }, onConflict: 'coach_id,client_id');
                final reviews = await Supabase.instance.client
                    .from('coach_reviews').select('rating')
                    .eq('coach_id', coachId);
                final ratings = (reviews as List)
                    .map((r) => (r['rating'] as int)).toList();
                final avg = ratings.isEmpty ? 0.0
                    : ratings.reduce((a, b) => a + b) / ratings.length;
                await Supabase.instance.client.from('user_profiles').update({
                  'rating_avg': avg, 'review_count': ratings.length,
                }).eq('id', coachId);
                if (dialogCtx.mounted) {
                  Navigator.of(dialogCtx, rootNavigator: true).pop();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Review submitted! Thank you.'),
                    backgroundColor: Color(0xFFA855F7)));
                }
              } catch (_) { setSt(() => saving = false); }
            },
            child: saving
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(
                    color: Color(0xFFA855F7), strokeWidth: 2))
              : const Text('Submit', style: TextStyle(color: Color(0xFFA855F7),
                  fontWeight: FontWeight.w700))),
        ],
      ),
    ),
  );
}

class _CoachAvatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    color: _C.surfContHigh,
    child: const Icon(Icons.person_rounded, color: _C.primary, size: 22));
}

