import 'dart:convert';

import 'package:circle_fitness/features/exercise_database/data/custom_exercise_service.dart';
import 'package:circle_fitness/features/exercise_database/domain/custom_exercise_provider.dart';
import 'package:circle_fitness/features/workout/presentation/exercise_library_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// The custom exercise lists:
//   * the published (global, approved) list was read with a bare
//     .order('name'), which postgrest-dart sends DESCENDING: Z to A;
//   * both reads ended `catch (_) { return []; }`, so a failed read was "no
//     exercises" -- the coach's own and the published exercises silently
//     vanished from a library that still looked complete.
// Now: A to Z, a failed read is an error, and the screens say so.
//
// HOW TO SEE IT FAIL: on main the order goes out descending and a 500 comes
// back as an empty list.

const _uid = '00000000-0000-4000-8000-0000000e1b00';

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
  bool fail = false;
  final List<Uri> reads = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    reads.add(request.url);
    final status = fail ? 500 : 200;
    final body = fail ? {'message': 'offline'} : [];
    return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
        request: request, headers: {'content-type': 'application/json'});
  }
}

void main() {
  final server = _Server();

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
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

  setUp(() {
    server.fail = false;
    server.reads.clear();
  });

  test('published exercises are read A to Z', () async {
    await CustomExerciseService().getGlobalApprovedExercises();
    expect(server.reads.single.queryParameters['order'], startsWith('name.asc'),
        reason: 'THE defect: a bare order() is sent descending -- Z to A');
  });

  test('a failed read is an error, not an empty library', () async {
    server.fail = true;
    await expectLater(CustomExerciseService().getGlobalApprovedExercises(), throwsA(anything));
    await expectLater(CustomExerciseService().getMyExercises(), throwsA(anything));
  });

  testWidgets('the client library says when published exercises did not load', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        globalApprovedExercisesProvider.overrideWith((ref) async => throw Exception('offline')),
      ],
      child: const MaterialApp(home: ExerciseLibraryScreen()),
    ));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(find.textContaining("Couldn't load"), findsOneWidget);
    // The screen starts timers (animations); unmount and let them run out.
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
  });
}
