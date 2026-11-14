import 'dart:convert';
import 'dart:io';

import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/nutrition/presentation/meals_dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// Two figures were shown that nothing measured.
//
//   * Meals' water card began every visit at "3 / 8" glasses: `_water` started
//     at 3 before the member had tapped anything, and nothing stores it.
//   * Home's score card drew a constant "+4%" rising trend under every
//     member's score — the same figure for everyone, computed from nothing.
//
// Both are removed as invented, not replaced: whether water is saved, and what
// a score trend measures, are open product choices.

const _uid = '00000000-0000-4000-8000-0000000f00d1';

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

/// The token is read, never verified client-side.
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

class _Server extends http.BaseClient {
  bool logsFail = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final single = request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
    if (path.endsWith('/nutrition_logs') && request.method == 'GET') {
      return logsFail
          ? _json({'message': 'offline'}, 500, request)
          : _json([], 200, request);
    }
    return _json(single ? null : [], 200, request);
  }

  http.StreamedResponse _json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
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
      ),
      debug: false,
    );
  });

  testWidgets('the water card starts at none, not three glasses', (t) async {
    t.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 3000);
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(Supabase.instance.client.auth.currentUser),
      ],
      child: const MaterialApp(home: MealsDashboardScreen()),
    ));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('3 / 8'), findsNothing,
        reason: 'THE defect: three glasses before anything was tapped');
    expect(find.text('0 / 8'), findsOneWidget);
  });

  test("guard: Home's score card draws no fixed trend figure", () {
    // Source guard: proves only that the constant is gone from the card.
    final src = File('lib/features/home/presentation/home_screen.dart').readAsStringSync();
    expect(src.contains("Text('+4%'"), isFalse);
  });
}
