import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/core/identity/account_scope.dart';
import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/core/router/app_router.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/auth/presentation/signup_screen.dart';
import 'package:circle_fitness/features/coach/domain/coach_provider.dart';
import 'package:circle_fitness/features/home/presentation/home_screen.dart';
import 'package:circle_fitness/features/payments/domain/entitlements.dart';
import 'package:circle_fitness/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/account_app.dart';
import '../support/pump_until.dart';

// P0-FL-59a round 2 — how an account's generation begins (items 4 and 5), and
// what a retired one must not do (item 11). Under the REAL app root.

final _server = AccountServer();
final _realtime = FakeRealtime();
final _store = MemoryStore();
final _failures = <AppFailure>[];

GoTrueClient get _auth => Supabase.instance.client.auth;

/// Found by its label, not its type, so this file also compiles at 4917961.
final _pending = find.byWidgetPredicate((w) =>
    w is Semantics &&
    w.properties.label == 'Loading your account' &&
    w.properties.liveRegion == true);

final _heldProvider = FutureProvider<String>((ref) async {
  ref.watch(currentUserProvider.select((u) => u?.id));
  final rows = await Supabase.instance.client.from('held').select().limit(1);
  return rows.isEmpty ? 'nothing' : rows.first['text'] as String;
});

class _Held extends ConsumerWidget {
  const _Held();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final held = ref.watch(_heldProvider);
    return Scaffold(
        body: Text('held: ${held.hasValue ? held.requireValue : '…'}'));
  }
}

