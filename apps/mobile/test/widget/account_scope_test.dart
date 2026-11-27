import 'dart:async';

import 'package:circle_fitness/core/identity/account_scope.dart';
import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/core/router/app_router.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/auth/presentation/login_screen.dart';
import 'package:circle_fitness/features/payments/domain/entitlements.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/account_app.dart';
import '../support/pump_until.dart';

// P0-FL-59a (A-28) — the app's state belongs to one account.
//
// `main()` put one ProviderScope, one router and one navigator stack under
// runApp for the life of the process. When the signed-in account changed under
// it (another web tab signed in, the session ended remotely, an ordinary mobile
// sign-out → sign-in) the previous member's screens, root dialogs, held
// provider values, timers and channels were still there for the next one.
//
// These mount the REAL app root (CircleFitnessRoot: AccountScope above the
// provider container, the real routerProvider, the real shell) over a fake
// PostgREST and realtime socket, and switch through the real auth client.
//
// HOW TO SEE IT FAIL: the root is new, so at a82f993 this file does not
// compile. Replace AccountScope.build with a fixed container (or make _follow
// return before setState) and every negative test below fails.

final _server = AccountServer();
final _realtime = FakeRealtime();
final _store = MemoryStore();
final _failures = <AppFailure>[];

/// A provider holding something of the account's, and a timer.
final _heldProvider = FutureProvider<String>((ref) async {
  ref.watch(currentUserProvider.select((u) => u?.id));
  final t = Timer.periodic(const Duration(seconds: 1), (_) => _ticks++);
  ref.onDispose(t.cancel);
  final rows =
      await Supabase.instance.client.from('held').select().limit(1);
  return rows.isEmpty ? 'nothing' : rows.first['text'] as String;
});
var _ticks = 0;

/// A screen that keeps everything the app's own screens keep: typed text, a
/// held provider value read the leaky way, and what it loaded at mount.
class _Private extends ConsumerStatefulWidget {
  const _Private(this.text);
  final String text;
  @override
  ConsumerState<_Private> createState() => _PrivateState();
}

final _liveStates = <State>{};

class _PrivateState extends ConsumerState<_Private> {
  @override
  void initState() {
    super.initState();
    _liveStates.add(this);
  }

