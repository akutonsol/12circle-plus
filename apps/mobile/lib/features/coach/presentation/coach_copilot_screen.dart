// Coach Copilot — the fastest path to the intelligence 12 Circle has built.
// The coach opens a client; the Copilot runs the deterministic MIE for that
// client (recovery-aware), surfaces the recommended session + WHY (from the
// decision trace) + warm-up, and the coach Approves to assign it. The coach
// stays in control; the engine does the thinking. Consumes the engine — no new
// backend. Coaches/admins only.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../exercise_database/data/custom_exercise_service.dart';
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
const _fail   = Color(0xFFEF4444);

class CoachCopilotScreen extends ConsumerStatefulWidget {
  const CoachCopilotScreen({super.key});
  @override
  ConsumerState<CoachCopilotScreen> createState() => _State();
}

class _State extends ConsumerState<CoachCopilotScreen> {
  final _svc = CustomExerciseService();
  final _programs = CoachProgramService();
  Map<String, dynamic>? _client;    // selected client profile
  int _recovery = 75;
  bool _busy = false, _assigning = false;
  Map<String, dynamic>? _rec;       // engine recommendation (+ trace)
  Map<String, dynamic>? _outlook;   // predictive outlook for the client
  String? _explanation;
  String? _status;

  SupabaseClient get _db => Supabase.instance.client;

  // Derive the MIE context from the client's onboarding profile + recovery.
  Map<String, dynamic> _context(Map<String, dynamic> p) {
    final goalRaw = (p['fitness_goal'] as String?)?.toLowerCase() ?? '';
    final goal = goalRaw.contains('fat') || goalRaw.contains('lose') ? 'fat_loss'
        : goalRaw.contains('muscle') || goalRaw.contains('hyper') ? 'hypertrophy'
        : goalRaw.contains('strength') ? 'strength'
        : goalRaw.contains('endur') ? 'endurance' : 'hypertrophy';
    final loc = (p['training_location'] as String?)?.toLowerCase() ?? 'gym';
    final equipment = loc.contains('home')
        ? ['dumbbell', 'bodyweight', 'band']
        : ['barbell', 'dumbbell', 'cable', 'machine', 'bodyweight'];
    final injuries = <String>[
      if (p['injury_locations'] is List) ...List<String>.from(p['injury_locations'] as List),
    ];
    return {
      'goal': goal, 'recovery': _recovery,
      'experience': (p['experience_level'] as String?)?.toLowerCase() ?? 'intermediate',
      'equipment': equipment, 'injuries': injuries, 'size': 5,
    };
  }

  Future<void> _run() async {
    final c = _client;
    if (c == null) return;
    setState(() { _busy = true; _rec = null; _explanation = null; _status = null; });
    final r = await _svc.generateWorkout(_context(c), subjectId: c['id'] as String);
    if (!mounted) return;
    setState(() { _busy = false; _rec = r; });
  }

  Future<void> _explain() async {
    final tid = _rec?['trace_id']?.toString();
    if (tid == null) return;
    final text = await _svc.explainDecision(tid, audience: 'coach');
    if (mounted) setState(() => _explanation = text ?? 'Explanation unavailable (deploy explain-decision).');
  }

