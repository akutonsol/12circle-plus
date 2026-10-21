// Continuous Coaching Engine — the closed loop. The coach records a week's
// feedback; the deterministic evaluation engine recommends an action; the coach
// (or the approval matrix) applies it — regenerating ONLY future weeks, never
// completed ones — producing a diff, a new version, and a decision trace.
// The engine decides; the LLM explains later. Coaches/admins only.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/coach_program_service.dart';
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

class ContinuousCoachingScreen extends ConsumerStatefulWidget {
  const ContinuousCoachingScreen({super.key});
  @override
  ConsumerState<ContinuousCoachingScreen> createState() => _State();
}

class _State extends ConsumerState<ContinuousCoachingScreen> {
  final _svc = CoachProgramService();
  List<Map<String, dynamic>> _programs = [];
  Map<String, dynamic>? _program;
  int _week = 1;
  int _completion = 90, _recovery = 75, _energy = 70;
  bool _pain = false;
  bool _loading = true, _busy = false;
  Map<String, dynamic>? _eval;   // evaluation result
  Map<String, dynamic>? _applied; // regeneration result
  String? _status;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final progs = await _svc.getMyPrograms();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _programs = progs.where((p) => p['engine_generated'] == true).toList();
      if (_programs.isEmpty) { _programs = progs; } // fall back to all
    });
  }

  Future<void> _evaluate() async {
    final p = _program;
    if (p == null) return;
    setState(() { _busy = true; _eval = null; _applied = null; _status = null; });
    final ok = await _svc.submitWeeklyFeedback(p['id'] as String, _week, {
      'completion_pct': _completion, 'recovery': _recovery, 'energy': _energy,
      'pain': _pain ? ['reported'] : [],
    });
    if (!ok) { if (mounted) setState(() { _busy = false; _status = 'Feedback save failed — apply migration 094.'; }); return; }
    final e = await _svc.evaluateWeek(p['id'] as String, _week);
    if (!mounted) return;
    setState(() { _busy = false; _eval = e; });
  }

  Future<void> _apply({required bool approved}) async {
    final p = _program;
    if (p == null) return;
    setState(() { _busy = true; _status = null; });
    final r = await _svc.regenerateProgram(p['id'] as String, _week, approved: approved);
    if (!mounted) return;
    setState(() {
      _busy = false; _applied = r;
      _status = switch (r?['status']) {
        'applied' => 'Applied — future weeks regenerated (v${r?['version']}).',
        'pending_approval' => 'Needs coach approval.',
        'no_change' => 'On track — no change.',
        _ => 'Regeneration unavailable — apply migration 094.',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(currentUserProfileProvider).valueOrNull?['role'];
    if (role != 'coach' && role != 'admin') {
      return const Scaffold(backgroundColor: _bg,
        body: Center(child: Text('Coaches only.', style: TextStyle(color: _muted))));
    }
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(backgroundColor: _bg, foregroundColor: _text,
        title: const Text('Continuous Coaching', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18))),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _brand))
          : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
              _programPicker(),
              if (_program != null) ...[
                const SizedBox(height: 14),
                _feedbackCard(),
                const SizedBox(height: 12),
                _evalBtn(),
                if (_eval != null) ..._evalView(_eval!),
                if (_status != null) Padding(padding: const EdgeInsets.only(top: 12),
                  child: Text(_status!, style: TextStyle(
                      color: _status!.contains('failed') || _status!.contains('unavailable') ? _fail : _pass,
                      fontSize: 13, fontWeight: FontWeight.w700))),
              ],
            ]),
    );
  }

  Widget _programPicker() {
    if (_programs.isEmpty) {
      return const Text('No programs yet — build one in Program Builder.',
          style: TextStyle(color: _muted));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('PROGRAM', style: TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final p in _programs) GestureDetector(
          onTap: () => setState(() { _program = p; _eval = null; _applied = null; _status = null; }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _program?['id'] == p['id'] ? _brand : _panel2, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _brand.withValues(alpha: 0.2))),
            child: Text(p['name']?.toString() ?? 'Program',
                style: TextStyle(color: _program?['id'] == p['id'] ? Colors.white : _text,
                    fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    ]);
  }

  Widget _feedbackCard() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(16)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text("WEEK FEEDBACK", style: TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        const Spacer(),
        Text('Completed week', style: const TextStyle(color: _muted, fontSize: 11)),
        const SizedBox(width: 8),
        DropdownButton<int>(
          value: _week, dropdownColor: _panel2, style: const TextStyle(color: _text),
          underline: const SizedBox(), items: [
            for (var i = 1; i <= 12; i++) DropdownMenuItem(value: i, child: Text('W$i'))
          ], onChanged: (v) => setState(() { _week = v ?? 1; _eval = null; })),
      ]),
      _slider('Completion', _completion, (v) => setState(() => _completion = v)),
      _slider('Recovery', _recovery, (v) => setState(() => _recovery = v)),
      _slider('Energy', _energy, (v) => setState(() => _energy = v)),
      Row(children: [
        const Text('Pain reported', style: TextStyle(color: _text, fontSize: 13, fontWeight: FontWeight.w600)),
        const Spacer(),
        Switch(value: _pain, activeThumbColor: _fail, onChanged: (v) => setState(() => _pain = v)),
      ]),
    ]),
  );

  Widget _slider(String label, int val, ValueChanged<int> onCh) => Row(children: [
    SizedBox(width: 90, child: Text(label, style: const TextStyle(color: _text, fontSize: 13, fontWeight: FontWeight.w600))),
    Expanded(child: Slider(value: val.toDouble(), min: 0, max: 100, divisions: 20,
      activeColor: _brand, label: '$val', onChanged: (v) => onCh(v.round()))),
    SizedBox(width: 36, child: Text('$val', textAlign: TextAlign.right,
        style: TextStyle(color: val < 60 ? _warn : _pass, fontSize: 13, fontWeight: FontWeight.w800))),
  ]);

  Widget _evalBtn() => GestureDetector(
    onTap: _busy ? null : _evaluate,
    child: Container(
      width: double.infinity, alignment: Alignment.center, padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(color: _brand, borderRadius: BorderRadius.circular(12)),
      child: _busy
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
          : const Text('Evaluate week', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
    ),
  );

  List<Widget> _evalView(Map<String, dynamic> e) {
    final action = e['action']?.toString() ?? 'CONTINUE';
    if (action == 'NO_FEEDBACK') return [const SizedBox(height: 12), Text('No feedback recorded.', style: TextStyle(color: _muted))];
    final rules = (e['rules_triggered'] as List?)?.map((x) => x.toString()).toList() ?? [];
    final needsApproval = e['needs_approval'] == true;
    final mode = e['coaching_mode']?.toString() ?? '';
    final affected = (e['affected_weeks'] as List?)?.cast<num>() ?? [];
    final isContinue = action == 'CONTINUE';
    final col = isContinue ? _pass : (action == 'REPLACE_EXERCISES' ? _fail : _warn);
    return [
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [col.withValues(alpha: 0.2), _panel2],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16), border: Border.all(color: col.withValues(alpha: 0.4))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(isContinue ? Icons.check_circle_rounded : Icons.autorenew_rounded, color: col, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(action.replaceAll('_', ' '),
                style: TextStyle(color: col, fontSize: 18, fontWeight: FontWeight.w900))),
          ]),
          const SizedBox(height: 6),
          Text(e['reason']?.toString() ?? '', style: const TextStyle(color: _text, fontSize: 13)),
          if (affected.length == 2 && !isContinue)
            Text('Affects weeks ${affected.first}–${affected.last} (completed weeks locked)',
                style: const TextStyle(color: _muted, fontSize: 11.5)),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final r in rules) Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: col.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(8)),
              child: Text(r, style: TextStyle(color: col, fontSize: 10, fontWeight: FontWeight.w700))),
          ]),
          if (!isContinue) ...[
            const SizedBox(height: 8),
            Text(needsApproval ? 'Requires coach approval ($mode)' : 'Auto-applies ($mode)',
                style: TextStyle(color: needsApproval ? _warn : _pass, fontSize: 11.5, fontWeight: FontWeight.w700)),
          ],
        ]),
      ),
      if (!isContinue) ...[
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _busy ? null : () => _apply(approved: true),
          child: Container(
            width: double.infinity, alignment: Alignment.center, padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(color: needsApproval ? _pass : _brand, borderRadius: BorderRadius.circular(12)),
            child: Text(needsApproval ? 'Approve & regenerate' : 'Apply',
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
          ),
        ),
      ],
      if (_applied?['diff'] is List) ..._diffView((_applied!['diff'] as List).cast<Map<String, dynamic>>()),
    ];
  }

  List<Widget> _diffView(List<Map<String, dynamic>> diff) {
    if (diff.isEmpty) return [];
    return [
      const SizedBox(height: 16),
      const Text('PROGRAM DIFF', style: TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
      const SizedBox(height: 8),
      ...diff.map((d) {
        final b = d['before'] as Map?; final a = d['after'] as Map?;
        return Container(
          margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            SizedBox(width: 42, child: Text('W${d['week']}', style: const TextStyle(color: _text, fontSize: 13, fontWeight: FontWeight.w800))),
            Expanded(child: Text('vol ×${b?['volume_multiplier']} → ×${a?['volume_multiplier']}'
                '${a?['is_deload'] == true && b?['is_deload'] != true ? '  + deload' : ''}',
                style: const TextStyle(color: _muted, fontSize: 12.5))),
            const Icon(Icons.arrow_forward_rounded, color: _brand, size: 14),
          ]),
        );
      }),
    ];
  }
}
