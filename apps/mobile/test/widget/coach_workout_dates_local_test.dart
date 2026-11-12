import 'dart:convert';

import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart';
import 'package:circle_fitness/features/coach/domain/package_provider.dart';
import 'package:circle_fitness/features/dashboard/presentation/client_detail_screen.dart';
import 'package:circle_fitness/features/scoring/domain/score_provider.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:circle_fitness/features/workout/presentation/coach_client_workout_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// The coach's two views of a client's workouts dated them wrongly.
//
// `completed_at` is a timestamptz: the database returns a UTC instant.
//
//   * Client Workout Stats (`coach_client_workout_screen.dart`, the screen
//     "Needs you today" opens for an at-risk client) labelled the last workout
//     "Today" / "Yesterday" by ELAPSED HOURS: 23:59 last night, read at 09:00,
//     is nine hours ago — "Today". Its recent sessions printed the UTC date.
//   * The client page's Progress tab (`client_detail_screen.dart`) printed
//     "Last Workout" and each recent session as the UTC date, while the
//     streak beside them (D7, `currentWorkoutStreak`) counts LOCAL days — so an
//     evening session west of UTC was dated tomorrow, next to a streak that
//     counted it today.
//
// HOW TO SEE THE DATE CASES FAIL: they depend on the machine's zone. Under UTC
// the UTC date is the local date and they pass on the old code; run with
// `TZ=America/New_York` (the 23:30 case) or `TZ=Asia/Tokyo` (the 00:30 case).
// The "Yesterday" case fails on the old code in any zone.

const _uid = '00000000-0000-4000-8000-00000000da7e';
const _clientId = 'client-1';

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

/// Every read the screens make beyond the overridden providers answers empty.
class _Empty extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final single = request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
    return http.StreamedResponse(Stream.value(utf8.encode(single ? 'null' : '[]')), 200,
        request: request, headers: {'content-type': 'application/json'});
  }
}

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

/// A local wall time as the UTC instant the database returns.
String _stored(DateTime local) => local.toUtc().toIso8601String();

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Last night at 23:30 — the evening case west of UTC.
DateTime _lastNight() => _today().subtract(const Duration(minutes: 30));

/// This morning at 00:30 — the early case east of UTC.
DateTime _earlyToday() => _today().add(const Duration(minutes: 30));

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _Empty(),
      authOptions: FlutterAuthClientOptions(
        localStorage: _SeededSession(),
        pkceAsyncStorage: _MemoryStore(),
      ),
      debug: false,
    );
  });

  void tall(WidgetTester t) {
    t.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1200, 4000);
    addTearDown(t.view.reset);
  }

  group('Client Workout Stats', () {
    Future<void> open(WidgetTester t, {required String lastWorkoutAt,
        List<Map<String, dynamic>> sessions = const []}) async {
      tall(t);
      await t.pumpWidget(ProviderScope(
        overrides: [
          clientWorkoutStatsProvider(_uid).overrideWith((ref) async => [
                {
                  'client_id': _clientId,
                  'client_name': 'Jordan Test',
                  'total_completed': 3,
                  'workouts_this_week': 1,
                  'completion_rate_pct': 80,
                  'last_workout_at': lastWorkoutAt,
                },
              ]),
          clientRecentSessionsProvider(_clientId).overrideWith((ref) async => sessions),
          clientPersonalRecordsProvider(_clientId).overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: CoachClientWorkoutScreen()),
      ));
      await t.pump();
      await t.pump();
    }

    testWidgets('a workout at 23:59 last night was "Yesterday"', (t) async {
      await open(t,
          lastWorkoutAt: _stored(_today().subtract(const Duration(minutes: 1))));
      expect(find.text('Today'), findsNothing,
          reason: 'THE defect: labelled by elapsed hours, so last night read '
              'as "Today" all morning');
      expect(find.text('Yesterday'), findsOneWidget);
    });

    testWidgets('control: a workout this morning is "Today"', (t) async {
      await open(t, lastWorkoutAt: _stored(_today().add(const Duration(minutes: 1))));
      expect(find.text('Today'), findsOneWidget);
    });

    testWidgets("recent sessions are dated on the coach's own calendar", (t) async {
      await open(t, lastWorkoutAt: _stored(_earlyToday()), sessions: [
        {'workout_title': 'Early', 'status': 'completed', 'duration_seconds': 1800,
         'completed_at': _stored(_earlyToday())},
        {'workout_title': 'Late', 'status': 'completed', 'duration_seconds': 1800,
         'completed_at': _stored(_lastNight())},
      ]);
      await t.tap(find.text('Jordan Test'));
      await t.pump();
      await t.pump();
      expect(find.text(_ymd(_today())), findsOneWidget, reason: '00:30 this morning');
      expect(find.text(_ymd(_lastNight())), findsOneWidget, reason: '23:30 last night');
    });
  });

  group("the client page's Progress tab", () {
    Future<void> open(WidgetTester t, List<Map<String, dynamic>> sessions) async {
      tall(t);
      final router = GoRouter(
        initialLocation: '/client',
        routes: [
          GoRoute(
            path: '/client',
            builder: (_, __) =>
                const ClientDetailScreen(clientId: _clientId, clientName: 'Jordan'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await t.pumpWidget(ProviderScope(
        overrides: [
          clientDetailProvider(_clientId).overrideWith((ref) async => {
                'id': _clientId,
                'first_name': 'Jordan',
                'last_name': 'Test',
                'role': 'client',
                'workout_logs': sessions,
              }),
          clientHasPaidPlanProvider(_clientId).overrideWith((ref) async => true),
          clientScheduleProvider(_clientId).overrideWith((ref) async => null),
          clientScoreProvider(_clientId).overrideWith((ref) async => null),
        ],
        child: MaterialApp.router(routerConfig: router),
      ));
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      await t.tap(find.text('Progress'));
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    Map<String, dynamic> session(String title, DateTime local) => {
          'user_id': _clientId, 'workout_title': title,
          'completed_at': _stored(local), 'duration_seconds': 1800,
        };

    testWidgets('Last Workout and recent sessions are local dates', (t) async {
      await open(t, [session('Early', _earlyToday()), session('Late', _lastNight())]);
      // "Last Workout" and the first recent session are both this morning.
      expect(find.text(_ymd(_today())), findsNWidgets(2));
      expect(find.text(_ymd(_lastNight())), findsOneWidget);
    });
  });
}
