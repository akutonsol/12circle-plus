// 12 Circle QA Center — a DEBUG/QA-ONLY developer dashboard for validating the
// health of the whole platform before deploy. It orchestrates the live QaSuites
// (which reuse the app's own business logic) and renders pass/fail per module.
// It never duplicates check logic; state-mutating certifications live in the CLI
// harnesses and appear here as SKIP with the command to run them.
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/qa_models.dart';
import '../domain/qa_suites.dart';

const _bg      = Color(0xFF0A0A0B);
const _panel   = Color(0xFF14101E);
const _panel2  = Color(0xFF1B1526);
const _brand   = Color(0xFFB76DFF);
const _text    = Color(0xFFEDE7F3);
const _muted   = Color(0xFF9A93A6);
const _pass    = Color(0xFF10B981);
const _fail    = Color(0xFFEF4444);
const _warn    = Color(0xFFF59E0B);
const _skip    = Color(0xFF6B7280);

Color _statusColor(QaStatus s) => switch (s) {
      QaStatus.pass => _pass,
      QaStatus.fail => _fail,
      QaStatus.warn => _warn,
      QaStatus.running => _brand,
      _ => _skip,
    };
String _statusLabel(QaStatus s) => switch (s) {
      QaStatus.pass => 'PASS',
      QaStatus.fail => 'FAIL',
      QaStatus.warn => 'WARN',
      QaStatus.running => 'RUNNING',
      QaStatus.skip => 'SKIP',
      QaStatus.idle => 'IDLE',
    };
IconData _statusIcon(QaStatus s) => switch (s) {
      QaStatus.pass => Icons.check_circle_rounded,
      QaStatus.fail => Icons.cancel_rounded,
      QaStatus.warn => Icons.error_rounded,
      QaStatus.running => Icons.autorenew_rounded,
      _ => Icons.remove_circle_outline_rounded,
    };

class QaCenterScreen extends StatefulWidget {
  const QaCenterScreen({super.key});
  @override
  State<QaCenterScreen> createState() => _QaCenterScreenState();
}

class _QaCenterScreenState extends State<QaCenterScreen> {
  final _suites = allSuites();
  final Map<String, QaSuiteResult> _results = {};
  final Map<String, QaStatus> _running = {};
  final List<String> _log = [];
  bool _dbConnected = false;
  bool _busy = false;
  DateTime? _lastRun;
  Set<String>? _focusGroups; // module-list filter set by a Release category tap

