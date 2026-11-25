import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/observability/app_failure.dart';
import '../data/payment_service.dart'
    show CheckoutRefused, ownerGone, signedInUid;
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
  if (signedInUid() != owner) return false;
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(problem), backgroundColor: const Color(0xFFFFB4AB)));
  }
  return false;
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

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(paymentAccountProvider, (_, uid) {
      if (uid == _owner) return;
      final route = ModalRoute.of(context);
      if (route != null && route.isCurrent) Navigator.of(context).pop();
    });
    return ref.watch(paymentAccountProvider) == _owner && signedInUid() == _owner
        ? widget.child
        : const SizedBox.shrink();
  }
}
