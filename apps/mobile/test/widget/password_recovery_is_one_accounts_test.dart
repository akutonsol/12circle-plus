import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/core/router/app_router.dart';
import 'package:circle_fitness/features/auth/presentation/reset_password_screen.dart';
import 'package:circle_fitness/features/auth/presentation/widgets/auth_design.dart';
import 'package:circle_fitness/features/payments/domain/entitlements.dart';
import 'package:circle_fitness/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/account_app.dart';
import '../support/pump_until.dart';

// P0-FL-59a (c) — a password recovery belongs to the account whose link it is
// (A-06 / W2).
//
// `passwordRecoveryNotifier` was a bool. Whoever was signed in was forced onto
// /reset-password, and `updateUser(password)` set the password of whoever was
// signed in at that moment: A's form open in one tab, B signing in in another,
// then Update — B's password became what A typed. And `?recovery=1` in the
// launch URL raised the flag whether or not the link signed anyone in.
//
// The form tests mount the screen WITHOUT AccountScope; the recovery paths run
// under the real app root.

final _server = AccountServer();
final _realtime = FakeRealtime();
final _store = MemoryStore();
final _failures = <AppFailure>[];

GoTrueClient get _auth => Supabase.instance.client.auth;

final _link = Uri.parse('https://app.example/?recovery=1&code=c0de');

/// What supabase_flutter does with a link: exchange its code; a failure is
/// reported on the auth stream and whoever was signed in stays signed in.
Future<void> _openLink({Uri? uri}) async {
  try {
    await _auth.getSessionFromUrl(uri ?? _link);
  } on AuthException catch (e, st) {
    // ignore: invalid_use_of_internal_member
    _auth.notifyException(e, st);
  }
}

