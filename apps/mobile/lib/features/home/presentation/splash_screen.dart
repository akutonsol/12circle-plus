import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Splash-standalone — the single onboarding landing. Cinematic cross-cutting
/// hero photos, smoke + drifting embers, a spinning-ring 12 Circle brand mark, a
/// cycling headline (Train like you mean it → Push past your limits → Stronger
/// every rep), and a glowing slide-free Get Started CTA into the create-account
/// flow. "Already a member? Sign In" → login.
///
/// Get Started now hands off to `/onboarding` (the locked FIT-006 Welcome frame),
/// which owns the Create-account / Sign-in choice — the router's own comment has
/// always said the splash "hands off to /onboarding itself". Welcome had no way in
/// before (OD-31). The Sign In link is kept as a shortcut for returning members.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

const _purple      = Color(0xFF8A3DF0);
const _purpleLight = Color(0xFFB06BFF);
const _pink        = Color(0xFFFF4D8D);

const _heroes = [
  ('assets/images/splash_dc_0.jpg', Alignment(0.56, -0.56)),
  ('assets/images/splash_dc_1.jpg', Alignment(0.0, 0.0)),
  ('assets/images/dumbell.png', Alignment(0.28, -0.08)),
];
const _phrases = ['Train like\nyou mean it', 'Push past\nyour limits', 'Stronger\nevery rep'];

