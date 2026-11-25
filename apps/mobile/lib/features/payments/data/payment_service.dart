import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show PlatformException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/observability/app_failure.dart';

/// create-checkout said no to a purchase the user already has (409
/// `already_subscribed`), with the reason to show them.
class CheckoutRefused implements Exception {
  const CheckoutRefused(this.message);
  final String message;
  @override
  String toString() => 'CheckoutRefused: $message';
}

/// The refusal inside a failed create-checkout call, or null when the failure
/// is anything else (a fault, which stays a plain "could not start").
CheckoutRefused? checkoutRefusal(FunctionException e) {
  final d = e.details;
  if (e.status != 409 || d is! Map || d['code'] != 'already_subscribed') return null;
  final msg = d['error'];
  return CheckoutRefused(msg is String && msg.isNotEmpty
      ? msg
      : 'You already have this plan.');
}

/// Who is signed in right now, or null (P0-FL-60a). Read it before the first
/// await of an action and compare before every further step: a payment page or
/// a cancellation belongs to the account that asked for it.
///
/// The only error it answers null for is the assertion of a Supabase client
/// that was never initialised (a widget test without one; the app initialises
/// it before the first frame).
String? signedInUid() {
  try {
    return Supabase.instance.client.auth.currentUser?.id;
  } on AssertionError {
    return null;
  }
}

/// True — and recorded — when [owner] is no longer the signed-in account.
/// Nothing of [owner]'s may be opened, written or said after that.
bool ownerGone(String? owner, String origin, String what) {
  if (signedInUid() == owner) return false;
  reportError(origin, _accountChanged(what), StackTrace.current);
  return true;
}

StateError _accountChanged(String what) =>
    StateError('$what: the signed-in account changed');

/// Runs [then] once, as soon as [owner] is no longer the signed-in account,
/// and returns how to stop waiting for that (P0-FL-60a).
///
/// From the auth client, not from a widget or a provider container: what it
/// takes away (a SnackBar, a sheet) outlives the screen that showed it, and
/// may have to go before the next frame.
void Function() whenOwnerGone(String? owner, void Function() then) {
  final GoTrueClient auth;
  try {
    auth = Supabase.instance.client.auth;
  } on AssertionError {
    return () {}; // no client, so no account to change (see [signedInUid])
  }
  late final StreamSubscription<AuthState> sub;
  sub = auth.onAuthStateChange.listen((_) {
    if (signedInUid() == owner) return;
    sub.cancel();
    then();
    // An auth failure is its own event's to record (and changes no account).
  }, onError: (Object _) {});
  return sub.cancel;
}

/// True when the server's answer says the change was NOT made. Anything else —
/// no answer, a fault after the payment provider may have acted, a reply that
/// was lost — leaves the outcome unknown (P0-FL-60a, item 7).
///
///  * a table read or write is one transaction: PostgREST's error means it was
///    not made, except a gateway's (502/504), which does not know;
///  * the payment functions refuse with a 4xx before they act, and name the
///    two failures after which nothing was changed.
bool definitelyRefused(Object e) => switch (e) {
      PostgrestException(:final code) => code != '502' && code != '504',
      FunctionException(:final status, :final details) =>
        (status >= 400 && status < 500 && status != 408) ||
            (details is Map &&
                const {'stripe_cancel_failed', 'Could not read your membership'}
                    .contains(details['error'])),
      _ => false,
    };

/// What a cancellation came to.
enum CancelOutcome { cancelled, refused, unconfirmed }

/// Cancellations whose `false` was not the server's refusal.
final _unconfirmedCancels = <String>{};

extension CancelSubscriptionOutcome on PaymentService {
  /// [PaymentService.cancelSubscription], with its `false` told apart: refused
  /// by the server, or not known to have failed.
  Future<CancelOutcome> cancelSubscriptionOutcome(String rowId) async {
    _unconfirmedCancels.remove(rowId);
    if (await cancelSubscription(rowId)) return CancelOutcome.cancelled;
    return _unconfirmedCancels.remove(rowId)
        ? CancelOutcome.unconfirmed
        : CancelOutcome.refused;
  }
}

