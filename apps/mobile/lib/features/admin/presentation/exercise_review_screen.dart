import 'package:flutter/material.dart';
import '../../exercise_database/data/custom_exercise_service.dart';
import '../../exercise_database/data/models/exercise_detail_model.dart';
import '../../workout/presentation/widgets/section_load_failure.dart';

const _bg    = Color(0xFF0B0712);
const _card  = Color(0xFF171026);
const _brand = Color(0xFFB76DFF);
const _mint  = Color(0xFF6FFBBE);
const _white = Color(0xFFEDE7F3);
const _muted = Color(0xFFB6A9C4);
const _danger = Color(0xFFFFB4AB);

/// Admin review queue for the Global Exercise Library (EL-005). Lists coach
/// submissions awaiting approval; admin can approve (→ global) or reject.
class ExerciseReviewScreen extends StatefulWidget {
  const ExerciseReviewScreen({super.key});
  @override
  State<ExerciseReviewScreen> createState() => _ExerciseReviewScreenState();
}

class _ExerciseReviewScreenState extends State<ExerciseReviewScreen> {
  final _svc = CustomExerciseService();
  late Future<List<ExerciseDetail>> _future;
  final _busy = <String>{};

  /// The last read's failure (kept while a retry is in flight, so the notice
  /// stays on screen, busy, instead of blinking to a spinner).
  Object? _failedWith;
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    _future = _read();
  }

  Future<List<ExerciseDetail>> _read() {
    final f = _svc.getPendingGlobalSubmissions();
    f.then<void>((_) { _failedWith = null; }, onError: (Object e) { _failedWith = e; });
    return f;
  }

  /// Re-reads the queue; returns when the read settles. Its failure is shown
  /// by the builder, not thrown.
  Future<void> _reload() {
    final f = _read();
    setState(() { _future = f; });
    return f.then((_) {}, onError: (_) {});
  }

  /// The notice's retry: busy until the read settles, so it can't double fire.
  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    await _reload();
    if (mounted) setState(() => _retrying = false);
  }

  Future<void> _moderate(ExerciseDetail ex, bool approve) async {
    setState(() => _busy.add(ex.id));
    final ok = approve
        ? await _svc.approveGlobalExercise(ex.id)
        : await _svc.rejectGlobalExercise(ex.id);
    if (!mounted) return;
    setState(() => _busy.remove(ex.id));
    // P0-FL-50a · the service has recorded the failure (a 0-row update
    // included); the admin is told which action did not happen.
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? (approve ? '"${ex.name}" approved to the global library.'
                     : '"${ex.name}" rejected.')
          : couldntMessage(
              approve ? 'approve "${ex.name}"' : 'reject "${ex.name}"',
              _svc.lastError))));
    if (ok) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: _white,
        title: const Text('Global Library Review',
          style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: FutureBuilder<List<ExerciseDetail>>(
        future: _future,
        builder: (context, snap) {
          final waiting = snap.connectionState == ConnectionState.waiting;
          // P0-FL-50a · a failed read is not "No pending submissions"; while
          // its retry runs, the notice stays (busy).
          final failure = snap.hasError
              ? snap.error
              : (waiting && _retrying ? _failedWith : null);
          if (snap.hasError || failure != null) {
            return Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: SectionLoadFailure(
                what: 'the submissions',
                error: failure,
                busy: _retrying,
                onRetry: _retry,
                accent: _brand,
                textColor: _white,
                mutedColor: _muted),
            ));
          }
          if (waiting) {
            return const Center(child: CircularProgressIndicator(color: _brand));
          }
          final pending = snap.data ?? [];
          if (pending.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView(children: const [
                SizedBox(height: 160),
                Icon(Icons.inbox_outlined, color: _muted, size: 48),
                SizedBox(height: 12),
                Center(child: Text('No pending submissions.',
                  style: TextStyle(color: _muted, fontSize: 15))),
              ]),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: pending.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _card_(pending[i]),
            ),
          );
        },
      ),
    );
  }

  Widget _card_(ExerciseDetail ex) {
    final busy = _busy.contains(ex.id);
    final hasVideo = ex.videoUrl != null || ex.videoVariants.isNotEmpty;
    final hasImage = ex.imageUrl != null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _brand.withValues(alpha: 0.18))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(ex.name, style: const TextStyle(color: _white, fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('${ex.muscleGroup} · ${ex.equipment} · ${ex.difficulty}',
          style: const TextStyle(color: _muted, fontSize: 12.5)),
        if (ex.description.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(ex.description, maxLines: 3, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _white, fontSize: 13, height: 1.4)),
        ],
        const SizedBox(height: 10),
        Row(children: [
          if (hasVideo) _chip(Icons.videocam_rounded, 'Video'),
          if (hasImage) _chip(Icons.image_rounded, 'Image'),
          if (ex.instructions.isNotEmpty) _chip(Icons.list_alt_rounded, '${ex.instructions.length} steps'),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: busy ? null : () => _moderate(ex, false),
            style: OutlinedButton.styleFrom(
              foregroundColor: _danger,
              side: BorderSide(color: _danger.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(vertical: 12)),
            child: const Text('Reject', style: TextStyle(fontWeight: FontWeight.w700)))),
          const SizedBox(width: 10),
          Expanded(child: ElevatedButton(
            onPressed: busy ? null : () => _moderate(ex, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _mint, foregroundColor: Colors.black87,
              padding: const EdgeInsets.symmetric(vertical: 12)),
            child: busy
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black87))
                : const Text('Approve', style: TextStyle(fontWeight: FontWeight.w700)))),
        ]),
      ]),
    );
  }

  Widget _chip(IconData icon, String label) => Container(
    margin: const EdgeInsets.only(right: 8),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: _brand.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: _brand, size: 13),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(color: _brand, fontSize: 11, fontWeight: FontWeight.w600)),
    ]),
  );
}
