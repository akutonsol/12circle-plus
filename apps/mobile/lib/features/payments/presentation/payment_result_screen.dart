import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../domain/entitlements.dart';
import '../domain/payment_provider.dart';
import '../../coach/domain/coach_provider.dart';

const _bg    = Color(0xFF030303);
const _brand = Color(0xFFA855F7);
const _mint  = Color(0xFF6FFBBE);
const _white = Colors.white;
const _muted = Color(0xFFCFC2D6);

/// This account's coach only (P0-FL-60a, A-21).
final _ownedCoachProvider = ownedReadProvider(assignedCoachProvider,
    origin: 'PaymentResultScreen.assignedCoach');

/// Landing page Stripe Checkout returns to. On success we refresh entitlements
/// (the webhook has usually written the row by now) and send the user home.
class PaymentResultScreen extends ConsumerStatefulWidget {
  final bool success;
  const PaymentResultScreen({super.key, required this.success});
  @override
  ConsumerState<PaymentResultScreen> createState() => _PaymentResultScreenState();
}

class _PaymentResultScreenState extends ConsumerState<PaymentResultScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.success) {
      // Give the webhook a beat, then refresh plan + subscriptions.
      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;
        ref.invalidate(clientPlanProvider);
        ref.invalidate(membershipTierProvider);
        ref.invalidate(coachPlanTierProvider);
        ref.invalidate(mySubscriptionsProvider);
        ref.invalidate(assignedCoachProvider);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ok = widget.success;
    final accent = ok ? _mint : _muted;
    // If this purchase connected them to a coach, send them to book sessions.
    final hasCoach = ref.watch(_ownedCoachProvider).value != null;
    return Scaffold(
      backgroundColor: _bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.3), blurRadius: 24)],
                ),
                child: Icon(
                    ok ? Icons.check_rounded : Icons.close_rounded,
                    color: accent, size: 44),
              ),
              const SizedBox(height: 24),
              Text(ok ? 'You’re all set!' : 'Checkout canceled',
                  style: const TextStyle(
                      color: _white, fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                ok
                    ? 'Your plan is active. It may take a moment to appear.'
                    : 'No charge was made. You can upgrade any time.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted, fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brand,
                    foregroundColor: _white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => context.go(ok
                      ? (hasCoach ? '/booking-handoff' : '/subscription')
                      : '/upgrade'),
                  child: Text(ok ? (hasCoach ? 'Book your sessions' : 'Continue') : 'Back to plans',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
              TextButton(
                onPressed: () => context.go('/directory'),
                child: const Text('Go to app', style: TextStyle(color: _muted)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
