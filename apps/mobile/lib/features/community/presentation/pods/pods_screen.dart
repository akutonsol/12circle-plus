import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
const _bg    = Color(0xFF030303);
const _card  = Color(0xFF0E0B16);
const _brd   = Color(0xFF1A1020);
const _brand = Color(0xFFA855F7);
const _pri   = Color(0xFFDDB7FF);
const _tert  = Color(0xFF6FFBBE);
const _wht   = Colors.white;
const _mut   = Color(0xFFCFC2D6);

// ── UC34: Accountability Pods ─────────────────────────────────────────────────
class PodsScreen extends StatefulWidget {
  const PodsScreen({super.key});
  @override
  State<PodsScreen> createState() => _PodsScreenState();
}

class _PodsScreenState extends State<PodsScreen> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _myPods = [];
  List<Map<String, dynamic>> _openPods = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uid = _db.auth.currentUser?.id;
      final [mine, open] = await Future.wait([
        _db.from('accountability_pods')
            .select('*, accountability_pod_members!inner(user_id), public_profiles!coach_id(first_name, last_name)')
            .eq('accountability_pod_members.user_id', uid!),
        _db.from('accountability_pods')
            .select('*, public_profiles!coach_id(first_name, last_name)')
            .eq('status', 'open')
            .limit(10),
      ]);
      if (!mounted) return;
      setState(() {
        _myPods = List<Map<String, dynamic>>.from(mine as List);
        _openPods = List<Map<String, dynamic>>.from(open as List);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; });
    }
  }

  Future<void> _joinPod(String podId) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await _db.from('accountability_pod_members').insert({'pod_id': podId, 'user_id': uid});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Joined pod! Welcome to your accountability group 🙌'),
          backgroundColor: Color(0xFF6FFBBE)));
        _load();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _card, elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _wht, size: 20),
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context)),
        title: const Text('Accountability Pods',
          style: TextStyle(color: _wht, fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _brand))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _Section('What are Pods?', child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _brand.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _brand.withValues(alpha: 0.3))),
                  child: const Text(
                    'Accountability pods are small groups of 4–8 clients who support each other daily. Share wins, check in, and keep each other on track.',
                    style: TextStyle(color: _pri, fontSize: 13, height: 1.5)),
                )),
                const SizedBox(height: 24),
                if (_myPods.isNotEmpty) ...[
                  _Section('My Pods', child: Column(
                    children: _myPods.map((p) => _PodCard(pod: p, isJoined: true, onJoin: null)).toList(),
                  )),
                  const SizedBox(height: 24),
                ],
                _Section('Open Pods', child: _openPods.isEmpty
                    ? const _EmptyPods()
                    : Column(
                        children: _openPods.map((p) {
                          final alreadyIn = _myPods.any((m) => m['id'] == p['id']);
                          return _PodCard(
                            pod: p, isJoined: alreadyIn,
                            onJoin: alreadyIn ? null : () => _joinPod(p['id'] as String));
                        }).toList(),
                      )),
              ]),
            ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section(this.title, {required this.child});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title, style: const TextStyle(color: _wht, fontSize: 16, fontWeight: FontWeight.w700)),
    const SizedBox(height: 12),
    child,
  ]);
}

class _PodCard extends StatelessWidget {
  final Map<String, dynamic> pod;
  final bool isJoined;
  final VoidCallback? onJoin;
  const _PodCard({required this.pod, required this.isJoined, required this.onJoin});

  @override
  Widget build(BuildContext context) {
    final members = pod['member_count'] as int? ?? 0;
    final maxMembers = pod['max_members'] as int? ?? 8;
    final coachProfile = pod['public_profiles'] as Map<String, dynamic>? ?? {};
    final coachName = '${coachProfile['first_name'] ?? 'Coach'} ${coachProfile['last_name'] ?? ''}'.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isJoined ? _tert.withValues(alpha: 0.4) : _brd)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: _brand.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.group_rounded, color: _brand, size: 24)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(pod['name'] as String? ?? 'Accountability Pod',
              style: const TextStyle(color: _wht, fontSize: 15, fontWeight: FontWeight.w700)),
            Text('Led by $coachName', style: const TextStyle(color: _mut, fontSize: 12)),
          ])),
          if (isJoined)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _tert.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
              child: const Text('Joined', style: TextStyle(color: _tert, fontSize: 11, fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 12),
        Text(pod['description'] as String? ?? 'Daily accountability and support group',
          style: const TextStyle(color: _mut, fontSize: 13)),
        const SizedBox(height: 12),
        Row(children: [
          _Tag(Icons.people_rounded, '$members/$maxMembers members'),
          const SizedBox(width: 8),
          _Tag(Icons.schedule_rounded, pod['meeting_frequency'] as String? ?? 'Daily check-ins'),
          const Spacer(),
          if (onJoin != null)
            ElevatedButton(
              onPressed: onJoin,
              style: ElevatedButton.styleFrom(
                backgroundColor: _brand, foregroundColor: _wht,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: const Text('Join', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
        ]),
      ]),
    );
  }
}

class _Tag extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Tag(this.icon, this.label);
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, color: _mut, size: 13),
    const SizedBox(width: 4),
    Text(label, style: const TextStyle(color: _mut, fontSize: 11)),
  ]);
}

class _EmptyPods extends StatelessWidget {
  const _EmptyPods();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16), border: Border.all(color: _brd)),
    child: const Center(child: Column(children: [
      Text('🫂', style: TextStyle(fontSize: 40)),
      SizedBox(height: 12),
      Text('No open pods yet', style: TextStyle(color: _wht, fontSize: 15, fontWeight: FontWeight.w700)),
      SizedBox(height: 4),
      Text('Your coach will create accountability groups soon. Check back later!',
        style: TextStyle(color: _mut, fontSize: 13), textAlign: TextAlign.center),
    ])),
  );
}
