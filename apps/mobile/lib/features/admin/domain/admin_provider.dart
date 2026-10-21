import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/app_env.dart';
import '../data/admin_metrics_service.dart';
import '../data/admin_trust_service.dart';
import '../data/admin_service.dart';
import 'admin_metrics.dart';
import 'admin_trust.dart';

final adminServiceProvider = Provider<AdminService>((ref) => AdminService());

final platformStatsProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  return ref.watch(adminServiceProvider).getPlatformStats();
});

final recentUsersProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(adminServiceProvider).getRecentUsers();
});

// ── V5 §163 · the owner-approved metric surfaces (migrations 171-173) ───────
// Each provider yields a NULLABLE model. Null means "this area's surface
// returned no row" — the caller holds no capability for it — and the UI renders
// the approved A11 empty state. None of these providers substitutes an empty
// model, because zeros would assert measurements nobody is authorized to see.

final adminMetricsServiceProvider =
    Provider<AdminMetricsService>((ref) => AdminMetricsService());

final adminActivityOverviewProvider =
    FutureProvider<AdminActivityOverview?>((ref) async =>
        ref.watch(adminMetricsServiceProvider).getActivityOverview());

final adminUserOverviewProvider = FutureProvider<AdminUserOverview?>(
    (ref) async => ref.watch(adminMetricsServiceProvider).getUserOverview());

final adminEventsOverviewProvider = FutureProvider<AdminEventsOverview?>(
    (ref) async => ref.watch(adminMetricsServiceProvider).getEventsOverview());

final adminCommunityOverviewProvider =
    FutureProvider<AdminCommunityOverview?>((ref) async =>
        ref.watch(adminMetricsServiceProvider).getCommunityOverview());

final adminRevenueOverviewProvider = FutureProvider<AdminRevenueOverview?>(
    (ref) async => ref.watch(adminMetricsServiceProvider).getRevenueOverview());

final adminReleaseStatusProvider = FutureProvider<AdminReleaseStatus?>(
    (ref) async => ref.watch(adminMetricsServiceProvider).getReleaseStatus());

/// `DESIGN-01` §1 · the attention queue. Null means no `Incidents·view`; an empty
/// list means authorized with nothing raised, which the design renders with its own
/// literal copy rather than as a blank panel.
final adminIncidentsProvider = FutureProvider<List<AdminIncident>?>(
    (ref) async => ref.watch(adminMetricsServiceProvider).getIncidents());

// ── V5 §183 · Trust (P6) ────────────────────────────────────────────────────
// Null means "no capability for this area"; an empty list means authorized with
// nothing recorded. The service asks admin_can rather than inferring a permission
// from an empty read.

final adminTrustServiceProvider =
    Provider<AdminTrustService>((ref) => AdminTrustService());

final adminAuditEventsProvider = FutureProvider<List<AdminAuditEvent>?>(
    (ref) async => ref.watch(adminTrustServiceProvider).getAuditEvents());

final adminSecurityEventsProvider = FutureProvider<List<AdminAuditEvent>?>(
    (ref) async => ref.watch(adminTrustServiceProvider).getSecurityEvents());

final adminGuardianStateProvider = FutureProvider<AdminGuardianState?>(
    (ref) async => ref.watch(adminTrustServiceProvider).getGuardianState());

/// Separate from [adminGuardianStateProvider] on purpose: that provider returns null
/// for BOTH "no capability" and "nothing recorded", and the Trust page must say which.
final adminCanViewGuardianProvider = FutureProvider<bool>(
    (ref) async => ref.watch(adminTrustServiceProvider).canViewGuardian());

final adminGovernancePoliciesProvider =
    FutureProvider<List<AdminGovernancePolicy>?>((ref) async =>
        ref.watch(adminTrustServiceProvider).getGovernancePolicies());

final adminTrainingOverviewProvider = FutureProvider<AdminTrainingOverview?>(
    (ref) async => ref.watch(adminMetricsServiceProvider).getTrainingOverview());

/// Connection counts only — the ingestion-health half waits on WI-13 under PD-G01.
final adminWearableConnectionsProvider =
    FutureProvider<AdminWearableConnections?>((ref) async =>
        ref.watch(adminMetricsServiceProvider).getWearableConnections());

/// The People search box's current text. Empty means no filter — NOT "match nothing".
final adminUserSearchProvider = StateProvider<String>((_) => '');