  // Release categories → the suite groups that roll into each.
  static const Map<String, List<String>> _categories = {
    'Feature': ['Core', 'Engagement', 'Training'],
    'Entitlements': ['Billing', 'Coaching Modes'],
    'Data Integrity': ['Data Integrity'],
    'Content Quality': ['Content Quality'],
    'User Journeys': ['User Journeys'],
    'Intelligence': ['Intelligence', 'Coaching'],
  };

  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _ping();
  }

  Future<void> _ping() async {
    try {
      await _db.rpc('client_plan');
      if (mounted) setState(() => _dbConnected = true);
    } catch (_) {
      if (mounted) setState(() => _dbConnected = false);
    }
  }

  void _addLog(String s) {
    setState(() => _log.insert(0, '${TimeOfDay.now().format(context)}  $s'));
  }

  Future<void> _runOne(QaSuite s) async {
    setState(() => _running[s.name] = QaStatus.running);
    _addLog('▶ ${s.name} …');
    final res = await s.run(_db);
    if (!mounted) return;
    setState(() {
      _results[s.name] = res;
      _running.remove(s.name);
      _lastRun = DateTime.now();
    });
    _addLog('${_statusLabel(res.status)}  ${s.name}  (${res.passed}/${res.total} · ${res.ms}ms)');
  }

  Future<void> _runGroup(String group) async {
    if (_busy) return;
    setState(() => _busy = true);
    for (final s in _suites.where((s) => s.group == group)) {
      await _runOne(s);
    }
    if (!mounted) return;
    setState(() => _busy = false);
  }

  Future<void> _runAll() async {
    if (_busy) return;
    setState(() { _busy = true; _log.clear(); });
    _addLog('Running full suite …');
    for (final s in _suites) {
      await _runOne(s);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _addLog('Done — ${_overall == QaStatus.pass ? 'ALL GREEN' : _statusLabel(_overall)}');
  }

  QaStatus get _overall =>
      QaStatusX.rollup(_results.values.map((r) => r.status));
  int get _totalChecks => _results.values.fold(0, (a, r) => a + r.total);
  int get _passedChecks => _results.values.fold(0, (a, r) => a + r.passed);
  int _countStatus(QaStatus s) =>
      _results.values.fold(0, (a, r) => a + r.checks.where((c) => c.status == s).length);
  int get _criticalIssues => _countStatus(QaStatus.fail);
  int get _warnings => _countStatus(QaStatus.warn);
  int get _modulesCertified =>
      _results.values.where((r) => r.status == QaStatus.pass).length;
  double get _certPct => _totalChecks == 0 ? 0 : _passedChecks / _totalChecks * 100;

  // Per-category score = green ÷ (green+warn+fail), SKIP excluded. null = not run.
  double? _categoryScore(List<String> groups) {
    int p = 0, wf = 0;
    for (final s in _suites) {
      if (!groups.contains(s.group)) continue;
      final r = _results[s.name];
      if (r == null) continue;
      for (final c in r.checks) {
        if (c.status == QaStatus.pass) {
          p++;
        } else if (c.status == QaStatus.warn || c.status == QaStatus.fail) {
          wf++;
        }
      }
    }
    final denom = p + wf;
    return denom == 0 ? null : p / denom * 100;
  }

  bool _categoryHasFail(List<String> groups) => _suites
      .where((s) => groups.contains(s.group))
      .any((s) => (_results[s.name]?.status) == QaStatus.fail);

  double? get _releaseScore {
    final scores = _categories.values.map(_categoryScore).whereType<double>().toList();
    if (scores.isEmpty) return null;
    return scores.reduce((a, b) => a + b) / scores.length;
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: Text('QA Center is available in debug builds only.',
            style: TextStyle(color: _muted))),
      );
    }
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: _text,
        title: const Text('12 Circle QA Center',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        actions: [
          if (_busy)
            const Padding(padding: EdgeInsets.only(right: 16),
              child: Center(child: SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(color: _brand, strokeWidth: 2)))),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          _certScoreCard(),
          const SizedBox(height: 12),
          _headerStrip(),
          const SizedBox(height: 14),
          _overallCard(),
          const SizedBox(height: 20),
          _runButtons(),
          const SizedBox(height: 20),
          _releaseSection(),
          const SizedBox(height: 20),
          Row(children: [
            _sectionLabel('MODULE HEALTH'),
            const Spacer(),
            if (_focusGroups != null)
              GestureDetector(
                onTap: () => setState(() => _focusGroups = null),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: _panel2, borderRadius: BorderRadius.circular(20)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.close_rounded, size: 12, color: _brand),
                    SizedBox(width: 4),
                    Text('clear filter', style: TextStyle(color: _brand, fontSize: 10, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
          ]),
          const SizedBox(height: 10),
          ..._visibleSuites.map(_suiteTile),
          const SizedBox(height: 20),
          _sectionLabel('LIVE LOG'),
          const SizedBox(height: 10),
          _logPanel(),
        ],
      ),
    );
  }

  List<QaSuite> get _visibleSuites => _focusGroups == null
      ? _suites
      : _suites.where((s) => _focusGroups!.contains(s.group)).toList();

  // ── Release Certification: per-category roll-up → one release decision ──
  Widget _releaseSection() {
    final overall = _releaseScore;
    final anyFail = _categories.values.any(_categoryHasFail);
    final ran = _results.isNotEmpty;
    final ready = ran && !anyFail;
    final c = !ran ? _skip : (ready ? _pass : _fail);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('RELEASE CERTIFICATION',
              style: TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          const Spacer(),
          Text(overall == null ? '—' : '${overall.toStringAsFixed(1)}%',
              style: TextStyle(color: c, fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: c.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)),
            child: Text(!ran ? 'NOT RUN' : (ready ? '🟢 READY' : '🔴 BLOCKED'),
                style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 12),
        ..._categories.entries.map((e) {
          final score = _categoryScore(e.value);
          final fail = _categoryHasFail(e.value);
          final cc = score == null ? _skip : (fail ? _fail : (score >= 99.99 ? _pass : _warn));
          final selected = _focusGroups != null && _focusGroups!.containsAll(e.value.toSet());
          return GestureDetector(
            onTap: () => setState(() =>
                _focusGroups = selected ? null : e.value.toSet()),
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: selected ? _panel2 : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: selected ? _brand.withValues(alpha: 0.4) : _panel2),
              ),
              child: Row(children: [
                Icon(fail ? Icons.cancel_rounded : (score == null ? Icons.remove_rounded : Icons.check_circle_rounded),
                    color: cc, size: 15),
                const SizedBox(width: 8),
                Expanded(child: Text(e.key,
                    style: const TextStyle(color: _text, fontSize: 13, fontWeight: FontWeight.w600))),
                // Mini progress bar.
                SizedBox(width: 90, child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (score ?? 0) / 100, minHeight: 5,
                    backgroundColor: _panel2, color: cc),
                )),
                const SizedBox(width: 10),
                SizedBox(width: 44, child: Text(score == null ? '—' : '${score.toStringAsFixed(0)}%',
                    textAlign: TextAlign.right,
                    style: TextStyle(color: cc, fontSize: 12, fontWeight: FontWeight.w800))),
                const Icon(Icons.chevron_right_rounded, size: 16, color: _muted),
              ]),
            ),
          );
        }),
        if (ran)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              ready ? 'No blocking failures — safe to release.'
                    : 'Resolve the failing category before releasing.',
              style: TextStyle(color: ready ? _pass : _fail, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
      ]),
    );
  }

  // ── Certification score hero: the one number to gate a release on ──
  Widget _certScoreCard() {
    final ran = _results.isNotEmpty;
    final ready = ran && _criticalIssues == 0;
    final c = !ran ? _skip : (ready ? _pass : _fail);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [c.withValues(alpha: 0.20), _panel2],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.withValues(alpha: 0.45)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('PLATFORM CERTIFICATION',
            style: TextStyle(color: _muted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(ran ? '${_certPct.toStringAsFixed(1)}%' : '—',
              style: TextStyle(color: c, fontSize: 40, fontWeight: FontWeight.w900, height: 1)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(color: c.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(ready ? Icons.verified_rounded : (ran ? Icons.gpp_bad_rounded : Icons.hourglass_empty_rounded),
                  color: c, size: 16),
              const SizedBox(width: 6),
              Text(!ran ? 'NOT RUN' : (ready ? 'READY' : 'BLOCKED'),
                  style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w800)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          _metric('Build', '1.0.0+1', _text),
          _metric('Certified', '$_modulesCertified / ${_suites.length}', _text),
          _metric('Critical', '$_criticalIssues', _criticalIssues == 0 ? _pass : _fail),
          _metric('Warnings', '$_warnings', _warnings == 0 ? _muted : _warn),
        ]),
      ]),
    );
  }

  Widget _metric(String label, String value, Color color) => Expanded(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: TextStyle(color: color, fontSize: 17, fontWeight: FontWeight.w900)),
      const SizedBox(height: 2),
      Text(label.toUpperCase(),
          style: const TextStyle(color: _muted, fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: .6)),
    ]),
  );

  // ── Header: env / build / db / last-run ──
  Widget _headerStrip() {
    final items = [
      ('Environment', 'Development', _brand),
      ('Build', '1.0.0+1', _text),
      ('Database', _dbConnected ? 'Connected' : 'Offline', _dbConnected ? _pass : _fail),
      ('Last Run', _lastRun == null ? '—' : _ago(_lastRun!), _muted),
    ];
    return Row(children: [
      for (final it in items)
        Expanded(child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(it.$1.toUpperCase(),
                style: const TextStyle(color: _muted, fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: .6)),
            const SizedBox(height: 4),
            Text(it.$2, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: it.$3, fontSize: 12, fontWeight: FontWeight.w800)),
          ]),
        )),
    ]);
  }

  // ── Overall status hero ──
  Widget _overallCard() {
    final s = _results.isEmpty ? QaStatus.idle : _overall;
    final c = _statusColor(s);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [c.withValues(alpha: 0.22), _panel],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Row(children: [
        Icon(_statusIcon(s), color: c, size: 40),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_results.isEmpty ? 'NOT RUN' : _statusLabel(s),
              style: TextStyle(color: c, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 1)),
          const SizedBox(height: 4),
          Text(_results.isEmpty
                  ? 'Press Run All Tests to certify the build'
                  : '$_passedChecks / $_totalChecks checks passed',
              style: const TextStyle(color: _muted, fontSize: 13, fontWeight: FontWeight.w600)),
        ])),
      ]),
    );
  }

  // ── Run buttons ──
  Widget _runButtons() {
    return Wrap(spacing: 8, runSpacing: 8, children: [
      _btn('Run All Tests', Icons.play_arrow_rounded, _busy ? null : _runAll, primary: true),
      _btn('Coaching Modes', Icons.tune_rounded,
          _busy ? null : () => _runGroup('Coaching Modes')),
      _btn('Data Integrity', Icons.fact_check_rounded,
          _busy ? null : () => _runGroup('Data Integrity')),
      _btn('User Journeys', Icons.route_rounded,
          _busy ? null : () => _runGroup('User Journeys')),
      _btn('Content Quality', Icons.photo_library_rounded,
          _busy ? null : () => _runGroup('Content Quality')),
      _btn('Entitlements', Icons.workspace_premium_rounded,
          _busy ? null : () => _runOne(_suites.firstWhere((s) => s.name == 'Entitlements'))),
      _btn('Database', Icons.storage_rounded,
          _busy ? null : () => _runOne(_suites.firstWhere((s) => s.name == 'Database'))),
      _btn('Scoring', Icons.emoji_events_rounded,
          _busy ? null : () => _runOne(_suites.firstWhere((s) => s.name == 'Scoring'))),
    ]);
  }

  Widget _btn(String label, IconData icon, VoidCallback? onTap, {bool primary = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: primary ? _brand : _panel2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: primary ? _brand : _brand.withValues(alpha: 0.25)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: primary ? Colors.white : _brand),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(
                color: primary ? Colors.white : _text, fontSize: 13, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }

  // ── One suite: header row + expandable checks ──
  Widget _suiteTile(QaSuite s) {
    final res = _results[s.name];
    final status = _running[s.name] ?? res?.status ?? QaStatus.idle;
    final c = _statusColor(status);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(14)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          iconColor: _muted,
          collapsedIconColor: _muted,
          leading: status == QaStatus.running
              ? const SizedBox(width: 22, height: 22,
                  child: CircularProgressIndicator(color: _brand, strokeWidth: 2))
              : Icon(_statusIcon(status), color: c, size: 22),
          title: Text(s.name, style: const TextStyle(color: _text, fontSize: 15, fontWeight: FontWeight.w700)),
          subtitle: Text(s.group, style: const TextStyle(color: _muted, fontSize: 11)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (res != null)
              Text('${res.passed}/${res.total}',
                  style: const TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: c.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(8)),
              child: Text(_statusLabel(status),
                  style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.expand_more_rounded, size: 18, color: _muted),
          ]),
          children: [
            if (res == null)
              GestureDetector(
                onTap: _busy ? null : () => _runOne(s),
                child: Container(
                  width: double.infinity, alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(color: _panel2, borderRadius: BorderRadius.circular(10)),
                  child: const Text('Run this module',
                      style: TextStyle(color: _brand, fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              )
            else
              ...res.checks.map((chk) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Icon(_statusIcon(chk.status), color: _statusColor(chk.status), size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(chk.name,
                      style: const TextStyle(color: _text, fontSize: 13))),
                  if (chk.value != null) ...[
                    SizedBox(width: 70, child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: chk.value!.clamp(0, 1), minHeight: 5,
                        backgroundColor: _panel2, color: _statusColor(chk.status)),
                    )),
                    const SizedBox(width: 8),
                  ],
                  Flexible(child: Text(chk.detail, textAlign: TextAlign.right, maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _muted, fontSize: 11))),
                ]),
              )),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String s) => Text(s,
      style: const TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2));

  Widget _logPanel() {
    return Container(
      height: 170,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF07060B), borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _panel2),
      ),
      child: _log.isEmpty
          ? const Center(child: Text('No runs yet', style: TextStyle(color: _skip, fontSize: 12)))
          : ListView.builder(
              itemCount: _log.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(_log[i], style: const TextStyle(
                    color: Color(0xFF9FE8C4), fontSize: 11, fontFamily: 'monospace')),
              ),
            ),
    );
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return '${d.inSeconds}s ago';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    return '${d.inHours}h ago';
  }
}
