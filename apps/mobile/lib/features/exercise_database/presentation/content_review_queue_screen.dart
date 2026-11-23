// Content Review Queue — editorial approval surface for AI-drafted exercise
// content. Shows one candidate at a time with its generated content + AI
// confidence; the editor Approves, Publishes, or sends back for Revision, then
// advances to the next. Reuses review_exercise_content() (snapshots a version
// on every transition). Admin / content-manager only.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/custom_exercise_service.dart';
import '../../../core/widgets/role_gate.dart';

const _bg     = Color(0xFF0A0A0B);
const _panel  = Color(0xFF14101E);
const _panel2 = Color(0xFF1B1526);
const _brand  = Color(0xFFB76DFF);
const _text   = Color(0xFFEDE7F3);
const _muted  = Color(0xFF9A93A6);
const _pass   = Color(0xFF10B981);
const _warn   = Color(0xFFF59E0B);
const _fail   = Color(0xFFEF4444);

class ContentReviewQueueScreen extends ConsumerStatefulWidget {
  const ContentReviewQueueScreen({super.key});
  @override
  ConsumerState<ContentReviewQueueScreen> createState() => _State();
}

class _State extends ConsumerState<ContentReviewQueueScreen> {
  final _svc = CustomExerciseService();
  List<Map<String, dynamic>>? _queue;
  bool _loading = true;
  bool _notMigrated = false;
  bool _acting = false;
  int _i = 0;
  int _reviewed = 0;
  Map<String, dynamic>? _cert;  // certification of the current exercise
  Map<String, dynamic>? _graph; // movement-graph relationships of the current exercise
  String? _certForId;

  // P0-FL-45a: the content-only read starts once the gate has confirmed this
  // member's role (see build), not in initState before the role is known.
  final _firstLoad = RoleConfirmedLoad();

