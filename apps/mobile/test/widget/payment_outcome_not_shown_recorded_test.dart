import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/payments/presentation/coach_payments_screen.dart';
import 'package:circle_fitness/features/payments/presentation/coach_plan_screen.dart';
import 'package:circle_fitness/features/payments/presentation/manage_subscription_screen.dart';
import 'package:circle_fitness/features/payments/presentation/upgrade_screen.dart';

import '../support/pump_until.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-63b · the outcome of A's payment action that is NOT shown because the
// signed-in account changed is itself recorded (FL-60a recorded only the
// failure underneath, or nothing): once, under an origin naming the flow, as
// StateError('<flow> outcome not shown: the signed-in account changed') — and
// nothing else in it: no amount, no plan, no coach, no message text. B is told
// nothing. Controls: the same account sees the message and nothing is recorded.
//
// Two real accounts through the real auth client and providers; no account
// scope is mounted, and every screen STAYS mounted across the switch.
//
// HOW TO SEE IT FAIL: `git checkout 7b9ce5c -- lib/features/payments`: no
// "outcome not shown" record exists there (the drop was silent).

class _Server extends TwoMemberPostgrest {
  final answers = <String, (int, Object?)>{};
  final gates = <String, Completer<void>>{};
  final log = <String>[];
  final writes = <String>[];

  @override
  void reset() {
    super.reset();
    answers.clear();
    gates.clear();
    log.clear();
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
    final isWrite = request.method != 'GET' &&
        path.startsWith('/rest/') &&
        !path.contains('/rpc/');
    if (isWrite) writes.add('${request.method} $key');
    final gate = gates[key];
    final answer = answers['${request.method} $key'] ??
        answers[key] ??
        answers[name];
    if (gate != null) await gate.future;
    if (answer == null && isWrite &&
        !request.url.queryParameters.containsKey('select')) {
      // A write that asked for no rows gets none.
      return http.StreamedResponse(const Stream.empty(), 204, request: request);
    }
    final (status, body) = answer ??
        (path.contains('/rpc/') ? (200, null) : (200, const <Object?>[]));
    return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))), status,
        request: request, headers: {'content-type': 'application/json'});
  }
}

const _a = memberA;
const _b = memberB;
const _down = (500, {'message': 'SECRET backend text', 'code': 'XX000'});

