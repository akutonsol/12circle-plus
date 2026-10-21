import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/observability/app_failure.dart';

import '../domain/admin_metrics.dart';
import '../domain/admin_provider.dart';
import '../domain/admin_trust.dart';
import 'admin_metric_tile.dart';
import 'admin_chrome.dart';
import 'admin_tokens.dart';

/// V5 §183 — P6 · Trust.
///
/// The sections are the published ones, in the published order
/// (`SCREEN-INVENTORY.md` at `931218b`): `#overview` · `#ai-guardian` ·
/// `#security` (incl. `#sec-authz`) · `#incidents` · `#audit` · `#trust-system`. The
/// design's stated data requirements for this page are *"AI Guardian actions and
/// autonomy; auth and authorisation events; incidents; immutable audit log with
/// before/after"*, and every one is read from a surface migrations 156/159/160/163/169
/// already publish — nothing new was added to the schema for this screen.
///
/// A CORRECTION TO §183. This page was first shipped as read-only on the stated grounds
/// that it was *"a design rule"*, citing `CONF-D5`'s drawer footer — *"Actions open the
/// item. Nothing is changed from this screen."* **That was wrong about the page.** That
/// footer governs the attention-queue DRAWER, and the approved Trust screen itself
/// contains action controls: `Resolve` appears three times, alongside `Investigate` and
/// *"Assign, change status, add…"*. `Read-only` is listed in the inventory as one of the
/// **states** designed for Trust, Operations and Settings — a state for a role that may
/// view and not update, not a property of the surface.
///
/// So incident resolution is implemented, and the read-only state is rendered for anyone
/// without `Incidents·update` — a capability `trust_lead` holds alone. The inventory's
/// Interactions section requires the shape: *"row actions open confirm dialogs for
/// destructive changes."*
///
/// THE GUARDIAN REMAINS READ-ONLY HERE, and that one IS a rule: `A10` bars the Guardian
/// from holding admin authority, re-stating it goes through `admin_set_guardian_state`
/// gated `AI Guardian·manage`, and nothing on this page calls it.
///
/// WHAT IT REFUSES TO DO, each a defect this programme has already paid for once:
///   * it never resolves `subject_pseudonym` — §19.3, and the model gives it no way to;
///   * it never presents an unrecorded Guardian state as `Active` — that is EC-04's
///     coercion applied to a safety control;
///   * it states `A13·1` on the audit section rather than implying a complete ledger;
///   * loading, error, "no capability" and "nothing recorded" are four distinct states;
///   * it never presents a write as having happened when the governed path refused it.
class AdminTrustScreen extends ConsumerWidget {
  const AdminTrustScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AdminColors.colorBgCanvas,
      appBar: AppBar(
        backgroundColor: AdminColors.colorBgCanvas,
        surfaceTintColor: AdminColors.colorBgCanvas,
        elevation: 0,
        iconTheme: const IconThemeData(color: AdminColors.colorTextPrimary),
        title: const Text('Trust',
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
          ref.invalidate(adminGuardianStateProvider);
          ref.invalidate(adminCanViewGuardianProvider);
          ref.invalidate(adminGovernancePoliciesProvider);
          ref.invalidate(adminSecurityEventsProvider);
          ref.invalidate(adminIncidentsProvider);
          ref.invalidate(adminAuditEventsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AdminDims.space8, AdminDims.space6,
              AdminDims.space8, AdminDims.space20),
          children: [
            _overview(ref),
            const SizedBox(height: AdminDims.space6),
            _aiGuardian(ref),
            const SizedBox(height: AdminDims.space6),
            _security(ref),
            const SizedBox(height: AdminDims.space6),
            _incidents(ref),
            const SizedBox(height: AdminDims.space6),
            _audit(ref),
            const SizedBox(height: AdminDims.space6),
            const _TrustSystemPanel(),
          ],
        ),
      ),
    );
  }

  // ── #overview ───────────────────────────────────────────────────────────
  Widget _overview(WidgetRef ref) {
    final guardian = ref.watch(adminGuardianStateProvider);
    final canGuardian = ref.watch(adminCanViewGuardianProvider);
    final incidents = ref.watch(adminIncidentsProvider);
    final security = ref.watch(adminSecurityEventsProvider);
    return AdminCard(
      title: 'Overview',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The Guardian reading is NOT a boolean. `guardianIsHealthy` returns null for
          // "cannot say", and this renders that rather than resolving it to a reassuring
          // answer. The capability is read from its own provider so that "you may not
          // see this" and "nothing is recorded" stay distinguishable.
          _guardianHealthTile(guardian, canGuardian),
          _countTile('Open incidents', incidents,
              (l) => l.where((i) => i.resolution == null).length,
              zeroCopy: 'none open'),
          _countTile('Security events', security, (l) => l.length,
              zeroCopy: 'none raised'),
        ],
      ),
    );
  }

  static Widget _guardianHealthTile(
      AsyncValue<AdminGuardianState?> g, AsyncValue<bool> can) {
    return g.when(
      loading: () => const AdminNote('Loading…'),
      error: (_, __) => const AdminNote('Unavailable'),
      data: (state) => can.when(
        loading: () => const AdminNote('Loading…'),
        error: (_, __) => const AdminNote('Unavailable'),
        data: (permitted) {
          if (!permitted) {
            return const AdminMetricTile.absent(
                label: 'AI Guardian', absence: MetricAbsence.notAuthorized);
          }
          final healthy = AdminTrustSummary.guardianIsHealthy(state);
          if (healthy == null) {
            // NOT "Active". guardian_state starts empty (169), and the most reassuring
            // reading of missing data is exactly the EC-04 defect.
            return const AdminMetricTile.absent(
                label: 'AI Guardian', absence: MetricAbsence.notRecorded);
          }
          return AdminMetricTile.text(label: 'AI Guardian', display: state!.state!);
        },
      ),
    );
  }

  static Widget _countTile<T>(
    String label,
    AsyncValue<List<T>?> async,
    int Function(List<T>) count, {
    String? zeroCopy,
  }) =>
      async.when(
        loading: () => AdminPlaceholderRow(label: label, text: 'Loading…'),
        error: (_, __) => AdminPlaceholderRow(label: label, text: 'Unavailable'),
        data: (list) => list == null
            ? AdminMetricTile.absent(
                label: label, absence: MetricAbsence.notAuthorized)
            : AdminMetricTile.value(
                label: label, value: count(list), zeroCopy: zeroCopy),
      );

  // ── #ai-guardian ────────────────────────────────────────────────────────
  Widget _aiGuardian(WidgetRef ref) {
    final g = ref.watch(adminGuardianStateProvider);
    final can = ref.watch(adminCanViewGuardianProvider);
    final policies = ref.watch(adminGovernancePoliciesProvider);
    return AdminCard(
      title: 'AI Guardian',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _guardianHealthTile(g, can),
          // A reason is REQUIRED to disable (169 gates it), so showing it is part of
          // showing the state honestly — a Disabled Guardian with no stated reason is
          // itself a finding.
          // A REASON IS PROSE, NOT A STAT. It is rendered as a wrapping footnote rather
          // than a tile value: a disablement reason is the one thing on this card that
          // must not be truncated, and a tile is a single row by design. The first draft
          // put it in a tile and overflowed by 288px, which would have silently clipped
          // why a safety control was switched off.
          g.maybeWhen(
            data: (s) => (s?.isDisabled ?? false)
                ? AdminFootnote('Disabled because: ${s!.reason ?? 'no reason recorded'}')
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),
          _countTile('Policies', policies, (l) => l.length, zeroCopy: 'None'),
          _countTile('Policies active', policies,
              (l) => l.whereType<AdminGovernancePolicy>().where((p) => p.isActive).length,
              zeroCopy: 'None'),
          // THE APPROVED SECTION ASKS FOR MORE THAN EXISTS, and each absence is named.
          // The published Guardian section shows "Guardian health", "Evaluation engine:
          // Operating", "Median decision time", "Agents without a policy", "Last full
          // evaluation" and a decisions-by-hour chart. `guardian_state` and
          // `governance_policy` back the state and the policy counts; the rest has no
          // surface, and a blank where a figure was is indistinguishable from an
          // oversight.
          const AdminFootnote(
              'Not recorded: evaluation-engine state, median decision time, agents '
              'without a policy, last full evaluation, decisions per hour. No surface '
              'produces them and none is estimated here.'),
          // OWNER DECISION Q9 placed the emergency-disable control here. `A10` requires
          // that emergency disablement be POSSIBLE and migration 169 is that control; what
          // §189.5 recorded as open was only its placement, and Q9 answers it: Trust → AI
          // Guardian, approved placement and confirmation only, authorization unchanged.
          const _GuardianDisableAction(),
          // THE OTHER THREE `A5` STATES ARE NOT OFFERED, and that absence is stated rather
          // than left to be noticed. 169 accepts Active · Monitoring · Degraded ·
          // Disabled; Q9 authorized the emergency-disable control, not a state picker.
          // Restoring the Guardian is not an emergency action and has no approved
          // affordance, so it is named here instead of invented.
          const AdminFootnote(
              'Only emergency disablement is available here. Returning the Guardian to '
              'Active, Monitoring or Degraded is not offered on this screen — the governed '
              'path accepts those states, no approved surface places them.'),
        ],
      ),
    );
  }

  // ── #security, incl. #sec-authz ─────────────────────────────────────────
  Widget _security(WidgetRef ref) {
    final async = ref.watch(adminSecurityEventsProvider);
    return AdminCard(
      title: 'Security',
      child: async.when(
        loading: () => const AdminNote('Loading…'),
        error: (_, __) => const AdminNote('Unavailable'),
        data: (events) {
          if (events == null) {
            return const AdminNote('Not available to your role');
          }
          if (events.isEmpty) return const AdminNote('none raised');
          final denials =
              events.where((e) => e.category == 'authorization_denial').length;
          final auth = events.where((e) => e.category == 'authentication').length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // #sec-authz — the authorization half of the section.
              AdminMetricTile.value(
                  label: 'Authorization denials', value: denials, zeroCopy: 'none raised'),
              AdminMetricTile.value(
                  label: 'Authentication events', value: auth, zeroCopy: 'none raised'),
              const SizedBox(height: AdminDims.space4),
              for (final e in events.take(10)) _EventRow(event: e),
            ],
          );
        },
      ),
    );
  }

  // ── #incidents ──────────────────────────────────────────────────────────
  Widget _incidents(WidgetRef ref) {
    final async = ref.watch(adminIncidentsProvider);
    final canUpdate = ref.watch(adminCanUpdateIncidentsProvider);
    return AdminCard(
      title: 'Incidents',
      child: async.when(
        loading: () => const AdminNote('Loading…'),
        error: (_, __) => const AdminNote('Unavailable'),
        data: (items) {
          if (items == null) return const AdminNote('Not available to your role');
          if (items.isEmpty) return const AdminNote('none open');
          // THE INCIDENTS THEMSELVES ARE NOT GATED ON `update`. They are read under
          // `Incidents·view`, and they used to sit inside an `adminCapabilityGate` keyed on
          // `Incidents·update` — so a pending or failed answer about a DIFFERENT VERB
          // blanked every incident. §189 found the same shape on People and on the events
          // directory. The rows render in all four states; only the action depends on the
          // answer, and a failed check still gets its sentence. See [adminGatedList].
          return adminGatedList(
            canUpdate,
            denied: 'Read-only: resolving an incident requires Incidents · update.',
            rows: (canAct) => [
              for (final i in items.take(10))
                _IncidentRow(incident: i, canUpdate: canAct),
              const AdminFootnote(
                  'Evidence and actor identity are withheld from this layer (B-4).'),
            ],
          );
        },
      ),
    );
  }

  // ── #audit ──────────────────────────────────────────────────────────────
  Widget _audit(WidgetRef ref) {
    final async = ref.watch(adminAuditEventsProvider);
    return AdminCard(
      title: 'Audit logs',
      child: async.when(
        loading: () => const AdminNote('Loading…'),
        error: (_, __) => const AdminNote('Unavailable'),
        data: (events) {
          if (events == null) return const AdminNote('Not available to your role');
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (events.isEmpty)
                const AdminNote('none raised')
              else
                for (final e in events.take(15)) _EventRow(event: e),
              // A13·1 IS STATED, NOT IMPLIED. This ledger is incomplete for whoever is
              // reading it, so absence here is not evidence of absence.
              const AdminFootnote(AdminAuditEvent.a13Note),
              // AND SO IS B-19. This page's stated requirement is "immutable audit log
              // with before/after", and the before/after half is absent BY OWNER DECISION:
              // B-19 ruled "withhold both" for `delta` and `changed_columns` in the Admin
              // audit projections, and closed as a CONFIRMED DESIGN. The columns exist —
              // 150 added them for A6 delta capture — and 156/159 deliberately do not
              // project them. A requirement half that is absent by ruling still needs a
              // sentence saying so, which is the rule §194 applied to the Control Center;
              // this card had A13·1 and not this one.
              const AdminFootnote(
                  'Before/after values are withheld from this layer by owner decision '
                  'B-19. The audit record retains them; this projection does not carry '
                  'them, so no diff is shown here and none is reconstructed.'),
            ],
          );
        },
      ),
    );
  }
}

