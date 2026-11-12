import 'dart:convert';

import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/dashboard/presentation/coach_dashboard_screen.dart';
import 'package:circle_fitness/features/workout/data/workout_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// "This week" for workouts started at the wrong instant.
//
// `completed_at` is a timestamptz written as a UTC instant
// (`DateTime.now().toUtc()` in `logWorkout` and the session store). The two
// "this week" reads — the client's `getWeeklyWorkoutCount` (Train hub "This
// week", the AI weekly review, program adherence) and the coach dashboard's
// `clientWorkoutLogsProvider` (Workouts tab, the summary strip) — filtered it
// with `.gte('completed_at', start.toIso8601String())`, where `start` is LOCAL
// Monday midnight. That string has no zone, and Postgres reads a zoneless
// timestamp as UTC. So the week began at Monday 00:00 UTC, not the user's
// Monday:
//
//   * west of UTC (New York), Sunday evening's workouts counted in the new week;
//   * east of UTC (Tokyo), Monday morning's workouts were left out of it.
//
// HOW TO SEE IT FAIL: these tests are run under the machine's zone. Under UTC
// the two instants agree and they pass on the old code too; run with
// `TZ=America/New_York` or `TZ=Asia/Tokyo` to see the old code fail.

const _uid = '00000000-0000-4000-8000-00000000c0de';

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

/// Answers like PostgREST, applying the `completed_at=gte.` filter as Postgres
/// does: a value with no zone is read as UTC (the server's TimeZone).
class _Server extends http.BaseClient {
  late List<Map<String, Object?>> rows;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (path.endsWith('/coach_client_relationships')) {
      return _json([{'client_id': 'client-a'}], 200, request);
    }
    if (path.endsWith('/workout_logs') || path.endsWith('/workout_sessions')) {
      final gte = request.url.queryParameters['completed_at'];
      final from = gte == null ? null : _asPostgres(gte.substring('gte.'.length));
      return _json([
        for (final r in rows)
          if (from == null || !DateTime.parse(r['completed_at'] as String).isBefore(from)) r,
      ], 200, request);
    }
    return _json([], 200, request);
  }

  static DateTime _asPostgres(String v) {
    final zoned = v.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(v);
    return DateTime.parse(zoned ? v : '${v}Z');
  }

  http.StreamedResponse _json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

/// A workout completed at local [at], stored as the UTC instant the app writes.
Map<String, Object?> _done(String id, DateTime at) => {
      'id': id,
      'user_id': 'client-a',
      'workout_title': id,
      'status': 'completed',
      'duration_seconds': 1800,
      'completed_at': at.toUtc().toIso8601String(),
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
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    server.rows = [
      // Last Sunday at 21:00 — last week.
      _done('sunday-evening', DateTime(monday.year, monday.month, monday.day - 1, 21)),
      // This Monday at 08:00 — this week.
      _done('monday-morning', DateTime(monday.year, monday.month, monday.day, 8)),
    ];
  });

  test("the client's week starts at their own Monday midnight", () async {
    expect(await WorkoutService().getWeeklyWorkoutCount(), 1,
        reason: 'THE defect: the week began at Monday 00:00 UTC, so Sunday '
            'evening counted (west of UTC) or Monday morning did not (east)');
  });

  test("the coach's Workouts tab holds this week's sessions only", () async {
    final c = ProviderContainer(overrides: [
      currentUserProvider.overrideWithValue(Supabase.instance.client.auth.currentUser),
    ]);
    addTearDown(c.dispose);
    final rows = await c.read(clientWorkoutLogsProvider.future);
    expect(rows.map((r) => r['workout_title']), ['monday-morning']);
  });

  test('control: a workout in the middle of the week counts', () async {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    server.rows = [_done('midweek', DateTime(monday.year, monday.month, monday.day, 12))];
    expect(await WorkoutService().getWeeklyWorkoutCount(), 1);
  });
}
