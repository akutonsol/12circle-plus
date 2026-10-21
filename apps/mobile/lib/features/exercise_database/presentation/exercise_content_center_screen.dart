// Exercise Content Management Center — admin / content-manager tool for driving
// the global `exercises` library to content-completeness. Shows live per-field
// completion and runs the bulk AI enricher (enrich-exercise-content) in a loop,
// streaming progress. Access-gated: role must be admin or content_manager.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/custom_exercise_service.dart';
import '../../auth/domain/auth_provider.dart';
import '../../../core/router/app_router.dart' show kQaToolingEnabled;

const _bg     = Color(0xFF0A0A0B);
const _panel2 = Color(0xFF1B1526);
const _brand  = Color(0xFFB76DFF);
const _text   = Color(0xFFEDE7F3);
const _muted  = Color(0xFF9A93A6);
const _pass   = Color(0xFF10B981);
const _warn   = Color(0xFFF59E0B);
const _fail   = Color(0xFFEF4444);

class ExerciseContentCenterScreen extends ConsumerStatefulWidget {
  const ExerciseContentCenterScreen({super.key});
  @override
  ConsumerState<ExerciseContentCenterScreen> createState() => _State();
}

class _State extends ConsumerState<ExerciseContentCenterScreen> {
  final _svc = CustomExerciseService();
  int _total = 0;
  Map<String, int> _filled = {};
  Map<String, dynamic>? _pipeline; // lifecycle counts (null = migration 083 absent)
  Map<String, dynamic>? _cert;     // per-module certified counts (null = 084 absent)
  Map<String, dynamic>? _graph;    // movement graph stats (null = 085 absent)
  Map<String, dynamic>? _intel;    // intelligence-layer coverage (null = 087 absent)
  bool _graphBusy = false;
  bool _intelBusy = false;
  bool _loading = true;
  bool _running = false;
  bool _stop = false;
  final List<String> _log = [];

