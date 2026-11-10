// MIE Debugger — the Decision Intelligence Engine's window. Generate a workout
// for a context and inspect the full deterministic decision trace: which
// candidates were accepted/rejected, by which rule, and why. Everything shown is
// structured data recorded by generate_workout — no AI. Admin/content-manager.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/custom_exercise_service.dart';
import '../../auth/domain/auth_provider.dart';

const _bg     = Color(0xFF0A0A0B);
const _panel  = Color(0xFF14101E);
const _panel2 = Color(0xFF1B1526);
const _brand  = Color(0xFFB76DFF);
const _text   = Color(0xFFEDE7F3);
const _muted  = Color(0xFF9A93A6);
const _pass   = Color(0xFF10B981);
const _warn   = Color(0xFFF59E0B);
const _fail   = Color(0xFFEF4444);

class MieDebuggerScreen extends ConsumerStatefulWidget {
  const MieDebuggerScreen({super.key});
  @override
  ConsumerState<MieDebuggerScreen> createState() => _State();
}

class _State extends ConsumerState<MieDebuggerScreen> {
  final _svc = CustomExerciseService();
  String _goal = 'hypertrophy';
  int _recovery = 75;
  String _experience = 'intermediate';
  bool _busy = false;
  Map<String, dynamic>? _result;
  String? _error;
  String? _explanation;
  String _audience = 'client';
  bool _explaining = false;

  static const _goals = ['strength', 'hypertrophy', 'power', 'endurance', 'fat_loss'];

