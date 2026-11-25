import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/payments/data/payment_service.dart';
import 'package:circle_fitness/features/payments/domain/entitlements.dart';
import 'package:circle_fitness/features/payments/domain/payment_provider.dart';
import 'package:circle_fitness/features/payments/presentation/coach_payments_screen.dart';
import 'package:circle_fitness/features/payments/presentation/coach_plan_screen.dart';
import 'package:circle_fitness/features/payments/presentation/manage_subscription_screen.dart';
import 'package:circle_fitness/features/payments/presentation/upgrade_screen.dart';
import 'package:circle_fitness/features/workout/presentation/widgets/section_load_failure.dart';

import '../support/pump_until.dart';
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
// HOW TO SEE IT FAIL: `git checkout a82f993 -- lib/features/payments`.

class _Server extends TwoMemberPostgrest {
  /// Answers keyed `name:<who asked>` (else `name`): an rpc, a function or a
  /// table name. `(status, body)`.
  final answers = <String, (int, Object?)>{};

  /// `name:<who>` held until completed. The answer is the one that was true
  /// when the request ARRIVED.
  final gates = <String, Completer<void>>{};

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
    final (status, body) = answers[key] ??
        answers[name] ??
        (path.contains('/rpc/') ? (200, null) : (200, const <Object?>[]));
    final gate = gates[key];
    if (gate != null) await gate.future;
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
        _Launch.throws => throw PlatformException(code: 'ACTIVITY_NOT_FOUND'),
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
      expect(await svc().changeMembership('ai_guided'), 'error');
      server.answers['update-subscription'] = (200, {'what': 1});
      expect(await svc().changeMembership('ai_guided'), 'error');
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
        await pumpEventQueue();
        expect(server.log, ['${o.$1}:$_a'], reason: 'premise: A asked');
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
      await pumpEventQueue();
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
      expect(enabled(t, startsWith: 'Upgrade to AI-Guided'), isNotEmpty,
          reason: "A's spinner is not B's");
      gate.complete();
      await settle(t);
      expect(server.count('create-checkout'), 0,
          reason: "A's plan change minted a checkout for B");
      expect(launched, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      expect(recordedAccountChange(), isTrue);
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
      await until(t, () => seen(find.byType(PlanLoadFailedNotice)), 'the notice');
      expect(find.text('Current'), findsNothing);
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
      await until(t, () => seen(find.text("Couldn't load your coach")), 'said');
      expect(find.textContaining('Anna'), findsNothing);
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

    testWidgets('an unread tier is not "no plan": nothing is for sale, it is '
        'said, and Try again re-reads', (t) async {
      server.answers['coach_plan_tier:$_a'] = _down;
      await open(t, const CoachPlanScreen());
      await until(t, () => seen(find.byType(SectionLoadFailure)), 'the failure');
      expect(find.text("Couldn't load your plan"), findsOneWidget);
      expect(enabled(t, startsWith: 'Choose'), isEmpty,
          reason: 'a paying coach was offered every plan');
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
      await until(t, () => server.count('coach_plan_tier') == 1, 'asked');
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
      expect(find.text('Current'), findsNothing, reason: 'pending');
      await until(t, () => seen(find.byType(SectionLoadFailure)), 'failure');
      expect(find.text('Current'), findsNothing, reason: 'failed');
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
      container(t).invalidate(coachPlanTierProvider);
      await until(t, () => seen(find.byType(SectionLoadFailure)), 'failure');
      expect(find.text('Current'), findsOneWidget);
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
      await until(t, () => enabled(t, startsWith: 'Choose').length == 3,
          "B's three plans");
      gate.complete();
      await settle(t);
      expect(launched, isEmpty);
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

    /// B's status answers; B's money does not (yet, or at all).
    void statusOnlyForB() {
      server.answers['payments:$_b'] = _down;
      server.answers['stripe-connect:$_b'] = (200, {'connected': true});
    }

    testWidgets("A-19: B's revenue and balance failed: A's are not B's, and it "
        'is said and recorded', (t) async {
      await openAsA(t);
      server.answers['payments:$_b'] = _down;
      server.answers['stripe-connect:$_b'] = (200, {'connected': true});
      await signIn(t, _b);
      await until(t, () => seen(find.text("Couldn't load your revenue")), 'said');
      noneOfAs();
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
      await until(
          t, () => seen(find.text("Couldn't load your Stripe status")), 'said');
      noneOfAs();
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
      statusOnlyForB();
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
      await until(t, () => seen(find.text(portal)), "B's button");
      gate.complete();
      await settle(t);
      expect(launched, isEmpty, reason: "A's invoices opened for B");
      expect(find.byType(SnackBar), findsNothing);
      expect(recordedAccountChange(), isTrue);
    });

    testWidgets("A-21: B's plan read failed: A's plan is not B's", (t) async {
      await openAsA(t);
      server.answers['client_plan:$_b'] = _down;
      await signIn(t, _b);
      await until(t, () => seen(find.byType(PlanLoadFailedNotice)), 'the notice');
      expect(find.text('Self-Guided'), findsNothing);
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
      expect(server.writes, isEmpty);
      expect(server.count('cancel-subscription'), 0);
    });

    testWidgets("Stop coach: B signs in while A's is being ended: B is told "
        'nothing', (t) async {
      shareCoach();
      await openAsA(t);
      await tapStop(t);
      server.answers['subscriptions:$_a'] = _down;
      final gate = server.gates['subscriptions:$_a'] = Completer();
      final before = server.count('subscriptions', _a);
      await t.tap(find.text('Yes, stop'));
      await until(
          t, () => server.count('subscriptions', _a) > before, 'A asked');
      await signIn(t, _b);
      gate.complete();
      await settle(t);
      expect(find.byType(SnackBar), findsNothing);
      expect(server.writes, isEmpty);
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
}
