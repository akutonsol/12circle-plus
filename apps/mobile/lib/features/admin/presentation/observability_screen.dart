// Coaching Observability — an internal dashboard for coaching QUALITY, not
// servers. It reuses data the deterministic engines already produce (decision
// traces, predictions, communications, certification, intelligence) to answer
// the only question that matters post-architecture: is the platform delivering
// coaching value? No new intelligence. Admin only.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../exercise_database/data/custom_exercise_service.dart';
import '../../auth/domain/auth_provider.dart';
import '../../profile/presentation/widgets/profile_load_failed_notice.dart';

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

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final d = await _svc.platformObservability();
    if (mounted) setState(() { _data = d; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    // P0-FL-40: an unread role is not a missing one. While the member's own
    // profile is loading, or its read failed, the gate stays shut (nothing
    // role-only is shown) and says which — never "… only.". Only a read that
    // succeeded without the role gets that message.
    final profileAsync = ref.watch(currentUserProfileProvider);
    final unread = _unreadRoleGate(ref, profileAsync, 'Coaching Observability');
    if (unread != null) return unread;
    final role = profileAsync.value?['role'];
    if (role != 'admin') {
      return const Scaffold(backgroundColor: _bg,
        body: Center(child: Text('Admins only.', style: TextStyle(color: _muted))));
    }
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(backgroundColor: _bg, foregroundColor: _text,
        title: const Text('Coaching Observability', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _loading ? null : _load)]),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _brand))
          : _body(_data ?? {}),
    );
  }

  Widget _body(Map<String, dynamic> d) {
    final a = (d['analytics'] as Map?) ?? {};
    final cert = (d['certification'] as Map?) ?? {};
    final intel = (d['intelligence'] as Map?) ?? {};
    int i(dynamic v) => (v as num?)?.toInt() ?? 0;
    final certTotal = i(cert['total']);
    final certReady = i(cert['workout_builder']);
    final certPct = certTotal == 0 ? 0 : (certReady / certTotal * 100).round();
    final intelProfiled = i(intel['profiled']);
    final intelTotal = i(intel['total_exercises']);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
      const Text('Is the platform delivering coaching value?',
          style: TextStyle(color: _muted, fontSize: 12)),
      const SizedBox(height: 14),
      _section('ENGINE ACTIVITY'),
      _grid([
        _kpi('Programs generated', '${i(d['programs_generated'])}', _brand),
        _kpi('Decision traces', '${i(d['decision_traces'])}', _brand),
        _kpi('Predictions made', '${i(d['predictions'])}', _brand),
        _kpi('Weekly reviews sent', '${i(d['weekly_reviews_sent'])}', _brand),
      ]),
      const SizedBox(height: 18),
      _section('OUTCOMES'),
      _grid([
        _kpi('Avg client adherence', d['avg_adherence'] == null ? '—' : '${d['avg_adherence']}%',
            _adh(i(d['avg_adherence']))),
        _kpi('Avg goal confidence', d['avg_goal_confidence'] == null ? '—' : '${d['avg_goal_confidence']}%',
            _adh(i(d['avg_goal_confidence']))),
        _kpi('Avg recovery (traced)', a['avg_recovery'] == null ? '—' : '${a['avg_recovery']}',
            _adh(i(a['avg_recovery']))),
        _kpi('Reviews (all states)', '${i(d['communications_total'])}', _muted),
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

  Widget _kpi(String label, String value, Color color) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(14)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w900)),
      const SizedBox(height: 4),
      Text(label.toUpperCase(),
          style: const TextStyle(color: _muted, fontSize: 8.5, fontWeight: FontWeight.w700, letterSpacing: .5)),
    ]),
  );

  Widget _rowFact(String k, String v) => Container(
    margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(12)),
    child: Row(children: [
      Text(k, style: const TextStyle(color: _muted, fontSize: 12)),
      const Spacer(),
      Text(v, style: const TextStyle(color: _text, fontSize: 13, fontWeight: FontWeight.w800)),
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
          detail: 'Admin tools stay closed until it loads.',
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
