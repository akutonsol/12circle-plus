import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/payments/domain/entitlements.dart';
import 'package:circle_fitness/features/payments/presentation/paywall_gate.dart';
import 'package:circle_fitness/features/profile/presentation/widgets/profile_load_failed_notice.dart';

// P0-FL-44 · a failed role read is never shown as a role fact — PaywallGate.
//
// The gate decided "coach" from
// `currentUserProfileProvider.valueOrNull?['role'] == 'coach'`. Since
// P0-FL-16 that provider rethrows, so a COACH whose profile read FAILED read
// as "not a coach", fell through to the client plan check and could be shown
// PaywallLocked — "<feature> is a Coach-Guided feature · Upgrade your plan" —
// a false statement about a coach's account.
//
// Now: profile loading → the gate's spinner; profile failed → the shared
// profile-failure notice with Try again (neither locked nor opened); only a
// successful read decides coach vs plan. The plan rules, the plan-error
// fail-open choice and PaywallLocked are unchanged.
//
// HOW TO SEE IT FAIL: `git checkout df35d5f --
// lib/features/payments/presentation/paywall_gate.dart` — the failed-read
// tests find PaywallLocked (or the child) and no notice.

const _child = Text('PAID FEATURE', key: Key('child'));

enum _P { ok, network, server, pending }

/// The profile read, controllable per test.
class _Profile {
  _Profile(this.role);
  String role;
  _P mode = _P.ok;
  int reads = 0;
  Completer<void>? gate;

  Future<Map<String, dynamic>?> read() async {
    reads++;
    if (gate != null) await gate!.future;
    switch (mode) {
      case _P.network:
        throw http.ClientException('Connection refused');
      case _P.server:
        throw const PostgrestException(message: 'refused', code: 'XX000');
      case _P.pending:
        return Completer<Map<String, dynamic>?>().future;
      case _P.ok:
        return <String, dynamic>{'role': role};
    }
  }
}

Widget _gate(_Profile profile, {required ClientPlan plan}) =>
    ProviderScope(
      overrides: [
        currentUserProfileProvider.overrideWith((ref) => profile.read()),
        clientPlanProvider.overrideWith((ref) async => plan),
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
  testWidgets('a coach whose profile read FAILED is not told to upgrade',
      (tester) async {
    final p = _Profile('coach')..mode = _P.server;
    await tester.pumpWidget(_gate(p, plan: ClientPlan.free));
    await tester.pumpAndSettle();

    expect(find.byType(PaywallLocked), findsNothing,
        reason: 'the read failed — "upgrade your plan" would be a false fact '
            'about a coach (the coach was read as a client on a free plan)');
    expect(find.byKey(const Key('child')), findsNothing,
        reason: 'not opened either: the role is unknown');
    expect(find.byType(ProfileLoadFailedNotice), findsOneWidget);
    expect(
        find.text("Couldn't load your profile — try again in a moment. "
            'If it keeps happening, contact support.'),
        findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    // The member can still leave: the gate keeps a named Back control.
    expect(find.bySemanticsLabel('Back'), findsOneWidget);
  });

  testWidgets('a network failure gets the connection hint, nothing else does',
      (tester) async {
    final p = _Profile('coach')..mode = _P.network;
    await tester.pumpWidget(_gate(p, plan: ClientPlan.free));
    await tester.pumpAndSettle();

    expect(
        find.text(
            "Couldn't load your profile — check your connection and try again."),
        findsOneWidget);
    expect(find.byType(PaywallLocked), findsNothing);
  });

  testWidgets('Try again re-reads once (busy-aware), then a coach is let in',
      (tester) async {
    final p = _Profile('coach')..mode = _P.server;
    await tester.pumpWidget(_gate(p, plan: ClientPlan.free));
    await tester.pumpAndSettle();
    expect(p.reads, 1);

    // Hold the re-read in flight and tap twice.
    p
      ..mode = _P.ok
      ..gate = Completer<void>();
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(find.text('Loading…'), findsOneWidget,
        reason: 'busy while the re-read is in flight');
    await tester.tap(find.text('Loading…'), warnIfMissed: false);
    await tester.pump();
    expect(p.reads, 2, reason: 'a second tap while busy must not re-fire');

    p.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('child')), findsOneWidget);
    expect(find.byType(PaywallLocked), findsNothing);
  });

  testWidgets('Try again is at least 44px tall', (tester) async {
    final p = _Profile('coach')..mode = _P.server;
    await tester.pumpWidget(_gate(p, plan: ClientPlan.free));
    await tester.pumpAndSettle();
    final button = find.ancestor(
        of: find.text('Try again'), matching: find.byType(TextButton));
    expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
  });

  testWidgets('while the profile is LOADING: the spinner, not locked or open',
      (tester) async {
    final p = _Profile('coach')..mode = _P.pending;
    await tester.pumpWidget(_gate(p, plan: ClientPlan.free));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(PaywallLocked), findsNothing,
        reason: 'a coach still loading was read as a free client and locked');
    expect(find.byKey(const Key('child')), findsNothing);
  });

  testWidgets('a successful coach read opens the gate (no plan needed)',
      (tester) async {
    await tester.pumpWidget(_gate(_Profile('coach'), plan: ClientPlan.free));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('child')), findsOneWidget);
  });

  group('a successful client read keeps the plan rules', () {
    testWidgets('free → locked', (tester) async {
      await tester.pumpWidget(_gate(_Profile('client'), plan: ClientPlan.free));
      await tester.pumpAndSettle();
      expect(find.byType(PaywallLocked), findsOneWidget);
    });

    testWidgets('self-guided (under tier) → locked', (tester) async {
      await tester
          .pumpWidget(_gate(_Profile('client'), plan: ClientPlan.selfGuided));
      await tester.pumpAndSettle();
      expect(find.byType(PaywallLocked), findsOneWidget);
    });

    testWidgets('coach-guided → open', (tester) async {
      await tester
          .pumpWidget(_gate(_Profile('client'), plan: ClientPlan.coachGuided));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('child')), findsOneWidget);
    });
  });

  testWidgets(
      'a refresh that fails AFTER a successful read keeps the known role '
      '(Riverpod keeps the previous value) — a coach stays in', (tester) async {
    final p = _Profile('coach');
    late WidgetRef captured;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProfileProvider.overrideWith((ref) => p.read()),
        clientPlanProvider.overrideWith((ref) async => ClientPlan.free),
      ],
      child: MaterialApp(
        home: Consumer(builder: (context, ref, _) {
          captured = ref;
          return const PaywallGate(
            required: ClientPlan.coachGuided,
            featureName: 'Action Items',
            child: _child,
          );
        }),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('child')), findsOneWidget);

    p.mode = _P.server;
    captured.invalidate(currentUserProfileProvider);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('child')), findsOneWidget,
        reason: 'the role came from a real read; a later failed refresh does '
            'not make it unknown');
    expect(find.byType(PaywallLocked), findsNothing);
  });
}
