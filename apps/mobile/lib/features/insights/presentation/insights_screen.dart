import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:math' as math;
import '../../../shared/widgets/app_scaffold.dart';
import '../domain/insights_provider.dart';

class _C {
  static const card      = Color(0xFF0E0B16);
  static const border    = Color(0xFF1A1020);
  static const brand     = Color(0xFFA855F7);
  static const primary   = Color(0xFFDDB7FF);
  static const cyan      = Color(0xFF6FD6FF);
  static const green     = Color(0xFF6FFBBE);
  static const amber     = Color(0xFFFFD479);
  static const onSurface = Color(0xFFE9E4F0);
  static const muted     = Color(0xFFA99FB8);
}

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(insightsProvider);
    return AppScaffold(
      body: SizedBox.expand(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator(color: _C.brand)),
          error: (e, _) => Center(
              child: Text('Could not load insights.',
                  textAlign: TextAlign.center, style: const TextStyle(color: _C.muted))),
          data: (d) => RefreshIndicator(
            color: _C.brand,
            backgroundColor: _C.card,
            onRefresh: () async => ref.invalidate(insightsProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              children: [
                _header(),
                const SizedBox(height: 20),
                _ScoreHero(data: d),
                const SizedBox(height: 14),
                _CategoryBreakdown(data: d),
                const SizedBox(height: 14),
                _TrendCard(last7: d.last7),
                const SizedBox(height: 14),
                _ReadinessRow(data: d),
                const SizedBox(height: 14),
                _deepBtn(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(width: 6, height: 6, decoration: const BoxDecoration(
                shape: BoxShape.circle, color: _C.green)),
            const SizedBox(width: 8),
            const Text('PERFORMANCE',
                style: TextStyle(color: _C.green, fontSize: 11,
                    fontWeight: FontWeight.w800, letterSpacing: 2)),
          ]),
          const SizedBox(height: 6),
          const Text('Your Insights',
              style: TextStyle(color: _C.onSurface, fontSize: 30,
                  fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          const SizedBox(height: 2),
          const Text('Real numbers from your 12 Circle activity.',
              style: TextStyle(color: _C.muted, fontSize: 13)),
        ],
      );

  Widget _deepBtn(BuildContext context) => GestureDetector(
        onTap: () => context.go('/progress'),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 15),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_C.brand, Color(0xFF6D28D9)]),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: _C.brand.withValues(alpha: 0.35), blurRadius: 16)],
          ),
          child: const Text('View Full Progress',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
        ),
      );
}

class _Box extends StatelessWidget {
  final Widget child;
  final Color? glow;
  const _Box({required this.child, this.glow});
  @override
  Widget build(BuildContext ctx) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [(glow ?? _C.brand).withValues(alpha: 0.10), _C.card]),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: (glow ?? _C.border).withValues(alpha: glow != null ? 0.25 : 1)),
        ),
        child: child,
      );
}

class _ScoreHero extends StatelessWidget {
  final InsightsData data;
  const _ScoreHero({required this.data});
  @override
  Widget build(BuildContext context) {
    final up = data.trendPct >= 0;
    return _Box(
      glow: _C.brand,
      child: Row(children: [
        SizedBox(
          width: 128, height: 128,
          child: Stack(alignment: Alignment.center, children: [
            CustomPaint(size: const Size(128, 128), painter: _RingPainter(data.todayScore / 100)),
            Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('TODAY', style: TextStyle(color: _C.muted, fontSize: 10,
                  fontWeight: FontWeight.w700, letterSpacing: 1.5)),
              const SizedBox(height: 2),
              Text('${data.todayScore}',
                  style: const TextStyle(color: _C.onSurface, fontSize: 38, fontWeight: FontWeight.w900)),
              Text('${up ? '▲' : '▼'} ${data.trendPct.abs().toStringAsFixed(0)}%',
                  style: TextStyle(color: up ? _C.green : _C.amber, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ]),
        ),
        const SizedBox(width: 18),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('12 Circle Score', style: TextStyle(color: _C.primary, fontSize: 13,
              fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          _stat('7-day average', data.weekAvg.toStringAsFixed(0), _C.cyan),
          const SizedBox(height: 10),
          _stat('Workouts this week', '${data.workoutsThisWeek}', _C.green),
          const SizedBox(height: 10),
          _stat('vs. last 7 days', '${up ? '+' : ''}${data.trendPct.toStringAsFixed(0)}%',
              up ? _C.green : _C.amber),
        ])),
      ]),
    );
  }

  Widget _stat(String label, String value, Color color) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: _C.muted, fontSize: 12)),
          Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w800)),
        ],
      );
}

