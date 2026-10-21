/// V5 §183 — models for the Trust area (P6), over the surfaces migrations 156, 159,
/// 160, 163, 167 and 169 already publish.
///
/// The approved design states Trust's data requirements outright (`SCREEN-INVENTORY.md`
/// at `931218b`): *"AI Guardian actions and autonomy; auth and authorisation events;
/// incidents; immutable audit log with before/after."* Each already has a surface, so
/// nothing new is modelled here — these are the shapes those views project.
///
/// THREE PROPERTIES THIS FILE EXISTS TO MAKE UNBREAKABLE.
///
/// 1. **A pseudonym is never resolved.** `§19.3` rules that no standing party may resolve
///    a pseudonym and that resolution happens only inside the audit read path — and a
///    view is a standing resolver by definition, which is why `admin_audit_events`
///    projects `subject_pseudonym` and never joins `audit_identity_map`.
///    [AdminAuditEvent] therefore carries the pseudonym as an OPAQUE STRING and has no
///    field, getter or method that could resolve it. There is nothing here to misuse.
///
/// 2. **The audit projection is deliberately INCOMPLETE for its reader.** `A13·1` excludes
///    an admin's own `admin_action` rows (`NOT (category = 'admin_action' AND actor_id =
///    auth.uid())`). So absence is not evidence of absence, and [AdminAuditEvent.a13Note]
///    exists so a surface can say so rather than implying a complete ledger.
///
/// 3. **An unrecorded Guardian state is not `Active`.** `guardian_state` starts EMPTY
///    (169) and `A5` rules the states `Active · Monitoring · Degraded · Disabled`.
///    Rendering "Active" for a state nobody recorded would be EC-04's defect on a safety
///    control — the most reassuring reading of missing data. [AdminGuardianState] is
///    returned as null in that case and the UI must say so.
library;

/// One row of the curated audit projection (`admin_audit_events`, migration 156).
class AdminAuditEvent {
  const AdminAuditEvent({
    required this.id,
    required this.actorId,
    required this.subjectPseudonym,
    required this.action,
    required this.occurredAt,
    required this.outcome,
    required this.category,
    required this.actorProvenance,
    required this.correlationId,
  });

  final String? id;

  /// The acting admin. This is an actor, not a subject — `A12`'s concern is the SUBJECT,
  /// and `admin_incidents` withholds `actor_identity` for that reason.
  final String? actorId;

  /// OPAQUE. §19.3: no standing party resolves a pseudonym. There is deliberately no
  /// `subjectId`, no `resolve()` and no identity-map lookup anywhere in this layer.
  final String? subjectPseudonym;

  final String? action;
  final DateTime? occurredAt;
  final String? outcome;
  final String? category;
  final String? actorProvenance;
  final String? correlationId;

  /// What `A13·1` means for anyone reading this ledger, stated so a surface can show it.
  static const a13Note =
      'Your own admin actions are excluded from this log (A13·1).';

  static AdminAuditEvent fromRow(Map<String, dynamic> r) => AdminAuditEvent(
        id: r['id'] as String?,
        actorId: r['actor_id'] as String?,
        subjectPseudonym: r['subject_pseudonym'] as String?,
        action: r['action'] as String?,
        occurredAt: _date(r['occurred_at']),
        outcome: r['outcome'] as String?,
        category: r['category'] as String?,
        actorProvenance: r['actor_provenance'] as String?,
        correlationId: r['correlation_id'] as String?,
      );
}

/// `A5`'s Guardian states. Null means NOT RECORDED, which is not a state.
class AdminGuardianState {
  const AdminGuardianState({
    required this.state,
    required this.reason,
    required this.setAt,
  });

  /// One of `Active · Monitoring · Degraded · Disabled` (`A5`, enforced by 169's CHECK).
  final String? state;

  /// Required when disabling (169 gates it), so its absence on a `Disabled` row is
  /// itself a finding.
  final String? reason;
  final DateTime? setAt;

  bool get isDisabled => state == 'Disabled';

  /// True when the recorded state is one `A5` defines. An unrecognised value is NOT
  /// treated as healthy — see [AdminTrustSummary.guardianIsHealthy].
  bool get isKnownState =>
      const {'Active', 'Monitoring', 'Degraded', 'Disabled'}.contains(state);

  static AdminGuardianState fromRow(Map<String, dynamic> r) => AdminGuardianState(
        state: r['state'] as String?,
        reason: r['reason'] as String?,
        setAt: _date(r['set_at']),
      );
}

/// One row of the governance registry (`governance_policy`, migration 163/167).
class AdminGovernancePolicy {
  const AdminGovernancePolicy({
    required this.id,
    required this.code,
    required this.name,
    required this.category,
    required this.scope,
    required this.status,
  });

  final String? id;

  /// The design's coded form — `RB-01`, `DA-07`.
  final String? code;
  final String? name;
  final String? category;
  final String? scope;

  /// `draft · active · retired` (163's CHECK).
  final String? status;

  bool get isActive => status == 'active';

  static AdminGovernancePolicy fromRow(Map<String, dynamic> r) =>
      AdminGovernancePolicy(
        id: r['id'] as String?,
        code: r['code'] as String?,
        name: r['name'] as String?,
        category: r['category'] as String?,
        scope: r['scope'] as String?,
        status: r['status'] as String?,
      );
}

/// Convenience readings the Trust overview needs, kept out of the UI so they can be
/// asserted directly.
abstract final class AdminTrustSummary {
  /// Whether the Guardian may be presented as healthy.
  ///
  /// **A null state is NOT healthy, and neither is an unrecognised one.** `guardian_state`
  /// starts empty, so "no row" is the normal early condition — and answering `true` there
  /// would tell an operator a safety control is running when nobody has said it is. This
  /// returns null for "cannot say", never a boolean guess.
  static bool? guardianIsHealthy(AdminGuardianState? g) {
    if (g == null || g.state == null || !g.isKnownState) return null;
    return g.state == 'Active' || g.state == 'Monitoring';
  }
}

DateTime? _date(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  return DateTime.tryParse(v.toString());
}
