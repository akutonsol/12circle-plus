import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/core/identity/account_scope.dart';
import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/core/router/app_router.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/auth/presentation/reset_password_screen.dart';
import 'package:circle_fitness/features/payments/domain/entitlements.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/account_app.dart';

// P0-FL-59a round 2, item 1 — A's password update answers after B has signed in.
//
// gotrue's `updateUser` copies the ANSWERED user (A) onto whatever session is
// current by then (B's token) and tells every listener and every other tab.
// AccountScope began a generation for A on B's token, every
// `currentUser.id == owner` guard in the app passed for A, and unless the
// refresh that followed succeeded it stayed so (and was stored for the next
// start).
//
// HOW TO SEE IT FAIL: lib files at 4917961.

final _server = AccountServer();
final _realtime = FakeRealtime();
final _store = MemoryStore();
final _stored = MemorySession();

/// How often the device was asked to take the first reminder id off.
var _sweeps = 0;

GoTrueClient get _auth => Supabase.instance.client.auth;

const _acctC = 'acc7c000-0000-4000-8000-00000000000c';

/// What gotrue tells the other tabs: everything but `initialSession`, and what
/// they told it.
Iterable<AuthState> _goesOut(Iterable<AuthState> heard) => heard.where((s) =>
    !s.fromBroadcast && s.event != AuthChangeEvent.initialSession);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dexterous.com/flutter/local_notifications'),
            (call) async {
      if (call.method == 'cancel' && (call.arguments as Map)['id'] == 1000) {
        _sweeps++;
      }
      return call.method == 'initialize' ? true : null;
    });
    await initAccountSupabase(_server, _realtime, _store, session: _stored);
    _auth.onAuthStateChange.listen((_) {}, onError: (Object _) {});
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _server.reset();
    passwordRecoveryNotifier.value = null;
    accountReadFailureNotifier.value = null;
    setFailureSink((_) {});
    addTearDown(resetFailureSink);
    for (final (id, name) in [
      (acctA, 'Alba'),
      (acctB, 'Bruno'),
      (_acctC, 'Carla'),
    ]) {
      _server.rows['user_profiles:$id'] = [
        {'id': id, 'role': 'client', 'onboarding_complete': true, 'first_name': name}
      ];
    }
  });

  Future<void> tick(WidgetTester t) => t
      .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));

  Future<void> type(WidgetTester t, String pw) async {
    await t.enterText(find.byType(TextField).at(0), pw);
    await t.enterText(find.byType(TextField).at(1), pw);
    await t.pump();
  }

  Completer<void> holdToken() =>
      _server.holds['POST token'] = Completer<void>();

  /// Whatever a test that failed left unanswered: gotrue keeps waiting for a
  /// token refresh, and so would every test after it.
  void releaseHolds() {
    for (final hold in _server.holds.values) {
      if (!hold.isCompleted) hold.complete();
    }
  }

  tearDown(releaseHolds);

  void expectBsOwnSession(String when) {
    expect(_auth.currentUser?.id, acctB, reason: when);
    expect(AccountServer.sub(_auth.currentSession!.accessToken), acctB);
  }

  group('under the app root', () {
    /// A's form with the update out, then B signed in on a page of B's own.
    Future<Completer<void>> updateOutAndBIn(WidgetTester t) async {
      await mountApp(t, as: acctA, overrides: [
        clientPlanProvider.overrideWith((ref) async => ClientPlan.coachGuided),
      ]);
      startPasswordRecovery(acctA);
      appRouter(t).go('/home');
      await settleApp(t);
      expect(appPath(t), '/reset-password', reason: 'premise');
      await type(t, 'alba-new-pw');
      final hold = _server.holds['PUT user:$acctA'] = Completer<void>();
      await t.tap(find.text('Update Password'));
      await settleApp(t, 2);
      expect(_server.of('user', method: 'PUT').map((s) => s.who), [acctA]);
      return hold;
    }

    void rootTest(String name, Future<void> Function(WidgetTester t) body) =>
        testWidgets(name, (t) async {
          try {
            await body(t);
            expect(t.takeException(), isNull);
          } finally {
            releaseHolds();
            await unmountApp(t, _server);
          }
        });

    void expectBsGenerationUntouched(WidgetTester t, int from) {
      final generation = appContainer(t).read(accountGenerationProvider);
      expect((generation.number, generation.startedAs), (1, acctB));
      expect(appContainer(t).read(currentUserProvider)?.id, acctB);
      for (final s in _server.sent.skip(from)) {
        expect(s.who, acctB, reason: 'as whom: $s');
        expect('${s.url}${s.body}', isNot(contains(acctA)), reason: '$s');
      }
      expect(_stored.who, (acctB, acctB), reason: 'what the next start restores');
    }

    for (final (what, refresh) in [
      ('answers', () {}),
      ('is refused (503)', () => _server.fails['POST token'] = 503),
      ('never arrives', () => _server.drops.add('POST token')),
    ]) {
      rootTest("A's answer after A -> B, where a token refresh $what: B's app is "
          "B's, and keeps B's draft", (t) async {
        final hold = await updateOutAndBIn(t);
        _sweeps = 0;
        await t.runAsync(() => signInAs(acctB));
        await settleApp(t);
        expect(appPath(t), '/home', reason: 'premise: B is in');
        appRouter(t).go('/forgot-password');
        await settleApp(t);
        await t.enterText(find.byType(TextField).first, 'bruno@draft');
        final gen = appContainer(t);
        refresh();

        final from = _server.sent.length;
        hold.complete();
        await tick(t);
        expectBsOwnSession('at once, before any frame');
        await settleApp(t, 40);

        expectBsOwnSession('and later');
        expect(appContainer(t), same(gen), reason: "B's generation, not another");
        expectBsGenerationUntouched(t, from);
        expect(appPath(t), '/forgot-password');
        expect(
            t.widget<TextField>(find.byType(TextField).first).controller!.text,
            'bruno@draft');
        expect(_sweeps, 1, reason: "A's reminders, once");
        expect(_realtime.joinedFor(acctA), isEmpty);
        expect(_server.of('token'), isEmpty, reason: 'put back with no network');
        expect(find.text('Password updated'), findsNothing);
      });
    }

    rootTest('no frame between B arriving and the answer: B begins one '
        'generation, as B', (t) async {
      final hold = await updateOutAndBIn(t);
      _sweeps = 0;
      _server.fails['POST token'] = 503;
      final from = _server.sent.length;
      await t.runAsync(() async {
        await signInAs(acctB);
        hold.complete();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      expectBsOwnSession('before any frame');
      await settleApp(t, 40);
      expectBsGenerationUntouched(t, from);
      expect(appPath(t), '/home');
      expect(_sweeps, 1);
    });

    rootTest('B signed out again meanwhile: the answer brings nobody back',
        (t) async {
      final hold = await updateOutAndBIn(t);
      await t.runAsync(() => signInAs(acctB));
      await settleApp(t);
      await t.runAsync(signOut);
      await settleApp(t);
      hold.complete();
      await settleApp(t);
      expect(_auth.currentSession, isNull);
      expect(_stored.stored, isNull);
      expect(appPath(t), '/login');
    });

    rootTest("a mixed session from anywhere else than the form is put right, and "
        "neither moves the app nor the watcher, nor ends B's recovery",
        (t) async {
      await mountApp(t, as: acctA, overrides: [
        clientPlanProvider.overrideWith((ref) async => ClientPlan.coachGuided),
      ]);
      final hold = _server.holds['PUT user:$acctA'] = Completer<void>();
      // Not the form's, so not the form's to put back.
      unawaited(_auth.updateUser(UserAttributes(data: {'x': 1})).then((_) {}));
      await settleApp(t, 1);
      await t.runAsync(() => signInAs(acctB));
      await settleApp(t);
      appRouter(t).go('/home');
      await settleApp(t);
      final gen = appContainer(t);
      final channels = _realtime.joinedFor(acctB).toList();
      expect(channels, isNotEmpty, reason: 'premise: the watcher is on B');
      startPasswordRecovery(acctB);
      await settleApp(t);
      expect(appPath(t), '/reset-password');
      await type(t, 'bruno-new-pw');

      final heard = <AuthState>[];
      final sub = _auth.onAuthStateChange.listen(heard.add);
      hold.complete();
      await tick(t);
      expect(heard.where((s) => isMixedSession(s.session)), isNotEmpty,
          reason: 'premise: every listener is told of the mixed one');
      unawaited(sub.cancel());
      expectBsOwnSession('at once');
      await settleApp(t);

      expect(appContainer(t), same(gen));
      expect(passwordRecoveryNotifier.value, acctB);
      expect(find.byType(ResetPasswordScreen), findsOneWidget);
      expect(t.widget<TextField>(find.byType(TextField).at(0)).controller!.text,
          'bruno-new-pw');
      expect(_realtime.joinedFor(acctA), isEmpty);
      // A coherent one, of B's, is a renewal.
      await t.runAsync(() => _auth.refreshSession());
      await settleApp(t);
      expectBsOwnSession('after a refresh');
      expect(appContainer(t), same(gen));
    });

    for (final expired in [false, true]) {
      for (final (what, leave, then, path) in [
        ('a sign-out', signOut, null, '/login'),
        ("C's sign-in", () => signInAs(_acctC), _acctC, '/home'),
      ]) {
        rootTest('a mixed session another tab told of (token '
            "${expired ? 'expired' : 'good'}) is put back here only, and $what "
            'that follows stands', (t) async {
          await mountApp(t, as: acctB, at: '/forgot-password', overrides: [
            clientPlanProvider.overrideWith((ref) async => ClientPlan.coachGuided),
          ]);
          final token = holdToken();
          final gen = appContainer(t);
          final heard = <AuthState>[];
          final sub = _auth.onAuthStateChange.listen(heard.add);
          await tick(t);
          heard.clear(); // the replayed one
          hearMixedFromAnotherTab(
              user: acctA, subject: acctB, expired: expired);
          await tick(t);
          expect(
              heard.where((s) => s.fromBroadcast && isMixedSession(s.session)),
              isNotEmpty,
              reason: 'premise');
          expectBsOwnSession('before any frame');
          expect(_goesOut(heard), isEmpty,
              reason: 'told on, it would undo what the other tabs did since');
          expect(_stored.who, (acctB, acctB));
          expect(appContainer(t), same(gen));

          // No frame since.
          await t.runAsync(leave);
          token.complete();
          await tick(t);
          expect(_auth.currentUser?.id, then, reason: 'B came back');
          expect(_stored.who, then == null ? null : (then, then));
          expect(_server.of('token'), isEmpty);
          await settleApp(t);
          final now = appContainer(t).read(accountGenerationProvider);
          expect((now.number, now.startedAs), (1, then));
          expect(appPath(t), path);
          unawaited(sub.cancel());
        });
      }
    }

    rootTest('control: one account — updated once, no new generation, its own '
        'session stored', (t) async {
      final hold = await updateOutAndBIn(t);
      final gen = appContainer(t);
      await t.runAsync(renewToken); // while it is out
      hold.complete();
      await settleApp(t);
      expect(find.text('Password updated'), findsOneWidget);
      expect(appContainer(t), same(gen));
      expect(_auth.currentUser?.id, acctA);
      expect(_stored.who, (acctA, acctA));
      expect(_server.of('user', method: 'PUT'), hasLength(1));
    });
  });

  group('the form, without AccountScope', () {
    Future<Completer<void>> updateOut(WidgetTester t) async {
      await t.runAsync(signOut);
      await t.runAsync(() => signInAs(acctA));
      startPasswordRecovery(acctA);
      final router = GoRouter(initialLocation: '/reset-password', routes: [
        GoRoute(
            path: '/reset-password',
            builder: (_, __) => const ResetPasswordScreen()),
        GoRoute(
            path: '/login',
            builder: (_, __) => const Scaffold(body: Text('SIGN-IN'))),
      ]);
      addTearDown(router.dispose);
      await t.pumpWidget(MaterialApp.router(routerConfig: router));
      await settleApp(t, 3);
      await type(t, 'alba-new-pw');
      final hold = _server.holds['PUT user:$acctA'] = Completer<void>();
      await t.tap(find.text('Update Password'));
      await settleApp(t, 2);
      return hold;
    }

    Future<void> end(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.runAsync(signOut);
      await t.pump(const Duration(seconds: 5));
    }

    /// A's answer mixes B's session, whose token has expired.
    Future<void> mixedOnExpiredToken(WidgetTester t) async {
      final hold = await updateOut(t);
      await t.runAsync(() => _auth
          .setInitialSession(jsonEncode(sessionOf(acctB, expired: true))));
      await settleApp(t, 2);
      hold.complete();
      await tick(t);
      expectBsOwnSession("B's user is put back");
      expect(_auth.currentSession!.isExpired, isTrue, reason: 'premise');
      expect(_stored.who, (acctB, acctB));
    }

    for (final (what, leave, then) in [
      ('a sign-out', signOut, null),
      ("C's sign-in", () => signInAs(_acctC), _acctC),
    ]) {
      testWidgets("B's own token has expired: B's user is put back with no request "
          'of ours, so $what is not undone by the answer', (t) async {
        final token = holdToken();
        await mixedOnExpiredToken(t);
        await t.runAsync(leave);
        token.complete();
        await tick(t);
        expect(_auth.currentUser?.id, then, reason: 'B came back');
        expect(_stored.who, then == null ? null : (then, then));
        expect(_server.of('token'), isEmpty);
        await end(t);
      });
    }

    for (final (what, renew) in [
      ('its next request', () async {
        await Supabase.instance.client.from('habits').select();
        expect(_server.of('habits').map((s) => s.who), [acctB]);
      }),
      ('its next tick', () async {
        _auth.startAutoRefresh();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        _auth.stopAutoRefresh();
      }),
    ]) {
      testWidgets('control: gotrue renews the expired token put back, at $what',
          (t) async {
        await mixedOnExpiredToken(t);
        await t.runAsync(renew);
        await tick(t);
        expectBsOwnSession('with the new token');
        expect(_auth.currentSession!.isExpired, isFalse);
        expect(_stored.who, (acctB, acctB));
        expect(_server.of('token').single.body, contains(acctB),
            reason: "asked for with B's");
        await end(t);
      });
    }

    for (final expired in [false, true]) {
      testWidgets('told of the mixed session by another tab (token '
          "${expired ? 'expired' : 'good'}): the form puts B back here only",
          (t) async {
        final hold = await updateOut(t);
        await t.runAsync(() => signInAs(acctB));
        await settleApp(t, 2);
        final heard = <AuthState>[];
        final sub = _auth.onAuthStateChange.listen(heard.add);
        await tick(t);
        heard.clear(); // the replayed one
        hearMixedFromAnotherTab(user: acctA, subject: acctB, expired: expired);
        await tick(t);
        expect(heard.where((s) => s.fromBroadcast && isMixedSession(s.session)),
            isNotEmpty, reason: 'premise');
        expectBsOwnSession('at once');
        expect(_goesOut(heard), isEmpty);
        expect(_server.of('token'), isEmpty);
        hold.complete();
        await tick(t);
        expect(_stored.who, (acctB, acctB));
        unawaited(sub.cancel());
        await end(t);
      });
    }

    testWidgets('told of one whose own user is not known here: nothing is asked',
        (t) async {
      await t.runAsync(signOut);
      await t.runAsync(() => signInAs(acctA));
      // A's user on B's token, with no event.
      await t.runAsync(() => _auth.recoverSession(
          jsonEncode(sessionOf(acctB)..['user'] = userOf(acctA))));
      expect(isMixedSession(_auth.currentSession), isTrue, reason: 'premise');
      for (final own in [
        null,
        Session.fromJson(jsonDecode(jsonEncode(sessionOf(_acctC)))),
      ]) {
        await t.runAsync(() => putBackOwnUser(own, fromBroadcast: true));
        expect(_server.of('token'), isEmpty);
      }
      // Control: this tab's own (what an earlier run stored) is asked about.
      await t.runAsync(() => putBackOwnUser(null));
      expectBsOwnSession('the answer');
      await end(t);
    });

    for (final refused in [true, false]) {
      testWidgets(
          "B's own recovery took the form over: A's ${refused ? 'refusal' : 'answer'} "
          "says nothing to B and clears nothing of B's", (t) async {
        final hold = await updateOut(t);
        if (refused) _server.fails['PUT user:$acctA'] = 422;
        startPasswordRecovery(acctB);
        await t.runAsync(() => signInAs(acctB));
        await settleApp(t, 2);
        expect(find.text('Set a new password'), findsOneWidget, reason: 'premise');
        await type(t, 'bruno-new-pw');
        hold.complete();
        await settleApp(t);
        expect(find.byType(SnackBar), findsNothing);
        expect(find.text('Password updated'), findsNothing);
        expect(
            t.widget<TextField>(find.byType(TextField).at(0)).controller!.text,
            'bruno-new-pw');
        expect(passwordRecoveryNotifier.value, acctB);
        expectBsOwnSession('B');
        await t.tap(find.text('Update Password'));
        await settleApp(t, 4);
        expect(_server.of('user', method: 'PUT').map((s) => s.who),
            [acctA, acctB]);
        expect(find.text('Password updated'), findsOneWidget);
        await end(t);
      });
    }

    testWidgets("A's form over a mixed session (A's user, B's token): Update "
        "does not set B's password", (t) async {
      await updateOut(t).then((h) => h.complete());
      await settleApp(t, 4);
      await t.pumpWidget(const SizedBox());
      // A's form again, nothing typed; then the session turns into a mixed one
      // with no event at all.
      await t.runAsync(signOut);
      await t.runAsync(() => signInAs(acctA));
      _server.holds.clear();
      _server.sent.clear();
      startPasswordRecovery(acctA);
      await t.pumpWidget(const MaterialApp(home: ResetPasswordScreen()));
      await settleApp(t, 2);
      await type(t, 'alba-new-pw');
      final mixed = sessionOf(acctB)..['user'] = userOf(acctA);
      await t.runAsync(() => _auth.recoverSession(jsonEncode(mixed)));
      await t.tap(find.text('Update Password'));
      await settleApp(t, 4);
      expect(_server.of('user', method: 'PUT'), isEmpty);
      await end(t);
    });
  });
}
