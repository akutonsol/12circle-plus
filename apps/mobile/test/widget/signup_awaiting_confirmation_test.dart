import 'dart:convert';

import 'package:circle_fitness/features/auth/presentation/signup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// Sign-up that needs an email confirmation sent the member into intake signed out.
//
// When the project requires email confirmation (QA does), `auth.signUp` returns
// the new user and NO session. The sign-up screen went to /intake regardless;
// /intake is an auth route, so the router let a signed-out member through, and
// every intake save was skipped for want of a user — then intake met them again
// at their first sign-in. Without a session it now says to confirm the email
// and goes to sign-in.

class _MemoryStore extends GotrueAsyncStorage {
  final Map<String, String> _m = {};
  @override
  Future<String?> getItem({required String key}) async => _m[key];
  @override
  Future<void> setItem({required String key, required String value}) async =>
      _m[key] = value;
  @override
  Future<void> removeItem({required String key}) async => _m.remove(key);
}

/// GoTrue's answer to a sign-up awaiting confirmation: the user, no tokens.
class _AuthServer extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = request.url.path.endsWith('/signup')
        ? {
            'id': '00000000-0000-4000-8000-00000000510a',
            'aud': 'authenticated',
            'role': '',
            'email': 'new@member.test',
            'app_metadata': {'provider': 'email'},
            'user_metadata': {'first_name': 'New', 'last_name': 'Member', 'role': 'client'},
            'created_at': '2026-11-13T12:00:00Z',
            'confirmation_sent_at': '2026-11-13T12:00:00Z',
          }
        : <String, Object?>{};
    return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), 200,
        request: request, headers: {'content-type': 'application/json'});
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _AuthServer(),
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryStore(),
        detectSessionInUri: false,
      ),
      debug: false,
    );
  });

  testWidgets('a sign-up awaiting email confirmation goes to sign-in, not intake',
      (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 2400);
    addTearDown(tester.view.reset);
    final router = GoRouter(initialLocation: '/signup', routes: [
      GoRoute(path: '/signup', builder: (_, __) => const SignupScreen()),
      GoRoute(path: '/login', builder: (_, __) => const Scaffold(body: Text('SIGN IN'))),
      GoRoute(path: '/intake', builder: (_, __) => const Scaffold(body: Text('INTAKE'))),
    ]);
    await tester.pumpWidget(ProviderScope(child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'New');
    await tester.enterText(fields.at(1), 'Member');
    await tester.enterText(fields.at(2), 'new@member.test');
    await tester.enterText(fields.at(3), 'longenough1');
    await tester.tap(find.text('Terms of Service'));
    await tester.pump();
    await tester.ensureVisible(find.text('Create Account'));
    await tester.tap(find.text('Create Account'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(Supabase.instance.client.auth.currentSession, isNull);
    expect(find.text('INTAKE'), findsNothing,
        reason: 'THE defect: a signed-out member was sent through intake');
    expect(find.text('SIGN IN'), findsOneWidget);
    expect(find.text(signupConfirmEmailMessage), findsOneWidget);
  });
}
