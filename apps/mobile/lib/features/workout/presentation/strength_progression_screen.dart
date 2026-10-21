import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../domain/workout_provider.dart';
import '../../../core/widgets/named_icon_button.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
const _bg      = Color(0xFF030303);
const _card    = Color(0xFF0E0B16);
const _border  = Color(0xFF1A1020);
const _brand   = Color(0xFFA855F7);
const _primary = Color(0xFFDDB7FF);
const _white   = Colors.white;
const _muted   = Color(0xFFCFC2D6);
const _teal    = Color(0xFF6FFBBE);
const _amber   = Color(0xFFFFD580);

class StrengthProgressionScreen extends ConsumerStatefulWidget {
  const StrengthProgressionScreen({super.key});
  @override
  ConsumerState<StrengthProgressionScreen> createState() => _StrengthProgressionScreenState();
}

class _StrengthProgressionScreenState extends ConsumerState<StrengthProgressionScreen> {
  String? _selectedExercise;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final exerciseNames = ref.watch(loggedExerciseNamesProvider);

    return Scaffold(
      backgroundColor: _bg,
      body: Column(children: [
        // ── Header ──────────────────────────────────────────────────────────
        Container(
          padding: EdgeInsets.only(top: topPad + 12, left: 16, right: 16, bottom: 16),
          decoration: const BoxDecoration(color: _card, border: Border(bottom: BorderSide(color: _border))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              NamedIconButton(
                label: 'Back',
                onTap: () => context.pop(),
                child: const Icon(Icons.arrow_back_ios_new_rounded, color: _primary, size: 20)),
              const SizedBox(width: 14),
              const Text('Strength Progression',
                style: TextStyle(color: _white, fontSize: 20, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 4),
            Text('Track your personal records over time',
              style: TextStyle(color: _muted.withValues(alpha: 0.6), fontSize: 12)),
          ])),

        Expanded(child: exerciseNames.when(
          loading: () => const Center(child: CircularProgressIndicator(color: _brand)),
          error: (_, __) => const Center(child: Text('Failed to load exercises', style: TextStyle(color: _muted))),
          data: (names) {
            if (names.isEmpty) {
              return const _EmptyState();
            }
            // Auto-select first exercise
            _selectedExercise ??= names.first;
            return Column(children: [
              // ── Exercise picker ─────────────────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: const BoxDecoration(color: _card, border: Border(bottom: BorderSide(color: _border))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('EXERCISE', style: TextStyle(color: _muted, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: _border)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedExercise,
                        isExpanded: true,
                        dropdownColor: _card,
                        style: const TextStyle(color: _white, fontSize: 14),
                        items: names.map((n) => DropdownMenuItem(value: n, child: Text(n))).toList(),
                        onChanged: (v) => setState(() => _selectedExercise = v),
                      ))),
                ])),

              // ── Chart ────────────────────────────────────────────────────
              Expanded(
                child: _selectedExercise == null
                    ? const SizedBox()
                    : _ProgressionChart(exerciseName: _selectedExercise!)),
            ]);
          },
        )),
      ]),
    );
  }
}

// ── Chart widget ──────────────────────────────────────────────────────────────
class _ProgressionChart extends ConsumerWidget {
  final String exerciseName;
  const _ProgressionChart({required this.exerciseName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progression = ref.watch(exerciseProgressionProvider(exerciseName));
    return progression.when(
      loading: () => const Center(child: CircularProgressIndicator(color: _brand)),
      error: (_, __) => const Center(child: Text('No data yet', style: TextStyle(color: _muted))),
      data: (data) {
        if (data.isEmpty) {
          return const _EmptyState(message: 'No sets logged yet for this exercise.\nComplete a workout to see progress.');
        }
        // Sort by date
        final sorted = List<Map<String, dynamic>>.from(data)
          ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));

        final maxWeight = sorted.map((d) => (d['max_weight'] as num?)?.toDouble() ?? 0.0).reduce(max);
        final totalVols  = sorted.map((d) => (d['total_volume'] as num?)?.toDouble() ?? 0.0).toList();
        final maxVol     = totalVols.isEmpty ? 1.0 : totalVols.reduce(max);

        // Summary stats
        final latestWeight = (sorted.last['max_weight'] as num?)?.toDouble() ?? 0;
        final firstWeight  = (sorted.first['max_weight'] as num?)?.toDouble() ?? 0;
        final gain = latestWeight - firstWeight;
        final totalSets = sorted.fold<int>(0, (s, d) => s + ((d['sets_count'] as int?) ?? 0));

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── PR stats row ───────────────────────────────────────────────
            Row(children: [
              _StatCard(label: 'Current PR', value: '${latestWeight.toStringAsFixed(1)}kg', color: _brand),
              const SizedBox(width: 10),
              _StatCard(label: 'Total Gain', value: '${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)}kg', color: gain >= 0 ? _teal : _muted),
              const SizedBox(width: 10),
              _StatCard(label: 'Total Sets', value: '$totalSets', color: _amber),
            ]),
            const SizedBox(height: 20),

            // ── Weight chart ───────────────────────────────────────────────
            const _ChartLabel(text: 'MAX WEIGHT (kg)'),
            const SizedBox(height: 8),
            Container(
              height: 200,
              padding: const EdgeInsets.fromLTRB(8, 12, 12, 8),
              decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16), border: Border.all(color: _border)),
              child: CustomPaint(
                painter: _LineChartPainter(
                  values: sorted.map((d) => (d['max_weight'] as num?)?.toDouble() ?? 0.0).toList(),
                  maxValue: maxWeight > 0 ? maxWeight : 1,
                  lineColor: _brand,
                  fillColor: _brand.withValues(alpha: 0.12),
                ),
                size: Size.infinite)),
            const SizedBox(height: 4),
            _DateLabels(points: sorted),
            const SizedBox(height: 24),

