import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/workout_provider.dart';
import '../../../core/widgets/named_icon_button.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
const _bg      = Color(0xFF030303);
const _card    = Color(0xFF0E0B16);
const _border  = Color(0xFF1A1020);
const _brand   = Color(0xFFA855F7);
const _primary = Color(0xFFDDB7FF);
const _white   = Colors.white;
const _muted   = Color(0xFFCFC2D6);
const _teal    = Color(0xFF6FFBBE);
const _amber   = Color(0xFFFFD580);
const _error   = Color(0xFFFFB4AB);

class CoachClientWorkoutScreen extends ConsumerStatefulWidget {
  const CoachClientWorkoutScreen({super.key});
  @override
  ConsumerState<CoachClientWorkoutScreen> createState() => _CoachClientWorkoutScreenState();
}

class _CoachClientWorkoutScreenState extends ConsumerState<CoachClientWorkoutScreen> {
  String? _expandedClientId;

  String? get _coachId => Supabase.instance.client.auth.currentUser?.id;

  @override
  Widget build(BuildContext context) {
    final coachId = _coachId;
    if (coachId == null) {
      return Scaffold(
        backgroundColor: _bg,
        body: Center(child: Text('Not logged in', style: TextStyle(color: _muted))));
    }

    final topPad = MediaQuery.of(context).padding.top;
    final statsAsync = ref.watch(clientWorkoutStatsProvider(coachId));

    return Scaffold(
      backgroundColor: _bg,
      body: Column(children: [
        // ── Header ──────────────────────────────────────────────────────────
        Container(
          padding: EdgeInsets.only(top: topPad + 12, left: 16, right: 16, bottom: 16),
          decoration: const BoxDecoration(color: _card, border: Border(bottom: BorderSide(color: _border))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              NamedIconButton(
                label: 'Back',
                onTap: () => context.pop(),
                child: const Icon(Icons.arrow_back_ios_new_rounded, color: _primary, size: 20)),
              const SizedBox(width: 14),
              const Text('Client Workout Stats',
                style: TextStyle(color: _white, fontSize: 20, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 4),
            Text('Training overview across all active clients',
              style: TextStyle(color: _muted.withValues(alpha: 0.6), fontSize: 12)),
          ])),

        // ── Content ──────────────────────────────────────────────────────────
        Expanded(child: statsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: _brand)),
          error: (e, _) => Center(child: Text('Error loading stats', style: TextStyle(color: _error))),
          data: (stats) {
            if (stats.isEmpty) {
              return const _EmptyState();
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: stats.length,
              itemBuilder: (context, i) {
                final client = stats[i];
                final clientId = client['client_id'] as String? ?? '';
                final isExpanded = _expandedClientId == clientId;
                return _ClientCard(
                  client: client,
                  isExpanded: isExpanded,
                  onTap: () => setState(() =>
                    _expandedClientId = isExpanded ? null : clientId),
                );
              });
          },
        )),
      ]),
    );
  }
}

// ── Client card ───────────────────────────────────────────────────────────────
class _ClientCard extends ConsumerWidget {
  final Map<String, dynamic> client;
  final bool isExpanded;
  final VoidCallback onTap;
  const _ClientCard({required this.client, required this.isExpanded, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clientId        = client['client_id'] as String? ?? '';
    final name            = client['client_name'] as String? ?? 'Client';
    final completed       = (client['total_completed'] as int?) ?? 0;
    final inProgress      = (client['total_in_progress'] as int?) ?? 0;
    final abandoned       = (client['total_abandoned'] as int?) ?? 0;
    final completionRate  = (client['completion_rate_pct'] as num?)?.toDouble() ?? 0;
    final workoutsThisWeek = (client['workouts_this_week'] as int?) ?? 0;
    final lastWorkout     = client['last_workout_at'] as String?;

    final rateColor = completionRate >= 70 ? _teal
        : completionRate >= 40 ? _amber
        : _error;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isExpanded ? _brand.withValues(alpha: 0.4) : _border)),
      child: Column(children: [
        // ── Summary row ────────────────────────────────────────────────────
        GestureDetector(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Row(children: [
              // Avatar
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: _brand.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: _brand.withValues(alpha: 0.3))),
                child: Center(
                  child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(color: _primary, fontSize: 18, fontWeight: FontWeight.w800)))),
              const SizedBox(width: 12),
              // Name + last workout
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(color: _white, fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(_formatLastWorkout(lastWorkout),
                  style: TextStyle(color: _muted.withValues(alpha: 0.5), fontSize: 11)),
              ])),
              // Completion rate badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: rateColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: rateColor.withValues(alpha: 0.3))),
                child: Text('${completionRate.toStringAsFixed(0)}%',
                  style: TextStyle(color: rateColor, fontSize: 13, fontWeight: FontWeight.w800))),
              const SizedBox(width: 8),
              Icon(
                isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                color: _muted.withValues(alpha: 0.4), size: 20),
            ]))),

        // ── Stat chips ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(children: [
            _Chip(label: '$completed done', color: _teal),
            const SizedBox(width: 6),
            _Chip(label: '$inProgress active', color: _amber),
            const SizedBox(width: 6),
            _Chip(label: '$workoutsThisWeek this wk', color: _primary),
            if (abandoned > 0) ...[
              const SizedBox(width: 6),
              _Chip(label: '$abandoned quit', color: _error),
            ],
          ])),

        // ── Expanded: PRs + Recent Sessions ──────────────────────────────
        if (isExpanded) _ExpandedDetails(clientId: clientId, name: name),
      ]),
    );
  }

  String _formatLastWorkout(String? raw) {
    if (raw == null) return 'No workouts yet';
    try {
      final dt = DateTime.parse(raw);
      final diff = DateTime.now().difference(dt);
      if (diff.inDays == 0) return 'Today';
      if (diff.inDays == 1) return 'Yesterday';
      if (diff.inDays < 7) return '${diff.inDays} days ago';
      return '${(diff.inDays / 7).round()} weeks ago';
    } catch (_) {
      return raw.substring(0, 10);
    }
  }
}