// Piecewise-linear keyframe interpolation (t in 0..1).
double _pw(double t, List<List<double>> s) {
  if (t <= s.first[0]) return s.first[1];
  if (t >= s.last[0]) return s.last[1];
  for (var i = 0; i < s.length - 1; i++) {
    if (t >= s[i][0] && t <= s[i + 1][0]) {
      final f = (t - s[i][0]) / (s[i + 1][0] - s[i][0]);
      return s[i][1] + (s[i + 1][1] - s[i][1]) * f;
    }
  }
  return s.last[1];
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _cycle; // hero + headline 9s loop
  late final AnimationController _amb;   // smoke / embers / sweep
  late final AnimationController _spin;  // brand rings
  late final AnimationController _cta;   // CTA glow + shine
  late final AnimationController _intro; // staggered fade-up entrance

  @override
  void initState() {
    super.initState();
    _cycle = AnimationController(vsync: this, duration: const Duration(seconds: 9))..repeat();
    _amb   = AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat();
    _spin  = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
    _cta   = AnimationController(vsync: this, duration: const Duration(milliseconds: 4500))..repeat();
    _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..forward();
  }

  @override
  void dispose() {
    for (final c in [_cycle, _amb, _spin, _cta, _intro]) {
      c.dispose();
    }
    super.dispose();
  }

  double _heroOpacity(double p) => _pw(p, [[0, 0], [0.012, 1], [0.34, 1], [0.355, 0], [1, 0]]);

  Animation<double> _fade(double begin) =>
      CurvedAnimation(parent: _intro, curve: Interval(begin, (begin + 0.45).clamp(0.0, 1.0), curve: Curves.easeOut));

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0B),
      body: Stack(fit: StackFit.expand, children: [
        // ── Cross-cutting hero photos ──
        AnimatedBuilder(
          animation: _cycle,
          builder: (_, __) => Stack(fit: StackFit.expand, children: [
            const ColoredBox(color: Color(0xFF0A0A0B)),
            for (var i = 0; i < _heroes.length; i++)
              Opacity(
                opacity: _heroOpacity((_cycle.value + i / 3) % 1.0),
                child: Image.asset(_heroes[i].$1, fit: BoxFit.cover, alignment: _heroes[i].$2, gaplessPlayback: true),
              ),
          ]),
        ),
        // Radial vignette so the photo blends into the dark.
        const DecoratedBox(decoration: BoxDecoration(
          gradient: RadialGradient(center: Alignment(0.32, -0.34), radius: 1.1,
            colors: [Colors.transparent, Color(0x47060308), Color(0xD104020A)], stops: [0.44, 0.74, 0.94]))),
        // Vertical + side darkening.
        const DecoratedBox(decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0x14080410), Color(0x00080410), Color(0x2E06030E), Color(0xF504020A)],
            stops: [0.0, 0.28, 0.56, 1.0]))),
        const DecoratedBox(decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight,
            colors: [Color(0x9E06030E), Color(0x0D06030E), Colors.transparent], stops: [0.0, 0.38, 0.62]))),

        // ── Ambient: smoke, energy glow, embers ──
        AnimatedBuilder(animation: _amb, builder: (_, __) => _ambient(size)),

        // ── Content ──
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(30, 14, 30, 34),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // brand: spinning rings + 12 logo
              FadeTransition(opacity: _fade(0.0), child: SizedBox(
                width: 70, height: 70,
                child: AnimatedBuilder(animation: _spin, builder: (_, __) => Stack(alignment: Alignment.center, children: [
                  CustomPaint(size: const Size(70, 70), painter: _BrandRings(_spin.value)),
                  Padding(padding: const EdgeInsets.all(12),
                    child: Image.asset('assets/images/12circle-fab.png', fit: BoxFit.contain)),
                ])),
              )),
              const Spacer(),

              // eyebrow
              FadeTransition(opacity: _fade(0.18), child: const Text('WELCOME TO YOUR JOURNEY',
                style: TextStyle(color: Color(0xFFC9A6FF), fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 3))),
              const SizedBox(height: 12),

              // cycling headline
              SizedBox(height: 96, child: AnimatedBuilder(animation: _cycle, builder: (_, __) {
                return Stack(children: [
                  for (var i = 0; i < _phrases.length; i++) _flashLine(_phrases[i], (_cycle.value + i / 3) % 1.0),
                ]);
              })),
              const SizedBox(height: 16),

              // subtext
              FadeTransition(opacity: _fade(0.42), child: const Text(
                'Coaching, workouts, and progress tracking built to push you through all 12 weeks.',
                style: TextStyle(color: Color(0xFFD6CCE6), fontSize: 15, height: 1.5))),
              const SizedBox(height: 26),

              // Get Started CTA
              FadeTransition(opacity: _fade(0.55), child: _ctaButton(() => context.go('/onboarding'))),
              const SizedBox(height: 18),

              // Sign In
              FadeTransition(opacity: _fade(0.7), child: Center(child: GestureDetector(
                onTap: () => context.go('/login'),
                child: const Text.rich(TextSpan(children: [
                  TextSpan(text: 'Already a member?  ', style: TextStyle(color: Color(0xFFB6ABC8), fontSize: 14)),
                  TextSpan(text: 'Sign In', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                ])),
              ))),
            ]),
          ),
        ),

        // ── Periodic diagonal light sweep ──
        AnimatedBuilder(animation: _amb, builder: (ctx, __) {
          final p = (_amb.value * (12 / 7)) % 1.0; // ~7s sweep cadence
          final op = _pw(p, [[0, 0], [0.06, 0.45], [0.18, 0], [1, 0]]);
          return IgnorePointer(child: Transform.translate(
            offset: Offset((p * 4.6 - 1.8) * size.width, 0),
            child: Transform(transform: Matrix4.skewX(-0.28),
              child: Opacity(opacity: op, child: Container(width: size.width * 0.55,
                decoration: const BoxDecoration(gradient: LinearGradient(
                  colors: [Colors.transparent, Color(0x29DCBEFF), Colors.transparent])))))));
        }),

        // ── Pulsing purple edge glow (framePulse) — hugs all four edges ──
        AnimatedBuilder(animation: _cta, builder: (_, __) {
          final g = (math.sin(_cta.value * 2 * math.pi) + 1) / 2;
          return _edgePulse(g);
        }),
      ]),
    );
  }

  // ── Pulsing edge glow that fills every edge (top/bottom/left/right) ──
  Widget _edgePulse(double g) {
    Widget side(Alignment begin, Alignment end, {double? w, double? h}) => SizedBox(
      width: w, height: h,
      child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
        begin: begin, end: end,
        colors: [_purple.withValues(alpha: 0.20 + 0.18 * g), Colors.transparent],
        stops: const [0.0, 1.0]))));
    return IgnorePointer(child: Stack(fit: StackFit.expand, children: [
      Align(alignment: Alignment.topCenter,
        child: side(Alignment.topCenter, Alignment.bottomCenter, h: 110)),
      Align(alignment: Alignment.bottomCenter,
        child: side(Alignment.bottomCenter, Alignment.topCenter, h: 150)),
      Align(alignment: Alignment.centerLeft,
        child: side(Alignment.centerLeft, Alignment.centerRight, w: 84)),
      Align(alignment: Alignment.centerRight,
        child: side(Alignment.centerRight, Alignment.centerLeft, w: 84)),
      // crisp animated hairline right at the screen edge
      DecoratedBox(decoration: BoxDecoration(border: Border.all(
        color: _purpleLight.withValues(alpha: 0.20 + 0.16 * g), width: 1.4))),
    ]));
  }

  // ── Cycling headline line ──
  Widget _flashLine(String text, double p) {
    final op = _pw(p, [[0, 0], [0.03, 1], [0.30, 1], [0.33, 0], [1, 0]]);
    final ty = _pw(p, [[0, 14], [0.08, 0], [0.30, 0], [0.33, -8], [1, -8]]);
    final sc = _pw(p, [[0, 0.92], [0.08, 1.04], [0.12, 1], [1, 1]]);
    return Positioned(left: 0, top: 0, child: Opacity(opacity: op, child: Transform.translate(
      offset: Offset(0, ty), child: Transform.scale(scale: sc, alignment: Alignment.topLeft,
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 42, height: 0.98,
          fontWeight: FontWeight.w800, letterSpacing: -0.8))))));
  }

  // ── Get Started button with glow + shine ──
  Widget _ctaButton(VoidCallback onTap) => AnimatedBuilder(
    animation: _cta,
    builder: (_, __) {
      final glow = (math.sin(_cta.value * 2 * math.pi * 1.5) + 1) / 2;
      final shine = _pw(_cta.value, [[0, -1.6], [0.26, 2.8], [1, 2.8]]);
      return GestureDetector(
        onTap: onTap,
        child: Container(
          height: 56, width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(colors: [_purpleLight, _purple],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
            boxShadow: [BoxShadow(color: const Color(0xFFD36BFF).withValues(alpha: 0.3 + 0.4 * glow),
              blurRadius: 30 + 16 * glow, offset: const Offset(0, 12))]),
          child: ClipRRect(borderRadius: BorderRadius.circular(18), child: Stack(children: [
            const Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('Get Started', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
              SizedBox(width: 9),
              Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
            ])),
            Positioned(top: 0, bottom: 0, left: shine * 200,
              child: Transform(transform: Matrix4.skewX(-0.35), child: Container(width: 70,
                decoration: const BoxDecoration(gradient: LinearGradient(
                  colors: [Colors.transparent, Color(0x80FFFFFF), Colors.transparent]))))),
          ])),
        ),
      );
    },
  );

  // ── Smoke, energy glow, drifting embers ──
  Widget _ambient(Size size) {
    final t = _amb.value;
    Widget blob(Alignment a, double w, double h, Color c, double blur, double phase) {
      final s = (math.sin((t + phase) * 2 * math.pi) + 1) / 2;
      return Align(alignment: a, child: Transform.scale(scale: 1 + 0.18 * s,
        child: ImageFiltered(imageFilter: _blur(blur), child: Container(width: w, height: h,
          decoration: BoxDecoration(shape: BoxShape.circle,
            gradient: RadialGradient(colors: [c.withValues(alpha: c.a * (0.6 + 0.4 * s)), Colors.transparent], stops: const [0.0, 0.65]))))));
    }
    final beat = (math.sin(t * 2 * math.pi * 5) + 1) / 2;
    return IgnorePointer(child: Stack(children: [
      blob(const Alignment(-0.9, 1.0), size.width * 0.6, size.height * 0.55, const Color(0x66963CE6), 40, 0.0),
      blob(const Alignment(1.0, -0.55), size.width * 0.58, size.height * 0.5, const Color(0x52BE50FF), 46, 0.4),
      // energy glow behind athlete
      Align(alignment: const Alignment(0.85, -0.7), child: Opacity(opacity: 0.4 + 0.4 * beat,
        child: Transform.scale(scale: 1 + 0.14 * beat, child: ImageFiltered(imageFilter: _blur(34),
          child: Container(width: size.width * 0.54, height: size.height * 0.42,
            decoration: const BoxDecoration(shape: BoxShape.circle,
              gradient: RadialGradient(colors: [Color(0x73BE5AFF), Colors.transparent], stops: [0.0, 0.62]))))))),
      ..._embers(size),
    ]));
  }

  static ImageFilter _blur(double r) => ImageFilter.blur(sigmaX: r, sigmaY: r);

  List<Widget> _embers(Size size) {
    const spec = [(0.26, 4.0, 0.0), (0.40, 3.0, 0.3), (0.55, 5.0, 0.55), (0.68, 3.0, 0.15), (0.33, 4.0, 0.8)];
    final bottom = size.height * 0.32;
    return [
      for (final (x, sz, phase) in spec)
        Builder(builder: (_) {
          final p = (_amb.value + phase) % 1.0;
          final rise = _pw(p, [[0, 10], [1, -200]]);
          final op = _pw(p, [[0, 0], [0.12, 1], [0.78, 0.85], [1, 0]]);
          return Positioned(left: x * size.width, top: size.height - bottom + rise,
            child: Opacity(opacity: op, child: Container(width: sz, height: sz, decoration: BoxDecoration(
              shape: BoxShape.circle, color: const Color(0xFFE9C6FF),
              boxShadow: [BoxShadow(color: _purpleLight.withValues(alpha: 0.6), blurRadius: 8)]))));
        }),
    ];
  }
}

/// Brand rings — faint full circles + spinning purple/pink arcs.
class _BrandRings extends CustomPainter {
  final double t;
  _BrandRings(this.t);
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    const tau = 2 * math.pi;
    final rO = size.width * 0.48, rI = size.width * 0.36;
    canvas.drawCircle(c, rO, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = _purpleLight.withValues(alpha: 0.3));
    canvas.drawCircle(c, rI, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = _pink.withValues(alpha: 0.28));
    canvas.drawArc(Rect.fromCircle(center: c, radius: rO), t * tau, tau * 0.28, false,
      Paint()..style = PaintingStyle.stroke..strokeWidth = 2..strokeCap = StrokeCap.round..color = _purpleLight);
    canvas.drawArc(Rect.fromCircle(center: c, radius: rI), -t * tau * 1.3, tau * 0.28, false,
      Paint()..style = PaintingStyle.stroke..strokeWidth = 2..strokeCap = StrokeCap.round..color = _pink);
  }
  @override
  bool shouldRepaint(_BrandRings old) => old.t != t;
}
