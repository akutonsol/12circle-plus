import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/admin_metrics.dart';

/// V5 §163 — data access for the owner-approved Admin metric surfaces
/// (migrations 171–173).
///
/// WHY THESE ARE VIEW READS AND NOT RPCs. The existing [AdminService] calls
/// `admin_platform_stats()`, which is gated on `is_admin()` alone — one
/// cross-area gate for every figure on the dashboard. These surfaces are gated
/// PER AREA inside each view's own `WHERE`, against the approved capability
/// matrix, so a `content_editor` sees the Users panel and not the revenue panel
/// without the service having to know anything about roles.
///
/// WHY EVERY METHOD RETURNS A NULLABLE MODEL. A view whose `WHERE` fails returns
/// NO ROW, not an error and not zeros. `maybeSingle()` surfaces that as null,
/// which the UI renders as the approved `A11` state. Translating it into an empty
/// model full of zeros would tell an unauthorized viewer that the platform has no
/// users, no revenue and no events — a false statement, and for METRIC-02 an
/// inference about the audit population.
class AdminMetricsService {
  AdminMetricsService({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;

  Future<AdminActivityOverview?> getActivityOverview() async =>
      _one('admin_activity_overview', AdminActivityOverview.fromRow);

  Future<AdminUserOverview?> getUserOverview() async =>
      _one('admin_user_overview', AdminUserOverview.fromRow);

  Future<AdminEventsOverview?> getEventsOverview() async =>
      _one('admin_events_overview', AdminEventsOverview.fromRow);

  Future<AdminCommunityOverview?> getCommunityOverview() async =>
      _one('admin_community_overview', AdminCommunityOverview.fromRow);

  Future<AdminRevenueOverview?> getRevenueOverview() async =>
      _one('admin_revenue_overview', AdminRevenueOverview.fromRow);

  /// METRIC-11. Returns null when no release has been recorded for the
  /// environment — which is the current state, because the CI ingestion path is
  /// gated on `P10`/`CONF-D9` and is not built. The card renders `A11`.
  Future<AdminReleaseStatus?> getReleaseStatus() async =>
      _one('admin_release_status', AdminReleaseStatus.fromRow);

  /// `DESIGN-01` §1 — the attention queue's population.
  ///
  /// THREE STATES, AND A LIST READ CANNOT EXPRESS THEM ALONE. `admin_incidents`
  /// gates inside its own `WHERE`, so an uncapable caller and an incident-free
  /// platform BOTH come back as `[]`. Those are different facts: one is an
  /// authorization outcome, the other is the design's "none raised" zero state. An
  /// earlier draft of this method documented a distinction it did not actually make,
  /// which is worse than not making it.
  ///
  /// So the capability is ASKED FOR rather than inferred from emptiness.
  /// `admin_can(text, text)` is `SECURITY DEFINER` with `EXECUTE` granted to
  /// `authenticated` (`153:127`), and D13 proves it returns the right boolean for
  /// every area/verb pair. Hence:
  ///
  ///   * `null`         → the caller does not hold `Incidents·view`;
  ///   * `[]`           → authorized, nothing raised;
  ///   * a populated list → the queue.
  Future<List<AdminIncident>?> getIncidents({int limit = 20}) async {
    final permitted = await _db.rpc('admin_can',
        params: {'p_area': 'Incidents', 'p_verb': 'view'});
    if (permitted != true) return null;

    final rows = await _db
        .from('admin_incidents')
        .select()
        .order('occurred_at', ascending: false)
        .limit(limit);
    return [
      for (final r in rows) AdminIncident.fromRow(Map<String, dynamic>.from(r)),
    ];
  }

  Future<AdminTrainingOverview?> getTrainingOverview() async =>
      _one('admin_training_overview', AdminTrainingOverview.fromRow);

  /// Wearable CONNECTION counts. Selects `provider, connected` only — the view also
  /// projects `user_id`, which this page does not need, so the identifier never leaves
  /// the database. Returns null when the caller lacks `Wearable intelligence·view`,
  /// asked rather than inferred from an empty read.
  Future<AdminWearableConnections?> getWearableConnections() async {
    final permitted = await _db.rpc('admin_can',
        params: {'p_area': 'Wearable intelligence', 'p_verb': 'view'});
    if (permitted != true) return null;
    final rows = await _db.from('admin_integration_connections')
        .select('provider, connected');
    return AdminWearableConnections.fromRows(
        [for (final r in rows) Map<String, dynamic>.from(r)]);
  }

  /// The Users-area account list. Returns null when the caller lacks `Users·view`, asked
  /// rather than inferred from an empty read. `avatar_url` is in 160's projection and is
  /// NOT selected — this page lists accounts, and a column a page does not use should not
  /// cross the wire.
  /// `query` searches **name or email**, which is the approved screen's own placeholder —
  /// *"Search name or email"* — so the fields are specified by the design rather than chosen
  /// here. The match is a case-insensitive substring, and it runs SERVER-SIDE: filtering the
  /// `limit`-capped page on the client would search a 20-row window and report "no match"
  /// for records that exist, which is a false negative dressed as an answer.
  Future<List<AdminUserDirectoryEntry>?> getUserDirectory(
      {int limit = 50, String? query}) async {
    final permitted = await _db
        .rpc('admin_can', params: {'p_area': 'Users', 'p_verb': 'view'});
    if (permitted != true) return null;
    final term = _searchTerm(query);
    var q = _db
        .from('admin_user_directory')
        .select('id, first_name, last_name, email, role, membership_tier, '
            'onboarding_complete, created_at');
    if (term != null) {
      q = q.or('first_name.ilike.%$term%,last_name.ilike.%$term%,email.ilike.%$term%');
    }
    final rows = await q
        .order('created_at', ascending: false)
        .limit(limit);
    return [
      for (final r in rows)
        AdminUserDirectoryEntry.fromRow(Map<String, dynamic>.from(r)),
    ];
  }

  /// The approved capability matrix, gated `Roles·view` (156). Returns null when the
  /// caller lacks it, asked rather than inferred from an empty read.
  Future<List<AdminRoleCapability>?> getRoleCapabilities() async {
    final permitted = await _db
        .rpc('admin_can', params: {'p_area': 'Roles', 'p_verb': 'view'});
    if (permitted != true) return null;
    final rows = await _db
        .from('admin_role_capabilities')
        .select('admin_role, area, verb')
        .order('area', ascending: true);
    return [
      for (final r in rows) AdminRoleCapability.fromRow(Map<String, dynamic>.from(r)),
    ];
  }

  /// Role ASSIGNMENTS — who holds an Admin role. Gated `Roles·view` (156).
  Future<int?> getAdministratorCount() async {
    final permitted = await _db
        .rpc('admin_can', params: {'p_area': 'Roles', 'p_verb': 'view'});
    if (permitted != true) return null;
    final rows = await _db.from('admin_role_assignments').select('user_id');
    return rows.length;
  }

  /// `platform_settings`, gated `Configuration·view`. The store is generic key/value, so
  /// the values are carried as text and interpreted nowhere.
  Future<List<AdminPlatformSetting>?> getPlatformSettings() async {
    final permitted = await _db
        .rpc('admin_can', params: {'p_area': 'Configuration', 'p_verb': 'view'});
    if (permitted != true) return null;
    final rows = await _db
        .from('platform_settings')
        .select('key, value, updated_at')
        .order('key', ascending: true);
    return [
      for (final r in rows) AdminPlatformSetting.fromRow(Map<String, dynamic>.from(r)),
    ];
  }

  /// The OPEN moderation queue — `resolved_at IS NULL` is the queue, by 170's own
  /// comment. `reporter_id` is deliberately NOT selected: judging a post does not require
  /// knowing who reported it, and a queue that names reporters discourages reporting.
  Future<List<AdminContentReport>?> getOpenReports({int limit = 50}) async {
    final permitted = await _db
        .rpc('admin_can', params: {'p_area': 'Community', 'p_verb': 'view'});
    if (permitted != true) return null;
    final rows = await _db
        .from('content_reports')
        .select('id, target_type, target_id, reason, created_at')
        .isFilter('resolved_at', null)
        .order('created_at', ascending: true)
        .limit(limit);
    return [
      for (final r in rows) AdminContentReport.fromRow(Map<String, dynamic>.from(r)),
    ];
  }

  Future<bool> canModerate() async {
    final r = await _db
        .rpc('admin_can', params: {'p_area': 'Community', 'p_verb': 'update'});
    return r == true;
  }

  /// Hides or removes reported content through the governed path
  /// (`admin_moderate_content`, 170), which is `SECURITY DEFINER`, re-checks
  /// `admin_can('Community','update')` itself and **never writes `content`** — it changes
  /// `moderation_state` and records who and why. The error is allowed to surface.
  Future<void> moderate(String targetType, String targetId, String state,
          {String? reason}) =>
      _db.rpc('admin_moderate_content', params: {
        'p_target_type': targetType,
        'p_target_id': targetId,
        'p_state': state,
        if (reason != null) 'p_reason': reason,
      });

  Future<void> resolveReport(String reportId) =>
      _db.rpc('admin_resolve_report', params: {'p_report_id': reportId});

  Future<bool> canCreateEvents() async {
    final r = await _db
        .rpc('admin_can', params: {'p_area': 'Events', 'p_verb': 'create'});
    return r == true;
  }

  /// Creates an event through the governed path (`admin_create_event`, 165), which is
  /// `SECURITY DEFINER` and re-checks `admin_can('Events','create')` itself.
  ///
  /// IT TAKES DESCRIPTIVE FIELDS ONLY, and that is 165's design rather than this method's
  /// convenience: the function's parameter list has no `price`, `is_free`, `status`,
  /// `current_registered` or `vendor_id`. An Admin may describe an event; it may not price
  /// one, publish one or assign it to a vendor. There is no parameter here because there
  /// is none there.
  Future<String?> createEvent({
    required String title,
    required DateTime eventDate,
    String? description,
    String? location,
    int? maxCapacity,
  }) async {
    final id = await _db.rpc('admin_create_event', params: {
      'p_title': title,
      'p_event_date': eventDate.toIso8601String(),
      if (description != null) 'p_description': description,
      if (location != null) 'p_location': location,
      if (maxCapacity != null) 'p_max_capacity': maxCapacity,
    });
    return id as String?;
  }

  /// The approved Ecosystem screen's Events directory.
  ///
  /// EXPLICIT COLUMNS, NOT `select()`. The table carries `price` and `is_free`, and the
  /// approved screen gates event revenue behind the Finance viewer role — a Monetization
  /// capability this read does not test. A bare `select()` under an Events·view gate
  /// would hand a monetary figure to a role that was never granted it, so every column
  /// is named. See [AdminEventRow] for the two designed columns that have no backing.
  ///
  /// NO `status` FILTER. Drafts and cancelled events are exactly what an operator needs
  /// to find, and 156:45 already permits reading them; filtering to 'upcoming' here
  /// would hide the rows the directory exists to show.
  /// ASKS FIRST, exactly as [getUserDirectory] does and for the same reason: 156:45 is
  /// an RLS policy, and a SELECT it filters out is not an error — PostgREST answers
  /// `200 []`. Inferring authorization from an empty list would render an unauthorized
  /// read as the approved screen's "No events in this range", which is a confident lie.
  /// So `admin_can('Events','view')` is asked, and null means NO CAPABILITY while empty
  /// means authorized with nothing to show.
  /// `query` searches the event **title**, and that single field is a deliberate narrowing.
  /// The approved placeholder reads only *"Search events"* — unlike People's *"Search name or
  /// email"*, it does not name its fields — so the title is the minimal faithful reading and
  /// the UI states which field is searched rather than leaving a reader to guess. Adding
  /// location or host would be choosing scope the design did not specify.
  Future<List<AdminEventRow>?> eventDirectory({int limit = 50, String? query}) async {
    final permitted = await _db
        .rpc('admin_can', params: {'p_area': 'Events', 'p_verb': 'view'});
    if (permitted != true) return null;
    final term = _searchTerm(query);
    var q = _db
        .from('events')
        .select('id,title,location,event_date,end_date,host_name,'
            'max_capacity,current_registered,status,description');
    if (term != null) q = q.ilike('title', '%$term%');
    final rows = await q
        .order('event_date', ascending: false)
        .limit(limit);
    return [
      for (final r in rows) AdminEventRow.fromRow(Map<String, dynamic>.from(r)),
    ];
  }

  Future<bool> canUpdateEvents() async {
    final r = await _db
        .rpc('admin_can', params: {'p_area': 'Events', 'p_verb': 'update'});
    return r == true;
  }

  /// Edits an event through the governed path (`admin_update_event`, 165), which is
  /// `SECURITY DEFINER` and re-checks `admin_can('Events','update')` itself.
  ///
  /// WHY A NULL ARGUMENT IS NOT AN ERASURE. 165 coalesces every field against the
  /// existing column, so omitting one leaves it alone — the function cannot blank a
  /// value it was not asked to change. That makes the caller's duty the opposite of
  /// the usual one: it must send `null` for an untouched field rather than echoing
  /// back what it last read, because echoing a stale read is how a concurrent edit
  /// gets silently reverted.
  ///
  /// The same exclusions as [createEvent] apply and for the same reason: 165's
  /// parameter list carries no `price`, `is_free`, `status`, `current_registered` or
  /// `vendor_id`. An Admin may re-describe an event; it may not re-price or publish one.
  Future<void> updateEvent({
    required String eventId,
    String? title,
    String? description,
    String? location,
    DateTime? eventDate,
    int? maxCapacity,
  }) =>
      _db.rpc('admin_update_event', params: {
        'p_event_id': eventId,
        if (title != null) 'p_title': title,
        if (description != null) 'p_description': description,
        if (location != null) 'p_location': location,
        if (eventDate != null) 'p_event_date': eventDate.toIso8601String(),
        if (maxCapacity != null) 'p_max_capacity': maxCapacity,
      });

  Future<bool> canUpdateUsers() async {
    final r = await _db
        .rpc('admin_can', params: {'p_area': 'Users', 'p_verb': 'update'});
    return r == true;
  }

  /// Renames a user through the governed path (`admin_update_user_name`, 161), which is
  /// `SECURITY DEFINER` and re-checks `admin_can('Users','update')` itself.
  ///
  /// THIS IS THE WHOLE OF "Edit profile" THAT A BACKEND EXISTS FOR. The approved People
  /// screen's row menu also offers "Change role", and that action is deliberately absent
  /// here: `admin_set_user_role` (115:363) gates on the legacy `is_admin()` — a
  /// `user_profiles.role = 'admin'` test — and NOT on the capability matrix that every
  /// other Admin surface, including this method, is gated by. Offering it beside this
  /// one would either show an enabled control to a `Users·update` holder who will be
  /// refused, or require widening role assignment to those holders. Which of those is
  /// correct is an authorization decision, not a wiring detail.
  ///
  /// 161 refuses a blank name and a name over 100 characters, and records only the
  /// CHANGED COLUMN NAMES — never the values, which would re-identify the pseudonymous
  /// subject of its own audit row.
  Future<void> updateUserName({
    required String userId,
    String? firstName,
    String? lastName,
  }) =>
      _db.rpc('admin_update_user_name', params: {
        'p_user_id': userId,
        'p_first_name': firstName,
        'p_last_name': lastName,
      });

  Future<T?> _one<T>(
    String view,
    T Function(Map<String, dynamic>) parse,
  ) async {
    final row = await _db.from(view).select().maybeSingle();
    if (row == null) return null;
    return parse(Map<String, dynamic>.from(row));
  }
}

/// Sanitises a free-text query for use inside a PostgREST filter expression.
///
/// WHY THIS IS A SECURITY FUNCTION AND NOT A TIDYING ONE. PostgREST's filter grammar is
/// punctuation: `or=(a.ilike.*x*,b.ilike.*x*)` is parsed on `,` `.` `(` `)` and `*`. A query
/// containing any of those does not merely fail to match — it **re-parses the expression**,
/// and a crafted value can append a disjunct, which on an `or=` is a widening: it could make
/// a filter match rows the caller never asked for. These surfaces are already gated by
/// `admin_can`, so this is not a privilege escape; it is still a query the operator did not
/// write, and the filter must mean what the box said.
///
/// STRIPPING RATHER THAN ESCAPING, deliberately. PostgREST's quoting rules differ per
/// operator and per version, so an escape that is correct today is a dependency on a parser
/// detail; removing the grammar characters cannot be wrong. A query of only punctuation
/// therefore becomes empty, which the callers treat as "no filter" rather than as
/// "match nothing" — see each call site.
///
/// `%` and `_` are removed too: they are LIKE wildcards, so leaving them would let a typed
/// `%` silently widen the match the operator thinks they asked for.
String? _searchTerm(String? raw) {
  if (raw == null) return null;
  final cleaned = raw.replaceAll(RegExp(r'[,.()*%_"\\]'), ' ').trim();
  return cleaned.isEmpty ? null : cleaned;
}
