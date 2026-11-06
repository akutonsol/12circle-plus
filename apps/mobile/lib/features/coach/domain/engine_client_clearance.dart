// Whether a client is cleared for engine-generated training — the app's side of
// `engine_client_clearance` (migration 189).
//
// THE RULE LIVES IN THE DATABASE, ONCE. `_engine_client_clearance` decides; the
// same function guards every assignment of an engine-selected programme, so the
// app cannot disagree with what the database will enforce. This file only reads
// the verdict and words it for a coach.
//
// What "cleared" means is the owner's restriction for the initial walkthrough
// (2026-10-25): completed intake, explicit no-injury status, a complete low-risk
// PAR-Q, and no medical advice against exercise. It is a SCOPE RESTRICTION, not a
// clinical assessment — no clinical owner or clinical sign-off exists, and the
// engine's injury handling is not safe for injured clients (registry F-J-23 /
// waves 5.7).
//
// Fail-closed: an error, a missing RPC (a database without 189) or an unexpected
// shape is "not cleared", never cleared.

/// The verdict: `cleared` and the database's reason codes.
typedef EngineClearance = ({bool cleared, List<String> reasons});

const EngineClearance _unconfirmed = (cleared: false, reasons: ['UNCONFIRMED']);

/// Reads the `engine_client_clearance` result (`{cleared, reasons}`).
EngineClearance readClearance(Object? rpcResult) {
  if (rpcResult is! Map) return _unconfirmed;
  final cleared = rpcResult['cleared'];
  final reasons = rpcResult['reasons'];
  if (cleared is! bool || reasons is! List) return _unconfirmed;
  final codes = reasons.map((e) => e.toString()).toList();
  // A "cleared" verdict that still carries reasons is contradictory: not cleared.
  if (cleared && codes.isEmpty) return (cleared: true, reasons: const <String>[]);
  return (cleared: false, reasons: codes.isEmpty ? const ['UNCONFIRMED'] : codes);
}

String _reasonText(String code) => switch (code) {
      'INTAKE_INCOMPLETE' => "hasn't finished their intake",
      'INJURY_REPORTED' => 'has reported an injury',
      'PARQ_INCOMPLETE' => "hasn't answered every health-screening question",
      'PARQ_RISK_NOT_LOW' => "has a health-screening result that isn't low risk",
      'MEDICAL_ADVICE' => 'has indicated medical advice about exercise',
      'NO_PROFILE' => 'has no profile on file',
      _ => "couldn't be confirmed",
    };

/// Why Copilot will not plan for this client, or `null` when it may.
String? copilotClearanceRefusal(EngineClearance c) {
  if (c.cleared) return null;
  final why = c.reasons.map(_reasonText).toSet().join('; ');
  return 'Copilot is limited to clients cleared for generated training, and this client $why. '
      'Build this session by hand in Programs.';
}

/// What a coach is told when the database refuses to assign an engine-selected
/// programme (ENGINE_CLIENT_NOT_CLEARED).
const String kAssignNotClearedMessage =
    "This programme was generated, and generated programmes can only go to clients who've "
    'completed intake with no injury and a low-risk health screening. Nothing was assigned — '
    'build a programme by hand for this client.';

/// True when an error is the database's assignment-time refusal (189).
bool isNotClearedError(Object error) => error.toString().contains('ENGINE_CLIENT_NOT_CLEARED');
