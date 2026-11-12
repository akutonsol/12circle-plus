import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/features/coach/domain/coach_provider.dart';
import 'package:circle_fitness/features/payments/data/payment_service.dart';
import 'package:circle_fitness/features/payments/domain/entitlements.dart';
import 'package:circle_fitness/features/payments/domain/payment_provider.dart';
import 'package:circle_fitness/features/payments/presentation/upgrade_screen.dart';

// /upgrade's "Switch to Free" cancels every active platform membership.
//
//   * It found them with `ref.read(mySubscriptionsProvider).valueOrNull ?? []`,
//     and nothing on /upgrade watches that provider. Unless the client had
//     opened /manage-subscription earlier in the session, the read had not
//     happened: the list was empty, and the button returned without a word —
//     no confirmation, no cancellation, no message.
//   * It ignored `cancelSubscription`'s answer — false on any failure — and
//     said "Switched to the Free plan." whatever happened: a client whose
//     cancellation failed was told they were on Free, and was still billed.
//
// The same action on /manage-subscription (`_cancelPlan`) already reports its
// outcome — "Could not cancel. Try again." — and this follows it.

const _switched = 'Switched to the Free plan.';
const _failed = 'Could not cancel. Try again.';

class _FakePayments implements PaymentService {
  _FakePayments({required this.cancels});
  final bool cancels;
  final cancelled = <String>[];

  @override
  Future<bool> cancelSubscription(String subscriptionRowId) async {
    cancelled.add(subscriptionRowId);
    return cancels;
  }

  @override
  Future<List<Map<String, dynamic>>> getMySubscriptions() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// [primed]: the subscriptions were already read this session — as after a
/// visit to /manage-subscription — which is the only way the old code worked.
Future<void> _switchToFree(WidgetTester tester, _FakePayments fake,
    {bool primed = false}) async {
  tester.view.physicalSize = const Size(1200, 3600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(overrides: [
    paymentServiceProvider.overrideWithValue(fake),
    clientPlanProvider.overrideWith((ref) async => ClientPlan.selfGuided),
    mySubscriptionsProvider.overrideWith((ref) async => const [
          {'id': 'sub-m', 'kind': 'self_guided', 'status': 'active'},
        ]),
    membershipTierProvider.overrideWith((ref) async => 'self_guided'),
    assignedCoachProvider.overrideWith((ref) async => null),
  ]);
  addTearDown(container.dispose);
  if (primed) {
    container.listen(mySubscriptionsProvider, (_, __) {});
    await container.read(mySubscriptionsProvider.future);
  }

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: UpgradeScreen()),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Switch to Free'));
  await tester.pumpAndSettle();
  // The confirm dialog's own "Switch to Free".
  await tester.tap(find.text('Switch to Free').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the first tap asks, and then cancels', (tester) async {
    final fake = _FakePayments(cancels: true);
    await _switchToFree(tester, fake);

    expect(fake.cancelled, ['sub-m'],
        reason: 'THE defect: the subscriptions had never been read on this '
            'screen, so the tap found no membership and did nothing');
  });

  testWidgets('a failed cancellation is not "Switched to the Free plan"', (tester) async {
    final fake = _FakePayments(cancels: false);
    await _switchToFree(tester, fake, primed: true);

    expect(fake.cancelled, ['sub-m'], reason: 'premise: the cancellation was attempted');
    expect(find.text(_switched), findsNothing,
        reason: 'THE defect: the membership is still active, and still billed');
    expect(find.text(_failed), findsOneWidget);
  });

  testWidgets('control: a cancellation that worked says so', (tester) async {
    final fake = _FakePayments(cancels: true);
    await _switchToFree(tester, fake, primed: true);

    expect(find.text(_switched), findsOneWidget);
    expect(find.text(_failed), findsNothing);
  });
}