final adminUserDirectoryProvider =
    FutureProvider<List<AdminUserDirectoryEntry>?>((ref) async =>
        ref.watch(adminMetricsServiceProvider).getUserDirectory(
            query: ref.watch(adminUserSearchProvider)));

final adminRoleCapabilitiesProvider = FutureProvider<List<AdminRoleCapability>?>(
    (ref) async => ref.watch(adminMetricsServiceProvider).getRoleCapabilities());

final adminAdministratorCountProvider = FutureProvider<int?>(
    (ref) async => ref.watch(adminMetricsServiceProvider).getAdministratorCount());

final adminPlatformSettingsProvider = FutureProvider<List<AdminPlatformSetting>?>(
    (ref) async => ref.watch(adminMetricsServiceProvider).getPlatformSettings());

/// Whether the caller may resolve an incident. Separate from the incident LIST so the
/// Trust page can render the approved read-only state for a role that may view but not
/// update — `Incidents·update` is held by `trust_lead` alone.
final adminCanUpdateIncidentsProvider = FutureProvider<bool>(
    (ref) async => ref.watch(adminTrustServiceProvider).canUpdateIncidents());

/// The OPEN moderation queue. Null means no `Community·view`; empty means authorized with
/// nothing to moderate, which the design renders with its own "none open" wording.
final adminOpenReportsProvider = FutureProvider<List<AdminContentReport>?>(
    (ref) async => ref.watch(adminMetricsServiceProvider).getOpenReports());

/// Whether the caller may moderate — `Community·update`, held by `content_editor`. Kept
/// separate from the queue so the page can render the approved read-only state.
final adminCanModerateProvider = FutureProvider<bool>(
    (ref) async => ref.watch(adminMetricsServiceProvider).canModerate());

/// Whether the caller may create an event — `Events·create`, held by `content_editor`.
final adminCanCreateEventsProvider = FutureProvider<bool>(
    (ref) async => ref.watch(adminMetricsServiceProvider).canCreateEvents());

/// Whether the caller may edit an event — `Events·update`.
///
/// SEPARATE FROM [adminCanCreateEventsProvider] ON PURPOSE. The approved matrix grades
/// `create` and `update` independently, so a role may be able to describe a new event and
/// not re-describe an existing one, or the reverse. Reusing one flag for both would make
/// the UI assert a capability nobody granted.
final adminCanUpdateEventsProvider = FutureProvider<bool>(
    (ref) async => ref.watch(adminMetricsServiceProvider).canUpdateEvents());

/// The Events directory the approved Ecosystem screen lists.
///
/// Null means no `Events·view`; empty means authorized with no events in range,
/// which the approved screen words as "No events in this range." The distinction is the
/// three-state rule: an unauthorized read must not render as "no events".
/// The Events search box's current text. Empty means no filter.
final adminEventSearchProvider = StateProvider<String>((_) => '');

final adminEventDirectoryProvider = FutureProvider<List<AdminEventRow>?>(
    (ref) async => ref.watch(adminMetricsServiceProvider).eventDirectory(
        query: ref.watch(adminEventSearchProvider)));

/// Whether the caller may rename a user — `Users·update`.
final adminCanUpdateUsersProvider = FutureProvider<bool>(
    (ref) async => ref.watch(adminMetricsServiceProvider).canUpdateUsers());

/// Whether the caller may re-state the Guardian — `AI Guardian·manage`, held by
/// `trust_lead` alone.
///
/// SEPARATE FROM [adminCanViewGuardianProvider] ON PURPOSE: the section is readable by
/// several roles and writable by one, and collapsing the two would put a safety switch in
/// front of every reader of the card.
final adminCanManageGuardianProvider = FutureProvider<bool>(
    (ref) async => ref.watch(adminTrustServiceProvider).canManageGuardian());

/// The environment this build targets, for the Admin environment strip.
///
/// A PROVIDER RATHER THAN A DIRECT `AppEnv.current` READ, because `AppEnv.current` is a
/// `static final` resolved once at first touch — so a test could not exercise the prod,
/// staging and development arms of the strip, and the arm that matters most (prod shows
/// NOTHING) would be the one never asserted.
final adminEnvironmentProvider =
    Provider<AppEnvironment>((_) => AppEnv.current.environment);