/// One incident. Carries the resolve action only for a caller holding
/// `Incidents·update`, and only behind a confirm dialog — the inventory's Interactions
/// section requires that shape, and recording a resolution is not undoable from here.
class _IncidentRow extends ConsumerWidget {
  const _IncidentRow({required this.incident, required this.canUpdate});

  final AdminIncident incident;
  final bool canUpdate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolved = incident.resolution != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AdminDims.space3),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(incident.summary ?? 'Incident',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AdminColors.colorTextPrimary,
                      fontSize: AdminDims.typeSmallSize,
                    )),
                Text(
                  [
                    if (incident.severity != null) incident.severity!,
                    if (incident.scope != null) incident.scope!,
                    if (resolved) 'resolved',
                  ].join(' · '),
                  style: const TextStyle(
                    color: AdminColors.colorTextSubtle,
                    fontSize: AdminDims.typeCaptionSize,
                  ),
                ),
              ],
            ),
          ),
          if (canUpdate && !resolved && incident.id != null)
            SizedBox(
              height: AdminDims.sizeControl, // 44px, RESPONSIVE.md
              child: TextButton(
                onPressed: () => _confirm(context, ref),
                style: TextButton.styleFrom(
                  foregroundColor: AdminColors.colorBrandAccent,
                  minimumSize:
                      const Size(AdminDims.sizeControl, AdminDims.sizeControl),
                ),
                child: const Text('Resolve',
                    style: TextStyle(
                      fontSize: AdminDims.typeCaptionSize,
                      fontWeight: FontWeight.w500,
                    )),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminColors.colorBgSurface,
        title: const Text('Record a resolution',
            style: TextStyle(
                color: AdminColors.colorTextPrimary,
                fontSize: AdminDims.typeCardTitleSize)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(incident.summary ?? 'Incident',
                style: const TextStyle(
                    color: AdminColors.colorTextSecondary,
                    fontSize: AdminDims.typeSmallSize)),
            const SizedBox(height: AdminDims.space6),
            TextField(
              controller: controller,
              maxLines: 3,
              style: const TextStyle(
                  color: AdminColors.colorTextPrimary,
                  fontSize: AdminDims.typeSmallSize),
              decoration: const InputDecoration(
                hintText: 'What resolved it',
                hintStyle: TextStyle(color: AdminColors.colorTextMuted),
              ),
            ),
            const SizedBox(height: AdminDims.space4),
            const Text('This is recorded against the incident and audited. It cannot be '
                'undone from this screen.',
                style: TextStyle(
                    color: AdminColors.colorTextSubtle,
                    fontSize: AdminDims.typeCaptionSize)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: AdminColors.colorTextMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Record',
                style: TextStyle(
                    color: AdminColors.colorBrandAccent,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final text = controller.text.trim();
    if (text.isEmpty) return;
    try {
      await ref.read(adminTrustServiceProvider).resolveIncident(incident.id!, text);
      ref.invalidate(adminIncidentsProvider);
    } catch (e, st) {
      // THE FAILURE IS SHOWN, AND THE DETAIL GOES TO THE SINK. The governed path
      // re-checks the capability itself and raises 42501; swallowing that into a silent
      // no-op would let an operator believe a resolution was recorded when it was refused
      // — EC-03's defect applied to a write.
      //
      // The operator gets a STABLE SENTENCE, not `$e`. ERR-G2 caught the first version
      // interpolating the raw exception, and it was right to: a Postgres error can carry
      // SQL, identifiers and internal detail, and it tells an operator nothing they can
      // act on. The diagnosable half goes to EC-01's `reportError` sink instead.
      reportError('admin_trust.resolveIncident', e, st,
          {'incident_id': incident.id});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: AdminColors.colorBgRaised,
          content: Text(
              'The resolution was not recorded. You may not have permission, or the '
              'incident has changed. Nothing was saved.',
              style: TextStyle(color: AdminColors.colorStatusDangerText)),
        ));
      }
    }
  }
}

