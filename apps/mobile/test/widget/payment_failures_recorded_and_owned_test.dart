import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthChangeEvent, Supabase;

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/payments/data/payment_service.dart';
import 'package:circle_fitness/features/payments/domain/entitlements.dart';
import 'package:circle_fitness/features/payments/domain/payment_provider.dart';
import 'package:circle_fitness/features/payments/presentation/checkout_launcher.dart'
    show checkoutFailedMessage;
import 'package:circle_fitness/features/payments/presentation/coach_payments_screen.dart';
import 'package:circle_fitness/features/payments/presentation/coach_plan_screen.dart';
import 'package:circle_fitness/features/payments/presentation/manage_subscription_screen.dart';
import 'package:circle_fitness/features/payments/presentation/payment_result_screen.dart';
import 'package:circle_fitness/features/payments/presentation/paywall_gate.dart';
import 'package:circle_fitness/features/payments/presentation/upgrade_screen.dart';
import 'package:circle_fitness/features/profile/presentation/subscription_screen.dart';
import 'package:circle_fitness/features/workout/presentation/widgets/section_load_failure.dart';

import '../support/pump_until.dart';
import '../support/settled.dart' show eventually;
import '../support/two_member_postgrest.dart';

// P0-FL-60a · payment failures are recorded, and a payment page opens only for
// the account that asked.
//
//  (a) PaymentService lost the cause of every failure; a failed plan read was
//      "no plan" (so every plan was for sale); a failed portal was "No billing
//      account yet"; a page that failed to open by throwing escaped.
//  (b) E13/W26: a checkout, portal or onboarding link requested by A opened
//      for B, and A's plan change could mint a checkout for B.
//  (c) A-19/A-21: A's revenue, balance, status and plan were B's — while B's
//      read ran, and for good when it failed.
//
// Two real accounts on one device, through the real auth client and the real
// providers; nothing here mounts an account scope, and every screen STAYS
// mounted across the switch. The request log says who asked for what.
//
// HOW TO SEE IT FAIL: `git checkout a82f993 -- lib/features/payments`. The
// groups marked R3 (rounds 2 and 3) fail on 5cafdd4 or 46ec3f0 too (with
// lib/features/profile/presentation/subscription_screen.dart). What needs the
// new helpers by name is in test/unit/payment_ownership_helpers_test.dart.

class _Server extends TwoMemberPostgrest {
  /// Answers keyed `METHOD name:<who asked>`, else `name:<who asked>`, else
  /// `name`: an rpc, a function or a table name. `(status, body)`.
  final answers = <String, (int, Object?)>{};

  /// `name:<who>` held until completed. The answer is the one that was true
  /// when the request ARRIVED.
  final gates = <String, Completer<void>>{};

  /// `name:<who>` whose connection is lost: the request is thrown, unanswered.
  final lost = <String>{};

  /// Every non-auth request: `name:<who>`.
  final log = <String>[];

  /// `METHOD table:<who>` of every table write.
  final writes = <String>[];

  /// Bodies of function calls, as `name:<who> {json}`.
  final bodies = <String>[];

  @override
  void reset() {
    super.reset();
    answers.clear();
    gates.clear();
    lost.clear();
    log.clear();
    bodies.clear();
    writes.clear();
  }

  int count(String name, [String? who]) => log
      .where((l) => who == null ? l.startsWith('$name:') : l == '$name:$who')
      .length;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (path.startsWith('/auth/v1/')) return super.send(request);
    final name = path.split('/').last;
    final key = '$name:${TwoMemberPostgrest.who(request)}';
    log.add(key);
    if (path.startsWith('/functions/') && request is http.Request) {
      bodies.add('$key ${request.body}');
    }
    if (request.method != 'GET' &&
        path.startsWith('/rest/') &&
        !path.contains('/rpc/')) {
      writes.add('${request.method} $key');
    }
    final (status, body) = answers['${request.method} $key'] ??
        answers[key] ??
        answers[name] ??
        (path.contains('/rpc/') ? (200, null) : (200, const <Object?>[]));
    final gate = gates[key];
    if (gate != null) await gate.future;
    if (lost.contains(key)) {
      throw http.ClientException('Connection closed', request.url);
    }
    return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))), status,
        request: request, headers: {'content-type': 'application/json'});
  }
}

/// What the device was asked to open, and what it answers.
enum _Launch { opens, refuses, throws }

const _a = memberA;
const _b = memberB;
const _down = (500, {'message': 'SECRET backend text', 'code': 'XX000'});

