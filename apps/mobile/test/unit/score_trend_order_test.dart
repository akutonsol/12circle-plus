import 'dart:convert';

import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/coach/data/score_service.dart';
import 'package:circle_fitness/features/insights/domain/insights_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// The last seven days of scores were read newest first.
//
// `ScoreService.getWeekScores` and `insightsProvider` read `daily_scores` with
// `.order('score_date')`, and postgrest-dart's `order()` defaults to
// `ascending: false` — the opposite of the JS client (WKT-111 met the same
// default in `workout_service.dart`). Both callers read the list as oldest
// first:
//
//   * Activity's "vs last week" (`activity_screen.dart`) takes `last` as the
//     latest day and `first` as the oldest, so a rising week read as falling
//     and a falling one as improving;
//   * Insights draws `last7` left to right as a trend line, so it ran
//     backwards, and its "most recent row" fallback (`rows.last`) was the
//     oldest day.

const _uid = '00000000-0000-4000-8000-00000000050e';

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

/// Answers like PostgREST, including `order=`: rows come back sorted by the
/// columns and directions the request names, as the real server sorts them.
class _Server extends http.BaseClient {
  late List<Map<String, Object?>> scores;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final single = request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
    if (path.endsWith('/daily_scores')) {
      return _json(_ordered(scores, request.url.queryParameters['order']), 200, request);
    }
    return _json(single ? null : [], 200, request);
  }

  static List<Map<String, Object?>> _ordered(
      List<Map<String, Object?>> rows, String? order) {
    final keys = [
      for (final part in (order ?? '').split(',').where((p) => p.isNotEmpty))
        (column: part.split('.')[0], asc: part.split('.')[1] == 'asc'),
    ];
    return [...rows]..sort((a, b) {
        for (final k in keys) {
          final c = (a[k.column] as Comparable).compareTo(b[k.column]);
          if (c != 0) return k.asc ? c : -c;
        }
        return 0;
      });
  }

  http.StreamedResponse _json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

String _date(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

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
    // A rising week: 10, 20, 30, 40 over the last four days. Stored in no
    // particular order; the read decides the order.
    final now = DateTime.now();
    String daysAgo(int n) => _date(DateTime(now.year, now.month, now.day - n));
    server.scores = [
      {'score_date': daysAgo(1), 'total_score': 30, 'workout_points': 0},
      {'score_date': daysAgo(3), 'total_score': 10, 'workout_points': 0},
      {'score_date': daysAgo(0), 'total_score': 40, 'workout_points': 30},
      {'score_date': daysAgo(2), 'total_score': 20, 'workout_points': 0},
    ];
  });

  test("the week's scores are read oldest first", () async {
    final rows = await ScoreService().getWeekScores();
    final totals = rows.map((r) => r['total_score']).toList();
    expect(totals, [10, 20, 30, 40],
        reason: 'THE defect: postgrest-dart orders descending when `ascending` '
            'is omitted, so the latest day came first');

    // What Activity computes from it: latest minus oldest.
    final diff = (rows.last['total_score'] as int) - (rows.first['total_score'] as int);
    expect(diff, 30, reason: 'a rising week reads as rising');
  });

  test("Insights' trend line runs oldest to today", () async {
    final container = ProviderContainer(overrides: [
      currentUserProvider.overrideWithValue(
          Supabase.instance.client.auth.currentUser),
    ]);
    addTearDown(container.dispose);
    final d = await container.read(insightsProvider.future);
    expect(d.last7, [10, 20, 30, 40]);
  });

  test("control: Insights finds today's score by date, in any order", () async {
    final container = ProviderContainer(overrides: [
      currentUserProvider.overrideWithValue(
          Supabase.instance.client.auth.currentUser),
    ]);
    addTearDown(container.dispose);
    final d = await container.read(insightsProvider.future);
    expect(d.todayScore, 40);
    expect(d.workoutPts, 30, reason: "today's breakdown is today's row");
  });
}
