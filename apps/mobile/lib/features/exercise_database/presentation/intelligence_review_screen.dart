// Per-Attribute Knowledge Review — the editorial workflow for intelligence
// profiles. Instead of approve/reject the whole profile, the reviewer sees each
// attribute group with its AI confidence and acts on it independently, then
// Finalizes. Since migration 187 NOTHING auto-passes: the profile is approved
// only when a content editor has approved every one of the eight attribute
// groups as it currently stands — AI confidence is shown for prioritising, never
// counted as review. An attribute edited after approval reads "stale" and must be
// reviewed again. Admin / content-manager.
import 'dart:convert';
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

class IntelligenceReviewScreen extends ConsumerStatefulWidget {
  const IntelligenceReviewScreen({super.key});
  @override
  ConsumerState<IntelligenceReviewScreen> createState() => _State();
}

class _State extends ConsumerState<IntelligenceReviewScreen> {
  final _svc = CustomExerciseService();
  List<Map<String, dynamic>>? _queue;
  bool _loading = true, _notMigrated = false, _busy = false;
  int _i = 0, _reviewed = 0;
  Map<String, dynamic>? _attrs; // attribute_review_state of current profile
  String? _attrsFor;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final q = await _svc.intelligenceReviewQueue(limit: 100);
    if (!mounted) return;
    setState(() {
      _loading = false; _notMigrated = q == null; _queue = q ?? []; _i = 0;
      _attrs = null; _attrsFor = null;
    });
  }

  void _ensureAttrs(String id) {
    if (_attrsFor == id) return;
    _attrsFor = id; _attrs = null;
    _svc.attributeReviewState(id).then((a) {
      if (mounted && _attrsFor == id) setState(() => _attrs = a);
    });
  }

  Future<void> _act(String exerciseId, String attribute, String status, {String? fingerprint}) async {
    setState(() => _busy = true);
    final ok = await _svc.reviewAttribute(exerciseId, attribute, status, fingerprint: fingerprint);
    // Refresh either way: after a refusal the value shown may be stale.
    _attrsFor = null; _ensureAttrs(exerciseId);
    if (mounted) setState(() => _busy = false);
    if (!ok && mounted && '${_svc.lastError}'.contains('INTEL_REVIEW_VALUE_CHANGED')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(
          'This attribute changed while you were reviewing it. Nothing was approved — '
          'the current value is shown now; review it again.')));
    } else if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Action failed — check permissions / migration 091.')));
    }
  }

  Future<void> _finalize(String exerciseId) async {
    setState(() => _busy = true);
    final status = await _svc.finalizeIntelligence(exerciseId);
    if (!mounted) return;
    setState(() { _busy = false; if (status != null) { _reviewed++; _i++; _attrsFor = null; _attrs = null; } });
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
        title: const Text('Knowledge Review', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _loading ? null : _load)]),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _brand))
          : _notMigrated
              ? _banner('Apply migration 091 to enable per-attribute knowledge review.')
              : (_queue == null || _i >= _queue!.length)
                  ? _empty()
                  : _profile(_queue![_i]),
    );
  }

  Widget _banner(String m) => Center(child: Padding(padding: const EdgeInsets.all(28),
    child: Text(m, textAlign: TextAlign.center, style: const TextStyle(color: _muted, fontSize: 13))));

  Widget _empty() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.verified_rounded, color: _pass, size: 44), const SizedBox(height: 12),
    Text(_reviewed > 0 ? 'Queue cleared — $_reviewed profiles finalized 🎉' : 'No profiles awaiting review',
        style: const TextStyle(color: _text, fontSize: 16, fontWeight: FontWeight.w700)),
  ]));

  Widget _profile(Map<String, dynamic> p) {
    final id = p['exercise_id'] as String;
    _ensureAttrs(id);
    final attrs = _attrs;
    final entries = (attrs ?? {}).entries.toList()
      ..sort((a, b) => ((a.value as Map)['confidence'] as num).compareTo((b.value as Map)['confidence'] as num));
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 6), child: Row(children: [
        Text('${_i + 1} of ${_queue!.length}', style: const TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w700)),
        const Spacer(),
        Text('overall ${p['confidence'] ?? '—'}%  ·  ${p['low_conf_count'] ?? 0} to review',
            style: const TextStyle(color: _muted, fontSize: 12)),
      ])),
      Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(16, 6, 16, 16), children: [
        Text(p['name']?.toString() ?? '—',
            style: const TextStyle(color: _text, fontSize: 22, fontWeight: FontWeight.w900)),
        Text('status: ${p['status'] ?? '—'}', style: const TextStyle(color: _muted, fontSize: 12)),
        const SizedBox(height: 14),
        if (attrs == null) const Center(child: Padding(padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(color: _brand)))
        else ...entries.map((e) => _attrCard(id, e.key, e.value as Map)),
      ])),
      _finalizeBar(id),
    ]);
  }

  Widget _attrCard(String id, String attr, Map state) {
    final conf = (state['confidence'] as num?)?.toInt() ?? 0;
    final rs = state['review_status']?.toString() ?? 'pending';
    final c = conf >= 90 ? _pass : (conf >= 70 ? _warn : _fail);
    final resolved = rs == 'auto' || rs == 'approved';
    final rejected = rs == 'rejected' || rs == 'needs_edit';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _panel, borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(
          color: resolved ? _pass : (rejected ? _fail : _warn), width: 3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(attr.replaceAll('_', ' '),
              style: const TextStyle(color: _text, fontSize: 14, fontWeight: FontWeight.w700))),
          Text('$conf%', style: TextStyle(color: c, fontSize: 13, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: conf / 100, minHeight: 5, backgroundColor: _panel2, color: c)),
        // The value under review (187). Before this the reviewer saw only the
        // model's confidence, so an approval was not tied to anything they read.
        if (state['value'] != null) ...[
          const SizedBox(height: 8),
          Text(const JsonEncoder.withIndent('  ').convert(state['value']),
              style: const TextStyle(color: _text, fontSize: 11.5, fontFamily: 'monospace')),
        ],
        const SizedBox(height: 8),
        Row(children: [
          _statusTag(rs),
          const Spacer(),
          if (rs == 'auto')
            const Text('auto-passed (high confidence)', style: TextStyle(color: _muted, fontSize: 10.5))
          else ...[
            // 187: an approval names the exact value shown above; no value, no approve.
            if (state['fingerprint'] is String)
              _mini('Approve', _pass, () => _act(id, attr, 'approved',
                  fingerprint: state['fingerprint'] as String)),
            const SizedBox(width: 6),
            _mini('Edit', _warn, () => _act(id, attr, 'needs_edit')),
            const SizedBox(width: 6),
            _mini('Reject', _fail, () => _act(id, attr, 'rejected')),
          ],
        ]),
      ]),
    );
  }

  Widget _statusTag(String rs) {
    final col = switch (rs) {
      'auto' || 'approved' => _pass, 'rejected' || 'needs_edit' => _fail, _ => _warn,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: col.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(8)),
      child: Text(rs, style: TextStyle(color: col, fontSize: 10, fontWeight: FontWeight.w800)),
    );
  }

  Widget _mini(String label, Color col, VoidCallback onTap) => GestureDetector(
    onTap: _busy ? null : onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: col.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8),
          border: Border.all(color: col.withValues(alpha: 0.4))),
      child: Text(label, style: TextStyle(color: col, fontSize: 11, fontWeight: FontWeight.w800)),
    ),
  );

  Widget _finalizeBar(String id) => Container(
    padding: EdgeInsets.fromLTRB(12, 10, 12, 12 + MediaQuery.of(context).padding.bottom),
    decoration: const BoxDecoration(color: _panel2),
    child: Row(children: [
      Expanded(child: GestureDetector(
        onTap: _busy ? null : () => _finalize(id),
        child: Container(
          alignment: Alignment.center, padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(color: _brand, borderRadius: BorderRadius.circular(12)),
          child: const Text('Finalize profile', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
        ),
      )),
    ]),
  );
}
