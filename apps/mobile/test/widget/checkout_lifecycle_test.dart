import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/features/coach/domain/coach_provider.dart';
import 'package:circle_fitness/features/payments/data/payment_service.dart';
import 'package:circle_fitness/features/payments/domain/entitlements.dart';
import 'package:circle_fitness/features/payments/domain/payment_provider.dart';
import 'package:circle_fitness/features/payments/presentation/upgrade_screen.dart';

/// The checkout lifecycle, under the owner's direction of 2026-10-12:
/// **do not create a new checkout session after the client navigates away from
/// the upgrade flow** — and equally, do not abandon or duplicate one that was
/// already created.
///
/// ── WHY THE FIXTURE LOOKS LIKE THIS ────────────────────────────────────────
/// The async gap only exists on ONE path. `_onCta` awaits
/// `changeMembership` only when `onMembership` is true — that is, when the
/// client is ALREADY on `selfGuided` or `aiGuided`. A free → paid tap skips
/// that call entirely and reaches checkout with no gap at all, so a test
/// starting from Free would pass whether the guard existed or not.
///
/// Hence: current = **selfGuided**, target = **aiGuided**, which labels its CTA
/// "Upgrade to AI-Guided" and is the only shape that exercises the window.
class _FakePayments implements PaymentService {
  _FakePayments({this.changeGate, this.checkoutGate, this.checkoutResult = true});

  /// When supplied, `changeMembership` hangs on this until the test completes
  /// it — which is what lets the widget be disposed *mid-await*.
  final Completer<String>? changeGate;
  final Completer<bool>? checkoutGate;
  final bool checkoutResult;

  int changeCalls = 0;
  int checkoutCalls = 0;

  @override
  Future<String> changeMembership(String newKind) {
    changeCalls++;
    return changeGate?.future ?? Future.value('needs_checkout');
  }

  @override
  Future<bool> startCheckout({
    required String kind,
    String? coachId,
    String? eventId,
    String? packageId,
    String? tier,
  }) {
    checkoutCalls++;
    return checkoutGate?.future ?? Future.value(checkoutResult);
  }

  @override
  Future<List<Map<String, dynamic>>> getMySubscriptions() async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The scope is built ONCE with a fixed override list and only its child
/// changes. Riverpod asserts on a changed override COUNT between rebuilds
/// ("overrides cannot be removed/added, they can only be updated"), so swapping
/// in a bare `ProviderScope` to simulate leaving the screen throws before any
/// assertion runs. Keeping the scope and replacing the child is also the truer
/// simulation: navigating away disposes the screen, it does not tear down the
/// app's providers.
Widget _scope(_FakePayments fake, Widget child) => ProviderScope(
      overrides: [
        paymentServiceProvider.overrideWithValue(fake),
        clientPlanProvider.overrideWith((ref) async => ClientPlan.selfGuided),
        mySubscriptionsProvider.overrideWith((ref) async => const []),
        membershipTierProvider.overrideWith((ref) async => null),
        assignedCoachProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp(home: child),
    );

Widget _zone(_FakePayments fake) => _scope(fake, const UpgradeScreen());

/// Leaving the upgrade flow: same providers, different screen.
Widget _elsewhere(_FakePayments fake) =>
    _scope(fake, const Scaffold(body: Text('gone')));

Future<void> _tapUpgrade(WidgetTester tester, _FakePayments fake) async {
  // A TALL surface, deliberately. At the default 800px the AI-Guided card sits
  // below the fold and is never built, so `find.text` returns nothing and every
  // assertion below fails for a reason that has nothing to do with checkout.
  tester.view.physicalSize = const Size(1200, 3600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_zone(fake));
  await tester.pumpAndSettle();
  final cta = find.text('Upgrade to AI-Guided');
  expect(cta, findsOneWidget,
      reason: 'the selfGuided → aiGuided CTA is the only path with an async gap');
  await tester.tap(cta);
  await tester.pump();
}

void main() {
  group('checkout lifecycle · no new session after the client leaves', () {
    testWidgets('NAVIGATION BEFORE COMPLETION — the client leaves while '
        'changeMembership is in flight, so no session is ever created',
        (tester) async {
      final gate = Completer<String>();
      final fake = _FakePayments(changeGate: gate);
      await _tapUpgrade(tester, fake);

      expect(fake.changeCalls, 1, reason: 'the membership change was attempted');
      expect(fake.checkoutCalls, 0, reason: 'nothing has reached checkout yet');

      // The client navigates away WHILE the change is still pending.
      await tester.pumpWidget(_elsewhere(fake));
      await tester.pump();

      // Only now does the change resolve, asking for a checkout.
      gate.complete('needs_checkout');
      await tester.pump();
      await tester.pumpAndSettle();

      expect(fake.checkoutCalls, 0,
          reason: 'THE POINT: create-checkout must not mint a session for '
              'someone who already left. Without the `!mounted` guard before '
              'launchCheckout, this is 1.');
    });

    testWidgets('COMPLETION AFTER DISPOSAL — a session already in flight is '
        'allowed to finish, not abandoned', (tester) async {
      final checkoutGate = Completer<bool>();
      final fake = _FakePayments(checkoutGate: checkoutGate);
      await _tapUpgrade(tester, fake);
      // `pump`, NOT `pumpAndSettle`. `startCheckout` is deliberately hanging on
      // an open gate here, so the CTA's loading indicator animates forever and
      // `pumpAndSettle` times out instead of ever returning. Settling is only
      // safe once the gate is closed.
      await tester.pump();

      expect(fake.checkoutCalls, 1,
          reason: 'the client was present, so the session was legitimately started');

      // Now they leave — mid-session-creation.
      await tester.pumpWidget(_elsewhere(fake));
      await tester.pump();

      // The server-side session completes. It must NOT be cancelled or retried.
      checkoutGate.complete(true);
      await tester.pump();
      await tester.pump();

      expect(fake.checkoutCalls, 1,
          reason: 'exactly one — not abandoned, and not duplicated by a retry');
      expect(tester.takeException(), isNull,
          reason: 'the post-await setState is guarded, so disposal is not an error');
    });

    testWidgets('REQUEST FAILURE — checkout declines and the client is told',
        (tester) async {
      final fake = _FakePayments(checkoutResult: false);
      await _tapUpgrade(tester, fake);
      await tester.pumpAndSettle();

      expect(fake.checkoutCalls, 1);
      expect(find.text('Could not start checkout. Try again.'), findsOneWidget,
          reason: 'a failure the client is present for must surface');
    });

    testWidgets('SUCCESS — one session, and no error shown', (tester) async {
      final fake = _FakePayments(checkoutResult: true);
      await _tapUpgrade(tester, fake);
      await tester.pumpAndSettle();

      expect(fake.changeCalls, 1);
      expect(fake.checkoutCalls, 1, reason: 'exactly one session, never two');
      expect(find.text('Could not start checkout. Try again.'), findsNothing);
    });
  });
}
