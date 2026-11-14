import 'dart:convert';

import 'package:circle_fitness/core/router/app_router.dart';
import 'package:circle_fitness/features/auth/presentation/forgot_password_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// Settings' "Change password" (FIT-030) did nothing.
//
// It pushes `/forgot-password`, the reset flow the app already has. The router
// listed that path among the auth routes, and its redirect sends a signed-in user
// on an auth route to their home: `/home` for a client, `/coach-dashboard` for a
// coach. So the push landed the user back where they started, every time. The
// path is now open whether or not anyone is signed in; the signed-out flow is
// unchanged.

const _uid = '00000000-0000-4000-8000-0000000000a5';

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

String _jwt() {
  final exp = DateTime.now().add(const Duration(days: 3650)).millisecondsSinceEpoch ~/ 1000;
  return '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${_b64({'sub': _uid, 'role': 'authenticated', 'exp': exp, 'aud': 'authenticated'})}.'
      'not-verified-client-side';
}

class _SeededSession extends LocalStorage {
  @override
  Future<void> initialize() async {}
  @override
  Future<String?> accessToken() async => jsonEncode({
        'access_token': _jwt(),
        'token_type': 'bearer',
        'expires_in': 315360000,
        'refresh_token': 'test-refresh',
        'user': {
          'id': _uid,
          'app_metadata': {},
          'user_metadata': {},
          'aud': 'authenticated',
          'created_at': '2026-01-01T00:00:00Z',
        },
      });
  @override
  Future<bool> hasAccessToken() async => true;
  @override
  Future<void> persistSession(String persistSessionString) async {}
  @override
  Future<void> removePersistedSession() async {}
}

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

/// The signed-in user's profile, which the redirect reads to choose a home.
class _Server extends http.BaseClient {
  String role = 'client';
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final single = request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
    if (request.url.path.endsWith('/user_profiles')) {
      final row = {'role': role, 'onboarding_complete': true};
      return _json(single ? row : [row], request);
    }
    return _json(single ? null : [], request);
  }

  http.StreamedResponse _json(Object? body, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), 200,
          request: r, headers: {'content-type': 'application/json'});
}

void main() {
  late _Server server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = _Server();
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: server,
      authOptions: FlutterAuthClientOptions(
        localStorage: _SeededSession(),
        pkceAsyncStorage: _MemoryStore(),
        detectSessionInUri: false,
      ),
      debug: false,
    );
  });

  for (final role in ['client', 'coach']) {
    testWidgets('a signed-in $role who opens Change password reaches the reset flow',
        (tester) async {
      server.role = role;
      expect(Supabase.instance.client.auth.currentSession, isNotNull,
          reason: 'the test needs a signed-in user');
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final router = container.read(routerProvider);
      router.go('/forgot-password');
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(router.routerDelegate.currentConfiguration.uri.path, '/forgot-password',
          reason: 'THE defect: the redirect sent a signed-in $role home');
      expect(find.byType(ForgotPasswordScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
