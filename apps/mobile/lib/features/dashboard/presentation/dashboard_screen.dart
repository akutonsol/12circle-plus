import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../auth/domain/auth_provider.dart';
import '../domain/dashboard_provider.dart';
import '../../../shared/widgets/cinematic_backdrop.dart';

// Exact colors from Stitch DESIGN.md
class _S {
  static const bg          = Color(0xFF0A0A0B);
  static const card        = Color(0xFF161618);
  static const cardHigh    = Color(0xFF27272A);
  static const primary     = Color(0xFFDDB7FF);
  static const primaryCont = Color(0xFFB76DFF);
  static const secondary   = Color(0xFFADC6FF);
  static const tertiary    = Color(0xFF4EDEA3);
  static const onSurface   = Color(0xFFE5E2E3);
  static const onSurfaceV  = Color(0xFFCFC2D6);
  static const outlineVar  = Color(0xFF4D4354);
  static const orange      = Color(0xFFFF6B35);
  static const white       = Color(0xFFFFFFFF);
  static const gray        = Color(0xFFA1A1AA);
  static const grayDim     = Color(0xFF71717A);
  static const border      = Color(0xFF27272A);
}

TextStyle _mono({double size = 12, FontWeight weight = FontWeight.w600, Color color = _S.onSurface}) =>
    GoogleFonts.jetBrainsMono(fontSize: size, fontWeight: weight, color: color, letterSpacing: 0.1);

