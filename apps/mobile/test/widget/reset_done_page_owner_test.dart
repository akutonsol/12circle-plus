import 'dart:async';

import 'package:circle_fitness/core/identity/account_scope.dart';
import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/core/router/app_router.dart';
import 'package:circle_fitness/features/auth/presentation/reset_password_screen.dart';
import 'package:circle_fitness/features/auth/presentation/widgets/auth_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/account_app.dart';

// P0-FL-59a round 4 — the reset form's done page (sec S2, ux note 1).
//
// - S2: B's own recovery made the form B's, with no frame since. A's drawn
//   "Back to Sign In" then passed its check (the form's owner was B, and B was
//   signed in) and ended B's recovery session.
// - ux 1: gotrue forgets the session before the device has removed it. A
//   second press in that gap found nobody signed in and left for the sign-in
//   page as if signed out; the first one's refusal then went unsaid.
//
// Mounted WITHOUT AccountScope.

final _server = AccountServer();
final _realtime = FakeRealtime();
final _store = MemoryStore();
final _failures = <AppFailure>[];

GoTrueClient get _auth => Supabase.instance.client.auth;

const _notSignedOut = "Couldn't sign you out — try again in a moment. If it "
    'keeps happening, contact support.';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await initAccountSupabase(_server, _realtime, _store);
    _auth.onAuthStateChange.listen((_) {}, onError: (Object _) {});
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _server.reset();
    _store.m.clear();
    _failures.clear();
    passwordRecoveryNotifier.value = null;
    accountNoticeNotifier.value = null;
    setFailureSink(_failures.add);
    addTearDown(resetFailureSink);
  });

  Future<void> reachDone(WidgetTester t) async {
    // A failing test never reaches end(): a removal left held would hang the
    // next one's sign-out.
    addTearDown(() {
      _store.refuseRemoval = false;
      final hold = _store.holdRemoval;
      if (hold != null && !hold.isCompleted) hold.complete();
      _store.holdRemoval = null;
    });
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
    for (final i in [0, 1]) {
      await t.enterText(find.byType(TextField).at(i), 'alba-new-pw');
    }
    await t.pump();
    await t.tap(find.text('Update Password'));
    await settleApp(t, 4);
    expect(find.text('Password updated'), findsOneWidget, reason: 'premise');
  }

  Future<void> end(WidgetTester t) async {
    _store.refuseRemoval = false;
    final hold = _store.holdRemoval;
    if (hold != null && !hold.isCompleted) hold.complete();
    _store.holdRemoval = null;
    await settleApp(t, 2);
    await t.pumpWidget(const SizedBox());
    await t.runAsync(signOut);
    await t.pump(const Duration(seconds: 5));
  }

  VoidCallback back(WidgetTester t) =>
      t.widget<AuthButton>(find.byType(AuthButton)).onTap!;

  testWidgets("S2: B's own recovery took the form over with no frame since: "
      "A's drawn Back to Sign In does not end B's recovery session", (t) async {
    await reachDone(t);
    final press = back(t);
    _server.sent.clear();
    startPasswordRecovery(acctB);
    await t.runAsync(() async {
      await signInAs(acctB);
      // The form has heard of it, and is B's now; nothing has been drawn.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      press();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await settleApp(t);
    expect(_server.of('logout'), isEmpty,
        reason: "THE defect: B's recovery session ended");
    expect(_auth.currentUser?.id, acctB);
    expect(passwordRecoveryNotifier.value, acctB);
    expect(find.text('Set a new password'), findsOneWidget,
        reason: "B's own form, empty");
    await end(t);
  });

  testWidgets('ux 1: a second press while the first sign-out is out does '
      'nothing; the refusal is said on the done page', (t) async {
    await reachDone(t);
    final press = back(t);
    _store.refuseRemoval = true;
    final hold = _store.holdRemoval = Completer<void>();
    await t.runAsync(() async {
      press();
      // gotrue has forgotten the session; the device is still removing it.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(_auth.currentSession, isNull, reason: 'premise: the gap');
      press(); // no frame since the first
      await Future<void>.delayed(const Duration(milliseconds: 5));
    });
    await t.pump();
    expect(find.text('SIGN-IN'), findsNothing,
        reason: 'THE defect: left as if signed out, with the session stored');
    hold.complete();
    await settleApp(t);
    expect(find.text('SIGN-IN'), findsNothing);
    expect(find.text('Password updated'), findsOneWidget);
    expect(find.text(_notSignedOut), findsOneWidget);
    await end(t);
  });

  testWidgets('ux 1: while it runs the button shows it is busy, and a tap on '
      'it sends nothing more', (t) async {
    await reachDone(t);
    final hold = _store.holdRemoval = Completer<void>();
    await t.tap(find.text('Back to Sign In'));
    await settleApp(t, 2);
    expect(find.text('Back to Sign In'), findsNothing);
    expect(
        find.descendant(
            of: find.byType(AuthButton),
            matching: find.byType(CircularProgressIndicator)),
        findsOneWidget);
    await t.tap(find.byType(AuthButton));
    await settleApp(t, 2);
    expect(find.text('SIGN-IN'), findsNothing);
    hold.complete();
    await settleApp(t);
    expect(find.text('SIGN-IN'), findsOneWidget,
        reason: 'control: the one sign-out lands on sign-in');
    expect(_server.of('logout'), hasLength(1));
    await end(t);
  });

  testWidgets('control: after a refusal the button is ready again, and the '
      'next press signs out', (t) async {
    await reachDone(t);
    _store.refuseRemoval = true;
    await t.tap(find.text('Back to Sign In'));
    await settleApp(t);
    expect(find.text(_notSignedOut), findsOneWidget);
    expect(find.text('Back to Sign In'), findsOneWidget, reason: 'not busy');
    _store.refuseRemoval = false;
    await t.tap(find.text('Back to Sign In'));
    await settleApp(t);
    expect(find.text('SIGN-IN'), findsOneWidget);
    expect(_auth.currentSession, isNull);
    await end(t);
  });

  testWidgets('control: the same account, through a token refresh, signs out '
      'from the done page', (t) async {
    await reachDone(t);
    await t.runAsync(renewToken);
    await settleApp(t, 3);
    await t.tap(find.text('Back to Sign In'));
    await settleApp(t);
    expect(_server.of('logout', by: acctA), hasLength(1));
    expect(find.text('SIGN-IN'), findsOneWidget);
    await end(t);
  });
}
