import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../data/workout_service.dart';
import '../domain/workout_provider.dart';

class _C {
  static const card                 = Color(0xFF131314);
  static const cardBorder           = Color(0xFF1A1020);
  static const elevated             = Color(0xFF201F20);
  static const primary              = Color(0xFFDDB7FF);
  static const brand                = Color(0xFFA855F7);
  static const inversePrimary       = Color(0xFF842BD2);
  static const onSurface            = Color(0xFFE5E2E3);
  static const muted                = Color(0xFFCFC2D6);
  static const tertiary             = Color(0xFF6FFBBE);
  static const outline              = Color(0xFF968E99);
  static const outlineVar           = Color(0xFF4B444F);
}

// Provider for per-session set logs (keyed by sessionId)
final _sessionLogsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>(
  (ref, sessionId) async {
    return WorkoutService().getSessionSetLogs(sessionId);
  },
);

class WorkoutHistoryScreen extends ConsumerWidget {
  const WorkoutHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(workoutHistoryProvider);

    return AppScaffold(
      showBackButton: true,
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Header ──
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Workout History',
              style: TextStyle(color: _C.onSurface, fontSize: 28,
                fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            const SizedBox(height: 4),
            Text('All completed sessions', style: TextStyle(
              color: _C.muted.withValues(alpha: 0.6), fontSize: 13)),
          ])),

        // ── Sessions list ──
        Expanded(
          child: historyAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: _C.brand, strokeWidth: 2)),
            error: (e, _) => Center(
              child: Text('Could not load history',
                style: TextStyle(color: _C.muted.withValues(alpha: 0.5)))),
            data: (sessions) => sessions.isEmpty
                ? _EmptyState()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                    itemCount: sessions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (ctx, i) =>
                        _SessionCard(session: sessions[i])),
          )),
      ]),
    );
  }
}

// ── Session card ──────────────────────────────────────────────────────────────
class _SessionCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> session;
  const _SessionCard({required this.session});
  @override
  ConsumerState<_SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends ConsumerState<_SessionCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final title = s['workout_title'] as String? ?? 'Workout';
    final completedAt = s['completed_at'] as String?;
    final duration = s['duration_seconds'] as int? ?? 0;
    final calories = s['calories_burned'] as int? ?? 0;
    final sessionId = s['id'] as String;

    final date = completedAt != null
        ? _formatDate(DateTime.parse(completedAt))
        : 'Unknown date';
    final durationStr = '${duration ~/ 60}:${(duration % 60).toString().padLeft(2, '0')}';

    return Container(
      decoration: BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.cardBorder)),
      child: Column(children: [
        // Card header
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: _C.brand.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _C.brand.withValues(alpha: 0.3))),
                child: const Icon(Icons.fitness_center, color: _C.brand, size: 22)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                    style: const TextStyle(color: _C.onSurface, fontSize: 15,
                      fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(date, style: TextStyle(
                    color: _C.muted.withValues(alpha: 0.6), fontSize: 12)),
                ])),
              // Stats chips
              Row(children: [
                _MiniChip(icon: Icons.timer_outlined, label: durationStr, color: _C.primary),
                const SizedBox(width: 8),
                _MiniChip(icon: Icons.local_fire_department_outlined,
                  label: '$calories', color: _C.tertiary),
              ]),
              const SizedBox(width: 8),
              Icon(_expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                color: _C.outline, size: 20),
            ]))),

        // Expanded set logs
        if (_expanded) _SessionLogs(sessionId: sessionId),
      ]));
  }

  String _formatDate(DateTime dt) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

