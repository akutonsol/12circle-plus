import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/admin_metrics.dart';
import '../domain/admin_provider.dart';
import '../../../core/observability/app_failure.dart';
import 'admin_chrome.dart';
import 'admin_metric_tile.dart';
import 'admin_tokens.dart';

/// V5 §184 — P5 · Ecosystem.
///
/// Sections are the published ones, in the published order (`SCREEN-INVENTORY.md` at
/// `931218b`): `#overview` · `#community` · `#events` · `#training` · `#monetization` ·
/// `#wearables`. The page's stated data requirements are *"community posts, reports and
/// moderation queue; events and attendance; training content and completion;
/// monetisation (plans, payouts, commission); wearable connections"* — every one reads a
/// surface migrations 156/157/166/170/171/172/178 already publish. **No schema was added
/// for this screen.**
///
/// TWO THINGS IT DELIBERATELY DOES NOT SHOW.
///
/// 1. **Wearable sync health.** The data contract splits that tile — *"its connection
///    half is buildable now … its ingestion-health half depends on `WI-13` and waits for
///    `PD-G01`"* — and `PD-G01` is `APPROVED — FUTURE BUILD · implementation NOT
///    AUTHORIZED`. So connections are counted and no latency, sync status or error rate
///    is invented. The card says so rather than leaving a silent hole.
/// 2. **A training "completion rate".** The design asks for *"training content and
///    completion"*; `admin_training_overview` publishes raw counts and no ruled
///    denominator exists for a rate. Counts are shown; a rate is not derived.
class AdminEcosystemScreen extends ConsumerWidget {
  const AdminEcosystemScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        backgroundColor: AdminColors.colorBgCanvas,
        appBar: AppBar(
          backgroundColor: AdminColors.colorBgCanvas,
          surfaceTintColor: AdminColors.colorBgCanvas,
          elevation: 0,
          iconTheme: const IconThemeData(color: AdminColors.colorTextPrimary),
          title: const Text('Ecosystem',
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
            ref.invalidate(adminCommunityOverviewProvider);
            ref.invalidate(adminEventsOverviewProvider);
            ref.invalidate(adminEventDirectoryProvider);
            ref.invalidate(adminTrainingOverviewProvider);
            ref.invalidate(adminRevenueOverviewProvider);
            ref.invalidate(adminWearableConnectionsProvider);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(AdminDims.space8, AdminDims.space6,
                AdminDims.space8, AdminDims.space20),
            children: [
              _overview(ref),
              const SizedBox(height: AdminDims.space6),
              _community(ref),
              const SizedBox(height: AdminDims.space6),
              _moderationQueue(ref),
              const SizedBox(height: AdminDims.space6),
              _events(ref),
              const SizedBox(height: AdminDims.space6),
              const _EventsDirectory(),
              const SizedBox(height: AdminDims.space6),
              _training(ref),
              const SizedBox(height: AdminDims.space6),
              _monetization(ref),
              const SizedBox(height: AdminDims.space6),
              _wearables(ref),
            ],
          ),
        ),
      );

  /// Renders one area, keeping the four states apart: loading · error · no capability ·
  /// the data. A null model means the surface returned no row, which is an authorization
  /// outcome for the whole area — so the card states that rather than vanishing.
  static Widget _area<T>(
    String title,
    AsyncValue<T?> async,
    List<String> labels,
    List<Widget> Function(T) body,
  ) =>
      AdminCard(
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
          data: (v) => v == null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final l in labels)
                      AdminMetricTile.absent(
                          label: l, absence: MetricAbsence.notAuthorized)
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: body(v)),
        ),
      );

  Widget _overview(WidgetRef ref) => _area<AdminCommunityOverview>(
        'Overview',
        ref.watch(adminCommunityOverviewProvider),
        const ['Pods', 'Posts'],
        (m) => [
          AdminMetricTile.of('Pods', m.podsTotal,
              whenNull: MetricAbsence.notAuthorized, zeroCopy: 'None'),
          AdminMetricTile.of('Posts', m.postsTotal,
              whenNull: MetricAbsence.notAuthorized, zeroCopy: 'None'),
        ],
      );

  Widget _community(WidgetRef ref) => _area<AdminCommunityOverview>(
        'Community',
        ref.watch(adminCommunityOverviewProvider),
        const ['Pods', 'Groups', 'Reports open'],
        (m) => [
          AdminMetricTile.of('Pods', m.podsTotal,
              whenNull: MetricAbsence.notAuthorized, zeroCopy: 'None'),
          AdminMetricTile.of('Pods active', m.podsActive,
              whenNull: MetricAbsence.notAuthorized, zeroCopy: 'None'),
          // Reported beside pods, never merged into them — different units.
          AdminMetricTile.of('Groups', m.communityGroupsTotal,
              whenNull: MetricAbsence.notAuthorized, zeroCopy: 'None'),
          AdminMetricTile.of('Posts', m.postsTotal,
              whenNull: MetricAbsence.notAuthorized, zeroCopy: 'None'),
          AdminMetricTile.of('Posts visible', m.postsVisible,
              whenNull: MetricAbsence.notAuthorized, zeroCopy: 'None'),
          // The moderation queue the design names: unresolved reports.
          AdminMetricTile.of('Reports open', m.reportsOpen,
              whenNull: MetricAbsence.notAuthorized, zeroCopy: 'none open'),
        ],
      );

  /// The moderation queue the design names on `#community`.
  ///
  /// `resolved_at IS NULL` IS the queue, by 170's own comment. The actions are gated on
  /// `Community·update` — held by `content_editor` — and the approved read-only state is
  /// rendered and STATED for anyone else. The inventory requires the shape: *"row actions
  /// open confirm dialogs for destructive changes"*, and hiding or removing a member's
  /// post is destructive.
  Widget _moderationQueue(WidgetRef ref) {
    final async = ref.watch(adminOpenReportsProvider);
    final canModerate = ref.watch(adminCanModerateProvider);
    return AdminCard(
      title: 'Moderation queue',
      child: async.when(
        loading: () => const AdminNote('Loading…'),
        error: (_, __) => const AdminNote('Unavailable'),
        data: (reports) {
          if (reports == null) return const AdminNote('Not available to your role');
          if (reports.isEmpty) return const AdminNote('none open');
          // THE DEFECT §189 NAMED WAS HERE FIRST. This queue — including its count — is
          // read under `Community·view`, and it used to sit inside an
          // `adminCapabilityGate` keyed on `Community·update`. A pending or failed
          // moderation-capability check therefore blanked the whole queue. The rows render
          // in all four states now; only the row actions depend on the answer. See
          // [adminGatedList].
          return adminGatedList(
            canModerate,
            denied: 'Read-only: moderating content requires Community · update.',
            rows: (canAct) => [
              AdminMetricTile.value(label: 'Open reports', value: reports.length),
              const SizedBox(height: AdminDims.space4),
              for (final r in reports.take(10))
                _ReportRow(report: r, canModerate: canAct),
              // The reported CONTENT is not shown here, and that is deliberate: 170's
              // moderation path never writes `content`, and a queue that reproduced the
              // reported text would republish it to every moderator before anyone had
              // judged it.
              const AdminFootnote(
                  'The reported text is not reproduced here. Reasons are as the reporter '
                  'wrote them — there is no reason-code list, which is owner vocabulary.'),
            ],
          );
        },
      ),
    );
  }

  Widget _events(WidgetRef ref) => _area<AdminEventsOverview>(
        'Events',
        ref.watch(adminEventsOverviewProvider),
        const ['Events', 'Attendance rate'],
        (m) => [
          // "Create event" is on the approved Ecosystem screen, so the action exists —
          // gated on Events·create, which content_editor holds.
          const _CreateEventAction(),
          AdminMetricTile.of('Events', m.eventsTotal,
              whenNull: MetricAbsence.notAuthorized, zeroCopy: 'None'),
          AdminMetricTile.of('Registrations · 30 d', m.registrations30d,
              whenNull: MetricAbsence.notAuthorized, zeroCopy: 'None'),
          AdminMetricTile.of('Attended', m.registrationsAttended,
              whenNull: MetricAbsence.notAuthorized, zeroCopy: 'None'),
          // NULL with nothing to divide — an A11 state, never "0%".
          if (m.attendanceRatePct != null)
            AdminMetricTile.text(
                label: 'Attendance rate',
                display: '${m.attendanceRatePct!.toStringAsFixed(1)}%')
          else
            const AdminMetricTile.absent(
                label: 'Attendance rate', absence: MetricAbsence.notRecorded),
        ],
      );

  Widget _training(WidgetRef ref) => _area<AdminTrainingOverview>(
        'Training',
        ref.watch(adminTrainingOverviewProvider),
        const ['Programs', 'Sessions'],
        (m) => [
          AdminMetricTile.of('Programs', m.programsTotal,
              whenNull: MetricAbsence.notAuthorized, zeroCopy: 'None'),
          AdminMetricTile.of('Workouts', m.workoutsTotal,
              whenNull: MetricAbsence.notAuthorized, zeroCopy: 'None'),
          AdminMetricTile.of('Sessions', m.sessionsTotal,
              whenNull: MetricAbsence.notAuthorized, zeroCopy: 'None'),
          AdminMetricTile.of('Logs', m.logsTotal,
              whenNull: MetricAbsence.notAuthorized, zeroCopy: 'None'),
          const AdminFootnote(
              'Counts only. No completion rate is derived — the design asks for '
              '"completion" and no ruled denominator exists for one.'),
        ],
      );

  Widget _monetization(WidgetRef ref) => _area<AdminRevenueOverview>(
        'Monetization',
        ref.watch(adminRevenueOverviewProvider),
        const ['Gross coaching', 'Paid to coaches'],
        (m) {
          final cur = (m.sourceCurrency ?? '').toUpperCase();
          String? money(int? c) =>
              c == null ? null : '$cur ${(c / 100).toStringAsFixed(2)}';
          Widget tile(String label, String? d) => d == null
              ? AdminMetricTile.absent(
                  label: label, absence: MetricAbsence.notAuthorized)
              : AdminMetricTile.text(label: label, display: d);
          return [
            tile('Gross coaching', money(m.grossCoachingCents)),
            tile('Platform commission', money(m.platformCommissionCents)),
            // The split as recorded — never derived from amount x rate.
            tile('Paid to coaches', money(m.coachPayoutCents)),
            tile('Platform fee', money(m.platformFeeCents)),
            if (m.payoutMissing != null && m.payoutMissing! > 0)
              AdminMetricTile.of('Payments with no recorded split', m.payoutMissing,
                  whenNull: MetricAbsence.notAuthorized),
            if (!m.commissionIsComplete)
              AdminMetricTile.of(
                  'Payments with no recorded rate', m.commissionRateMissing,
                  whenNull: MetricAbsence.notAuthorized),
            // THE "plans" HALF OF THIS REQUIREMENT IS RENDERED, JUST NOT HERE. The page's
            // stated requirement is "monetisation (plans, payouts, commission)": the payout
            // split and the commission decomposition are above, and the per-plan figures are
            // the per-stream breakdown the design places on the Control Center under
            // "revenue by stream" (migration 178, rendered by AdminMetricsPanel). Saying so
            // is the design's own cross-linking model; duplicating the card here would show
            // one set of figures in two places with no ruling that it belongs in both.
            const AdminFootnote(
                'Per-plan revenue is the per-stream breakdown on the Control Center — the '
                'design places "revenue by stream" there. This card carries the coaching '
                'decomposition and the recorded payout split.'),
          ];
        },
      );

  Widget _wearables(WidgetRef ref) => _area<AdminWearableConnections>(
        'Wearables',
        ref.watch(adminWearableConnectionsProvider),
        const ['Connections'],
        (m) => [
          AdminMetricTile.value(
              label: 'Connections', value: m.connectedTotal, zeroCopy: 'None'),
          for (final e in m.byProvider.entries)
            AdminMetricTile.value(label: e.key, value: e.value),
          // PD-G01 is APPROVED — FUTURE BUILD, implementation NOT AUTHORIZED. The
          // absence of sync health is a ruling, so the card states it rather than
          // leaving a hole a reader would assume was an oversight.
          const AdminFootnote(
              'Connections only. Sync health, latency and ingestion errors are WI-13 '
              'and wait on PD-G01 — nothing here estimates them.'),
        ],
      );
}


