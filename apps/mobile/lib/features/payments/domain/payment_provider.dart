import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/domain/auth_provider.dart';
import '../data/payment_service.dart';
import '../data/coach_revenue_service.dart';

final paymentServiceProvider = Provider<PaymentService>((ref) => PaymentService());

final mySubscriptionsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(paymentServiceProvider).getMySubscriptions();
});

/// Coach: Stripe Connect status (connected / charges_enabled / payouts_enabled).
final coachConnectStatusProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  return ref.watch(paymentServiceProvider).connectStripeStatus();
});

/// Coach revenue metrics (monthly/lifetime/mrr/subscribers/marketplace/direct $).
final coachRevenueServiceProvider = Provider((ref) => CoachRevenueService());
final coachRevenueProvider = FutureProvider<Map<String, double>>((ref) async {
  ref.watch(currentUserProvider);
  return ref.watch(coachRevenueServiceProvider).getMetrics();
});

/// Coach: connected-account balance {pending, available} (cents).
final coachBalanceProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return ref.watch(paymentServiceProvider).connectBalance();
});

/// Server-evaluated membership tier ('ai_guided' | 'self_guided' | null).
/// Gate platform features on this.
final membershipTierProvider = FutureProvider<String?>((ref) async {
  return ref.watch(paymentServiceProvider).activeMembership();
});

/// Convenience: any active platform membership at all.
final hasMembershipProvider = Provider<bool>((ref) {
  return ref.watch(membershipTierProvider).valueOrNull != null;
});

/// The coach's active platform plan tier ('starter'|'growth'|'elite' | null).
final coachPlanTierProvider = FutureProvider<String?>((ref) async {
  return ref.watch(paymentServiceProvider).coachPlanTier();
});

/// Active subscription to a given coach (null if not subscribed).
final coachSubscriptionProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, coachId) async {
  return ref.watch(paymentServiceProvider).activeCoachSubscription(coachId);
});