/// One audit or security row. It renders the PSEUDONYM and never anything resolved from
/// it — §19.3. There is no code path here that could.
class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final AdminAuditEvent event;

  @override
  Widget build(BuildContext context) {
    final when = event.occurredAt?.toIso8601String().replaceFirst('T', ' ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AdminDims.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(event.action ?? 'event',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AdminColors.colorTextPrimary,
                      fontSize: AdminDims.typeSmallSize,
                    )),
              ),
              const SizedBox(width: AdminDims.space4),
              Text(event.outcome ?? '—',
                  style: const TextStyle(
                    color: AdminColors.colorTextMuted,
                    fontSize: AdminDims.typeCaptionSize,
                  )),
            ],
          ),
          Text(
            [
              if (event.category != null) event.category!,
              if (when != null) when.split('.').first,
              // The pseudonym, shown AS a pseudonym and truncated for legibility. It is
              // not a name, and nothing in this layer can turn it into one.
              if (event.subjectPseudonym != null)
                'subject ${event.subjectPseudonym!.substring(0, event.subjectPseudonym!.length.clamp(0, 8))}…',
            ].join(' · '),
            style: const TextStyle(
              color: AdminColors.colorTextSubtle,
              fontSize: AdminDims.typeCaptionSize,
            ),
          ),
        ],
      ),
    );
  }
}

