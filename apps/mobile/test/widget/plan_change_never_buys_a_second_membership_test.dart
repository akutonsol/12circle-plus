import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/features/coach/domain/coach_provider.dart';
import 'package:circle_fitness/features/payments/data/payment_service.dart';
import 'package:circle_fitness/features/payments/domain/entitlements.dart';
import 'package:circle_fitness/features/payments/domain/payment_provider.dart';
import 'package:circle_fitness/features/payments/presentation/upgrade_screen.dart';

// Changing a membership tier must never end in a SECOND membership.
//
// The Upgrade screen asked update-subscription to swap the price in place, and
// on anything but 'changed' fell through to a brand-new checkout:
//   * on 'error' -- including the case where the swap went through at Stripe and
//     only the reply was lost -- the client was sent to buy the plan again;
//   * a member whose membership is failing payment (past_due) got
//     'needs_checkout' from the server and bought a second one while Stripe kept
//     retrying the first;
//   * a member shown as Coach-Guided (they also have a coach) skipped the swap
//     entirely and went straight to checkout for a second membership.
// Each is two live subscriptions, both billed.
//
// HOW TO SEE IT FAIL: on main's upgrade_screen.dart all three behaviour tests
// below record a checkout call.

class _FakePayments implements PaymentService {
  _FakePayments(this.changeResult);
  final String changeResult;
  int changeCalls = 0;
  int checkoutCalls = 0;

  @override
  Future<String> changeMembership(String newKind) async {
    changeCalls++;
    return changeResult;
  }

  @override
  Future<bool> startCheckout({
    required String kind,
    String? coachId,
    String? eventId,
    String? packageId,
    String? tier,
  }) async {
    checkoutCalls++;
    return true;
  }

  @override
  Future<List<Map<String, dynamic>>> getMySubscriptions() async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_FakePayments> _tap(WidgetTester tester,
    {required String changeResult, required ClientPlan shown, required String cta}) async {
  tester.view.physicalSize = const Size(1200, 3600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final fake = _FakePayments(changeResult);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      paymentServiceProvider.overrideWithValue(fake),
      clientPlanProvider.overrideWith((ref) async => shown),
      mySubscriptionsProvider.overrideWith((ref) async => const []),
      membershipTierProvider.overrideWith((ref) async => null),
      assignedCoachProvider.overrideWith((ref) async => null),
    ],
    child: const MaterialApp(home: UpgradeScreen()),
  ));
  await tester.pumpAndSettle();
  final button = find.text(cta);
  expect(button, findsOneWidget);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  testWidgets('a failed plan change is reported and does NOT start a new checkout',
      (tester) async {
    final fake = await _tap(tester,
        changeResult: 'error', shown: ClientPlan.selfGuided, cta: 'Upgrade to AI-Guided');
    expect(fake.checkoutCalls, 0,
        reason: 'THE defect: an error fell through to a second membership checkout');
    expect(find.textContaining("Couldn't change your plan"), findsOneWidget);
  });

  testWidgets('a membership with a payment problem is told to fix it, not to buy again',
      (tester) async {
    final fake = await _tap(tester,
        changeResult: 'payment_issue', shown: ClientPlan.selfGuided, cta: 'Upgrade to AI-Guided');
    expect(fake.checkoutCalls, 0,
        reason: 'a past_due membership is still billing; a new checkout is a second one');
    expect(find.textContaining('payment problem'), findsOneWidget);
  });

  testWidgets('a member shown as Coach-Guided still changes the membership in place',
      (tester) async {
    final fake = await _tap(tester,
        changeResult: 'changed', shown: ClientPlan.coachGuided, cta: 'Switch to AI-Guided');
    expect(fake.changeCalls, 1,
        reason: 'the in-place change was skipped because the screen showed Coach-Guided');
    expect(fake.checkoutCalls, 0, reason: 'a second membership was bought instead');
  });

  testWidgets('no membership to change → checkout, exactly once (positive control)',
      (tester) async {
    final fake = await _tap(tester,
        changeResult: 'needs_checkout', shown: ClientPlan.free, cta: 'Upgrade to AI-Guided');
    expect(fake.changeCalls, 1);
    expect(fake.checkoutCalls, 1);
  });
}
