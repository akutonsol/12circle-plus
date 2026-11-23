// Coaching Observability — an internal dashboard for coaching QUALITY, not
// servers. It reuses data the deterministic engines already produce (decision
// traces, predictions, communications, certification, intelligence) to answer
// the only question that matters post-architecture: is the platform delivering
// coaching value? No new intelligence. Admin only.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../exercise_database/data/custom_exercise_service.dart';
import '../../../core/widgets/role_gate.dart';
import '../../workout/presentation/widgets/section_load_failure.dart';

const _bg     = Color(0xFF0A0A0B);
const _panel  = Color(0xFF14101E);
const _panel2 = Color(0xFF1B1526);
const _brand  = Color(0xFFB76DFF);
const _text   = Color(0xFFEDE7F3);
const _muted  = Color(0xFF9A93A6);
const _pass   = Color(0xFF10B981);
const _warn   = Color(0xFFF59E0B);

class ObservabilityScreen extends ConsumerStatefulWidget {
  const ObservabilityScreen({super.key});
  @override
  ConsumerState<ObservabilityScreen> createState() => _State();
}

class _State extends ConsumerState<ObservabilityScreen> {
  final _svc = CustomExerciseService();
  Map<String, dynamic>? _data;
  bool _loading = true;

  /// The failed-figures notice's retry is in flight: the figures stay on
  /// screen (their failures as "—") with the notice busy, not a spinner.
  bool _retrying = false;

  // P0-FL-45a: the admin-only read starts once the gate has confirmed this
  // member is an admin (see build), not in initState before the role is known;
  // what it loaded belongs to that member (cleared for the next one).
  final _firstLoad = RoleConfirmedLoad();

  void _resetForMember() { _data = null; _loading = true; _retrying = false; }

  Future<void> _retryFigures() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await _load();
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  Future<void> _load() async {
    final session = _firstLoad.session;
    setState(() => _loading = true);
    final d = await _svc.platformObservability();
    // A late answer for a member no longer admitted is dropped.
    if (mounted && _firstLoad.isCurrent(session)) setState(() { _data = d; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    // P0-FL-40/45a: the shared gate — only a role confirmed for THIS member
    // opens (or closes) the screen; unread → loading / failure notice.
    final gate = _firstLoad.gate(this, ref,
        title: 'Coaching Observability',
        allowedRoles: const {'admin'},
        detail: 'Admin tools stay closed until it loads.',
        deniedText: 'Admins only.',
        reset: _resetForMember,
        load: _load);
    if (gate != null) return gate;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(backgroundColor: _bg, foregroundColor: _text,
        title: const Text('Coaching Observability', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _loading ? null : _load)]),
      body: _loading && !_retrying
          ? const Center(child: CircularProgressIndicator(color: _brand))
          : _body(_data ?? {}),
    );
  }