  Future<void> _generate() async {
    setState(() { _busy = true; _error = null; });
    final ctx = {
      // Copilot's module: the debugger shows what Copilot would decide (188).
      'module': 'workout_builder',
      'goal': _goal, 'recovery': _recovery, 'experience': _experience,
      'equipment': ['barbell', 'dumbbell', 'cable', 'bodyweight'], 'size': 5,
    };
    final r = await _svc.generateWorkout(ctx);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = r;
      _explanation = null; // new trace → clear prior narration
      if (r == null) _error = 'No result — apply migrations 085/087/088/089, then Rebuild graph + intelligence.';
    });
  }

  Future<void> _explain() async {
    final tid = _result?['trace_id']?.toString();
    if (tid == null) return;
    setState(() { _explaining = true; _explanation = null; });
    final text = await _svc.explainDecision(tid, audience: _audience);
    if (!mounted) return;
    setState(() {
      _explaining = false;
      _explanation = text ?? 'Explanation unavailable — set ANTHROPIC_API_KEY + deploy explain-decision.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(currentUserProfileProvider).valueOrNull?['role'];
    if (role != 'admin' && role != 'content_manager') {
      return const Scaffold(backgroundColor: _bg,
        body: Center(child: Text('Admins & content managers only.', style: TextStyle(color: _muted))));
    }
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(backgroundColor: _bg, foregroundColor: _text,
        title: const Text('MIE Debugger', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
        _contextCard(),
        const SizedBox(height: 14),
        if (_error != null) _banner(_error!),
        if (_result != null) ..._traceView(_result!),
      ]),
    );
  }

  Widget _banner(String msg) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: _panel2, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _warn.withValues(alpha: 0.4))),
    child: Row(children: [
      const Icon(Icons.build_circle_outlined, color: _warn, size: 16), const SizedBox(width: 8),
      Expanded(child: Text(msg, style: const TextStyle(color: _muted, fontSize: 12))),
    ]),
  );

  Widget _contextCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('CONTEXT', style: TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        const SizedBox(height: 10),
        const Text('Goal', style: TextStyle(color: _text, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final g in _goals) _chip(g, _goal == g, () => setState(() => _goal = g)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          const Text('Recovery', style: TextStyle(color: _text, fontSize: 12, fontWeight: FontWeight.w600)),
          Expanded(child: Slider(
            value: _recovery.toDouble(), min: 0, max: 100, divisions: 20, activeColor: _brand,
            label: '$_recovery', onChanged: (v) => setState(() => _recovery = v.round()))),
          Text('$_recovery', style: TextStyle(
              color: _recovery < 60 ? _warn : _pass, fontSize: 13, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 6),
        const Text('Experience', style: TextStyle(color: _text, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, children: [
          for (final e in ['beginner', 'intermediate', 'advanced'])
            _chip(e, _experience == e, () => setState(() => _experience = e)),
        ]),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: _busy ? null : _generate,
          child: Container(
            width: double.infinity, alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(color: _brand, borderRadius: BorderRadius.circular(12)),
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Generate & trace', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
          ),
        ),
      ]),
    );
  }

  Widget _chip(String label, bool sel, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: sel ? _brand : _panel2, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: sel ? _brand : _brand.withValues(alpha: 0.2))),
      child: Text(label.replaceAll('_', ' '),
          style: TextStyle(color: sel ? Colors.white : _text, fontSize: 12, fontWeight: FontWeight.w700)),
    ),
  );

  List<Widget> _traceView(Map<String, dynamic> r) {
    final trace = (r['trace'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final rules = (r['rules_triggered'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final warmup = (r['warmup'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final vol = (r['volume_factor'] as num?)?.toDouble() ?? 1.0;
    final tid = r['trace_id']?.toString();
    return [
      const SizedBox(height: 14),
      // Header: engine + volume + rules triggered.
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('DECISION TRACE',
                style: TextStyle(color: _brand, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
            const Spacer(),
            Text('engine 3.0.0', style: TextStyle(color: _muted, fontSize: 10, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 8),
          Text('Volume factor ${vol.toStringAsFixed(2)}${vol < 1 ? '  (recovery reduction)' : ''}',
              style: const TextStyle(color: _text, fontSize: 12)),
          if (tid != null) Text('trace #${tid.substring(0, 8)}',
              style: const TextStyle(color: _muted, fontSize: 10)),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final rule in rules)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: _warn.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(8)),
                child: Text(rule, style: const TextStyle(color: _warn, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
          ]),
        ]),
      ),
      const SizedBox(height: 16),
      _explanationCard(),
      const Text('CANDIDATES CONSIDERED',
          style: TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
      const SizedBox(height: 8),
      ...trace.map(_candidateRow),
      if (warmup.isNotEmpty) ...[
        const SizedBox(height: 16),
        const Text('WARM-UP (graph-derived)',
            style: TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final w in warmup)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: _panel2, borderRadius: BorderRadius.circular(8)),
              child: Text('${w['name']}  · ${w['type']}',
                  style: const TextStyle(color: _text, fontSize: 11.5)),
            ),
        ]),
      ],
    ];
  }

  // L4 Communication — narrate the trace (coach vs client), grounded in it.
  Widget _explanationCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _panel, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _brand.withValues(alpha: 0.25))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('AI EXPLANATION',
              style: TextStyle(color: _brand, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
          const Spacer(),
          // Audience toggle.
          for (final a in ['client', 'coach'])
            GestureDetector(
              onTap: () => setState(() { _audience = a; _explanation = null; }),
              child: Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _audience == a ? _brand : _panel2, borderRadius: BorderRadius.circular(20)),
                child: Text(a, style: TextStyle(
                    color: _audience == a ? Colors.white : _muted, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ),
        ]),
        const SizedBox(height: 10),
        if (_explanation != null)
          Text(_explanation!, style: const TextStyle(color: _text, fontSize: 14, height: 1.5))
        else
          const Text('Grounded in the decision trace — the model can only explain what the engine recorded.',
              style: TextStyle(color: _muted, fontSize: 12)),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _explaining ? null : _explain,
          child: Container(
            alignment: Alignment.center, padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: _brand.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10), border: Border.all(color: _brand.withValues(alpha: 0.4))),
            child: _explaining
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: _brand, strokeWidth: 2))
                : Text('Explain for $_audience', style: const TextStyle(color: _brand, fontSize: 13, fontWeight: FontWeight.w800)),
          ),
        ),
      ]),
    );
  }

  Widget _candidateRow(Map<String, dynamic> c) {
    final accepted = c['decision'] == 'accepted';
    final col = accepted ? _pass : _fail;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _panel, borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: col, width: 3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(accepted ? Icons.check_circle_rounded : Icons.cancel_rounded, color: col, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(c['name']?.toString() ?? '—',
              style: const TextStyle(color: _text, fontSize: 14, fontWeight: FontWeight.w700))),
          Text('score ${c['score'] ?? '-'}',
              style: const TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (c['rule'] != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: _fail.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(6)),
              child: Text(c['rule'].toString(), style: const TextStyle(color: _fail, fontSize: 9, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(child: Text(c['reason']?.toString() ?? '',
              style: const TextStyle(color: _muted, fontSize: 12, height: 1.3))),
        ]),
      ]),
    );
  }
}