/// What the app's redirect reads of a [GoRouterState].
class _StateAt implements GoRouterState {
  _StateAt(this.uri);
  @override
  final Uri uri;
  @override
  String get matchedLocation => uri.path;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await initAccountSupabase(_server, _realtime, _store);
    _auth.onAuthStateChange.listen((_) {}, onError: (Object _) {});
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    passwordRecoveryNotifier.value = null;
    accountReadFailureNotifier.value = null;
    _server.reset();
    _store.m.clear();
    _failures.clear();
    setFailureSink(_failures.add);
    addTearDown(resetFailureSink);
    for (final (id, name) in [(acctA, 'Alba'), (acctB, 'Bruno')]) {
      _server.rows['user_profiles:$id'] = [
        {'id': id, 'role': 'client', 'onboarding_complete': true, 'first_name': name}
      ];
      _server.rows['held:$id'] = [
        {'text': id == acctA ? 'A-HELD' : 'B-HELD'}
      ];
    }
  });

  Future<void> mount(WidgetTester t, {required String? as, String? at}) =>
      mountApp(t, as: as, at: at, overrides: [
        clientPlanProvider.overrideWith((ref) async => ClientPlan.coachGuided),
      ]);

  Future<void> auth(WidgetTester t, Future<void> Function() f) async {
    await t.runAsync(f);
    await settleApp(t);
  }

  void appTest(String name, Future<void> Function(WidgetTester t) body) =>
      testWidgets(name, (t) async {
        try {
          await body(t);
          expect(t.takeException(), isNull);
        } finally {
          await unmountApp(t, _server);
        }
      });

  // ── The launch ────────────────────────────────────────────────────────────

  group('the launch deep link', () {
    void deepLink(WidgetTester t) {
      t.binding.platformDispatcher.defaultRouteNameTestValue = '/goals';
      addTearDown(t.binding.platformDispatcher.clearDefaultRouteNameTestValue);
    }

    appTest('opens for the account that launched it, and not for the next',
        (t) async {
      deepLink(t);
      await mount(t, as: acctA);
      await settleApp(t);
      expect(appPath(t), '/goals', reason: 'control: the launch opens it');
      await auth(t, () => signInAs(acctB));
      expect(appPath(t), '/home');
    });

    appTest('is not reopened signed out', (t) async {
      deepLink(t);
      await mount(t, as: acctA);
      await auth(t, signOut);
      expect(appPath(t), '/login');
      await auth(t, () => signInAs(acctB));
      expect(appPath(t), '/home');
    });
  });

  group('a launch whose stored session has expired', () {
    Future<void> launch(WidgetTester t) async {
      await t.runAsync(signOut);
      // As supabase_flutter restores it: whatever its age.
      await t.runAsync(() => _auth
          .setInitialSession(jsonEncode(sessionOf(acctA, expired: true))));
      _server.holds['POST token'] = Completer<void>();
      t.view.physicalSize = const Size(900, 2600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(CircleFitnessRoot(theme: ThemeData.dark(), overrides: [
        clientPlanProvider.overrideWith((ref) async => ClientPlan.coachGuided),
      ]));
      await settleApp(t, 4);
      expect(appPath(t), '/splash', reason: 'premise');
    }

    Future<void> answerRefresh(WidgetTester t) async {
      unawaited(_auth.refreshSession().then((_) {}, onError: (Object _) {}));
      await settleApp(t, 1);
      _server.holds.remove('POST token')!.complete();
      await settleApp(t);
    }

    appTest('the refresh is refused: sign-in, in a generation of nobody\'s',
        (t) async {
      await launch(t);
      _server.fails['POST token'] = 400;
      await answerRefresh(t);
      expect(appPath(t), '/login');
      final g = appContainer(t).read(accountGenerationProvider);
      expect((g.number, g.startedAs), (1, null));
      expect(_pending, findsNothing, reason: 'nobody is loading');
    });

    appTest('control: the refresh answers — the launch carries on, not remounted',
        (t) async {
      await launch(t);
      final c = appContainer(t);
      await answerRefresh(t);
      expect(appContainer(t), same(c));
      expect(appPath(t), '/splash');
      expect(_auth.currentSession!.isExpired, isFalse);
    });
  });

  // ── null -> X: a sign-in is not a switch ──────────────────────────────────

  group('signed out -> A keeps the tree', () {
    Future<void> signUpForm(WidgetTester t) async {
      await settleApp(t);
      for (final (i, v)
          in ['Alba', 'Aye', acctA, 'secret-1'].indexed) {
        await t.enterText(find.byType(TextField).at(i), v);
      }
      await t.ensureVisible(find.textContaining('Terms of Service').first);
      await t.tap(find.byType(AnimatedContainer).last, warnIfMissed: false);
      await t.pump();
      await t.ensureVisible(find.text('Create Account').last);
      await t.tap(find.text('Create Account').last, warnIfMissed: false);
    }

    appTest('sign-up, then intake with what was typed there', (t) async {
      _server.rows['user_profiles:$acctA']!.first['onboarding_complete'] = false;
      await mount(t, as: null);
      appRouter(t).go('/signup');
      final c = appContainer(t);
      await signUpForm(t);
      await pumpUntil(t, () => appPath(t) == '/intake', what: 'the intake');
      await settleApp(t);
      expect(appContainer(t), same(c));
      expect(_pending, findsNothing);
      final page = find.byWidgetPredicate(
          (w) => '${w.runtimeType}' == 'IntakeFlowScreen');
      final state = t.state(page);
      await auth(t, renewToken);
      await auth(t, () => sameMemberInAnotherTab(acctA));
      expect(appPath(t), '/intake');
      expect(t.state(page), same(state), reason: 'intake keeps its steps');
      expect(appContainer(t), same(c));
    });

    appTest('an OAuth return', (t) async {
      await mount(t, as: null);
      appRouter(t).go('/login');
      await settleApp(t);
      final c = appContainer(t);
      _store.m['supabase.auth.token-code-verifier'] = 'verifier';
      _server.codeSession = sessionOf(acctA);
      await auth(
          t,
          () => _auth.getSessionFromUrl(
              Uri.parse('https://app.example/?code=c0de')));
      await pumpUntil(t, () => appPath(t) == '/home', what: 'home');
      expect(appContainer(t), same(c));
      expect(_pending, findsNothing);
    });

    appTest('an invite link: the token survives the sign-up and is redeemed once',
        (t) async {
      await mount(t, as: null);
      appRouter(t).go('/signup?invite=tok-a');
      final c = appContainer(t);
      await settleApp(t);
      expect(find.byType(SignupScreen), findsOneWidget);
      await signUpForm(t);
      await pumpUntil(t, () => _server.of('accept_coach_invite').isNotEmpty,
          what: 'the invite');
      await settleApp(t);
      expect(appContainer(t), same(c));
      expect(_server.of('accept_coach_invite').map((s) => s.who), [acctA]);
      expect(_server.of('accept_coach_invite').single.body, contains('tok-a'));
    });
  });

  // ── Delayed answers ───────────────────────────────────────────────────────

  appTest("A's delayed answer BEFORE B's own read: B sees B's pending, then B's",
      (t) async {
    await mount(t, as: acctA, at: '/settings');
    final a = _server.holds['GET held:$acctA'] = Completer<void>();
    final b = _server.holds['GET held:$acctB'] = Completer<void>();
    void push() => unawaited(appRouter(t)
        .configuration
        .navigatorKey
        .currentState!
        .push(MaterialPageRoute<void>(builder: (_) => const _Held())));
    push();
    await settleApp(t);
    await auth(t, () => signInAs(acctB));
    push();
    await settleApp(t);
    expect(_server.of('held').map((s) => s.who), [acctA, acctB]);

    a.complete();
    await settleApp(t);
    expect(find.text('held: …'), findsOneWidget, reason: "B's is still out");
    expect(find.textContaining('A-HELD', skipOffstage: false), findsNothing);
    b.complete();
    await settleApp(t);
    expect(find.text('held: B-HELD'), findsOneWidget);
  });

  // ── Pending: never an empty window ────────────────────────────────────────

  group('A -> B, before B has anywhere to go', () {
    for (final scale in [1.0, 3.0]) {
      appTest('says B\'s account is loading, until it is (text ×$scale)',
          (t) async {
        t.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await mount(t, as: acctA, at: '/goals');
        final hold =
            _server.holds['GET user_profiles:$acctB'] = Completer<void>();
        final handle = t.ensureSemantics();
        await auth(t, () => signInAs(acctB));
        expect(_pending, findsOneWidget);
        expect(find.bySemanticsLabel('Loading your account'), findsOneWidget);
        expect(
            find.descendant(
                of: _pending, matching: find.byType(CircularProgressIndicator)),
            findsOneWidget);
        final box = t.getRect(_pending);
        expect(box, Offset.zero & const Size(900, 2600), reason: 'full size');
        expect(
            t.getCenter(find.descendant(
                of: _pending, matching: find.byType(CircularProgressIndicator))),
            box.center);
        expect(find.textContaining('Alba'), findsNothing);

        // Home itself at ×3 is not what this is on.
        t.platformDispatcher.clearTextScaleFactorTestValue();
        hold.complete();
        await settleApp(t);
        expect(_pending, findsNothing);
        expect(appPath(t), '/home');
        expect(find.byType(HomeScreen), findsOneWidget);
        handle.dispose();
      });
    }

    appTest('the read fails: gone, and B\'s own failure notice with Try again',
        (t) async {
      await mount(t, as: acctA, at: '/settings');
      _server.fails['GET user_profiles:$acctB'] = 403;
      final hold =
          _server.holds['GET user_profiles:$acctB'] = Completer<void>();
      await auth(t, () => signInAs(acctB));
      expect(_pending, findsOneWidget);
      hold.complete();
      await settleApp(t, 30);
      expect(_pending, findsNothing);
      expect(find.byKey(const Key('login-account-read-failure')), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    appTest('a dropped connection: shown for as long as the client tries',
        (t) async {
      await mount(t, as: acctA, at: '/settings');
      _server.drops.add('GET user_profiles:$acctB');
      await t.runAsync(() => signInAs(acctB));
      await settleApp(t, 2);
      expect(_pending, findsOneWidget);
      await pumpUntil(
          t,
          () => find
              .byKey(const Key('login-account-read-failure'))
              .evaluate()
              .isNotEmpty,
          what: "B's failure notice",
          step: const Duration(milliseconds: 200));
      expect(_pending, findsNothing);
    });

    appTest('B leaves while waiting: sign-in, and nothing pending', (t) async {
      await mount(t, as: acctA, at: '/settings');
      _server.holds['GET user_profiles:$acctB'] = Completer<void>();
      await auth(t, () => signInAs(acctB));
      expect(_pending, findsOneWidget);
      await auth(t, signOut);
      expect(_pending, findsNothing);
      expect(appPath(t), '/login');
      _server.holds.remove('GET user_profiles:$acctB')!.complete();
      await settleApp(t);
      expect(appPath(t), '/login');
    });

    appTest('A signs out and B is in before the next frame: B\'s is said too',
        (t) async {
      await mount(t, as: acctA, at: '/settings');
      _server.holds['GET user_profiles:$acctB'] = Completer<void>();
      await auth(t, () async {
        await signOut();
        await signInAs(acctB);
      });
      expect(_pending, findsOneWidget);
      _server.holds.remove('GET user_profiles:$acctB')!.complete();
      await settleApp(t);
      expect(_pending, findsNothing);
      expect(appPath(t), '/home');
    });

    Future<void> neverPending(WidgetTester t, Future<void> Function() f) async {
      await f();
      for (var i = 0; i < 12; i++) {
        expect(_pending, findsNothing, reason: 'frame $i');
        await settleApp(t, 1);
      }
    }

    appTest('control: never at a launch, a sign-in or a renewal of one account',
        (t) async {
      await neverPending(t, () => mount(t, as: null));
      final hold =
          _server.holds['GET user_profiles:$acctA'] = Completer<void>();
      appRouter(t).go('/login');
      await settleApp(t);
      await neverPending(t, () => t.runAsync(() => signInAs(acctA)));
      hold.complete();
      await settleApp(t);
      expect(appPath(t), '/home');
      await neverPending(t, () => t.runAsync(renewToken));
      await neverPending(t, () => t.runAsync(signOut));
      expect(appPath(t), '/login');
    });
  });

  // ── What a retired generation must not do ─────────────────────────────────

  group('a retired generation', () {
    appTest('its router and what it listened with are disposed', (t) async {
      await mount(t, as: acctA, at: '/settings');
      final old = appRouter(t);
      await auth(t, () => signInAs(acctB));
      expect(() => old.routeInformationProvider.addListener(() {}),
          throwsFlutterError);
      // The global recovery notifier no longer drives it either.
      startPasswordRecovery(acctB);
      await settleApp(t);
      expect(appPath(t), '/reset-password', reason: "B's own router follows it");
    });

    appTest("A's invite answering after A -> B refreshes nothing, throws nothing",
        (t) async {
      var reads = 0;
      SharedPreferences.setMockInitialValues({});
      await mountApp(t, as: acctA, overrides: [
        clientPlanProvider.overrideWith((ref) async => ClientPlan.coachGuided),
        assignedCoachProvider.overrideWith((ref) async {
          reads++;
          return null;
        }),
      ]);
      final hold =
          _server.holds['POST accept_coach_invite:$acctA'] = Completer<void>();
      appRouter(t).go('/signup?invite=tok-a');
      await settleApp(t);
      expect(_server.of('accept_coach_invite').map((s) => s.who), [acctA],
          reason: 'premise: it is out');
      await auth(t, () => signInAs(acctB));
      final before = reads;
      hold.complete();
      await settleApp(t);
      expect(reads, before);
      expect(_server.of('accept_coach_invite').map((s) => s.who), [acctA]);
    });

    appTest("a link A opened is not redeemed as B, who arrives while it is kept "
        '(no frame between)', (t) async {
      await mount(t, as: acctA, at: '/settings');
      final redirect = appRouter(t).configuration.topRedirect;
      final ctx = t.element(find.byType(MaterialApp));
      await t.runAsync(() async {
        final to = redirect(ctx, _StateAt(Uri.parse('/signup?invite=tok-a')));
        unawaited(Future.value(to));
        // Before the token is stored.
        unawaited(signInAs(acctB));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await settleApp(t);
      expect(_server.of('accept_coach_invite').where((s) => s.who == acctB),
          isEmpty);
    });

    appTest('a retired router\'s redirect does not redeem either', (t) async {
      await mount(t, as: acctA, at: '/settings');
      final redirect = appRouter(t).configuration.topRedirect;
      await auth(t, () => signInAs(acctB));
      final ctx = t.element(find.byType(MaterialApp));
      unawaited(Future.value(
          redirect(ctx, _StateAt(Uri.parse('/signup?invite=tok-a')))));
      await settleApp(t);
      expect(_server.of('accept_coach_invite'), isEmpty);
    });

    appTest('control: a link the signed-in account opens is redeemed, once',
        (t) async {
      await mount(t, as: acctA, at: '/settings');
      appRouter(t).go('/signup?invite=tok-a');
      await settleApp(t);
      expect(_server.of('accept_coach_invite').map((s) => s.who), [acctA]);
    });
  });

  appTest('a failed refresh does not replay the last event: an ended recovery '
      'stays ended', (t) async {
    await mount(t, as: null);
    appRouter(t).go('/login');
    await settleApp(t);
    _store.askedForReset();
    _server.codeSession = sessionOf(acctA);
    await auth(
        t,
        () => _auth.getSessionFromUrl(
            Uri.parse('https://app.example/?recovery=1&code=c0de')));
    expect(passwordRecoveryNotifier.value, acctA, reason: 'premise');
    endPasswordRecovery();
    // ignore: invalid_use_of_internal_member
    _auth.notifyException(AuthRetryableFetchException());
    await settleApp(t);
    expect(passwordRecoveryNotifier.value, isNull);
  });
}
