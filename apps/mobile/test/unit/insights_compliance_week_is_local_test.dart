import 'dart:convert';

import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/compliance/data/compliance_service.dart';
import 'package:circle_fitness/features/insights/domain/insights_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// Two more "this week" workout reads began at Monday 00:00 UTC.
//
// `completed_at` is written as a UTC instant (`workout_service.dart`, the
// session store). #69 fixed `getWeeklyWorkoutCount` and the coach's Workouts tab,
// which sent local Monday midnight with no zone (Postgres reads that as UTC).
// Two siblings still did:
//
//   * Insights' "Workouts this week" (`insightsProvider`, workout_logs) — it
//     disagreed with the Train hub's count for the same week;
//   * the coach's Compliance roster (`ComplianceService.getRoster`,
//     workout_sessions) — west of UTC Sunday evening counted in the new week,
//     east of UTC Monday morning was dropped, pushing clients toward off-track.
//
// The bound must be the user's own Monday midnight, sent as the UTC instant it is.

const _uid = '00000000-0000-4000-8000-0000000c0b1e';

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

bool _zoned(String v) => v.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(v);

class _Server extends http.BaseClient {
  final Map<String, String> completedAt = {};
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final single = request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
    final c = request.url.queryParameters['completed_at'];
    if (c != null) completedAt[path.split('/').last] = c;
    if (path.endsWith('/coach_client_relationships')) return _json([{'client_id': 'c1'}], request);
    if (path.endsWith('/user_profiles')) {
      return _json([{'id': 'c1', 'first_name': 'Ana', 'last_name': 'Ruiz', 'avatar_url': null}], request);
    }
    return _json(single ? null : [], request);
  }

  http.StreamedResponse _json(Object? body, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), 200,
          request: r, headers: {'content-type': 'application/json'});
}

DateTime _localMonday() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day - (n.weekday - 1));
}

void _expectMondayInstant(String? filter, String table) {
  expect(filter, isNotNull, reason: '$table was not read with a completed_at bound');
  expect(filter!.startsWith('gte.'), isTrue);
  final v = filter.substring(4);
  expect(_zoned(v), isTrue,
      reason: 'THE defect: `$v` has no zone, so Postgres began the week at Monday 00:00 UTC');
  expect(DateTime.parse(v).toUtc(), _localMonday().toUtc());
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

  test("Insights' workouts this week start at the user's own Monday", () async {
    final c = ProviderContainer(overrides: [
      currentUserProvider.overrideWithValue(Supabase.instance.client.auth.currentUser),
    ]);
    addTearDown(c.dispose);
    c.listen(insightsProvider, (_, __) {});
    try {
      await c.read(insightsProvider.future);
    } catch (_) {}
    _expectMondayInstant(server.completedAt['workout_logs'], 'workout_logs');
  });

  test("the coach's Compliance week starts at the coach's own Monday", () async {
    try {
      await ComplianceService().getRoster();
    } catch (_) {}
    _expectMondayInstant(server.completedAt['workout_sessions'], 'workout_sessions');
  });
}