/// One open report. Carries the destructive actions only for a caller holding
/// `Community·update`, and only behind a confirm dialog that names what will change.
class _ReportRow extends ConsumerWidget {
  const _ReportRow({required this.report, required this.canModerate});

  final AdminContentReport report;
  final bool canModerate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final when = report.createdAt?.toIso8601String().split('T').first;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AdminDims.space3),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    if (report.targetType != null) report.targetType!,
                    if (when != null) when,
                  ].join(' · '),
                  style: const TextStyle(
                    color: AdminColors.colorTextPrimary,
                    fontSize: AdminDims.typeSmallSize,
                  ),
                ),
                // The reporter's own words, shown as written and never mapped to an enum.
                Text(report.reason ?? 'no reason given',
                    style: const TextStyle(
                      color: AdminColors.colorTextSubtle,
                      fontSize: AdminDims.typeCaptionSize,
                    )),
              ],
            ),
          ),
          if (canModerate && report.id != null && report.targetId != null) ...[
            _action(context, ref, 'Hide', 'hidden'),
            _action(context, ref, 'Dismiss', null),
          ],
        ],
      ),
    );
  }

  Widget _action(BuildContext context, WidgetRef ref, String label, String? state) =>
      SizedBox(
        height: AdminDims.sizeControl, // 44px, RESPONSIVE.md
        child: TextButton(
          onPressed: () => _confirm(context, ref, label, state),
          style: TextButton.styleFrom(
            foregroundColor: state == null
                ? AdminColors.colorTextMuted
                : AdminColors.colorStatusWarningText,
            minimumSize: const Size(AdminDims.sizeControl, AdminDims.sizeControl),
          ),
          child: Text(label,
              style: const TextStyle(
                fontSize: AdminDims.typeCaptionSize,
                fontWeight: FontWeight.w500,
              )),
        ),
      );

  Future<void> _confirm(
      BuildContext context, WidgetRef ref, String label, String? state) async {
    final destructive = state != null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminColors.colorBgSurface,
        title: Text(destructive ? 'Hide this content?' : 'Dismiss this report?',
            style: const TextStyle(
                color: AdminColors.colorTextPrimary,
                fontSize: AdminDims.typeCardTitleSize)),
        content: Text(
          destructive
              // Says exactly what changes and what does not. 170 never writes `content`.
              ? 'The ${report.targetType ?? 'content'} will be hidden from everyone except '
                  'its author and the Community admins. Its text is not altered or '
                  'deleted, and the change is audited.'
              : 'The report is marked resolved. The reported '
                  '${report.targetType ?? 'content'} is left exactly as it is.',
          style: const TextStyle(
              color: AdminColors.colorTextSecondary,
              fontSize: AdminDims.typeSmallSize),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: AdminColors.colorTextMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(destructive ? 'Hide' : 'Dismiss',
                style: const TextStyle(
                    color: AdminColors.colorBrandAccent,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final svc = ref.read(adminMetricsServiceProvider);
    try {
      if (destructive) {
        await svc.moderate(report.targetType!, report.targetId!, state);
      }
      await svc.resolveReport(report.id!);
      ref.invalidate(adminOpenReportsProvider);
      ref.invalidate(adminCommunityOverviewProvider);
    } catch (e, st) {
      // Reported, not shown raw (ERR-G2), and never silent — a moderation action that
      // was refused must not read as one that succeeded.
      reportError('admin_ecosystem.moderate', e, st, {
        'report_id': report.id,
        'target_type': report.targetType,
        'state': state,
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: AdminColors.colorBgRaised,
          content: Text(
              'That action was not applied. You may not have permission, or the report '
              'has changed. Nothing was altered.',
              style: TextStyle(color: AdminColors.colorStatusDangerText)),
        ));
      }
    }
  }
}


/// The approved screen's "Create event" action.
///
/// DESCRIPTIVE FIELDS ONLY, and that is the governed path's rule rather than this form's
/// simplicity: `admin_create_event` (165) accepts title, date, description, location,
/// end date, cover image, host and capacity — and deliberately NOT `price`, `is_free`,
/// `status`, `current_registered` or `vendor_id`. An Admin may describe an event; pricing,
/// publishing and vendor assignment are not Admin acts. The form offers no field for them
/// because the function has no parameter for them, and a form that collected them would
/// imply an authority that does not exist.
class _CreateEventAction extends ConsumerWidget {
  const _CreateEventAction();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return adminCapabilityGate(
      ref.watch(adminCanCreateEventsProvider),
      denied: const AdminFootnote(
          'Read-only: creating an event requires Events · create.'),
      allowed: () => _button(context, ref),
    );
  }

  Widget _button(BuildContext context, WidgetRef ref) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        height: AdminDims.sizeControl, // 44px, RESPONSIVE.md
        child: TextButton(
          onPressed: () => _open(context, ref),
          style: TextButton.styleFrom(
            foregroundColor: AdminColors.colorBrandAccent,
            minimumSize: const Size(AdminDims.sizeControl, AdminDims.sizeControl),
          ),
          child: const Text('Create event',
              style: TextStyle(
                fontSize: AdminDims.typeCaptionSize,
                fontWeight: FontWeight.w500,
              )),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final title = TextEditingController();
    final location = TextEditingController();
    final capacity = TextEditingController();
    DateTime? when;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: AdminColors.colorBgSurface,
          title: const Text('Create event',
              style: TextStyle(
                  color: AdminColors.colorTextPrimary,
                  fontSize: AdminDims.typeCardTitleSize)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: title,
                style: const TextStyle(
                    color: AdminColors.colorTextPrimary,
                    fontSize: AdminDims.typeSmallSize),
                decoration: const InputDecoration(
                  labelText: 'Title',
                  labelStyle: TextStyle(color: AdminColors.colorTextMuted),
                ),
              ),
              TextField(
                controller: location,
                style: const TextStyle(
                    color: AdminColors.colorTextPrimary,
                    fontSize: AdminDims.typeSmallSize),
                decoration: const InputDecoration(
                  labelText: 'Location',
                  labelStyle: TextStyle(color: AdminColors.colorTextMuted),
                ),
              ),
              TextField(
                controller: capacity,
                keyboardType: TextInputType.number,
                style: const TextStyle(
                    color: AdminColors.colorTextPrimary,
                    fontSize: AdminDims.typeSmallSize),
                decoration: const InputDecoration(
                  labelText: 'Capacity',
                  labelStyle: TextStyle(color: AdminColors.colorTextMuted),
                ),
              ),
              const SizedBox(height: AdminDims.space6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                        when == null
                            ? 'No date chosen'
                            : when!.toIso8601String().split('T').first,
                        style: const TextStyle(
                            color: AdminColors.colorTextSecondary,
                            fontSize: AdminDims.typeSmallSize)),
                  ),
                  TextButton(
                    onPressed: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: now,
                        firstDate: now,
                        lastDate: DateTime(now.year + 3),
                      );
                      // `ctx.mounted` first. LIFE-G1 caught this calling setState after
                      // an await with no check — the dialog can be dismissed while the
                      // date picker is open, and setState on a disposed element throws.
                      if (picked != null && ctx.mounted) {
                        setState(() => when = picked);
                      }
                    },
                    child: const Text('Choose date',
                        style: TextStyle(color: AdminColors.colorBrandAccent)),
                  ),
                ],
              ),
              const SizedBox(height: AdminDims.space4),
              // Says what an Admin may NOT set, so its absence is not read as a
              // missing field.
              const Text(
                  'Price, free/paid, publication status and vendor are not set here — '
                  'the governed path accepts none of them.',
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
              child: const Text('Create',
                  style: TextStyle(
                      color: AdminColors.colorBrandAccent,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final t = title.text.trim();
    // The governed path requires a title and a date; the form does not pretend otherwise.
    if (t.isEmpty || when == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: AdminColors.colorBgRaised,
          content: Text('An event needs a title and a date. Nothing was created.',
              style: TextStyle(color: AdminColors.colorStatusWarningText)),
        ));
      }
      return;
    }
    try {
      await ref.read(adminMetricsServiceProvider).createEvent(
            title: t,
            eventDate: when!,
            location: location.text.trim().isEmpty ? null : location.text.trim(),
            maxCapacity: int.tryParse(capacity.text.trim()),
          );
      ref.invalidate(adminEventsOverviewProvider);
    } catch (e, st) {
      reportError('admin_ecosystem.createEvent', e, st, {'title': t});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: AdminColors.colorBgRaised,
          content: Text(
              'The event was not created. You may not have permission. Nothing was '
              'saved.',
              style: TextStyle(color: AdminColors.colorStatusDangerText)),
        ));
      }
    }
  }
}