  Future<void> _load() async {
    setState(() => _loading = true);
    final q = await _svc.reviewQueue(limit: 100);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _notMigrated = q == null;
      _queue = q ?? [];
      _i = 0;
    });
  }

  Future<void> _act(String status) async {
    if (_acting || _queue == null || _i >= _queue!.length) return;
    setState(() => _acting = true);
    final ex = _queue![_i];
    final ok = await _svc.reviewExercise(ex['id'] as String, status);
    if (!mounted) return;
    setState(() {
      _acting = false;
      if (ok) { _reviewed++; _i++; }
    });
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Action failed — check permissions / migration 083.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    // P0-FL-40/45a: the shared gate — only a role confirmed for THIS member
    // opens (or closes) the screen; unread → loading / failure notice.
    final gate = roleGate(ref,
        title: 'Review Queue',
        allowedRoles: const {'admin', 'content_manager'},
        detail: 'Content tools stay closed until it loads.',
        denied: const Scaffold(backgroundColor: _bg,
          body: Center(child: Text('Admins & content managers only.', style: TextStyle(color: _muted)))));
    if (gate != null) return gate;
    _firstLoad.start(this, _load);
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg, foregroundColor: _text,
        title: const Text('Review Queue', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        actions: [IconButton(icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _brand))
          : _notMigrated
              ? _banner('Pipeline not migrated', 'Apply migration 083_exercise_content_pipeline.sql to enable the editorial workflow.')
              : (_queue == null || _i >= _queue!.length)
                  ? _emptyState()
                  : _card(_queue![_i]),
    );
  }

  // Lazily load this exercise's certification object (view 084) for the matrix.
  void _ensureCert(String id) {
    if (_certForId == id) return;
    _certForId = id;
    _cert = null;
    _graph = null;
    _svc.exerciseCertification(id).then((c) {
      if (mounted && _certForId == id) setState(() => _cert = c);
    });
    _svc.movementGraph(id).then((g) {
      if (mounted && _certForId == id) setState(() => _graph = g);
    });
  }

  Widget _certMatrix() {
    final c = _cert;
    if (c == null) return const SizedBox.shrink();
    const modules = <String, String>{
      'workout_builder': 'Workout Builder', 'program_generator': 'Program Gen',
      'ai_coach': 'AI Coach', 'self_guided': 'Self-Guided', 'coach_guided': 'Coach-Guided',
      'marketplace': 'Marketplace', 'premium_content': 'Premium', 'voice_coaching': 'Voice',
    };
    final current = (c['overall_pct'] as num?)?.toInt() ?? 0;
    final projected = (c['projected_pct'] as num?)?.toInt() ?? 0;
    // What approval would newly unlock.
    final unlocks = <String>[
      for (final e in modules.entries)
        if (c[e.key] != true && c['proj_${e.key}'] == true) e.value,
    ];
    Color pc(int v) => v >= 80 ? _pass : (v >= 50 ? _warn : _fail);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _panel, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _brand.withValues(alpha: 0.25))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('CERTIFICATION',
            style: TextStyle(color: _brand, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
        const SizedBox(height: 10),
        Row(children: [
          _scorePill('Current', current, pc(current)),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 10),
            child: Icon(Icons.arrow_forward_rounded, color: _muted, size: 16)),
          _scorePill('After approval', projected, pc(projected)),
        ]),
        const SizedBox(height: 10),
        // Projected module chips (what it will be certified for once approved).
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final e in modules.entries)
            _certChip(e.value, c['proj_${e.key}'] == true),
        ]),
        if (unlocks.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Approving unlocks: ${unlocks.join(', ')}',
              style: const TextStyle(color: _pass, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ],
      ]),
    );
  }

  Widget _scorePill(String label, int v, Color c) => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(),
          style: const TextStyle(color: _muted, fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: .6)),
      const SizedBox(height: 2),
      Text('$v/100', style: TextStyle(color: c, fontSize: 18, fontWeight: FontWeight.w900)),
    ]);

  Widget _certChip(String label, bool ok) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: (ok ? _pass : _muted).withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(8)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(ok ? Icons.check_circle_rounded : Icons.remove_circle_outline_rounded,
          color: ok ? _pass : _muted, size: 12),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(
          color: ok ? _text : _muted, fontSize: 11, fontWeight: FontWeight.w600)),
    ]),
  );

  // Graph-backed related movements (targets, patterns, alternatives…).
  Widget _relatedMovements() {
    final g = _graph;
    if (g == null) return const SizedBox.shrink();
    final rels = (g['relationships'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (rels.isEmpty) return const SizedBox.shrink();
    final byType = <String, List<String>>{};
    for (final r in rels) {
      byType.putIfAbsent(r['relationship'] as String, () => []).add(r['to'] as String);
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('MOVEMENT GRAPH',
            style: TextStyle(color: _brand, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
        const SizedBox(height: 8),
        ...byType.entries.map((e) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 130, child: Text(e.key.replaceAll('_', ' ').toLowerCase(),
                style: const TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w700))),
            Expanded(child: Text(e.value.join(', '),
                style: const TextStyle(color: _text, fontSize: 12.5))),
          ]),
        )),
      ]),
    );
  }

  Widget _banner(String title, String body) => Center(child: Padding(
    padding: const EdgeInsets.all(28),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.build_circle_outlined, color: _warn, size: 40),
      const SizedBox(height: 12),
      Text(title, style: const TextStyle(color: _text, fontSize: 16, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Text(body, textAlign: TextAlign.center, style: const TextStyle(color: _muted, fontSize: 13)),
    ]),
  ));

  Widget _emptyState() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.verified_rounded, color: _pass, size: 44),
    const SizedBox(height: 12),
    Text(_reviewed > 0 ? 'Queue cleared — $_reviewed reviewed 🎉' : 'Nothing awaiting review',
        style: const TextStyle(color: _text, fontSize: 16, fontWeight: FontWeight.w700)),
  ]));

  Widget _card(Map<String, dynamic> ex) {
    _ensureCert(ex['id'] as String);
    final conf = (ex['ai_confidence'] as num?)?.toInt();
    final cc = conf == null ? _muted : (conf >= 90 ? _pass : (conf >= 70 ? _warn : _fail));
    List<String> arr(dynamic v) => v is List ? v.map((e) => e.toString()).toList() : const [];
    return Column(children: [
      // Progress header.
      Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(children: [
          Text('${_i + 1} of ${_queue!.length}',
              style: const TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w700)),
          const Spacer(),
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: cc.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)),
            child: Text(conf == null ? 'no confidence' : 'AI confidence $conf%',
                style: TextStyle(color: cc, fontSize: 11, fontWeight: FontWeight.w800))),
        ])),
      Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 16), children: [
        Text(ex['name']?.toString() ?? '—',
            style: const TextStyle(color: _text, fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text('${ex['muscle_group'] ?? '—'} · ${ex['equipment'] ?? '—'} · ${ex['content_status'] ?? '—'}',
            style: const TextStyle(color: _muted, fontSize: 12)),
        const SizedBox(height: 16),
        _certMatrix(),
        _relatedMovements(),
        _list('Instructions', arr(ex['instructions']), numbered: true),
        _list('Coaching cues', arr(ex['coaching_cues'])),
        _list('Common mistakes', arr(ex['common_mistakes'])),
        _single('Beginner modification', ex['beginner_modification']?.toString()),
        _single('Advanced progression', ex['advanced_progression']?.toString()),
        _list('Alternatives', arr(ex['alternatives'])),
      ])),
      _actionBar(),
    ]);
  }

  Widget _list(String label, List<String> items, {bool numbered = false}) {
    if (items.isEmpty) return _emptyField(label);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(),
            style: const TextStyle(color: _brand, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
        const SizedBox(height: 8),
        ...items.asMap().entries.map((e) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(numbered ? '${e.key + 1}. ' : '• ',
                style: const TextStyle(color: _muted, fontSize: 13.5)),
            Expanded(child: Text(e.value,
                style: const TextStyle(color: _text, fontSize: 13.5, height: 1.4))),
          ]),
        )),
      ]),
    );
  }

  Widget _single(String label, String? value) {
    if (value == null || value.trim().isEmpty) return _emptyField(label);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(),
            style: const TextStyle(color: _brand, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(color: _text, fontSize: 13.5, height: 1.4)),
      ]),
    );
  }

  Widget _emptyField(String label) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: _panel, borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _fail.withValues(alpha: 0.3))),
    child: Row(children: [
      const Icon(Icons.warning_amber_rounded, color: _fail, size: 15),
      const SizedBox(width: 8),
      Text('$label — missing', style: const TextStyle(color: _fail, fontSize: 12.5, fontWeight: FontWeight.w600)),
    ]),
  );

  Widget _actionBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(12, 10, 12, 12 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(color: _panel2),
      child: Row(children: [
        _btn('Revise', Icons.replay_rounded, _warn, () => _act('needs_revision')),
        const SizedBox(width: 8),
        _btn('Approve', Icons.check_rounded, _pass, () => _act('approved')),
        const SizedBox(width: 8),
        _btn('Publish', Icons.publish_rounded, _brand, () => _act('published'), filled: true),
      ]),
    );
  }

  Widget _btn(String label, IconData icon, Color color, VoidCallback onTap, {bool filled = false}) {
    return Expanded(child: GestureDetector(
      onTap: _acting ? null : onTap,
      child: Opacity(opacity: _acting ? 0.5 : 1, child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? color : color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: filled ? 1 : 0.4))),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: filled ? Colors.white : color, size: 16),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(
              color: filled ? Colors.white : color, fontSize: 13.5, fontWeight: FontWeight.w800)),
        ]),
      )),
    ));
  }
}
