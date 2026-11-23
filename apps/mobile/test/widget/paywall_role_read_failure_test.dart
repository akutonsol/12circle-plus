import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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
// Review round (SEC-F1/F2): Riverpod keeps the previous value through a
// re-read, so after coach A signs out and member B signs in, a FAILED read for
// B still `hasValue` — A's coach role, and B walked past the paywall. A value
// now counts only when it was read for the member signed in now (`id` ==
// current user id). (UX-F1): Back / Not now pop when there is somewhere to
// go, else go to Profile — `context.go` leaves nothing to pop.
//
// HOW TO SEE IT FAIL: `git checkout df35d5f --
// lib/features/payments/presentation/paywall_gate.dart` — the failed-read
// tests find PaywallLocked (or the child) and no notice; `git checkout HEAD~1
// -- …` for the review-round tests.

const _child = Text('PAID FEATURE', key: Key('child'));

enum _P { ok, network, server, pending }

User _user(String id) => User(
      id: id,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-11-01T00:00:00Z',
    );

final _signedIn = StateProvider<User?>((ref) => _user('user-a'));

/// The profile read, controllable per test; each member has their own role.
class _Profile {
  _Profile(String role) : roles = {'user-a': role};
  final Map<String, String> roles;
  _P mode = _P.ok;
  int reads = 0;
  Completer<void>? gate;

  /// Per-member overrides of [mode]; a member without one uses [mode].
  final Map<String, _P> modes = {};

  /// Per-member response delay (fake-async clock): a slow server.
  final Map<String, Duration> delays = {};

  /// Members whose read actually produced a row, in arrival order — proves a
  /// late response really arrived (and was then not applied).
  final List<String> answered = [];

  Future<Map<String, dynamic>?> read(String uid) async {
    reads++;
    final delay = delays[uid];
    if (delay != null) await Future<void>.delayed(delay);
    if (gate != null) await gate!.future;
    switch (modes[uid] ?? mode) {
      case _P.network:
        throw http.ClientException('Connection refused');
      case _P.server:
        throw const PostgrestException(message: 'refused', code: 'XX000');
      case _P.pending:
        return Completer<Map<String, dynamic>?>().future;
      case _P.ok:
        answered.add(uid);
        return <String, dynamic>{'id': uid, 'role': roles[uid]};
    }
  }
}

/// The signed-in member (changeable via [_signedIn]) and their profile read.
List<Override> _overrides(_Profile profile, ClientPlan plan) => [
      currentUserProvider.overrideWith((ref) => ref.watch(_signedIn)),
      currentUserProfileProvider.overrideWith((ref) async {
        final u = ref.watch(currentUserProvider);
        if (u == null) return null;
        return profile.read(u.id);
      }),
      clientPlanProvider.overrideWith((ref) async => plan),
    ];

Widget _gate(_Profile profile, {required ClientPlan plan}) => ProviderScope(
      overrides: _overrides(profile, plan),
      child: const MaterialApp(
        home: PaywallGate(
          required: ClientPlan.coachGuided,
          featureName: 'Action Items',
          child: _child,
        ),
      ),
    );

