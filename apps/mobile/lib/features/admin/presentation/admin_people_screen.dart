import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/admin_metrics.dart';
import '../domain/admin_provider.dart';
import '../../../core/observability/app_failure.dart';
import 'admin_chrome.dart';
import 'admin_metric_tile.dart';
import 'admin_tokens.dart';

/// V5 §185 — P5 · People.
///
/// Published sections, in order: `#users` · `#coaches` · `#clients` · `#partners`
/// (Wellness Partners) · `#states`. The page's stated data requirements are *"account list
/// with role, status, last active; coach verification; client assignment; Wellness Partner
/// onboarding and approval states"*.
///
/// THREE OF THOSE ARE NOT BUILT, AND EACH ABSENCE IS STATED RATHER THAN LEFT BLANK:
///
///   * **"last active"** — which signal makes a person active is the open population
///     question (data contract `:98`). METRIC-02 settled which events count for a COUNT,
///     not what makes one individual active. Deriving a per-user recency from
///     `workout_sessions` would answer a question nobody asked.
///   * **"coach verification"** — no verification state exists in the schema. The nearest
///     columns are Stripe onboarding flags, which are a PAYMENTS fact and not a
///     verification one; relabelling them would invent a state machine.
///   * **Partner approval states** — `METRIC-05 = Option 2`: the total only. No approval
///     state machine exists (§77.3) and none was invented, which is the owner's ruling.
///
/// PII IS SHOWN ONLY WHERE THE SECTION IS ABOUT IT. `admin_user_directory` (160) projects
/// nine columns for the Users area and the design asks for an account list, so names and
/// emails appear in `#users`. The aggregate sections show counts and no identifiers, and
/// `avatar_url` is never selected at all.
class AdminPeopleScreen extends ConsumerWidget {
  const AdminPeopleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        backgroundColor: AdminColors.colorBgCanvas,
        appBar: AppBar(
          backgroundColor: AdminColors.colorBgCanvas,
          surfaceTintColor: AdminColors.colorBgCanvas,
          elevation: 0,
          iconTheme: const IconThemeData(color: AdminColors.colorTextPrimary),
          title: const Text('People',
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
            ref.invalidate(adminUserOverviewProvider);
            ref.invalidate(adminUserDirectoryProvider);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(AdminDims.space8, AdminDims.space6,
                AdminDims.space8, AdminDims.space20),
            children: [
              _users(ref),
              const SizedBox(height: AdminDims.space6),
              _coaches(ref),
              const SizedBox(height: AdminDims.space6),
              _clients(ref),
              const SizedBox(height: AdminDims.space6),
              _partners(ref),
              const SizedBox(height: AdminDims.space6),
              const _StatesPanel(),
            ],
          ),
        ),
      );

  Widget _users(WidgetRef ref) {
    final overview = ref.watch(adminUserOverviewProvider);
    final directory = ref.watch(adminUserDirectoryProvider);
    return AdminCard(
      title: 'Users',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          overview.when(
            loading: () => const AdminPlaceholderRow(label: 'Members', text: 'Loading…'),
            error: (_, __) =>
                const AdminPlaceholderRow(label: 'Members', text: 'Unavailable'),
            data: (m) => m == null
                ? const AdminMetricTile.absent(
                    label: 'Members', absence: MetricAbsence.notAuthorized)
                : AdminMetricTile.of('Members', m.usersTotal,
                    whenNull: MetricAbsence.notAuthorized),
          ),
          const SizedBox(height: AdminDims.space4),
          // The approved table's own search box. Its placeholder NAMES the fields, so the
          // note below it is the design's promise rather than this layer's choice.
          AdminSearchBox(
            hint: 'Search name or email',
            fieldsNote: 'Searches first name, last name and email. A result of none means '
                'no match in those fields — not that the account does not exist.',
            value: ref.watch(adminUserSearchProvider),
            onChanged: (v) =>
                ref.read(adminUserSearchProvider.notifier).state = v,
          ),
          const SizedBox(height: AdminDims.space4),
          directory.when(
            loading: () => const AdminNote('Loading…'),
            error: (_, __) => const AdminNote('Unavailable'),
            data: (rows) {
              if (rows == null) return const AdminNote('Not available to your role');
              // AN EMPTY SEARCH RESULT IS NOT AN EMPTY DIRECTORY. With a query active the
              // zero means "nothing matched"; without one it means the population is empty.
              // Rendering the same word for both would make a filter look like a fact.
              if (rows.isEmpty) {
                return AdminNote(ref.watch(adminUserSearchProvider).trim().isEmpty
                    ? 'None'
                    : 'No account matches that search');
              }
              // THE GATE WRAPS THE ACTION, NOT THE DATA — and that distinction cost a
              // test. Putting `adminCapabilityGate` around the whole list meant that
              // while the `Users·update` check was in flight, the gate's honest
              // "Checking your permissions…" replaced EVERY ROW — hiding records the
              // operator was already authorized to see by `Users·view`, on the strength
              // of a pending answer about a different verb. Each row now gates its own
              // trailing action, so a slow or failed `update` check can cost the button
              // and never the data.
              // ONE decision, in one `when`, for all four states — and the rows render in
              // every one of them. See [adminGatedList] for the three shapes this
              // replaced and the guard that rejected each.
              return adminGatedList(
                ref.watch(adminCanUpdateUsersProvider),
                denied: 'Read-only: editing a profile requires Users · update.',
                rows: (canAct) => [
                  for (final u in rows.take(20))
                    _UserRow(entry: u, canEdit: canAct),
                ],
              );
            },
          ),
          const AdminFootnote(
              '"Last active" is not shown: which signal makes a person active is an open '
              'definition, and deriving one here would answer a question nobody asked.'),
        ],
      ),
    );
  }

  Widget _coaches(WidgetRef ref) => _counts(
        ref,
        'Coaches',
        const ['Coaches', 'Active this month'],
        (m) => [
          AdminMetricTile.of('Coaches', m.coachesTotal,
              whenNull: MetricAbsence.notAuthorized),
          // METRIC-03 = calendar month, and the partition the design requires:
          // "of N · M with no client this month".
          AdminMetricTile.of('Active this month', m.coachesActiveThisMonth,
              whenNull: MetricAbsence.notAuthorized),
          AdminMetricTile.of('No client this month', m.coachesNoClientThisMonth,
              whenNull: MetricAbsence.notAuthorized, zeroCopy: 'None'),
          // §193 · the fourth People requirement — "client assignment" — which §185.2's
          // three-absence audit omitted entirely rather than refusing.
          AdminMetricTile.of('Clients served', m.coachClientsServed,
              whenNull: MetricAbsence.notAuthorized, zeroCopy: 'None'),
          // NULL IS NOT ZERO HERE. An average needs something to divide by, and "no active
          // coach to average over" is not "an average of zero clients" — the A11 state,
          // never 0.0.
          if (m.coachClientsPerActiveCoach != null)
            AdminMetricTile.text(
                label: 'Average per active coach',
                display: m.coachClientsPerActiveCoach!.toStringAsFixed(1))
          else
            const AdminMetricTile.absent(
                label: 'Average per active coach',
                absence: MetricAbsence.notRecorded),
          // The three Coaches-module tiles that remain unbuilt, named rather than left as
          // blanks — the discipline §185.2 applied to the other absences.
          const AdminFootnote(
              'Not shown: "Programs live" — workout_programs carries no lifecycle state, '
              'so a program\'s "live" is undefined in the schema. "Sessions · 30 d, '
              'coach-led" — "coach-led" is not a column, and the two readings available '
              '(a client with an active coach, or a coach-authored program) differ with '
              'nothing to rule between them. "Reassign clients" — a write with no governed '
              'path and no defined triage model.'),
          const AdminFootnote(
              'Coach verification is not shown — no verification state exists in the '
              'schema, and the Stripe onboarding flags are a payments fact, not a '
              'verification one.'),
        ],
      );

  Widget _clients(WidgetRef ref) => _counts(
        ref,
        'Clients',
        const ['Clients'],
        (m) => [
          AdminMetricTile.of('Clients', m.clientsTotal,
              whenNull: MetricAbsence.notAuthorized),
          // METRIC-17 = Option 2. The fourth bucket is `unknown`; `age_out_of_range` is a
          // reconciliation figure and is shown only when non-empty, never as a bucket.
          AdminMetricTile.of('Age 18–30', m.age18to30,
              whenNull: MetricAbsence.notAuthorized),
          AdminMetricTile.of('Age 30–45', m.age30to45,
              whenNull: MetricAbsence.notAuthorized),
          AdminMetricTile.of('Age 45–60', m.age45to60,
              whenNull: MetricAbsence.notAuthorized),
          AdminMetricTile.of('Age unknown', m.ageUnknown,
              whenNull: MetricAbsence.notAuthorized),
          if (m.ageOutOfRange != null && m.ageOutOfRange! > 0)
            AdminMetricTile.of('Outside the approved buckets', m.ageOutOfRange,
                whenNull: MetricAbsence.notAuthorized),
        ],
      );

  Widget _partners(WidgetRef ref) => _counts(
        ref,
        'Wellness Partners',
        const ['Partners'],
        (m) => [
          // METRIC-05 = Option 2 — the TOTAL ONLY. No "awaiting approval" sub-count,
          // because no approval state machine exists and the owner ruled it dropped.
          AdminMetricTile.of('Partners', m.vendorsTotal,
              whenNull: MetricAbsence.notAuthorized, zeroCopy: 'None'),
          const AdminFootnote(
              'Total only. Onboarding and approval states are not shown — the schema has '
              'no approval state machine and none was invented.'),
        ],
      );

  static Widget _counts(
    WidgetRef ref,
    String title,
    List<String> labels,
    List<Widget> Function(AdminUserOverview) body,
  ) {
    final async = ref.watch(adminUserOverviewProvider);
    return AdminCard(
      title: title,
      child: async.when(
        loading: () => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final l in labels) AdminPlaceholderRow(label: l, text: 'Loading…')
          ],
        ),
        error: (_, __) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final l in labels) AdminPlaceholderRow(label: l, text: 'Unavailable')
          ],
        ),
        data: (m) => m == null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final l in labels)
                    AdminMetricTile.absent(
                        label: l, absence: MetricAbsence.notAuthorized)
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch, children: body(m)),
      ),
    );
  }
}

