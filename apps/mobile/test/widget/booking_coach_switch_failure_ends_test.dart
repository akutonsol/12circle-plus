import 'dart:convert';

import 'package:circle_fitness/features/booking/presentation/booking_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// Switching coach on Book a Call spun forever when the read failed.
//
// `_selectCoach` set the loading state and called `_applyCoach` without
// awaiting or catching it. For a client with two coaches, a failed slots read
// for the second left the spinner up for good (and the error unhandled), where
// the same failure on first load ends in the screen's error state.

const _uid = '00000000-0000-4000-8000-0000000000b0';

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

/// Two active coaches. Coach B's slots cannot be read (500; a 503 is retried).
class _Server extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final q = request.url.queryParameters;
    Object? body = [];
    var status = 200;
    if (path.endsWith('/coach_client_relationships')) {
      body = [
        {'coach_id': 'coach-a', 'status': 'active', 'pending_at': null, 'activated_at': '2026-10-01T00:00:00Z'},
        {'coach_id': 'coach-b', 'status': 'active', 'pending_at': null, 'activated_at': '2026-10-02T00:00:00Z'},
      ];
    } else if (path.endsWith('/public_profiles')) {
      body = [
        {'id': 'coach-a', 'first_name': 'Avery', 'last_name': 'Stone', 'avatar_url': null,
         'coach_title': null, 'coach_bio': null, 'specialties': null},
        {'id': 'coach-b', 'first_name': 'Blake', 'last_name': 'Ray', 'avatar_url': null,
         'coach_title': null, 'coach_bio': null, 'specialties': null},
      ];
    } else if (path.endsWith('/coach_availability') && (q['coach_id'] ?? '') == 'eq.coach-b') {
      body = {'message': 'upstream down'};
      status = 500;
    }
    return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
        request: request, headers: {'content-type': 'application/json'});
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _Server(),
      authOptions: FlutterAuthClientOptions(
        localStorage: _SeededSession(),
        pkceAsyncStorage: _MemoryStore(),
        detectSessionInUri: false,
      ),
      debug: false,
    );
  });

  testWidgets("a coach whose slots cannot be read ends in the error state, not a spinner",
      (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: BookingScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Blake').first);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull, reason: 'the failure escaped unhandled');
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'THE defect: the spinner never stopped');
  });
}