void main() {
  final server = _Server();
  final reported = <AppFailure>[];
  final launched = <String>[];
  const channel = MethodChannel('plugins.flutter.io/url_launcher');

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(server);
  });

  setUp(() {
    server.reset();
    reported.clear();
    launched.clear();
    setFailureSink(reported.add);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'canLaunch') return true;
      if (call.method != 'launch') return null;
      launched.add((call.arguments as Map)['url'] as String);
      return true;
    });
  });
  tearDown(resetFailureSink);

  Iterable<AppFailure> notShown() =>
      reported.where((f) => '${f.error}'.contains('outcome not shown'));

  /// Exactly one drop is recorded, it is [flow]'s under [origin], and it says
  /// nothing but that — no amount, plan, coach, message text or id.
  void recordedOnce(String origin, String flow) {
    final drops = notShown().toList();
    expect(drops, hasLength(1),
        reason: 'the outcome A never saw is recorded once: '
            '${reported.map((f) => '${f.origin}: ${f.error}').toList()}');
    final f = drops.single;
    expect(f.origin, origin);
    expect(f.error, isA<StateError>());
    expect((f.error as StateError).message,
        '$flow outcome not shown: the signed-in account changed');
    expect(f.context, isNull, reason: 'no payment or personal detail attached');
  }

  Future<void> signIn(WidgetTester t, String uid) async {
    await t.runAsync(() => signInAs(uid));
    await t.pump();
  }

  Future<void> open(WidgetTester t, Widget screen) async {
    await t.binding.setSurfaceSize(const Size(700, 3200));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.runAsync(() => signInAs(_a));
    await t.pumpWidget(ProviderScope(child: MaterialApp(home: screen)));
    await t.pump();
  }

  Future<void> until(WidgetTester t, bool Function() ok, String what) =>
      pumpUntil(t, ok, what: what);

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 12; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  /// What is in flight lands and runs; no frame is drawn (a hidden web tab).
  Future<void> noFrames(WidgetTester t) async {
    for (var i = 0; i < 12; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await t.idle();
    }
  }

  bool seen(Finder f) => f.evaluate().isNotEmpty;

  void saidNothing() {
    expect(find.byType(SnackBar), findsNothing, reason: "A's outcome said to B");
  }

  // ── Plans (Upgrade) ───────────────────────────────────────────────────────
  group('Plans (Upgrade)', () {
    const sub1 = {'id': 'sub-1', 'kind': 'self_guided', 'status': 'active'};
    const sub2 = {'id': 'sub-2', 'kind': 'ai_guided', 'status': 'active'};

    Future<void> openAsA(WidgetTester t) async {
      server.answers['client_plan:$_a'] = (200, 'self_guided');
      server.answers['client_plan:$_b'] = (200, 'free');
      server.answers['subscriptions:$_a'] = (200, [sub1, sub2]);
      await open(t, const UpgradeScreen());
      await until(t, () => seen(find.text('Current')), "A's plan");
    }

    for (final (answer, what) in [
      ((200, {'ok': true}), 'changed'),
      ((200, {'paymentIssue': true}), 'payment problem'),
      (_down, 'refused'),
    ]) {
      testWidgets("plan change ($what) lands after B signed in: B is told "
          'nothing, the drop is recorded once', (t) async {
        await openAsA(t);
        server.answers['update-subscription:$_a'] = answer;
        final gate = server.gates['update-subscription:$_a'] = Completer();
        await t.tap(find.text('Upgrade to AI-Guided'));
        await until(t, () => server.count('update-subscription') == 1, 'A asked');
        await signIn(t, _b);
        await until(t, () => seen(find.text('Upgrade to Self-Guided')), "B's plan");
        gate.complete();
        await settle(t);
        saidNothing();
        expect(server.count('update-subscription'), 1);
        expect(server.count('create-checkout'), 0);
        recordedOnce('UpgradeScreen.planChange', 'plan change');
      });
    }

    testWidgets('control: plan change for the same account is said, nothing '
        'recorded', (t) async {
      await openAsA(t);
      server.answers['update-subscription:$_a'] = (200, {'ok': true});
      final gate = server.gates['update-subscription:$_a'] = Completer();
      await t.tap(find.text('Upgrade to AI-Guided'));
      await until(t, () => server.count('update-subscription') == 1, 'A asked');
      await t.runAsync(refreshSession); // the same account
      await t.pump();
      gate.complete();
      await until(t, () => seen(find.text('Your plan is now AI-Guided.')), 'said');
      expect(reported, isEmpty);
    });

    testWidgets('needs_checkout after B signed in: nothing was changed, so no '
        'outcome is recorded as dropped (the stop is)', (t) async {
      await openAsA(t);
      server.answers['update-subscription:$_a'] = (200, {'needsCheckout': true});
      final gate = server.gates['update-subscription:$_a'] = Completer();
      await t.tap(find.text('Upgrade to AI-Guided'));
      await until(t, () => server.count('update-subscription') == 1, 'A asked');
      await signIn(t, _b);
      gate.complete();
      await settle(t);
      saidNothing();
      expect(server.count('create-checkout'), 0);
      expect(notShown(), isEmpty);
      expect(reported.map((f) => '${f.error}'),
          contains('Bad state: plan change: the signed-in account changed'));
    });

    testWidgets("Switch to Free: B signs in between A's two cancellations: the "
        'outcome of the first is recorded as not shown', (t) async {
      await openAsA(t);
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
      expect(server.count('cancel-subscription', _b), 0);
      expect(server.count('cancel-subscription'), 1);
      saidNothing();
      recordedOnce('UpgradeScreen.switchToFree', 'switch to Free');
    });

    testWidgets('control: Switch to Free for the same account is said, nothing '
        'recorded', (t) async {
      await openAsA(t);
      server.answers['cancel-subscription'] = (200, {'ok': true});
      await t.tap(find.text('Switch to Free'));
      await until(t, () => seen(find.text('Switch to Free?')), 'the dialog');
      await settle(t);
      await t.tap(find.text('Switch to Free').last);
      await until(t, () => seen(find.text('Switched to the Free plan.')), 'said');
      expect(server.count('cancel-subscription', _a), 2);
      expect(reported, isEmpty);
    });

    testWidgets("A's refused checkout lands after B signed in: recorded once as "
        'not shown, and its refusal is not said to B', (t) async {
      await openAsA(t);
      server.answers['update-subscription:$_a'] = (200, {'needsCheckout': true});
      server.answers['create-checkout:$_a'] =
          (409, {'code': 'already_subscribed', 'error': 'You have AI-Guided.'});
      final gate = server.gates['create-checkout:$_a'] = Completer();
      await t.tap(find.text('Upgrade to AI-Guided'));
      await until(t, () => server.count('create-checkout') == 1, 'A asked');
      await signIn(t, _b);
      gate.complete();
      await settle(t);
      saidNothing();
      expect(find.textContaining('You have AI-Guided'), findsNothing);
      expect(launched, isEmpty);
      recordedOnce('launchCheckout', 'checkout');
    });

    testWidgets("control: the same account's refused checkout is said, no drop "
        'recorded', (t) async {
      await openAsA(t);
      server.answers['update-subscription:$_a'] = (200, {'needsCheckout': true});
      server.answers['create-checkout:$_a'] =
          (409, {'code': 'already_subscribed', 'error': 'You have AI-Guided.'});
      await t.tap(find.text('Upgrade to AI-Guided'));
      await until(t, () => seen(find.byType(SnackBar)), 'said');
      expect(notShown(), isEmpty);
    });
  });

  // ── Coach plan ────────────────────────────────────────────────────────────
  group('Coach plan', () {
    testWidgets("A's failed coach-plan checkout lands after B: recorded once, "
        'nothing said to B', (t) async {
      server.answers['coach_plan_tier:$_a'] = (200, null);
      server.answers['coach_plan_tier:$_b'] = (200, 'growth');
      server.answers['create-checkout:$_a'] = _down;
      await open(t, const CoachPlanScreen());
      await until(t, () => seen(find.text('Choose Starter')), 'plans');
      final gate = server.gates['create-checkout:$_a'] = Completer();
      await t.tap(find.text('Choose Starter'));
      await until(t, () => server.count('create-checkout') == 1, 'A asked');
      await signIn(t, _b);
      gate.complete();
      await settle(t);
      saidNothing();
      expect(server.count('create-checkout', _b), 0);
      recordedOnce('launchCheckout', 'checkout');
    });

    testWidgets("control: the same coach's failed checkout is said, no drop "
        'recorded', (t) async {
      server.answers['coach_plan_tier:$_a'] = (200, null);
      server.answers['create-checkout:$_a'] = _down;
      await open(t, const CoachPlanScreen());
      await until(t, () => seen(find.text('Choose Starter')), 'plans');
      await t.tap(find.text('Choose Starter'));
      await until(
          t, () => seen(find.text('Could not start checkout. Try again.')), 'said');
      expect(notShown(), isEmpty);
    });
  });

  // ── Coach payments ────────────────────────────────────────────────────────
  group('Coach payments', () {
    Future<void> openAsA(WidgetTester t) async {
      server.answers['payments:$_a'] = (200, const <Object?>[]);
      server.answers['stripe-connect:$_a'] = (200, {
        'connected': true,
        'charges_enabled': true,
        'payouts_enabled': true,
        'pending': 22200,
        'paid': 33300,
      });
      await open(t, const CoachPaymentsScreen());
      await until(t, () => seen(find.text('Manage Stripe account')), 'A');
    }

    testWidgets("A's Stripe page fails after B signed in: recorded once, "
        'nothing opened or said to B', (t) async {
      await openAsA(t);
      server.answers['stripe-connect:$_a'] = (200, {'url': 'https://stripe/a'});
      server.answers['stripe-connect:$_b'] = (200, {'connected': true});
      final gate = server.gates['stripe-connect:$_a'] = Completer();
      await t.tap(find.text('Manage Stripe account'));
      await until(t, () => server.count('stripe-connect', _a) >= 2, 'A asked');
      await signIn(t, _b);
      gate.complete();
      await settle(t);
      expect(launched, isEmpty);
      saidNothing();
      recordedOnce('CoachPaymentsScreen.openStripe', 'open Stripe');
      final drop = notShown().single;
      expect('${drop.error}', isNot(contains(r'$')), reason: 'no amount');
      expect('${drop.error}', isNot(contains('222')));
    });

    testWidgets("control: the same coach's failed Stripe page is said, no drop "
        'recorded', (t) async {
      await openAsA(t);
      server.answers['stripe-connect:$_a'] = _down;
      await t.tap(find.text('Manage Stripe account'));
      await until(t, () => seen(find.byType(SnackBar)), 'said');
      expect(notShown(), isEmpty);
    });
  });

  // ── Manage subscription ───────────────────────────────────────────────────
  group('Manage subscription', () {
    const portal = 'Manage billing & payment method';
    const rel = {'coach_id': 'c-1', 'status': 'active'};

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

    testWidgets("A's billing page fails after B signed in: recorded once, "
        'nothing said to B', (t) async {
      await openAsA(t);
      server.answers['create-portal-session:$_a'] = _down;
      final gate = server.gates['create-portal-session:$_a'] = Completer();
      await t.tap(find.text(portal));
      await until(t, () => seen(find.text('Opening…')), 'A asked');
      await signIn(t, _b);
      gate.complete();
      await settle(t);
      saidNothing();
      expect(launched, isEmpty);
      recordedOnce('ManageSubscriptionScreen.openBilling', 'open billing');
    });

    testWidgets("control: the same account's failed billing page is said, no "
        'drop recorded', (t) async {
      await openAsA(t);
      server.answers['create-portal-session:$_a'] = _down;
      await t.tap(find.text(portal));
      await until(t, () => seen(find.byType(SnackBar)), 'said');
      expect(notShown(), isEmpty);
    });

    testWidgets("hidden tab: A's billing failure is put up but never drawn, "
        'then B signs in: recorded once, nothing drawn for B', (t) async {
      await openAsA(t);
      server.answers['create-portal-session:$_a'] = _down;
      final gate = server.gates['create-portal-session:$_a'] = Completer();
      await t.tap(find.text(portal));
      await until(t, () => seen(find.text('Opening…')), 'A asked');
      gate.complete();
      await noFrames(t); // the answer lands for A; no frame draws the bar
      expect(notShown(), isEmpty, reason: 'premise: A is still signed in');
      await t.runAsync(() => signInAs(_b));
      await noFrames(t);
      await t.pump();
      saidNothing();
      await settle(t);
      saidNothing();
      recordedOnce('ManageSubscriptionScreen.openBilling', 'open billing');
    });

    testWidgets('control: a bar A saw, taken away when B signs in, is not '
        'recorded as unseen', (t) async {
      await openAsA(t);
      server.answers['create-portal-session:$_a'] = _down;
      await t.tap(find.text(portal));
      await until(t, () => seen(find.byType(SnackBar)), 'drawn for A');
      await settle(t);
      await signIn(t, _b);
      await settle(t);
      saidNothing();
      expect(notShown(), isEmpty);
    });

    testWidgets("Cancel plan: B signs in between A's two cancellations: "
        'recorded once as not shown', (t) async {
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
      expect(server.count('cancel-subscription'), 1);
      saidNothing();
      recordedOnce('ManageSubscriptionScreen.switchToFree', 'switch to Free');
    });

    testWidgets('control: Cancel plan for the same account is said, nothing '
        'recorded', (t) async {
      await openAsA(t);
      server.answers['cancel-subscription'] = (200, {'ok': true});
      await t.tap(find.textContaining('Cancel').first);
      await until(t, () => seen(find.text('Switch to Free?')), 'the dialog');
      await settle(t);
      await t.runAsync(refreshSession);
      await settle(t);
      await t.tap(find.text('Switch to Free'));
      await until(t, () => seen(find.text('Switched to the Free plan.')), 'said');
      expect(server.count('cancel-subscription', _a), 2);
      expect(reported, isEmpty);
    });

    for (final paid in [true, false]) {
      final kind = paid ? 'paid' : 'unpaid';
      Future<void> tapStop(WidgetTester t) async {
        server.answers['coach_client_relationships'] = (200, [rel]);
        server.answers['public_profiles'] = (200, [
          {'id': 'c-1', 'first_name': 'Anna', 'last_name': 'Coach'}
        ]);
        await openAsA(t);
        await until(t, () => seen(find.text('Stop')), "A's coach");
        await t.tap(find.text('Stop'));
        await until(t, () => seen(find.text('Stop working with Anna Coach?')),
            'the dialog');
        await settle(t);
        server.answers['subscriptions:$_a'] = (200, [
          if (paid) {'id': 's-a', 'current_period_end': '2027-03-03T12:00:00Z'},
        ]);
        server.answers['cancel-subscription:$_a'] =
            (200, {'ok': true, 'endsAt': '2027-03-03T12:00:00Z'});
      }

      testWidgets("Stop coach ($kind): B signs in while A's is being ended: "
          'recorded once as not shown, nothing named to B', (t) async {
        await tapStop(t);
        final gate = server.gates['subscriptions:$_a'] = Completer();
        final before = server.count('subscriptions', _a);
        await t.tap(find.text('Yes, stop'));
        await until(
            t, () => server.count('subscriptions', _a) > before, 'A asked');
        await signIn(t, _b);
        gate.complete();
        await settle(t);
        saidNothing();
        recordedOnce('ManageSubscriptionScreen.stopCoach', 'stop coaching');
        expect('${notShown().single.error}', isNot(contains('Anna')));
      });

      testWidgets("Stop coach ($kind): B signs in after it ended, before it is "
          'said: recorded once as not shown', (t) async {
        await tapStop(t);
        // The last step of each path is held: the outcome is known, unsaid.
        final last = paid ? 'cancel-subscription:$_a' : 'notifications:$_a';
        final gate = server.gates[last] = Completer();
        await t.tap(find.text('Yes, stop'));
        await until(t, () => server.count(last.split(':').first, _a) == 1,
            'the last step');
        await signIn(t, _b);
        gate.complete();
        await settle(t);
        saidNothing();
        recordedOnce('ManageSubscriptionScreen.stopCoach', 'stop coaching');
      });

      testWidgets('control: Stop coach ($kind) by the same account is said, '
          'nothing recorded', (t) async {
        await tapStop(t);
        await t.runAsync(refreshSession);
        await settle(t);
        await t.tap(find.text('Yes, stop'));
        await until(t, () => seen(find.byType(SnackBar)), 'the outcome');
        expect(reported, isEmpty);
      });
    }
  });
}