  Widget _body(Map<String, dynamic> d) {
    final a = (d['analytics'] as Map?) ?? {};
    final cert = (d['certification'] as Map?) ?? {};
    final intel = (d['intelligence'] as Map?) ?? {};
    int i(dynamic v) => (v as num?)?.toInt() ?? 0;
    // P0-FL-50a · a figure that couldn't be read is UNKNOWN ("—"), never 0.
    final failed = ((d[CustomExerciseService.observabilityFailedKey] as List?) ?? const [])
        .map((e) => e.toString()).toSet();
    String count(String key) => failed.contains(key) ? '—' : '${i(d[key])}';
    String pct(String key) =>
        failed.contains(key) || d[key] == null ? '—' : '${d[key]}%';
    final certTotal = i(cert['total']);
    final certReady = i(cert['workout_builder']);
    final certPct = certTotal == 0 ? 0 : (certReady / certTotal * 100).round();
    final intelProfiled = i(intel['profiled']);
    final intelTotal = i(intel['total_exercises']);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
      const Text('Is the platform delivering coaching value?',
          style: TextStyle(color: _muted, fontSize: 12)),
      const SizedBox(height: 14),
      if (failed.isNotEmpty) ...[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: _panel2, borderRadius: BorderRadius.circular(12)),
          child: SectionLoadFailure(
            what: failed.length == 1 ? '1 figure' : '${failed.length} figures',
            error: d[CustomExerciseService.observabilityErrorKey],
            detail: 'Those show as —.',
            busy: _retrying,
            onRetry: _retryFigures,
            accent: _brand,
            textColor: _text,
            mutedColor: _muted),
        ),
        const SizedBox(height: 14),
      ],
      _section('ENGINE ACTIVITY'),
      _grid([
        _kpi('Programs generated', count('programs_generated'), _brand),
        _kpi('Decision traces', count('decision_traces'), _brand),
        _kpi('Predictions made', count('predictions'), _brand),
        _kpi('Weekly reviews sent', count('weekly_reviews_sent'), _brand),
      ]),
      const SizedBox(height: 18),
      _section('OUTCOMES'),
      _grid([
        _kpi('Avg client adherence', pct('avg_adherence'),
            _adh(i(d['avg_adherence']))),
        _kpi('Avg goal confidence', pct('avg_goal_confidence'),
            _adh(i(d['avg_goal_confidence']))),
        _kpi('Avg recovery (traced)', a['avg_recovery'] == null ? '—' : '${a['avg_recovery']}',
            _adh(i(a['avg_recovery']))),
        _kpi('Reviews (all states)', count('communications_total'), _muted),
      ]),
      const SizedBox(height: 18),
      _section('DECISION INTELLIGENCE'),
      _rowFact('Most triggered rule', a['most_triggered_rule']?.toString() ?? '—'),
      _rowFact('Most rejected exercise', a['most_rejected_exercise']?.toString() ?? '—'),
      const SizedBox(height: 18),
      _section('KNOWLEDGE HEALTH'),
      _grid([
        _kpi('Exercise certification', '$certPct%', _adh(certPct)),
        _kpi('Workout-ready', '$certReady / $certTotal', _muted),
        _kpi('Intelligence profiled', '$intelProfiled / $intelTotal', _muted),
        _kpi('Knowledge confidence', intel['avg_confidence'] == null ? '—' : '${intel['avg_confidence']}%',
            _adh(i(intel['avg_confidence']))),
      ]),
      const SizedBox(height: 20),
      Container(padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: _panel2, borderRadius: BorderRadius.circular(12)),
        child: const Text('Every metric here is derived from deterministic engine output — '
            'no estimation, no LLM. Zeros mean the stack isn\'t activated yet '
            '(apply migrations + deploy edge fns).',
            style: TextStyle(color: _muted, fontSize: 11.5, height: 1.4))),
    ]);
  }

  Color _adh(int v) => v >= 80 ? _pass : (v >= 50 ? _warn : (v == 0 ? _muted : _warn));

  Widget _section(String s) => Padding(padding: const EdgeInsets.only(bottom: 10),
    child: Text(s, style: const TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)));

  Widget _grid(List<Widget> items) => GridView.count(
    crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
    childAspectRatio: 2.2, crossAxisSpacing: 8, mainAxisSpacing: 8, children: items);

  /// P0-FL-50a · an unknown figure ("—": failed or no data) is NEUTRAL — never
  /// the bad-value colour, which would grade a number nobody has — and its
  /// tile is announced as "<figure>: unavailable".
  Widget _kpi(String label, String value, Color color) {
    final unknown = value == '—';
    final tile = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(14)),
      // Large text scales the readout down to the fixed-ratio tile instead of
      // overflowing it (seen at 320dp, 2.0x).
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(value, style: TextStyle(color: unknown ? _muted : color, fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(label.toUpperCase(),
              style: const TextStyle(color: _muted, fontSize: 8.5, fontWeight: FontWeight.w700, letterSpacing: .5)),
        ]),
      ),
    );
    if (!unknown) return tile;
    return Semantics(container: true, label: '$label: unavailable', excludeSemantics: true, child: tile);
  }

  Widget _rowFact(String k, String v) => Container(
    margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(12)),
    // Both sides wrap at large text rather than overflow (320dp, 2.0x).
    child: Row(children: [
      Expanded(child: Text(k, style: const TextStyle(color: _muted, fontSize: 12))),
      const SizedBox(width: 8),
      Flexible(child: Text(v, textAlign: TextAlign.end,
          style: const TextStyle(color: _text, fontSize: 13, fontWeight: FontWeight.w800))),
    ]),
  );
}
