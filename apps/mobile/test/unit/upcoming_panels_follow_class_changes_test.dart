import 'dart:convert';

import 'package:circle_fitness/features/classes/domain/class_provider.dart' show refreshClassesProvider;
import 'package:circle_fitness/features/dashboard/domain/dashboard_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// The Directory's and Activity's Upcoming missed a class just created or
// cancelled. Creating or cancelling a class bumps `refreshClassesProvider`,
// which Classes follows; `upcomingClassesProvider` (#89's panel) did not, never
// disposes and was invalidated nowhere, so it kept the old five.

const _uid = '00000000-0000-4000-8000-0000000000ed';

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

class _Server extends http.BaseClient {
  int classReads = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path.endsWith('/classes')) classReads++;
    return http.StreamedResponse(Stream.value(utf8.encode('[]')), 200,
        request: request, headers: {'content-type': 'application/json'});
  }
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

  test('a class created or cancelled re-reads the Upcoming panel', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.listen(upcomingClassesProvider, (_, __) {});
    await c.read(upcomingClassesProvider.future);
    final before = server.classReads;

    c.read(refreshClassesProvider.notifier).state++; // what create/cancel do
    await c.read(upcomingClassesProvider.future);

    expect(server.classReads, greaterThan(before),
        reason: 'THE defect: the panel kept the classes it read first');
  });
}