/// Module 16 — Payments (Stripe).
/// The app never touches the secret key; it asks the `create-checkout` Edge
/// Function for a hosted Checkout URL and opens it, then reads subscription /
/// payment state that the `stripe-webhook` function writes back.
class PaymentService {
  final _db = Supabase.instance.client;
  String? get _uid => _db.auth.currentUser?.id;

  /// Opens [url] for [owner] — never for another account (P0-FL-60a/E13): the
  /// link was made for whoever was signed in when it was asked for, and shows
  /// their invoices, card digits or payout account. Throws when the account
  /// changed or the page did not open.
  Future<void> _open(Object? url, String? owner, String what) async {
    if (signedInUid() != owner) throw _accountChanged(what);
    if (url is! String) throw StateError('$what: no url in the answer');
    final bool opened;
    try {
      opened = await launchUrl(
        Uri.parse(url),
        mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
        webOnlyWindowName: kIsWeb ? '_self' : null,
      );
    } catch (e, st) {
      // N-5: url_launcher and Uri.parse put the LINK in their message, and it
      // opens the member's invoices or payout account for whoever has it. The
      // type and code are what is recorded.
      final code = e is PlatformException ? ' ${e.code}' : '';
      Error.throwWithStackTrace(
          StateError('$what: the page did not open (${e.runtimeType}$code)'),
          st);
    }
    if (!opened) throw StateError('$what: the page did not open');
  }

  /// Launches Stripe Checkout for the given flow. Returns false if we couldn't
  /// get / open a URL. The webhook reconciles the result asynchronously.
  /// On web, build return URLs from the app's own origin so Stripe sends the
  /// user back into the running app (hash routing) instead of a dead domain.
  ({String? success, String? cancel}) _returnUrls() {
    if (!kIsWeb) return (success: null, cancel: null);
    final base = Uri.base.origin; // e.g. http://localhost:62130
    return (success: '$base/#/payment-success', cancel: '$base/#/payment-cancel');
  }

  Future<bool> startCheckout({
    required String kind, // coach | coach_plan | self_guided | ai_guided | event_ticket | package
    String? coachId,
    String? eventId,
    String? packageId,
    String? tier, // for coach_plan: starter | growth | elite
  }) async {
    final owner = _uid;
    try {
      final urls = _returnUrls();
      final res = await _db.functions.invoke('create-checkout', body: {
        'kind': kind,
        if (coachId != null) 'coachId': coachId,
        if (eventId != null) 'eventId': eventId,
        if (packageId != null) 'packageId': packageId,
        if (tier != null) 'tier': tier,
        if (urls.success != null) 'successUrl': urls.success,
        if (urls.cancel != null) 'cancelUrl': urls.cancel,
      });
      await _open(res.data is Map ? res.data['url'] : null, owner, 'checkout');
      return true;
    } on FunctionException catch (e, st) {
      // create-checkout refuses a second live subscription for what the user
      // already pays for (409 already_subscribed). That is an answer, not a
      // fault: "try again" would never work, so the caller is told why.
      // Only the account that asked is told: the refusal is a fact about it.
      final refused = checkoutRefusal(e);
      if (refused == null) {
        reportError('PaymentService.startCheckout', e, st);
      } else if (!ownerGone(owner, 'PaymentService.startCheckout', 'checkout')) {
        throw refused;
      }
      return false;
    } catch (e, st) {
      // P0-FL-60a: the cause was lost, and a page that failed to open by
      // throwing escaped (the launch was not awaited inside this try).
      reportError('PaymentService.startCheckout', e, st);
      return false;
    }
  }

  /// Switches the active membership to another tier in place (Self <-> AI).
  /// Returns 'changed' on success, 'needs_checkout' if there's no membership to
  /// change (caller should start a checkout), 'payment_issue', 'error' (the
  /// server refused; nothing was changed) or 'unconfirmed' (no answer that says
  /// so: the swap may have gone through and only the reply been lost).
  Future<String> changeMembership(String newKind) async {
    try {
      final res = await _db.functions
          .invoke('update-subscription', body: {'newKind': newKind});
      final data = res.data;
      // A membership whose payment is failing: fix the payment, never buy a
      // second membership while Stripe retries the first.
      if (data is Map && data['paymentIssue'] == true) return 'payment_issue';
      if (data is Map && data['needsCheckout'] == true) return 'needs_checkout';
      if (data is Map && (data['ok'] == true)) return 'changed';
      throw StateError('update-subscription: unexpected response');
    } catch (e, st) {
      // P0-FL-60a: said by the caller; the cause was lost.
      reportError('PaymentService.changeMembership', e, st);
      return definitelyRefused(e) ? 'error' : 'unconfirmed';
    }
  }

