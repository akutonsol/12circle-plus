import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/cancel_booking.dart';

/// FIT-088 · confirm → cancelled, with the failure state.
///
/// Its own widget rather than a branch inside `ClassDetailScreen`, which is a
/// `ConsumerWidget` with no state to hold a stage in — and because a flow with
/// three visible states is worth pumping on its own. `ClassDetailScreen`
/// reaches Supabase on build, so a test of the whole screen would be measuring
/// the harness.
class CancelBookingControl extends StatefulWidget {
  /// Performs the cancellation. Throwing is how it reports failure, which is
  /// what `LiveClassService.cancelBooking` already does.
  final Future<void> Function() onCancel;

  /// Called once the place has actually been given up.
  final VoidCallback onCancelled;

  const CancelBookingControl({
    super.key,
    required this.onCancel,
    required this.onCancelled,
  });

  @override
  State<CancelBookingControl> createState() => _CancelBookingControlState();
}

class _CancelBookingControlState extends State<CancelBookingControl> {
  CancelStage _stage = CancelStage.idle;

  Future<void> _cancel() async {
    setState(() => _stage = CancelStage.cancelling);
    try {
      await widget.onCancel();
      if (!mounted) return;
      // Leave the in-flight state BEFORE handing back. The caller normally
      // pops, so this is not seen — but a caller that does not navigate would
      // otherwise be left with a spinner that never stops, which is how the
      // first version of this widget hung `pumpAndSettle` forever.
      setState(() => _stage = CancelStage.idle);
      widget.onCancelled();
    } catch (_) {
      // FIT-088's `failure`. The old code left the `await` unguarded, so a
      // throw meant the screen simply did not change — still showing the user
      // as booked, with no way to tell whether they still had a place.
      if (mounted) setState(() => _stage = CancelStage.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_stage == CancelStage.failed) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.surfaceDarkElevated),
        ),
        child: Column(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: AppColors.textTertiary, size: 32),
            const SizedBox(height: 10),
            const Text(cancelFailedTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text(cancelFailedBody,
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: AppColors.textTertiary, fontSize: 13)),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: _cancel,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                side: const BorderSide(color: AppColors.error),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text(cancelTryAgainLabel,
                  style: TextStyle(color: AppColors.error)),
            ),
          ],
        ),
      );
    }

    if (isConfirming(_stage) || cancelBusy(_stage)) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.surfaceDarkElevated),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(cancelConfirmTitle,
                style: TextStyle(
                    color: AppColors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text(cancelConfirmBody,
                style:
                    TextStyle(color: AppColors.textTertiary, fontSize: 13)),
            const SizedBox(height: 14),
            // `Keep it` first and drawn as the plain action: it is the
            // harmless one, and it is the one a mis-tap should land on.
            ElevatedButton(
              onPressed: cancelBusy(_stage)
                  ? null
                  : () => setState(() => _stage = CancelStage.idle),
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48)),
              child: const Text(keepBookingLabel),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: cancelBusy(_stage) ? null : _cancel,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                side: const BorderSide(color: AppColors.error),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: cancelBusy(_stage)
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.error))
                  // The sheet repeats the destructive action by name rather
                  // than saying "Confirm", so what is about to happen is
                  // legible at the moment of the tap.
                  : const Text(cancelBookingLabel,
                      style: TextStyle(color: AppColors.error)),
            ),
          ],
        ),
      );
    }

    return OutlinedButton(
      onPressed: () => setState(() => _stage = CancelStage.confirming),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 52),
        side: const BorderSide(color: AppColors.error),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: const Text(cancelBookingLabel,
          style: TextStyle(color: AppColors.error)),
    );
  }
}
