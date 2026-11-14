import 'dart:convert';

import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/insights/domain/insights_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// "Today's Breakdown" showed another day's points.
//
// With no `daily_scores` row for today yet, `insightsProvider` fell back to the
// most recent row for the category breakdown. So a member active on Monday who
// opened Insights on Thursday saw "Workout 30 / 30" under "Today's Breakdown",
// beneath a ring that — rightly — said today's score was 0.

const _uid = '00000000-0000-4000-8000-0000000000e5';

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

String _day(DateTime d) => d.toIso8601String().split('T')[0];

class _Server extends http.BaseClient {
  List<Map<String, Object?>> scores = [];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final single = request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
    final body = request.url.path.endsWith('/daily_scores') ? scores : (single ? null : []);
    return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), 200,
        request: request, headers: {'content-type': 'application/json'});
  }
}

Map<String, Object?> _row(DateTime d, int workout) => {
      'user_id': _uid, 'score_date': _day(d), 'total_score': workout,
      'workout_points': workout, 'nutrition_points': 0, 'habits_points': 0,
      'checkin_points': 0, 'community_points': 0,
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
        detectSessionInUri: false,
      ),
      debug: false,
    );
  });

  Future<InsightsData> read() async {
    final c = ProviderContainer(overrides: [
      currentUserProvider.overrideWithValue(Supabase.instance.client.auth.currentUser),
    ]);
    addTearDown(c.dispose);
    c.listen(insightsProvider, (_, __) {});
    return c.read(insightsProvider.future);
  }

  test("with nothing scored today, today's breakdown is empty", () async {
    server.scores = [_row(DateTime.now().subtract(const Duration(days: 3)), 30)];
    final d = await read();
    expect(d.todayScore, 0);
    expect(d.workoutPts, 0,
        reason: "THE defect: an earlier day's 30 workout points shown as today's");
  });

  test("control: today's own points are today's breakdown", () async {
    server.scores = [
      _row(DateTime.now().subtract(const Duration(days: 3)), 30),
      _row(DateTime.now(), 10),
    ];
    final d = await read();
    expect(d.workoutPts, 10);
    expect(d.todayScore, 10);
  });
}