/// The approved Ecosystem screen's Events directory, and the "Edit event" action that
/// its Event detail panel carries.
///
/// WHY THE LIST EXISTS AT ALL. `admin_update_event` (165) has been applied since §18x and
/// nothing could reach it: the page showed only `admin_events_overview`, an aggregate, and
/// an edit action needs a subject. The directory is the missing half, and it needed no
/// schema — 156:45 already grants a full `events` read to `Events·view`.
///
/// THREE DESIGNED COLUMNS ARE NAMED RATHER THAN FILLED. "Type" has no column at all,
/// "Status" exists but holds no ruled vocabulary, and event revenue sits behind the
/// Finance viewer role, which this card does not test — so it is not read. See
/// [AdminEventRow].
///
/// THE EDIT FORM SENDS ONLY WHAT CHANGED. 165 coalesces each argument against the stored
/// column, so an omitted field is left alone. Echoing back every field — including the
/// ones the operator never touched — would make this form silently revert a concurrent
/// edit, so each controller is compared against what was read and unchanged fields are
/// sent as null.
class _EventsDirectory extends ConsumerWidget {
  const _EventsDirectory();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminEventDirectoryProvider);
    final canEdit = ref.watch(adminCanUpdateEventsProvider);
    return AdminCard(
      title: 'Events directory',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The approved placeholder is only "Search events" — it does not name its fields,
          // so the note states the one field matched rather than implying all of them.
          AdminSearchBox(
            hint: 'Search events',
            fieldsNote: 'Searches the event title only. Location, host and status are not '
                'matched, so a result of none means no title match.',
            value: ref.watch(adminEventSearchProvider),
            onChanged: (v) =>
                ref.read(adminEventSearchProvider.notifier).state = v,
          ),
          const SizedBox(height: AdminDims.space4),
          async.when(
        loading: () => const AdminNote('Loading…'),
        error: (_, __) => const AdminNote('Unavailable'),
        data: (events) {
          if (events == null) return const AdminNote('Not available to your role');
          // The approved screen's own empty wording. It is only reachable once the
          // capability has been confirmed, so it cannot stand in for a denial.
          if (events.isEmpty) {
            // The approved empty wording when nothing is filtered; a distinct sentence
            // when a query is active, so a filter cannot read as a fact about the range.
            return AdminNote(ref.watch(adminEventSearchProvider).trim().isEmpty
                ? 'No events in this range.'
                : 'No event title matches that search');
          }
          // THE GATE WRAPS EACH ROW'S ACTION, NOT THE ROWS. Wrapping the list meant
          // that while the `Events·update` check was in flight, "Checking your
          // permissions…" replaced every event — hiding records `Events·view` had already
          // authorized, on the strength of a pending answer about a different verb.
          // ONE decision, in one `when`, for all four states — and the rows render in
          // every one of them. See [adminGatedList].
          return adminGatedList(
            canEdit,
            denied: 'Read-only: editing an event requires Events · update.',
            rows: (canAct) => [
              for (final e in events.take(10)) _EventRow(event: e, canEdit: canAct),
              const AdminFootnote(
                  'Status is shown as recorded. The design\'s Scheduled/Full/Live/'
                  'Draft/Cancelled labels are not a vocabulary this column holds, and '
                  'event type has no column at all.'),
              const AdminFootnote(
                  'Price, publication status and vendor are not editable here — the '
                  'governed path accepts none of them. Event revenue needs the '
                  'Finance viewer role and is not read on this card.'),
            ],
          );
        },
          ),
        ],
      ),
    );
  }
}

