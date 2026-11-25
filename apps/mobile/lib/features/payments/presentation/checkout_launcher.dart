import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/observability/app_failure.dart';
import '../data/payment_service.dart'
    show CheckoutRefused, ownerGone, signedInUid, whenOwnerGone;
import '../domain/payment_provider.dart';

/// What a client is told when a checkout could not be started for a reason
/// they cannot act on except by trying again.
const checkoutFailedMessage = 'Could not start checkout. Try again.';

/// Single entry point for starting a checkout. Always uses the hosted Stripe
/// Checkout (top-level redirect) — Stripe Checkout cannot run inside an iframe
/// ("…redirect to Checkout at the top level"), so the in-app embedded flow is
/// not used. Returns true if a checkout was started.
///
/// It is also the ONE place a failed start is reported, with ONE message: the
/// server's refusal when the client already has what they are buying
/// (create-checkout's 409 `already_subscribed` -- "try again" would never work),
/// otherwise [checkoutFailedMessage]. Callers do not add their own. When the
/// account that asked is gone, nothing is said: it is not the new one's action
/// (P0-FL-60a).
Future<bool> launchCheckout(
  BuildContext context,
  WidgetRef ref, {
  required String kind,
  String? coachId,
  String? eventId,
  String? tier,
  required String? owner,
}) async {
  // [owner] is the account the card was built for (P0-FL-60a, B-3): another
  // one signed in means this tap is not theirs. Nothing is sent or said.
  if (ownerGone(owner, 'launchCheckout', 'checkout')) return false;
  String problem;
  try {
    final ok = await ref.read(paymentServiceProvider).startCheckout(
      kind: kind, coachId: coachId, eventId: eventId, tier: tier,
    );
    if (ok) return true;
    problem = checkoutFailedMessage;
  } on CheckoutRefused catch (e) {
    problem = e.message;
  } catch (e, st) {
    reportError('launchCheckout', e, st);
    problem = checkoutFailedMessage;
  }
  // The service recorded it.
  if (context.mounted) {
    showOwnedSnackBar(ScaffoldMessenger.of(context), owner,
        SnackBar(content: Text(problem), backgroundColor: const Color(0xFFFFB4AB)));
  }
  return false;
}

/// Says the outcome of [owner]'s action to [owner] only (P0-FL-60a): not shown
/// when another account is signed in, and gone — without its exit animation —
/// when that changes, even if the screen that showed it is not there any more.
void showOwnedSnackBar(
    ScaffoldMessengerState messenger, String? owner, SnackBar bar) {
  if (signedInUid() != owner || !messenger.mounted) return;
  final shown = messenger.showSnackBar(bar);
  final stop = whenOwnerGone(owner, () {
    if (!messenger.mounted) return;
    // Every bar up or waiting is from before the account changed.
    messenger
      ..clearSnackBars()
      ..removeCurrentSnackBar();
  });
  shown.closed.whenComplete(stop);
}

/// Runs [open], which pushes one route, and takes that route away when [owner]
/// is no longer signed in (P0-FL-60a) — before it is drawn, if no frame ran in
/// between. For a sheet another feature draws; a dialog of ours is an
/// [OwnedDialog].
void openOwnedRoute(BuildContext context, String? owner, VoidCallback open) {
  final navigator = Navigator.of(context);
  Route<dynamic>? top() {
    Route<dynamic>? r;
    navigator.popUntil((route) {
      r = route;
      return true; // looks, pops nothing
    });
    return r;
  }

  final before = top();
  open();
  final pushed = top();
  if (pushed == null || identical(pushed, before)) return;
  final stop = whenOwnerGone(owner, () {
    if (navigator.mounted && pushed.isActive) navigator.removeRoute(pushed);
  });
  pushed.popped.whenComplete(stop);
}

/// A dialog about one account's payment: it closes itself, unanswered, when
/// that account is no longer the one signed in, and never draws for another
/// (P0-FL-60a). The caller's check after the dialog still decides the action.
class OwnedDialog extends ConsumerStatefulWidget {
  const OwnedDialog({super.key, required this.owner, required this.child});
  /// The account the dialog was opened for.
  final String? owner;
  final Widget child;
  @override
  ConsumerState<OwnedDialog> createState() => _OwnedDialogState();
}

class _OwnedDialogState extends ConsumerState<OwnedDialog> {
  String? get _owner => widget.owner;
  late final void Function() _stop;

  @override
  void initState() {
    super.initState();
    // Also for an account that left before this was first drawn.
    _stop = whenOwnerGone(_owner, _close);
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _close() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    // Not on top: its barrier would stay behind whatever is.
    route.isCurrent
        ? Navigator.of(context).pop()
        : Navigator.of(context).removeRoute(route);
  }

  @override
  Widget build(BuildContext context) {
    return ref.watch(paymentAccountProvider) == _owner && signedInUid() == _owner
        ? widget.child
        : const SizedBox.shrink();
  }
}
