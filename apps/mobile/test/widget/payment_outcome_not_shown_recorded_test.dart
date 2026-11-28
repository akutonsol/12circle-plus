import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:circle_fitness/core/identity/account_scope.dart';
import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/payments/domain/payment_provider.dart'
    show mySubscriptionsProvider;
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

  /// RM-2 (C15-63b-05) · [flow] stopped before anything of it was sent:
  /// recorded once as the plain stop, and NOT as an outcome left unshown (there
  /// was none). Names the flow only.
  void stoppedOnce(String origin, String flow) {
    final stops = reported
        .where((f) =>
            f.error is StateError &&
            (f.error as StateError).message ==
                '$flow: the signed-in account changed')
        .toList();
    expect(stops, hasLength(1),
        reason: 'the stop is recorded once: '
            '${reported.map((f) => '${f.origin}: ${f.error}').toList()}');
    expect(stops.single.origin, origin);
    expect(stops.single.context, isNull);
    expect(notShown(), isEmpty,
        reason: 'THE defect: nothing was sent, yet the record said an outcome '
            'was not shown');
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

      // The switch lands during the read, before any write: nothing was
      // changed, so there is no outcome - the stop is the service's record,
      // once (FL-62b), and none is added here.
      testWidgets("Stop coach ($kind): B signs in during A's read, before "
          'anything was sent: no outcome recorded, the stop once', (t) async {
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
        expect(server.count('cancel-subscription'), 0);
        expect(server.writes, isEmpty);
        expect(notShown(), isEmpty);
        expect(
            reported.where(
                (f) => '${f.error}'.contains('the signed-in account changed')),
            hasLength(1));
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
        expect('${notShown().single.error}', isNot(contains('Anna')));
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

  // ── Round 2 (P0-FL-63b): the branches round 1 never reached ───────────────
  // Each kills one code mutant that survived round 1 (M7, M9, M14, M18).
  group('round 2', () {
    const sub1 = {'id': 'sub-1', 'kind': 'self_guided', 'status': 'active'};

    List<String> records() =>
        reported.map((f) => '${f.origin}: ${f.error}').toList();

    Future<void> openUpgradeOneSub(WidgetTester t) async {
      server.answers['client_plan:$_a'] = (200, 'self_guided');
      server.answers['client_plan:$_b'] = (200, 'free');
      server.answers['subscriptions:$_a'] = (200, [sub1]);
      await open(t, const UpgradeScreen());
      await until(t, () => seen(find.text('Current')), "A's plan");
    }

    Future<void> openManageOneSub(WidgetTester t) async {
      server.answers['client_plan:$_a'] = (200, 'self_guided');
      server.answers['client_plan:$_b'] = (200, 'free');
      server.answers['subscriptions:$_a'] = (200, [sub1]);
      await open(t, const ManageSubscriptionScreen());
      await until(t, () => seen(find.text('Self-Guided')), "A's plan");
      await settle(t);
    }

    Future<void> leaveFor(WidgetTester t, bool toB) async {
      if (toB) {
        await signIn(t, _b);
      } else {
        await t.runAsync(signOut);
        await t.pump();
      }
    }

    for (final toB in [true, false]) {
      final label = toB ? 'B signs in' : 'A signs out';

      // M7: the check after the LAST (here: the only) cancellation.
      testWidgets('Upgrade, Switch to Free: $label while the last cancellation '
          'is in flight: its outcome is recorded once as not shown', (t) async {
        await openUpgradeOneSub(t);
        server.answers['cancel-subscription'] = (200, {'ok': true});
        final gate = server.gates['cancel-subscription:$_a'] = Completer();
        await t.tap(find.text('Switch to Free'));
        await until(t, () => seen(find.text('Switch to Free?')), 'the dialog');
        await settle(t);
        await t.tap(find.text('Switch to Free').last);
        await until(t, () => server.count('cancel-subscription') == 1, 'sent');
        await leaveFor(t, toB);
        gate.complete();
        await settle(t);
        expect(server.log.where((l) => l.startsWith('cancel-subscription')),
            ['cancel-subscription:$_a'], reason: "one cancel, A's, none for B");
        saidNothing();
        expect(find.text('Switched to the Free plan.'), findsNothing);
        recordedOnce('UpgradeScreen.switchToFree', 'switch to Free');
        expect(reported, hasLength(1), reason: '${records()}');
        expect('${reported.single.error}', isNot(contains('sub-1')));
      });

      // M9: the same check on /manage-subscription.
      testWidgets('Manage, Cancel plan: $label while the last cancellation is '
          'in flight: its outcome is recorded once as not shown', (t) async {
        await openManageOneSub(t);
        server.answers['cancel-subscription'] = (200, {'ok': true});
        final gate = server.gates['cancel-subscription:$_a'] = Completer();
        await t.tap(find.textContaining('Cancel').first);
        await until(t, () => seen(find.text('Switch to Free?')), 'the dialog');
        await settle(t);
        await t.tap(find.text('Switch to Free'));
        await until(t, () => server.count('cancel-subscription') == 1, 'sent');
        await leaveFor(t, toB);
        gate.complete();
        await settle(t);
        expect(server.log.where((l) => l.startsWith('cancel-subscription')),
            ['cancel-subscription:$_a'], reason: "one cancel, A's, none for B");
        saidNothing();
        recordedOnce('ManageSubscriptionScreen.switchToFree', 'switch to Free');
        expect(reported, hasLength(1), reason: '${records()}');
        expect('${reported.single.error}', isNot(contains('sub-1')));
      });
    }

    testWidgets('control: Upgrade Switch to Free with one membership, same '
        'account (token refresh mid-cancel): said once, nothing recorded',
        (t) async {
      await openUpgradeOneSub(t);
      server.answers['cancel-subscription'] = (200, {'ok': true});
      final gate = server.gates['cancel-subscription:$_a'] = Completer();
      await t.tap(find.text('Switch to Free'));
      await until(t, () => seen(find.text('Switch to Free?')), 'the dialog');
      await settle(t);
      await t.tap(find.text('Switch to Free').last);
      await until(t, () => server.count('cancel-subscription') == 1, 'sent');
      await t.runAsync(refreshSession);
      await t.pump();
      gate.complete();
      await until(t, () => seen(find.text('Switched to the Free plan.')), 'said');
      expect(server.count('cancel-subscription', _a), 1);
      expect(reported, isEmpty);
    });

    testWidgets('control: Manage Cancel plan with one membership, same account '
        '(token refresh mid-cancel): said once, nothing recorded', (t) async {
      await openManageOneSub(t);
      server.answers['cancel-subscription'] = (200, {'ok': true});
      final gate = server.gates['cancel-subscription:$_a'] = Completer();
      await t.tap(find.textContaining('Cancel').first);
      await until(t, () => seen(find.text('Switch to Free?')), 'the dialog');
      await settle(t);
      await t.tap(find.text('Switch to Free'));
      await until(t, () => server.count('cancel-subscription') == 1, 'sent');
      await t.runAsync(refreshSession);
      await t.pump();
      gate.complete();
      await until(t, () => seen(find.text('Switched to the Free plan.')), 'said');
      expect(server.count('cancel-subscription', _a), 1);
      expect(reported, isEmpty);
    });

    // M18: the Free tap's subscriptions read is still pending when B signs
    // in, and it fails. The subscriptions are watched lower in the stack (as
    // /manage-subscription does, which pushes /upgrade), so the read is rerun
    // for B and the tap's await ends in that failure while B is signed in.
    // (With nothing watching it, the await never ends and nothing is said
    // or recorded — see the report.)
    testWidgets("Upgrade, Switch to Free: the tap's subscriptions read fails "
        'after B signed in: not said to B, recorded under the Switch to Free '
        'origin, nothing cancelled', (t) async {
      server.answers['client_plan:$_a'] = (200, 'self_guided');
      server.answers['client_plan:$_b'] = (200, 'free');
      server.answers['subscriptions:$_a'] = _down;
      server.answers['subscriptions:$_b'] = _down;
      final gateA = server.gates['subscriptions:$_a'] = Completer();
      final gateB = server.gates['subscriptions:$_b'] = Completer();
      await open(t, Consumer(builder: (context, ref, _) {
        ref.watch(mySubscriptionsProvider); // the screen beneath
        return const UpgradeScreen();
      }));
      await until(t, () => seen(find.text('Current')), "A's plan");
      expect(server.count('subscriptions', _a), 1, reason: 'premise: pending');
      await t.tap(find.text('Switch to Free'));
      await t.pump();
      await signIn(t, _b);
      await until(t, () => server.count('subscriptions', _b) == 1, 'B read');
      gateA.complete();
      gateB.complete();
      await settle(t);
      saidNothing();
      expect(find.textContaining('Nothing was cancelled'), findsNothing);
      expect(find.text('Switch to Free?'), findsNothing);
      expect(server.count('cancel-subscription'), 0);
      expect(server.writes, isEmpty);
      stoppedOnce('UpgradeScreen.switchToFree', 'switch to Free');
      // Round 3: the tap ends when A leaves (the stop record comes first
      // now); the read failure that lands later is still recorded.
      expect(reported.map((f) => f.origin).toList(),
          unorderedEquals(
              ['UpgradeScreen.mySubscriptions', 'UpgradeScreen.switchToFree']),
          reason: '${records()}');
      expect(
          '${reported.singleWhere((f) => f.origin == 'UpgradeScreen.switchToFree').error}',
          isNot(contains('SECRET')));
    });

    testWidgets("control: the same account's failed subscriptions read is said "
        '("Nothing was cancelled."), no drop recorded', (t) async {
      server.answers['client_plan:$_a'] = (200, 'self_guided');
      await open(t, const UpgradeScreen());
      await until(t, () => seen(find.text('Current')), "A's plan");
      server.answers['subscriptions:$_a'] = _down;
      await t.tap(find.text('Switch to Free'));
      await until(t, () => seen(find.textContaining('Nothing was cancelled.')),
          'said');
      expect(notShown(), isEmpty);
      expect(server.count('cancel-subscription'), 0);
    });

    // M14: the screen went with the account (the real AccountScope disposes
    // A's tree on the switch) while A's billing page was being opened.
    testWidgets("Manage billing: AccountScope takes A's screen away while A's "
        'billing page fails: recorded once as not shown, nothing for B',
        (t) async {
      await t.binding.setSurfaceSize(const Size(700, 3200));
      addTearDown(() => t.binding.setSurfaceSize(null));
      server.answers['client_plan:$_a'] = (200, 'self_guided');
      server.answers['client_plan:$_b'] = (200, 'free');
      server.answers['subscriptions:$_a'] = (200, [sub1]);
      await t.runAsync(() => signInAs(_a));
      await t.pumpWidget(const AccountScope(
          child: MaterialApp(home: ManageSubscriptionScreen())));
      await until(t, () => seen(find.text('Self-Guided')), "A's plan");
      await settle(t);
      server.answers['create-portal-session:$_a'] = _down;
      final gate = server.gates['create-portal-session:$_a'] = Completer();
      await t.tap(find.text('Manage billing & payment method'));
      await until(t, () => seen(find.text('Opening…')), 'A asked');
      await signIn(t, _b);
      await settle(t);
      expect(find.text('Opening…'), findsNothing,
          reason: "premise: A's screen went with A");
      gate.complete();
      await settle(t);
      saidNothing();
      expect(launched, isEmpty);
      expect(server.count('create-portal-session', _b), 0);
      recordedOnce('ManageSubscriptionScreen.openBilling', 'open billing');
    });

    // Round 3 (the round-2 follow-up): the Free tap's subscriptions read is
    // held, the account changes, and NOTHING else watches the subscriptions.
    // The tap awaited `mySubscriptionsProvider.future`, which the switch left
    // waiting for an answer nobody asks for: the flow never ended, its stop
    // was never recorded. Each test waits a
    // bounded 10 s of real time for the flow to end (a record), so on that
    // code it fails with "Timed out … waiting for the Free tap to end".
    Future<void> tapFreeWithReadHeld(WidgetTester t, Object answer) async {
      server.answers['client_plan:$_a'] = (200, 'self_guided');
      server.answers['client_plan:$_b'] = (200, 'free');
      server.answers['subscriptions:$_a'] = answer as (int, Object?);
      await open(t, const UpgradeScreen());
      await until(t, () => seen(find.text('Current')), "A's plan");
      expect(server.count('subscriptions'), 0,
          reason: 'premise: nothing on the screen reads the subscriptions');
      server.gates['subscriptions:$_a'] = Completer();
      await t.tap(find.text('Switch to Free'));
      await until(t, () => server.count('subscriptions', _a) == 1,
          "A's read is out");
    }

    Future<void> flowEnds(WidgetTester t) => pumpUntil(
        t, () => reported.isNotEmpty,
        what: 'the Free tap to end (a record of its stop)',
        timeout: const Duration(seconds: 10));

    for (final toB in [true, false]) {
      final label = toB ? 'B signs in' : 'A signs out';

      testWidgets("Upgrade, Switch to Free: $label while the tap's read is held "
          '(nothing else watching), then it answers: the flow ends, recorded '
          'once, nothing asked, sent or shown', (t) async {
        await tapFreeWithReadHeld(t, (200, [sub1]));
        await leaveFor(t, toB);
        await flowEnds(t);
        server.gates['subscriptions:$_a']!.complete();
        await settle(t);
        stoppedOnce('UpgradeScreen.switchToFree', 'switch to Free');
        expect(reported, hasLength(1), reason: '${records()}');
        expect(find.text('Switch to Free?'), findsNothing,
            reason: "A's confirmation is not put to B");
        saidNothing();
        expect(server.count('cancel-subscription'), 0);
        expect(server.writes, isEmpty);
        expect(server.log.where((l) => l.startsWith('subscriptions')),
            ['subscriptions:$_a'], reason: "A's one read; none made for B");
      });

      testWidgets("Upgrade, Switch to Free: $label while the tap's read is held "
          '(nothing else watching), then it fails: the flow ends, recorded '
          'once, nothing said to B or cancelled', (t) async {
        await tapFreeWithReadHeld(t, _down);
        await leaveFor(t, toB);
        await flowEnds(t);
        server.gates['subscriptions:$_a']!.complete();
        await settle(t);
        stoppedOnce('UpgradeScreen.switchToFree', 'switch to Free');
        expect(reported, hasLength(1), reason: '${records()}');
        expect('${reported.single.error}', isNot(contains('SECRET')));
        saidNothing();
        expect(find.textContaining('Nothing was cancelled'), findsNothing);
        expect(find.text('Switch to Free?'), findsNothing);
        expect(server.count('cancel-subscription'), 0);
        expect(server.writes, isEmpty);
      });
    }

    testWidgets("control: the same account (token refresh while the tap's read "
        'is held, nothing else watching): the confirmation is asked, the '
        'cancellation sent and said once, nothing recorded', (t) async {
      await tapFreeWithReadHeld(t, (200, [sub1]));
      server.answers['cancel-subscription'] = (200, {'ok': true});
      await t.runAsync(refreshSession);
      await t.pump();
      server.gates['subscriptions:$_a']!.complete();
      await until(t, () => seen(find.text('Switch to Free?')), 'the dialog');
      await settle(t);
      await t.tap(find.text('Switch to Free').last);
      await until(t, () => seen(find.text('Switched to the Free plan.')), 'said');
      expect(server.log.where((l) => l.startsWith('cancel-subscription')),
          ['cancel-subscription:$_a']);
      expect(reported, isEmpty, reason: '${records()}');
    });

    testWidgets("control: AccountScope, the same account's failed billing page "
        'is said, no drop recorded', (t) async {
      await t.binding.setSurfaceSize(const Size(700, 3200));
      addTearDown(() => t.binding.setSurfaceSize(null));
      server.answers['client_plan:$_a'] = (200, 'self_guided');
      server.answers['subscriptions:$_a'] = (200, [sub1]);
      await t.runAsync(() => signInAs(_a));
      await t.pumpWidget(const AccountScope(
          child: MaterialApp(home: ManageSubscriptionScreen())));
      await until(t, () => seen(find.text('Self-Guided')), "A's plan");
      await settle(t);
      server.answers['create-portal-session:$_a'] = _down;
      await t.tap(find.text('Manage billing & payment method'));
      await t.runAsync(refreshSession);
      await until(t, () => seen(find.byType(SnackBar)), 'said');
      expect(notShown(), isEmpty);
    });
  });
}