void main() {
  final server = _Server();
  final reported = <AppFailure>[];
  final launched = <String>[];
  var launch = _Launch.opens;

  const channel = MethodChannel('plugins.flutter.io/url_launcher');

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(server);
  });

  setUp(() {
    server.reset();
    reported.clear();
    launched.clear();
    launch = _Launch.opens;
    setFailureSink(reported.add);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'canLaunch') return true;
      if (call.method != 'launch') return null;
      launched.add((call.arguments as Map)['url'] as String);
      return switch (launch) {
        _Launch.opens => true,
        _Launch.refuses => false,
        // As url_launcher does: the link is in the message.
        _Launch.throws => throw PlatformException(
            code: 'ACTIVITY_NOT_FOUND',
            message: 'No Activity found to handle intent { ${launched.last} }'),
      };
    });
  });
  tearDown(resetFailureSink);

  Iterable<String> origins() => reported.map((f) => f.origin);
  bool recordedAccountChange() => reported
      .any((f) => '${f.error}'.contains('the signed-in account changed'));

  // ── the service ───────────────────────────────────────────────────────────
  group('PaymentService records why it failed', () {
    setUp(() => signInAs(_a));
    final svc = PaymentService.new;

    test('startCheckout: a server failure is false, recorded', () async {
      server.answers['create-checkout'] = _down;
      expect(await svc().startCheckout(kind: 'ai_guided'), isFalse);
      expect(origins(), ['PaymentService.startCheckout']);
    });

    test('startCheckout: an answer without a url is false, recorded', () async {
      server.answers['create-checkout'] = (200, {'ok': true});
      expect(await svc().startCheckout(kind: 'ai_guided'), isFalse);
      expect(origins(), ['PaymentService.startCheckout']);
    });

    test('startCheckout: a page that did not open is false, recorded', () async {
      server.answers['create-checkout'] = (200, {'url': 'https://pay/a'});
      launch = _Launch.refuses;
      expect(await svc().startCheckout(kind: 'ai_guided'), isFalse);
      expect(launched, ['https://pay/a'], reason: 'premise: it was tried');
      expect(origins(), ['PaymentService.startCheckout']);
    });

    test('startCheckout: a page that failed to open by throwing does not escape',
        () async {
      server.answers['create-checkout'] = (200, {'url': 'https://pay/a'});
      launch = _Launch.throws;
      expect(await svc().startCheckout(kind: 'ai_guided'), isFalse);
      expect(origins(), ['PaymentService.startCheckout']);
    });

    test('control: 409 already_subscribed is an answer, thrown, not recorded',
        () async {
      server.answers['create-checkout'] =
          (409, {'code': 'already_subscribed', 'error': 'You have this.'});
      await expectLater(svc().startCheckout(kind: 'ai_guided'),
          throwsA(isA<CheckoutRefused>()));
      expect(reported, isEmpty);
    });

    test('control: checkout opens; the request body is unchanged', () async {
      server.answers['create-checkout'] = (200, {'url': 'https://pay/a'});
      expect(
          await svc().startCheckout(kind: 'coach_plan', tier: 'growth'), isTrue);
      expect(launched, ['https://pay/a']);
      expect(server.bodies,
          ['create-checkout:$_a {"kind":"coach_plan","tier":"growth"}']);
      expect(reported, isEmpty);
    });

    test('changeMembership: a failure and an unreadable answer are recorded',
        () async {
      server.answers['update-subscription'] = _down;
      // R3 (item 7): the 500 may come after Stripe swapped the plan, and the
      // unreadable answer says nothing — neither is "it was not changed".
      expect(await svc().changeMembership('ai_guided'), 'unconfirmed');
      server.answers['update-subscription'] = (200, {'what': 1});
      expect(await svc().changeMembership('ai_guided'), 'unconfirmed');
      expect(origins(), [
        'PaymentService.changeMembership',
        'PaymentService.changeMembership'
      ]);
    });

    test('control: changeMembership answers are answers', () async {
      for (final (body, want) in [
        ({'ok': true}, 'changed'),
        ({'needsCheckout': true}, 'needs_checkout'),
        ({'paymentIssue': true}, 'payment_issue'),
      ]) {
        server.answers['update-subscription'] = (200, body);
        expect(await svc().changeMembership('ai_guided'), want);
      }
      expect(reported, isEmpty);
    });

    test('openBillingPortal: a failure is not "no billing account"', () async {
      server.answers['create-portal-session'] = _down;
      await expectLater(svc().openBillingPortal(), throwsA(anything));
      expect(origins(), ['PaymentService.openBillingPortal']);
    });

    test('openBillingPortal: a page that did not open is not "no account"',
        () async {
      server.answers['create-portal-session'] = (200, {'url': 'https://p/a'});
      launch = _Launch.refuses;
      await expectLater(svc().openBillingPortal(), throwsA(anything));
      expect(origins(), ['PaymentService.openBillingPortal']);
    });

    test('control: "No billing account yet" is false, not recorded', () async {
      server.answers['create-portal-session'] =
          (400, {'error': 'No billing account yet'});
      expect(await svc().openBillingPortal(), isFalse);
      expect(reported, isEmpty);
    });

    test('connectStripeOnboard: a failure is thrown and recorded', () async {
      server.answers['stripe-connect'] = _down;
      await expectLater(svc().connectStripeOnboard(), throwsA(anything));
      expect(origins(), ['PaymentService.connectStripeOnboard']);
    });

    final reads = <String, (String, Future<Object?> Function())>{
      'activeMembership': ('active_membership', () => svc().activeMembership()),
      'coachPlanTier': ('coach_plan_tier', () => svc().coachPlanTier()),
      'activeCoachSubscription': (
        'subscriptions',
        () => svc().activeCoachSubscription('coach-1')
      ),
    };
    reads.forEach((name, r) {
      test('$name: a failed read throws, recorded — not null', () async {
        server.answers[r.$1] = _down;
        await expectLater(r.$2(), throwsA(anything));
        expect(origins(), ['PaymentService.$name']);
      });

      test('control: $name answering none is null, not recorded', () async {
        expect(await r.$2(), isNull);
        expect(reported, isEmpty);
      });
    });

    test('hasMembership: unread is unknown, none is false, one is true',
        () async {
      Future<Object?> answer((int, Object?) a) async {
        server.answers['active_membership'] = a;
        final c = ProviderContainer();
        addTearDown(c.dispose);
        c.listen<Object?>(hasMembershipProvider, (_, __) {});
        try {
          await c.read(membershipTierProvider.future);
        } catch (_) {}
        await pumpEventQueue();
        return c.read(hasMembershipProvider);
      }

      expect(await answer(_down), isNull, reason: 'it answered false');
      expect(await answer((200, null)), isFalse);
      expect(await answer((200, 'ai_guided')), isTrue);
    });
  });

  group('a payment page opens only for the account that asked (E13)', () {
    final openers = <String, (String, Future<Object?> Function())>{
      'startCheckout': (
        'create-checkout',
        () => PaymentService().startCheckout(kind: 'ai_guided')
      ),
      'openBillingPortal': (
        'create-portal-session',
        () => PaymentService().openBillingPortal()
      ),
      'connectStripeOnboard': (
        'stripe-connect',
        () async {
          await PaymentService().connectStripeOnboard();
          return null;
        }
      ),
    };

    openers.forEach((name, o) {
      Future<void> during(Future<void> Function() change) async {
        await signInAs(_a);
        server.answers['${o.$1}:$_a'] = (200, {'url': 'https://stripe/a'});
        final gate = server.gates['${o.$1}:$_a'] = Completer();
        final done = o.$2().then<void>((_) {}, onError: (_) {});
        // C14-FLAKE-01: this was `pumpEventQueue()` (20 turns) and then the
        // premise. Under load the invoke had not reached the server in 20
        // turns (CI: Expected ['stripe-connect:<A>'] Actual []), so the
        // control failed before anything was opened. The request is now
        // waited for as an event, bounded, and the premise is unchanged.
        await eventually(() => server.log, ['${o.$1}:$_a'],
            reason: 'premise: A asked');
        await change();
        gate.complete();
        await done;
      }

      test('$name: A → B while the link is made: nothing opens', () async {
        await during(() => signInAs(_b));
        expect(launched, isEmpty, reason: "A's page opened for B");
        expect(recordedAccountChange(), isTrue);
        expect(server.log, ['${o.$1}:$_a'], reason: 'nothing was sent as B');
      });

      test('$name: A signed out while the link is made: nothing opens',
          () async {
        await during(signOut);
        expect(launched, isEmpty);
        expect(recordedAccountChange(), isTrue);
      });

      test('$name: control — a token refresh is the same account: it opens',
          () async {
        await during(refreshSession);
        expect(launched, ['https://stripe/a']);
        expect(reported, isEmpty);
      });

      test('$name: control — A signs out and back in: it opens', () async {
        await during(() async {
          await signOut();
          await signInAs(_a);
        });
        expect(launched, ['https://stripe/a']);
      });
    });

    test("A's 409 is not thrown to B", () async {
      await signInAs(_a);
      server.answers['create-checkout:$_a'] =
          (409, {'code': 'already_subscribed', 'error': 'You have this.'});
      final gate = server.gates['create-checkout:$_a'] = Completer();
      final done = PaymentService().startCheckout(kind: 'ai_guided');
      // C14-FLAKE-01: the same unsynchronised step: B must sign in while A's
      // request is held, not before it was sent.
      await eventually(() => server.log, ['create-checkout:$_a'],
          reason: 'premise: A asked');
      await signInAs(_b);
      gate.complete();
      expect(await done, isFalse);
      expect(recordedAccountChange(), isTrue);
    });
  });

  // ── the screens ───────────────────────────────────────────────────────────

  Future<void> signIn(WidgetTester t, String uid) async {
    await t.runAsync(() => signInAs(uid));
    await t.pump();
  }

  Future<void> open(WidgetTester t, Widget screen, {String as = _a}) async {
    await t.binding.setSurfaceSize(const Size(700, 3200));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.runAsync(() => signInAs(as));
    await t.pumpWidget(ProviderScope(child: MaterialApp(home: screen)));
    await t.pump();
  }

  Future<void> until(WidgetTester t, bool Function() ok, String what) =>
      pumpUntil(t, ok, what: what);

  /// Lets everything in flight land (nothing observable is expected).
  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 12; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  /// The same without drawing a frame: what was in flight lands and runs, the
  /// screen and Riverpod's flush (which needs a frame) stay where they were.
  Future<void> noFrames(WidgetTester t) async {
    for (var i = 0; i < 12; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await t.idle();
    }
  }

  // By name, so this file also compiles against the code before the fix.
  final ownedDialog = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == 'OwnedDialog');

  ProviderContainer container(WidgetTester t) =>
      ProviderScope.containerOf(t.element(find.byType(MaterialApp)));

  bool seen(Finder f) => f.evaluate().isNotEmpty;

  Iterable<String> enabled(WidgetTester t, {String startsWith = ''}) sync* {
    for (final e in find.byType(ElevatedButton).evaluate()) {
      final b = e.widget as ElevatedButton;
      if (b.onPressed == null) continue;
      final label = find
          .descendant(of: find.byWidget(b), matching: find.byType(Text))
          .evaluate();
      final text =
          label.isEmpty ? '' : (label.first.widget as Text).data ?? '';
      if (text.startsWith(startsWith)) yield text;
    }
  }

  void noBackendText() =>
      expect(find.textContaining('SECRET'), findsNothing);

  group('Plans (Upgrade)', () {
    const sub1 = {'id': 'sub-1', 'kind': 'self_guided', 'status': 'active'};
    const sub2 = {'id': 'sub-2', 'kind': 'ai_guided', 'status': 'active'};

    Future<void> openAsA(WidgetTester t, {String plan = 'self_guided'}) async {
      server.answers['client_plan:$_a'] = (200, plan);
      server.answers['subscriptions:$_a'] = (200, [sub1, sub2]);
      await open(t, const UpgradeScreen());
      await until(t, () => seen(find.text('Current')), "A's plan");
    }

    testWidgets("W26: A's plan change answers after B signed in: no checkout "
        'for B', (t) async {
      await openAsA(t);
      server.answers['client_plan:$_b'] = (200, 'free');
      server.answers['update-subscription:$_a'] = (200, {'needsCheckout': true});
      server.answers['create-checkout'] = (200, {'url': 'https://stripe/x'});
      final gate = server.gates['update-subscription:$_a'] = Completer();
      await t.tap(find.text('Upgrade to AI-Guided'));
      await until(t, () => server.count('update-subscription') == 1, 'A asked');
      await signIn(t, _b);
      await until(t, () => seen(find.text('Upgrade to Self-Guided')), "B's plan");
      gate.complete();
      await settle(t);
      expect(server.count('create-checkout'), 0,
          reason: "A's plan change minted a checkout for B");
      expect(launched, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      expect(recordedAccountChange(), isTrue);
    });


    testWidgets("no-frame: A's plan card tapped after B signed in sends nothing", (t) async {
      await openAsA(t);
      server.answers['client_plan:$_b'] = (200, 'self_guided');
      server.answers['update-subscription:$_b'] = (200, {'ok': true});
      await t.runAsync(() => signInAs(_b)); // no pump
      await t.tap(find.text('Upgrade to AI-Guided'));
      await settle(t);
      expect(server.count('update-subscription', _b), 0);
      expect(server.count('update-subscription'), 0);
      expect(recordedAccountChange(), isTrue, reason: 'the refusal is recorded');
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets("A's busy plan card is not busy for B", (t) async {
      await openAsA(t);
      server.answers['client_plan:$_b'] = (200, 'free');
      final gate = server.gates['update-subscription:$_a'] = Completer();
      await t.tap(find.text('Upgrade to AI-Guided'));
      await until(t, () => server.count('update-subscription') == 1, 'A asked');
      await signIn(t, _b);
      await until(t, () => seen(find.text('Upgrade to Self-Guided')), "B's plan");
      expect(enabled(t, startsWith: 'Upgrade to AI-Guided'), isNotEmpty);
      gate.complete();
      await settle(t);
    });

    for (final (answer, what) in [
      ((200, {'ok': true}), 'changed'),
      (_down, 'failed'),
    ]) {
      testWidgets("A's plan change that $what says nothing to B", (t) async {
        await openAsA(t);
        server.answers['client_plan:$_b'] = (200, 'free');
        server.answers['update-subscription:$_a'] = answer;
        final gate = server.gates['update-subscription:$_a'] = Completer();
        await t.tap(find.text('Upgrade to AI-Guided'));
        await until(t, () => server.count('update-subscription') == 1, 'A asked');
        await signIn(t, _b);
        await until(
            t, () => seen(find.text('Upgrade to Self-Guided')), "B's plan");
        gate.complete();
        await settle(t);
        expect(find.byType(SnackBar), findsNothing);
      });
    }

    testWidgets('control: needs_checkout for the same account (its token '
        'refreshed meanwhile) opens one checkout', (t) async {
      await openAsA(t);
      server.answers['update-subscription:$_a'] = (200, {'needsCheckout': true});
      server.answers['create-checkout:$_a'] = (200, {'url': 'https://stripe/a'});
      final gate = server.gates['update-subscription:$_a'] = Completer();
      await t.tap(find.text('Upgrade to AI-Guided'));
      await until(t, () => server.count('update-subscription') == 1, 'A asked');
      await t.runAsync(refreshSession);
      await t.pump();
      gate.complete();
      await until(t, () => launched.isNotEmpty, 'the checkout page');
      await settle(t);
      expect(launched, ['https://stripe/a']);
      expect(server.count('create-checkout', _a), 1);
      expect(server.count('create-checkout'), 1);
      expect(find.byType(SnackBar), findsNothing);
      expect(reported, isEmpty);
    });

    testWidgets('a checkout page that fails to open is said and recorded',
        (t) async {
      await openAsA(t);
      server.answers['update-subscription:$_a'] = (200, {'needsCheckout': true});
      server.answers['create-checkout:$_a'] = (200, {'url': 'https://stripe/a'});
      launch = _Launch.throws;
      await t.tap(find.text('Upgrade to AI-Guided'));
      await until(
          t,
          () => seen(find.text('Could not start checkout. Try again.')),
          'the failure');
      expect(origins(), contains('PaymentService.startCheckout'));
      await settle(t);
      expect(enabled(t, startsWith: 'Upgrade to AI-Guided'), isNotEmpty);
    });

    testWidgets("A's failed checkout is not said to B", (t) async {
      await openAsA(t);
      server.answers['client_plan:$_b'] = (200, 'free');
      server.answers['update-subscription:$_a'] = (200, {'needsCheckout': true});
      server.answers['create-checkout:$_a'] =
          (409, {'code': 'already_subscribed', 'error': 'You have AI-Guided.'});
      final gate = server.gates['create-checkout:$_a'] = Completer();
      await t.tap(find.text('Upgrade to AI-Guided'));
      await until(t, () => server.count('create-checkout') == 1, 'A asked');
      await signIn(t, _b);
      await until(t, () => seen(find.text('Upgrade to Self-Guided')), "B's plan");
      gate.complete();
      await settle(t);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.textContaining('You have AI-Guided'), findsNothing);
    });

    testWidgets("Switch to Free: B signs in over A's dialog: it goes away and "
        'nothing is cancelled', (t) async {
      await openAsA(t);
      server.answers['client_plan:$_b'] = (200, 'free');
      await t.tap(find.text('Switch to Free'));
      await until(t, () => seen(find.text('Switch to Free?')), 'the dialog');
      await settle(t);
      await signIn(t, _b);
      await settle(t);
      expect(find.text('Switch to Free?'), findsNothing);
      expect(ownedDialog, findsNothing, reason: 'its barrier too');
      expect(server.count('cancel-subscription'), 0);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets("Switch to Free: B signs in between A's two cancellations: "
        'the second is never sent', (t) async {
      await openAsA(t);
      server.answers['client_plan:$_b'] = (200, 'free');
      server.answers['cancel-subscription'] = (200, {'ok': true});
      final gate = server.gates['cancel-subscription:$_a'] = Completer();
      await t.tap(find.text('Switch to Free'));
      await until(t, () => seen(find.text('Switch to Free?')), 'the dialog');
      await settle(t);
      await t.tap(find.text('Switch to Free').last);
      await until(t, () => server.count('cancel-subscription') == 1, 'one sent');
      await signIn(t, _b);
      gate.complete();
      await settle(t);
      expect(server.count('cancel-subscription', _b), 0,
          reason: "A's membership was cancelled as B");
      expect(server.count('cancel-subscription'), 1);
      expect(find.byType(SnackBar), findsNothing);
      expect(recordedAccountChange(), isTrue);
    });

    testWidgets('control: Switch to Free cancels both for the same account',
        (t) async {
      await openAsA(t);
      server.answers['cancel-subscription'] = (200, {'ok': true});
      await t.tap(find.text('Switch to Free'));
      await until(t, () => seen(find.text('Switch to Free?')), 'the dialog');
      await settle(t);
      await t.runAsync(refreshSession);
      await settle(t);
      expect(find.text('Switch to Free?'), findsOneWidget,
          reason: 'a token refresh is the same account');
      await t.tap(find.text('Switch to Free').last);
      await until(t, () => seen(find.text('Switched to the Free plan.')), 'said');
      expect(server.count('cancel-subscription', _a), 2);
      expect(reported, isEmpty);
    });

    testWidgets('Switch to Free: an unread subscription list is recorded and '
        'said; nothing is cancelled', (t) async {
      await openAsA(t);
      server.answers['subscriptions:$_a'] = _down;
      await t.tap(find.text('Switch to Free'));
      await until(t, () => seen(find.byType(SnackBar)), 'the failure');
      expect(
          find.text("Couldn't load your subscriptions — try again in a moment. "
              'If it keeps happening, contact support. Nothing was cancelled.'),
          findsOneWidget);
      expect(origins(), contains('UpgradeScreen.mySubscriptions'));
      expect(server.count('cancel-subscription'), 0);
      noBackendText();
    });

    testWidgets("A-21: B's plan read pending: A's plan is not B's", (t) async {
      await openAsA(t);
      final gate = server.gates['client_plan:$_b'] = Completer();
      server.answers['client_plan:$_b'] = (200, 'free');
      await signIn(t, _b);
      await until(t, () => server.count('client_plan', _b) >= 1, 'B asked');
      await settle(t);
      expect(find.text('Current'), findsNothing);
      expect(enabled(t), isEmpty);
      gate.complete();
      await until(t, () => seen(find.text('Upgrade to Self-Guided')), "B's plan");
    });

    testWidgets("A-21: B's plan read failed: A's plan is not B's, and it is "
        'said', (t) async {
      await openAsA(t);
      server.answers['client_plan:$_b'] = _down;
      await signIn(t, _b);
      await until(
          t, () => origins().contains('UpgradeScreen.clientPlan'), 'failure');
      await settle(t);
      expect(find.text('Current'), findsNothing, reason: "A's plan for B");
      expect(find.byType(PlanLoadFailedNotice), findsOneWidget);
      expect(enabled(t), isEmpty);
      noBackendText();
      server.answers['client_plan:$_b'] = (200, 'free');
      await t.tap(find.text('Try again'));
      await until(t, () => seen(find.text('Upgrade to Self-Guided')), "B's plan");
    });

    testWidgets("A-21: A's late plan answer lands after B's", (t) async {
      server.answers['client_plan:$_a'] = (200, 'ai_guided');
      server.answers['client_plan:$_b'] = (200, 'free');
      final gate = server.gates['client_plan:$_a'] = Completer();
      await open(t, const UpgradeScreen());
      await until(t, () => server.count('client_plan', _a) >= 1, 'A asked');
      await signIn(t, _b);
      await until(t, () => seen(find.text('Upgrade to Self-Guided')), "B's plan");
      gate.complete();
      await settle(t);
      expect(find.text('Upgrade to Self-Guided'), findsOneWidget);
    });

    testWidgets('A-21: signed out, A\'s plan goes away; A back in gets it again',
        (t) async {
      await openAsA(t);
      server.answers['client_plan:anon'] = _down;
      await t.runAsync(signOut);
      await settle(t);
      expect(find.text('Current'), findsNothing);
      await signIn(t, _a);
      await until(t, () => seen(find.text('Current')), "A's plan again");
    });

    testWidgets('control: a failed refresh by the same account keeps its plan',
        (t) async {
      await openAsA(t);
      server.answers['client_plan:$_a'] = _down;
      container(t).invalidate(clientPlanProvider);
      await until(
          t, () => origins().contains('UpgradeScreen.clientPlan'), 'failure');
      await settle(t);
      expect(find.text('Current'), findsOneWidget);
      expect(enabled(t, startsWith: 'Upgrade to AI-Guided'), isNotEmpty);
    });

    testWidgets("A-21: A's coach is not offered to B while B's coach is unread",
        (t) async {
      server.answers['coach_client_relationships:$_a'] =
          (200, {'coach_id': 'c-a', 'status': 'active'});
      server.answers['public_profiles:$_a'] =
          (200, {'id': 'c-a', 'first_name': 'Anna', 'last_name': 'Coach'});
      await openAsA(t, plan: 'coach_guided');
      await until(
          t, () => seen(find.text("View Anna Coach's packages")), "A's coach");
      server.answers['client_plan:$_b'] = (200, 'coach_guided');
      server.answers['coach_client_relationships:$_b'] = _down;
      await signIn(t, _b);
      await until(t, () => server.count('coach_client_relationships', _b) >= 1,
          'B asked');
      await settle(t);
      expect(find.textContaining('Anna'), findsNothing,
          reason: "A's coach offered to B");
      expect(find.text("Couldn't load your coach"), findsOneWidget);
      expect(find.text('Current'), findsOneWidget, reason: "B's own plan");
    });
  });

  group('plan chip (Profile and Settings rows)', () {
    testWidgets("A-21: A's plan is not B's — pending, then failed", (t) async {
      server.answers['client_plan:$_a'] = (200, 'ai_guided');
      await open(t, Scaffold(body: PlanChipState(chip: Text.new)));
      await until(t, () => seen(find.text('AI-GUIDED')), "A's plan");
      await t.runAsync(refreshSession);
      await settle(t);
      expect(find.text('AI-GUIDED'), findsOneWidget,
          reason: 'control: a token refresh is the same account');
      server.answers['client_plan:$_b'] = _down;
      final gate = server.gates['client_plan:$_b'] = Completer();
      await signIn(t, _b);
      await until(t, () => server.count('client_plan', _b) >= 1, 'B asked');
      await settle(t);
      expect(find.text('AI-GUIDED'), findsNothing, reason: 'pending');
      expect(find.text('…'), findsOneWidget);
      gate.complete();
      await until(t, () => seen(find.text('—')), 'the failure');
      expect(find.text('AI-GUIDED'), findsNothing, reason: 'failed');
    });
  });

  group('Coach plan', () {
    Future<void> openAsA(WidgetTester t, {Object? tier = 'growth'}) async {
      server.answers['coach_plan_tier:$_a'] = (200, tier);
      await open(t, const CoachPlanScreen());
      await until(t, () => enabled(t, startsWith: 'Choose').isNotEmpty, 'plans');
    }


    testWidgets("no-frame: A's plan re-read before B's account arrived is not B's", (t) async {
      await openAsA(t, tier: 'growth');
      expect(find.text('Current'), findsOneWidget);
      server.answers['coach_plan_tier:$_b'] = (500, {'message': 'down'});
      final c = ProviderScope.containerOf(t.element(find.byType(CoachPlanScreen)), listen: false);
      await t.runAsync(() => signInAs(_b)); // no pump
      c.invalidate(coachPlanTierProvider);
      await settle(t);
      expect(find.text('Current'), findsNothing);
      expect(find.textContaining('from the last time'), findsNothing);
    });

    testWidgets("no-frame: A's coach plan card tapped after B signed in sends nothing", (t) async {
      await openAsA(t, tier: null);
      server.answers['coach_plan_tier:$_b'] = (200, 'growth');
      server.answers['create-checkout:$_b'] = (200, {'url': 'https://stripe/b'});
      await t.runAsync(() => signInAs(_b)); // no pump
      await t.tap(find.text('Choose Starter'));
      await settle(t);
      expect(server.count('create-checkout', _b), 0);
      expect(recordedAccountChange(), isTrue);
    });
    testWidgets('an unread tier is not "no plan": nothing is for sale, it is '
        'said, and Try again re-reads', (t) async {
      server.answers['coach_plan_tier:$_a'] = _down;
      await open(t, const CoachPlanScreen());
      await until(t, () => server.count('coach_plan_tier') >= 1, 'asked');
      await settle(t);
      expect(enabled(t, startsWith: 'Choose'), isEmpty,
          reason: 'a paying coach was offered every plan');
      expect(find.text("Couldn't load your plan"), findsOneWidget);
      expect(find.text('Current'), findsNothing);
      expect(origins(), ['PaymentService.coachPlanTier']);
      noBackendText();
      server.answers['coach_plan_tier:$_a'] = (200, 'growth');
      await t.tap(find.text('Try again'));
      await until(t, () => seen(find.text('Current')), 'the plan');
      expect(find.byType(SectionLoadFailure), findsNothing);
      expect(enabled(t, startsWith: 'Choose'), hasLength(2));
    });

    testWidgets('nothing is for sale while the tier is being read', (t) async {
      final gate = server.gates['coach_plan_tier:$_a'] = Completer();
      await open(t, const CoachPlanScreen());
      await until(t, () => server.count('coach_plan_tier') >= 1, 'asked');
      expect(enabled(t, startsWith: 'Choose'), isEmpty);
      expect(find.text('Loading your plan…'), findsOneWidget);
      gate.complete();
      await until(t, () => enabled(t).isNotEmpty, 'the answer');
    });

    testWidgets('control: no plan is an answer — all three are for sale, and '
        'choosing one opens its checkout', (t) async {
      await openAsA(t, tier: null);
      expect(enabled(t, startsWith: 'Choose'), hasLength(3));
      expect(find.byType(SectionLoadFailure), findsNothing);
      server.answers['create-checkout:$_a'] = (200, {'url': 'https://stripe/a'});
      await t.tap(find.text('Choose Growth'));
      await until(t, () => launched.isNotEmpty, 'checkout');
      await settle(t);
      expect(server.bodies,
          ['create-checkout:$_a {"kind":"coach_plan","tier":"growth"}']);
      expect(reported, isEmpty);
    });

    testWidgets("A-19: B's tier pending, then failed: A's is never B's",
        (t) async {
      await openAsA(t);
      expect(find.text('Current'), findsOneWidget);
      server.answers['coach_plan_tier:$_b'] = _down;
      final gate = server.gates['coach_plan_tier:$_b'] = Completer();
      await signIn(t, _b);
      await until(t, () => server.count('coach_plan_tier', _b) == 1, 'B asked');
      await settle(t);
      expect(find.text('Current'), findsNothing, reason: 'pending');
      expect(enabled(t, startsWith: 'Choose'), isEmpty);
      gate.complete();
      await until(t, () => seen(find.byType(SectionLoadFailure)), 'failure');
      expect(find.text('Current'), findsNothing, reason: 'failed');
      expect(enabled(t, startsWith: 'Choose'), isEmpty);
    });

    testWidgets('A-19: coach A → coach B with a tier of their own', (t) async {
      await openAsA(t);
      server.answers['coach_plan_tier:$_b'] = (200, 'elite');
      await signIn(t, _b);
      await until(
          t, () => enabled(t, startsWith: 'Choose').length == 2, "B's plans");
      expect(find.text('Choose Elite'), findsNothing);
    });

    testWidgets('A-19: sign-out, then B while the screen is not shown',
        (t) async {
      server.answers['coach_plan_tier:$_a'] = (200, 'growth');
      final c = ProviderContainer();
      addTearDown(c.dispose);
      Future<void> show(Widget w) async {
        await t.pumpWidget(UncontrolledProviderScope(
            container: c, child: MaterialApp(home: w)));
        await t.pump();
      }

      await t.binding.setSurfaceSize(const Size(700, 3200));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.runAsync(() => signInAs(_a));
      await show(const CoachPlanScreen());
      await until(t, () => seen(find.text('Current')), "A's plan");
      await show(const SizedBox());
      await t.runAsync(signOut);
      await t.runAsync(() => signInAs(_b));
      server.answers['coach_plan_tier:$_b'] = _down;
      await show(const CoachPlanScreen());
      expect(find.text('Current'), findsNothing,
          reason: "A's plan was B's while B's read ran");
      await settle(t);
      expect(find.text('Current'), findsNothing, reason: 'failed');
      expect(find.byType(SectionLoadFailure), findsOneWidget);
      expect(enabled(t, startsWith: 'Choose'), isEmpty);
    });

    testWidgets('control: a token refresh neither re-reads nor drops it',
        (t) async {
      await openAsA(t);
      await t.runAsync(refreshSession);
      await settle(t);
      expect(server.count('coach_plan_tier'), 1);
      expect(find.text('Current'), findsOneWidget);
    });

    testWidgets('control: a failed refresh keeps the plan, says so, and holds '
        'the choice', (t) async {
      await openAsA(t);
      server.answers['coach_plan_tier:$_a'] = _down;
      final before = server.count('coach_plan_tier');
      container(t).invalidate(coachPlanTierProvider);
      await until(
          t, () => server.count('coach_plan_tier') > before, 're-read');
      await settle(t);
      expect(find.text('Current'), findsOneWidget,
          reason: 'a failed refresh lost the plan');
      expect(find.byType(SectionLoadFailure), findsOneWidget);
      expect(enabled(t, startsWith: 'Choose'), isEmpty);
    });

    testWidgets("B signs in while A's checkout is made: nothing opens and "
        "B's card is not busy", (t) async {
      await openAsA(t, tier: null);
      server.answers['coach_plan_tier:$_b'] = (200, null);
      server.answers['create-checkout:$_a'] = (200, {'url': 'https://stripe/a'});
      final gate = server.gates['create-checkout:$_a'] = Completer();
      await t.tap(find.text('Choose Growth'));
      await until(t, () => server.count('create-checkout') == 1, 'A asked');
      await signIn(t, _b);
      await settle(t);
      final plans = enabled(t, startsWith: 'Choose').toList();
      gate.complete();
      await settle(t);
      expect(launched, isEmpty, reason: "A's checkout opened for B");
      expect(plans, hasLength(3), reason: "A's spinner was B's");
      expect(find.byType(SnackBar), findsNothing);
      expect(recordedAccountChange(), isTrue);
    });
  });

  group('Coach payments', () {
    Map<String, Object> body(Object? payout) => {
          'coach_payout': payout!,
          'client_source': 'marketplace',
          'status': 'paid',
          'created_at': '2026-01-01T00:00:00Z',
        };

    void coach(String uid, int cents) {
      server.answers['payments:$uid'] = (200, [body(cents)]);
      server.answers['stripe-connect:$uid'] = (200, {
        'connected': true,
        'charges_enabled': true,
        'payouts_enabled': true,
        'pending': cents * 2,
        'paid': cents * 3,
      });
    }

    Future<void> openAsA(WidgetTester t) async {
      coach(_a, 11100); // $111 lifetime, $222 pending, $333 completed
      await open(t, const CoachPaymentsScreen());
      await until(
          t,
          () => seen(find.text(r'$222')) && seen(find.text(r'$111')),
          "A's money");
    }

    void noneOfAs() {
      for (final s in [r'$111', r'$222', r'$333']) {
        expect(find.text(s), findsNothing, reason: "A's $s shown to B");
      }
    }

    testWidgets("A-19: B's revenue and balance failed: A's are not B's, and it "
        'is said and recorded', (t) async {
      await openAsA(t);
      server.answers['payments:$_b'] = _down;
      server.answers['stripe-connect:$_b'] = (200, {'connected': true});
      await signIn(t, _b);
      await until(t, () => seen(find.text('Finish setup')), "B's status");
      await until(t, () => server.count('payments', _b) >= 1, 'B asked');
      await settle(t);
      noneOfAs();
      expect(find.text("Couldn't load your revenue"), findsOneWidget);
      expect(origins(), contains('CoachPaymentsScreen.revenue'));
      noBackendText();
    });

    testWidgets("A-19: B's money pending: A's is not B's", (t) async {
      await openAsA(t);
      coach(_b, 4400);
      final gate = server.gates['payments:$_b'] = Completer();
      await signIn(t, _b);
      await until(t, () => seen(find.text(r'$88')), "B's balance");
      expect(find.text(r'$111'), findsNothing);
      expect(find.text('—'), findsWidgets, reason: 'unread is unknown');
      gate.complete();
      await until(t, () => seen(find.text(r'$44')), "B's revenue");
      noneOfAs();
    });

    testWidgets("A-19: a refresh A asked for lands after B's own read",
        (t) async {
      await openAsA(t);
      coach(_b, 4400);
      final gate = server.gates['payments:$_a'] = Completer();
      container(t).invalidate(coachRevenueProvider);
      await until(t, () => server.count('payments', _a) == 2, 'A refreshed');
      await signIn(t, _b);
      await until(t, () => seen(find.text(r'$44')), "B's revenue");
      gate.complete();
      await settle(t);
      noneOfAs();
      expect(find.text(r'$44'), findsWidgets);
    });

    testWidgets("A-19: B's Connect status failed: said, with Try again; none of "
        "A's", (t) async {
      await openAsA(t);
      server.answers['payments:$_b'] = _down;
      server.answers['stripe-connect:$_b'] = _down;
      await signIn(t, _b);
      await until(t, () => server.count('stripe-connect', _b) >= 2, 'B asked');
      await settle(t);
      noneOfAs();
      expect(find.text("Couldn't load your Stripe status"), findsOneWidget);
      expect(find.text('Payments active'), findsNothing);
      expect(origins(), contains('CoachPaymentsScreen.connectStatus'));
      coach(_b, 4400);
      await t.tap(find.text('Try again'));
      await until(t, () => seen(find.text('Payments active')), "B's status");
    });

    testWidgets('A-19: signed out, the figures go away', (t) async {
      await openAsA(t);
      server.answers['stripe-connect:anon'] = _down;
      await t.runAsync(signOut);
      await settle(t);
      noneOfAs();
    });

    testWidgets('control: a failed refresh by the same coach keeps the figures '
        'and says so', (t) async {
      await openAsA(t);
      server.answers['payments:$_a'] = _down;
      server.answers['stripe-connect:$_a'] = _down;
      container(t)
        ..invalidate(coachRevenueProvider)
        ..invalidate(coachBalanceProvider)
        ..invalidate(coachConnectStatusProvider);
      await until(
          t,
          () =>
              seen(find.text("Couldn't load your revenue")) &&
              seen(find.text("Couldn't load your payouts")) &&
              seen(find.text("Couldn't load your Stripe status")),
          'all three said');
      for (final s in [r'$111', r'$222', r'$333']) {
        expect(find.text(s), findsWidgets);
      }
      expect(find.text('Payments active'), findsOneWidget);
      expect(
          origins(),
          unorderedEquals([
            'CoachPaymentsScreen.revenue',
            'CoachPaymentsScreen.balance',
            'CoachPaymentsScreen.connectStatus',
          ]),
          reason: 'each failure once');
      noBackendText();
    });

    testWidgets('control: a token refresh neither re-reads nor drops a figure',
        (t) async {
      await openAsA(t);
      final before = server.log.length;
      await t.runAsync(refreshSession);
      await settle(t);
      expect(server.log.length, before);
      expect(find.text(r'$111'), findsWidgets);
    });

    testWidgets('control: a real zero is zero, not a failure', (t) async {
      server.answers['stripe-connect:$_a'] =
          (200, {'connected': false, 'pending': 0, 'paid': 0});
      await open(t, const CoachPaymentsScreen());
      await until(t, () => find.text(r'$0').evaluate().length == 6, 'zeros');
      expect(find.byType(SectionLoadFailure), findsNothing);
      expect(find.text('Not connected'), findsOneWidget);
      expect(reported, isEmpty);
    });

    testWidgets('a Stripe page that does not open is said', (t) async {
      await openAsA(t);
      server.answers['stripe-connect:$_a'] = (200, {'url': 'https://stripe/a'});
      launch = _Launch.throws;
      await t.tap(find.text('Manage Stripe account'));
      await until(
          t,
          () => seen(find.text(
              "Couldn't open Stripe — try again in a moment. If it keeps "
              'happening, contact support.')),
          'the failure');
      expect(origins(), ['PaymentService.connectStripeOnboard']);
    });

    testWidgets("A's failed onboarding is not said to B", (t) async {
      await openAsA(t);
      server.answers['stripe-connect:$_a'] = (200, {'url': 'https://stripe/a'});
      final gate = server.gates['stripe-connect:$_a'] = Completer();
      await t.tap(find.text('Manage Stripe account'));
      await until(t, () => server.bodies.last.contains('onboard'), 'A asked');
      server.answers['payments:$_b'] = _down;
      server.answers['stripe-connect:$_b'] = (200, {'connected': true});
      await signIn(t, _b);
      await until(t, () => seen(find.text('Finish setup')), "B's status");
      gate.complete();
      await settle(t);
      expect(launched, isEmpty, reason: "A's payout account opened for B");
      expect(find.byType(SnackBar), findsNothing);
      expect(recordedAccountChange(), isTrue);
    });
  });

  group('Manage subscription', () {
    const portal = 'Manage billing & payment method';
    const rel = {
      'coach_id': 'c-1',
      'status': 'active',
    };

    /// A and B share a coach; the coach's row reads the same for both.
    void shareCoach() {
      server.answers['coach_client_relationships'] = (200, [rel]);
      server.answers['public_profiles'] = (200, [
        {'id': 'c-1', 'first_name': 'Anna', 'last_name': 'Coach'}
      ]);
    }

    Future<void> tapStop(WidgetTester t) async {
      await until(t, () => seen(find.text('Stop')), "A's coach");
      await t.tap(find.text('Stop'));
      await until(
          t,
          () => seen(find.text('Stop working with Anna Coach?')),
          'the dialog');
      await settle(t);
    }

    Future<void> openAsA(WidgetTester t) async {
      server.answers['client_plan:$_a'] = (200, 'self_guided');
      server.answers['client_plan:$_b'] = (200, 'free');
      server.answers['subscriptions:$_a'] = (200, [
        {'id': 'sub-1', 'kind': 'self_guided', 'status': 'active'},
        {'id': 'sub-2', 'kind': 'ai_guided', 'status': 'active'},
      ]);
      await open(t, const ManageSubscriptionScreen());
      await until(t, () => seen(find.text('Self-Guided')), "A's plan");
      await settle(t);
    }

    testWidgets('a failed portal is not "No billing account yet"', (t) async {
      await openAsA(t);
      server.answers['create-portal-session'] = _down;
      await t.tap(find.text(portal));
      await until(t, () => seen(find.byType(SnackBar)), 'the failure');
      expect(find.textContaining('No billing account'), findsNothing);
      expect(
          find.text("Couldn't open billing — try again in a moment. If it "
              'keeps happening, contact support.'),
          findsOneWidget);
      expect(origins(), contains('PaymentService.openBillingPortal'));
      expect(find.text(portal), findsOneWidget, reason: 'can be tried again');
      noBackendText();
    });

    testWidgets('control: no billing account is said as that', (t) async {
      await openAsA(t);
      server.answers['create-portal-session'] =
          (400, {'error': 'No billing account yet'});
      await t.tap(find.text(portal));
      await until(
          t,
          () => seen(find.text(
              'No billing account yet. Subscribe to a plan first.')),
          'the answer');
      expect(reported, isEmpty);
    });

    testWidgets("E13: B signs in while A's portal link is made: nothing opens, "
        "nothing is said, B's button is not busy", (t) async {
      await openAsA(t);
      server.answers['create-portal-session:$_a'] =
          (200, {'url': 'https://stripe/a'});
      final gate = server.gates['create-portal-session:$_a'] = Completer();
      await t.tap(find.text(portal));
      await until(t, () => seen(find.text('Opening…')), 'A asked');
      await signIn(t, _b);
      await settle(t);
      final free = seen(find.text(portal));
      gate.complete();
      await settle(t);
      expect(launched, isEmpty, reason: "A's invoices opened for B");
      expect(free, isTrue, reason: "A's busy button was B's");
      expect(find.byType(SnackBar), findsNothing);
      expect(recordedAccountChange(), isTrue);
    });

    testWidgets("A-21: B's plan read failed: A's plan is not B's", (t) async {
      await openAsA(t);
      server.answers['client_plan:$_b'] = _down;
      await signIn(t, _b);
      await until(
          t,
          () => origins().contains('ManageSubscriptionScreen.clientPlan'),
          'failure');
      await settle(t);
      expect(find.text('Self-Guided'), findsNothing, reason: "A's plan for B");
      expect(find.byType(PlanLoadFailedNotice), findsOneWidget);
    });

    testWidgets("Cancel plan: B signs in over A's dialog: closed, nothing sent",
        (t) async {
      await openAsA(t);
      await t.tap(find.textContaining('Cancel').first);
      await until(t, () => seen(find.text('Switch to Free?')), 'the dialog');
      await settle(t);
      await signIn(t, _b);
      await settle(t);
      expect(find.text('Switch to Free?'), findsNothing);
      expect(ownedDialog, findsNothing, reason: 'its barrier too');
      expect(server.count('cancel-subscription'), 0);
    });

    testWidgets("Cancel plan: B signs in between A's two cancellations",
        (t) async {
      await openAsA(t);
      server.answers['cancel-subscription'] = (200, {'ok': true});
      final gate = server.gates['cancel-subscription:$_a'] = Completer();
      await t.tap(find.textContaining('Cancel').first);
      await until(t, () => seen(find.text('Switch to Free?')), 'the dialog');
      await settle(t);
      await t.tap(find.text('Switch to Free'));
      await until(t, () => server.count('cancel-subscription') == 1, 'one sent');
      await signIn(t, _b);
      gate.complete();
      await settle(t);
      expect(server.count('cancel-subscription', _b), 0);
      expect(server.count('cancel-subscription'), 1);
      expect(find.byType(SnackBar), findsNothing);
      expect(recordedAccountChange(), isTrue);
    });

    testWidgets("Stop coach: B (same coach) signs in over A's dialog: A's coach "
        "is not named to B and B's coaching is not ended", (t) async {
      shareCoach();
      await openAsA(t);
      await tapStop(t);
      await signIn(t, _b);
      await settle(t);
      expect(find.text('Stop working with Anna Coach?'), findsNothing);
      expect(ownedDialog, findsNothing, reason: 'its barrier too');
      expect(server.writes, isEmpty);
      expect(server.count('cancel-subscription'), 0);
    });

    // The caller's half only: cancelCoach's own steps after the switch are
    // FL-59d's, so what it sends is NOT asserted here (the lead runs that on the
    // combined head). The read succeeds and cancelCoach goes on to an outcome,
    // so there IS something to say — to A, not to B.
    for (final paid in [true, false]) {
      testWidgets("Stop coach, the caller's half (${paid ? 'paid' : 'unpaid'}): "
          "B signs in while A's is being ended: B is told nothing and it is "
          'recorded', (t) async {
        shareCoach();
        await openAsA(t);
        await tapStop(t);
        server.answers['subscriptions:$_a'] = (200, [
          if (paid) {'id': 's-a', 'current_period_end': '2027-03-03T00:00:00Z'},
        ]);
        server.answers['cancel-subscription'] =
            (200, {'ok': true, 'endsAt': '2027-03-03T00:00:00Z'});
        final gate = server.gates['subscriptions:$_a'] = Completer();
        final before = server.count('subscriptions', _a);
        await t.tap(find.text('Yes, stop'));
        await until(
            t, () => server.count('subscriptions', _a) > before, 'A asked');
        await signIn(t, _b);
        gate.complete();
        await settle(t);
        expect(find.byType(SnackBar), findsNothing);
        expect(find.textContaining('oaching'), findsNothing);
        expect(recordedAccountChange(), isTrue);
        // B's own first reads, and no more: A's outcome refreshes nothing of B's.
        expect(server.count('client_plan', _b), 1);
      });

      testWidgets("no-frame: Stop coach, the caller's half "
          "(${paid ? 'paid' : 'unpaid'}): the outcome lands before a frame",
          (t) async {
        shareCoach();
        await openAsA(t);
        await tapStop(t);
        server.answers['subscriptions:$_a'] = (200, [
          if (paid) {'id': 's-a', 'current_period_end': '2027-03-03T00:00:00Z'},
        ]);
        server.answers['cancel-subscription'] =
            (200, {'ok': true, 'endsAt': '2027-03-03T00:00:00Z'});
        final gate = server.gates['subscriptions:$_a'] = Completer();
        final before = server.count('subscriptions', _a);
        await t.tap(find.text('Yes, stop'));
        await until(
            t, () => server.count('subscriptions', _a) > before, 'A asked');
        await t.runAsync(() => signInAs(_b));
        gate.complete();
        await noFrames(t);
        await t.pump();
        expect(find.byType(SnackBar), findsNothing);
        await settle(t);
        expect(find.byType(SnackBar), findsNothing);
        expect(recordedAccountChange(), isTrue);
      });

      testWidgets('control: Stop coach by the same account '
          "(${paid ? 'paid' : 'unpaid'}) ends it and says so", (t) async {
        shareCoach();
        await openAsA(t);
        await tapStop(t);
        server.answers['subscriptions:$_a'] = (200, [
          if (paid) {'id': 's-a', 'current_period_end': '2027-03-03T12:00:00Z'},
        ]);
        server.answers['cancel-subscription:$_a'] =
            (200, {'ok': true, 'endsAt': '2027-03-03T12:00:00Z'});
        await t.runAsync(refreshSession);
        await settle(t);
        await t.tap(find.text('Yes, stop'));
        await until(t, () => seen(find.byType(SnackBar)), 'the outcome');
        expect(find.textContaining('until Mar 3'),
            paid ? findsOneWidget : findsNothing);
        expect(server.count('cancel-subscription', _a), paid ? 1 : 0);
        expect(
            server.writes,
            paid
                ? isEmpty
                : [
                    'PATCH coach_client_relationships:$_a',
                    'POST notifications:$_a',
                  ]);
        expect(reported, isEmpty);
      });
    }

    testWidgets("no-frame: A's coach row tapped after B signed in draws no dialog", (t) async {
      shareCoach();
      await openAsA(t);
      await until(t, () => seen(find.text('Stop')), "A's coach");
      server.answers['public_profiles:$_b'] = (200, [{'id': 'c-2', 'first_name': 'Bob', 'last_name': 'Other'}]);
      server.answers['coach_client_relationships:$_b'] = (200, [rel]);
      await t.runAsync(() => signInAs(_b)); // no pump
      await t.tap(find.text('Stop'));
      await t.pump();
      expect(ownedDialog, findsNothing, reason: 'not even put up');
      await t.pump(const Duration(milliseconds: 300));
      final drawn = seen(find.text('Stop working with Anna Coach?'));
      if (drawn) {
        await t.tap(find.text('Yes, stop'));
        await settle(t);
      }
      expect(drawn, isFalse);
      expect(recordedAccountChange(), isTrue);
    });
    testWidgets("no-frame: A's stop dialog confirmed after B signed in writes nothing", (t) async {
      shareCoach();
      await openAsA(t);
      await tapStop(t);
      await t.runAsync(() => signInAs(_b)); // no pump
      await t.tap(find.text('Yes, stop'));
      await settle(t);
      expect(server.writes, isEmpty);
      expect(recordedAccountChange(), isTrue);
    });
    testWidgets("no-frame: A's plan row cancelled after B signed in sends nothing", (t) async {
      await openAsA(t);
      await t.runAsync(() => signInAs(_b)); // no pump
      await t.tap(find.textContaining('Cancel').first);
      await t.pump();
      expect(ownedDialog, findsNothing, reason: 'not even put up');
      await t.pump(const Duration(milliseconds: 300));
      if (seen(find.text('Switch to Free'))) {
        await t.tap(find.text('Switch to Free'));
        await settle(t);
      }
      expect(server.count('cancel-subscription', _b), 0);
      expect(recordedAccountChange(), isTrue);
    });
    testWidgets('control: the same account ending coaching is told the outcome',
        (t) async {
      shareCoach();
      await openAsA(t);
      await tapStop(t);
      server.answers['subscriptions:$_a'] = _down;
      await t.runAsync(refreshSession);
      await settle(t);
      await t.tap(find.text('Yes, stop'));
      await until(t, () => seen(find.byType(SnackBar)), 'the outcome');
      expect(find.textContaining('Nothing was changed'), findsOneWidget);
    });
  });

  // ── rounds 2 and 3 ────────────────────────────────────────────────────────

  group('R3 the owner travels with the value (item 1)', () {
    final sources = <String, (String, FutureProvider<Object?>, Object?)>{
      'coachPlanTierProvider': ('coach_plan_tier', coachPlanTierProvider, 'growth'),
      'membershipTierProvider':
          ('active_membership', membershipTierProvider, 'ai_guided'),
      'mySubscriptionsProvider': ('subscriptions', mySubscriptionsProvider, [
        {'id': 'sub-A', 'kind': 'self_guided', 'status': 'active'}
      ]),
      'coachRevenueProvider': ('payments', coachRevenueProvider, const []),
      'coachBalanceProvider': ('stripe-connect', coachBalanceProvider, {'pending': 1}),
      'coachConnectStatusProvider':
          ('stripe-connect', coachConnectStatusProvider, {'connected': true}),
      'coachSubscriptionProvider': ('subscriptions', coachSubscriptionProvider('c'), null),
      'clientPlanProvider': ('client_plan', clientPlanProvider, 'ai_guided'),
    };

    Future<ProviderContainer> read(
        WidgetTester t, String name, ProviderBase<AsyncValue<Object?>> p) async {
      await t.runAsync(() => signInAs(_a));
      await t.pumpWidget(ProviderScope(
          child: MaterialApp(
              home: Consumer(builder: (_, ref, __) {
        ref.watch(p);
        return const SizedBox();
      }))));
      final c = container(t);
      await until(t, () => c.read(p).hasValue, "A's value");
      return c;
    }

    sources.forEach((name, s) {
      final (table, provider, answer) = s;
      testWidgets('$name: A → B and an invalidate before the change is flushed: '
          "a reload, never an AsyncData with A's value", (t) async {
        server.answers['$table:$_a'] = (200, answer);
        final c = await read(t, name, provider);
        server.answers['$table:$_b'] = (200, answer);
        server.gates['$table:$_b'] = Completer();
        await t.runAsync(() => signInAs(_b)); // no frame
        c.invalidate(provider);
        await t.pump();
        final now = c.read(provider);
        expect(now.isLoading, isTrue);
        expect(now, isNot(isA<AsyncData<Object?>>()), reason: '$now');
        server.gates['$table:$_b']!.complete();
        await until(t, () => !c.read(provider).isLoading, "B's answer");
      });

      testWidgets('$name: control — the same account invalidating (its token '
          'refreshed first) keeps its value meanwhile', (t) async {
        server.answers['$table:$_a'] = (200, answer);
        final c = await read(t, name, provider);
        await t.runAsync(refreshSession);
        await settle(t);
        server.gates['$table:$_a'] = Completer();
        c.invalidate(provider);
        await t.pump();
        expect(c.read(provider).isLoading, isTrue);
        expect(c.read(provider).hasValue, isTrue);
        server.gates['$table:$_a']!.complete();
        await until(t, () => !c.read(provider).isLoading, 'the refresh');
      });
    });

    testWidgets('Coach plan: no frame, then an invalidate; B pending, then B '
        'answers', (t) async {
      server.answers['coach_plan_tier:$_a'] = (200, 'growth');
      await open(t, const CoachPlanScreen());
      await until(t, () => seen(find.text('Current')), "A's plan");
      server.answers['coach_plan_tier:$_b'] = (200, 'elite');
      final gate = server.gates['coach_plan_tier:$_b'] = Completer();
      await t.runAsync(() => signInAs(_b)); // no frame
      container(t).invalidate(coachPlanTierProvider);
      await settle(t);
      expect(server.count('coach_plan_tier', _b), greaterThan(0));
      expect(find.text('Current'), findsNothing);
      expect(enabled(t, startsWith: 'Choose'), isEmpty);
      gate.complete();
      await until(t, () => seen(find.text('Current')), "B's plan");
      expect(find.text('Choose Elite'), findsNothing);
    });

    testWidgets('control: Coach plan, the same account, invalidate in flight '
        'keeps "Current"', (t) async {
      server.answers['coach_plan_tier:$_a'] = (200, 'growth');
      await open(t, const CoachPlanScreen());
      await until(t, () => seen(find.text('Current')), "A's plan");
      await t.runAsync(refreshSession);
      final gate = server.gates['coach_plan_tier:$_a'] = Completer();
      container(t).invalidate(coachPlanTierProvider);
      await settle(t);
      expect(server.count('coach_plan_tier', _a), 2, reason: 'premise');
      expect(find.text('Current'), findsOneWidget);
      expect(find.text('Choose Growth'), findsNothing);
      gate.complete();
      await settle(t);
      expect(find.text('Current'), findsOneWidget);
    });

    Future<void> manageAsA(WidgetTester t) async {
      server.answers['client_plan:$_a'] = (200, 'self_guided');
      server.answers['client_plan:$_b'] = (200, 'free');
      server.answers['subscriptions:$_a'] = (200, [
        {
          'id': 'sub-A',
          'kind': 'self_guided',
          'status': 'active',
          'current_period_end': '2027-03-03T12:00:00Z'
        }
      ]);
      await open(t, const ManageSubscriptionScreen());
      await until(
          t, () => seen(find.text('Self-Guided Membership')), "A's row");
    }

    testWidgets("Manage: no frame, then an invalidate, B pending: A's row is "
        'not drawn and there is nothing to cancel', (t) async {
      await manageAsA(t);
      server.answers['subscriptions:$_b'] = (200, const []);
      final gate = server.gates['subscriptions:$_b'] = Completer();
      await t.runAsync(() => signInAs(_b)); // no frame
      container(t).invalidate(mySubscriptionsProvider);
      await settle(t);
      expect(server.count('subscriptions', _b), greaterThan(0));
      expect(find.text('Self-Guided Membership'), findsNothing);
      expect(find.textContaining('Renews'), findsNothing);
      expect(find.textContaining('Cancel'), findsNothing);
      expect(server.count('cancel-subscription'), 0);
      gate.complete();
      await until(t, () => seen(find.textContaining('on the Free plan')),
          "B's own answer");
    });

    testWidgets('control: Manage, the same account, invalidate in flight keeps '
        'its row', (t) async {
      await manageAsA(t);
      final gate = server.gates['subscriptions:$_a'] = Completer();
      container(t).invalidate(mySubscriptionsProvider);
      await settle(t);
      expect(server.count('subscriptions', _a), 2, reason: 'premise');
      expect(find.text('Self-Guided Membership'), findsOneWidget);
      gate.complete();
      await settle(t);
      expect(find.text('Self-Guided Membership'), findsOneWidget);
    });

    testWidgets("Manage signed out: A's rows and coaches go away", (t) async {
      server.answers['coach_client_relationships:$_a'] = (200, [
        {'coach_id': 'c-1', 'status': 'active'}
      ]);
      server.answers['public_profiles:$_a'] = (200, [
        {'id': 'c-1', 'first_name': 'Anna', 'last_name': 'Coach'}
      ]);
      await manageAsA(t);
      await until(t, () => seen(find.text('Anna Coach')), "A's coach");
      server.answers['client_plan:anon'] = _down;
      await t.runAsync(signOut);
      await settle(t);
      expect(find.text('Self-Guided Membership'), findsNothing);
      expect(find.text('Anna Coach'), findsNothing);
      expect(find.text('Self-Guided'), findsNothing);
    });

    testWidgets("N-6: A's failure is not B's first state: B pending shows "
        'loading, not a failure', (t) async {
      server.answers['client_plan:$_a'] = (200, 'self_guided');
      server.answers['client_plan:$_b'] = (200, 'free');
      server.answers['subscriptions:$_a'] = _down;
      server.answers['coach_client_relationships:$_a'] = _down;
      await open(t, const ManageSubscriptionScreen());
      await until(
          t,
          () =>
              seen(find.text("Couldn't load your subscriptions")) &&
              seen(find.text("Couldn't load your coaches")),
          "A's failures");
      final subs = server.gates['subscriptions:$_b'] = Completer();
      final rels = server.gates['coach_client_relationships:$_b'] = Completer();
      await signIn(t, _b);
      await until(
          t,
          () =>
              server.count('subscriptions', _b) > 0 &&
              server.count('coach_client_relationships', _b) > 0,
          'B asked');
      await settle(t);
      expect(find.byType(SectionLoadFailure), findsNothing,
          reason: "A's failure was B's");
      expect(find.byType(CircularProgressIndicator), findsNWidgets(2));
      subs.complete();
      rels.complete();
      await until(t, () => seen(find.textContaining('not working with a coach')),
          "B's own answers");
    });

    testWidgets("control: B's own failure is B's", (t) async {
      server.answers['client_plan'] = (200, 'free');
      server.answers['subscriptions:$_b'] = _down;
      await open(t, const ManageSubscriptionScreen());
      await settle(t);
      await signIn(t, _b);
      await until(t, () => seen(find.text("Couldn't load your subscriptions")),
          "B's failure");
    });
  });

  group('R3 an action belongs to the account it was built for (items 2, 3)', () {
    const rel = {'coach_id': 'c-1', 'status': 'active'};

    void shareCoach() {
      server.answers['coach_client_relationships'] = (200, [rel]);
      server.answers['public_profiles'] = (200, [
        {'id': 'c-1', 'first_name': 'Anna', 'last_name': 'Coach'}
      ]);
    }

    Future<void> manage(WidgetTester t) async {
      server.answers['client_plan'] = (200, 'self_guided');
      server.answers['subscriptions'] = (200, [
        {'id': 'sub-1', 'kind': 'self_guided', 'status': 'active'},
        {'id': 'sub-2', 'kind': 'ai_guided', 'status': 'active'},
      ]);
      await open(t, const ManageSubscriptionScreen());
      await until(t, () => seen(find.text('Cancel')), "A's plan");
      await settle(t);
    }

    Future<void> plans(WidgetTester t) async {
      server.answers['client_plan'] = (200, 'self_guided');
      server.answers['subscriptions'] = (200, [
        {'id': 'sub-1', 'kind': 'self_guided', 'status': 'active'},
        {'id': 'sub-2', 'kind': 'ai_guided', 'status': 'active'},
      ]);
      await open(t, const UpgradeScreen());
      await until(t, () => seen(find.text('Current')), "A's plan");
    }

    void nothingSent() {
      expect(server.count('cancel-subscription'), 0);
      expect(server.count('update-subscription'), 0);
      expect(server.count('create-checkout'), 0);
      expect(server.writes, isEmpty);
      expect(launched, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    }

    testWidgets('no-frame: Cancel plan confirmed after B signed in sends '
        'nothing, recorded', (t) async {
      await manage(t);
      await t.tap(find.text('Cancel'));
      await until(t, () => seen(find.text('Switch to Free?')), 'the dialog');
      await settle(t);
      await t.runAsync(() => signInAs(_b)); // no frame
      await t.tap(find.text('Switch to Free'), warnIfMissed: false);
      await noFrames(t);
      await settle(t);
      nothingSent();
      expect(recordedAccountChange(), isTrue);
      expect(ownedDialog, findsNothing);
    });

    testWidgets('no-frame: Plans, Switch to Free confirmed after B signed in '
        'sends nothing, recorded', (t) async {
      await plans(t);
      await t.tap(find.text('Switch to Free'));
      await until(t, () => seen(find.text('Switch to Free?')), 'the dialog');
      await settle(t);
      await t.runAsync(() => signInAs(_b)); // no frame
      await t.tap(find.text('Switch to Free').last, warnIfMissed: false);
      await noFrames(t);
      await settle(t);
      nothingSent();
      expect(recordedAccountChange(), isTrue);
      expect(ownedDialog, findsNothing);
    });

    testWidgets("no-frame: Plans, A's subscriptions read lands after B signed "
        'in: no dialog, nothing sent, recorded', (t) async {
      await plans(t);
      final gate = server.gates['subscriptions:$_a'] = Completer();
      await t.tap(find.text('Switch to Free'));
      await until(t, () => server.count('subscriptions', _a) == 1, 'A asked');
      await t.runAsync(() => signInAs(_b)); // no frame
      gate.complete();
      await noFrames(t);
      await t.pump();
      expect(ownedDialog, findsNothing,
          reason: "A's question was put to B");
      expect(recordedAccountChange(), isTrue);
      await settle(t);
      nothingSent();
    });

    testWidgets("no-frame: Plans, A's subscriptions read FAILS after B signed "
        'in: B is told nothing', (t) async {
      await plans(t);
      server.answers['subscriptions:$_a'] = _down;
      final gate = server.gates['subscriptions:$_a'] = Completer();
      await t.tap(find.text('Switch to Free'));
      await until(t, () => server.count('subscriptions', _a) == 1, 'A asked');
      await t.runAsync(() => signInAs(_b)); // no frame
      gate.complete();
      await noFrames(t);
      await t.pump();
      expect(find.byType(SnackBar), findsNothing);
      await settle(t);
      nothingSent();
      expect(origins(), contains('UpgradeScreen.mySubscriptions'));
    });

    for (final (answer, what) in [
      ((200, {'needsCheckout': true}), 'needs_checkout'),
      ((200, {'ok': true}), 'changed'),
      (_down, 'failed'),
    ]) {
      testWidgets("no-frame: W26, A's plan change answers ($what) after B signed "
          'in: no checkout, nothing said, recorded', (t) async {
        await plans(t);
        server.answers['update-subscription:$_a'] = answer;
        server.answers['create-checkout'] = (200, {'url': 'https://stripe/x'});
        final gate = server.gates['update-subscription:$_a'] = Completer();
        await t.tap(find.text('Upgrade to AI-Guided'));
        await until(
            t, () => server.count('update-subscription') == 1, 'A asked');
        await t.runAsync(() => signInAs(_b)); // no frame
        gate.complete();
        await noFrames(t);
        expect(server.count('create-checkout'), 0);
        await t.pump();
        expect(find.byType(SnackBar), findsNothing);
        await settle(t);
        expect(server.count('create-checkout'), 0);
        expect(launched, isEmpty);
        expect(recordedAccountChange(), isTrue);
      });
    }

    testWidgets('W26: A signs out while the plan change runs: no checkout',
        (t) async {
      await plans(t);
      server.answers['update-subscription:$_a'] = (200, {'needsCheckout': true});
      final gate = server.gates['update-subscription:$_a'] = Completer();
      await t.tap(find.text('Upgrade to AI-Guided'));
      await until(t, () => server.count('update-subscription') == 1, 'A asked');
      await t.runAsync(signOut);
      gate.complete();
      await settle(t);
      expect(server.count('create-checkout'), 0);
      expect(recordedAccountChange(), isTrue);
    });

    testWidgets("no-frame: A's billing button tapped after B signed in asks for "
        'nothing', (t) async {
      await manage(t);
      server.answers['create-portal-session'] = (200, {'url': 'https://stripe/b'});
      await t.runAsync(() => signInAs(_b)); // no frame
      await t.tap(find.text('Manage billing & payment method'));
      await noFrames(t);
      await settle(t);
      expect(server.count('create-portal-session'), 0);
      expect(launched, isEmpty);
      expect(recordedAccountChange(), isTrue);
    });

    testWidgets("no-frame: A's portal failure is not said to B", (t) async {
      await manage(t);
      server.answers['create-portal-session:$_a'] = _down;
      final gate = server.gates['create-portal-session:$_a'] = Completer();
      await t.tap(find.text('Manage billing & payment method'));
      await until(
          t, () => server.count('create-portal-session') == 1, 'A asked');
      await t.runAsync(() => signInAs(_b)); // no frame
      gate.complete();
      await noFrames(t);
      await t.pump();
      expect(find.byType(SnackBar), findsNothing);
      expect(origins(), contains('PaymentService.openBillingPortal'));
      await settle(t);
      expect(find.text('Manage billing & payment method'), findsOneWidget);
    });

    testWidgets("B's own portal request stays busy when A's answer lands",
        (t) async {
      await manage(t);
      final a = server.gates['create-portal-session:$_a'] = Completer();
      final b = server.gates['create-portal-session:$_b'] = Completer();
      server.answers['create-portal-session:$_b'] = (200, {'url': 'https://stripe/b'});
      await t.tap(find.text('Manage billing & payment method'));
      await until(
          t, () => server.count('create-portal-session', _a) == 1, 'A asked');
      await signIn(t, _b);
      await until(t, () => seen(find.text('Cancel')), "B's plan");
      await t.tap(find.text('Manage billing & payment method'));
      await until(
          t, () => server.count('create-portal-session', _b) == 1, 'B asked');
      a.complete();
      await settle(t);
      expect(find.text('Opening…'), findsOneWidget);
      b.complete();
      await until(t, () => launched.isNotEmpty, "B's page");
      await settle(t);
      expect(launched, ['https://stripe/b']);
      expect(find.text('Manage billing & payment method'), findsOneWidget);
    });

    testWidgets('no-frame: portal, A → B → A: the button is not stuck on its '
        'spinner', (t) async {
      await manage(t);
      server.answers['create-portal-session:$_a'] = (200, {'url': 'https://stripe/a'});
      final gate = server.gates['create-portal-session:$_a'] = Completer();
      await t.tap(find.text('Manage billing & payment method'));
      await until(t, () => seen(find.text('Opening…')), 'A asked');
      await t.runAsync(() => signInAs(_b));
      gate.complete();
      await noFrames(t);
      expect(launched, isEmpty);
      await t.runAsync(() => signInAs(_a));
      await settle(t);
      expect(find.text('Opening…'), findsNothing);
    });

    // N-7
    testWidgets('no-frame: A → B → A around a plan change: the card is not '
        'stuck on its spinner', (t) async {
      await plans(t);
      server.answers['update-subscription:$_a'] = (200, {'ok': true});
      final gate = server.gates['update-subscription:$_a'] = Completer();
      await t.tap(find.text('Upgrade to AI-Guided'));
      await until(t, () => server.count('update-subscription') == 1, 'A asked');
      await t.runAsync(() => signInAs(_b));
      gate.complete();
      await noFrames(t);
      await t.runAsync(() => signInAs(_a));
      await settle(t);
      expect(find.text('Current'), findsOneWidget);
      expect(enabled(t, startsWith: 'Upgrade to AI-Guided'), isNotEmpty);
    });

    testWidgets('no-frame: A → B → A around Switch to Free: the card is not '
        'stuck on its spinner', (t) async {
      await plans(t);
      server.answers['cancel-subscription'] = (200, {'ok': true});
      final gate = server.gates['cancel-subscription:$_a'] = Completer();
      await t.tap(find.text('Switch to Free'));
      await until(t, () => seen(find.text('Switch to Free?')), 'the dialog');
      await settle(t);
      await t.tap(find.text('Switch to Free').last);
      await until(t, () => server.count('cancel-subscription') == 1, 'one sent');
      await t.runAsync(() => signInAs(_b));
      gate.complete();
      await noFrames(t);
      expect(server.count('cancel-subscription'), 1);
      await t.runAsync(() => signInAs(_a));
      await settle(t);
      expect(find.text('Current'), findsOneWidget);
      expect(enabled(t, startsWith: 'Switch to Free'), isNotEmpty);
    });

    // Same-account controls of the five probes.
    testWidgets('control: the same account (its token refreshed) changes its '
        'plan', (t) async {
      await plans(t);
      server.answers['update-subscription:$_a'] = (200, {'ok': true});
      await t.runAsync(refreshSession);
      await t.tap(find.text('Upgrade to AI-Guided'));
      await until(
          t, () => seen(find.text('Your plan is now AI-Guided.')), 'said');
      expect(server.bodies, ['update-subscription:$_a {"newKind":"ai_guided"}']);
      expect(reported, isEmpty);
    });

    testWidgets('control: the same account (its token refreshed) cancels its '
        'plan from its row', (t) async {
      await manage(t);
      server.answers['cancel-subscription:$_a'] = (200, {'ok': true});
      await t.runAsync(refreshSession);
      await t.tap(find.text('Cancel'));
      await until(t, () => seen(find.text('Switch to Free?')), 'the dialog');
      await settle(t);
      await t.tap(find.text('Switch to Free'));
      await until(t, () => seen(find.text('Switched to the Free plan.')), 'said');
      expect(server.bodies.toSet(), {
        'cancel-subscription:$_a {"subscriptionId":"sub-1"}',
        'cancel-subscription:$_a {"subscriptionId":"sub-2"}',
      });
      expect(reported, isEmpty);
    });

    testWidgets('control: the same account (its token refreshed) is asked about '
        'its coach row and can keep it', (t) async {
      shareCoach();
      await manage(t);
      await until(t, () => seen(find.text('Stop')), "A's coach");
      await t.runAsync(refreshSession);
      await t.tap(find.text('Stop'));
      await until(t, () => seen(find.text('Stop working with Anna Coach?')),
          'the dialog');
      await settle(t);
      await t.tap(find.text('Keep coach'));
      await settle(t);
      expect(find.text('Stop working with Anna Coach?'), findsNothing);
      nothingSent();
      expect(reported, isEmpty);
    });

    testWidgets('control: the same account (its token refreshed) buys a coach '
        'plan', (t) async {
      server.answers['coach_plan_tier'] = (200, null);
      server.answers['create-checkout:$_a'] = (200, {'url': 'https://stripe/a'});
      await open(t, const CoachPlanScreen());
      await until(t, () => enabled(t).length == 3, 'plans');
      await t.runAsync(refreshSession);
      await t.tap(find.text('Choose Starter'));
      await until(t, () => launched.isNotEmpty, 'the page');
      expect(launched, ['https://stripe/a']);
      await settle(t);
      expect(reported, isEmpty);
      expect(server.count('coach_plan_tier', _a), 2, reason: 're-read after');
    });

    testWidgets("no-frame: A's checkout that ends after B signed in does not "
        "re-read B's plan", (t) async {
      server.answers['coach_plan_tier'] = (200, null);
      server.answers['create-checkout:$_a'] = (200, {'url': 'https://stripe/a'});
      await open(t, const CoachPlanScreen());
      await until(t, () => enabled(t).length == 3, 'plans');
      final gate = server.gates['create-checkout:$_a'] = Completer();
      await t.tap(find.text('Choose Starter'));
      await until(t, () => server.count('create-checkout') == 1, 'A asked');
      await t.runAsync(() => signInAs(_b)); // no frame
      gate.complete();
      await noFrames(t);
      await settle(t);
      expect(server.count('coach_plan_tier', _b), 1, reason: "B's own read only");
      expect(launched, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('R3 readers of a held plan or coach (item 5, A-21)', () {
    void member(String uid, {String role = 'client'}) =>
        server.answers['user_profiles:$uid'] = (200, {'id': uid, 'role': role});

    Future<void> gate(WidgetTester t, String planOfA) async {
      member(_a);
      member(_b);
      server.answers['client_plan:$_a'] = (200, planOfA);
      await open(
          t,
          const PaywallGate(
              required: ClientPlan.aiGuided,
              featureName: 'AI coach',
              child: Text('GATED')));
      await until(
          t,
          () => seen(find.text('GATED')) || seen(find.byType(PaywallLocked)),
          "A's gate");
    }

    testWidgets("PaywallGate: A's paid plan does not open it for B while B's "
        'read is pending; a genuine Free locks it', (t) async {
      await gate(t, 'ai_guided');
      expect(find.text('GATED'), findsOneWidget, reason: 'premise');
      server.answers['client_plan:$_b'] = (200, 'free');
      final g = server.gates['client_plan:$_b'] = Completer();
      await signIn(t, _b);
      await until(t, () => server.count('client_plan', _b) > 0, 'B asked');
      await settle(t);
      expect(find.text('GATED'), findsNothing, reason: "A's plan opened it");
      expect(find.byType(PaywallLocked), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      g.complete();
      await until(t, () => seen(find.byType(PaywallLocked)), "B's Free");
      expect(find.text('GATED'), findsNothing);
    });

    testWidgets("PaywallGate: A's Free does not lock B whose read failed: the "
        'gate fails open, as it does for anyone', (t) async {
      await gate(t, 'free');
      expect(find.byType(PaywallLocked), findsOneWidget, reason: 'premise');
      server.answers['client_plan:$_b'] = _down;
      await signIn(t, _b);
      await until(t, () => seen(find.text('GATED')), 'fail open');
      expect(find.byType(PaywallLocked), findsNothing);
    });

    testWidgets("PaywallGate: A's FAILURE does not open it for B", (t) async {
      member(_a);
      member(_b);
      server.answers['client_plan:$_a'] = _down;
      await open(
          t,
          const PaywallGate(
              required: ClientPlan.aiGuided,
              featureName: 'AI coach',
              child: Text('GATED')));
      await until(t, () => seen(find.text('GATED')), 'A: fail open');
      server.answers['client_plan:$_b'] = (200, 'free');
      final g = server.gates['client_plan:$_b'] = Completer();
      await signIn(t, _b);
      await until(t, () => server.count('client_plan', _b) > 0, 'B asked');
      await settle(t);
      expect(find.text('GATED'), findsNothing);
      g.complete();
      await until(t, () => seen(find.byType(PaywallLocked)), "B's Free");
    });

    testWidgets('PaywallGate: no frame, then an invalidate', (t) async {
      await gate(t, 'ai_guided');
      server.answers['client_plan:$_b'] = (200, 'free');
      final g = server.gates['client_plan:$_b'] = Completer();
      await t.runAsync(() => signInAs(_b)); // no frame
      container(t).invalidate(clientPlanProvider);
      await settle(t);
      expect(find.text('GATED'), findsNothing);
      g.complete();
      await until(t, () => seen(find.byType(PaywallLocked)), "B's Free");
    });

    testWidgets('control: PaywallGate keeps the same account through a token '
        'refresh, a pending refresh and a failed one', (t) async {
      await gate(t, 'ai_guided');
      await t.runAsync(refreshSession);
      await settle(t);
      expect(find.text('GATED'), findsOneWidget);
      server.answers['client_plan:$_a'] = _down;
      final g = server.gates['client_plan:$_a'] = Completer();
      final before = server.count('client_plan', _a);
      container(t).invalidate(clientPlanProvider);
      await until(t, () => server.count('client_plan', _a) > before, 're-read');
      await settle(t);
      expect(find.text('GATED'), findsOneWidget, reason: 'pending');
      g.complete();
      await settle(t);
      expect(find.text('GATED'), findsOneWidget, reason: 'failed');
    });

    testWidgets('control: PaywallGate keeps a locked account locked through a '
        'failed refresh', (t) async {
      await gate(t, 'free');
      server.answers['client_plan:$_a'] = _down;
      final before = server.count('client_plan', _a);
      container(t).invalidate(clientPlanProvider);
      await until(t, () => server.count('client_plan', _a) > before, 're-read');
      await settle(t);
      expect(find.byType(PaywallLocked), findsOneWidget);
    });

    testWidgets("Subscription: A's tier is not B's — pending, then failed, with "
        'Try again', (t) async {
      server.answers['client_plan:$_a'] = (200, 'coach_guided');
      await open(t, const SubscriptionScreen());
      await until(t, () => seen(find.text('CURRENT')), "A's tier");
      server.answers['client_plan:$_b'] = _down;
      final g = server.gates['client_plan:$_b'] = Completer();
      await signIn(t, _b);
      await until(t, () => server.count('client_plan', _b) > 0, 'B asked');
      await settle(t);
      expect(find.text('CURRENT'), findsNothing, reason: 'pending');
      expect(find.text('…'), findsOneWidget);
      g.complete();
      await until(t, () => seen(find.byType(PlanLoadFailedNotice)), 'failure');
      expect(find.text('CURRENT'), findsNothing, reason: 'failed');
      expect(find.text('—'), findsOneWidget);
      server.answers['client_plan:$_b'] = (200, 'free');
      await t.tap(find.text('Try again'));
      await until(t, () => seen(find.text('CURRENT')), "B's own");
      expect(find.text('Basic'), findsWidgets, reason: 'a genuine Free');
    });

    testWidgets('control: Subscription keeps the tier through a token refresh '
        'and a failed refresh by the same account', (t) async {
      server.answers['client_plan:$_a'] = (200, 'coach_guided');
      await open(t, const SubscriptionScreen());
      await until(t, () => seen(find.text('CURRENT')), "A's tier");
      await t.runAsync(refreshSession);
      await settle(t);
      server.answers['client_plan:$_a'] = _down;
      final before = server.count('client_plan', _a);
      container(t).invalidate(clientPlanProvider);
      await until(t, () => server.count('client_plan', _a) > before, 're-read');
      await settle(t);
      expect(find.text('CURRENT'), findsOneWidget);
    });

    for (final failed in [false, true]) {
      testWidgets("Payment result: A's coach is not B's "
          "(${failed ? 'failed' : 'pending'})", (t) async {
        server.answers['coach_client_relationships:$_a'] =
            (200, {'coach_id': 'c-a', 'status': 'active'});
        server.answers['public_profiles:$_a'] =
            (200, {'id': 'c-a', 'first_name': 'Anna', 'last_name': 'Coach'});
        await open(t, const PaymentResultScreen(success: true));
        await until(
            t, () => seen(find.text('Book your sessions')), "A's coach");
        if (failed) {
          server.answers['coach_client_relationships:$_b'] = _down;
        } else {
          server.gates['coach_client_relationships:$_b'] = Completer();
        }
        await signIn(t, _b);
        await until(t, () => server.count('coach_client_relationships', _b) > 0,
            'B asked');
        await settle(t);
        expect(find.text('Book your sessions'), findsNothing,
            reason: "A's coach sent B to book");
        expect(find.text('Continue'), findsOneWidget);
        // The screen's own 2 s re-read, now B's.
        await t.pump(const Duration(seconds: 3));
        await settle(t);
        expect(find.text('Book your sessions'), findsNothing);
        server.gates['coach_client_relationships:$_b']?.complete();
        await settle(t);
      });
    }

    testWidgets('control: Payment result keeps the same account\'s coach through '
        'its re-read and a failed one', (t) async {
      server.answers['coach_client_relationships:$_a'] =
          (200, {'coach_id': 'c-a', 'status': 'active'});
      server.answers['public_profiles:$_a'] =
          (200, {'id': 'c-a', 'first_name': 'Anna', 'last_name': 'Coach'});
      await open(t, const PaymentResultScreen(success: true));
      await until(t, () => seen(find.text('Book your sessions')), "A's coach");
      server.answers['coach_client_relationships:$_a'] = _down;
      await t.pump(const Duration(seconds: 3));
      await settle(t);
      expect(server.count('coach_client_relationships', _a), 2,
          reason: 'premise: re-read');
      expect(find.text('Book your sessions'), findsOneWidget);
      expect(origins(), contains('PaymentResultScreen.assignedCoach'));
    });
  });

  group('R3 sheets and SnackBars leave with their account (item 6)', () {
    const sheet = "Anna Coach's Packages";
    const said = 'Your plan is now AI-Guided.';

    Future<void> openPlans(WidgetTester t, {String plan = 'coach_guided'}) async {
      for (final uid in [_a, _b]) {
        server.answers['client_plan:$uid'] = (200, plan);
      }
      server.answers['coach_client_relationships:$_a'] =
          (200, {'coach_id': 'c-a', 'status': 'active'});
      server.answers['public_profiles:$_a'] =
          (200, {'id': 'c-a', 'first_name': 'Anna', 'last_name': 'Coach'});
      await open(t, const UpgradeScreen());
      await until(t, () => seen(find.text('Current')), "A's plan");
    }

    final button = find.text("View Anna Coach's packages");

    Future<void> openSheet(WidgetTester t) async {
      await openPlans(t);
      await until(t, () => seen(button), "A's coach");
      await t.tap(button);
      await until(t, () => seen(find.text(sheet)), 'the sheet');
      await settle(t);
    }

    testWidgets('the packages sheet closes when B signs in', (t) async {
      await openSheet(t);
      await t.runAsync(() => signInAs(_b));
      await t.pump(); // the very next frame
      expect(find.text(sheet), findsNothing);
      await settle(t);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Current'), findsOneWidget, reason: 'Plans is still there');
    });

    testWidgets('the packages sheet closes on sign-out', (t) async {
      await openSheet(t);
      server.answers['client_plan:anon'] = _down;
      await t.runAsync(signOut);
      await t.pump();
      expect(find.text(sheet), findsNothing);
      await settle(t);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('the packages sheet closes even when Plans is gone from under '
        'it', (t) async {
      await openSheet(t);
      final plansPage =
          t.element(find.byType(UpgradeScreen, skipOffstage: false));
      Navigator.of(plansPage).replace(
          oldRoute: ModalRoute.of(plansPage)!,
          newRoute: MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('elsewhere'))));
      await settle(t);
      expect(find.byType(UpgradeScreen, skipOffstage: false), findsNothing,
          reason: 'premise');
      expect(find.text(sheet), findsOneWidget, reason: 'premise: still up');
      await t.runAsync(() => signInAs(_b));
      await settle(t);
      expect(find.text(sheet), findsNothing);
      expect(find.text('elsewhere'), findsOneWidget);
    });

    testWidgets('no-frame: pushed, then B signs in: never drawn', (t) async {
      await openPlans(t);
      await until(t, () => seen(button), "A's coach");
      await t.tap(button); // no frame
      await t.runAsync(() => signInAs(_b));
      await t.pump();
      expect(find.text(sheet), findsNothing);
      await settle(t);
      expect(find.text(sheet), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      expect(server.count('coach_packages', _b), 0, reason: 'read as B');
    });

    testWidgets("no-frame: A's packages button tapped after B signed in opens "
        'nothing, recorded', (t) async {
      await openPlans(t);
      await until(t, () => seen(button), "A's coach");
      await t.runAsync(() => signInAs(_b)); // no frame
      await t.tap(button);
      await settle(t);
      expect(find.text(sheet), findsNothing);
      expect(recordedAccountChange(), isTrue);
    });

    testWidgets('control: a token refresh keeps the sheet; swiping it away works '
        'and it can be opened again', (t) async {
      await openSheet(t);
      await t.runAsync(refreshSession);
      await settle(t);
      expect(find.text(sheet), findsOneWidget);
      await t.tapAt(const Offset(350, 40)); // the barrier
      await settle(t);
      expect(find.text(sheet), findsNothing);
      await t.tap(button);
      await until(t, () => seen(find.text(sheet)), 'the sheet again');
      expect(reported, isEmpty);
    });

    Future<void> say(WidgetTester t) async {
      await openPlans(t, plan: 'self_guided');
      server.answers['update-subscription:$_a'] = (200, {'ok': true});
      await t.tap(find.text('Upgrade to AI-Guided'));
      await until(t, () => seen(find.text(said)), 'said to A');
      await settle(t);
      expect(find.text(said), findsOneWidget, reason: 'premise: still up');
    }

    testWidgets("A's plan-change SnackBar is gone at B's first frame", (t) async {
      await say(t);
      await t.runAsync(() => signInAs(_b));
      await t.pump();
      expect(find.text(said), findsNothing);
      await settle(t);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets("A's plan-change SnackBar is gone when A signs out and Plans "
        'was already left', (t) async {
      await say(t);
      final nav = Navigator.of(t.element(find.byType(UpgradeScreen)));
      nav.pushReplacement(MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('elsewhere'))));
      await settle(t);
      expect(find.byType(UpgradeScreen), findsNothing);
      expect(find.text(said), findsOneWidget, reason: 'premise: it follows');
      await t.runAsync(signOut);
      await t.pump();
      expect(find.text(said), findsNothing);
    });

    testWidgets('no-frame: shown, then B signs in: never drawn', (t) async {
      await openPlans(t, plan: 'self_guided');
      server.answers['update-subscription:$_a'] = (200, {'ok': true});
      await t.tap(find.text('Upgrade to AI-Guided'));
      await until(t, () => server.count('update-subscription') == 1, 'asked');
      await noFrames(t); // the answer is in; nothing drawn since
      await t.runAsync(() => signInAs(_b));
      await t.pump();
      expect(find.text(said), findsNothing);
      await settle(t);
      expect(find.text(said), findsNothing);
    });

    testWidgets("A's end-coaching SnackBar is gone at B's first frame",
        (t) async {
      server.answers['client_plan'] = (200, 'coach_guided');
      server.answers['coach_client_relationships'] = (200, [
        {'coach_id': 'c-1', 'status': 'active'}
      ]);
      server.answers['public_profiles'] = (200, [
        {'id': 'c-1', 'first_name': 'Anna', 'last_name': 'Coach'}
      ]);
      await open(t, const ManageSubscriptionScreen());
      await until(t, () => seen(find.text('Stop')), "A's coach");
      await t.tap(find.text('Stop'));
      await until(t, () => seen(find.text('Yes, stop')), 'the dialog');
      await settle(t);
      await t.tap(find.text('Yes, stop'));
      await until(t, () => seen(find.textContaining('Coaching ended')), 'said');
      await settle(t);
      await t.runAsync(() => signInAs(_b));
      await t.pump();
      expect(find.textContaining('Coaching ended'), findsNothing);
    });

    testWidgets('control: a token refresh keeps the SnackBar, and it leaves on '
        'its own', (t) async {
      await say(t);
      await t.runAsync(refreshSession);
      await t.pump();
      expect(find.text(said), findsOneWidget);
      await t.pump(const Duration(seconds: 5));
      await settle(t);
      expect(find.text(said), findsNothing);
    });
  });

  group('R3 what could not be confirmed is not said to have failed (item 7)', () {
    const plans = [
      {'id': 'sub-1', 'kind': 'self_guided', 'status': 'active'},
    ];

    Future<void> openPlans(WidgetTester t) async {
      server.answers['client_plan:$_a'] = (200, 'self_guided');
      server.answers['subscriptions:$_a'] = (200, plans);
      await open(t, const UpgradeScreen());
      await until(t, () => seen(find.text('Current')), "A's plan");
    }

    Future<void> openManage(WidgetTester t) async {
      server.answers['client_plan:$_a'] = (200, 'self_guided');
      server.answers['subscriptions:$_a'] = (200, plans);
      server.answers['coach_client_relationships'] = (200, [
        {'coach_id': 'c-1', 'status': 'active'}
      ]);
      server.answers['public_profiles'] = (200, [
        {'id': 'c-1', 'first_name': 'Anna', 'last_name': 'Coach'}
      ]);
      await open(t, const ManageSubscriptionScreen());
      await until(t,
          () => seen(find.text('Cancel')) && seen(find.text('Stop')), 'rows');
    }

    Future<void> outcome(WidgetTester t, String text) async {
      await until(t, () => seen(find.byType(SnackBar)), 'the outcome');
      final shown = t.widgetList<Text>(find.descendant(
          of: find.byType(SnackBar), matching: find.byType(Text)));
      expect(shown.map((w) => w.data), [text]);
      noBackendText();
    }

    const unsurePlan = "Couldn't confirm your plan change — check your plan "
        'before trying again.';
    const unsureCancel = "Couldn't confirm the cancellation — check your plan "
        'before trying again.';
    const unsureEnd = "Couldn't confirm that coaching ended — check your "
        'coaches before trying again.';

    for (final (what, setUpAnswer, text) in <(String, void Function(), String)>[
      ('the connection is lost', () => server.lost.add('update-subscription:$_a'), unsurePlan),
      ('the server faults', () => server.answers['update-subscription:$_a'] = _down, unsurePlan),
      (
        'the server refuses (4xx)',
        () => server.answers['update-subscription:$_a'] =
            (400, {'error': 'SECRET Unknown membership tier'}),
        "Couldn't change your plan. Try again."
      ),
      (
        'the server says it could not read the membership',
        () => server.answers['update-subscription:$_a'] =
            (503, {'error': 'Could not read your membership'}),
        "Couldn't change your plan. Try again."
      ),
    ]) {
      testWidgets('plan change: $what', (t) async {
        await openPlans(t);
        setUpAnswer();
        final before = server.count('client_plan', _a);
        await t.tap(find.text('Upgrade to AI-Guided'));
        await outcome(t, text);
        await settle(t);
        expect(server.count('client_plan', _a), greaterThan(before),
            reason: 'the plan is re-read, to check');
        expect(server.count('create-checkout'), 0);
        expect(origins(), contains('PaymentService.changeMembership'));
      });
    }

    for (final (what, setUpAnswer, text) in <(String, void Function(), String)>[
      ('the connection is lost', () => server.lost.add('cancel-subscription:$_a'), unsureCancel),
      ('the server faults', () => server.answers['cancel-subscription:$_a'] = _down, unsureCancel),
      (
        'the server refuses (4xx)',
        () => server.answers['cancel-subscription:$_a'] = (404, {'error': 'x'}),
        'Could not cancel. Try again.'
      ),
      (
        'Stripe refused and nothing was changed',
        () => server.answers['cancel-subscription:$_a'] =
            (502, {'error': 'stripe_cancel_failed'}),
        'Could not cancel. Try again.'
      ),
    ]) {
      testWidgets('Switch to Free on Plans: $what', (t) async {
        await openPlans(t);
        setUpAnswer();
        await t.tap(find.text('Switch to Free'));
        await until(t, () => seen(find.text('Switch to Free?')), 'the dialog');
        await settle(t);
        await t.tap(find.text('Switch to Free').last);
        await outcome(t, text);
      });

      testWidgets('Cancel on Manage: $what', (t) async {
        await openManage(t);
        setUpAnswer();
        await t.tap(find.text('Cancel'));
        await until(t, () => seen(find.text('Switch to Free?')), 'the dialog');
        await settle(t);
        await t.tap(find.text('Switch to Free'));
        await outcome(t, text);
      });

      testWidgets('End coaching (paid): $what', (t) async {
        await openManage(t);
        setUpAnswer();
        await t.tap(find.text('Stop'));
        await until(t, () => seen(find.text('Yes, stop')), 'the dialog');
        await settle(t);
        await t.tap(find.text('Yes, stop'));
        await outcome(
            t,
            text == unsureCancel
                ? unsureEnd
                : 'Could not end coaching. Nothing was changed. Try again.');
        expect(origins(), contains('ManageSubscriptionScreen.stopCoach'));
      });
    }

    // Round 4: the ONE write of an unpaid Stop. A gateway that gave up waiting
    // does not know whether it landed; the database's own refusal does.
    for (final (what, answer, text) in <(String, (int, Object?), String)>[
      ('the gateway gives up (524)', (524, 'error code: 524'), unsureEnd),
      ('a bare 500', (500, 'Internal Server Error'), unsureEnd),
      ('a bare 503', (503, {'message': 'offline'}), unsureEnd),
      // Round 5: the connection went during the request, or the commit's
      // completion is unknown — the database cannot say nothing was changed.
      (
        'the connection is lost during the request (PGRST001)',
        (503, {'message': 'lost', 'code': 'PGRST001'}),
        unsureEnd
      ),
      (
        'the commit\'s completion is unknown (40003)',
        (500, {'message': 'unknown', 'code': '40003'}),
        unsureEnd
      ),
      (
        'control: no connection to the database at all (PGRST000)',
        (503, {'message': 'down', 'code': 'PGRST000'}),
        'Could not end coaching. Nothing was changed. Try again.'
      ),
      (
        'control: the database refuses',
        (403, {'message': 'SECRET denied', 'code': '42501'}),
        'Could not end coaching. Nothing was changed. Try again.'
      ),
    ]) {
      testWidgets('End coaching (unpaid): $what', (t) async {
        await openManage(t);
        server.answers['subscriptions:$_a'] = (200, const []);
        server.answers['PATCH coach_client_relationships:$_a'] = answer;
        final before = server.count('coach_client_relationships', _a);
        await t.tap(find.text('Stop'));
        await until(t, () => seen(find.text('Yes, stop')), 'the dialog');
        await settle(t);
        await t.tap(find.text('Yes, stop'));
        await outcome(t, text);
        expect(server.writes, ['PATCH coach_client_relationships:$_a'],
            reason: 'asked once, and the coach is told nothing');
        expect(server.count('cancel-subscription'), 0, reason: 'unpaid');
        expect(origins(), contains('ManageSubscriptionScreen.stopCoach'));
        await settle(t);
        expect(server.count('coach_client_relationships', _a),
            greaterThan(before + 1), reason: 'the coaches are re-read, to check');
      });
    }

    // What the screen cannot tell apart: cancelCoach's first READ lost behind a
    // gateway changed nothing, but its error is the one a lost write gives, so
    // it is not said to have changed nothing (precision for FL-59d's cancelCoach).
    testWidgets('End coaching: the subscriptions read lost behind a gateway '
        '(500, no code) is not confirmed, and nothing is written', (t) async {
      await openManage(t);
      server.answers['GET subscriptions:$_a'] = (500, {'message': 'offline'});
      await t.tap(find.text('Stop'));
      await until(t, () => seen(find.text('Yes, stop')), 'the dialog');
      await settle(t);
      await t.tap(find.text('Yes, stop'));
      await outcome(t, unsureEnd);
      expect(server.writes, isEmpty);
      expect(server.count('cancel-subscription'), 0);
    });

    testWidgets('Plans says a failed refresh of the plan it still shows; '
        'choices stay enabled; Try again clears it', (t) async {
      await openPlans(t);
      server.answers['client_plan:$_a'] = _down;
      container(t).invalidate(clientPlanProvider);
      await until(t, () => seen(find.byType(PlanLoadFailedNotice)), 'the notice');
      expect(find.text(kPlanLoadFailedMessage), findsOneWidget);
      expect(find.text('This is the plan from the last time it loaded.'),
          findsOneWidget);
      expect(find.text('Current'), findsOneWidget);
      expect(enabled(t, startsWith: 'Upgrade to AI-Guided'), isNotEmpty);
      server.answers['client_plan:$_a'] = (200, 'self_guided');
      await t.tap(find.text('Try again'));
      await until(
          t, () => !seen(find.byType(PlanLoadFailedNotice)), 'it to clear');
      expect(find.text('Current'), findsOneWidget);
    });

    testWidgets('Manage says a failed refresh of the plan it still shows; the '
        'row can still be cancelled', (t) async {
      await openManage(t);
      server.answers['client_plan:$_a'] = _down;
      container(t).invalidate(clientPlanProvider);
      await until(t, () => seen(find.byType(PlanLoadFailedNotice)), 'the notice');
      expect(find.text('This is the plan from the last time it loaded.'),
          findsOneWidget);
      expect(find.text('Self-Guided'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await until(t, () => seen(find.text('Switch to Free?')), 'still offered');
    });

    testWidgets("Plans: A's failed refresh is not said to B", (t) async {
      await openPlans(t);
      server.answers['client_plan:$_a'] = _down;
      container(t).invalidate(clientPlanProvider);
      await until(t, () => seen(find.byType(PlanLoadFailedNotice)), 'the notice');
      server.answers['client_plan:$_b'] = (200, 'free');
      final gate = server.gates['client_plan:$_b'] = Completer();
      await signIn(t, _b);
      await settle(t);
      expect(find.byType(PlanLoadFailedNotice), findsNothing);
      gate.complete();
      await until(t, () => seen(find.text('Current')), "B's plan");
    });

    Future<void> openPayments(WidgetTester t) async {
      server.answers['stripe-connect'] =
          (200, {'connected': true, 'charges_enabled': true});
      await open(t, const CoachPaymentsScreen());
      await until(t, () => seen(find.text('Manage Stripe account')), 'status');
      await settle(t);
    }

    int onboards() => server.bodies.where((b) => b.contains('onboard')).length;

    testWidgets('the Stripe button asks once, is busy meanwhile, and is free '
        'again', (t) async {
      await openPayments(t);
      server.answers['stripe-connect:$_a'] = (200, {'url': 'https://stripe/a'});
      final gate = server.gates['stripe-connect:$_a'] = Completer();
      await t.tap(find.text('Manage Stripe account'));
      await t.pump();
      await t.tap(find.text('Manage Stripe account'), warnIfMissed: false);
      await until(t, () => onboards() > 0, 'asked');
      await settle(t);
      expect(onboards(), 1);
      expect(find.bySemanticsLabel(RegExp('Opening Stripe')), findsOneWidget);
      expect(enabled(t), isEmpty);
      gate.complete();
      await until(t, () => launched.isNotEmpty, 'the page');
      await settle(t);
      expect(launched, ['https://stripe/a']);
      expect(enabled(t), isNotEmpty);
      expect(
          t.getSize(find.byType(ElevatedButton)).height, greaterThanOrEqualTo(44));
    });

    testWidgets("no-frame: A's Stripe button tapped after B signed in asks for "
        'nothing', (t) async {
      await openPayments(t);
      await t.runAsync(() => signInAs(_b)); // no frame
      await t.tap(find.text('Manage Stripe account'));
      await noFrames(t);
      await settle(t);
      expect(onboards(), 0);
      expect(recordedAccountChange(), isTrue);
    });

    testWidgets("no-frame: A's failed onboarding is not said to B, whose button "
        'is free', (t) async {
      await openPayments(t);
      server.answers['stripe-connect:$_a'] = _down;
      final gate = server.gates['stripe-connect:$_a'] = Completer();
      await t.tap(find.text('Manage Stripe account'));
      await until(t, () => onboards() == 1, 'A asked');
      await t.runAsync(() => signInAs(_b)); // no frame
      gate.complete();
      await noFrames(t);
      await t.pump();
      expect(find.byType(SnackBar), findsNothing);
      await settle(t);
      expect(find.byType(SnackBar), findsNothing);
      expect(enabled(t), isNotEmpty);
    });
  });

  group('R3 gaps (items 8, 9)', () {
    final openers = <String, (String, Future<Object?> Function())>{
      'startCheckout': (
        'create-checkout',
        () => PaymentService().startCheckout(kind: 'ai_guided')
      ),
      'openBillingPortal': (
        'create-portal-session',
        () => PaymentService().openBillingPortal()
      ),
      'connectStripeOnboard': (
        'stripe-connect',
        () async {
          await PaymentService().connectStripeOnboard();
          return true;
        }
      ),
    };
    openers.forEach((name, o) {
      for (final (how, url) in [
        (_Launch.throws, 'https://stripe/secret-link'),
        (_Launch.refuses, 'https://stripe/secret-link'),
        (_Launch.opens, 'https://[secret-link'), // not a URL at all
      ]) {
        test('N-5: $name, ${how.name} $url: a failure, recorded without the link',
            () async {
          await signInAs(_a);
          server.answers[o.$1] = (200, {'url': url});
          launch = how;
          Object? thrown;
          Object? answer;
          try {
            answer = await o.$2();
          } catch (e) {
            thrown = e;
          }
          expect(name == 'startCheckout' ? answer : thrown,
              name == 'startCheckout' ? isFalse : isNotNull);
          expect(origins(), ['PaymentService.$name']);
          for (final f in reported) {
            expect('$f', isNot(contains('secret-link')));
          }
          expect('$thrown', isNot(contains('secret-link')));
          if (how == _Launch.throws) {
            expect('${reported.single}', contains('ACTIVITY_NOT_FOUND'));
          }
        });
      }

      test('control: $name opens its page', () async {
        await signInAs(_a);
        server.answers[o.$1] = (200, {'url': 'https://stripe/a'});
        expect(await o.$2(), isTrue);
        expect(launched, ['https://stripe/a']);
        expect(reported, isEmpty);
      });
    });

    test('"No billing account yet" under another status is a failure', () async {
      await signInAs(_a);
      server.answers['create-portal-session'] =
          (500, {'error': 'No billing account yet'});
      await expectLater(PaymentService().openBillingPortal(), throwsA(anything));
      expect(origins(), ['PaymentService.openBillingPortal']);
    });

    Map<String, Object> money(int cents) => {
          'connected': true,
          'charges_enabled': true,
          'pending': cents * 2,
          'paid': cents * 3,
        };
    (int, Object?) revenue(int cents) => (200, [
          {
            'coach_payout': cents,
            'client_source': 'marketplace',
            'status': 'paid',
            'created_at': '2026-01-01T00:00:00Z',
          }
        ]);

    Future<void> payments(WidgetTester t) async {
      server.answers['payments:$_a'] = revenue(11100);
      server.answers['stripe-connect:$_a'] = (200, money(11100));
      await open(t, const CoachPaymentsScreen());
      await until(t,
          () => seen(find.text(r'$111')) && seen(find.text(r'$222')), "A's money");
    }

    testWidgets("B's balance failing alone: B's revenue shows, A's balance does "
        'not, and it is said', (t) async {
      await payments(t);
      server.answers['payments:$_b'] = revenue(4400);
      server.answers['stripe-connect:$_b'] = (200, money(4400));
      await signIn(t, _b);
      await until(t, () => seen(find.text(r'$44')), "B's revenue");
      server.answers['stripe-connect:$_b'] = _down;
      container(t).invalidate(coachBalanceProvider);
      await until(
          t, () => seen(find.text("Couldn't load your payouts")), 'said');
      expect(find.text(r'$88'), findsOneWidget, reason: "B's own, kept");
      for (final s in [r'$111', r'$222', r'$333']) {
        expect(find.text(s), findsNothing);
      }
      expect(find.text("Couldn't load your revenue"), findsNothing);
      expect(find.text(r'$44'), findsWidgets);
    });

    for (final fails in [false, true]) {
      final what = fails ? 'failure' : 'answer';
      testWidgets("revenue: A's delayed $what lands before B's own read", (t) async {
        await payments(t);
        if (fails) server.answers['payments:$_a'] = _down;
        server.answers['payments:$_b'] = revenue(4400);
        server.answers['stripe-connect:$_b'] = (200, money(4400));
        final a = server.gates['payments:$_a'] = Completer();
        final b = server.gates['payments:$_b'] = Completer();
        container(t).invalidate(coachRevenueProvider);
        await until(t, () => server.count('payments', _a) == 2, 'A refreshed');
        await signIn(t, _b);
        await until(t, () => server.count('payments', _b) == 1, 'B asked');
        a.complete();
        await settle(t);
        expect(find.text(r'$111'), findsNothing);
        expect(find.text("Couldn't load your revenue"), findsNothing);
        b.complete();
        await until(t, () => seen(find.text(r'$44')), "B's revenue");
      });

      testWidgets("revenue, no-frame: A's delayed $what lands before B is known",
          (t) async {
        await payments(t);
        if (fails) server.answers['payments:$_a'] = _down;
        server.answers['payments:$_b'] = revenue(4400);
        server.answers['stripe-connect:$_b'] = (200, money(4400));
        final a = server.gates['payments:$_a'] = Completer();
        final b = server.gates['payments:$_b'] = Completer();
        container(t).invalidate(coachRevenueProvider);
        await until(t, () => server.count('payments', _a) == 2, 'A refreshed');
        await t.runAsync(() => signInAs(_b));
        a.complete();
        await noFrames(t);
        await settle(t);
        expect(find.text(r'$111'), findsNothing);
        expect(find.text("Couldn't load your revenue"), findsNothing);
        b.complete();
        await until(t, () => seen(find.text(r'$44')), "B's revenue");
      });

      testWidgets("coach tier: A's delayed $what lands before B's own read",
          (t) async {
        server.answers['coach_plan_tier:$_a'] = fails ? _down : (200, 'growth');
        server.answers['coach_plan_tier:$_b'] = (200, 'elite');
        final a = server.gates['coach_plan_tier:$_a'] = Completer();
        final b = server.gates['coach_plan_tier:$_b'] = Completer();
        await open(t, const CoachPlanScreen());
        await until(t, () => server.count('coach_plan_tier', _a) == 1, 'A asked');
        await signIn(t, _b);
        await until(t, () => server.count('coach_plan_tier', _b) == 1, 'B asked');
        a.complete();
        await settle(t);
        expect(find.text('Current'), findsNothing);
        expect(find.byType(SectionLoadFailure), findsNothing);
        expect(enabled(t, startsWith: 'Choose'), isEmpty);
        b.complete();
        await until(t, () => seen(find.text('Current')), "B's plan");
        expect(find.text('Choose Elite'), findsNothing);
      });

      testWidgets("plan: A's delayed $what lands before B's own read", (t) async {
        server.answers['client_plan:$_a'] = fails ? _down : (200, 'ai_guided');
        server.answers['client_plan:$_b'] = (200, 'free');
        final a = server.gates['client_plan:$_a'] = Completer();
        final b = server.gates['client_plan:$_b'] = Completer();
        await open(t, const UpgradeScreen());
        await until(t, () => server.count('client_plan', _a) == 1, 'A asked');
        await signIn(t, _b);
        await until(t, () => server.count('client_plan', _b) == 1, 'B asked');
        a.complete();
        await settle(t);
        expect(find.text('Current'), findsNothing);
        expect(find.byType(PlanLoadFailedNotice), findsNothing);
        expect(enabled(t), isEmpty);
        b.complete();
        await until(t, () => seen(find.text('Upgrade to Self-Guided')), "B's");
      });
    }
  });

  // R6 · the three lead mutants that survived round 5 (60a_surv.jsonl).
  group('R6 the owner checks no other guard covers', () {
    const subs = [
      {'id': 'sub-1', 'kind': 'self_guided', 'status': 'active'},
    ];
    final cancelled = find.textContaining('Nothing was cancelled');

    Future<void> plans(WidgetTester t) async {
      for (final uid in [_a, _b]) {
        server.answers['client_plan:$uid'] = (200, 'self_guided');
      }
      server.answers['subscriptions'] = (200, subs);
      await open(t, const UpgradeScreen());
      await until(t, () => seen(find.text('Current')), "A's plan");
      await settle(t);
    }

    /// Frames, each checked: [never] is not drawn in any of them.
    Future<void> framesWithout(WidgetTester t, Finder never, String why) async {
      for (var i = 0; i < 12; i++) {
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await t.pump(const Duration(milliseconds: 50));
        expect(never, findsNothing, reason: why);
      }
    }

    /// A token refresh of the signed-in account, and proof that it arrived.
    Future<void> sameAccountEvent(WidgetTester t) async {
      final events = <AuthChangeEvent>[];
      await t.runAsync(() async {
        final sub = Supabase.instance.client.auth.onAuthStateChange
            .listen((s) => events.add(s.event));
        await refreshSession();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await sub.cancel();
      });
      expect(events, contains(AuthChangeEvent.tokenRefreshed),
          reason: 'premise: the event arrived');
    }

    // 60a-6 (checkout_launcher: showOwnedSnackBar's owner check). Billing's
    // screen stays mounted across the change, so nothing before the call
    // stops A's late failure. Without the check A's bar is shown to B; the
    // owner-gone listener, added after the change, is handed the auth client's
    // LAST event at once and clears it before a frame — and with it every bar
    // B had up or waiting.
    const aFailed = "Couldn't open billing";
    const bsOwn = 'No billing account yet. Subscribe to a plan first.';

    Future<void> manage(WidgetTester t) async {
      server.answers['client_plan'] = (200, 'self_guided');
      server.answers['subscriptions'] = (200, subs);
      await open(t, const ManageSubscriptionScreen());
      await until(t, () => seen(find.text('Cancel')), "A's plan");
      await settle(t);
    }

    testWidgets("A's billing failure lands after B signed in (frames): B's own "
        'message stays, nothing of A is said', (t) async {
      await manage(t);
      server.answers['create-portal-session:$_a'] = _down;
      server.answers['create-portal-session:$_b'] =
          (400, {'error': 'No billing account yet'});
      final gate = server.gates['create-portal-session:$_a'] = Completer();
      await t.tap(find.text('Manage billing & payment method'));
      await until(
          t, () => server.count('create-portal-session', _a) == 1, 'A asked');
      await signIn(t, _b);
      await until(t, () => seen(find.text('Cancel')), "B's plan");
      await settle(t);
      await t.tap(find.text('Manage billing & payment method'));
      await until(t, () => seen(find.text(bsOwn)), "B's own message");
      await settle(t);
      gate.complete();
      await framesWithout(t, find.textContaining(aFailed), "A's failure, to B");
      expect(find.text(bsOwn), findsOneWidget,
          reason: "A's failure took B's own message down");
      expect(origins(), contains('PaymentService.openBillingPortal'));
      expect(launched, isEmpty);
    });

    testWidgets("A's billing failure lands after B signed in (frames): B is "
        'told nothing', (t) async {
      await manage(t);
      server.answers['create-portal-session:$_a'] = _down;
      final gate = server.gates['create-portal-session:$_a'] = Completer();
      await t.tap(find.text('Manage billing & payment method'));
      await until(
          t, () => server.count('create-portal-session', _a) == 1, 'A asked');
      await signIn(t, _b);
      await settle(t);
      gate.complete();
      await framesWithout(t, find.byType(SnackBar), "A's failure, to B");
      expect(origins(), contains('PaymentService.openBillingPortal'));
    });

    testWidgets("control: the same account's billing failure, a token refresh "
        'in between, is said once', (t) async {
      await manage(t);
      server.answers['create-portal-session:$_a'] = _down;
      final gate = server.gates['create-portal-session:$_a'] = Completer();
      await t.tap(find.text('Manage billing & payment method'));
      await until(
          t, () => server.count('create-portal-session', _a) == 1, 'A asked');
      await sameAccountEvent(t);
      gate.complete();
      await until(t, () => seen(find.textContaining(aFailed)), 'said');
      await settle(t);
      expect(find.textContaining(aFailed), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(recordedAccountChange(), isFalse);
    });

    // The lead's scenario for 60a-8, as it is: A's subscriptions read (Switch
    // to Free) fails after B signed in. With frames the card is A's (keyed by
    // account) and leaves; the no-frame case is in R3 above.
    testWidgets("A's subscriptions read fails after B signed in (frames): B is "
        'told nothing, nothing is sent', (t) async {
      await plans(t);
      server.answers['subscriptions:$_a'] = _down;
      final gate = server.gates['subscriptions:$_a'] = Completer();
      await t.tap(find.text('Switch to Free'));
      await until(t, () => server.count('subscriptions', _a) == 1, 'A asked');
      await signIn(t, _b);
      await settle(t);
      gate.complete();
      await framesWithout(t, cancelled, "A's failure, to B");
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Switch to Free?'), findsNothing);
      expect(server.count('cancel-subscription'), 0);
    });

    testWidgets('control: the same failure with no switch (a token refresh in '
        'between) is said once', (t) async {
      await plans(t);
      server.answers['subscriptions:$_a'] = _down;
      final gate = server.gates['subscriptions:$_a'] = Completer();
      await t.tap(find.text('Switch to Free'));
      await until(t, () => server.count('subscriptions', _a) == 1, 'A asked');
      await sameAccountEvent(t);
      gate.complete();
      await until(t, () => seen(cancelled), 'said');
      await settle(t);
      expect(cancelled, findsOneWidget);
      expect(origins().where((o) => o == 'UpgradeScreen.mySubscriptions'),
          hasLength(1));
      expect(recordedAccountChange(), isFalse);
    });

    // 60a-8 (upgrade_screen: the owner check before `_refresh()` after the
    // checkout). Without it A's checkout, ending after B signed in, re-reads
    // B's plan, tier and subscriptions: A's step, taken as B.
    for (final (answer, what, failed) in [
      (_down, 'fails', true),
      ((200, {'url': 'https://stripe/a'}), 'answers', false),
    ]) {
      testWidgets("A's checkout $what after B signed in (frames): B's plan is "
          'not re-read for it, nothing said', (t) async {
        await plans(t);
        server.answers['update-subscription:$_a'] = (200, {'needsCheckout': true});
        server.answers['create-checkout:$_a'] = answer;
        final gate = server.gates['create-checkout:$_a'] = Completer();
        await t.tap(find.text('Upgrade to AI-Guided'));
        await until(t, () => server.count('create-checkout', _a) == 1, 'A asked');
        await signIn(t, _b);
        await until(t, () => server.count('client_plan', _b) == 1, 'B read');
        await settle(t);
        expect(server.count('client_plan', _b), 1, reason: 'premise');
        gate.complete();
        await settle(t);
        expect(server.count('client_plan', _b), 1,
            reason: "A's checkout re-read B's plan");
        expect(find.byType(SnackBar), findsNothing);
        expect(launched, isEmpty);
        // A failure is the service's to record; a link made for A, the
        // change's.
        failed
            ? expect(origins(), contains('PaymentService.startCheckout'))
            : expect(recordedAccountChange(), isTrue);
      });

      testWidgets("no-frame: A's checkout $what after B signed in: B's plan is "
          'read once, nothing said', (t) async {
        await plans(t);
        server.answers['update-subscription:$_a'] = (200, {'needsCheckout': true});
        server.answers['create-checkout:$_a'] = answer;
        final gate = server.gates['create-checkout:$_a'] = Completer();
        await t.tap(find.text('Upgrade to AI-Guided'));
        await until(t, () => server.count('create-checkout', _a) == 1, 'A asked');
        await t.runAsync(() => signInAs(_b)); // no frame
        gate.complete();
        await noFrames(t);
        await settle(t);
        expect(server.count('client_plan', _b), 1);
        expect(find.byType(SnackBar), findsNothing);
        expect(launched, isEmpty);
        failed
            ? expect(origins(), contains('PaymentService.startCheckout'))
            : expect(recordedAccountChange(), isTrue);
      });
    }

    testWidgets("control: the same account's failed checkout is said once and "
        'its plan re-read', (t) async {
      await plans(t);
      server.answers['update-subscription:$_a'] = (200, {'needsCheckout': true});
      server.answers['create-checkout:$_a'] = _down;
      final before = server.count('client_plan', _a);
      await t.tap(find.text('Upgrade to AI-Guided'));
      await until(t, () => seen(find.text(checkoutFailedMessage)), 'said');
      await settle(t);
      expect(find.text(checkoutFailedMessage), findsOneWidget);
      expect(server.count('client_plan', _a), before + 1, reason: 're-read');
      expect(recordedAccountChange(), isFalse);
    });

    // 60a-N4 (paywall_gate: no plan and no failure of THIS account = loading).
    // Without it `clientPlanProvider.when` decides; a refresh asked for before
    // the change reached the providers keeps A's plan as data that is
    // refreshing, and `when` shows that data.
    Future<void> gate(WidgetTester t) async {
      for (final uid in [_a, _b]) {
        server.answers['user_profiles:$uid'] =
            (200, {'id': uid, 'role': 'client'});
      }
      server.answers['client_plan:$_a'] = (200, 'ai_guided');
      await open(
          t,
          const PaywallGate(
              required: ClientPlan.aiGuided,
              featureName: 'AI coach',
              child: Text('GATED')));
      await until(t, () => seen(find.text('GATED')), "A's gate");
    }

    testWidgets("no-frame: A's plan refresh asked for, then B signs in: A's "
        'plan never opens it for B', (t) async {
      await gate(t);
      server.answers['client_plan:$_b'] = (200, 'free');
      final g = server.gates['client_plan:$_b'] = Completer();
      container(t).invalidate(clientPlanProvider); // A's refresh, no frame
      await t.runAsync(() => signInAs(_b)); // no frame
      for (var i = 0; i < 12; i++) {
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await t.pump(const Duration(milliseconds: 50));
        expect(find.text('GATED'), findsNothing, reason: "A's plan opened it");
      }
      expect(find.byType(PaywallLocked), findsNothing);
      g.complete();
      await until(t, () => seen(find.byType(PaywallLocked)), "B's Free");
    });
  });
}
