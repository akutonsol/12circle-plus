import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/payment_service.dart' show CheckoutRefused;
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
/// otherwise [checkoutFailedMessage]. Callers do not add their own.
Future<bool> launchCheckout(
  BuildContext context,
  WidgetRef ref, {
  required String kind,
  String? coachId,
  String? eventId,
  String? tier,
}) async {
  String problem;
  try {
    final ok = await ref.read(paymentServiceProvider).startCheckout(
      kind: kind, coachId: coachId, eventId: eventId, tier: tier,
    );
    if (ok) return true;
    problem = checkoutFailedMessage;
  } on CheckoutRefused catch (e) {
    problem = e.message;
  } catch (_) {
    problem = checkoutFailedMessage;
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(problem), backgroundColor: const Color(0xFFFFB4AB)));
  }
  return false;
}
