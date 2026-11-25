import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/observability/app_failure.dart';
import '../../../workout/presentation/widgets/section_load_failure.dart';

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
  bool _loading = false;

  /// Whose pods these are (P0-FL-60c); null when nobody is signed in.
  String? _owner;

  /// One per account shown: an answer that started under another one is
  /// dropped, even when the same member is back.
  int _epoch = 0;

  /// [_owner]'s pods were read. Until then the empty lists are not "none".
  bool _loaded = false;
  Object? _loadError;

  /// The latest read; an older one still in flight is dropped.
  int _loadSeq = 0;

  /// The pod being joined; one at a time.
  String? _joining;

  /// Who is signed in is followed here, without a frame: an answer can land
  /// while the app is hidden.
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _owner = _db.auth.currentUser?.id;
    _authSub = _db.auth.onAuthStateChange.listen((_) => _followAccount(),
        onError: (Object e, StackTrace st) =>
            reportError('PodsScreen.onAuthStateChange', e, st));
    _load();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  /// Whether [owner] is still the one signed in, and the one shown. Otherwise
  /// the screen follows whoever is.
  bool _still(String? owner) {
    if (owner != null &&
        owner == _owner &&
        _db.auth.currentUser?.id == owner) {
      return true;
    }
    _followAccount();
    return false;
  }

  /// Nothing of the previous member's stays, and the next one's are read.
  void _followAccount() {
    if (!mounted) return;
    final uid = _db.auth.currentUser?.id;
    if (uid == _owner) return;
    setState(() {
      _owner = uid;
      _epoch++;
      _myPods = [];
      _openPods = [];
      _loaded = false;
      _loading = false;
      _loadError = null;
      _joining = null;
    });
    _load();
  }

  /// [again]: what is on its way may predate a change just made.
  Future<void> _load({bool again = false}) async {
    final owner = _owner;
    if (owner == null || (_loading && !again) || !_still(owner)) return;
    final seq = ++_loadSeq;
    setState(() => _loading = true);
    try {
      final [mine, open] = await Future.wait([
        _db.from('accountability_pods')
            .select('*, accountability_pod_members!inner(user_id), public_profiles!coach_id(first_name, last_name)')
            .eq('accountability_pod_members.user_id', owner),
        _db.from('accountability_pods')
            .select('*, public_profiles!coach_id(first_name, last_name)')
            .eq('status', 'open')
            .limit(10),
      ]);
      if (!mounted || seq != _loadSeq || !_still(owner)) return;
      setState(() {
        _myPods = List<Map<String, dynamic>>.from(mine as List);
        _openPods = List<Map<String, dynamic>>.from(open as List);
        _loaded = true;
        _loadError = null;
        _loading = false;
      });
    } catch (e, st) {
      // Not "no pods": said as a failure, over whatever was read before.
      reportError('PodsScreen.load', e, st);
      if (!mounted || seq != _loadSeq || !_still(owner)) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  /// [owner]: who the Join button was built for. Nothing is sent, read again
  /// or said once they are no longer the one signed in.
  Future<void> _joinPod(Map<String, dynamic> pod, String? owner) async {
    if (!_still(owner)) return _accountChanged();
    if (_joining != null) return;
    final epoch = _epoch;
    final podId = pod['id'] as String;
    setState(() => _joining = podId);
    Object? error;
    try {
      await _db.from('accountability_pod_members').insert({'pod_id': podId, 'user_id': owner});
    } catch (e, st) {
      reportError('PodsScreen.joinPod', e, st);
      error = e;
    }
    if (!mounted) return;
    if (epoch != _epoch || !_still(owner)) return _accountChanged();
    if (error == null) {
      // The server took it: theirs, even if the read that follows fails.
      setState(() => _myPods = [..._myPods, pod]);
      _say('Joined pod! Welcome to your accountability group 🙌',
          background: const Color(0xFF6FFBBE));
    }
    // "Already a member" (23505) is answered by the pods themselves.
    final duplicate = error is PostgrestException && error.code == '23505';
    if (error == null || duplicate) await _load(again: true);
    if (!mounted) return;
    if (epoch != _epoch || !_still(owner)) return _accountChanged();
    setState(() => _joining = null);
    if (error == null) return;
    if (!duplicate) {
      _say(couldntMessage('join that pod', error));
    } else if (!_myPods.any((m) => m['id'] == podId)) {
      // The pods were not read (said above them), so the answer is said here;
      // or they were, and it is not among them.
      _say(_loadError != null
          ? "You're already in that pod."
          : couldntMessage('join that pod', error));
    }
  }

  void _accountChanged() => reportError(
      'PodsScreen.joinPod',
      StateError('joining a pod: the signed-in account changed'),
      StackTrace.current);

  void _say(String message, {Color? background}) =>
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: background));

  @override
  Widget build(BuildContext context) {
    final error = _loadError;
    final owner = _owner;
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
      body: _loading && !_loaded && error == null
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
                if (error != null) ...[
                  SectionLoadFailure(
                    what: _loaded ? 'the latest pods' : 'your pods',
                    error: error,
                    busy: _loading,
                    onRetry: () => _load()),
                  const SizedBox(height: 24),
                ],
                if (_myPods.isNotEmpty) ...[
                  _Section('My Pods', child: Column(
                    children: _myPods.map((p) => _PodCard(pod: p, isJoined: true, onJoin: null)).toList(),
                  )),
                  const SizedBox(height: 24),
                ],
                if (_loaded) _Section('Open Pods', child: _openPods.isEmpty
                    ? const _EmptyPods()
                    : Column(
                        children: _openPods.map((p) {
                          final alreadyIn = _myPods.any((m) => m['id'] == p['id']);
                          return _PodCard(
                            pod: p, isJoined: alreadyIn,
                            busy: _joining != null,
                            joining: _joining == p['id'],
                            onJoin: alreadyIn ? null : () => _joinPod(p, owner));
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

  /// A join is in flight ([joining]: this pod's); no other can start.
  final bool busy;
  final bool joining;
  const _PodCard({
    required this.pod, required this.isJoined, required this.onJoin,
    this.busy = false, this.joining = false});

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
              onPressed: busy ? null : onJoin,
              style: ElevatedButton.styleFrom(
                backgroundColor: _brand, foregroundColor: _wht,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: joining
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2, color: _wht, semanticsLabel: 'Joining'))
                  : const Text('Join', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
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