// ── Expanded details: PRs + sessions ─────────────────────────────────────────
class _ExpandedDetails extends ConsumerWidget {
  final String clientId;
  final String name;
  const _ExpandedDetails({required this.clientId, required this.name});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prsAsync     = ref.watch(clientPersonalRecordsProvider(clientId));
    final sessionsAsync = ref.watch(clientRecentSessionsProvider(clientId));

    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF1A1020)))),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // PRs
          const Text('TOP PERSONAL RECORDS',
            style: TextStyle(color: _muted, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
          const SizedBox(height: 10),
          prsAsync.when(
            loading: () => const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: _brand, strokeWidth: 2))),
            error: (_, __) => const SizedBox(),
            data: (prs) {
              if (prs.isEmpty) {
                return Text('No personal records yet', style: TextStyle(color: _muted.withValues(alpha: 0.4), fontSize: 12));
              }
              return Column(children: prs.take(5).map((pr) {
                final exName = pr['exercise_name'] as String? ?? '';
                final weight = (pr['weight_kg'] as num?)?.toDouble() ?? 0;
                final reps   = (pr['reps'] as int?) ?? 0;
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: _amber.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _amber.withValues(alpha: 0.15))),
                  child: Row(children: [
                    const Icon(Icons.emoji_events_rounded, color: _amber, size: 14),
                    const SizedBox(width: 8),
                    Expanded(child: Text(exName, style: const TextStyle(color: _white, fontSize: 12, fontWeight: FontWeight.w600))),
                    Text('${weight.toStringAsFixed(1)}kg × $reps',
                      style: const TextStyle(color: _amber, fontSize: 12, fontWeight: FontWeight.w700)),
                  ]));
              }).toList());
            }),

          const SizedBox(height: 16),
          const Text('RECENT SESSIONS',
            style: TextStyle(color: _muted, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
          const SizedBox(height: 10),
          sessionsAsync.when(
            loading: () => const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: _brand, strokeWidth: 2))),
            error: (_, __) => const SizedBox(),
            data: (sessions) {
              if (sessions.isEmpty) {
                return Text('No sessions recorded', style: TextStyle(color: _muted.withValues(alpha: 0.4), fontSize: 12));
              }
              return Column(children: sessions.take(5).map((s) {
                final title    = s['workout_title'] as String? ?? 'Workout';
                final status   = s['status'] as String? ?? '';
                final duration = (s['duration_seconds'] as int?) ?? 0;
                final date     = s['completed_at'] as String? ?? s['started_at'] as String? ?? '';
                final statusColor = status == 'completed' ? _teal
                    : status == 'in_progress' ? _amber : _error;
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: _border.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: const TextStyle(color: _white, fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(date.length >= 10 ? date.substring(0, 10) : date,
                        style: TextStyle(color: _muted.withValues(alpha: 0.4), fontSize: 10)),
                    ])),
                    if (duration > 0)
                      Text('${duration ~/ 60}m', style: TextStyle(color: _muted.withValues(alpha: 0.6), fontSize: 11)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999)),
                      child: Text(status, style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.w700))),
                  ]));
              }).toList());
            }),
        ])));
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────
class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: 0.2))),
    child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)));
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Center(child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.group_outlined, color: _brand, size: 48),
        const SizedBox(height: 16),
        const Text('No Active Clients', style: TextStyle(color: _white, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('Your clients will appear here once they start training.',
          style: TextStyle(color: _muted.withValues(alpha: 0.6), fontSize: 13), textAlign: TextAlign.center),
      ])));
  }
}
