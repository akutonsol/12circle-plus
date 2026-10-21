/// FIT-088 · "Cancellation — confirm → cancelled".
///
/// The board marks this anchor **`missing`**, and it is: `/class-detail` has a
/// `Cancel Booking` button that does the whole thing on one tap.
///
/// ```dart
/// OutlinedButton(
///   onPressed: () async {
///     await ref.read(liveClassServiceProvider).cancelBooking(fitnessClass.id);
///     ref.read(refreshClassesProvider.notifier).state++;
///     if (context.mounted) context.pop();
///   },
///   child: const Text('Cancel Booking'),
/// )
/// ```
///
/// ── TWO DEFECTS ────────────────────────────────────────────────────────────
/// **No confirmation, on an action that cannot be undone.** Cancelling frees
/// the seat and `_promoteFromWaitlist` hands it to whoever is next in line, so
/// a mis-tap does not just cost the place — it gives it away. FIT-088 puts a
/// step in front of exactly this, with two controls: **`Keep it`** and
/// **`Cancel place`**.
///
/// **The failure is invisible.** The `await` is unguarded. If the request
/// throws, `context.pop()` never runs and nothing is said: the user is left on
/// the same screen, still showing them as booked, with no idea whether they
/// still have a place. FIT-088 declares a `failure` state whose control is
/// **`Try again`**.
///
/// ── WHAT WAS CHECKED AND FOUND SOUND ───────────────────────────────────────
/// Two things that looked wrong are not, and are written down so the next
/// reader does not re-raise them:
///
///   * `cancelBooking` calls `_promoteFromWaitlist` unconditionally, including
///     when the update matched no rows. That does **not** overbook: the
///     promotion returns early unless `_confirmedCount < max_capacity`, so it
///     only ever fills a seat that is genuinely free;
///   * `class_bookings`' only policy is
///     `FOR ALL TO authenticated USING (user_id = auth.uid())` with no
///     `WITH CHECK`. Postgres uses the `USING` expression as the check when
///     `WITH CHECK` is omitted, so a user still cannot write a row onto
///     somebody else's `user_id`. **This is not the F-21 shape.**
library;

/// Where the cancellation got to.
enum CancelStage {
  /// Booked, nothing asked yet.
  idle,

  /// FIT-088's confirm step.
  confirming,

  /// In flight.
  cancelling,

  /// FIT-088's `failure` state.
  failed,
}

/// Whether the confirm step is what the user is looking at.
bool isConfirming(CancelStage s) => s == CancelStage.confirming;

/// Whether the cancel control should be inert — mid-request, so a second tap
/// cannot start a second cancellation.
bool cancelBusy(CancelStage s) => s == CancelStage.cancelling;

// ── Copy. FIT-088 names all of these. ──────────────────────────────────────

/// The control that opens the confirm step. It read "Cancel Booking".
const cancelBookingLabel = 'Cancel place';

/// The way out of the confirm step — and the one that should be easiest to
/// hit, because it is the harmless one.
const keepBookingLabel = 'Keep it';

/// FIT-088's `failure` control.
const cancelTryAgainLabel = 'Try again';

const cancelConfirmTitle = 'Give up your place?';

/// Says what actually happens, rather than asking "are you sure?". The seat
/// does not sit empty — it goes to the next person waiting.
const cancelConfirmBody =
    'Your place goes to the next person on the waitlist. You would need to '
    'book again to get it back.';

const cancelFailedTitle = 'That didn\'t go through';
const cancelFailedBody = 'You still have your place. Try again in a moment.';