TextStyle _jakarta({double size = 16, FontWeight weight = FontWeight.w400, Color color = _S.onSurface, double? height}) =>
    GoogleFonts.plusJakartaSans(fontSize: size, fontWeight: weight, color: color, height: height);

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final firstName = user?.userMetadata?['first_name'] ?? 'there';
    final dashboardAsync = ref.watch(dashboardDataProvider);

    return Scaffold(
      backgroundColor: _S.bg,
      body: Stack(children: [
        const Positioned.fill(child: CinematicBackdrop()),
        dashboardAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: _S.primaryCont)),
        error: (e, _) => Center(child: Text('Error', style: _jakarta(color: Colors.red))),
        data: (data) {
          final title    = data['workout']['title'] as String;
          final duration = data['workout']['duration'] as int;
          final upcoming = data['upcoming_class'] as Map<String, dynamic>;
          return SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(context, firstName),
                  _scoreCard(context),
                  _sectionLabel("TODAY'S FOCUS", trailing: _pill('12')),
                  _focusCard(context, title, duration),
                  _sectionLabel('DAILY METRICS', trailing: _ghostBtn('EDIT', () {})),
                  _metricsRow(ref),
                  _weeklyProgress(),
                  _bottomCards(context, upcoming),
                  const SizedBox(height: 120),
                ],
              ),
            ),
          );
        },
      ),
      ]),
    );
  }

  // ─── HEADER ───────────────────────────────────────────────
  Widget _header(BuildContext context, String firstName) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.push('/profile'),
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _S.primaryCont, width: 2),
                boxShadow: [BoxShadow(color: _S.primaryCont.withValues(alpha: 0.3), blurRadius: 12)],
              ),
              child: ClipOval(
                child: Image.asset('assets/images/profile_avatar.png', fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(color: _S.primaryCont.withValues(alpha: 0.3),
                    child: const Icon(Icons.person, color: _S.white, size: 22))),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('GOOD MORNING', style: _mono(size: 10, color: _S.onSurfaceV)),
                Row(children: [
                  Text(firstName, style: _jakarta(size: 24, weight: FontWeight.w800, color: _S.white)),
                  const SizedBox(width: 6),
                  const Icon(Icons.bolt, color: _S.primaryCont, size: 22),
                ]),
              ],
            ),
          ),
          Stack(children: [
            IconButton(icon: const Icon(Icons.notifications_outlined, color: _S.white, size: 26), onPressed: () {}),
            Positioned(right: 8, top: 8,
              child: Container(width: 9, height: 9,
                decoration: BoxDecoration(color: _S.primaryCont, shape: BoxShape.circle,
                  border: Border.all(color: _S.bg, width: 1.5)))),
          ]),
        ],
      ),
    );
  }

  // ─── SECTION LABEL ────────────────────────────────────────
  Widget _sectionLabel(String label, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: _mono(size: 11, color: _S.gray)),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _pill(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: _S.card, borderRadius: BorderRadius.circular(999),
      border: Border.all(color: _S.border)),
    child: Text(text, style: _mono(size: 10, color: _S.onSurfaceV)),
  );

  Widget _ghostBtn(String text, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Text(text, style: _mono(size: 11, color: _S.primaryCont)),
  );

  // ─── SCORE CARD ───────────────────────────────────────────
  Widget _scoreCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _S.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _S.border),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: _S.cardHigh, borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _S.outlineVar)),
                child: Text('ELITE WEEK', style: _mono(size: 10, color: _S.primary)),
              ),
              const SizedBox(height: 12),
              Text("You're killing it!", style: _jakarta(size: 20, weight: FontWeight.w700, color: _S.white)),
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.trending_up, color: _S.tertiary, size: 16),
                const SizedBox(width: 6),
                RichText(text: TextSpan(children: [
                  TextSpan(text: '4 points', style: _jakarta(size: 13, weight: FontWeight.w700, color: _S.tertiary)),
                  TextSpan(text: ' from last week', style: _jakarta(size: 13, color: _S.gray)),
                ])),
              ]),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => context.push('/progress'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: _S.cardHigh, borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _S.outlineVar)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('View Insights', style: _jakarta(size: 13, weight: FontWeight.w600, color: _S.white)),
                    const SizedBox(width: 8),
                    const Icon(Icons.bar_chart, color: _S.primaryCont, size: 16),
                  ]),
                ),
              ),
            ]),
          ),
          const SizedBox(width: 16),
          // Score Ring
          SizedBox(width: 100, height: 100,
            child: Stack(alignment: Alignment.center, children: [
              CustomPaint(size: const Size(100, 100), painter: _RingPainter()),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text('87', style: _jakarta(size: 32, weight: FontWeight.w800, color: _S.white, height: 1.0)),
                Text('12 CIRCLE', style: _mono(size: 6, color: _S.onSurfaceV)),
                Text('SCORE™', style: _mono(size: 7, weight: FontWeight.w700, color: _S.primaryCont)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  // ─── FOCUS CARD ───────────────────────────────────────────
  Widget _focusCard(BuildContext context, String title, int duration) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: () => context.push('/workout-detail'),
        child: Container(
          height: 200,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: _S.card),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(children: [
              // Hero image
              Positioned.fill(
                child: Image.asset('assets/images/workout_hero.png',
                  fit: BoxFit.cover, alignment: const Alignment(0.2, -0.3),
                  errorBuilder: (_, __, ___) => Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF1a0040), Color(0xFF0D0020)],
                        begin: Alignment.topLeft, end: Alignment.bottomRight))))),
              // Dark overlay left side
              Positioned.fill(child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0A0A0B), Color(0xCC0A0A0B), Color(0x550A0A0B), Colors.transparent],
                    stops: [0.0, 0.35, 0.55, 0.80],
                    begin: Alignment.centerLeft, end: Alignment.centerRight)))),
              // Content
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: _jakarta(size: 26, weight: FontWeight.w800, color: _S.white, height: 1.1)),
                  const SizedBox(height: 10),
                  Row(children: [
                    const Icon(Icons.access_time_outlined, color: _S.gray, size: 13),
                    const SizedBox(width: 4),
                    Text('$duration MIN', style: _mono(size: 11, color: _S.gray)),
                    const SizedBox(width: 12),
                    Container(width: 1, height: 10, color: _S.outlineVar),
                    const SizedBox(width: 12),
                    const Icon(Icons.fitness_center, color: _S.primaryCont, size: 12),
                    const SizedBox(width: 4),
                    Text('5 EXERCISES', style: _mono(size: 11, color: _S.gray)),
                  ]),
                  const Spacer(),
                  // Button - pill with gradient, partial width
                  Container(
                    width: 200,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFB76DFF), Color(0xFF6900B3)]),
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [BoxShadow(
                        color: _S.primaryCont.withValues(alpha: 0.35),
                        blurRadius: 20, offset: const Offset(0, 4))]),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Start Workout', style: _jakarta(size: 14, weight: FontWeight.w700, color: _S.white)),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right, color: _S.white, size: 20),
                      ]),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ─── DAILY METRICS ────────────────────────────────────────
  Widget _metricsRow(WidgetRef ref) {
    final water = ref.watch(waterIntakeProvider);
    final steps = ref.watch(stepsProvider);

    final items = [
      _M('STEPS',   steps == null ? '—' : '$steps', '', ' of 10k', (steps ?? 0)/10000.0, _S.primaryCont, Icons.bolt),
      _M('WATER',   '$water/8', '50%', '',         water/8.0,    _S.secondary,   Icons.water_drop),
      _M('PROTEIN', '85g',      '71%', ' of goal', 0.71,         _S.primary,     Icons.restaurant_outlined),
      _M('SLEEP',   '7.4h',     'Good','',          0.92,         Color(0xFFfbbf24), Icons.bedtime_outlined),
    ];

    return Column(children: [
      SizedBox(
        height: 160,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: items.length,
          itemBuilder: (ctx, i) {
            final m = items[i];
            return Container(
              width: 120,
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _S.card, borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _S.border)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(width: 56, height: 56,
                    child: Stack(alignment: Alignment.center, children: [
                      CustomPaint(size: const Size(56, 56),
                        painter: _MiniRing(m.progress.clamp(0.0,1.0), m.color)),
                      Icon(m.icon, color: m.color, size: 22),
                    ])),
                  const SizedBox(height: 10),
                  Text(m.label, style: _mono(size: 9, color: _S.grayDim)),
                  const SizedBox(height: 3),
                  Text(m.value, style: _jakarta(size: 18, weight: FontWeight.w800, color: _S.white)),
                  RichText(text: TextSpan(children: [
                    TextSpan(text: m.hi, style: _mono(size: 9, color: m.color, weight: FontWeight.w600)),
                    TextSpan(text: m.suffix, style: _mono(size: 9, color: _S.grayDim)),
                  ])),
                ],
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 10),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(width: 6, height: 6, decoration: const BoxDecoration(color: _S.primaryCont, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Container(width: 6, height: 6, decoration: BoxDecoration(color: _S.border, shape: BoxShape.circle)),
      ]),
    ]);
  }

  // ─── WEEKLY PROGRESS ──────────────────────────────────────
  Widget _weeklyProgress() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _S.card, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _S.border)),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text("THIS WEEK'S PROGRESS", style: _mono(size: 10, color: _S.grayDim)),
            const Icon(Icons.chevron_right, color: _S.grayDim, size: 16),
          ]),
          const SizedBox(height: 20),
          // 2x2 grid layout like Stitch design
          Row(children: [
            _weekItem(Icons.fitness_center, 'Workouts', '4', '/5', _S.primaryCont, 0.8),
            const SizedBox(width: 16),
            _weekItem(Icons.restaurant_outlined, 'Nutrition', '92%', '', _S.primaryCont, 0.92),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            _weekItem(Icons.local_fire_department, 'Day Streak', '8', '', _S.orange, 1.0),
            const SizedBox(width: 16),
            _weekItem(Icons.trending_down_rounded, 'Weight', '-2.1lb', '', _S.tertiary, 0.6),
          ]),
        ]),
      ),
    );
  }

  Widget _weekItem(IconData icon, String label, String val, String suffix, Color color, double progress) {
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(label, style: _mono(size: 10, color: _S.gray)),
        ]),
        const SizedBox(height: 6),
        RichText(text: TextSpan(children: [
          TextSpan(text: val, style: _jakarta(size: 22, weight: FontWeight.w800, color: _S.white, height: 1.0)),
          if (suffix.isNotEmpty)
            TextSpan(text: suffix, style: _jakarta(size: 13, color: _S.grayDim)),
        ])),
        const SizedBox(height: 8),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: progress),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOut,
          builder: (_, val, __) => ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: val,
              backgroundColor: _S.cardHigh,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 4,
            ),
          ),
        ),
      ]),
    );
  }

  // ─── BOTTOM CARDS ─────────────────────────────────────────
  Widget _bottomCards(BuildContext context, Map<String, dynamic> upcoming) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(children: [
        // Next Event
        Expanded(
          child: GestureDetector(
            onTap: () => context.push('/classes'),
            child: Container(
              height: 170,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: _S.card, border: Border.all(color: _S.border)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(children: [
                  Positioned.fill(child: Image.asset(
                    'assets/images/recharge_event_bg.png', fit: BoxFit.cover,
                    opacity: const AlwaysStoppedAnimation(0.35),
                    errorBuilder: (_, __, ___) => Container(color: _S.card))),
                  Positioned.fill(child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [_S.card, _S.card.withValues(alpha: 0.4)],
                        begin: Alignment.bottomCenter, end: Alignment.topCenter)))),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('NEXT EVENT', style: _mono(size: 9, color: _S.gray)),
                      const SizedBox(height: 4),
                      Text('RECHARGE', style: _jakarta(size: 18, weight: FontWeight.w900, color: _S.white)),
                      Text('JULY 4, 2025', style: _mono(size: 9, color: _S.onSurfaceV)),
                      Row(children: [
                        Icon(Icons.location_on, color: _S.primaryCont, size: 10),
                        Text(' Lake Nona, FL', style: _mono(size: 9, color: _S.primaryCont)),
                      ]),
                      const Spacer(),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: _S.outlineVar)),
                        child: Text('Register Now',
                          textAlign: TextAlign.center,
                          style: _jakarta(size: 11, weight: FontWeight.w600, color: _S.white)),
                      ),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Community
        Expanded(
          child: GestureDetector(
            onTap: () => context.push('/community'),
            child: Container(
              height: 170,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _S.card, borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _S.border)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('COMMUNITY', style: _mono(size: 9, color: _S.gray)),
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: _S.primaryCont.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _S.outlineVar)),
                    child: const Icon(Icons.chat_bubble_outline, color: _S.primaryCont, size: 16)),
                ]),
                const SizedBox(height: 8),
                Text('24', style: _jakarta(size: 32, weight: FontWeight.w900, color: _S.white, height: 1.0)),
                Text('Members Active', style: _mono(size: 9, color: _S.gray)),
                const SizedBox(height: 10),
                // Avatars
                SizedBox(height: 26,
                  child: Stack(children: [
                    _av(const Color(0xFF4EDEA3), 0),
                    _av(const Color(0xFFADC6FF), 18),
                    _av(const Color(0xFFFFD700), 36),
                    _av(const Color(0xFFDDB7FF), 54),
                  ])),
                const Spacer(),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _S.outlineVar)),
                  child: Text('View Feed',
                    textAlign: TextAlign.center,
                    style: _jakarta(size: 11, weight: FontWeight.w600, color: _S.white)),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _av(Color c, double left) => Positioned(
    left: left,
    child: Container(width: 26, height: 26,
      decoration: BoxDecoration(shape: BoxShape.circle,
        color: c.withValues(alpha: 0.8),
        border: Border.all(color: _S.card, width: 2))));
}

