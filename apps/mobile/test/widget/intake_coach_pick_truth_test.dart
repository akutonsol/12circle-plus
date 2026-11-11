import 'dart:convert';

import 'package:circle_fitness/features/coach/domain/coach_provider.dart';
import 'package:circle_fitness/features/onboarding/presentation/intake_flow_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// Onboarding's "Choose Coach" step said "Meet Coach …" whether or not the
// coach was linked.
//
// `_selectCoach` wrapped the relationship upsert, the cancel of any other
// active coach, and the coach's notification in one `catch (_) {}`, then set
// `_selectedCoach` unconditionally. A client whose link failed was shown their
// coach's welcome page, "Let's Go, Avery!", and finished intake believing they
// had a coach who had never been linked — no roster entry, no coach-guided
// access, nobody reviewing their check-ins. And the reverse: a link that WORKED
// was undone in the client's eyes by nothing, but a failed notification (N3's
// shape) was folded into the same swallow.
//
// The real flow is mounted signed in; `_loadProgress` restores the step from
// the profile's `onboarding_step`, so answering 23 opens on Choose Coach (the
// harness EC-03's e2e test uses for the final step; the page list's inline
// numbering is one behind its PageView index here — 22 opens Coaching Mode).

const _uid = '00000000-0000-4000-8000-0000000c0a22';

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

/// Answers like PostgREST. The relationship link and the coach's notification
/// each succeed or fail on request.
class _Server extends http.BaseClient {
  bool linkFails = false;
  bool notificationFails = false;
  final writes = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (path.contains('/auth/v1/')) {
      return _json({'error': 'offline'}, 400, request);
    }
    if (request.method != 'GET') writes.add('${request.method} $path');
    if (request.method == 'GET' && path.contains('user_profiles')) {
      return _json([
        {'id': _uid, 'onboarding_step': 23, 'onboarding_complete': false},
      ], 200, request);
    }
    if (request.method == 'POST' && path.endsWith('/coach_client_relationships')) {
      return linkFails
          ? _json({'message': 'offline'}, 503, request)
          : _json([], 201, request);
    }
    if (path.endsWith('/notifications')) {
      return notificationFails
          ? _json({'message': 'notification insert failed'}, 500, request)
          : _json([], 201, request);
    }
    return _json([], 200, request);
  }

  http.StreamedResponse _json(Object body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

const _coach = {
  'id': 'coach-a',
  'first_name': 'Avery',
  'last_name': 'Stone',
  'coach_title': 'Strength Coach',
  'is_full': false,
};

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
      ..linkFails = false
      ..notificationFails = false
      ..writes.clear();
  });

  Future<void> pickCoach(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(430, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(ProviderScope(
      overrides: [
        availableCoachesProvider.overrideWith((ref) async => const [_coach]),
      ],
      child: const MaterialApp(home: IntakeFlowScreen()),
    ));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Select Coach'), findsOneWidget,
        reason: 'guard the premise: the flow opened on Choose Coach');

    await t.tap(find.text('Select Coach'));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('a failed link does not welcome the client to their coach',
      (t) async {
    server.linkFails = true;
    await pickCoach(t);

    expect(server.writes, contains('POST /rest/v1/coach_client_relationships'),
        reason: 'guard the premise: the link was attempted');
    expect(find.textContaining('Meet Coach'), findsNothing,
        reason: 'no relationship was saved; there is no coach to meet');
    expect(find.text('Select Coach'), findsOneWidget,
        reason: 'the client can pick again');
    expect(find.textContaining("Couldn't select this coach"), findsOneWidget);
  });

  testWidgets('a failed notification does not undo a saved link', (t) async {
    // The relationship IS active; only the notice to the coach failed.
    server.notificationFails = true;
    await pickCoach(t);

    expect(find.textContaining('Meet Coach'), findsOneWidget);
    expect(find.textContaining("Couldn't select this coach"), findsNothing);
  });

  testWidgets('a link that worked meets the coach', (t) async {
    await pickCoach(t);

    expect(find.text('Meet Coach Avery Stone'), findsOneWidget);
  });
}
