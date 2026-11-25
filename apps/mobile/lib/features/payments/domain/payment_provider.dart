import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/observability/app_failure.dart';
import '../../auth/domain/auth_provider.dart';
import '../data/payment_service.dart';
import '../data/coach_revenue_service.dart';

/// The signed-in account, by id only: a token refresh or a metadata edit is the
/// same account and must not re-read (or drop) anything (P0-FL-60a). Null when
/// signed out — and, like [signedInUid], when Supabase was never initialised.
final paymentAccountProvider = Provider<String?>((ref) {
  try {
    return ref.watch(currentUserProvider.select((u) => u?.id));
  } on AssertionError {
    return null;
  }
});

/// What a read shows to the account signed in now (P0-FL-60a, A-19/A-21).
class OwnedRead<T> {
  const OwnedRead({
    this.hasValue = false,
    this.value,
    this.error,
    this.isLoading = false,
  });
  final bool hasValue;
  final T? value;
  final Object? error;
  final bool isLoading;
}

/// A source read with every other account's value and failure taken out.
///
/// When the account changes, Riverpod re-reads but HOLDS the previous value —
/// through the loading state, and through a failure after it. That is right
/// for a refresh by the same account and wrong for the next one, and the
/// AsyncValue cannot tell them apart. So a value is tagged with the account it
/// arrived for, and a held one counts only for that account.
class OwnedReadNotifier<T> extends Notifier<OwnedRead<T>> {
  OwnedReadNotifier(this._source, {this.origin});

  final ProviderListenable<AsyncValue<T>> _source;

  /// When set, each settled failure is recorded once under this name (leave it
  /// null where the service or the screen already records).
  final String? origin;

  ({String? owner, T value})? _value;
  ({String? owner, Object error})? _failure;
  bool _recorded = false;

  @override
  OwnedRead<T> build() {
    final account = ref.watch(paymentAccountProvider);
    final now = ref.watch(_source);
    if (now is AsyncData<T>) {
      // Never held from another account: an account change re-reads, and that
      // is AsyncLoading (or AsyncError after it) until this account's answer.
      _value = (owner: account, value: now.value);
      _failure = null;
      _recorded = false;
      return OwnedRead(
          hasValue: true, value: now.value, isLoading: now.isLoading);
    }
    if (now is AsyncError<T>) {
      final error = now.error;
      if (now.isLoading) {
        _recorded = false;
      } else if (!_recorded || !identical(_failure?.error, error)) {
        _recorded = true;
        if (origin != null) reportError(origin!, error, now.stackTrace);
      }
      _failure = (owner: account, error: error);
    }
    // `identical` too: the tag may be from before the source moved on while
    // nothing on screen was watching this.
    final value = _value;
    final mine = value != null &&
        value.owner == account &&
        now.hasValue &&
        identical(now.value, value.value);
    final failure = _failure;
    return OwnedRead(
      hasValue: mine,
      value: mine ? value.value : null,
      error: failure != null &&
              failure.owner == account &&
              identical(failure.error, now.error)
          ? failure.error
          : null,
      isLoading: now.isLoading,
    );
  }
}

/// [OwnedReadNotifier] as a provider. Screens watch this and still invalidate
/// [source] to refresh.
NotifierProvider<OwnedReadNotifier<T>, OwnedRead<T>> ownedReadProvider<T>(
        ProviderListenable<AsyncValue<T>> source,
        {String? origin}) =>
    NotifierProvider<OwnedReadNotifier<T>, OwnedRead<T>>(
        () => OwnedReadNotifier<T>(source, origin: origin));

final ownedConnectStatusProvider = ownedReadProvider(coachConnectStatusProvider,
    origin: 'CoachPaymentsScreen.connectStatus');
final ownedRevenueProvider = ownedReadProvider(coachRevenueProvider,
    origin: 'CoachPaymentsScreen.revenue');
final ownedBalanceProvider = ownedReadProvider(coachBalanceProvider,
    origin: 'CoachPaymentsScreen.balance');
// The service records these two.
final ownedCoachPlanTierProvider = ownedReadProvider(coachPlanTierProvider);
final ownedMembershipTierProvider = ownedReadProvider(membershipTierProvider);

final paymentServiceProvider = Provider<PaymentService>((ref) => PaymentService());

final mySubscriptionsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  ref.watch(currentUserProvider.select((u) => u?.id));
  return ref.watch(paymentServiceProvider).getMySubscriptions();
});

/// Coach: Stripe Connect status (connected / charges_enabled / payouts_enabled).
final coachConnectStatusProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  ref.watch(currentUserProvider.select((u) => u?.id));
  return ref.watch(paymentServiceProvider).connectStripeStatus();
});

/// Coach revenue metrics (monthly/lifetime/mrr/subscribers/marketplace/direct $).
final coachRevenueServiceProvider = Provider((ref) => CoachRevenueService());
final coachRevenueProvider = FutureProvider<Map<String, double>>((ref) async {
  ref.watch(currentUserProvider.select((u) => u?.id));
  return ref.watch(coachRevenueServiceProvider).getMetrics();
});

/// Coach: connected-account balance {pending, available} (cents).
final coachBalanceProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  ref.watch(currentUserProvider.select((u) => u?.id));
  return ref.watch(paymentServiceProvider).connectBalance();
});

/// Server-evaluated membership tier ('ai_guided' | 'self_guided' | null).
/// Gate platform features on this — for whoever is signed in now, which is
/// why it watches the user: the server answers for `auth.uid()`.
final membershipTierProvider = FutureProvider<String?>((ref) async {
  ref.watch(currentUserProvider.select((u) => u?.id));
  return ref.watch(paymentServiceProvider).activeMembership();
});

/// Convenience: any active platform membership at all. Null while that is not
/// known — unread, or the read failed (P0-FL-60a: it answered false).
final hasMembershipProvider = Provider<bool?>((ref) {
  final tier = ref.watch(ownedMembershipTierProvider);
  return tier.hasValue ? tier.value != null : null;
});

/// The coach's active platform plan tier ('starter'|'growth'|'elite' | null).
final coachPlanTierProvider = FutureProvider<String?>((ref) async {
  ref.watch(currentUserProvider.select((u) => u?.id));
  return ref.watch(paymentServiceProvider).coachPlanTier();
});

/// Active subscription to a given coach (null if not subscribed).
final coachSubscriptionProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, coachId) async {
  ref.watch(currentUserProvider.select((u) => u?.id));
  return ref.watch(paymentServiceProvider).activeCoachSubscription(coachId);
});
