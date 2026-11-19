// Coach Copilot — the fastest path to the intelligence 12 Circle has built.
// The coach opens a client; the Copilot runs the deterministic MIE for that
// client (recovery-aware), surfaces the recommended session + WHY (from the
// decision trace) + warm-up, and the coach Approves to assign it. The coach
// stays in control; the engine does the thinking. Consumes the engine — no new
// backend. Coaches/admins only.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../exercise_database/data/custom_exercise_service.dart';
import '../data/coach_program_service.dart';
import '../../dashboard/presentation/coach_dashboard_screen.dart' show coachClientsProvider;
import '../../auth/domain/auth_provider.dart';
import '../../../core/observability/network_failure.dart';
import '../domain/coach_ecosystem_provider.dart'
    show ClientAssessment, ClientAssessmentStatus, clientAssessmentProvider;
import '../../profile/presentation/widgets/profile_load_failed_notice.dart';

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
  // The selected client's ROSTER row (`coachClientsProvider`): id and name
  // only. Their health context — goal, experience, location, injuries — is
  // read through the logged `get_client_assessment` RPC
  // ([clientAssessmentProvider]), never from `user_profiles` (P0-FL-38).
  Map<String, dynamic>? _client;
  int _recovery = 75;
  bool _busy = false, _assigning = false;
  Map<String, dynamic>? _rec;       // engine recommendation (+ trace)
  Map<String, dynamic>? _outlook;   // predictive outlook for the client
  String? _explanation;
  String? _status;

  /// The selected client's assessment read, or null with no client selected.
  /// Watched (not read) so it is sent ONCE per selection: autoDispose, and
  /// nothing here re-runs it on a rebuild.
  AsyncValue<ClientAssessment>? _watchAssessment() {
    final id = _client?['id'] as String?;
    return id == null ? null : ref.watch(clientAssessmentProvider(id));
  }

  /// The client's injury areas. `injury_locations` is comma-joined TEXT
  /// (migration 013, `IntakeData.toSupabase`), never a JSON list — the old
  /// `is List` check sent every client to the engine as uninjured.
  static List<String> _injuries(Object? raw) => [
        if (raw is List) ...raw.map((e) => e.toString().trim())
        else if (raw is String) ...raw.split(',').map((e) => e.trim()),
      ].where((e) => e.isNotEmpty).toList();

  /// The row Copilot builds the recommendation from, or null while the
  /// context is UNKNOWN (no client, still loading, or the read failed) — then
  /// Generate stays disabled: a failed read is never treated as "no context".
  ///
  /// When the read answered, generation works as it did before P0-FL-38;
  /// whether to block a client is a product decision, not this screen's:
  /// - a returned row → that row, completed or not: the answers on file are
  ///   used and [_context] defaults only the missing fields, exactly as the
  ///   pre-P0-FL-38 `user_profiles` row was (an injury with no area reaches
  ///   the engine as no areas, completed or not; the notice says so);
  /// - not the active coach (42501) or no row → the roster row, which carries
  ///   no health fields, so the engine uses its defaults (the notice says so).
  static Map<String, dynamic>? _generationSource(
      Map<String, dynamic>? client, AsyncValue<ClientAssessment>? a) {
    if (client == null || a == null) return null;
    if (a.isLoading || a.hasError || !a.hasValue) return null;
    final v = a.requireValue;
    return v.status == ClientAssessmentStatus.loaded ? v.row : client;
  }

  /// The answers on file — completed or not — report an injury but name no
  /// area.
  static bool _injuryWithoutArea(ClientAssessment v) =>
      v.status == ClientAssessmentStatus.loaded &&
      v.row['has_injuries'] == true &&
      _injuries(v.row['injury_locations']).isEmpty;

  // Derive the MIE context from the client's logged assessment + recovery.
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
    final injuries = _injuries(p['injury_locations']);
    return {
      'goal': goal, 'recovery': _recovery,
      'experience': (p['experience_level'] as String?)?.toLowerCase() ?? 'intermediate',
      'equipment': equipment, 'injuries': injuries, 'size': 5,
    };
  }

  Future<void> _run() async {
    final c = _client;
    if (c == null) return;
    final source = _generationSource(
        c, ref.read(clientAssessmentProvider(c['id'] as String)));
    if (source == null) return; // the button is disabled: context unknown
    // Captured before the await: the coach can pick another client while the
    // engine runs, and A's session must never land on B (UX-F4).
    final id = c['id'] as String;
    setState(() { _busy = true; _rec = null; _explanation = null; _status = null; });
    final r = await _svc.generateWorkout(_context(source), subjectId: id);
    if (!mounted) return;
    if (_client?['id'] != id) {
      // Stale: discard it. Selecting the new client already cleared the
      // panel; only the busy state is ours to end.
      setState(() => _busy = false);
      return;
    }
    // A failed call used to leave the panel blank — the error went into
    // `lastError` and nothing said so.
    setState(() {
      _busy = false;
      _rec = r;
      if (r == null) _status = "Couldn't generate a recommendation — try again.";
    });
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
    // P0-FL-40: an unread role is not a missing one. While the member's own
    // profile is loading, or its read failed, the gate stays shut (nothing
    // role-only is shown) and says which — never "… only.". Only a read that
    // succeeded without the role gets that message.
    final profileAsync = ref.watch(currentUserProfileProvider);
    final unread = _unreadRoleGate(ref, profileAsync, 'Coach Copilot');
    if (unread != null) return unread;
    final role = profileAsync.value?['role'];
    if (role != 'coach' && role != 'admin') {
      return const Scaffold(backgroundColor: _bg,
        body: Center(child: Text('Coaches only.', style: TextStyle(color: _muted))));
    }
    final clients = ref.watch(coachClientsProvider);
    final assessment = _watchAssessment();
    final ready = _generationSource(_client, assessment) != null;
    final notice = assessment == null ? null : _healthContextNotice(assessment);
    final injuryWarn = assessment != null && assessment.hasValue &&
        !assessment.hasError && !assessment.isLoading &&
        _injuryWithoutArea(assessment.requireValue);
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
          if (notice != null) ...[
            const SizedBox(height: 14),
            notice,
          ],
          const SizedBox(height: 14),
          _recoveryCard(),
          const SizedBox(height: 12),
          _generateButton(ready),
          if (_rec != null) ..._recommendation(_rec!, injuryWarn: injuryWarn),
          // The status line normally renders inside the recommendation; with no
          // recommendation (a failed call) it needs its own place, or it is lost.
          if (_rec == null && _status != null) Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_status!, style: const TextStyle(
                color: _fail, fontSize: 13, fontWeight: FontWeight.w700))),
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
          final name = '${c['first_name'] ?? 'Client'} ${(c['last_name'] ?? '').toString()}'.trim();
          Future<void> select() async {
            // Selecting the client starts their logged assessment read
            // (watched in build): the health context comes only from there.
            setState(() { _client = c; _rec = null; _status = null; _explanation = null; _outlook = null; });
            // Predictive outlook for this client (deterministic). A late
            // answer for a client no longer selected is discarded.
            final o = await _programs.predictClient(c['id'] as String);
            if (mounted && _client?['id'] == c['id']) setState(() => _outlook = o);
          }
          return Semantics(
            button: true, selected: sel, label: name, onTap: select,
            excludeSemantics: true,
            child: GestureDetector(
            onTap: select,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: sel ? _brand : _panel2, borderRadius: BorderRadius.circular(20),
                border: Border.all(color: sel ? _brand : _brand.withValues(alpha: 0.2))),
              child: Text(name,
                  style: TextStyle(color: sel ? Colors.white : _text, fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ));
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

  /// What Copilot does and does not know about this client's health, or null
  /// when the completed assessment is complete enough to say nothing. A
  /// missing context is never silent: it would read as a client with no
  /// injuries. The failure itself is recorded by [clientAssessmentProvider].
  Widget? _healthContextNotice(AsyncValue<ClientAssessment> a) {
    // Loading first: a Try again in flight shows this, not a second button,
    // so the read cannot be fired twice.
    if (a.isLoading) {
      return _notice(Icons.hourglass_top_rounded, _muted,
          "Loading this client's health context…", null);
    }
    if (a.hasError) {
      final nextStep = isNetworkFailure(a.error)
          ? 'check your connection, then try again.'
          : 'try again in a moment. If it keeps happening, contact support.';
      return _notice(Icons.error_outline, _fail,
        "Couldn't load this client's health context — $nextStep",
        "Copilot won't recommend a session without their goals, experience "
            'and injuries.',
        retry: Align(alignment: Alignment.centerRight, child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: TextButton(
            onPressed: () => ref.invalidate(
                clientAssessmentProvider(_client!['id'] as String)),
            child: const Text('Try again',
              semanticsLabel: "Try again, load this client's health context",
              style: TextStyle(color: _brand, fontWeight: FontWeight.w700))))));
    }
    final v = a.requireValue;
    // Informational, not blocking: Generate stays enabled for every answered
    // read (whether to block these clients is the owner's decision).
    const defaults = 'Recommendations use defaults — their goal, experience '
        'and injuries are unknown. Review the session before assigning it.';
    // Prominent: the one case where the client told us something Copilot
    // cannot act on. Shown for a completed assessment and, beside the "not
    // completed" notice, for one never completed.
    // Amber, not red: red means blocked, and Generate stays enabled (UX-F1).
    final injury = _injuryWithoutArea(v)
        ? _notice(Icons.healing_outlined, _warn,
            'This client reported an injury without saying where.',
            "Copilot can't plan around it — review the session before "
                'assigning it, or ask them to update their assessment.')
        : null;
    if (v.hasAssessment) return injury;
    const onFile = 'Recommendations use the answers on file and defaults for '
        'the rest. Review the session before assigning it.';
    final (IconData icon, String title, String detail) = switch (v.status) {
      ClientAssessmentStatus.notActiveCoach => (Icons.lock_outline,
          "This client's health context is available once coaching is active.",
          defaults),
      ClientAssessmentStatus.noRow => (Icons.assignment_outlined,
          'No assessment on file for this client yet.', defaults),
      ClientAssessmentStatus.loaded => (Icons.assignment_outlined,
          "This client hasn't completed their assessment yet.", onFile),
    };
    final status = _notice(icon, _warn, title, detail);
    if (injury == null) return status;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      injury, const SizedBox(height: 8), status,
    ]);
  }

  /// A live region, so a screen reader hears the state change.
  Widget _notice(IconData icon, Color color, String title, String? detail,
      {Widget? retry}) => Semantics(liveRegion: true, container: true,
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 18), const SizedBox(width: 10),
          Expanded(child: Text(title, style: const TextStyle(
              color: _text, fontSize: 13, fontWeight: FontWeight.w700))),
        ]),
        if (detail != null) Padding(padding: const EdgeInsets.only(top: 6),
          child: Text(detail,
              style: const TextStyle(color: _muted, fontSize: 12, height: 1.4))),
        if (retry != null) retry,
      ]),
    ));

  /// Disabled while the client's health context is unknown (loading or the
  /// read failed); enabled for every answer the read gave.
  Widget _generateButton(bool ready) {
    final enabled = ready && !_busy;
    return Semantics(
    button: true, enabled: enabled, label: 'Generate recommendation',
    onTap: enabled ? _run : null, excludeSemantics: true,
    child: GestureDetector(
    onTap: enabled ? _run : null,
    child: Container(
      width: double.infinity, alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
          color: ready ? _brand : _brand.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12)),
      child: _busy
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
          : const Text('Generate recommendation', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
    ),
  ));
  }

  /// [injuryWarn]: the client reported an injury without an area. The full
  /// notice sits above Generate and scrolls away, so one line repeats right
  /// above Approve & assign (UX-F1).
  List<Widget> _recommendation(Map<String, dynamic> r, {bool injuryWarn = false}) {
    final selected = (r['selected'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final trace = (r['trace'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final rejected = trace.where((e) => e['decision'] == 'rejected').toList();
    final warmup = (r['warmup'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final rules = (r['rules_triggered'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final vol = (r['volume_factor'] as num?)?.toDouble() ?? 1.0;
    if (selected.isEmpty) {
      return [const SizedBox(height: 14), _banner(
        // Was developer copy ("ensure the MIE migrations are applied …") shown to
        // coaches. The engine returns nothing when its exercise intelligence data
        // is not populated yet (registry EB-4); say what that means for the coach.
        'No recommendation yet — the exercise library behind Copilot is still being set up. '
        'Build this session by hand in Programs for now.')];
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
      if (injuryWarn) Padding(padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          const Icon(Icons.healing_outlined, color: _warn, size: 16),
          const SizedBox(width: 8),
          const Expanded(child: Text(
              'Injury reported with no area — review before assigning.',
              style: TextStyle(color: _warn, fontSize: 12.5, fontWeight: FontWeight.w700))),
        ])),
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

/// P0-FL-40 · the role gate while the signed-in member's profile is unread:
/// a neutral loading state, or the shared FL-16 failure notice with a
/// busy-aware Try again. `null` once the read has succeeded — the gate then
/// decides on the role exactly as before.
///
/// Both states keep the screen's own AppBar (title, normal back control —
/// no role-only actions) so there is always an in-app way out (UX-1).
Widget? _unreadRoleGate(WidgetRef ref,
    AsyncValue<Map<String, dynamic>?> profile, String title) {
  final appBar = _gateAppBar(title);
  if (profile.hasError) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: appBar,
      body: SafeArea(child: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ProfileLoadFailedNotice(
          error: profile.error!,
          busy: profile.isLoading,
          detail: 'Coach tools stay closed until it loads.',
          onRetry: () => ref.invalidate(currentUserProfileProvider),
        ),
      ))),
    );
  }
  if (!profile.hasValue) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: appBar,
      body: const Center(child: CircularProgressIndicator(
          color: _brand, semanticsLabel: 'Loading your account')),
    );
  }
  return null;
}

/// The screen's own AppBar style for the unread-role gate.
PreferredSizeWidget _gateAppBar(String title) => AppBar(
    backgroundColor: _bg, foregroundColor: _text,
    title: Text(title,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)));
