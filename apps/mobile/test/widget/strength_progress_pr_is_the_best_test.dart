import 'dart:convert';

import 'package:circle_fitness/features/workout/data/workout_service.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:circle_fitness/features/workout/presentation/strength_progression_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// Strength Progress called the latest session's best "Current PR", on UTC days.
//
// The card showed `sorted.last['max_weight']` — the most recent session — while
// the real maximum was computed just above it and used only to scale the chart:
// 100 kg last week and 60 kg today read "Current PR 60.0kg". The progression
// read also grouped sets by the first ten characters of `logged_at`, the UTC
// date, so an evening session in New York was plotted on tomorrow (#81's rule
// is the member's own day). Run with TZ=America/New_York for the day half.

const _uid = '00000000-0000-4000-8000-0000000000eb';

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
  List<Map<String, Object?>> rows = [];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(rows))), 200,
          request: request, headers: {'content-type': 'application/json'});
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

  testWidgets('Current PR is the heaviest set on record, not the latest session', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        loggedExerciseNamesProvider.overrideWith((ref) async => ['Deadlift']),
        exerciseProgressionProvider('Deadlift').overrideWith((ref) async => [
              {'date': '2026-11-05', 'max_weight': 100.0, 'total_volume': 500.0, 'sets_count': 1},
              {'date': '2026-11-12', 'max_weight': 60.0, 'total_volume': 300.0, 'sets_count': 1},
            ]),
      ],
      child: const MaterialApp(home: StrengthProgressionScreen()),
    ));
    await tester.pumpAndSettle();
    // The stat card: a Column holding its value above its label.
    final card = find.ancestor(of: find.text('Current PR'), matching: find.byType(Column)).first;
    expect(find.descendant(of: card, matching: find.text('100.0kg')), findsOneWidget,
        reason: 'THE defect: "Current PR 60.0kg" — the latest session, not the record');
  });

  test("a session is plotted on the member's own day", () async {
    final now = DateTime.now();
    final evening = DateTime(now.year, now.month, now.day, 21, 30);
    server.rows = [
      {'weight_kg': 80, 'reps': 5, 'logged_at': evening.toUtc().toIso8601String()},
    ];
    final points = await WorkoutService().getExerciseProgression('Squat');
    final day = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    expect(points.single['date'], day);
  });
}
