import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The client's coach, by name — or nothing.
///
/// ── WHY THIS IS ONE FUNCTION AND NOT THREE CALL SITES ──────────────────────
/// The design package addresses the coach by name in several places —
/// "Send to Nadia" (FIT-004), "Message Nadia" (FIT-015), and the body copy on
/// `/train`'s empty state. The name is real data, so using it invents nothing.
/// What must not happen is either of the two failure modes on each side of it,
/// and they are easy to reintroduce one screen at a time:
///
///   * naming a coach the client **does not have**; and
///   * naming one when the read **failed** — which is `/profile`'s
///     "No coach assigned yet" collapse turned inside out. There a failure
///     claimed the client had no coach; here it would claim they have one.
///     Both are a screen answering a question it cannot.
///
/// So the rule lives once: **the name is used only on a settled, non-empty
/// value.** Loading, failed, no coach, and a coach row with a blank first name
/// all return null, and the caller falls back to wording that is true without
/// one.
///
/// It matches on the STATE, never on `.valueOrNull` — an error's value and an
/// empty result's value are the same null at the call site, and `.valueOrNull`
/// is the read EC-G8 ratchets.
String? coachFirstName(AsyncValue<Map<String, dynamic>?> coach) {
  return switch (coach) {
    AsyncError() => null,
    AsyncData(:final value) => () {
        final name = (value?['first_name'] as String?)?.trim();
        return (name == null || name.isEmpty) ? null : name;
      }(),
    _ => null,
  };
}

/// `withName('Nadia')` when the coach is known, [fallback] otherwise.
///
/// The fallback is always a phrase that stays true with no coach — this
/// repository's existing "Message your coach" and "Submit Check-In", not a
/// sentence addressed to nobody.
String coachAddressed(
  AsyncValue<Map<String, dynamic>?> coach, {
  required String Function(String name) withName,
  required String fallback,
}) {
  final name = coachFirstName(coach);
  return name == null ? fallback : withName(name);
}