// ── Set log expansion ─────────────────────────────────────────────────────────
class _SessionLogs extends ConsumerWidget {
  final String sessionId;
  const _SessionLogs({required this.sessionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(_sessionLogsProvider(sessionId));
    return logsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: SizedBox(width: 20, height: 20,
          child: CircularProgressIndicator(color: _C.brand, strokeWidth: 2)))),
      error: (_, __) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Failed to load sets',
          style: TextStyle(color: _C.muted.withValues(alpha: 0.5), fontSize: 12))),
      data: (logs) {
        if (logs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text('No per-set data recorded',
              style: TextStyle(color: _C.muted.withValues(alpha: 0.5), fontSize: 12)));
        }
        // Group by exercise_name
        final grouped = <String, List<Map<String, dynamic>>>{};
        for (final log in logs) {
          final name = log['exercise_name'] as String? ?? 'Exercise';
          grouped.putIfAbsent(name, () => []).add(log);
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Divider(color: _C.outlineVar.withValues(alpha: 0.4)),
              const SizedBox(height: 8),
              ...grouped.entries.map((entry) => _ExerciseLogSection(
                name: entry.key, sets: entry.value)),
            ]));
      });
  }
}

class _ExerciseLogSection extends StatelessWidget {
  final String name;
  final List<Map<String, dynamic>> sets;
  const _ExerciseLogSection({required this.name, required this.sets});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, style: const TextStyle(color: _C.primary,
          fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        // Header
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(children: [
            SizedBox(width: 40,
              child: Text('SET', style: TextStyle(
                color: _C.muted.withValues(alpha: 0.4), fontSize: 9,
                fontWeight: FontWeight.w700, letterSpacing: 1))),
            Expanded(child: Text('WEIGHT', textAlign: TextAlign.center,
              style: TextStyle(color: _C.muted.withValues(alpha: 0.4), fontSize: 9,
                fontWeight: FontWeight.w700, letterSpacing: 1))),
            Expanded(child: Text('REPS', textAlign: TextAlign.center,
              style: TextStyle(color: _C.muted.withValues(alpha: 0.4), fontSize: 9,
                fontWeight: FontWeight.w700, letterSpacing: 1))),
            Expanded(child: Text('RPE', textAlign: TextAlign.center,
              style: TextStyle(color: _C.muted.withValues(alpha: 0.4), fontSize: 9,
                fontWeight: FontWeight.w700, letterSpacing: 1))),
          ])),
        // Rows
        ...sets.map((set) {
          final setNum = set['set_number'] as int? ?? 0;
          final weight = set['weight_kg'];
          final reps = set['reps'] as int? ?? 0;
          final rpe = set['rpe'];
          final notes = set['notes'] as String?;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              margin: const EdgeInsets.only(bottom: 2),
              decoration: BoxDecoration(
                color: _C.elevated,
                borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                SizedBox(width: 40,
                  child: Text('$setNum',
                    style: const TextStyle(color: _C.tertiary, fontSize: 13,
                      fontWeight: FontWeight.w700))),
                Expanded(child: Text(
                  weight != null ? '${weight}kg' : '—',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _C.onSurface, fontSize: 13))),
                Expanded(child: Text('$reps',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _C.onSurface, fontSize: 13))),
                Expanded(child: Text(
                  rpe != null ? '$rpe' : '—',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _C.onSurface, fontSize: 13))),
              ])),
            if (notes != null && notes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 48, bottom: 4),
                child: Text('↳ $notes',
                  style: TextStyle(color: _C.muted.withValues(alpha: 0.5),
                    fontSize: 11, fontStyle: FontStyle.italic))),
          ]);
        }),
      ]));
  }
}

// ── Mini chip ────────────────────────────────────────────────────────────────
class _MiniChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _MiniChip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: color, size: 13),
      const SizedBox(width: 3),
      Text(label, style: TextStyle(color: color, fontSize: 11,
        fontWeight: FontWeight.w600)),
    ]);
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.fitness_center, color: _C.brand.withValues(alpha: 0.3), size: 56),
        const SizedBox(height: 16),
        const Text('No workouts yet',
          style: TextStyle(color: _C.onSurface, fontSize: 18,
            fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('Complete your first workout to see it here',
          style: TextStyle(color: _C.muted.withValues(alpha: 0.5), fontSize: 13)),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: () => context.go('/workouts'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                colors: [_C.inversePrimary, _C.brand],
                begin: Alignment.topLeft, end: Alignment.bottomRight)),
            child: const Text('Browse Workouts',
              style: TextStyle(color: Colors.white, fontSize: 14,
                fontWeight: FontWeight.w700)))),
      ]));
  }
}