  @override
  void dispose() {
    _liveStates.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final held = ref.watch(_heldProvider);
    return Scaffold(
        body: Column(children: [
      Text(widget.text),
      Text('held: ${held.hasValue ? held.value : '…'}'),
    ]));
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await initAccountSupabase(_server, _realtime, _store);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    passwordRecoveryNotifier.value = null;
    accountReadFailureNotifier.value = null;
    _server.reset();
    _failures.clear();
    _liveStates.clear();
    _ticks = 0;
    setFailureSink(_failures.add);
    addTearDown(resetFailureSink);
    _server.rows['user_profiles:$acctA'] = [
      {'id': acctA, 'role': 'client', 'onboarding_complete': true, 'first_name': 'Alba'}
    ];
    _server.rows['user_profiles:$acctB'] = [
      {'id': acctB, 'role': 'client', 'onboarding_complete': true, 'first_name': 'Bruno'}
    ];
    _server.rows['held:$acctA'] = [
      {'text': 'A-HELD'}
    ];
    _server.rows['held:$acctB'] = [
      {'text': 'B-HELD'}
    ];
  });

  ProviderContainer container(WidgetTester t) => appContainer(t);
  GoRouter router(WidgetTester t) => appRouter(t);
  String path(WidgetTester t) => appPath(t);
  Future<void> settle(WidgetTester t, [int frames = 12]) =>
      settleApp(t, frames);

  Future<void> auth(WidgetTester t, Future<void> Function() f) async {
    await t.runAsync(f);
    await settle(t);
  }

  Future<void> mount(WidgetTester t, {required String? as, String? at}) =>
      mountApp(t, as: as, at: at, overrides: [
        clientPlanProvider.overrideWith((ref) async => ClientPlan.coachGuided),
      ]);

  /// Runs [body], and unmounts whatever happened.
  void appTest(String name, Future<void> Function(WidgetTester t) body) =>
      testWidgets(name, (t) async {
        try {
          await body(t);
          expect(t.takeException(), isNull);
        } finally {
          await unmountApp(t, _server);
        }
      });

  /// Puts a pushed private page and a private root dialog over the shell.
  Future<void> openPrivateUi(WidgetTester t) async {
    final nav = router(t).configuration.navigatorKey.currentState!;
    unawaited(nav.push(MaterialPageRoute<void>(
        builder: (_) => const _Private("A's client PAR-Q"))));
    await settle(t);
    unawaited(showDialog<void>(
        context: nav.context,
        useRootNavigator: true,
        builder: (_) => const AlertDialog(title: Text("A's open dialog"))));
    await settle(t);
    expect(find.text("A's open dialog"), findsOneWidget, reason: 'premise');
    expect(find.text("A's client PAR-Q", skipOffstage: false), findsOneWidget);
    expect(find.text('held: A-HELD', skipOffstage: false), findsOneWidget);
    expect(_liveStates, hasLength(1));
  }

  void expectNothingOfA(WidgetTester t) {
    expect(find.text("A's open dialog", skipOffstage: false), findsNothing);
    expect(find.text("A's client PAR-Q", skipOffstage: false), findsNothing);
    expect(find.textContaining('A-HELD', skipOffstage: false), findsNothing);
    expect(_liveStates, isEmpty,
        reason: 'the State was disposed, not re-parented');
  }

  for (final (what, change, dest) in [
    ('A -> B (another tab)', () => signInAs(acctB), '/home'),
    ('A signs out', signOut, '/login'),
    ('A\'s session ends remotely', () => expire(_server), '/login'),
  ]) {
    appTest('$what: page, root dialog, provider and timer of A are gone',
        (t) async {
      await mount(t, as: acctA, at: '/settings');
      await openPrivateUi(t);
      final oldContainer = container(t);
      final oldRouter = router(t);
      final oldRoot = oldRouter.configuration.navigatorKey;
      final ticks = _ticks;
      await t.pump(const Duration(seconds: 3));
      expect(_ticks, greaterThan(ticks), reason: 'premise: the timer runs');

      await auth(t, change);

      expectNothingOfA(t);
      expect(container(t), isNot(same(oldContainer)));
      expect(router(t), isNot(same(oldRouter)));
      expect(oldRoot.currentState, isNull, reason: 'old navigator unmounted');
      expect(() => oldContainer.read(_heldProvider), throwsStateError,
          reason: 'the old container is disposed');
      final after = _ticks;
      await t.pump(const Duration(seconds: 5));
      expect(_ticks, after, reason: "A's timer stopped");
      expect(path(t), dest);
      expect(_realtime.joinedFor(acctA), isEmpty,
          reason: "A's channels are left");
    });
  }

  appTest("B never gets A's held value: B's read pending, then failed",
      (t) async {
    await mount(t, as: acctA, at: '/settings');
    await openPrivateUi(t);
    final hold = _server.holds['GET held:$acctB'] = Completer<void>();
    _server.fails['GET held:$acctB'] = 500;
    await auth(t, () => signInAs(acctB));
    expectNothingOfA(t);

    final nav = router(t).configuration.navigatorKey.currentState!;
    unawaited(nav.push(
        MaterialPageRoute<void>(builder: (_) => const _Private("B's page"))));
    await settle(t);
    expect(find.text('held: …'), findsOneWidget, reason: 'pending: not A');
    hold.complete();
    await settle(t, 40);
    expect(find.text('held: …'), findsOneWidget, reason: 'failed: not A');
    expect(find.textContaining('A-HELD'), findsNothing);
  });

  appTest("a late answer to A's request, after B's own read, changes nothing",
      (t) async {
    await mount(t, as: acctA, at: '/settings');
    final hold = _server.holds['GET held:$acctA'] = Completer<void>();
    final nav = router(t).configuration.navigatorKey.currentState!;
    unawaited(nav.push(
        MaterialPageRoute<void>(builder: (_) => const _Private("A's page"))));
    await settle(t);
    expect(_server.of('held', by: acctA), hasLength(1), reason: 'premise');

    await auth(t, () => signInAs(acctB));
    final navB = router(t).configuration.navigatorKey.currentState!;
    unawaited(navB.push(
        MaterialPageRoute<void>(builder: (_) => const _Private("B's page"))));
    await settle(t);
    expect(find.text('held: B-HELD'), findsOneWidget);
    hold.complete();
    await settle(t);
    expect(find.text('held: B-HELD'), findsOneWidget);
    expect(find.textContaining('A-HELD'), findsNothing);
  });

  appTest('sign-out then B signs in: B starts clean, on B\'s own home',
      (t) async {
    await mount(t, as: acctA, at: '/settings');
    await openPrivateUi(t);
    await auth(t, signOut);
    expect(path(t), '/login');
    expect(find.byType(LoginScreen), findsOneWidget);
    final gen = container(t);
    await auth(t, () => signInAs(acctB));
    expect(container(t), same(gen),
        reason: 'signed out -> B is a sign-in: no remount');
    expectNothingOfA(t);
    expect(path(t), '/home');
  });

  appTest('rapid A -> B -> A ends in a clean generation of A', (t) async {
    await mount(t, as: acctA, at: '/settings');
    await openPrivateUi(t);
    final old = container(t);
    // Both events are delivered before any frame, and after currentUser is A
    // again.
    await t.runAsync(() async {
      unawaited(signInAs(acctB));
      await signInAs(acctA);
    });
    await settle(t);
    expectNothingOfA(t);
    expect(container(t), isNot(same(old)));
    expect(container(t).read(accountGenerationProvider).number, 2);
    expect(container(t).read(currentUserProvider)?.id, acctA);
    expect(path(t), '/home');
  });

  appTest('coach A -> coach B: the shell and the dashboard are new', (t) async {
    _server.rows['user_profiles:$acctA']!.first['role'] = 'coach';
    _server.rows['user_profiles:$acctB']!.first['role'] = 'coach';
    await mount(t, as: acctA, at: '/settings');
    await openPrivateUi(t);
    await auth(t, () => signInAs(acctB));
    expectNothingOfA(t);
    expect(path(t), '/coach-dashboard');
  });

  appTest("A -> B whose role read fails: B's failure notice, nothing of A",
      (t) async {
    await mount(t, as: acctA, at: '/settings');
    await openPrivateUi(t);
    _server.fails['GET user_profiles:$acctB'] = 403;
    await auth(t, () => signInAs(acctB));
    await settle(t, 30);
    expectNothingOfA(t);
    expect(path(t), '/login');
    expect(find.byKey(const Key('login-account-read-failure')), findsOneWidget);
  });

  // ── Positive controls: the same account keeps everything ──────────────────

  for (final (what, f) in [
    ('token refresh', renewToken),
    (
      'profile metadata edit',
      () async => Supabase.instance.client.auth
          .updateUser(UserAttributes(data: {'first_name': 'Alba'}))
    ),
    (
      'the same member\'s session from another tab',
      () => sameMemberInAnotherTab(acctA)
    ),
    (
      'a failed refresh that ends no session',
      () async {
        // 5xx is retryable: gotrue reports it and keeps the session. One try:
        // notifyException is what it calls once its retries run out.
        final auth = Supabase.instance.client.auth;
        // ignore: invalid_use_of_internal_member
        auth.notifyException(AuthRetryableFetchException());
      }
    ),
  ]) {
    appTest('control: $what never remounts', (t) async {
      await mount(t, as: acctA, at: '/settings');
      await openPrivateUi(t);
      final c = container(t);
      final state = _liveStates.single;
      await auth(t, () async => await f());
      expect(container(t), same(c));
      expect(_liveStates.single, same(state));
      expect(find.text("A's open dialog"), findsOneWidget);
      expect(path(t), '/settings');
    });
  }

  appTest('control: signed out -> A -> (sign-up/sign-in/OAuth) keeps the tree',
      (t) async {
    await mount(t, as: null);
    expect(container(t).read(accountGenerationProvider).isFirst, isTrue);
    expect(path(t), '/splash', reason: 'the first generation opens the splash');
    router(t).go('/login');
    await settle(t);
    final c = container(t);
    await t.enterText(find.byType(TextField).first, acctA);
    await t.enterText(find.byType(TextField).last, 'secret-1');
    await t.tap(find.text('Sign in'));
    await settle(t);
    await pumpUntil(t, () => path(t) == '/home', what: 'the sign-in to route');
    expect(container(t), same(c));
  });

  appTest('control: the same member signing out and back in gets a fresh app',
      (t) async {
    await mount(t, as: acctA, at: '/settings');
    await openPrivateUi(t);
    await auth(t, signOut);
    await auth(t, () => signInAs(acctA));
    expectNothingOfA(t);
    expect(path(t), '/home');
    final nav = router(t).configuration.navigatorKey.currentState!;
    unawaited(nav.push(
        MaterialPageRoute<void>(builder: (_) => const _Private("A's page"))));
    await settle(t);
    expect(find.text('held: A-HELD'), findsOneWidget, reason: 'and still works');
  });

  appTest('control: an empty read is still empty for B', (t) async {
    _server.rows['held:$acctB'] = [];
    await mount(t, as: acctA, at: '/settings');
    await auth(t, () => signInAs(acctB));
    final nav = router(t).configuration.navigatorKey.currentState!;
    unawaited(nav.push(
        MaterialPageRoute<void>(builder: (_) => const _Private("B's page"))));
    await settle(t);
    expect(find.text('held: nothing'), findsOneWidget);
  });

  // ── Invites: a switch is not a sign-in ────────────────────────────────────

  appTest('A -> B does not redeem an invite remembered for A', (t) async {
    await mount(t, as: acctA, at: '/settings');
    SharedPreferences.setMockInitialValues({'pending_coach_invite': 'tok-a'});
    await auth(t, () => signInAs(acctB));
    expect(path(t), '/home', reason: 'premise: B is in');
    expect(_server.of('accept_coach_invite'), isEmpty);
  });

  appTest('control: signing in redeems a remembered invite once', (t) async {
    await mount(t, as: null);
    router(t).go('/login');
    await settle(t);
    SharedPreferences.setMockInitialValues({'pending_coach_invite': 'tok-a'});
    await auth(t, () => signInAs(acctA));
    expect(_server.of('accept_coach_invite', by: acctA), hasLength(1));
  });

  // ── Every sign-out path finishes on a disposed tree ───────────────────────

  /// The server's answer to the sign-out comes after the old tree and its
  /// container are gone, as over any real network.
  late Completer<void> logout;
  void holdLogout() => logout = _server.holds['POST logout'] = Completer<void>();
  Future<void> answerLogout(WidgetTester t) async {
    expect(path(t), '/login', reason: 'before the server has answered');
    expect(_server.of('logout'), hasLength(1));
    logout.complete();
    await settle(t);
    expect(path(t), '/login');
  }

  Future<void> confirmSignOut(WidgetTester t, Finder opener, String confirm) async {
    holdLogout();
    await t.ensureVisible(opener);
    await t.tap(opener);
    await settle(t);
    await t.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text(confirm)).last);
    await settle(t, 20);
  }

  for (final offline in [false, true]) {
    final how = offline ? 'the server refuses' : 'the server answers';
    appTest('Profile sign-out ($how) lands on sign-in, throws nothing',
        (t) async {
      await mount(t, as: acctA, at: '/profile');
      if (offline) _server.fails['POST logout'] = 500;
      await confirmSignOut(t, find.text('Sign Out').last, 'Sign Out');
      await answerLogout(t);
      expect(Supabase.instance.client.auth.currentSession, isNull);
      expect(_server.of('logout'), hasLength(1));
      expect(_failures.map((f) => f.origin).where((o) => o.contains('signOut')),
          offline ? ['ProfileScreen.signOut'] : isEmpty);
    });

    appTest('Settings sign-out ($how) lands on sign-in, throws nothing',
        (t) async {
      await mount(t, as: acctA, at: '/settings');
      if (offline) _server.fails['POST logout'] = 500;
      await confirmSignOut(t, find.text('Sign out').last, 'Sign out');
      await answerLogout(t);
      expect(_server.of('logout'), hasLength(1));
      expect(_failures.map((f) => f.origin).where((o) => o.contains('signOut')),
          offline ? ['SettingsScreen.signOut'] : isEmpty);
    });
  }

  const refusedByDevice = "Couldn't sign you out — try again in a moment. "
      'If it keeps happening, contact support.';

  /// The device refuses to remove what gotrue stores (round 2, item 7): nobody
  /// is told, and the stored session signs the account in at the next start.
  Future<void> expectRefusedByDevice(
      WidgetTester t, String origin, String at) async {
    expect(find.text(refusedByDevice), findsOneWidget);
    expect(find.textContaining('storage:'), findsNothing);
    expect(appPath(t), at);
    expect(_failures.map((f) => f.origin), contains(origin));
    await t.pump(const Duration(seconds: 5));
    await settle(t);
  }

  for (final (who, at, opener, confirm, origin) in [
    ('Profile', '/profile', 'Sign Out', 'Sign Out', 'ProfileScreen.signOut'),
    ('Settings', '/settings', 'Sign out', 'Sign out', 'SettingsScreen.signOut'),
  ]) {
    Future<void> press(WidgetTester t) async {
      await t.ensureVisible(find.text(opener).last);
      await t.tap(find.text(opener).last);
      await settle(t);
      await t.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text(confirm)).last);
      await settle(t);
    }

    appTest('$who sign-out, the device refuses: says so, and can be tried again',
        (t) async {
      await mount(t, as: acctA, at: at);
      _store.refuseRemoval = true;
      addTearDown(() => _store.refuseRemoval = false);
      await press(t);
      await expectRefusedByDevice(t, origin, at);
      _store.refuseRemoval = false;
      await press(t);
      expect(appPath(t), '/login');
      expect(find.text(refusedByDevice), findsNothing);
      expect(container(t).read(accountGenerationProvider).number, 1);
    });

    appTest('$who sign-out, the device refuses once: signed out, nothing said',
        (t) async {
      await mount(t, as: acctA, at: at);
      _store.refuseRemoval = true;
      addTearDown(() => _store.refuseRemoval = false);
      _store.onRefused = () => _store.refuseRemoval = false;
      addTearDown(() => _store.onRefused = null);
      await press(t);
      expect(appPath(t), '/login');
      expect(find.text(refusedByDevice), findsNothing);
    });

    appTest("$who: A's sign-out dialog, confirmed after A -> B with no frame "
        'between, does not sign B out', (t) async {
      await mount(t, as: acctA, at: at);
      await t.ensureVisible(find.text(opener).last);
      await t.tap(find.text(opener).last);
      await settle(t);
      final button = t.widget<TextButton>(find.ancestor(
          of: find.descendant(
              of: find.byType(AlertDialog), matching: find.text(confirm)).last,
          matching: find.byType(TextButton)));
      await t.runAsync(() async {
        await signInAs(acctB);
        button.onPressed!();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await settle(t);
      expect(_server.of('logout'), isEmpty);
      expect(Supabase.instance.client.auth.currentUser?.id, acctB);
      expect(path(t), '/home');
      expect(_failures.where((f) => f.origin == origin), hasLength(1));
    });
  }

  appTest('Sign-in\'s "Sign out", the device refuses: says so, keeps the notice',
      (t) async {
    _server.fails['GET user_profiles:$acctA'] = 403;
    await mount(t, as: null);
    router(t).go('/login');
    await settle(t);
    await t.enterText(find.byType(TextField).first, acctA);
    await t.enterText(find.byType(TextField).last, 'secret-1');
    await t.tap(find.text('Sign in'));
    await settle(t, 30);
    expect(find.byKey(const Key('login-account-read-failure')), findsOneWidget,
        reason: 'premise');
    _store.refuseRemoval = true;
    addTearDown(() => _store.refuseRemoval = false);
    await t.tap(find.text('Sign out'));
    await settle(t);
    expect(find.byKey(const Key('login-account-read-failure')), findsOneWidget);
    await expectRefusedByDevice(t, 'LoginScreen._signOutAfterFailure', '/login');
    _store.refuseRemoval = false;
  });

  for (final (role, at, origin) in [
    ('admin', '/admin-dashboard', 'AdminDashboardScreen.signOut'),
    ('vendor', '/vendor-portal', 'VendorPortalScreen.signOut')
  ]) {
    Future<void> open(WidgetTester t) async {
      // The admin tiles overflow by 2px in the test font; not what this is on.
      final onError = FlutterError.onError;
      FlutterError.onError = (d) =>
          '${d.exception}'.contains('overflowed') ? null : onError!(d);
      addTearDown(() => FlutterError.onError = onError);
      _server.rows['user_profiles:$acctA']!.first['role'] = role;
      await mount(t, as: acctA, at: at);
    }

    appTest('$role sign-out, the server refuses: sign-in, recorded, not thrown',
        (t) async {
      await open(t);
      _server.fails['POST logout'] = 500;
      await t.tap(find.byIcon(Icons.logout_rounded));
      await settle(t, 20);
      expect(path(t), '/login');
      expect(Supabase.instance.client.auth.currentSession, isNull);
      expect(
          _failures.map((f) => f.origin).where((o) => o == origin), hasLength(1));
      expect(find.text(refusedByDevice), findsNothing);
    });

    appTest('$role sign-out, the device refuses: says so', (t) async {
      await open(t);
      _store.refuseRemoval = true;
      addTearDown(() => _store.refuseRemoval = false);
      await t.tap(find.byIcon(Icons.logout_rounded));
      await settle(t);
      await expectRefusedByDevice(t, origin, at);
      _store.refuseRemoval = false;
    });

    appTest('$role sign-out lands on sign-in, throws nothing', (t) async {
      // The admin tiles overflow by 2px in the test font; not what this is on.
      final onError = FlutterError.onError;
      FlutterError.onError = (d) =>
          '${d.exception}'.contains('overflowed') ? null : onError!(d);
      addTearDown(() => FlutterError.onError = onError);
      _server.rows['user_profiles:$acctA']!.first['role'] = role;
      await mount(t, as: acctA, at: at);
      holdLogout();
      await t.tap(find.byIcon(Icons.logout_rounded));
      await settle(t, 20);
      await answerLogout(t);
      expect(_server.of('logout'), hasLength(1));
      expect(find.byIcon(Icons.logout_rounded), findsNothing);
    });
  }

  appTest('Sign-in\'s "Sign out" after a failed account read: an empty form',
      (t) async {
    _server.fails['GET user_profiles:$acctA'] = 403;
    await mount(t, as: null);
    router(t).go('/login');
    await settle(t);
    await t.enterText(find.byType(TextField).first, acctA);
    await t.enterText(find.byType(TextField).last, 'secret-1');
    await t.tap(find.text('Sign in'));
    await settle(t, 30);
    expect(find.byKey(const Key('login-account-read-failure')), findsOneWidget,
        reason: 'premise');
    holdLogout();
    await t.tap(find.text('Sign out'));
    await settle(t, 20);
    await answerLogout(t);
    expect(Supabase.instance.client.auth.currentSession, isNull);
    expect(find.byKey(const Key('login-account-read-failure')), findsNothing);
    final fields = t.widgetList<TextField>(find.byType(TextField));
    expect(fields.map((f) => f.controller!.text), everyElement(isEmpty));
  });

  // ── The hook ──────────────────────────────────────────────────────────────

  testWidgets('onOwnerLeft: each owner that leaves, once, failures recorded',
      (t) async {
    final left = <String>[];
    await t.runAsync(signOut);
    await t.runAsync(() => signInAs(acctA));
    await t.pumpWidget(AccountScope(
      onOwnerLeft: (uid) {
        left.add(uid);
        throw StateError('device refused');
      },
      child: const SizedBox(),
    ));
    await t.pump();
    await auth(t, () async => Supabase.instance.client.auth.refreshSession());
    expect(left, isEmpty, reason: 'same member');
    await auth(t, () => signInAs(acctB));
    await auth(t, signOut);
    await auth(t, () => signInAs(acctA));
    expect(left, [acctA, acctB]);
    expect(_failures.map((f) => f.origin),
        everyElement('AccountScope.onOwnerLeft'));
    expect(_failures, hasLength(2));
    await t.pumpWidget(const SizedBox());
    await t.runAsync(signOut);
  });
}
