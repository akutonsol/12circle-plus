import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/features/payments/data/payment_service.dart';
import 'package:circle_fitness/features/payments/domain/entitlements.dart';
import 'package:circle_fitness/features/payments/domain/payment_provider.dart';
import 'package:circle_fitness/features/payments/presentation/paywall_gate.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';

// FIT-021 · the entitlement gate said "fail open" and the app failed closed.
//
// `PaywallGate` states its own policy for a failed resolve:
//
//     error: (_, __) => child, // fail open rather than lock a paying user out
//
// That arm could never run. `PaymentService.clientPlan()` caught the failure
// and returned 'free':
//
//     } catch (_) { return 'free'; }
//
// so `clientPlanProvider` was ALWAYS `AsyncData(ClientPlan.free)`. The gate's
// earlier `plan != null` branch took the early return, `atLeast(coachGuided)`
// was false, and a paying Coach-Guided member whose entitlement read failed
// was shown `PaywallLocked` for a feature they had paid for.
//
// The service no longer catches, so the error reaches the provider and the
// policy the gate already wrote takes effect. This does NOT widen a
// server-side boundary: the gate decides whether a screen is OFFERED, and
// every read inside it is still filtered by RLS.

const _child = Text('PAID FEATURE', key: Key('child'));

Widget _gate({
  required AsyncValue<ClientPlan> plan,
  String role = 'client',
}) =>
    ProviderScope(
      overrides: [
        currentUserProfileProvider.overrideWith(
            (ref) async => <String, dynamic>{'role': role}),
        clientPlanProvider.overrideWith((ref) async => switch (plan) {
              AsyncData(:final value) => value,
              _ => throw Exception('entitlement read failed'),
            }),
      ],
      child: const MaterialApp(
        home: PaywallGate(
          required: ClientPlan.coachGuided,
          featureName: 'Action Items',
          child: _child,
        ),
      ),
    );

void main() {
  testWidgets('a FAILED entitlement read opens the gate, it does not lock it',
      (tester) async {
    await tester.pumpWidget(_gate(
        plan: AsyncError(Exception('boom'), StackTrace.empty)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('child')), findsOneWidget,
        reason: 'the gate says "fail open rather than lock a paying user out"; '
            'with clientPlan() swallowing into free, a paying Coach-Guided '
            'member saw PaywallLocked instead');
    expect(find.byType(PaywallLocked), findsNothing);
  });

  testWidgets('a real "free" still locks — the fix does not open the gate',
      (tester) async {
    await tester.pumpWidget(_gate(plan: const AsyncData(ClientPlan.free)));
    await tester.pumpAndSettle();

    expect(find.byType(PaywallLocked), findsOneWidget,
        reason: 'a successful read saying free is an ANSWER, and must still '
            'lock — otherwise this repair would have removed the paywall');
    expect(find.byKey(const Key('child')), findsNothing);
  });

  testWidgets('a paying member is let through', (tester) async {
    await tester.pumpWidget(
        _gate(plan: const AsyncData(ClientPlan.coachGuided)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('child')), findsOneWidget);
  });

  testWidgets('an under-tier paying member is still locked', (tester) async {
    await tester.pumpWidget(
        _gate(plan: const AsyncData(ClientPlan.selfGuided)));
    await tester.pumpAndSettle();

    expect(find.byType(PaywallLocked), findsOneWidget);
  });

  testWidgets('a coach is never paywalled, even on a failed read',
      (tester) async {
    await tester.pumpWidget(_gate(
      plan: AsyncError(Exception('boom'), StackTrace.empty),
      role: 'coach',
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('child')), findsOneWidget);
  });

  // ── The layer the tests above do not reach ───────────────────────────────
  //
  // Every test above overrides `clientPlanProvider` directly, so they prove
  // what the GATE does with an AsyncError — not that anything produces one.
  // Restoring `catch (_) { return 'free'; }` in the service left all five
  // passing, which is the same two-layer blindness this commit is about.
  // These drive the real provider over a failing service.
  group('the failure survives the service, not just the gate', () {
    test('a throwing clientPlan makes the provider an AsyncError', () async {
      final container = ProviderContainer(overrides: [
        paymentServiceProvider.overrideWithValue(_ThrowingPayments()),
      ]);
      addTearDown(container.dispose);

      await expectLater(
        container.read(clientPlanProvider.future),
        throwsA(isA<Exception>()),
        reason: 'the service swallowed into ClientPlan.free, so the gate never '
            'saw a failure and locked a paying member out',
      );
    });

    // [SOURCE] — and this is why it is needed.
    //
    // The two tests around it use a FAKE PaymentService, so neither can see
    // what the real `clientPlan()` does with an exception: restoring
    // `catch (_) { return 'free'; }` in the real method left every other test
    // in this file green. `_db` is `Supabase.instance.client` and is not
    // injectable, so the real catch cannot be driven in a test at all.
    //
    // A source assertion is the only thing that closes this, and it is worth
    // what a source assertion is worth.
    test('[SOURCE] the real clientPlan does not swallow its failure', () {
      final src = File('lib/features/payments/data/payment_service.dart')
          .readAsStringSync();
      final start = src.indexOf('Future<String?> clientPlan() async {');
      expect(start, greaterThan(0), reason: 'clientPlan has moved');
      final body = src.substring(start, src.indexOf('\n  }', start));

      expect(body.contains('catch'), isFalse,
          reason: "clientPlan is catching again. The gate's "
              '"fail open rather than lock a paying user out" arm cannot run, '
              'and a paying Coach-Guided member whose entitlement read fails '
              'is shown PaywallLocked for a feature they paid for.');
      // A non-String from a SUCCESSFUL call is still 'free' — an answer, not a
      // failure — and that must stay.
      expect(body, contains("res is String ? res : 'free'"));
    });

    test('a successful read still resolves to a plan', () async {
      final container = ProviderContainer(overrides: [
        paymentServiceProvider.overrideWithValue(_CoachGuidedPayments()),
      ]);
      addTearDown(container.dispose);

      expect(await container.read(clientPlanProvider.future),
          ClientPlan.coachGuided);
    });
  });
}

class _ThrowingPayments implements PaymentService {
  @override
  Future<String?> clientPlan() async => throw Exception('entitlement read failed');
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _CoachGuidedPayments implements PaymentService {
  @override
  Future<String?> clientPlan() async => 'coach_guided';
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}