  /// Cancels a subscription immediately (in-app, no portal). Returns true on
  /// success. The DB row is flipped to canceled server-side right away.
  Future<bool> cancelSubscription(String subscriptionRowId) async {
    try {
      final res = await _db.functions.invoke('cancel-subscription',
          body: {'subscriptionId': subscriptionRowId});
      return (res.data is Map) && res.data['ok'] == true;
    } catch (e, st) {
      // P0-FL-56b: `false` is said by the caller; the cause was lost.
      reportError('PaymentService.cancelSubscription', e, st);
      // Read by [CancelSubscriptionOutcome].
      if (!definitelyRefused(e)) _unconfirmedCancels.add(subscriptionRowId);
      return false;
    }
  }

  /// Coach: starts (or resumes) Stripe Connect onboarding. Opens the Stripe
  /// Account Link so the coach can receive client payments directly.
  ///
  /// Throws, recorded, when it was not opened (P0-FL-60a) — including when the
  /// account that asked is no longer the one signed in.
  Future<void> connectStripeOnboard() async {
    final owner = _uid;
    try {
      final base = kIsWeb ? Uri.base.origin : null;
      final res = await _db.functions.invoke('stripe-connect', body: {
        'action': 'onboard',
        if (base != null) 'returnUrl': '$base/#/coach-payments',
      });
      await _open(
          res.data is Map ? res.data['url'] : null, owner, 'Stripe onboarding');
    } catch (e, st) {
      reportError('PaymentService.connectStripeOnboard', e, st);
      rethrow;
    }
  }

  /// Coach: connected-account balance {pending, available} in cents.
  ///
  /// **Throws when it cannot be read (EC-14).** It answered
  /// `{'pending': 0, 'available': 0}` for any failure: a zero balance stated as
  /// fact, made from a network error. A figure that was not read is not zero.
  Future<Map<String, dynamic>> connectBalance() async {
    final res = await _db.functions.invoke('stripe-connect', body: {'action': 'balance'});
    if (res.data is Map) return Map<String, dynamic>.from(res.data as Map);
    throw StateError('stripe-connect balance: unexpected response');
  }

  /// Coach: current Connect status {connected, charges_enabled, payouts_enabled}.
  ///
  /// **Throws when it cannot be read (EC-14).** It answered `connected: false`
  /// for any failure, so a connected coach on a bad connection was told they
  /// were not connected and offered onboarding again. Status is tri-state:
  /// connected, not connected (the function says so), or unknown (an error).
  Future<Map<String, dynamic>> connectStripeStatus() async {
    final res = await _db.functions.invoke('stripe-connect', body: {'action': 'status'});
    if (res.data is Map) return Map<String, dynamic>.from(res.data as Map);
    throw StateError('stripe-connect status: unexpected response');
  }

  /// Opens the Stripe Customer Portal (manage / update card). False only when
  /// the server ANSWERED that there is no billing account yet.
  ///
  /// Throws, recorded, when it was not opened (P0-FL-60a): every failure used
  /// to be false, and a paying member on a bad connection was told "No billing
  /// account yet. Subscribe to a plan first."
  Future<bool> openBillingPortal() async {
    final owner = _uid;
    try {
      final base = kIsWeb ? Uri.base.origin : null;
      final res = await _db.functions.invoke('create-portal-session', body: {
        if (base != null) 'returnUrl': '$base/#/subscription',
      });
      await _open(
          res.data is Map ? res.data['url'] : null, owner, 'billing portal');
      return true;
    } catch (e, st) {
      if (e is FunctionException &&
          e.status == 400 &&
          e.details is Map &&
          e.details['error'] == 'No billing account yet') {
        return false;
      }
      reportError('PaymentService.openBillingPortal', e, st);
      rethrow;
    }
  }

