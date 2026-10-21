// ERR-1 / EC-01 + EC-23 — Workstream B Phase B0, the observability sink.
//
// EC-01, verbatim: "One `reportFailure(AppFailure)` sink that every sanctioned
// swallow calls, and that every propagated failure passes through on its way to
// the UI." Its contract is §4 rule **O** — *no swallow is sanctioned unless it
// records*. A swallow that records is an engineering decision; a swallow that
// does not is an outage nobody will ever see.
//
// ── WHAT THIS IS DELIBERATELY NOT ───────────────────────────────────────────
// Not a vendor integration. `PD-A24` (observability vendor, cost and
// data-residency posture) is OPEN, and it is owned by product + privacy because
// health and fitness data implies a privacy review of anything that leaves the
// device. That decision explicitly does not gate this file: *"the sink
// abstraction (`reportFailure`) can and should be built before the vendor is
// chosen — it is one interface."* So this is one interface and nothing more.
// Choosing Sentry, Crashlytics or a self-hosted collector later means
// implementing `FailureSink` once and installing it at start-up; no call site
// changes.
//
// ── ADDITIVE BY CONSTRUCTION ────────────────────────────────────────────────
// Phase B0 is *"additive; zero behaviour change"* — "No propagation changes
// yet." Nothing here throws, nothing here returns a value a caller could branch
// on, and the default sink writes only in debug builds. A site that swallowed
// before still swallows; it is now merely visible.
//
// ── SCOPE ───────────────────────────────────────────────────────────────────
// This file closes the *capability* half of EC-01 and, with the call-site edits
// that accompany it, EC-23 (the seven `print()` calls that were the only
// diagnostics in the tree). Classifying and wiring the remaining ~234 swallow
// sites is **Phase B4** — "each site is resolved as *propagate* or
// *sanctioned-with-a-recorded-reason*" — and is deliberately NOT done here.

import 'package:flutter/foundation.dart';

/// One failure, as the sink sees it.
///
/// `origin` is the call site in `Class.method` form. It is a stable identifier
/// a human can grep for, not a message: the message lives in `error`.
@immutable
class AppFailure {
  const AppFailure({
    required this.origin,
    required this.error,
    this.stackTrace,
    this.context,
  });

  /// `'CheckinService.saveDailyCheckin'` — where the failure was caught.
  final String origin;

  /// The caught object, unmodified. Never re-wrapped, never stringified early:
  /// a sink that wants the type still has it.
  final Object error;

  /// Present when the catch site captured one. Optional by design — adding
  /// `catch (e, s)` to a site that had `catch (e)` is a call-site change, and
  /// B0 makes none it does not have to.
  final StackTrace? stackTrace;

  /// Anything the call site knows that the error does not. Must never carry
  /// personal or health data: this value is destined for an operator's console
  /// and, once PD-A24 is answered, possibly for a third party.
  final Map<String, Object?>? context;

  @override
  String toString() {
    final buffer = StringBuffer('AppFailure($origin): $error');
    final extra = context;
    if (extra != null && extra.isNotEmpty) {
      buffer.write(' context=$extra');
    }
    return buffer.toString();
  }
}

/// The one seam a vendor implementation installs itself into.
typedef FailureSink = void Function(AppFailure failure);

/// Debug builds print; release builds do nothing at all until PD-A24 is
/// answered and a real sink is installed. It does not fabricate a destination.
void _defaultSink(AppFailure failure) {
  if (kDebugMode) {
    debugPrint(failure.toString());
  }
}

FailureSink _sink = _defaultSink;

/// Record a failure. Never throws, never blocks, never changes control flow.
///
/// A sink that throws would convert an observability call into the very outage
/// it exists to report, so its own failure is contained here — the one place in
/// this codebase where an unconditional swallow is the correct answer.
void reportFailure(AppFailure failure) {
  try {
    _sink(failure);
  } catch (_) {
    // Intentionally empty: see above. Reporting must never be able to break
    // the path that reported.
  }
}

/// Convenience for the common call-site shape.
void reportError(
  String origin,
  Object error, [
  StackTrace? stackTrace,
  Map<String, Object?>? context,
]) {
  reportFailure(AppFailure(
    origin: origin,
    error: error,
    stackTrace: stackTrace,
    context: context,
  ));
}

/// Install a sink. Test-only until PD-A24 names a vendor, at which point the
/// annotation comes off and start-up installs the real one.
@visibleForTesting
void setFailureSink(FailureSink sink) {
  _sink = sink;
}

/// Restore the default. Every test that installs a sink must call this.
@visibleForTesting
void resetFailureSink() {
  _sink = _defaultSink;
}
