import 'dart:convert';

import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/coach/domain/coach_provider.dart';
import 'package:circle_fitness/features/profile/presentation/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// F-15 hid /profile's "MY COACH" section on a failed read rather than telling
// a paying client "No coach assigned yet — Complete onboarding to choose your
// coach." `coach_section_state_test.dart` pins that decision, and feeds it an
// `AsyncError` by overriding the provider.
//
// The real provider could never produce one. `assignedCoachProvider` ended in
// `catch (_) { return null; }`, so every failed read arrived as "no coach" and
// the screen said exactly what F-15 removed. The A-G5/A-G6 shape: the screen
// had the right branch, over a provider that destroyed the signal it needed.
//
// These tests run the REAL provider against a fake PostgREST.

const _uid = '00000000-0000-4000-8000-0000000a55c1';

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

/// Answers like PostgREST: the client's active relationship and the coach's
/// public profile, or a failure.
class _Server extends http.BaseClient {
  bool fails = false;
  bool hasCoach = true;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (fails) return _json({'message': 'offline'}, 500, request);
    if (path.endsWith('/coach_client_relationships')) {
      return _json(hasCoach ? {'coach_id': 'coach-a', 'status': 'active'} : null, 200, request);
    }
    if (path.endsWith('/public_profiles')) {
      return _json({'id': 'coach-a', 'first_name': 'Avery', 'last_name': 'Stone'}, 200, request);
    }
    return _json(null, 200, request);
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

  setUp(() {
    server
      ..fails = false
      ..hasCoach = true;
  });

  List<Override> signedIn() => [
        currentUserProvider.overrideWithValue(Supabase.instance.client.auth.currentUser),
      ];

  Future<AsyncValue<Map<String, dynamic>?>> settle() async {
    final c = ProviderContainer(overrides: signedIn());
    addTearDown(c.dispose);
    try {
      await c.read(assignedCoachProvider.future);
    } catch (_) {}
    return c.read(assignedCoachProvider);
  }

  test('a failed read is an error, not "no coach"', () async {
    server.fails = true;
    final v = await settle();
    expect(v, isA<AsyncError<Map<String, dynamic>?>>(),
        reason: 'THE defect: `catch (_) { return null; }` made a failed read '
            'indistinguishable from a client with no coach');
  });

  testWidgets('/profile does not tell a client with a failed read to choose a coach',
      (t) async {
    server.fails = true;
    await t.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(ProviderScope(
      overrides: signedIn(),
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MyCoachSection(onCoachCancelled: () {}),
          ),
        ),
      ),
    ));
    await t.pump();
    await t.pump();

    expect(find.text('No coach assigned yet'), findsNothing);
    expect(find.text('Complete onboarding to choose your coach.'), findsNothing);
  });

  test('control: a client with no coach is a real "no coach"', () async {
    server.hasCoach = false;
    final v = await settle();
    expect(v, const AsyncData<Map<String, dynamic>?>(null));
  });

  test("control: a client's coach is read", () async {
    final v = await settle();
    expect(v.valueOrNull?['first_name'], 'Avery');
  });
}