  Future<void> _approve() async {
    final c = _client, rec = _rec;
    if (c == null || rec == null) return;
    final selected = (rec['selected'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (selected.isEmpty) return;
    setState(() => _assigning = true);
    try {
      final prog = await _programs.createProgram({
        'name': 'Copilot session · ${DateTime.now().toIso8601String().substring(0, 10)}',
        'description': 'AI-recommended, coach-approved (recovery $_recovery).',
      });
      final exercises = [
        for (final e in selected)
          {'name': e['name'], 'sets': 3, 'reps': 10, 'rest_seconds': 90},
      ];
      await _programs.addWorkoutToProgram(prog['id'] as String, {
        'week_number': 1, 'day_of_week': 'monday',
        'title': 'Copilot Session', 'exercises': exercises, 'sort_order': 0,
      });
      await _programs.assignProgram(prog['id'] as String, c['id'] as String);
      if (mounted) setState(() => _status = 'Assigned to ${c['first_name'] ?? 'client'} ✓');
    } catch (e) {
      if (mounted) setState(() => _status = 'Assign failed.');
    } finally {
      if (mounted) setState(() => _assigning = false);
    }
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
        title: const Text('Coach Copilot', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
        clients.when(
          loading: () => const Padding(padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator(color: _brand))),
          error: (e, _) => Text('Could not load clients.', style: const TextStyle(color: _fail)),
          data: (list) => list.isEmpty
              ? const Text('No active clients yet.', style: TextStyle(color: _muted))
              : _clientPicker(list),
        ),
        if (_client != null) ...[
          if (_outlook != null && _outlook!['status'] == 'ok') ...[
            const SizedBox(height: 14),
            _outlookCard(_outlook!),
          ],
          const SizedBox(height: 14),
          _recoveryCard(),
          const SizedBox(height: 12),
          _generateButton(),
          if (_rec != null) ..._recommendation(_rec!),
        ],
      ]),
    );
  }

  Widget _clientPicker(List<Map<String, dynamic>> list) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('CLIENT', style: TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
      const SizedBox(height: 8),
      SizedBox(height: 40, child: ListView.separated(
        scrollDirection: Axis.horizontal, itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final c = list[i];
          final sel = _client?['id'] == c['id'];
          return GestureDetector(
            onTap: () async {
              // Load full profile for context derivation.
              final full = await _db.from('user_profiles')
                  .select('id, first_name, fitness_goal, experience_level, training_location, injury_locations')
                  .eq('id', c['id']).maybeSingle();
              if (mounted) setState(() { _client = full ?? c; _rec = null; _status = null; _explanation = null; _outlook = null; });
              // Predictive outlook for this client (deterministic).
              final o = await _programs.predictClient(c['id'] as String);
              if (mounted) setState(() => _outlook = o);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: sel ? _brand : _panel2, borderRadius: BorderRadius.circular(20),
                border: Border.all(color: sel ? _brand : _brand.withValues(alpha: 0.2))),
              child: Text('${c['first_name'] ?? 'Client'} ${(c['last_name'] ?? '').toString()}'.trim(),
                  style: TextStyle(color: sel ? Colors.white : _text, fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          );
        },
      )),
    ]);
  }

  // Predictive Intelligence — the client's forward-looking outlook.
  Widget _outlookCard(Map<String, dynamic> o) {
    final goal = o['goal'] as Map? ?? {};
    final progress = (goal['progress_pct'] as num?)?.toInt() ?? 0;
    final conf = (goal['confidence'] as num?)?.toInt() ?? 0;
    final finish = goal['predicted_finish']?.toString();
    final plateau = o['plateau_risk']?.toString() ?? 'low';
    final injury = (o['injury_risk'] as Map?)?['general']?.toString() ?? 'low';
    final rec = o['recovery'] as Map? ?? {};
    final alerts = (o['alerts'] as List?)?.map((e) => e.toString()).toList() ?? [];
    Color risk(String r) => r == 'high' ? _fail : (r == 'medium' ? _warn : _pass);
    Color cc(int v) => v >= 80 ? _pass : (v >= 50 ? _warn : _fail);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [cc(conf).withValues(alpha: 0.18), _panel2],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16), border: Border.all(color: cc(conf).withValues(alpha: 0.4))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('CLIENT OUTLOOK', style: TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          const Spacer(),
          Text('${o['weeks_completed']}/${o['duration_weeks']} wks', style: const TextStyle(color: _muted, fontSize: 11)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('GOAL PROGRESS', style: TextStyle(color: _muted, fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: .6)),
            const SizedBox(height: 4),
            ClipRRect(borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: progress / 100, minHeight: 8, backgroundColor: _panel, color: _brand)),
            const SizedBox(height: 4),
            Text('$progress%', style: const TextStyle(color: _text, fontSize: 13, fontWeight: FontWeight.w800)),
          ])),
          const SizedBox(width: 16),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('$conf%', style: TextStyle(color: cc(conf), fontSize: 24, fontWeight: FontWeight.w900)),
            const Text('confidence', style: TextStyle(color: _muted, fontSize: 9)),
          ]),
        ]),
        if (finish != null && finish != 'null') Padding(padding: const EdgeInsets.only(top: 8),
          child: Text('Predicted finish: $finish', style: const TextStyle(color: _text, fontSize: 12.5, fontWeight: FontWeight.w600))),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          _riskChip('Plateau', plateau, risk(plateau)),
          _riskChip('Injury', injury, risk(injury)),
          _riskChip('Recovery', rec['trend']?.toString() ?? '—', rec['trend'] == 'declining' ? _warn : _pass),
        ]),
        if (alerts.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10),
          child: Text('⚠ ${alerts.map((a) => a.replaceAll('_', ' ')).join(' · ')}',
              style: const TextStyle(color: _warn, fontSize: 11.5, fontWeight: FontWeight.w600))),
      ]),
    );
  }

  Widget _riskChip(String label, String val, Color col) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: col.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
    child: Text('$label: $val', style: TextStyle(color: col, fontSize: 11, fontWeight: FontWeight.w700)),
  );

  Widget _recoveryCard() {
    final c = _recovery < 60 ? _warn : _pass;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        const Text('Recovery', style: TextStyle(color: _text, fontSize: 13, fontWeight: FontWeight.w700)),
        Expanded(child: Slider(value: _recovery.toDouble(), min: 0, max: 100, divisions: 20,
          activeColor: _brand, label: '$_recovery',
          onChanged: (v) => setState(() => _recovery = v.round()))),
        Text('$_recovery%', style: TextStyle(color: c, fontSize: 15, fontWeight: FontWeight.w900)),
      ]),
    );
  }

  Widget _generateButton() => GestureDetector(
    onTap: _busy ? null : _run,
    child: Container(
      width: double.infinity, alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(color: _brand, borderRadius: BorderRadius.circular(12)),
      child: _busy
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
          : const Text('Generate recommendation', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
    ),
  );

  List<Widget> _recommendation(Map<String, dynamic> r) {
    final selected = (r['selected'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final trace = (r['trace'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final rejected = trace.where((e) => e['decision'] == 'rejected').toList();
    final warmup = (r['warmup'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final rules = (r['rules_triggered'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final vol = (r['volume_factor'] as num?)?.toDouble() ?? 1.0;
    if (selected.isEmpty) {
      return [const SizedBox(height: 14), _banner(
        'Engine returned no session — ensure the MIE migrations are applied and intelligence profiles are enriched/approved.')];
    }
    final volPct = ((vol - 1) * 100).round();
    return [
      const SizedBox(height: 16),
      // At-a-glance summary tiles.
      Row(children: [
        Expanded(child: _tile('Volume', volPct == 0 ? 'Full' : '${volPct > 0 ? '+' : ''}$volPct%', vol < 1 ? _warn : _pass)),
        const SizedBox(width: 8),
        Expanded(child: _tile('Exercises', '${selected.length}', _text)),
        const SizedBox(width: 8),
        Expanded(child: _tile('Swaps', '${rejected.length}', rejected.isEmpty ? _muted : _warn)),
      ]),
      const SizedBox(height: 12),
      _section('RECOMMENDED SESSION'),
      ...selected.map((e) => _line(Icons.check_circle_rounded, _pass,
          e['name']?.toString() ?? '—', 'score ${e['score'] ?? '-'} · ${e['pattern'] ?? ''}')),
      if (rejected.isNotEmpty) ...[
        const SizedBox(height: 10),
        _section('WHY (swaps & skips)'),
        ...rejected.map((e) => _line(Icons.swap_horiz_rounded, _warn,
            e['name']?.toString() ?? '—', '${e['rule']}: ${e['reason']}')),
      ],
      if (rules.isNotEmpty) ...[
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final r in rules) Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: _panel2, borderRadius: BorderRadius.circular(8)),
            child: Text(r, style: const TextStyle(color: _muted, fontSize: 10, fontWeight: FontWeight.w700))),
        ]),
      ],
      if (warmup.isNotEmpty) ...[
        const SizedBox(height: 12),
        _section('WARM-UP'),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final w in warmup) Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: _panel2, borderRadius: BorderRadius.circular(8)),
            child: Text('${w['name']} · ${w['type']}', style: const TextStyle(color: _text, fontSize: 11.5))),
        ]),
      ],
      const SizedBox(height: 12),
      if (_explanation != null)
        Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _brand.withValues(alpha: 0.25))),
          child: Text(_explanation!, style: const TextStyle(color: _text, fontSize: 13.5, height: 1.5)))
      else
        GestureDetector(onTap: _explain, child: Padding(padding: const EdgeInsets.only(bottom: 12),
          child: Text('Explain for coach →', style: TextStyle(color: _brand, fontSize: 12.5, fontWeight: FontWeight.w700)))),
      // Approve.
      GestureDetector(
        onTap: _assigning ? null : _approve,
        child: Container(
          width: double.infinity, alignment: Alignment.center, padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(color: _pass, borderRadius: BorderRadius.circular(12)),
          child: _assigning
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Approve & assign', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
        ),
      ),
      if (_status != null) Padding(padding: const EdgeInsets.only(top: 10),
        child: Text(_status!, style: TextStyle(
            color: _status!.contains('failed') ? _fail : _pass, fontSize: 13, fontWeight: FontWeight.w700))),
    ];
  }

  Widget _banner(String m) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: _panel2, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _warn.withValues(alpha: 0.4))),
    child: Row(children: [
      const Icon(Icons.info_outline_rounded, color: _warn, size: 16), const SizedBox(width: 8),
      Expanded(child: Text(m, style: const TextStyle(color: _muted, fontSize: 12))),
    ]),
  );

  Widget _section(String s) => Padding(padding: const EdgeInsets.only(bottom: 8),
    child: Text(s, style: const TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)));

  Widget _tile(String label, String value, Color color) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
    decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(12)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: TextStyle(color: color, fontSize: 17, fontWeight: FontWeight.w900)),
      const SizedBox(height: 2),
      Text(label.toUpperCase(), style: const TextStyle(color: _muted, fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: .6)),
    ]),
  );

  Widget _line(IconData icon, Color col, String title, String sub) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: col, size: 16), const SizedBox(width: 8),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: _text, fontSize: 13.5, fontWeight: FontWeight.w600)),
        Text(sub, style: const TextStyle(color: _muted, fontSize: 11.5)),
      ])),
    ]),
  );
}
