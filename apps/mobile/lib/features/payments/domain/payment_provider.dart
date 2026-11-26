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

/// Who each answer of one source was READ for (P0-FL-60a, A-19/A-21).
///
/// When the account changes, Riverpod re-reads but HOLDS the previous value —
/// through the loading state, through a failure after it and, for a provider
/// invalidated before the change was flushed, as an AsyncData that is loading.
/// None of those states says whose the value is. So the owner is taken when a
/// read STARTS and travels with the answer of that read; a held value keeps the
/// owner it has, whoever is signed in when it is looked at.
///
/// Only listens, never watches: it is not rebuilt, so it misses no transition,
/// and each listener runs synchronously with the flush that starts the read.
class _ReadOwners<T> {
  _ReadOwners(this._ref, this._origin);

  final Ref _ref;

  /// When set, each settled failure is recorded once under this name (leave it
  /// null where the service or the screen already records).
  final String? _origin;

  /// Who the read now in flight (or just landed) is for; null = not known.
  ({String? uid})? _started;
  bool _loading = false;

  ({String? owner, T value})? value;
  ({String? owner, Object error})? failure;

  /// The account the sources depend on — unless the auth client is already
  /// another one's: then the request itself is ambiguous, its answer counts for
  /// nobody, and the sources re-read as soon as that change reaches them.
  ({String? uid})? _account() {
    final account = _ref.read(paymentAccountProvider);
    final client = signedInUid();
    return client == null || client == account ? (uid: account) : null;
  }

  /// A read in flight across an account change is re-started by its source
  /// (which depends on the account) without a new loading state to see.
  void onAccount(String? _, String? __) {
    if (_loading) _started = _account();
  }

  void onSource(AsyncValue<T>? previous, AsyncValue<T> now) {
    // Loading → settled is the end of the read that was started; anything else
    // is a new one.
    if (now.isLoading || !_loading) _started = _account();
    _loading = now.isLoading;
    if (now.isLoading) return;
    final owner = _started;
    if (now is AsyncError<T>) {
      failure = owner == null ? null : (owner: owner.uid, error: now.error);
      final origin = _origin;
      if (origin != null) reportError(origin, now.error, now.stackTrace);
    } else {
      failure = null;
      value = owner == null ? null : (owner: owner.uid, value: now.requireValue);
    }
  }
}

/// [source] with every other account's value and failure taken out. Screens
/// watch this and still invalidate [source] to refresh.
Provider<OwnedRead<T>> ownedReadProvider<T>(
    ProviderListenable<AsyncValue<T>> source,
    {String? origin}) {
  final owners = Provider<_ReadOwners<T>>((ref) {
    final o = _ReadOwners<T>(ref, origin);
    ref.listen<String?>(paymentAccountProvider, o.onAccount);
    ref.listen<AsyncValue<T>>(source, o.onSource, fireImmediately: true);
    return o;
  });
  return Provider<OwnedRead<T>>((ref) {
    final o = ref.watch(owners);
    final account = ref.watch(paymentAccountProvider);
    final now = ref.watch(source);
    final value = o.value;
    final mine = value != null && value.owner == account;
    final failure = o.failure;
    return OwnedRead(
      hasValue: mine,
      value: mine ? value.value : null,
      error:
          failure != null && failure.owner == account ? failure.error : null,
      isLoading: now.isLoading,
    );
  });
}

final ownedConnectStatusProvider = ownedReadProvider(coachConnectStatusProvider,
    origin: 'CoachPaymentsScreen.connectStatus');
final ownedRevenueProvider = ownedReadProvider(coachRevenueProvider,
    origin: 'CoachPaymentsScreen.revenue');
final ownedBalanceProvider = ownedReadProvider(coachBalanceProvider,
    origin: 'CoachPaymentsScreen.balance');
// The service records these two.
final ownedCoachPlanTierProvider = ownedReadProvider(coachPlanTierProvider);
final ownedMySubscriptionsProvider = ownedReadProvider(mySubscriptionsProvider);
final ownedMembershipTierProvider = ownedReadProvider(membershipTierProvider);

// The reads below watch the account twice, on purpose. `select` alone is not a
// dependency Riverpod 2.6.1 counts as CHANGED when the provider is invalidated
// before the account change is flushed (no frame): the re-read is then taken
// for a refresh, and the provider becomes AsyncData(isLoading: true) with the
// PREVIOUS account's value. Watching [paymentAccountProvider] makes it a
// reload — AsyncLoading — and stays by id only. (The select is the literal
// watch per_user_provider_scope_test asks of each provider.)

final paymentServiceProvider = Provider<PaymentService>((ref) => PaymentService());

final mySubscriptionsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  ref.watch(currentUserProvider.select((u) => u?.id));
  ref.watch(paymentAccountProvider);
  return ref.watch(paymentServiceProvider).getMySubscriptions();
});

/// Coach: Stripe Connect status (connected / charges_enabled / payouts_enabled).
final coachConnectStatusProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  ref.watch(currentUserProvider.select((u) => u?.id));
  ref.watch(paymentAccountProvider);
  return ref.watch(paymentServiceProvider).connectStripeStatus();
});

/// Coach revenue metrics (monthly/lifetime/mrr/subscribers/marketplace/direct $).
final coachRevenueServiceProvider = Provider((ref) => CoachRevenueService());
final coachRevenueProvider = FutureProvider<Map<String, double>>((ref) async {
  ref.watch(currentUserProvider.select((u) => u?.id));
  ref.watch(paymentAccountProvider);
  return ref.watch(coachRevenueServiceProvider).getMetrics();
});

/// Coach: connected-account balance {pending, available} (cents).
final coachBalanceProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  ref.watch(currentUserProvider.select((u) => u?.id));
  ref.watch(paymentAccountProvider);
  return ref.watch(paymentServiceProvider).connectBalance();
});

/// Server-evaluated membership tier ('ai_guided' | 'self_guided' | null).
/// Gate platform features on this — for whoever is signed in now, which is
/// why it watches the user: the server answers for `auth.uid()`.
final membershipTierProvider = FutureProvider<String?>((ref) async {
  ref.watch(currentUserProvider.select((u) => u?.id));
  ref.watch(paymentAccountProvider);
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
  ref.watch(paymentAccountProvider);
  return ref.watch(paymentServiceProvider).coachPlanTier();
});

/// Active subscription to a given coach (null if not subscribed).
final coachSubscriptionProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, coachId) async {
  ref.watch(currentUserProvider.select((u) => u?.id));
  ref.watch(paymentAccountProvider);
  return ref.watch(paymentServiceProvider).activeCoachSubscription(coachId);
});