/// The gate as the app reaches it: a GoRouter route entered with
/// `context.go` (nothing beneath to pop), plus `/profile`.
Future<GoRouter> _routedGate(WidgetTester tester, _Profile profile,
    {required ClientPlan plan, bool pushed = false}) async {
  final router = GoRouter(initialLocation: pushed ? '/home' : '/gated', routes: [
    GoRoute(
        path: '/home',
        builder: (context, _) => Scaffold(
            body: TextButton(
                onPressed: () => context.push('/gated'),
                child: const Text('HOME')))),
    GoRoute(
        path: '/gated',
        builder: (_, __) => const PaywallGate(
              required: ClientPlan.coachGuided,
              featureName: 'Action Items',
              child: _child,
            )),
    GoRoute(
        path: '/profile',
        builder: (_, __) => const Scaffold(body: Text('PROFILE PAGE'))),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: _overrides(profile, plan),
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  if (pushed) {
    await tester.tap(find.text('HOME'));
    await tester.pumpAndSettle();
  }
  return router;
}

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
      overrides: _overrides(p, ClientPlan.free),
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
    expect(captured.read(currentUserProfileProvider).hasError, isTrue,
        reason: 'precondition: the refresh really failed');
    expect(find.byKey(const Key('child')), findsOneWidget,
        reason: 'the role came from a real read; a later failed refresh does '
            'not make it unknown');
    expect(find.byType(PaywallLocked), findsNothing);
  });

  // ── Review round ───────────────────────────────────────────────────────────

  testWidgets(
      "SEC-F1/F2 · coach A signs out, member B signs in and B's read FAILS: "
      'no coach bypass — B sees the failure state', (tester) async {
    final p = _Profile('coach')..roles['user-b'] = 'client';
    late WidgetRef captured;
    await tester.pumpWidget(ProviderScope(
      overrides: _overrides(p, ClientPlan.free),
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
    expect(find.byKey(const Key('child')), findsOneWidget,
        reason: 'A is a coach: always in');

    captured.read(_signedIn.notifier).state = null; // sign out
    await tester.pumpAndSettle();
    p.mode = _P.server;
    captured.read(_signedIn.notifier).state = _user('user-b'); // B signs in
    await tester.pumpAndSettle();

    expect(captured.read(currentUserProfileProvider).hasValue, isTrue,
        reason: 'precondition: Riverpod kept a previous value through the '
            'failed re-read — the leak the fix closes');
    expect(find.byKey(const Key('child')), findsNothing,
        reason: "A's coach role must not let B past the paywall");
    expect(find.byType(PaywallLocked), findsNothing,
        reason: "B's role is unknown — not a fact either way");
    expect(find.byType(ProfileLoadFailedNotice), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets(
      "SEC-F1/F2 · A's coach value does not open the gate while B's read is "
      'in flight', (tester) async {
    final p = _Profile('coach')..roles['user-b'] = 'client';
    late WidgetRef captured;
    await tester.pumpWidget(ProviderScope(
      overrides: _overrides(p, ClientPlan.free),
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

    p.mode = _P.pending;
    captured.read(_signedIn.notifier).state = _user('user-b');
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('child')), findsNothing);
    expect(find.byType(PaywallLocked), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  group('UX-F1 · Back never strands the member', () {
    testWidgets('failure state reached by context.go: Back goes to Profile',
        (tester) async {
      final p = _Profile('coach')..mode = _P.server;
      await _routedGate(tester, p, plan: ClientPlan.free);
      expect(find.byType(ProfileLoadFailedNotice), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      expect(find.text('PROFILE PAGE'), findsOneWidget,
          reason: 'nothing to pop after context.go — Back must still leave');
    });

    testWidgets('failure state pushed over a screen: Back pops to it',
        (tester) async {
      final p = _Profile('coach')..mode = _P.server;
      await _routedGate(tester, p, plan: ClientPlan.free, pushed: true);
      expect(find.byType(ProfileLoadFailedNotice), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('PROFILE PAGE'), findsNothing);
    });

    testWidgets('locked reached by context.go: Back and Not now go to Profile',
        (tester) async {
      for (final control in ['Back', 'Not now']) {
        await _routedGate(tester, _Profile('client'), plan: ClientPlan.free);
        expect(find.byType(PaywallLocked), findsOneWidget);
        await tester.tap(control == 'Back'
            ? find.bySemanticsLabel('Back')
            : find.text('Not now'));
        await tester.pumpAndSettle();
        expect(find.text('PROFILE PAGE'), findsOneWidget,
            reason: '"$control" was a no-op after context.go');
      }
    });

    testWidgets('locked pushed over a screen: Back pops to it',
        (tester) async {
      await _routedGate(tester, _Profile('client'),
          plan: ClientPlan.free, pushed: true);
      expect(find.byType(PaywallLocked), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
    });
  });

  // ── Test-only round: member switches in both directions ───────────────────
  //
  // Two ways the sign-out can land, and they are protected by different lines
  // of `confirmedRoleRead`:
  //  * OBSERVED sign-out (a frame passes while signed out): the profile
  //    provider answers `null` for nobody, so B's read starts from a `null`
  //    value — the "null held over a re-read" guard is what stops it.
  //  * SAME-FRAME switch (sign-out and sign-in land before one rebuild, e.g. an
  //    account switch): B's read starts from A's ROW — only the SEC-F1 `id`
  //    check stops A's role being applied to B.
  // Each scenario runs both ways. Every client here is on the FREE plan, so
  // "the gate opened" can only mean a coach role was applied.

  Future<void> settle(WidgetTester tester) async {
    // The spinner animates forever: pump, never settle.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// The gate with a switchable member; the plan is per member (signed out →
  /// free), as `client_plan()` answers for `auth.uid()`.
  Future<WidgetRef> pumpSwitchable(WidgetTester tester, _Profile p,
      {Map<String, ClientPlan> plans = const {}}) async {
    late WidgetRef captured;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => ref.watch(_signedIn)),
        currentUserProfileProvider.overrideWith((ref) async {
          final u = ref.watch(currentUserProvider);
          if (u == null) return null;
          return p.read(u.id);
        }),
        clientPlanProvider.overrideWith((ref) async =>
            plans[ref.watch(currentUserProvider)?.id] ?? ClientPlan.free),
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
    await settle(tester);
    return captured;
  }

  Future<void> switchTo(WidgetTester tester, WidgetRef ref, String uid,
      {required bool observeSignOut}) async {
    ref.read(_signedIn.notifier).state = null; // A signs out
    if (observeSignOut) await settle(tester);
    ref.read(_signedIn.notifier).state = _user(uid); // B signs in
    await settle(tester);
  }

  /// A coach is let in; a client on the free plan is locked.
  void expectRole(String role) {
    if (role == 'coach') {
      expect(find.byKey(const Key('child')), findsOneWidget,
          reason: 'a confirmed coach is always in');
      expect(find.byType(PaywallLocked), findsNothing);
    } else {
      expect(find.byKey(const Key('child')), findsNothing,
          reason: 'a free client must not get a coach bypass');
      expect(find.byType(PaywallLocked), findsOneWidget,
          reason: "the client's own (free) plan applies");
    }
    expect(find.byType(ProfileLoadFailedNotice), findsNothing);
  }

  void expectFailure() {
    expect(find.byKey(const Key('child')), findsNothing,
        reason: 'unknown role: not opened');
    expect(find.byType(PaywallLocked), findsNothing,
        reason: 'unknown role: not locked as a client either');
    expect(find.byType(ProfileLoadFailedNotice), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  }

  void expectPending() {
    expect(find.byKey(const Key('child')), findsNothing);
    expect(find.byType(PaywallLocked), findsNothing);
    expect(find.byType(ProfileLoadFailedNotice), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  }

  for (final observe in [true, false]) {
    final how = observe ? 'sign-out observed' : 'same-frame switch';

    // 1 · CLIENT → COACH
    group('CLIENT A → COACH B ($how)', () {
      _Profile clientThenCoach() =>
          _Profile('client')..roles['user-b'] = 'coach';

      testWidgets("1(a) B's read FAILS: the failure state — never "
          'PaywallLocked-as-client for B', (tester) async {
        final p = clientThenCoach()..modes['user-b'] = _P.server;
        final ref = await pumpSwitchable(tester, p);
        expectRole('client');

        await switchTo(tester, ref, 'user-b', observeSignOut: observe);
        expect(ref.read(currentUserProfileProvider).hasError, isTrue,
            reason: "precondition: B's read really failed");
        expectFailure();
      });

      testWidgets("1(b) B's read IN FLIGHT: the spinner — never A's client "
          'role applied to B', (tester) async {
        final p = clientThenCoach()..modes['user-b'] = _P.pending;
        final ref = await pumpSwitchable(tester, p);
        expectRole('client');

        await switchTo(tester, ref, 'user-b', observeSignOut: observe);
        expectPending();
      });

      testWidgets("1(c) B's read then SUCCEEDS: the coach passes the paywall",
          (tester) async {
        final p = clientThenCoach()
          ..delays['user-b'] = const Duration(seconds: 2);
        final ref = await pumpSwitchable(tester, p);
        expectRole('client');

        await switchTo(tester, ref, 'user-b', observeSignOut: observe);
        expectPending(); // B's read is still on the wire
        await tester.pump(const Duration(seconds: 2));
        await settle(tester);
        expectRole('coach');
      });
    });

    // 2 · COACH → CLIENT, success path: B's own plan applies.
    group('2 · COACH A → CLIENT B ($how), B\'s read succeeds', () {
      testWidgets('B on the free plan is locked — no coach bypass from A',
          (tester) async {
        final p = _Profile('coach')..roles['user-b'] = 'client';
        final ref = await pumpSwitchable(tester, p);
        expectRole('coach');

        await switchTo(tester, ref, 'user-b', observeSignOut: observe);
        expectRole('client');
      });

      testWidgets("B on coach-guided is let in by B's plan", (tester) async {
        final p = _Profile('coach')..roles['user-b'] = 'client';
        final ref = await pumpSwitchable(tester, p,
            plans: const {'user-b': ClientPlan.coachGuided});
        expectRole('coach');

        await switchTo(tester, ref, 'user-b', observeSignOut: observe);
        expect(find.byKey(const Key('child')), findsOneWidget);
        expect(find.byType(PaywallLocked), findsNothing);
        expect(find.byType(ProfileLoadFailedNotice), findsNothing);
      });
    });

    // 3 · DELAYED RESPONSE: A's request is slow; B signs in before it lands.
    for (final dir in const [('coach', 'client'), ('client', 'coach')]) {
      final (aRole, bRole) = dir;
      // `first`: A's very first read is the slow one (A never had a role).
      // `refresh`: A had a role, then A's refresh is the slow one.
      for (final slow in const ['first', 'refresh']) {
        for (final bMode in const [_P.ok, _P.server, _P.pending]) {
          testWidgets(
              "3 · A=$aRole, B=$bRole ($how): A's slow $slow read lands after "
              "B signed in; B's read ${bMode.name} — A's late answer is never "
              "B's role", (tester) async {
            const lag = Duration(seconds: 5);
            final p = _Profile(aRole)
              ..roles['user-b'] = bRole
              ..modes['user-b'] = bMode;
            if (slow == 'first') p.delays['user-a'] = lag;
            final ref = await pumpSwitchable(tester, p);
            if (slow == 'first') {
              expectPending();
            } else {
              expectRole(aRole);
              p.delays['user-a'] = lag;
              ref.invalidate(currentUserProfileProvider); // A's slow refresh
              await settle(tester);
              expectRole(aRole); // same member: the kept role is real
            }
            expect(p.answered.where((u) => u == 'user-a').length,
                slow == 'first' ? 0 : 1,
                reason: "precondition: A's slow answer has not arrived yet");

            await switchTo(tester, ref, 'user-b', observeSignOut: observe);

            void expectB() {
              switch (bMode) {
                case _P.ok:
                  expectRole(bRole);
                case _P.server:
                  expectFailure();
                case _P.pending:
                case _P.network:
                  expectPending();
              }
            }

            expectB(); // before A's answer lands
            await tester.pump(lag);
            await settle(tester);
            expect(p.answered.where((u) => u == 'user-a').length,
                slow == 'first' ? 1 : 2,
                reason: "precondition: A's late answer really arrived");
            expectB(); // and after: still B's state, not A's role
          });
        }
      }
    }
  }

  // 4 · SIGN-OUT ONLY
  testWidgets('4 · coach A signs out, nobody signs in: no coach bypass remains '
      'from A', (tester) async {
    final ref = await pumpSwitchable(tester, _Profile('coach'));
    expectRole('coach');

    ref.read(_signedIn.notifier).state = null;
    await settle(tester);
    expect(find.byKey(const Key('child')), findsNothing,
        reason: "A's coach bypass must not outlive A's session");
  });

  testWidgets("4 · coach A signs out while A's refresh is slow; the late "
      'answer lands with nobody signed in: still no coach bypass',
      (tester) async {
    final p = _Profile('coach');
    final ref = await pumpSwitchable(tester, p);
    expectRole('coach');
    p.delays['user-a'] = const Duration(seconds: 5);
    ref.invalidate(currentUserProfileProvider);
    await settle(tester);

    ref.read(_signedIn.notifier).state = null;
    await settle(tester);
    await tester.pump(const Duration(seconds: 5));
    await settle(tester);
    expect(p.answered.where((u) => u == 'user-a').length, 2,
        reason: "precondition: A's late refresh really arrived");
    expect(find.byKey(const Key('child')), findsNothing,
        reason: "A's coach bypass must not outlive A's session");
  });
}
