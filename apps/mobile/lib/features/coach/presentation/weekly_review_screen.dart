// AI Weekly Review — the first output of the Coaching Communication Engine.
// The coach picks a client + week; the platform assembles a DETERMINISTIC brief
// (facts from feedback, program diff, predictions), the LLM phrases it into
// coach + client drafts (grounded, no analysis), the coach edits, then sends.
// The brief is always shown so the coach sees the grounding. Coaches/admins only.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/coach_program_service.dart';
import '../../dashboard/presentation/coach_dashboard_screen.dart' show coachClientsProvider;
import '../../auth/domain/auth_provider.dart';

const _bg     = Color(0xFF0A0A0B);
const _panel  = Color(0xFF14101E);
const _panel2 = Color(0xFF1B1526);
const _brand  = Color(0xFFB76DFF);
const _text   = Color(0xFFEDE7F3);
const _muted  = Color(0xFF9A93A6);
const _pass   = Color(0xFF10B981);
const _warn   = Color(0xFFF59E0B);

class WeeklyReviewScreen extends ConsumerStatefulWidget {
  const WeeklyReviewScreen({super.key});
  @override
  ConsumerState<WeeklyReviewScreen> createState() => _State();
}

class _State extends ConsumerState<WeeklyReviewScreen> {
  final _svc = CoachProgramService();
  List<Map<String, dynamic>> _programs = [];
  Map<String, dynamic>? _program;
  String? _clientId;
  int _week = 1;
  bool _busy = false, _sent = false;
  Map<String, dynamic>? _brief;
  String? _commId;
  final _clientCtl = TextEditingController();
  final _coachCtl = TextEditingController();
  String? _status;

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _clientCtl.dispose(); _coachCtl.dispose(); super.dispose(); }

  Future<void> _load() async {
    final progs = await _svc.getMyPrograms();
    if (mounted) setState(() => _programs = progs);
  }

  Future<void> _generate() async {
    final p = _program, cid = _clientId;
    if (p == null || cid == null) { setState(() => _status = 'Pick a program and client.'); return; }
    setState(() { _busy = true; _brief = null; _commId = null; _sent = false; _status = null;
      _clientCtl.clear(); _coachCtl.clear(); });
    final created = await _svc.createWeeklyReview(cid, p['id'] as String, _week);
    if (!mounted) return;
    if (created == null || created['status'] != 'ok') {
      setState(() { _busy = false; _status = 'No feedback for week $_week (or apply migration 096).'; });
      return;
    }
    _brief = created;
    _commId = created['communication_id'] as String?;
    // Ask the LLM to phrase it (grounded). Degrades to brief-only if not deployed.
    final gen = _commId == null ? null : await _svc.generateCommunication(_commId!);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (gen != null && gen['client_text'] != null) {
        _clientCtl.text = gen['client_text']?.toString() ?? '';
        _coachCtl.text = gen['coach_text']?.toString() ?? '';
      } else {
        _status = 'Brief assembled. Deploy generate-communication for AI drafting; you can also write it below.';
      }
    });
  }

  Future<void> _send() async {
    final id = _commId;
    if (id == null) return;
    setState(() => _busy = true);
    final r = await sendReviewedCommunication(_svc, id, _clientCtl.text, _coachCtl.text);
    if (!mounted) return;
    setState(() { _busy = false; _sent = r.sent; _status = r.status; });
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(currentUserProfileProvider).valueOrNull?['role'];
    if (role != 'coach' && role != 'admin') {
      return const Scaffold(backgroundColor: _bg,
        body: Center(child: Text('Coaches only.', style: TextStyle(color: _muted))));
    }
    final clients = ref.watch(coachClientsProvider);
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(backgroundColor: _bg, foregroundColor: _text,
        title: const Text('Weekly Review', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
        _picker('PROGRAM', [for (final p in _programs) (p['id'] as String, p['name']?.toString() ?? 'Program')],
            _program?['id'] as String?, (id) => setState(() => _program = _programs.firstWhere((p) => p['id'] == id))),
        const SizedBox(height: 12),
        clients.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (list) => _picker('CLIENT', [for (final c in list) (c['id'] as String, '${c['first_name'] ?? 'Client'}')],
              _clientId, (id) => setState(() => _clientId = id)),
        ),
        const SizedBox(height: 12),
        Row(children: [
          const Text('Completed week', style: TextStyle(color: _text, fontSize: 13, fontWeight: FontWeight.w600)),
          const Spacer(),
          DropdownButton<int>(value: _week, dropdownColor: _panel2, style: const TextStyle(color: _text),
            underline: const SizedBox(), items: [for (var i = 1; i <= 12; i++) DropdownMenuItem(value: i, child: Text('W$i'))],
            onChanged: (v) => setState(() => _week = v ?? 1)),
        ]),
        const SizedBox(height: 8),
        GestureDetector(onTap: _busy ? null : _generate, child: Container(
          width: double.infinity, alignment: Alignment.center, padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(color: _brand, borderRadius: BorderRadius.circular(12)),
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Generate review', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)))),
        if (_brief != null) ..._reviewView(),
        if (_status != null) Padding(padding: const EdgeInsets.only(top: 12),
          child: Text(_status!, style: TextStyle(color: _sent ? _pass : _warn, fontSize: 13, fontWeight: FontWeight.w700))),
      ]),
    );
  }

  Widget _picker(String label, List<(String, String)> opts, String? sel, ValueChanged<String> onTap) {
    if (opts.isEmpty) return Text('$label: none', style: const TextStyle(color: _muted, fontSize: 12));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [for (final o in opts) GestureDetector(
        onTap: () => onTap(o.$1),
        child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(color: sel == o.$1 ? _brand : _panel2, borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _brand.withValues(alpha: 0.2))),
          child: Text(o.$2, style: TextStyle(color: sel == o.$1 ? Colors.white : _text, fontSize: 12, fontWeight: FontWeight.w700))))]),
    ]);
  }

  List<Widget> _reviewView() {
    final b = _brief!;
    final ws = b['week_summary'] as Map? ?? {};
    final wins = (b['wins'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final goal = b['goal_progress'] as Map? ?? {};
    final changes = b['program_changes'] as Map? ?? {};
    return [
      const SizedBox(height: 18),
      // The deterministic grounding brief (always shown — this is the source of truth).
      Container(padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('GROUNDING BRIEF (deterministic)',
              style: TextStyle(color: _brand, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
          const SizedBox(height: 8),
          _fact('Completion', '${ws['completion'] ?? '—'}%'),
          _fact('Recovery', '${ws['recovery'] ?? '—'}${ws['recovery_delta'] != null ? '  (Δ ${ws['recovery_delta']})' : ''}'),
          _fact('PRs', '${ws['prs'] ?? 0}'),
          if (wins.isNotEmpty) _fact('Wins', wins.join(', ')),
          _fact('Goal progress', '${goal['progress_pct'] ?? '—'}% · conf ${goal['confidence'] ?? '—'}%'),
          if (goal['predicted_finish'] != null && '${goal['predicted_finish']}' != 'null')
            _fact('Predicted finish', '${goal['predicted_finish']}'),
          _fact('Program change', '${changes['action'] ?? 'none'}'),
        ])),
      const SizedBox(height: 14),
      _editor('CLIENT MESSAGE', _clientCtl),
      const SizedBox(height: 12),
      _editor('COACH SUMMARY', _coachCtl),
      const SizedBox(height: 14),
      GestureDetector(onTap: (_busy || _sent) ? null : _send, child: Container(
        width: double.infinity, alignment: Alignment.center, padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(color: _sent ? _muted : _pass, borderRadius: BorderRadius.circular(12)),
        child: Text(_sent ? 'Sent' : 'Send to client',
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)))),
    ];
  }

  Widget _fact(String k, String v) => Padding(padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 130, child: Text(k, style: const TextStyle(color: _muted, fontSize: 12))),
      Expanded(child: Text(v, style: const TextStyle(color: _text, fontSize: 12.5, fontWeight: FontWeight.w600))),
    ]));

  Widget _editor(String label, TextEditingController ctl) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
    const SizedBox(height: 6),
    TextField(controller: ctl, maxLines: null, minLines: 3, style: const TextStyle(color: _text, fontSize: 13.5, height: 1.4),
      decoration: InputDecoration(filled: true, fillColor: _panel,
        hintText: 'Coach edit before sending…', hintStyle: const TextStyle(color: _muted),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.all(12))),
  ]);
}

/// Saves the coach's edits, then sends — and sends nothing the coach did not
/// approve.
///
/// The save's result was ignored: when it failed, the unedited draft went to
/// the client anyway and the coach was told "Sent to client ✓". Now a failed
/// save sends nothing and says so. (`send_communication` returns void and
/// cannot report a row it did not change; that needs the RPC to return a count.)
@visibleForTesting
Future<({bool sent, String status})> sendReviewedCommunication(
    CoachProgramService svc, String id, String clientText, String coachText) async {
  final saved = await svc.updateCommunication(id, clientText, coachText);
  if (!saved) {
    return (sent: false, status: "Your edits weren't saved, so nothing was sent. Try again.");
  }
  final ok = await svc.sendCommunication(id);
  return (sent: ok, status: ok ? 'Sent to client ✓' : 'Send failed.');
}
