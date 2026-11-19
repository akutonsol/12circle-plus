import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/payments/domain/entitlements.dart';
import 'package:circle_fitness/features/profile/presentation/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/profile_read_postgrest.dart';
import '../support/row_checking_postgrest.dart';

// P0-FL-16 review round (QA gap) · when the profile cannot be read, Profile
// shows the failure notice and keeps Sign Out reachable. Signing out from that
// screen must still leave for /login: the button captures the router before
// its awaits, because signing out changes the profile read and can swap the
// screen it sits on. In its own file: signing out ends the shared session.

const _uid = '00000000-0000-4000-8000-0000000f1618';
const _offline =
    "Couldn't load your profile — check your connection and try again.";

void main() {
  late ProfileReadPostgrest server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = ProfileReadPostgrest(_uid);
    await initSignedInSupabase(server);
  });

  testWidgets('Sign Out from the profile-unavailable screen goes to /login',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    server.profileRead = ProfileRead.network;
    final router = GoRouter(initialLocation: '/profile', routes: [
      GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
      GoRoute(
          path: '/login',
          builder: (_, __) => const Scaffold(body: Text('LOGIN PAGE'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider
            .overrideWithValue(Supabase.instance.client.auth.currentUser),
        clientPlanProvider.overrideWith((ref) async => ClientPlan.selfGuided),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(find.text(_offline), findsOneWidget,
        reason: 'premise: the profile-unavailable screen');

    await tester.tap(find.text('Sign Out'));
    await tester.pumpAndSettle();
    expect(find.text('Are you sure you want to sign out?'), findsOneWidget);
    await tester.tap(find.text('Sign Out').last);
    await tester.pumpAndSettle();

    expect(Supabase.instance.client.auth.currentUser, isNull,
        reason: 'the session was ended');
    expect(find.text('LOGIN PAGE'), findsOneWidget,
        reason: 'Sign Out must leave the unavailable screen for /login');
  });
}