class _CategoryBreakdown extends StatelessWidget {
  final InsightsData data;
  const _CategoryBreakdown({required this.data});
  @override
  Widget build(BuildContext context) {
    final cats = [
      ('Workout', data.workoutPts, 30, _C.brand),
      ('Nutrition', data.nutritionPts, 30, _C.green),
      ('Habits', data.habitsPts, 20, _C.cyan),
      ('Check-in', data.checkinPts, 10, _C.primary),
      ('Community', data.communityPts, 10, _C.amber),
    ];
    return _Box(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("Today's Breakdown",
            style: TextStyle(color: _C.onSurface, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        ...cats.map((c) {
          final (label, pts, max, color) = c;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(label, style: const TextStyle(color: _C.muted, fontSize: 13)),
                Text('$pts / $max',
                    style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: max == 0 ? 0 : pts / max,
                  backgroundColor: _C.border,
                  valueColor: AlwaysStoppedAnimation(color),
                  minHeight: 6),
              ),
            ]),
          );
        }),
      ]),
    );
  }
}

class _TrendCard extends StatelessWidget {
  final List<int> last7;
  const _TrendCard({required this.last7});
  @override
  Widget build(BuildContext context) {
    return _Box(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('7-Day Trend',
            style: TextStyle(color: _C.onSurface, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        SizedBox(
          height: 110,
          child: last7.isEmpty
              ? const Center(child: Text('No score history yet — log activity to see your trend.',
                  textAlign: TextAlign.center, style: TextStyle(color: _C.muted, fontSize: 12)))
              : CustomPaint(size: Size.infinite, painter: _TrendPainter(last7)),
        ),
      ]),
    );
  }
}

class _ReadinessRow extends StatelessWidget {
  final InsightsData data;
  const _ReadinessRow({required this.data});
  @override
  Widget build(BuildContext context) {
    if (data.lastCheckin == null) {
      return _Box(
        child: Row(children: [
          const Icon(Icons.favorite_border_rounded, color: _C.muted, size: 22),
          const SizedBox(width: 12),
          const Expanded(child: Text('Submit a weekly check-in to see readiness metrics here.',
              style: TextStyle(color: _C.muted, fontSize: 13))),
        ]),
      );
    }
    return Row(children: [
      Expanded(child: _metric('Energy', data.energy != null ? '${data.energy}/5' : '—', Icons.bolt_rounded, _C.amber)),
      const SizedBox(width: 12),
      Expanded(child: _metric('Sleep', data.sleepHours != null ? '${data.sleepHours!.toStringAsFixed(1)}h' : '—', Icons.bedtime_rounded, _C.cyan)),
      const SizedBox(width: 12),
      Expanded(child: _metric('Stress', data.stress != null ? '${data.stress}/5' : '—', Icons.spa_rounded, _C.green)),
    ]);
  }

  Widget _metric(String label, String value, IconData icon, Color color) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.12), _C.card]),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800)),
          Text(label, style: const TextStyle(color: _C.muted, fontSize: 11)),
        ]),
      );
}

class _RingPainter extends CustomPainter {
  final double progress;
  const _RingPainter(this.progress);
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 9;
    canvas.drawCircle(c, r, Paint()..color = _C.border..strokeWidth = 9..style = PaintingStyle.stroke);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2,
        2 * math.pi * progress.clamp(0, 1), false,
        Paint()
          ..shader = const LinearGradient(colors: [Color(0xFF6FFBBE), Color(0xFFA855F7), Color(0xFFDDB7FF)])
              .createShader(Rect.fromCircle(center: c, radius: r))
          ..strokeWidth = 9..style = PaintingStyle.stroke..strokeCap = StrokeCap.round);
  }
  @override bool shouldRepaint(covariant _RingPainter o) => o.progress != progress;
}

class _TrendPainter extends CustomPainter {
  final List<int> values;
  const _TrendPainter(this.values);
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final n = values.length;
    if (n == 0) return;
    final maxV = 100.0;
    final dx = n == 1 ? 0.0 : w / (n - 1);
    final pts = <Offset>[];
    for (var i = 0; i < n; i++) {
      final x = n == 1 ? w / 2 : i * dx;
      final y = h - (values[i] / maxV).clamp(0, 1) * (h - 8) - 4;
      pts.add(Offset(x, y));
    }
    // area fill
    final fill = Path()..moveTo(pts.first.dx, h);
    for (final p in pts) {
      fill.lineTo(p.dx, p.dy);
    }
    fill..lineTo(pts.last.dx, h)..close();
    canvas.drawPath(fill, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [_C.brand.withValues(alpha: 0.35), _C.brand.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(0, 0, w, h)));
    // line
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 0; i < pts.length - 1; i++) {
      final cp1 = Offset((pts[i].dx + pts[i + 1].dx) / 2, pts[i].dy);
      final cp2 = Offset((pts[i].dx + pts[i + 1].dx) / 2, pts[i + 1].dy);
      line.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, pts[i + 1].dx, pts[i + 1].dy);
    }
    canvas.drawPath(line, Paint()
      ..color = _C.primary..strokeWidth = 2.5..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1));
    for (final p in pts) {
      canvas.drawCircle(p, 3, Paint()..color = _C.primary);
    }
  }
  @override bool shouldRepaint(covariant _TrendPainter o) => o.values != values;
}
