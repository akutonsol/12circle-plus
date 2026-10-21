import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/admin_trust.dart';

/// V5 §183 — reads for the Trust area, over surfaces 156/159/163/169 already publish.
///
/// EVERY METHOD ASKS `admin_can` BEFORE READING, for the reason §168.1 established: these
/// views gate inside their own `WHERE`, so an uncapable caller and an empty population
/// both come back as `[]`. Those are different facts — one is an authorization outcome,
/// the other is the design's zero state — and a list read cannot tell them apart.
/// `admin_can(text, text)` is `SECURITY DEFINER` with `EXECUTE` granted to `authenticated`
/// (`153:127`) and D13 proves it for every area/verb pair, so the capability is ASKED FOR
/// rather than inferred from emptiness.
///
///   * `null`           → the caller lacks the capability
///   * `[]` / an empty model → authorized, nothing recorded
class AdminTrustService {
  AdminTrustService({SupabaseClient? client}) : _injected = client;

  final SupabaseClient? _injected;

  /// Resolved LAZILY. The constructor used to read `Supabase.instance.client` eagerly,
  /// which made the class impossible to subclass in a test — `Supabase.instance` throws
  /// before initialization, so a fake that overrides one method still blew up in
  /// `super()`. A service that cannot be substituted cannot have its failure path tested,
  /// and the failure path is the one that matters here.
  SupabaseClient get _db => _injected ?? Supabase.instance.client;

  Future<bool> _can(String area, String verb) async {
    final r = await _db.rpc('admin_can', params: {'p_area': area, 'p_verb': verb});
    return r == true;
  }

  /// The curated audit projection. `A13·1` excludes the caller's own `admin_action`
  /// rows, so this list is deliberately incomplete FOR ITS READER — see
  /// [AdminAuditEvent.a13Note], which the surface must show rather than implying a
  /// complete ledger.
  Future<List<AdminAuditEvent>?> getAuditEvents({int limit = 50}) async {
    if (!await _can('Audit logs', 'view')) return null;
    final rows = await _db
        .from('admin_audit_events')
        .select()
        .order('occurred_at', ascending: false)
        .limit(limit);
    return [
      for (final r in rows) AdminAuditEvent.fromRow(Map<String, dynamic>.from(r)),
    ];
  }

  /// Authentication, authorization denials, admin actions and audit reads — the four
  /// categories 159 projects under the Security area per ruling `B-1`.
  Future<List<AdminAuditEvent>?> getSecurityEvents({int limit = 50}) async {
    if (!await _can('Security', 'view')) return null;
    final rows = await _db
        .from('admin_security_events')
        .select()
        .order('occurred_at', ascending: false)
        .limit(limit);
    return [
      for (final r in rows) AdminAuditEvent.fromRow(Map<String, dynamic>.from(r)),
    ];
  }

  /// The singleton Guardian state. Returns null for "no capability" AND for "nothing
  /// recorded" — and the caller must not conflate either with `Active`. 169 creates the
  /// row EMPTY on purpose, so "not recorded" is the normal early condition.
  Future<AdminGuardianState?> getGuardianState() async {
    if (!await _can('AI Guardian', 'view')) return null;
    final row = await _db.from('guardian_state').select().maybeSingle();
    if (row == null) return null;
    return AdminGuardianState.fromRow(Map<String, dynamic>.from(row));
  }

  Future<List<AdminGovernancePolicy>?> getGovernancePolicies({int limit = 100}) async {
    if (!await _can('AI Guardian', 'view')) return null;
    final rows = await _db
        .from('governance_policy')
        .select()
        .order('code', ascending: true)
        .limit(limit);
    return [
      for (final r in rows)
        AdminGovernancePolicy.fromRow(Map<String, dynamic>.from(r)),
    ];
  }

  /// Whether this caller may RESOLVE an incident. `Incidents·update` is held by
  /// `trust_lead` alone in the approved matrix, so most operators see the read-only state.
  Future<bool> canUpdateIncidents() => _can('Incidents', 'update');

  /// Records a resolution against an incident through the governed write path
  /// (`admin_update_incident_response`, migration 164), which is `SECURITY DEFINER` and
  /// re-checks `admin_can('Incidents','update')` ITSELF — so the client gate below is
  /// convenience, never the boundary. It raises `42501` if the caller lacks the
  /// capability, and that error is allowed to surface rather than being swallowed into a
  /// `false`: a write that did not happen must not read as one that did.
  Future<void> resolveIncident(String incidentId, String resolution) =>
      _db.rpc('admin_update_incident_response', params: {
        'p_incident_id': incidentId,
        'p_resolution': resolution,
      });

  /// Whether this caller may read the Guardian state at all, so the UI can distinguish
  /// "you may not see this" from "nothing is recorded" — the two cases
  /// [getGuardianState] collapses into null.
  /// Whether the caller may re-state the Guardian — `AI Guardian·manage`, which the
  /// approved matrix grants to **`trust_lead` alone**.
  ///
  /// DELIBERATELY NOT `AI Guardian·view`. The section is readable by several roles and
  /// writable by one, so reusing the view flag would put a safety switch in front of
  /// everyone who can read the card.
  Future<bool> canManageGuardian() => _can('AI Guardian', 'manage');

  /// Disables the Guardian through the governed path (`admin_set_guardian_state`, 169) —
  /// the emergency control `A10` names as a product requirement, placed on this screen by
  /// owner decision **Q9**.
  ///
  /// ONLY `'Disabled'`, AND THAT IS THE DECISION'S SCOPE RATHER THAN THIS METHOD'S
  /// LAZINESS. 169 accepts all four `A5` states, and Q9 authorizes *"the Guardian
  /// emergency-disable control"* — not a state picker. `Active`, `Monitoring` and
  /// `Degraded` therefore have no caller here; there is no approved affordance that places
  /// them, and inventing one would be reading product scope into a placement decision.
  ///
  /// THE REASON IS REQUIRED BY THE FUNCTION, not by this form. 169 raises `22023` on
  /// `p_state = 'Disabled'` with no reason — *"disabling the Guardian requires a reason"* —
  /// so the dialog asks for one because the governed path refuses without it. The error is
  /// allowed to surface.
  Future<void> disableGuardian(String reason) =>
      _db.rpc('admin_set_guardian_state',
          params: {'p_state': 'Disabled', 'p_reason': reason});
  Future<bool> canViewGuardian() => _can('AI Guardian', 'view');
}
