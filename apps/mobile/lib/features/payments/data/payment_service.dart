import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Module 16 — Payments (Stripe).
/// The app never touches the secret key; it asks the `create-checkout` Edge
/// Function for a hosted Checkout URL and opens it, then reads subscription /
/// payment state that the `stripe-webhook` function writes back.
class PaymentService {
  final _db = Supabase.instance.client;
  String? get _uid => _db.auth.currentUser?.id;

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
      final url = (res.data is Map) ? res.data['url'] as String? : null;
      if (url == null) return false;
      final uri = Uri.parse(url);
      return launchUrl(
        uri,
        mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
        webOnlyWindowName: kIsWeb ? '_self' : null,
      );
    } catch (_) {
      return false;
    }
  }

  /// Switches the active membership to another tier in place (Self <-> AI).
  /// Returns 'changed' on success, 'needs_checkout' if there's no membership to
  /// change (caller should start a checkout), or 'error'.
  Future<String> changeMembership(String newKind) async {
    try {
      final res = await _db.functions
          .invoke('update-subscription', body: {'newKind': newKind});
      final data = res.data;
      if (data is Map && data['needsCheckout'] == true) return 'needs_checkout';
      if (data is Map && (data['ok'] == true)) return 'changed';
      return 'error';
    } catch (_) {
      return 'error';
    }
  }

  /// Cancels a subscription immediately (in-app, no portal). Returns true on
  /// success. The DB row is flipped to canceled server-side right away.
  Future<bool> cancelSubscription(String subscriptionRowId) async {
    try {
      final res = await _db.functions.invoke('cancel-subscription',
          body: {'subscriptionId': subscriptionRowId});
      return (res.data is Map) && res.data['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Coach: starts (or resumes) Stripe Connect onboarding. Opens the Stripe
  /// Account Link so the coach can receive client payments directly.
  Future<bool> connectStripeOnboard() async {
    try {
      final base = kIsWeb ? Uri.base.origin : null;
      final res = await _db.functions.invoke('stripe-connect', body: {
        'action': 'onboard',
        if (base != null) 'returnUrl': '$base/#/coach-payments',
      });
      final url = (res.data is Map) ? res.data['url'] as String? : null;
      if (url == null) return false;
      return launchUrl(Uri.parse(url),
          mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
          webOnlyWindowName: kIsWeb ? '_self' : null);
    } catch (_) {
      return false;
    }
  }

  /// Coach: connected-account balance {pending, available} in cents.
  Future<Map<String, dynamic>> connectBalance() async {
    try {
      final res = await _db.functions.invoke('stripe-connect', body: {'action': 'balance'});
      if (res.data is Map) return Map<String, dynamic>.from(res.data as Map);
    } catch (_) {}
    return {'pending': 0, 'available': 0};
  }

  /// Coach: current Connect status {connected, charges_enabled, payouts_enabled}.
  Future<Map<String, dynamic>> connectStripeStatus() async {
    try {
      final res = await _db.functions.invoke('stripe-connect', body: {'action': 'status'});
      if (res.data is Map) return Map<String, dynamic>.from(res.data as Map);
    } catch (_) {}
    return {'connected': false, 'charges_enabled': false, 'payouts_enabled': false};
  }

  /// Opens the Stripe Customer Portal (manage / update card).
  Future<bool> openBillingPortal() async {
    try {
      final base = kIsWeb ? Uri.base.origin : null;
      final res = await _db.functions.invoke('create-portal-session', body: {
        if (base != null) 'returnUrl': '$base/#/subscription',
      });
      final url = (res.data is Map) ? res.data['url'] as String? : null;
      if (url == null) return false;
      return launchUrl(
        Uri.parse(url),
        mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
        webOnlyWindowName: kIsWeb ? '_self' : null,
      );
    } catch (_) {
      return false;
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
  Future<List<Map<String, dynamic>>> getMySubscriptions() async {
    final uid = _uid;
    if (uid == null) return [];
    try {
      final data = await _db
          .from('subscriptions')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(data);
    } catch (_) {
      return [];
    }
  }

  /// The user's active platform membership tier ('ai_guided' | 'self_guided'),
  /// or null if neither. Server-evaluated via active_membership().
  Future<String?> activeMembership() async {
    try {
      final res = await _db.rpc('active_membership');
      return res is String ? res : null;
    } catch (_) {
      return null;
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
  Future<String?> coachPlanTier() async {
    try {
      final res = await _db.rpc('coach_plan_tier');
      return res is String ? res : null;
    } catch (_) {
      return null;
    }
  }

  /// Active subscription to a specific coach, if any.
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
    } catch (_) {
      return null;
    }
  }
}