class _EventRow extends ConsumerWidget {
  const _EventRow({required this.event, required this.canEdit});

  final AdminEventRow event;

  /// A confirmed `true` from the parent — never a collapsed error. The card states a failed
  /// check once via [adminGatedList]; this flag only decides whether a button draws.
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final when = event.eventDate;
    final cap = event.maxCapacity;
    final reg = event.currentRegistered;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AdminDims.space3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.title ?? 'Untitled',
                    style: const TextStyle(
                        color: AdminColors.colorTextPrimary,
                        fontSize: AdminDims.typeSmallSize,
                        fontWeight: FontWeight.w500)),
                Text(
                    [
                      // Each absence is stated, never filled with a plausible blank.
                      when == null
                          ? 'No date recorded'
                          : when.toIso8601String().split('T').first,
                      event.location ?? 'No location recorded',
                      event.status ?? 'No status recorded',
                      // Registered/capacity is only a pair when BOTH are recorded.
                      if (reg != null && cap != null)
                        '$reg / $cap registered'
                      else if (reg != null)
                        '$reg registered · no capacity recorded'
                      else
                        'Registrations not recorded',
                    ].join(' · '),
                    style: const TextStyle(
                        color: AdminColors.colorTextMuted,
                        fontSize: AdminDims.typeCaptionSize)),
              ],
            ),
          ),
          if (canEdit)
            SizedBox(
              height: AdminDims.sizeControl,
              child: TextButton(
                onPressed: event.id == null ? null : () => _edit(context, ref),
                style: TextButton.styleFrom(
                  foregroundColor: AdminColors.colorBrandAccent,
                  minimumSize:
                      const Size(AdminDims.sizeControl, AdminDims.sizeControl),
                ),
                child: const Text('Edit event',
                    style: TextStyle(fontSize: AdminDims.typeCaptionSize)),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final title = TextEditingController(text: event.title ?? '');
    final location = TextEditingController(text: event.location ?? '');
    final capacity = TextEditingController(
        text: event.maxCapacity == null ? '' : '${event.maxCapacity}');
    DateTime? when = event.eventDate;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: AdminColors.colorBgSurface,
          title: const Text('Edit event',
              style: TextStyle(
                  color: AdminColors.colorTextPrimary,
                  fontSize: AdminDims.typeCardTitleSize)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _field(title, 'Title'),
              _field(location, 'Location'),
              _field(capacity, 'Capacity', number: true),
              const SizedBox(height: AdminDims.space6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                        when == null
                            ? 'No date recorded'
                            : when!.toIso8601String().split('T').first,
                        style: const TextStyle(
                            color: AdminColors.colorTextSecondary,
                            fontSize: AdminDims.typeSmallSize)),
                  ),
                  TextButton(
                    onPressed: () async {
                      final base = when ?? DateTime.now();
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: base,
                        // An existing event may legitimately be in the past, so the
                        // lower bound is the event itself, not today — unlike the create
                        // form, where a past date would be a new mistake.
                        firstDate: base.isBefore(DateTime(2020))
                            ? DateTime(2020)
                            : DateTime(base.year - 3),
                        lastDate: DateTime(DateTime.now().year + 3),
                      );
                      // `ctx.mounted` before setState after an await — LIFE-G1.
                      if (picked != null && ctx.mounted) {
                        setState(() => when = picked);
                      }
                    },
                    child: const Text('Change date',
                        style: TextStyle(color: AdminColors.colorBrandAccent)),
                  ),
                ],
              ),
              const SizedBox(height: AdminDims.space4),
              const Text(
                  'Price, free/paid, publication status and vendor are not set here — '
                  'the governed path accepts none of them. Clearing a field leaves it '
                  'unchanged; it cannot blank a value.',
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
      ),
    );
    if (ok != true) return;

    // ONLY WHAT CHANGED. See the class note: a field echoed back unchanged would let this
    // form revert someone else's concurrent edit.
    final newTitle = _changed(title.text, event.title);
    final newLocation = _changed(location.text, event.location);
    final parsedCap = int.tryParse(capacity.text.trim());
    final newCap = parsedCap == event.maxCapacity ? null : parsedCap;
    final newWhen = when == event.eventDate ? null : when;

    if (newTitle == null &&
        newLocation == null &&
        newCap == null &&
        newWhen == null) {
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
      await ref.read(adminMetricsServiceProvider).updateEvent(
            eventId: event.id!,
            title: newTitle,
            location: newLocation,
            eventDate: newWhen,
            maxCapacity: newCap,
          );
      ref.invalidate(adminEventDirectoryProvider);
      ref.invalidate(adminEventsOverviewProvider);
    } catch (e, st) {
      // The detail goes to the error sink, never into the sentence the operator reads —
      // ERR-G2. And the sentence does not claim the write was saved.
      reportError('admin_ecosystem.updateEvent', e, st, {'event': event.id});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: AdminColors.colorBgRaised,
          content: Text(
              'The event was not updated. You may not have permission. Nothing was '
              'saved.',
              style: TextStyle(color: AdminColors.colorStatusDangerText)),
        ));
      }
    }
  }

  /// Null when the field is unchanged OR emptied — 165 treats null as "leave alone", and
  /// it refuses a blank title anyway, so an emptied box is not a request to erase.
  static String? _changed(String raw, String? was) {
    final v = raw.trim();
    if (v.isEmpty) return null;
    return v == (was ?? '') ? null : v;
  }

  static Widget _field(TextEditingController c, String label,
          {bool number = false}) =>
      TextField(
        controller: c,
        keyboardType: number ? TextInputType.number : null,
        style: const TextStyle(
            color: AdminColors.colorTextPrimary, fontSize: AdminDims.typeSmallSize),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: AdminColors.colorTextMuted),
        ),
      );
}
