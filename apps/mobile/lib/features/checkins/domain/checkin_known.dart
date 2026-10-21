/// CON-01 (read side) · a failed check-in read answered "no".
///
/// ── WHAT THE SERVICE DID ───────────────────────────────────────────────────
/// ```dart
/// Future<bool> hasCheckedInThisWeek() async {
///   try { … } catch (e) { return false; }   // "you have not checked in"
/// }
///
/// Future<int> getCheckinStreak() async {
///   try { … } catch (e) { return 0; }       // "your streak is 0"
/// }
/// ```
///
/// `false` and `0` are **answers**, and the service was giving them when it had
/// none. Every failure — a missing table, an RLS filter, a dropped connection —
/// came back as a confident negative.
///
/// ── WHY THAT IS WORSE THAN A WRONG NUMBER HERE ─────────────────────────────
/// `daily_checkin_screen` branches on it:
///
/// ```dart
/// child: _alreadyDone
///   ? _AlreadyDone(onGoHome: …)
///   : SingleChildScrollView( … the whole check-in form … )
/// ```
///
/// So a failed read shows the **empty form to someone who has already checked
/// in this week**, and `_submit` writes another one. The lie does not stop at
/// the display: it produces a duplicate weekly check-in.
///
/// ── THE STANDING RULE IN THIS REPOSITORY ───────────────────────────────────
/// F-15 recorded this exact class — *"on a failed read this said '0 active
/// challenges', a number the screen cannot support, the same class as
/// `/train`'s '0 workouts' and `/home`'s '0%'"* — and `checkin_hub.dart`
/// already carries the copy the repository uses for it, noting the pattern is
/// rendered in fifteen places.
library;

/// Three states, because the screen needs three.
enum CheckinKnown {
  /// The read succeeded and there is a check-in.
  done,

  /// The read succeeded and there is none. **Only this may open the form.**
  notDone,

  /// The read failed. Not a "no".
  unknown,
}

/// Whether the check-in form may be presented as a fresh one.
///
/// `unknown` must not: the form is how a duplicate gets written.
bool mayOfferCheckinForm(CheckinKnown k) => k == CheckinKnown.notDone;

/// Whether the "already done" confirmation may be shown.
bool mayShowAlreadyDone(CheckinKnown k) => k == CheckinKnown.done;

/// A streak the screen can actually support.
///
/// `null` is unknown. The screen already hides the figure when it is not
/// positive — `if (_streak > 0)` — so an unknown streak renders as the word
/// alone rather than as a zero, which is F-15's em-dash rule reached by the
/// layout that was already there.
int? knownStreak(int? streak) => (streak != null && streak > 0) ? streak : null;