/// One account. Shows the name, the role and whether onboarding finished — named as what
/// it is rather than relabelled "status", which would imply a state machine the schema
/// does not have.
/// One directory row, and the approved People screen's "Edit profile" action.
///
/// WHAT "Edit profile" MEANS HERE, AND WHAT IT DOES NOT. The only governed write that
/// touches a profile from the Admin layer is `admin_update_user_name` (161), gated on
/// `Users·update` like this row. So the action renames; it does not edit a plan, a payout
/// or a tier, because no governed path accepts those from here.
///
/// "CHANGE ROLE" IS ABSENT ON PURPOSE, and this is the one omission worth stating in code
/// rather than leaving as a gap. The approved row menu lists it, and
/// `admin_set_user_role` exists (115:363) — but it gates on the legacy `is_admin()`, a
/// `user_profiles.role = 'admin'` test, and NOT on the capability matrix that gates this
/// row and every other Admin surface. Rendering it beside this action would either show
/// an enabled control to a `Users·update` holder who will be refused 42501, or require
/// widening role assignment to every holder of `Users·update`. The second is a
/// privilege-escalation decision; neither is a wiring detail, so the control waits.
class _UserRow extends ConsumerWidget {
  const _UserRow({required this.entry, required this.canEdit});

  final AdminUserDirectoryEntry entry;