Iterable<Sent> get _passwordWrites => _server.of('user', method: 'PUT');

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await initAccountSupabase(_server, _realtime, _store);
    // A failed exchange is an event here; somebody must always be listening.
    _auth.onAuthStateChange.listen((_) {}, onError: (Object _) {});
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _server.reset();
    _store.m.clear();
    _failures.clear();
    passwordRecoveryNotifier.value = null;
    accountReadFailureNotifier.value = null;
    setFailureSink(_failures.add);
    addTearDown(resetFailureSink);
    for (final (id, name) in [(acctA, 'Alba'), (acctB, 'Bruno')]) {
      _server.rows['user_profiles:$id'] = [
        {'id': id, 'role': 'client', 'onboarding_complete': true, 'first_name': name}
      ];
    }
  });

  Finder field(int i) => find.byType(TextField).at(i);
  String typed(WidgetTester t, int i) =>
      t.widget<TextField>(field(i)).controller!.text;

  Future<void> type(WidgetTester t, String pw) async {
    await t.enterText(field(0), pw);
    await t.enterText(field(1), pw);
    await t.pump();
  }

  group('the form, without AccountScope', () {
    Future<void> mountForm(WidgetTester t, {bool recovery = true}) async {
      await t.runAsync(signOut);
      await t.runAsync(() => signInAs(acctA));
      if (recovery) startPasswordRecovery(acctA);
      final router = GoRouter(initialLocation: '/reset-password', routes: [
        GoRoute(
            path: '/reset-password',
            builder: (_, __) => const ResetPasswordScreen()),
        GoRoute(
            path: '/login', builder: (_, __) => const Scaffold(body: Text('SIGN-IN'))),
      ]);
      addTearDown(router.dispose);
      await t.pumpWidget(MaterialApp.router(routerConfig: router));
      await settleApp(t, 3);
      expect(find.text('Set a new password'), findsOneWidget);
    }

    Future<void> end(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.runAsync(signOut);
      await t.pump(const Duration(seconds: 5));
    }

    for (final (what, change) in [
      ('A -> B', () => signInAs(acctB)),
      ('A signed out', signOut),
      ("A's session ended remotely", () => expire(_server)),
    ]) {
      testWidgets('$what: Update sends nothing, clears and leaves', (t) async {
        await mountForm(t);
        await type(t, 'alba-new-pw');
        final update = t.widget<AuthButton>(find.byType(AuthButton)).onTap!;
        // The press lands after the switch and before the screen has rebuilt.
        await t.runAsync(() async {
          await change();
          update();
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await settleApp(t);
        expect(_passwordWrites, isEmpty,
            reason: 'THE defect: the password of whoever is signed in was set');
        expect(find.text('SIGN-IN'), findsOneWidget, reason: 'the form is left');
        expect(passwordRecoveryNotifier.value, isNull);
        expect(_failures.where((f) => '${f.error}'.contains('account changed')),
            isNotEmpty);
        await end(t);
      });
    }

    testWidgets('A -> B clears what A typed without waiting for a press',
        (t) async {
      await mountForm(t);
      await type(t, 'alba-new-pw');
      final pw = t.widget<TextField>(field(0)).controller!;
      await t.runAsync(() => signInAs(acctB));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      expect(pw.text, isEmpty);
      await settleApp(t);
      expect(find.text('SIGN-IN'), findsOneWidget);
      await end(t);
    });

    testWidgets('A -> B while the update is out: no success shown to B, and the '
        "session is B's own", (t) async {
      await mountForm(t);
      await type(t, 'alba-new-pw');
      final hold = _server.holds['PUT user:$acctA'] = Completer<void>();
      await t.tap(find.text('Update Password'));
      await settleApp(t, 2);
      expect(_passwordWrites.map((s) => s.who), [acctA]);
      await t.runAsync(() => signInAs(acctB));
      await settleApp(t, 2);
      hold.complete();
      await settleApp(t);
      expect(_passwordWrites.map((s) => s.who), [acctA], reason: 'one, by A');
      expect(find.text('Password updated'), findsNothing);
      expect(find.text('SIGN-IN'), findsOneWidget);
      await pumpUntil(t, () => _auth.currentUser?.id == acctB,
          what: "B's own user back on B's session");
      expect(AccountServer.sub(_auth.currentSession!.accessToken), acctB);
      await end(t);
    });

    testWidgets("the done page: B arrives, and A's Back to Sign In cannot sign "
        'B out', (t) async {
      await mountForm(t);
      await type(t, 'alba-new-pw');
      await t.tap(find.text('Update Password'));
      await settleApp(t, 4);
      expect(find.text('Password updated'), findsOneWidget);
      final back = t.widget<AuthButton>(find.byType(AuthButton)).onTap!;
      _server.sent.clear();
      await t.runAsync(() async {
        await signInAs(acctB);
        back();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await settleApp(t);
      expect(_server.of('logout'), isEmpty, reason: 'B stays signed in');
      expect(_auth.currentUser?.id, acctB);
      expect(find.text('SIGN-IN'), findsOneWidget);
      await end(t);
    });

    for (final recovery in [true, false]) {
      testWidgets(
          'control: the same account (${recovery ? 'recovery' : 'opened by hand'}) '
          'updates once, through a token refresh that keeps what is typed',
          (t) async {
        await mountForm(t, recovery: recovery);
        await type(t, 'alba-new-pw');
        await t.runAsync(_auth.refreshSession);
        await settleApp(t, 3);
        expect(typed(t, 0), 'alba-new-pw');
        await t.tap(find.text('Update Password'));
        await settleApp(t, 4);
        expect(_passwordWrites, hasLength(1));
        expect(_passwordWrites.single.who, acctA);
        expect(_passwordWrites.single.body, contains('alba-new-pw'));
        expect(find.text('Password updated'), findsOneWidget);
        expect(passwordRecoveryNotifier.value, isNull);
        await t.tap(find.text('Back to Sign In'));
        await settleApp(t);
        expect(_auth.currentSession, isNull);
        expect(find.text('SIGN-IN'), findsOneWidget);
        await end(t);
      });
    }

    testWidgets('control: a refused update keeps the form and what was typed',
        (t) async {
      await mountForm(t);
      await type(t, 'alba-new-pw');
      _server.fails['PUT user:$acctA'] = 422;
      await t.tap(find.text('Update Password'));
      await settleApp(t, 4);
      expect(find.text('Set a new password'), findsOneWidget);
      expect(typed(t, 0), 'alba-new-pw');
      expect(find.byType(SnackBar), findsOneWidget);
      expect(passwordRecoveryNotifier.value, acctA, reason: 'still recovering');
      await end(t);
    });
  });

  group('the recovery, under the real app root', () {
    Future<void> pumpRoot(WidgetTester t) async {
      t.view.physicalSize = const Size(900, 2600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(CircleFitnessRoot(theme: ThemeData.dark(), overrides: [
        clientPlanProvider.overrideWith((ref) async => ClientPlan.coachGuided),
      ]));
      await settleApp(t, 4);
    }

    /// Runs [body] from nobody signed in, and unmounts whatever happened.
    void rootTest(String name, Future<void> Function(WidgetTester t) body) =>
        testWidgets(name, (t) async {
          await t.runAsync(signOut);
          try {
            await body(t);
            expect(t.takeException(), isNull);
          } finally {
            await unmountApp(t, _server);
          }
        });

    Future<void> expectFormWorksFor(WidgetTester t, String uid) async {
      expect(appPath(t), '/reset-password');
      _server.sent.clear();
      await type(t, 'a-new-pw');
      await t.tap(find.text('Update Password'));
      await settleApp(t, 4);
      expect(_passwordWrites.map((s) => s.who), [uid]);
      expect(find.text('Password updated'), findsOneWidget);
    }

    rootTest('control: the event path — the link opens the form and updates once',
        (t) async {
      await pumpRoot(t);
      appRouter(t).go('/login');
      await settleApp(t);
      _store.askedForReset();
      _server.codeSession = sessionOf(acctA);
      await t.runAsync(_openLink);
      await settleApp(t);
      expect(passwordRecoveryNotifier.value, acctA);
      await expectFormWorksFor(t, acctA);
      await t.tap(find.text('Back to Sign In'));
      await settleApp(t);
      expect(appPath(t), '/login');
      expect(_auth.currentSession, isNull);
    });

    rootTest("B signed in, A opens A's link: A's form, on A's account only",
        (t) async {
      await t.runAsync(() => signInAs(acctB));
      await pumpRoot(t);
      appRouter(t).go('/settings');
      await settleApp(t);
      _store.askedForReset();
      _server.codeSession = sessionOf(acctA);
      await t.runAsync(_openLink);
      await settleApp(t);
      await expectFormWorksFor(t, acctA);
    });

    rootTest('control: the ?recovery=1 launch path opens the form for its account',
        (t) async {
      _store.askedForReset();
      _server.codeSession = sessionOf(acctA);
      await t.runAsync(_openLink);
      await t.runAsync(() => bindPasswordRecoveryAtLaunch(_link));
      await pumpRoot(t);
      appRouter(t).go('/home'); // the splash hands off
      await settleApp(t);
      await expectFormWorksFor(t, acctA);
    });

    rootTest('the launch link fails while B is signed in: B is left alone',
        (t) async {
      await t.runAsync(() => signInAs(acctB));
      _store.askedForReset();
      _server.codeSession = null; // expired
      await t.runAsync(_openLink);
      await t.runAsync(() => bindPasswordRecoveryAtLaunch(_link));
      expect(_auth.currentUser?.id, acctB, reason: 'gotrue leaves B signed in');
      expect(passwordRecoveryNotifier.value, isNull,
          reason: 'THE defect: ?recovery=1 alone forced B onto the form');
      await pumpRoot(t);
      appRouter(t).go('/home');
      await settleApp(t);
      expect(appPath(t), '/home');
    });

    rootTest('the launch link fails signed out: whoever signs in later is not '
        'forced onto the form', (t) async {
      _store.askedForReset();
      await t.runAsync(_openLink);
      await t.runAsync(() => bindPasswordRecoveryAtLaunch(_link));
      await pumpRoot(t);
      appRouter(t).go('/login');
      await settleApp(t);
      expect(appPath(t), '/login');
      await t.runAsync(() => signInAs(acctB));
      await settleApp(t);
      expect(appPath(t), '/home');
      expect(passwordRecoveryNotifier.value, isNull);
    });

    rootTest('a link that carries no code starts nothing', (t) async {
      await t.runAsync(() => signInAs(acctB));
      await t.runAsync(() => bindPasswordRecoveryAtLaunch(
          Uri.parse('https://app.example/?recovery=1')));
      expect(passwordRecoveryNotifier.value, isNull);
      await t.runAsync(() => bindPasswordRecoveryAtLaunch(
          Uri.parse('https://app.example/#type=recovery')));
      expect(passwordRecoveryNotifier.value, isNull);
    });

    for (final (who, bound) in [(acctA, acctA), (acctB, null)]) {
      rootTest(
          'a reload of A\'s form (the code is spent) with '
          '${bound == null ? 'B' : 'A'} signed in: '
          '${bound == null ? 'nothing' : "A's form again"}', (t) async {
        SharedPreferences.setMockInitialValues(
            {passwordRecoveryStorageKey: acctA});
        await t.runAsync(() => signInAs(who));
        await t.runAsync(_openLink); // no verifier any more: refused
        await t.runAsync(() => bindPasswordRecoveryAtLaunch(_link));
        expect(passwordRecoveryNotifier.value, bound);
        await pumpRoot(t);
        appRouter(t).go('/home');
        await settleApp(t);
        expect(appPath(t), bound == null ? '/home' : '/reset-password');
      });
    }

    for (final (what, change, dest) in [
      ('another account', () => signInAs(acctB), '/home'),
      ('a sign-out', signOut, '/login'),
    ]) {
      rootTest('$what ends the recovery, and forces nobody', (t) async {
        _store.askedForReset();
        _server.codeSession = sessionOf(acctA);
        await t.runAsync(_openLink);
        await t.runAsync(() => bindPasswordRecoveryAtLaunch(_link));
        await pumpRoot(t);
        appRouter(t).go('/home');
        await settleApp(t);
        expect(appPath(t), '/reset-password', reason: 'premise');
        await type(t, 'alba-new-pw');
        await t.runAsync(change);
        await settleApp(t);
        expect(passwordRecoveryNotifier.value, isNull);
        expect(appPath(t), dest);
        expect(find.byType(ResetPasswordScreen), findsNothing);
        expect(_passwordWrites, isEmpty);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(passwordRecoveryStorageKey), isNull);
      });
    }
  });

  // ── A-29 · the redirect's role read ───────────────────────────────────────

  group("the router's role read is the account signed in now's", () {
    for (final (what, aFails) in [('a role', false), ('a failure', true)]) {
      testWidgets("$what of A's that lands after A -> B never routes B",
          (t) async {
        await t.runAsync(signOut);
        try {
          _server.rows['user_profiles:$acctA']!.first['role'] = 'coach';
          await t.runAsync(() => signInAs(acctA));
          final hold =
              _server.holds['GET user_profiles:$acctA'] = Completer<void>();
          if (aFails) _server.fails['GET user_profiles:$acctA'] = 403;
          await t.pumpWidget(CircleFitnessRoot(theme: ThemeData.dark()));
          await settleApp(t, 2);
          final router = appRouter(t);
          final redirect = router.configuration.topRedirect;
          final state = _StateAt('/login');
          final ctx = t.element(find.byType(MaterialApp));
          final answer = Future.value(redirect(ctx, state));
          await settleApp(t, 2);
          // B is signed in; this router's read for A is still out.
          await t.runAsync(() => signInAs(acctB));
          hold.complete();
          String? to = 'unanswered';
          unawaited(answer.then((v) => to = v));
          await settleApp(t);
          expect(to, '/home',
              reason: "B's own role; A's is a coach's (or unread)");
          expect(accountReadFailureNotifier.value, isNull);
        } finally {
          await unmountApp(t, _server);
        }
      });
    }

    testWidgets('signed out meanwhile: the auth route stays', (t) async {
      await t.runAsync(signOut);
      try {
        _server.rows['user_profiles:$acctA']!.first['role'] = 'coach';
        await t.runAsync(() => signInAs(acctA));
        final hold =
            _server.holds['GET user_profiles:$acctA'] = Completer<void>();
        await t.pumpWidget(CircleFitnessRoot(theme: ThemeData.dark()));
        await settleApp(t, 2);
        final redirect = appRouter(t).configuration.topRedirect;
        final answer = Future.value(
            redirect(t.element(find.byType(MaterialApp)), _StateAt('/login')));
        await t.runAsync(signOut);
        hold.complete();
        String? to = 'unanswered';
        unawaited(answer.then((v) => to = v));
        await settleApp(t);
        expect(to, isNull);
      } finally {
        await unmountApp(t, _server);
      }
    });

    testWidgets('control: one account, one read, its own role', (t) async {
      await t.runAsync(signOut);
      try {
        _server.rows['user_profiles:$acctA']!.first['role'] = 'vendor';
        await t.runAsync(() => signInAs(acctA));
        await t.pumpWidget(CircleFitnessRoot(theme: ThemeData.dark()));
        await settleApp(t, 2);
        _server.sent.clear();
        final redirect = appRouter(t).configuration.topRedirect;
        String? to = 'unanswered';
        unawaited(Future.value(redirect(
                t.element(find.byType(MaterialApp)), _StateAt('/login')))
            .then((v) => to = v));
        await settleApp(t);
        expect(to, '/vendor-portal');
        expect(_server.of('user_profiles', by: acctA), hasLength(1));
      } finally {
        await unmountApp(t, _server);
      }
    });
  });
}

/// The part of a [GoRouterState] the app's redirect reads.
class _StateAt implements GoRouterState {
  _StateAt(this.matchedLocation);
  @override
  final String matchedLocation;
  @override
  Uri get uri => Uri.parse(matchedLocation);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
