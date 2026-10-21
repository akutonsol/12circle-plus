import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/admin_metrics.dart';
import '../domain/admin_provider.dart';
import '../domain/admin_trust.dart';
import 'admin_chrome.dart';
import 'admin_metric_tile.dart';
import 'admin_tokens.dart';

/// V5 §185 — P5 · Operations.
///
/// Published sections, in order: `#overview` · `#releases` · `#integrations` ·
/// `#system` (`#sys-events`). The page's stated data requirements are *"releases and
/// environments; integrations health; system events"*.
///
/// **Two of those three are rulings, not builds.**
///   * `#releases` reads `admin_release_status` (173/174), which is **empty by design**:
///     the CI ingestion path is gated on `P10`'s *"installation forbidden"* constraint and
///     `CONF-D9`, neither released. So the section renders the `A11` not-recorded state and
///     says why. It also keeps the two verdicts **separate** — the owner ruled METRIC-11
///     Option 3, *"these are intentionally separate states and must not be collapsed"*.
///   * `#integrations` shows **connections**, not health. Integration health is `WI-13`
///     and waits on `PD-G01`.
///
/// `#system` reads the `admin_security_events` projection, whose categories include
/// `admin_action` and `audit_read` — the inventory's own cross-link confirms the placement:
/// *"Settings links across to Operations > System events"*.
class AdminOperationsScreen extends ConsumerWidget {
  const AdminOperationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        backgroundColor: AdminColors.colorBgCanvas,
        appBar: AppBar(
          backgroundColor: AdminColors.colorBgCanvas,
          surfaceTintColor: AdminColors.colorBgCanvas,
          elevation: 0,
          iconTheme: const IconThemeData(color: AdminColors.colorTextPrimary),
          title: const Text('Operations',
              style: TextStyle(
                color: AdminColors.colorTextPrimary,
                fontSize: AdminDims.typeSectionTitleSize,
                fontWeight: FontWeight.w500,
              )),
          // COMPONENTS.md · the 34px environment strip. Production shows NOTHING,
          // which is the design's own rule and the arm that matters most.
          bottom: AdminEnvironmentStrip(
              environment: ref.watch(adminEnvironmentProvider)),
        ),
        body: RefreshIndicator(
          color: AdminColors.colorBrandAccent,
          backgroundColor: AdminColors.colorBgSurface,
          onRefresh: () async {
            ref.invalidate(adminReleaseStatusProvider);
            ref.invalidate(adminWearableConnectionsProvider);
            ref.invalidate(adminSecurityEventsProvider);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(AdminDims.space8, AdminDims.space6,
                AdminDims.space8, AdminDims.space20),
            children: [
              _overview(ref),
              const SizedBox(height: AdminDims.space6),
              _releases(ref),
              const SizedBox(height: AdminDims.space6),
              _integrations(ref),
              const SizedBox(height: AdminDims.space6),
              _system(ref),
              const SizedBox(height: AdminDims.space6),
              // The design places a "State system" panel on People, Trust, Operations and
              // Settings. This page was the one of the four without it.
              const AdminStatesPanel(
                title: 'State system',
                implemented: 'Loading · Unavailable · Not available to your role · '
                    'Not recorded · None',
                readOnlyNote: 'This page is read-only. Nothing is changed from this '
                    'screen.',
              ),
            ],
          ),
        ),
      );

  Widget _overview(WidgetRef ref) {
    final rel = ref.watch(adminReleaseStatusProvider);
    final conn = ref.watch(adminWearableConnectionsProvider);
    return AdminCard(
      title: 'Overview',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          rel.when(
            loading: () =>
                const AdminPlaceholderRow(label: 'Current release', text: 'Loading…'),
            error: (_, __) =>
                const AdminPlaceholderRow(label: 'Current release', text: 'Unavailable'),
            data: (r) => r == null
                ? const AdminMetricTile.absent(
                    label: 'Current release', absence: MetricAbsence.notAuthorized)
                : r.releaseVersion == null
                    ? const AdminMetricTile.absent(
                        label: 'Current release', absence: MetricAbsence.notRecorded)
                    : AdminMetricTile.text(
                        label: 'Current release',
                        display: '${r.releaseVersion}'
                            '${r.environment != null ? ' · ${r.environment}' : ''}'),
          ),
          conn.when(
            loading: () =>
                const AdminPlaceholderRow(label: 'Connections', text: 'Loading…'),
            error: (_, __) =>
                const AdminPlaceholderRow(label: 'Connections', text: 'Unavailable'),
            data: (c) => c == null
                ? const AdminMetricTile.absent(
                    label: 'Connections', absence: MetricAbsence.notAuthorized)
                : AdminMetricTile.value(
                    label: 'Connections', value: c.connectedTotal, zeroCopy: 'None'),
          ),
        ],
      ),
    );
  }

  Widget _releases(WidgetRef ref) {
    final async = ref.watch(adminReleaseStatusProvider);
    return AdminCard(
      title: 'Releases',
      child: async.when(
        loading: () => const AdminNote('Loading…'),
        error: (_, __) => const AdminNote('Unavailable'),
        data: (r) {
          if (r == null) return const AdminNote('Not available to your role');
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (r.releaseVersion != null)
                AdminMetricTile.text(
                    label: 'Release',
                    display: '${r.releaseVersion}'
                        '${r.environment != null ? ' · ${r.environment}' : ''}'),
              // THE TWO VERDICTS STAY SEPARATE. METRIC-11 Option 3 — "intentionally
              // separate states and must not be collapsed" — so there is no combined
              // badge here and none is derived.
              if (r.hasCiVerdict)
                AdminMetricTile.text(label: 'CI status', display: r.ciStatus!)
              else
                const AdminMetricTile.absent(
                    label: 'CI status', absence: MetricAbsence.notRecorded),
              if (r.hasGateVerdict)
                AdminMetricTile.text(
                    label: 'V5 release gate', display: r.gateVerdict!)
              else
                const AdminMetricTile.absent(
                    label: 'V5 release gate', absence: MetricAbsence.notRecorded),
              if (r.gatesPass != null &&
                  r.gatesPartial != null &&
                  r.gatesFail != null &&
                  r.gatesTotal != null)
                AdminMetricTile.text(
                    label: 'Gates',
                    display: '${r.gatesPass} pass · ${r.gatesPartial} partial · '
                        '${r.gatesFail} fail of ${r.gatesTotal}'),
              const AdminFootnote(
                  'Nothing is recorded until a release is. CI ingestion is gated on P10 '
                  'and CONF-D9 — no verdict here is inferred from a build.'),
            ],
          );
        },
      ),
    );
  }

  Widget _integrations(WidgetRef ref) {
    final async = ref.watch(adminWearableConnectionsProvider);
    return AdminCard(
      title: 'Integrations',
      child: async.when(
        loading: () => const AdminNote('Loading…'),
        error: (_, __) => const AdminNote('Unavailable'),
        data: (c) {
          if (c == null) return const AdminNote('Not available to your role');
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminMetricTile.value(
                  label: 'Connections', value: c.connectedTotal, zeroCopy: 'None'),
              for (final e in c.byProvider.entries)
                AdminMetricTile.value(label: e.key, value: e.value),
              const AdminFootnote(
                  'Connections only. Integration health is WI-13 and waits on PD-G01 — '
                  'nothing here estimates it.'),
            ],
          );
        },
      ),
    );
  }

  Widget _system(WidgetRef ref) {
    final async = ref.watch(adminSecurityEventsProvider);
    return AdminCard(
      title: 'System events',
      child: async.when(
        loading: () => const AdminNote('Loading…'),
        error: (_, __) => const AdminNote('Unavailable'),
        data: (events) {
          if (events == null) return const AdminNote('Not available to your role');
          if (events.isEmpty) return const AdminNote('none raised');
          final admin = events.where((e) => e.category == 'admin_action').length;
          final reads = events.where((e) => e.category == 'audit_read').length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminMetricTile.value(
                  label: 'Admin actions', value: admin, zeroCopy: 'none raised'),
              AdminMetricTile.value(
                  label: 'Audit reads', value: reads, zeroCopy: 'none raised'),
              // A13·1 applies to this projection too: an admin's own admin_action rows
              // are excluded, so this count is incomplete for whoever is reading it.
              const AdminFootnote(AdminAuditEvent.a13Note),
            ],
          );
        },
      ),
    );
  }
}
