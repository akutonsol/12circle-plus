import 'dart:convert';

import 'package:circle_fitness/features/workout/data/workout_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// The client's own workout streak (Home "STREAK: N DAYS", the Train hub
// STREAK tile, the AI coach's "N-day streak") broke the rule every other
// streak in the app keeps.
//
// `getCurrentStreak` accepted `diff == 0 || diff == 1` at EVERY step, not just
// the first. Three defects followed:
//
//   * a one-day gap anywhere in the run kept it alive, so training every other
//     day read as an ever-growing streak;
//   * a second session on the same day ENDED the run: after counting today,
//     the next row was "tomorrow" relative to the cursor (`diff == -1`);
//   * days were UTC days (`DateTime.parse` of a `Z` timestamp, read without
//     `.toLocal()`), so an evening workout west of UTC landed on tomorrow.
//
// The coach's view of the same client already counts with
// `currentWorkoutStreak` (D7): local days, de-duplicated, consecutive, the run
// reaching today or yesterday. The habit streak and the activity streak keep
// the same consecutive rule. The client's number now agrees with them.

const _uid = '00000000-0000-4000-8000-0000000057a1';

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

/// Answers the `workout_logs` read with [logs], newest first, as PostgREST
/// would for `order('completed_at', ascending: false)`.
class _Server extends http.BaseClient {
  List<String> logs = const [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = request.url.path.endsWith('/workout_logs')
        ? [for (final at in logs) {'completed_at': at}]
        : [];
    return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), 200,
        request: request, headers: {'content-type': 'application/json'});
  }
}

/// A completion [daysAgo] local days before today, at a local [hour], stored
/// the way `logWorkout` writes it: a UTC instant.
String _at(int daysAgo, {int hour = 9, int minute = 0}) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day - daysAgo, hour, minute)
      .toUtc()
      .toIso8601String();
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

  Future<int> streakOf(List<String> logs) {
    server.logs = logs;
    return WorkoutService().getCurrentStreak();
  }

  test('training every other day is not a streak', () async {
    // Today, two days ago, four days ago: the run is today alone.
    expect(await streakOf([_at(0), _at(2), _at(4)]), 1);
  });

  test('a second session on the same day does not end the run', () async {
    // Today twice, then yesterday and the day before: three days.
    expect(await streakOf([_at(0, hour: 18), _at(0, hour: 7), _at(1), _at(2)]),
        3);
  });

  test("this evening's session counts today", () async {
    // 20:00 local today is still today, wherever the device is. West of UTC
    // its UTC date is TOMORROW, which the old count compared with today as a
    // day ahead and stopped at: a streak of 0 straight after training.
    // (CI runs in UTC, where the two dates agree; run with TZ set west of UTC
    // to see this one fail on the old code.)
    expect(await streakOf([_at(0, hour: 20)]), 1);
  });

  group('what stays the same', () {
    test('through today', () async {
      expect(await streakOf([_at(0), _at(1), _at(2)]), 3);
    });
    test('not trained yet today: a run ending yesterday still counts',
        () async {
      expect(await streakOf([_at(1), _at(2)]), 2);
    });
    test('a run that ended the day before yesterday is over', () async {
      expect(await streakOf([_at(2), _at(3)]), 0);
    });
    test('no workouts', () async {
      expect(await streakOf(const []), 0);
    });
  });
}
