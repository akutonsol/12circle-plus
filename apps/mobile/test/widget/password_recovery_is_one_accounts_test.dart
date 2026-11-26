import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/core/identity/account_scope.dart';
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

const _notSet = "Couldn't set the new password — the account signed in here "
    'changed. Ask for a new reset link.';

/// With nobody signed in.
const _notSetSignedOut = "Couldn't set the new password — the account changed. "
    'Ask for a new reset link.';

const _notSignedOut = "Couldn't sign you out — try again in a moment. If it "
    'keeps happening, contact support.';

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
    accountNoticeNotifier.value = null;
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

    for (final (what, change, said) in [
      ('A -> B', () => signInAs(acctB), _notSet),
      ('A signed out', signOut, _notSetSignedOut),
      ("A's session ended remotely", () => expire(_server), _notSetSignedOut),
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
        expect(find.text(said), findsOneWidget,
            reason: 'and why is said where it lands');
        expect(find.byType(SnackBar), findsOneWidget);
        expect(t.widget<Text>(find.text(said)).data, isNot(contains(acctB)));
        expect(passwordRecoveryNotifier.value, isNull);
        expect(_failures.where((f) => '${f.error}'.contains('account changed')),
            isNotEmpty);
        await end(t);
      });
    }

    testWidgets("B's own recovery took the form over, with no frame between: the "
        "press sends nothing, the form stays, and says so on it", (t) async {
      await mountForm(t);
      await type(t, 'alba-new-pw');
      final update = t.widget<AuthButton>(find.byType(AuthButton)).onTap!;
      startPasswordRecovery(acctB);
      await t.runAsync(() async {
        // The session is B's at once; no one has been told yet.
        unawaited(signInAs(acctB));
        update();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await settleApp(t);
      expect(_passwordWrites, isEmpty);
      expect(find.text('Set a new password'), findsOneWidget);
      expect(typed(t, 0), isEmpty);
      expect(find.text(_notSet), findsOneWidget);
      expect(passwordRecoveryNotifier.value, acctB);
      await end(t);
    });

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

    // Round 5 (59a-m17): the update that answers after the switch sets no
    // password for B, and is recorded as not done for A, where it was caught.
    // The control is the same account, through an event that really fires.
    for (final switched in [true, false]) {
      testWidgets(
          switched
              ? 'A -> B while the update is out: the answer is recorded as '
                  "the account's change, at the submit"
              : 'control: the same account renewed while the update is out: '
                  'nothing recorded, the done page', (t) async {
        await mountForm(t);
        await type(t, 'alba-new-pw');
        final hold = _server.holds['PUT user:$acctA'] = Completer<void>();
        await t.tap(find.text('Update Password'));
        await settleApp(t, 2);
        expect(_passwordWrites.map((s) => s.who), [acctA], reason: 'premise');
        await t.runAsync(switched ? () => signInAs(acctB) : renewToken);
        await settleApp(t, 2);
        _failures.clear(); // only what the answer brings
        hold.complete();
        await settleApp(t);
        final atSubmit = _failures.where((f) =>
            f.origin == 'ResetPasswordScreen._submit' &&
            '${f.error}'.contains('set new password: the signed-in account '
                'changed'));
        if (switched) {
          expect(atSubmit, hasLength(1),
              reason: 'THE defect: an update answered for nobody it may be '
                  'said to, and recorded nowhere');
          expect(find.text('Password updated'), findsNothing);
        } else {
          expect(_failures, isEmpty);
          expect(find.text('Password updated'), findsOneWidget);
        }
        await end(t);
      });
    }

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

    /// A's password set, and "Back to Sign In" on screen.
    Future<void> reachDone(WidgetTester t) async {
      await mountForm(t);
      await type(t, 'alba-new-pw');
      await t.tap(find.text('Update Password'));
      await settleApp(t, 4);
      expect(find.text('Password updated'), findsOneWidget, reason: 'premise');
    }

    testWidgets('the done page: the device keeps the session — said, every time, '
        'and not left for the sign-in page until it is gone', (t) async {
      addTearDown(() => _store.refuseRemoval = false);
      await reachDone(t);
      final told = <AuthState>[];
      final sub = _auth.onAuthStateChange.listen(told.add);
      _store.refuseRemoval = true;
      // The second press finds nobody signed in, and the session still stored.
      for (final press in ['first', 'second']) {
        await t.tap(find.text('Back to Sign In'));
        await settleApp(t);
        expect(find.text(_notSignedOut), findsOneWidget, reason: press);
        expect(find.text('Password updated'), findsOneWidget, reason: press);
        expect(find.text('SIGN-IN'), findsNothing,
            reason: 'THE defect: as if signed out; the next start signs in');
        expect(find.textContaining('storage'), findsNothing);
        await t.pump(const Duration(seconds: 6));
        await settleApp(t);
        expect(find.byType(SnackBar), findsNothing);
      }
      expect(told.map((s) => s.event),
          isNot(contains(AuthChangeEvent.signedOut)), reason: 'why');
      _store.refuseRemoval = false;
      await t.tap(find.text('Back to Sign In'));
      await settleApp(t);
      expect(told.last.event, AuthChangeEvent.signedOut);
      expect(find.text('SIGN-IN'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      unawaited(sub.cancel());
      await end(t);
    });

    testWidgets('the done page: B arrives while the device refuses — nothing is '
        'said to B, and B stays signed in', (t) async {
      addTearDown(() {
        _store.refuseRemoval = false;
        _store.holdRemoval = null;
      });
      await reachDone(t);
      final back = t.widget<AuthButton>(find.byType(AuthButton)).onTap!;
      _store.refuseRemoval = true;
      final hold = _store.holdRemoval = Completer<void>();
      _server.sent.clear();
      await t.runAsync(() async {
        back();
        await signInAs(acctB);
        hold.complete();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await settleApp(t);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('SIGN-IN'), findsOneWidget, reason: "not A's page");
      expect(_auth.currentUser?.id, acctB);
      expect(_server.of('logout'), isEmpty);
      _store.refuseRemoval = false;
      await end(t);
    });

    testWidgets('control: the server refuses the sign-out — the device is signed '
        'out, nothing is said', (t) async {
      await reachDone(t);
      _server.fails['POST logout'] = 500;
      await t.tap(find.text('Back to Sign In'));
      await settleApp(t);
      expect(_auth.currentSession, isNull);
      expect(find.text('SIGN-IN'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      _server.fails.clear();
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

    for (final (what, change, dest, said) in [
      ('A -> B', () => signInAs(acctB), '/home', _notSet),
      ('A signed out', signOut, '/login', _notSetSignedOut),
    ]) {
      rootTest('$what, then Update before any frame: one neutral line where the '
          'member lands, once', (t) async {
        _store.askedForReset();
        _server.codeSession = sessionOf(acctA);
        await t.runAsync(_openLink);
        await t.runAsync(() => bindPasswordRecoveryAtLaunch(_link));
        await pumpRoot(t);
        appRouter(t).go('/home');
        await settleApp(t);
        await type(t, 'alba-new-pw');
        final update = t.widget<AuthButton>(find.byType(AuthButton)).onTap!;
        await t.runAsync(() async {
          await change();
          update();
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        final handle = t.ensureSemantics();
        await settleApp(t);
        expect(_passwordWrites, isEmpty);
        expect(appPath(t), dest);
        expect(find.text(said), findsOneWidget);
        expect(
            find.ancestor(
                of: find.text(said),
                matching: find.byWidgetPredicate(
                    (w) => w is Semantics && w.properties.liveRegion == true)),
            findsWidgets);
        handle.dispose();
        await t.pump(const Duration(seconds: 6));
        await settleApp(t);
        expect(find.text(said), findsNothing, reason: 'not left standing');
        // Nor said again to whoever comes next.
        await t.runAsync(dest == '/home' ? signOut : () => signInAs(acctB));
        await settleApp(t);
        expect(find.text(said), findsNothing);
      });
    }

    rootTest('a notice left for another account is not said to this one',
        (t) async {
      await t.runAsync(() => signInAs(acctA));
      await pumpRoot(t);
      accountNoticeNotifier.value = (uid: null, text: _notSet);
      await t.runAsync(() => signInAs(acctB));
      await settleApp(t);
      expect(appPath(t), '/home');
      expect(find.text(_notSet), findsNothing);
      expect(accountNoticeNotifier.value, isNull);
    });

    rootTest("another tab's sign-in is not the launch link's: nobody is bound",
        (t) async {
      await t.runAsync(() => signInAs(acctB));
      // The link has no code; the last thing heard is B's, from another tab.
      await t.runAsync(() => sameMemberInAnotherTab(acctB));
      await t.runAsync(() => bindPasswordRecoveryAtLaunch(_link));
      expect(passwordRecoveryNotifier.value, isNull);
    });

    rootTest("nor is a mixed session", (t) async {
      await t.runAsync(() => signInAs(acctB));
      await t.runAsync(() async {
        final mixed = Session.fromJson(jsonDecode(
            jsonEncode(sessionOf(acctB)..['user'] = userOf(acctA))))!;
        // ignore: invalid_use_of_internal_member
        _auth.notifyAllSubscribers(AuthChangeEvent.signedIn, session: mixed);
        await bindPasswordRecoveryAtLaunch(_link);
      });
      expect(passwordRecoveryNotifier.value, isNull);
    });

    for (final (what, change) in [
      ('a sign-out', signOut),
      ('another account', () => signInAs(acctB)),
    ]) {
      rootTest('a note kept from an earlier run (nothing in memory) goes with '
          '$what', (t) async {
        SharedPreferences.setMockInitialValues(
            {passwordRecoveryStorageKey: acctA});
        await t.runAsync(() => signInAs(acctA));
        await pumpRoot(t);
        Future<String?> note() async => (await SharedPreferences.getInstance())
            .getString(passwordRecoveryStorageKey);
        await t.runAsync(renewToken);
        await settleApp(t, 2);
        expect(await note(), acctA, reason: 'control: the same account keeps it');
        await t.runAsync(change);
        await settleApp(t, 2);
        expect(passwordRecoveryNotifier.value, isNull);
        expect(await note(), isNull);
      });
    }

    rootTest("control: A's link after a sign-out keeps its own note", (t) async {
      SharedPreferences.setMockInitialValues(
          {passwordRecoveryStorageKey: acctB});
      await t.runAsync(() => signInAs(acctB));
      await pumpRoot(t);
      _store.askedForReset();
      _server.codeSession = sessionOf(acctA);
      await t.runAsync(_openLink);
      await settleApp(t);
      expect(passwordRecoveryNotifier.value, acctA);
      expect(
          (await SharedPreferences.getInstance())
              .getString(passwordRecoveryStorageKey),
          acctA);
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

    // Round 5 (59a-m18). The redirect's own uid check is the only guard while
    // the recovery this process holds is A's and the session is already B's,
    // before the router has heard of B: the first redirect of a launch runs
    // when the router is built, and the auth stream answers it only after.
    // Here: A's form reloaded (the note is A's, A signed in: A's recovery),
    // and B's session arrives from another tab before the app has drawn.
    for (final (who, dest) in [(acctB, '/home'), (acctA, '/reset-password')]) {
      rootTest(
          "a reload of A's form, with "
          '${who == acctB ? "B's session there before the router heard of it: "
              'B is not forced onto the form' : "control: A still A's: A's form"}',
          (t) async {
        t.binding.platformDispatcher.defaultRouteNameTestValue = '/home';
        addTearDown(
            t.binding.platformDispatcher.clearDefaultRouteNameTestValue);
        SharedPreferences.setMockInitialValues(
            {passwordRecoveryStorageKey: acctA});
        await t.runAsync(() => signInAs(acctA));
        await t.runAsync(_openLink); // the code is spent: refused
        await t.runAsync(() => bindPasswordRecoveryAtLaunch(_link));
        expect(passwordRecoveryNotifier.value, acctA, reason: 'premise');
        if (who == acctB) await t.runAsync(() => signInAs(acctB));
        expect(passwordRecoveryNotifier.value, acctA,
            reason: 'premise: no router has heard of B yet');
        await pumpRoot(t);
        await settleApp(t);
        expect(appPath(t), dest);
        if (who == acctB) {
          expect(find.byType(ResetPasswordScreen), findsNothing,
              reason: 'THE defect: B forced onto a reset form it never asked '
                  'for, with no link');
          expect(passwordRecoveryNotifier.value, isNull);
        } else {
          expect(find.text('Set a new password'), findsOneWidget);
          expect(passwordRecoveryNotifier.value, acctA);
        }
        expect(_passwordWrites, isEmpty);
      });
    }

    for (final (what, change) in [
      ('another account', () => signInAs(acctB)),
      ('a sign-out', signOut),
    ]) {
      rootTest('$what ends the recovery even before the form was opened',
          (t) async {
        _store.askedForReset();
        _server.codeSession = sessionOf(acctA);
        await t.runAsync(_openLink);
        await t.runAsync(() => bindPasswordRecoveryAtLaunch(_link));
        await pumpRoot(t);
        expect(appPath(t), '/splash', reason: 'premise: no form yet');
        expect(passwordRecoveryNotifier.value, acctA);
        await t.runAsync(change);
        await settleApp(t);
        expect(passwordRecoveryNotifier.value, isNull);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(passwordRecoveryStorageKey), isNull);
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