// ─── DATA MODELS ──────────────────────────────────────────
class _M {
  final String label, value, hi, suffix;
  final double progress;
  final Color color;
  final IconData icon;
  const _M(this.label, this.value, this.hi, this.suffix, this.progress, this.color, this.icon);
}

// ─── PAINTERS ─────────────────────────────────────────────
class _RingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width/2, size.height/2);
    final r = size.width/2 - 9;
    // Track
    canvas.drawCircle(c, r, Paint()
      ..color = const Color(0xFF27272A)
      ..style = PaintingStyle.stroke..strokeWidth = 8);
    // Glow
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -1.57, 5.5, false, Paint()
      ..color = const Color(0xFFB76DFF).withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke..strokeWidth = 14
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    // Arc
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -1.57, 5.5, false, Paint()
      ..color = const Color(0xFFB76DFF)
      ..style = PaintingStyle.stroke..strokeWidth = 8
      ..strokeCap = StrokeCap.round);
  }
  @override bool shouldRepaint(_) => false;
}

class _MiniRing extends CustomPainter {
  final double progress;
  final Color color;
  const _MiniRing(this.progress, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width/2, size.height/2);
    final r = size.width/2 - 4;
    canvas.drawCircle(c, r, Paint()
      ..color = color.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke..strokeWidth = 3.5);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r),
      -1.57, progress * math.pi * 2, false, Paint()
        ..color = color..style = PaintingStyle.stroke
        ..strokeWidth = 3.5..strokeCap = StrokeCap.round);
  }
  @override bool shouldRepaint(covariant _MiniRing o) => o.progress != progress;
}
