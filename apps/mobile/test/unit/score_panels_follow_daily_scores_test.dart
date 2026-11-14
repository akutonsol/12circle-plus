import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/core/realtime/realtime.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart';
import 'package:circle_fitness/features/dashboard/domain/dashboard_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// Points earned outside a workout or check-in never reached the score panels.
//
// Habits, community posts and progress logs write `daily_scores`; Home's
// Wellness Pulse (`todayScoreProvider`), the week (`weekScoresProvider`) and
// Activity's Performance (`monthScoresProvider`) and Streak (`streakProvider`)
// read it. None of them disposes, and only a finished workout or check-in
// re-read two of them — the other two were never re-read at all. `daily_scores`
// is in the realtime publication (037); the four now follow its ticker.

const _uid = '00000000-0000-4000-8000-0000000000d5';

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
  int dailyReads = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final single = request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
    if (request.url.path.endsWith('/daily_scores')) dailyReads++;
    return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(single ? null : []))), 200,
        request: request, headers: {'content-type': 'application/json'});
  }
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

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 60));

  for (final (name, provider) in <(String, ProviderListenable<AsyncValue<Object?>>)>[
    ('Wellness Pulse (todayScoreProvider)', todayScoreProvider),
    ('the week (weekScoresProvider)', weekScoresProvider),
    ("Activity's Performance (monthScoresProvider)", monthScoresProvider),
    ("Activity's Streak (streakProvider)", streakProvider),
  ]) {
    test('$name is read again when daily_scores changes', () async {
      final ticks = StreamController<int>();
      addTearDown(ticks.close);
      final c = ProviderContainer(overrides: [
        currentUserProvider.overrideWithValue(Supabase.instance.client.auth.currentUser),
        tableTickerProvider.overrideWith((ref, table) =>
            table == 'daily_scores' ? ticks.stream : Stream.value(0)),
      ]);
      addTearDown(c.dispose);
      c.listen<Object?>(provider, (_, __) {});
      ticks.add(0);
      await settle();
      final before = server.dailyReads;

      ticks.add(1); // a habit was ticked: its points were written
      await settle();

      expect(server.dailyReads, greaterThan(before),
          reason: 'THE defect: $name kept the points from before');
    });
  }
}