  /// Creates an Embedded Checkout session and returns its client secret (web,
  /// in-app). Returns null on failure.
  Future<String?> createEmbeddedCheckout({
    required String kind,
    String? coachId,
    String? eventId,
    String? tier,
  }) async {
    try {
      final base = kIsWeb ? Uri.base.origin : '';
      final res = await _db.functions.invoke('create-checkout', body: {
        'kind': kind,
        if (coachId != null) 'coachId': coachId,
        if (eventId != null) 'eventId': eventId,
        if (tier != null) 'tier': tier,
        'embedded': true,
        'returnUrl': '$base/checkout_complete.html',
      });
      return (res.data is Map) ? res.data['clientSecret'] as String? : null;
    } catch (_) {
      return null;
    }
  }

  /// All of the current user's subscriptions (coach + pro).
  ///
  /// A failed read throws. It used to return `[]`, which is a different
  /// answer: "Stop" then took a paid coach for an unpaid one and ended the
  /// relationship without cancelling the subscription, and the plan section
  /// said "Free plan" to a paying member.
  Future<List<Map<String, dynamic>>> getMySubscriptions() async {
    final uid = _uid;
    if (uid == null) return [];
    final data = await _db
        .from('subscriptions')
        .select()
        .eq('user_id', uid)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(data);
  }

  /// The user's active platform membership tier ('ai_guided' | 'self_guided'),
  /// or null if neither. Server-evaluated via active_membership().
  ///
  /// A failed read throws, recorded (P0-FL-60a): null is the answer "none".
  Future<String?> activeMembership() async {
    try {
      final res = await _db.rpc('active_membership');
      return res is String ? res : null;
    } catch (e, st) {
      reportError('PaymentService.activeMembership', e, st);
      rethrow;
    }
  }

  /// The client's effective plan: 'coach_guided'|'ai_guided'|'self_guided'|'free'.
  ///
  /// **Does not catch.** `PaywallGate` states its own policy for a failed
  /// resolve:
  ///
  /// ```dart
  /// error: (_, __) => child, // fail open rather than lock a paying user out
  /// ```
  ///
  /// That arm could never run while this returned `'free'` on failure: the
  /// provider was always `AsyncData(ClientPlan.free)`, `plan != null` took the
  /// early return, and a paying Coach-Guided member whose entitlement read
  /// failed was shown `PaywallLocked` for a feature they had paid for. The
  /// gate said fail open and the app failed closed.
  ///
  /// Letting the exception out is what makes the written policy effective. It
  /// does **not** widen any server-side boundary: the gate decides whether a
  /// screen is offered, and every read inside it is still filtered by RLS.
  ///
  /// A non-String result is still `'free'` — that is an answer from a
  /// successful call, not a failure.
  Future<String?> clientPlan() async {
    final res = await _db.rpc('client_plan');
    return res is String ? res : 'free';
  }

  /// The coach's active platform plan tier ('starter'|'growth'|'elite'), or null.
  ///
  /// A failed read throws, recorded (P0-FL-60a). It used to be null — "no
  /// plan" — and a paying coach was offered every plan for sale.
  Future<String?> coachPlanTier() async {
    try {
      final res = await _db.rpc('coach_plan_tier');
      return res is String ? res : null;
    } catch (e, st) {
      reportError('PaymentService.coachPlanTier', e, st);
      rethrow;
    }
  }

  /// Active subscription to a specific coach, if any. A failed read throws,
  /// recorded (P0-FL-60a): null is the answer "not subscribed".
  Future<Map<String, dynamic>?> activeCoachSubscription(String coachId) async {
    final uid = _uid;
    if (uid == null) return null;
    try {
      return await _db
          .from('subscriptions')
          .select()
          .eq('user_id', uid)
          .eq('coach_id', coachId)
          .inFilter('status', ['active', 'trialing'])
          .maybeSingle();
    } catch (e, st) {
      reportError('PaymentService.activeCoachSubscription', e, st);
      rethrow;
    }
  }
}