  /// A confirmed `true` from the parent — never a collapsed error. The parent states the
  /// failure once via [adminGatedList]; this flag only decides whether a button draws.
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AdminDims.space3),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.displayName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AdminColors.colorTextPrimary,
                        fontSize: AdminDims.typeSmallSize,
                      )),
                  Text(
                    [
                      if (entry.role != null) entry.role!,
                      if (entry.membershipTier != null) entry.membershipTier!,
                      if (entry.onboardingComplete == false) 'onboarding incomplete',
                    ].join(' · '),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AdminColors.colorTextSubtle,
                      fontSize: AdminDims.typeCaptionSize,
                    ),
                  ),
                ],
              ),
            ),
            if (canEdit)
              SizedBox(
                height: AdminDims.sizeControl,
                child: TextButton(
                  onPressed: entry.id == null ? null : () => _rename(context, ref),
                  style: TextButton.styleFrom(
                    foregroundColor: AdminColors.colorBrandAccent,
                    minimumSize:
                        const Size(AdminDims.sizeControl, AdminDims.sizeControl),
                  ),
                  child: const Text('Edit profile',
                      style: TextStyle(fontSize: AdminDims.typeCaptionSize)),
                ),
              ),
          ],
        ),
      );

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final first = TextEditingController(text: entry.firstName ?? '');
    final last = TextEditingController(text: entry.lastName ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminColors.colorBgSurface,
        title: const Text('Edit profile',
            style: TextStyle(
                color: AdminColors.colorTextPrimary,
                fontSize: AdminDims.typeCardTitleSize)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _field(first, 'First name'),
            _field(last, 'Last name'),
            const SizedBox(height: AdminDims.space4),
            // Says what this form is NOT, so its narrowness is not read as a bug.
            const Text(
                'Name only. Role, plan, tier and payout details are not changed here — '
                'no governed path accepts them from this screen. Clearing a box leaves '
                'that name unchanged; it cannot blank a name.',
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
            child: const Text('Save',
                style: TextStyle(
                    color: AdminColors.colorBrandAccent,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    // 161 coalesces each argument, so null means "leave this name alone". Sending back an
    // unchanged name would be harmless to the row but would pad the audit trail with a
    // changed-column list the operator did not change.
    final newFirst = _changed(first.text, entry.firstName);
    final newLast = _changed(last.text, entry.lastName);
    if (newFirst == null && newLast == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: AdminColors.colorBgRaised,
          content: Text('Nothing was changed, so nothing was saved.',
              style: TextStyle(color: AdminColors.colorTextSecondary)),
        ));
      }
      return;
    }

    try {
      await ref.read(adminMetricsServiceProvider).updateUserName(
            userId: entry.id!,
            firstName: newFirst,
            lastName: newLast,
          );
      ref.invalidate(adminUserDirectoryProvider);
    } catch (e, st) {
      // The names are NOT put in the error payload. 161 refuses to record them in its own
      // audit row because the values re-identify a pseudonymous subject, and an error
      // sink is not a weaker place to leak them.
      reportError('admin_people.updateUserName', e, st, {'user': entry.id});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: AdminColors.colorBgRaised,
          content: Text(
              'The profile was not updated. You may not have permission. Nothing was '
              'saved.',
              style: TextStyle(color: AdminColors.colorStatusDangerText)),
        ));
      }
    }
  }

  /// Null when unchanged or emptied — 161 refuses a blank name, so an emptied box is not
  /// a request to erase one.
  static String? _changed(String raw, String? was) {
    final v = raw.trim();
    if (v.isEmpty) return null;
    return v == (was ?? '') ? null : v;
  }

  static Widget _field(TextEditingController c, String label) => TextField(
        controller: c,
        style: const TextStyle(
            color: AdminColors.colorTextPrimary, fontSize: AdminDims.typeSmallSize),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: AdminColors.colorTextMuted),
        ),
      );
}

/// `#states` — the state-system panel the design places on People, naming the states this
/// page actually renders.
/// Delegates to [AdminStatesPanel] so the four DESIGNED-BUT-UNIMPLEMENTED states — Offline,
/// Stale, Degraded, Skeleton — are named identically on every page. This panel used to list
/// only the states this page renders, which meant the four absent ones were silently absent
/// on all six surfaces.
class _StatesPanel extends StatelessWidget {
  const _StatesPanel();

  @override
  Widget build(BuildContext context) => const AdminStatesPanel(
        title: 'State system',
        implemented: 'Loading · Unavailable · Not available to your role · '
            'Not recorded · None',
        readOnlyNote: 'Read-only except "Edit profile", which names the capability it '
            'needs and is shown only to a holder of it.',
      );
}
