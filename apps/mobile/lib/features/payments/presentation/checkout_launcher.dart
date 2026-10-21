import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/payment_provider.dart';

/// Single entry point for starting a checkout. Always uses the hosted Stripe
/// Checkout (top-level redirect) — Stripe Checkout cannot run inside an iframe
/// ("…redirect to Checkout at the top level"), so the in-app embedded flow is
/// not used. Returns true if a checkout was started.
Future<bool> launchCheckout(
  BuildContext context,
  WidgetRef ref, {
  required String kind,
  String? coachId,
  String? eventId,
  String? tier,
}) async {
  try {
    return await ref.read(paymentServiceProvider).startCheckout(
      kind: kind, coachId: coachId, eventId: eventId, tier: tier,
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Checkout could not start. Please try again.'),
          backgroundColor: const Color(0xFFFFB4AB)));
    }
    return false;
  }
}