            // ── Volume chart ───────────────────────────────────────────────
            const _ChartLabel(text: 'TOTAL VOLUME (kg × reps)'),
            const SizedBox(height: 8),
            Container(
              height: 160,
              padding: const EdgeInsets.fromLTRB(8, 12, 12, 8),
              decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16), border: Border.all(color: _border)),
              child: CustomPaint(
                painter: _LineChartPainter(
                  values: totalVols,
                  maxValue: maxVol > 0 ? maxVol : 1,
                  lineColor: _teal,
                  fillColor: _teal.withValues(alpha: 0.10),
                ),
                size: Size.infinite)),
            const SizedBox(height: 4),
            _DateLabels(points: sorted),
            const SizedBox(height: 24),

            // ── Data table ────────────────────────────────────────────────
            const _ChartLabel(text: 'SESSION HISTORY'),
            const SizedBox(height: 8),
            ...sorted.reversed.map((d) {
              final date   = (d['date'] as String).substring(0, 10);
              final weight = (d['max_weight'] as num?)?.toDouble() ?? 0;
              final vol    = (d['total_volume'] as num?)?.toDouble() ?? 0;
              final sets   = (d['sets_count'] as int?) ?? 0;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12), border: Border.all(color: _border)),
                child: Row(children: [
                  Expanded(child: Text(date, style: const TextStyle(color: _muted, fontSize: 12))),
                  _Pill(label: '${weight.toStringAsFixed(1)}kg', color: _primary),
                  const SizedBox(width: 8),
                  _Pill(label: 'Vol ${vol.toStringAsFixed(0)}', color: _teal),
                  const SizedBox(width: 8),
                  _Pill(label: '$sets sets', color: _amber),
                ]));
            }),
          ],
        );
      },
    );
  }
}

// ── Custom line-chart painter ─────────────────────────────────────────────────
class _LineChartPainter extends CustomPainter {
  final List<double> values;
  final double maxValue;
  final Color lineColor;
  final Color fillColor;

  _LineChartPainter({
    required this.values,
    required this.maxValue,
    required this.lineColor,
    required this.fillColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final w = size.width;
    final h = size.height;
    final n = values.length;

    // Y-axis guide lines
    final guidePaint = Paint()
      ..color = const Color(0xFF1A1020)
      ..strokeWidth = 1;
    for (int i = 0; i <= 4; i++) {
      final y = h - (h * i / 4);
      canvas.drawLine(Offset(0, y), Offset(w, y), guidePaint);
    }

    Offset pt(int i) {
      final x = n == 1 ? w / 2 : (i / (n - 1)) * w;
      final y = h - (values[i] / maxValue) * h;
      return Offset(x, y.clamp(0, h));
    }

    // Fill path
    final fillPath = Path();
    fillPath.moveTo(pt(0).dx, h);
    for (int i = 0; i < n; i++) {
      fillPath.lineTo(pt(i).dx, pt(i).dy);
    }
    fillPath.lineTo(pt(n - 1).dx, h);
    fillPath.close();
    canvas.drawPath(fillPath, Paint()..color = fillColor);

    // Line
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final linePath = Path();
    linePath.moveTo(pt(0).dx, pt(0).dy);
    for (int i = 1; i < n; i++) {
      // Smooth bezier curve
      final prev = pt(i - 1);
      final curr = pt(i);
      final cx = (prev.dx + curr.dx) / 2;
      linePath.cubicTo(cx, prev.dy, cx, curr.dy, curr.dx, curr.dy);
    }
    canvas.drawPath(linePath, linePaint);

    // Dot on each data point
    final dotPaint = Paint()..color = lineColor;
    final dotBg    = Paint()..color = _bg;
    for (int i = 0; i < n; i++) {
      final dotPt = pt(i);
      canvas.drawCircle(dotPt, 5, dotBg);
      canvas.drawCircle(dotPt, 4, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) =>
      old.values != values || old.maxValue != maxValue;
}

// ── Supporting widgets ────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StatCard({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14), border: Border.all(color: _border)),
      child: Column(children: [
        Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: _muted.withValues(alpha: 0.6), fontSize: 10), textAlign: TextAlign.center),
      ])));
  }
}

class _ChartLabel extends StatelessWidget {
  final String text;
  const _ChartLabel({required this.text});
  @override
  Widget build(BuildContext context) =>
    Text(text, style: const TextStyle(color: _muted, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5));
}

class _DateLabels extends StatelessWidget {
  final List<Map<String, dynamic>> points;
  const _DateLabels({required this.points});
  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox();
    final step = max(1, (points.length / 4).ceil());
    final labels = <String>[];
    for (int i = 0; i < points.length; i += step) {
      final raw = points[i]['date'] as String? ?? '';
      labels.add(raw.length >= 10 ? raw.substring(5, 10) : raw);
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: labels.map((l) => Text(l, style: TextStyle(color: _muted.withValues(alpha: 0.45), fontSize: 9))).toList());
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  const _Pill({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(999)),
    child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)));
}

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({this.message = 'Complete workouts to see your strength progression over time.'});
  @override
  Widget build(BuildContext context) {
    return Center(child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.show_chart_rounded, color: _brand, size: 48),
        const SizedBox(height: 16),
        const Text('No data yet', style: TextStyle(color: _white, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(message, style: TextStyle(color: _muted.withValues(alpha: 0.6), fontSize: 13), textAlign: TextAlign.center),
      ])));
  }
}
