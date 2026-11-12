import 'dart:convert';

import 'package:circle_fitness/features/challenges/presentation/challenges_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// /challenges was given its own F-15 failure state — "Could not load
// challenges" with a retry, and "— active challenges" in the header — because
// a failed read used to say "No challenges here". It decides on
// `liveChallengesProvider is AsyncError`. But the service under that provider
// caught every error and returned `[]`:
//
//   } catch (_) {
//     return [];
//   }
//
// so the provider was never an error, the state could never show, and a
// failed read still said "No challenges here" — here, in What's On, and on
// Activity, which all handle the error already.

const _uid = '00000000-0000-4000-8000-0000000c4a11';

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

/// `challenges`, which can be told to fail.
class _Server extends http.BaseClient {
  bool fails = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path.endsWith('/challenges') && fails) {
      return _json({'message': 'offline'}, 500, request);
    }
    return _json([], 200, request);
  }

  http.StreamedResponse _json(Object body, int status, http.BaseRequest r) =>
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

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: ChallengesScreen())));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('a FAILED read says so, not "No challenges here"', (tester) async {
    server.fails = true;
    await open(tester);
    expect(find.text('No challenges here'), findsNothing,
        reason: 'THE defect: a failure stated as an empty month');
    expect(find.text('Could not load challenges'), findsWidgets);
    expect(find.text('— active challenges'), findsOneWidget);
  });

  testWidgets('no challenges is still said plainly (control)', (tester) async {
    server.fails = false;
    await open(tester);
    expect(find.text('Could not load challenges'), findsNothing);
    expect(find.text('No challenges here'), findsWidgets);
  });
}
