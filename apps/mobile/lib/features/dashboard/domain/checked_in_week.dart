/// C7 (owner, 2026-11-09): a reviewed week remains in "Checked In" but leaves
/// "Needs Attention".
///
/// The coach dashboard read only `status = 'submitted'`, so the moment a coach
/// replied, that client's week dropped out of "Checked In" and off the
/// Check-ins tab as if they had never checked in. A reviewed week is still a
/// week the client checked in; it is only no longer the coach's to act on —
/// the same line `coach_triage_provider.dart` already draws with
/// `reviewed_at IS NULL`.
library;

/// The statuses that count as having checked in this week.
const kCheckedInStatuses = ['submitted', 'reviewed'];

/// Whether the coach has already replied to this check-in. A reviewed week is
/// never flagged as needing attention, however low the energy it reported.
bool reviewedByCoach(Map<String, dynamic> checkin) =>
    checkin['status'] == 'reviewed';