/// `#trust-system` — the state-system panel the design places on Trust, naming the `A11`
/// states this page actually renders rather than illustrating ones it does not.
class _TrustSystemPanel extends StatelessWidget {
  const _TrustSystemPanel();

  @override
  Widget build(BuildContext context) => const AdminStatesPanel(
        title: 'State system',
        implemented: 'Loading · Unavailable · Not available to your role · '
            'Not recorded · Read-only',
        readOnlyNote: 'Read-only except the incident resolve and Guardian disable actions, '
            'each shown only to a holder of its capability.',
      );
}






/// The emergency Guardian disablement control, placed on Trust → AI Guardian by **owner
/// decision Q9**.
///
/// WHAT Q9 DECIDED AND WHAT IT DID NOT. `A10` names emergency disablement a product
/// requirement, and migration `169` has been that control since §150 — `SECURITY DEFINER`,
/// gated on `admin_can('AI Guardian','manage')` which the approved matrix grants to
/// **`trust_lead` alone**, requiring `auth.uid()` so no agent can reach it, and requiring a
/// reason to disable. §188 wrongly recorded `A10` itself as an open boundary; §189.5
/// corrected that to the narrower question of *placement*, which is what Q9 answers.
///
/// Q9's words bound this widget: *"Implement only the approved UI placement and required
/// confirmation/A11 treatment. Do not broaden authorization."* So:
///
///   * the gate is `AI Guardian·manage` and **not** the section's `·view` flag, which
///     several roles hold;
///   * **only `'Disabled'`** is reachable — a state picker would be product scope read into
///     a placement decision;
///   * the reason is **required because 169 requires it**, not because this form prefers it;
///   * and the confirmation names what switches off, because the one thing worse than a
///     Guardian nobody can disable is a Guardian disabled by a misread tap.
///
/// THE A11 TREATMENT. The disabled state is never *asserted* by this widget. It does not
/// optimistically render "Disabled" on a successful RPC, and it does not render "Active" on
/// a failure: it invalidates [adminGuardianStateProvider] and lets the card read the state
/// back from the row. A safety control that displays its own intention rather than the
/// stored fact is the same defect as `EC-04`'s green badge, applied to the one switch on
/// this page that matters most.
class _GuardianDisableAction extends ConsumerWidget {
  const _GuardianDisableAction();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(adminGuardianStateProvider);
    // ALREADY DISABLED IS NOT AN ACTION. 169 returns early on a no-op transition without
    // auditing, so offering the control here would produce a button that does nothing and
    // records nothing — which reads as a failure.
    final alreadyOff = state.maybeWhen(
      data: (s) => s?.isDisabled ?? false,
      orElse: () => false,
    );
    if (alreadyOff) {
      return const AdminFootnote(
          'The Guardian is already disabled. Re-stating it is not done from this screen.');
    }
    return adminCapabilityGate(
      ref.watch(adminCanManageGuardianProvider),
      denied: const AdminFootnote(
          'Read-only: disabling the Guardian requires AI Guardian · manage, which the '
          'approved matrix grants to the Trust lead alone.'),
      allowed: () => Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          height: AdminDims.sizeControl, // 44px, RESPONSIVE.md
          child: TextButton(
            onPressed: () => _confirm(context, ref),
            style: TextButton.styleFrom(
              foregroundColor: AdminColors.colorStatusDangerText,
              minimumSize: const Size(AdminDims.sizeControl, AdminDims.sizeControl),
            ),
            child: const Text('Disable Guardian…',
                style: TextStyle(
                  fontSize: AdminDims.typeCaptionSize,
                  fontWeight: FontWeight.w600,
                )),
          ),
        ),
      ),
    );
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminColors.colorBgSurface,
        title: const Text('Disable the AI Guardian?',
            style: TextStyle(
                color: AdminColors.colorTextPrimary,
                fontSize: AdminDims.typeCardTitleSize)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Says what stops, in the terms the Guardian is described in elsewhere on this
            // card. A confirmation that only says "are you sure" confirms nothing.
            const Text(
                'Autonomy supervision stops until the Guardian is re-stated through the '
                'governed path. This screen cannot turn it back on.',
                style: TextStyle(
                    color: AdminColors.colorTextSecondary,
                    fontSize: AdminDims.typeSmallSize)),
            const SizedBox(height: AdminDims.space6),
            TextField(
              controller: reason,
              maxLines: 2,
              style: const TextStyle(
                  color: AdminColors.colorTextPrimary,
                  fontSize: AdminDims.typeSmallSize),
              decoration: const InputDecoration(
                labelText: 'Reason (required)',
                labelStyle: TextStyle(color: AdminColors.colorTextMuted),
              ),
            ),
            const SizedBox(height: AdminDims.space4),
            const Text(
                'The reason is recorded with the transition and shown on this card while '
                'the Guardian is disabled. A disabled Guardian with no stated reason is '
                'itself a finding.',
                style: TextStyle(
                    color: AdminColors.colorTextSubtle,
                    fontSize: AdminDims.typeCaptionSize)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: AdminColors.colorTextMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Disable',
                style: TextStyle(
                    color: AdminColors.colorStatusDangerText,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final text = reason.text.trim();
    // 169 refuses a blank reason with 22023. Catching it here is not a duplicated rule but
    // a kinder one: the operator is told what is missing instead of being handed a
    // constraint violation.
    if (text.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: AdminColors.colorBgRaised,
          content: Text(
              'A reason is required to disable the Guardian. Nothing was changed.',
              style: TextStyle(color: AdminColors.colorStatusWarningText)),
        ));
      }
      return;
    }

    try {
      await ref.read(adminTrustServiceProvider).disableGuardian(text);
      // READ THE STATE BACK; never assert it. See the class note on the A11 treatment.
      ref.invalidate(adminGuardianStateProvider);
    } catch (e, st) {
      // The reason text is NOT put in the error payload — it is operator prose about a
      // safety incident, and an error sink is not a quieter place to copy it to.
      reportError('admin_trust.disableGuardian', e, st, const {});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: AdminColors.colorBgRaised,
          content: Text(
              'The Guardian was not disabled. You may not have permission. Nothing was '
              'changed.',
              style: TextStyle(color: AdminColors.colorStatusDangerText)),
        ));
      }
    }
  }
}