  static const _labels = <String, String>{
    'image_url': 'Cover images',
    'video': 'Demo videos',
    'instructions': 'Instructions',
    'coaching_cues': 'Coaching cues',
    'common_mistakes': 'Common mistakes',
    'beginner_modification': 'Beginner modification',
    'advanced_progression': 'Advanced progression',
    'alternatives': 'Alternatives',
    'ai_ready': 'AI-ready',
  };

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final s = await _svc.exerciseContentStats();
      final p = await _svc.contentPipelineStats();
      final cert = await _svc.certificationSummary();
      final graph = await _svc.movementGraphStats();
      final intel = await _svc.intelligenceStats();
      if (!mounted) return;
      setState(() {
        _total = s.total; _filled = s.filled; _pipeline = p; _cert = cert;
        _graph = graph; _intel = intel; _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; });
      _addLog('Failed to load stats.');
    }
  }

  double _score() {
    if (_total == 0 || _filled.isEmpty) return 0;
    final keys = _labels.keys.where((k) => k != 'ai_ready');
    final sum = keys.fold<double>(0, (a, k) => a + (_filled[k] ?? 0) / _total);
    return sum / keys.length;
  }

  void _addLog(String s) {
    if (!mounted) return;
    setState(() => _log.insert(0, s));
  }

  Future<void> _enrichAll() async {
    if (_running) return;
    setState(() { _running = true; _stop = false; _log.clear(); });
    _addLog('Starting AI content enrichment…');
    var totalUpdated = 0;
    var guard = 0; // safety cap: 601 stubs / ~15 per batch ≈ 45 batches
    while (!_stop && guard < 80) {
      guard++;
      final r = await _svc.enrichExerciseContent(limit: 15);
      if (r == null) {
        _addLog('✗ Batch failed — check ANTHROPIC_API_KEY / deploy of enrich-exercise-content.');
        break;
      }
      totalUpdated += r.updated;
      _addLog('Batch $guard: +${r.updated} enriched'
          '${r.failed > 0 ? ' · ${r.failed} failed' : ''} · ${r.remaining} stubs left');
      await _refresh();
      if (r.remaining == 0 || (r.updated == 0 && r.failed == 0)) break;
    }
    _addLog(_stop ? 'Stopped — $totalUpdated enriched this run.'
                  : 'Done — $totalUpdated exercises enriched this run.');
    if (mounted) setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(currentUserProfileProvider).valueOrNull?['role'];
    final allowed = role == 'admin' || role == 'content_manager';
    if (!allowed) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: Text('Admins & content managers only.',
            style: TextStyle(color: _muted))),
      );
    }

    final stubs = _total - (_filled['instructions'] ?? 0);
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg, foregroundColor: _text,
        title: const Text('Content Center',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading || _running ? null : _refresh),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _brand))
          : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
              _scoreCard(stubs),
              const SizedBox(height: 16),
              _pipelineStrip(),
              _actions(stubs),
              const SizedBox(height: 20),
              const Text('CONTENT COMPLETION',
                  style: TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
              const SizedBox(height: 10),
              ..._labels.entries.map((e) => _metricRow(e.value, _filled[e.key] ?? 0)),
              const SizedBox(height: 20),
              _certSection(),
              _graphSection(),
              _intelSection(),
              const Text('ACTIVITY LOG',
                  style: TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
              const SizedBox(height: 10),
              _logPanel(),
            ]),
    );
  }

  // Lifecycle counts + the review-queue entry (needs migration 083).
  Widget _pipelineStrip() {
    final p = _pipeline;
    int c(String k) => (p?[k] as num?)?.toInt() ?? 0;
    final queue = c('ai_generated') + c('under_review') + c('needs_revision');
    if (p == null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _panel2, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _warn.withValues(alpha: 0.35))),
        child: const Row(children: [
          Icon(Icons.build_circle_outlined, color: _warn, size: 16),
          SizedBox(width: 8),
          Expanded(child: Text('Editorial pipeline off — apply migration 083 to enable review workflow.',
              style: TextStyle(color: _muted, fontSize: 12))),
        ]),
      );
    }
    Widget chip(String label, int n, Color col) => Container(
      margin: const EdgeInsets.only(right: 6, bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: col.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
      child: Text('$label $n', style: TextStyle(color: col, fontSize: 11, fontWeight: FontWeight.w700)),
    );
    return Column(children: [
      Wrap(children: [
        chip('Published', c('published'), _pass),
        chip('Approved', c('approved'), _pass),
        chip('Review', c('under_review') + c('ai_generated'), _warn),
        chip('Revise', c('needs_revision'), _fail),
        chip('Draft', c('draft'), _muted),
        chip('AI-certified', c('ai_certified'), _brand),
      ]),
      const SizedBox(height: 8),
      GestureDetector(
        onTap: () => context.push('/content-review'),
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: _panel2, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Icon(Icons.reviews_rounded, color: _brand, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text('Review Queue',
                style: TextStyle(color: _text, fontSize: 14, fontWeight: FontWeight.w700))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: queue > 0 ? _warn.withValues(alpha: 0.18) : _bg,
                borderRadius: BorderRadius.circular(20)),
              child: Text('$queue', style: TextStyle(
                  color: queue > 0 ? _warn : _muted, fontSize: 12, fontWeight: FontWeight.w800))),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded, color: _muted, size: 18),
          ]),
        ),
      ),
    ]);
  }

  Widget _scoreCard(int stubs) {
    final score = _score();
    final c = score >= 0.9 ? _pass : (score >= 0.4 ? _warn : _fail);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [c.withValues(alpha: 0.20), _panel2],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.withValues(alpha: 0.45)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('LIBRARY CONTENT QUALITY',
            style: TextStyle(color: _muted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${(score * 100).toStringAsFixed(0)}%',
              style: TextStyle(color: c, fontSize: 40, fontWeight: FontWeight.w900, height: 1)),
          const SizedBox(width: 12),
          Padding(padding: const EdgeInsets.only(bottom: 6),
            child: Text('$_total exercises · $stubs need content',
                style: const TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w600))),
        ]),
      ]),
    );
  }

  Widget _actions(int stubs) {
    return Row(children: [
      Expanded(child: GestureDetector(
        onTap: _running || stubs == 0 ? null : _enrichAll,
        child: Opacity(opacity: (_running || stubs == 0) ? 0.5 : 1, child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: _brand, borderRadius: BorderRadius.circular(14)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (_running)
              const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            else
              const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(_running ? 'Enriching…' : (stubs == 0 ? 'Library complete' : 'Enrich $stubs with AI'),
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
          ]),
        )),
      )),
      if (_running) ...[
        const SizedBox(width: 10),
        GestureDetector(
          onTap: () => setState(() => _stop = true),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _panel2, borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _fail.withValues(alpha: 0.4))),
            child: const Icon(Icons.stop_rounded, color: _fail, size: 20)),
        ),
      ],
    ]);
  }

  // How many exercises each platform module can safely consume (view 084).
  Widget _certSection() {
    final c = _cert;
    if (c == null) return const SizedBox.shrink();
    int v(String k) => (c[k] as num?)?.toInt() ?? 0;
    final avg = (c['avg_overall'] as num?)?.toDouble() ?? 0;
    const modules = <String, String>{
      'workout_builder': 'Workout Builder',
      'program_generator': 'Program Generator',
      'ai_coach': 'AI Coach',
      'self_guided': 'Self-Guided',
      'coach_guided': 'Coach-Guided',
      'marketplace': 'Marketplace',
      'premium_content': 'Premium Content',
      'voice_coaching': 'Voice Coaching',
      'wearables': 'Wearables',
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('MODULE CERTIFICATION',
            style: TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        const Spacer(),
        Text('avg ${avg.toStringAsFixed(0)}/100',
            style: const TextStyle(color: _brand, fontSize: 12, fontWeight: FontWeight.w800)),
      ]),
      const SizedBox(height: 4),
      const Text('Exercises each module can safely use — the single source of truth.',
          style: TextStyle(color: _muted, fontSize: 11)),
      const SizedBox(height: 10),
      ...modules.entries.map((e) => _metricRow(e.value, v(e.key))),
      const SizedBox(height: 20),
    ]);
  }

  // Movement Intelligence Engine — graph shape + rebuild-from-data control.
  Widget _graphSection() {
    final g = _graph;
    Future<void> rebuild() async {
      setState(() => _graphBusy = true);
      final r = await _svc.rebuildMovementGraph();
      _addLog(r == null
          ? '✗ Graph rebuild failed — apply migration 085 (MIE).'
          : 'Movement graph rebuilt — ${r['nodes']} nodes · ${r['edges']} edges.');
      await _refresh();
      if (mounted) setState(() => _graphBusy = false);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('MOVEMENT INTELLIGENCE ENGINE',
            style: TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        const Spacer(),
        GestureDetector(
          onTap: _graphBusy ? null : rebuild,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: _panel2, borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _brand.withValues(alpha: 0.3))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (_graphBusy)
                const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(color: _brand, strokeWidth: 2))
              else
                const Icon(Icons.hub_rounded, color: _brand, size: 13),
              const SizedBox(width: 6),
              const Text('Rebuild', style: TextStyle(color: _brand, fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ]),
      const SizedBox(height: 10),
      if (g == null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: _panel2, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _warn.withValues(alpha: 0.35))),
          child: const Row(children: [
            Icon(Icons.hub_outlined, color: _warn, size: 16), SizedBox(width: 8),
            Expanded(child: Text('Graph offline — apply migration 085, then Rebuild to derive it from exercise data.',
                style: TextStyle(color: _muted, fontSize: 12))),
          ]),
        )
      else ...[
        Row(children: [
          Expanded(child: _statTile('Nodes', '${g['nodes'] ?? 0}')),
          const SizedBox(width: 8),
          Expanded(child: _statTile('Edges', '${g['edges'] ?? 0}')),
          const SizedBox(width: 8),
          Expanded(child: _statTile('Pending', '${g['edges_pending'] ?? 0}')),
        ]),
        const SizedBox(height: 8),
        _graphBreakdown('Relationships', g['edges_by_type']),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _graphBusy ? null : () async {
            setState(() => _graphBusy = true);
            final r = await _svc.seedWarmupLibrary();
            _addLog(r == null
                ? '✗ Warm-up seed failed — apply migrations 085 + 088.'
                : 'Warm-up library seeded — ${r['warmup_edges']} mobility/activation edges.');
            await _refresh();
            if (mounted) setState(() => _graphBusy = false);
          },
          child: Container(
            width: double.infinity, alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: _panel2, borderRadius: BorderRadius.circular(10)),
            child: const Text('Seed warm-up library',
                style: TextStyle(color: _brand, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
      const SizedBox(height: 20),
    ]);
  }

  // MIE Phase 2 — deterministic programming-intelligence layer coverage.
  Widget _intelSection() {
    final n = _intel;
    Future<void> rebuild() async {
      setState(() => _intelBusy = true);
      final r = await _svc.rebuildExerciseIntelligence();
      _addLog(r == null
          ? '✗ Intelligence rebuild failed — apply migration 087 (MIE Phase 2).'
          : 'Intelligence profiles derived — ${r['profiles']} exercises.');
      await _refresh();
      if (mounted) setState(() => _intelBusy = false);
    }
    int v(String k) => (n?[k] as num?)?.toInt() ?? 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('PROGRAMMING INTELLIGENCE',
            style: TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        const Spacer(),
        GestureDetector(
          onTap: _intelBusy ? null : rebuild,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: _panel2, borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _brand.withValues(alpha: 0.3))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (_intelBusy)
                const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(color: _brand, strokeWidth: 2))
              else
                const Icon(Icons.insights_rounded, color: _brand, size: 13),
              const SizedBox(width: 6),
              const Text('Rebuild', style: TextStyle(color: _brand, fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ]),
      const SizedBox(height: 4),
      const Text('Deterministic scoring metadata the AI Coach & builders decide from.',
          style: TextStyle(color: _muted, fontSize: 11)),
      const SizedBox(height: 10),
      if (n == null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: _panel2, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _warn.withValues(alpha: 0.35))),
          child: const Row(children: [
            Icon(Icons.insights_outlined, color: _warn, size: 16), SizedBox(width: 8),
            Expanded(child: Text('Intelligence layer offline — apply migration 087, then Rebuild.',
                style: TextStyle(color: _muted, fontSize: 12))),
          ]),
        )
      else ...[
        Row(children: [
          Expanded(child: _statTile('Profiled', '${v('profiled')} / ${v('total_exercises')}')),
          const SizedBox(width: 8),
          Expanded(child: _statTile('Engine-ready', '${v('engine_ready')}')),
          const SizedBox(width: 8),
          Expanded(child: _statTile('Avg conf', (n['avg_confidence'] as num?)?.toStringAsFixed(0) ?? '—')),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          _pill('AI drafted', v('ai_generated'), _warn),
          _pill('Under review', v('under_review'), _warn),
          _pill('Approved', v('approved'), _pass),
          _pill('Derived draft', v('draft'), _muted),
        ]),
        const SizedBox(height: 8),
        // AI-enrich full profiles (Phase 2b) — loops the edge fn; lands for review.
        GestureDetector(
          onTap: _intelBusy ? null : () async {
            setState(() => _intelBusy = true);
            _addLog('Starting AI knowledge enrichment…');
            var total = 0; var guard = 0;
            while (guard < 80) {
              guard++;
              final r = await _svc.enrichExerciseIntelligence(limit: 10);
              if (r == null) { _addLog('✗ Intelligence enrichment failed — set ANTHROPIC_API_KEY + deploy.'); break; }
              total += r.updated;
              _addLog('Batch $guard: +${r.updated} profiled${r.failed > 0 ? ' · ${r.failed} failed' : ''} · ${r.remaining} drafts left');
              await _refresh();
              if (r.remaining == 0 || (r.updated == 0 && r.failed == 0)) break;
            }
            _addLog('AI knowledge enrichment done — $total profiles drafted for review.');
            if (mounted) setState(() => _intelBusy = false);
          },
          child: Container(
            width: double.infinity, alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(color: _brand.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10), border: Border.all(color: _brand.withValues(alpha: 0.4))),
            child: const Text('AI-enrich full profiles',
                style: TextStyle(color: _brand, fontSize: 13, fontWeight: FontWeight.w800)),
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => context.push('/knowledge-review'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: _panel2, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(Icons.reviews_rounded, color: _brand, size: 18),
              const SizedBox(width: 10),
              const Expanded(child: Text('Knowledge Review — certify AI profiles per-attribute',
                  style: TextStyle(color: _text, fontSize: 14, fontWeight: FontWeight.w700))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: (v('ai_generated') + v('under_review')) > 0 ? _warn.withValues(alpha: 0.18) : _bg,
                  borderRadius: BorderRadius.circular(20)),
                child: Text('${v('ai_generated') + v('under_review')}',
                    style: TextStyle(color: (v('ai_generated') + v('under_review')) > 0 ? _warn : _muted,
                        fontSize: 12, fontWeight: FontWeight.w800))),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, color: _muted, size: 18),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        // REL-3: debug/profile only. The route itself is unregistered in a
        // release build, so an ungated tile here would navigate to nothing.
        if (kQaToolingEnabled) GestureDetector(
          onTap: () => context.push('/mie-debugger'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: _panel2, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(Icons.bug_report_rounded, color: _brand, size: 18),
              const SizedBox(width: 10),
              const Expanded(child: Text('MIE Debugger — inspect decision traces',
                  style: TextStyle(color: _text, fontSize: 14, fontWeight: FontWeight.w700))),
              const Icon(Icons.chevron_right_rounded, color: _muted, size: 18),
            ]),
          ),
        ),
      ],
      const SizedBox(height: 20),
    ]);
  }

  Widget _pill(String label, int n, Color col) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: col.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
    child: Text('$label $n', style: TextStyle(color: col, fontSize: 11, fontWeight: FontWeight.w700)),
  );

  Widget _statTile(String label, String value) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
    decoration: BoxDecoration(color: _panel2, borderRadius: BorderRadius.circular(12)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: const TextStyle(color: _text, fontSize: 18, fontWeight: FontWeight.w900)),
      const SizedBox(height: 2),
      Text(label.toUpperCase(),
          style: const TextStyle(color: _muted, fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: .6)),
    ]),
  );

  Widget _graphBreakdown(String label, dynamic map) {
    if (map is! Map || map.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(spacing: 6, runSpacing: 6, children: [
        for (final e in map.entries)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: _panel2, borderRadius: BorderRadius.circular(8)),
            child: Text('${e.key.toString().replaceAll('_', ' ').toLowerCase()} ${e.value}',
                style: const TextStyle(color: _muted, fontSize: 10, fontWeight: FontWeight.w600)),
          ),
      ]),
    );
  }

  Widget _metricRow(String label, int count) {
    final frac = _total == 0 ? 0.0 : count / _total;
    final c = frac >= 0.95 ? _pass : (frac >= 0.4 ? _warn : _fail);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        SizedBox(width: 150, child: Text(label,
            style: const TextStyle(color: _text, fontSize: 13, fontWeight: FontWeight.w600))),
        Expanded(child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: frac, minHeight: 7, backgroundColor: _panel2, color: c),
        )),
        const SizedBox(width: 10),
        SizedBox(width: 78, child: Text('$count / $_total',
            textAlign: TextAlign.right,
            style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w700))),
      ]),
    );
  }

  Widget _logPanel() {
    return Container(
      height: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF07060B), borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _panel2)),
      child: _log.isEmpty
          ? const Center(child: Text('No enrichment runs yet',
              style: TextStyle(color: _muted, fontSize: 12)))
          : ListView.builder(
              itemCount: _log.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(_log[i], style: const TextStyle(
                    color: Color(0xFF9FE8C4), fontSize: 11, fontFamily: 'monospace')),
              )),
    );
  }
}
