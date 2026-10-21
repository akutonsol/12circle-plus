import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/compliance_service.dart';
import '../domain/compliance_provider.dart';
import '../../dashboard/presentation/client_detail_screen.dart';

const _bg       = Color(0xFF030303);
const _card     = Color(0xFF0E0B16);
const _border   = Color(0xFF1A1020);
const _brand    = Color(0xFFA855F7);
const _white    = Colors.white;
const _muted    = Color(0xFFCFC2D6);
const _onTrack  = Color(0xFF6FFBBE);
const _atRisk   = Color(0xFFFFD479);
const _offTrack = Color(0xFFFFB4AB);

Color _statusColor(String s) => switch (s) {
      'on_track' => _onTrack,
      'at_risk' => _atRisk,
      _ => _offTrack,
    };

String _statusLabel(String s) => switch (s) {
      'on_track' => 'On Track',
      'at_risk' => 'At Risk',
      _ => 'Off Track',
    };

/// Module 30 — Compliance Dashboard.
/// Coach sees every active client ranked worst-adherence-first, with the
/// signals that drove it, and taps through to the full client detail.
class ComplianceDashboardScreen extends ConsumerWidget {
  const ComplianceDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rosterAsync = ref.watch(complianceRosterProvider);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        title: const Text('Compliance',
            style: TextStyle(color: _white, fontWeight: FontWeight.w700)),
        iconTheme: const IconThemeData(color: _white),
      ),
      body: rosterAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: _brand)),
        error: (e, _) => Center(
            child: Text('Could not load compliance.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted))),
        data: (roster) {
          if (roster.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No active clients yet.\nAdherence appears here once clients are on your roster.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _muted, height: 1.4),
                ),
              ),
            );
          }
          return RefreshIndicator(
            color: _brand,
            backgroundColor: _card,
            onRefresh: () async => ref.invalidate(complianceRosterProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _SummaryStrip(roster: roster),
                const SizedBox(height: 16),
                ...roster.map((c) => _ClientComplianceCard(summary: c)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  final List<ComplianceSummary> roster;
  const _SummaryStrip({required this.roster});

  @override
  Widget build(BuildContext context) {
    final on = roster.where((c) => c.status == 'on_track').length;
    final risk = roster.where((c) => c.status == 'at_risk').length;
    final off = roster.where((c) => c.status == 'off_track').length;
    return Row(
      children: [
        _stat('On Track', on, _onTrack),
        const SizedBox(width: 10),
        _stat('At Risk', risk, _atRisk),
        const SizedBox(width: 10),
        _stat('Off Track', off, _offTrack),
      ],
    );
  }

  Widget _stat(String label, int value, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border),
          ),
          child: Column(
            children: [
              Text('$value',
                  style: TextStyle(
                      color: color,
                      fontSize: 24,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(label,
                  style: const TextStyle(color: _muted, fontSize: 11)),
            ],
          ),
        ),
      );
}

class _ClientComplianceCard extends StatelessWidget {
  final ComplianceSummary summary;
  const _ClientComplianceCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(summary.status);
    final pct = summary.compliance.round();

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ClientDetailScreen(
                  clientId: summary.clientId, clientName: summary.name))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _ComplianceRing(pct: pct, color: color),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(summary.name,
                          style: const TextStyle(
                              color: _white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(_statusLabel(summary.status),
                            style: TextStyle(
                                color: color,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: _muted),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _signal(
                    Icons.bolt, 'Avg score', summary.avgScore.round().toString()),
                _signal(Icons.fitness_center, 'Workouts/wk',
                    '${summary.workoutsThisWeek}'),
                _signal(
                    Icons.event_available,
                    'Check-in',
                    summary.daysSinceCheckin == null
                        ? 'never'
                        : '${summary.daysSinceCheckin}d ago'),
                if (summary.actionCompletion != null)
                  _signal(Icons.checklist, 'Actions',
                      '${(summary.actionCompletion! * 100).round()}%'),
                if (summary.goalsTotal > 0)
                  _signal(Icons.flag, 'Goals',
                      '${summary.goalsOnTrack}/${summary.goalsTotal}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _signal(IconData icon, String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: _muted),
            const SizedBox(width: 6),
            Text('$label  ',
                style: const TextStyle(color: _muted, fontSize: 11)),
            Text(value,
                style: const TextStyle(
                    color: _white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

class _ComplianceRing extends StatelessWidget {
  final int pct;
  final Color color;
  const _ComplianceRing({required this.pct, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              value: pct / 100,
              strokeWidth: 5,
              backgroundColor: _border,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          Text('$pct',
              style: TextStyle(
                  color: color, fontSize: 14, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
