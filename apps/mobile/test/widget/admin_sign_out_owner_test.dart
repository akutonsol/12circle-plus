import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/admin/presentation/admin_dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/account_app.dart';

// P0-FL-59a round 4 (sec S3) — the admin console's sign-out is for the account
// it was drawn for. Drawn for A and tapped with no frame after B signed in, it
// signed B out. (The vendor portal's: vendor_portal_follows_signin_test.)
// Mounted WITHOUT AccountScope.

final _server = AccountServer();
final _realtime = FakeRealtime();
final _store = MemoryStore();
final _failures = <AppFailure>[];

GoTrueClient get _auth => Supabase.instance.client.auth;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await initAccountSupabase(_server, _realtime, _store);
    _auth.onAuthStateChange.listen((_) {}, onError: (Object _) {});
  });

  setUp(() {
    _server.reset();
    _failures.clear();
    setFailureSink(_failures.add);
    addTearDown(resetFailureSink);
  });

  Future<void> mount(WidgetTester t) async {
    // The admin tiles overflow by 2px in the test font; not what this is on.
    final onError = FlutterError.onError;
    FlutterError.onError =
        (d) => '${d.exception}'.contains('overflowed') ? null : onError!(d);
    addTearDown(() => FlutterError.onError = onError);
    t.view.physicalSize = const Size(900, 2600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.runAsync(signOut);
    await t.runAsync(() => signInAs(acctA));
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const AdminDashboardScreen()),
      GoRoute(
          path: '/login',
          builder: (_, __) => const Scaffold(body: Text('SIGN-IN'))),
    ]);
    addTearDown(router.dispose);
    await t.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)));
    await settleApp(t, 4);
    expect(find.byIcon(Icons.logout_rounded), findsOneWidget,
        reason: 'premise');
  }

  Future<void> end(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.runAsync(signOut);
    await t.pump(const Duration(seconds: 5));
  }

  testWidgets("tapped with no frame after B signed in: B's session is "
      'untouched, and it is recorded', (t) async {
    await mount(t);
    await t.runAsync(() async {
      await signInAs(acctB);
      await Future<void>.delayed(const Duration(milliseconds: 5));
    });
    _server.sent.clear();
    await t.tap(find.byIcon(Icons.logout_rounded), warnIfMissed: false);
    await settleApp(t);
    expect(_server.of('logout'), isEmpty, reason: 'THE defect: B signed out');
    expect(_auth.currentUser?.id, acctB);
    expect(find.text('SIGN-IN'), findsNothing);
    expect(
        _failures
            .where((f) => '${f.error}'.contains('account changed'))
            .map((f) => f.origin),
        contains('AdminDashboardScreen.signOut'));
    await end(t);
  });

  testWidgets('drawn again for B: it signs B out', (t) async {
    await mount(t);
    await t.runAsync(() => signInAs(acctB));
    await settleApp(t);
    _server.sent.clear();
    await t.tap(find.byIcon(Icons.logout_rounded));
    await settleApp(t);
    expect(_server.of('logout', by: acctB), hasLength(1));
    expect(_auth.currentSession, isNull);
    await end(t);
  });

  testWidgets('control: the same admin, after a token refresh, is signed out',
      (t) async {
    await mount(t);
    await t.runAsync(renewToken);
    await settleApp(t, 3);
    await t.tap(find.byIcon(Icons.logout_rounded));
    await settleApp(t);
    expect(_server.of('logout', by: acctA), hasLength(1));
    expect(_auth.currentSession, isNull);
    expect(find.text('SIGN-IN'), findsOneWidget);
    expect(_failures.where((f) => '${f.error}'.contains('account changed')),
        isEmpty);
    await end(t);
  });
}
