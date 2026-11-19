import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/workout/data/workout_service.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:circle_fitness/features/workout/presentation/coach_client_workout_screen.dart';
import 'package:circle_fitness/features/workout/presentation/strength_progression_screen.dart';
import 'package:circle_fitness/features/workout/presentation/train_hub_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// P0-FL-18 — progress views: a failed read is never "no data yet".
//
// Five WorkoutService reads ended `catch (_) { return []; }`:
// getExerciseProgression, getLoggedExerciseNames, getPersonalRecords,
// getClientPersonalRecords and getClientRecentSessions. Their consumers then
// drew a FAILED read as the empty state — "No data yet" on the strength chart,
// "No personal records yet" / "No sessions recorded" on the coach's view of a
// client (J11), and a Train hub with no Personal Records section at all.
//
// Per method: the failure is recorded and propagates; each consumer shows
// "Couldn't load <thing>" with a Try again that recovers; and a SUCCESSFUL
// empty answer keeps today's empty copy exactly.

const _uid = '00000000-0000-4000-8000-0000000000f8';

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

/// PostgREST stand-in: answers `[]`, or a 500 with a PostgREST error body.
class _Server extends http.BaseClient {
  bool fail = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (fail) {
      return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode({
            'code': 'XX000',
            'message': 'internal error',
            'details': null,
            'hint': null,
          }))),
          500,
          request: request,
          headers: {'content-type': 'application/json'});
    }
    return http.StreamedResponse(Stream.value(utf8.encode('[]')), 200,
        request: request, headers: {'content-type': 'application/json'});
  }
}

const _otherwise = 'Try again in a moment. If it keeps happening, contact support.';
const _network = 'Check your connection and try again.';

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

  tearDown(() {
    server.fail = false;
    resetFailureSink();
  });

  // ── Service: record, then propagate ─────────────────────────────────────
  group('WorkoutService progress reads propagate a failure', () {
    final reads = <String, Future<List<dynamic>> Function()>{
      'getExerciseProgression': () => WorkoutService().getExerciseProgression('Deadlift'),
      'getLoggedExerciseNames': () => WorkoutService().getLoggedExerciseNames(),
      'getPersonalRecords': () => WorkoutService().getPersonalRecords(),
      'getClientPersonalRecords': () => WorkoutService().getClientPersonalRecords('c1'),
      'getClientRecentSessions': () => WorkoutService().getClientRecentSessions('c1'),
    };
    reads.forEach((method, read) {
      test('$method: a failed read throws and is recorded — it is not []', () async {
        final seen = <AppFailure>[];
        setFailureSink(seen.add);
        server.fail = true;
        await expectLater(read(), throwsA(isA<PostgrestException>()),
            reason: 'THE defect: the failure was answered as an empty list');
        expect(seen.map((f) => f.origin), ['WorkoutService.$method']);
      });
      test('$method: an empty answer is still []', () async {
        final seen = <AppFailure>[];
        setFailureSink(seen.add);
        expect(await read(), isEmpty);
        expect(seen, isEmpty);
      });
    });
  });

  // ── Strength Progression ────────────────────────────────────────────────
  Future<void> pumpStrength(WidgetTester tester, List<Override> overrides) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProfileProvider.overrideWith((ref) async => {'unit_preference': 'metric'}),
        ...overrides,
      ],
      child: const MaterialApp(home: StrengthProgressionScreen()),
    ));
    await tester.pumpAndSettle();
  }

  group('Strength Progression', () {
    testWidgets('exercise list failure → error arm, Try again recovers', (tester) async {
      var calls = 0;
      await pumpStrength(tester, [
        loggedExerciseNamesProvider.overrideWith((ref) async {
          calls++;
          if (calls == 1) throw PostgrestException(message: 'boom', code: 'XX000');
          return ['Deadlift'];
        }),
        exerciseProgressionProvider('Deadlift').overrideWith((ref) async => [
              {'date': '2026-11-05', 'max_weight': 100.0, 'total_volume': 500.0, 'sets_count': 1},
            ]),
      ]);
      expect(find.text("Couldn't load your exercises"), findsOneWidget);
      expect(find.text(_otherwise), findsOneWidget);
      expect(find.text('No data yet'), findsNothing);
      expect(find.textContaining('Failed to load'), findsNothing);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text("Couldn't load your exercises"), findsNothing);
      expect(find.text('Current PR'), findsOneWidget);
    });

    testWidgets('exercise list empty → today\'s empty copy, unchanged', (tester) async {
      await pumpStrength(tester, [
        loggedExerciseNamesProvider.overrideWith((ref) async => <String>[]),
      ]);
      expect(find.text('No data yet'), findsOneWidget);
      expect(find.text('Complete workouts to see your strength progression over time.'),
          findsOneWidget);
      expect(find.textContaining("Couldn't load"), findsNothing);
    });

    testWidgets('chart failure → error arm scoped to the chart; busy-aware retry recovers',
        (tester) async {
      var calls = 0;
      final retry = Completer<List<Map<String, dynamic>>>();
      await pumpStrength(tester, [
        loggedExerciseNamesProvider.overrideWith((ref) async => ['Deadlift']),
        exerciseProgressionProvider('Deadlift').overrideWith((ref) {
          calls++;
          if (calls == 1) {
            return Future.error(const SocketException('offline'));
          }
          return retry.future;
        }),
      ]);
      expect(find.text("Couldn't load progress for Deadlift"), findsOneWidget);
      expect(find.text(_network), findsOneWidget,
          reason: 'a connection failure names the connection');
      expect(find.text('No data yet'), findsNothing,
          reason: 'THE defect: the failed chart read said "No data yet"');
      // Scoped: the picker above the chart is still there.
      expect(find.text('EXERCISE'), findsOneWidget);

      final button = find.widgetWithText(TextButton, 'Try again');
      expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
      await tester.tap(button);
      await tester.pump();
      // In flight: still the failure card, the button disabled — no double fire.
      final busy = tester.widget<TextButton>(find.byType(TextButton));
      expect(busy.onPressed, isNull);
      await tester.tap(find.byType(TextButton), warnIfMissed: false);
      await tester.pump();
      expect(calls, 2);

      retry.complete([
        {'date': '2026-11-05', 'max_weight': 100.0, 'total_volume': 500.0, 'sets_count': 1},
      ]);
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't load"), findsNothing);
      expect(find.text('Current PR'), findsOneWidget);
    });

    testWidgets('chart empty → today\'s empty copy, unchanged', (tester) async {
      await pumpStrength(tester, [
        loggedExerciseNamesProvider.overrideWith((ref) async => ['Deadlift']),
        exerciseProgressionProvider('Deadlift').overrideWith((ref) async => []),
      ]);
      expect(find.text('No data yet'), findsOneWidget);
      expect(find.text('No sets logged yet for this exercise.\nComplete a workout to see progress.'),
          findsOneWidget);
      expect(find.textContaining("Couldn't load"), findsNothing);
    });
  });

  // ── Coach: a client's PRs and recent sessions (J11) ─────────────────────
  Future<void> pumpCoach(WidgetTester tester, List<Override> overrides) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        clientWorkoutStatsProvider(_uid).overrideWith((ref) async => [
              {'client_id': 'c1', 'client_name': 'Ana', 'total_completed': 3},
            ]),
        ...overrides,
      ],
      child: const MaterialApp(home: CoachClientWorkoutScreen()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ana'));
    await tester.pumpAndSettle();
  }

  group("Coach's client workout view", () {
    testWidgets('PR failure → error arm, not "No personal records yet"; retry recovers',
        (tester) async {
      var calls = 0;
      await pumpCoach(tester, [
        clientPersonalRecordsProvider('c1').overrideWith((ref) async {
          calls++;
          if (calls == 1) throw PostgrestException(message: 'boom', code: 'XX000');
          return [
            {'exercise_name': 'Squat', 'weight_kg': 90.0, 'reps': 5},
          ];
        }),
        clientRecentSessionsProvider('c1').overrideWith((ref) async => []),
      ]);
      expect(find.text("Couldn't load Ana's personal records"), findsOneWidget);
      expect(find.text('No personal records yet'), findsNothing,
          reason: 'THE defect: a failed read was "No personal records yet"');
      // Scoped: the sessions list beside it still answers.
      expect(find.text('No sessions recorded'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.textContaining("Couldn't load"), findsNothing);
      expect(find.text('Squat'), findsOneWidget);
    });

    testWidgets('sessions failure → error arm, not "No sessions recorded"; retry recovers',
        (tester) async {
      var calls = 0;
      await pumpCoach(tester, [
        clientPersonalRecordsProvider('c1').overrideWith((ref) async => []),
        clientRecentSessionsProvider('c1').overrideWith((ref) async {
          calls++;
          if (calls == 1) throw PostgrestException(message: 'boom', code: 'XX000');
          return [
            {'workout_title': 'Leg Day', 'status': 'completed',
             'completed_at': '2026-11-10T10:00:00Z'},
          ];
        }),
      ]);
      expect(find.text("Couldn't load Ana's recent sessions"), findsOneWidget);
      expect(find.text(_otherwise), findsOneWidget);
      expect(find.text('No sessions recorded'), findsNothing,
          reason: 'THE defect: a failed read was "No sessions recorded"');
      expect(find.text('No personal records yet'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.textContaining("Couldn't load"), findsNothing);
      expect(find.text('Leg Day'), findsOneWidget);
    });

    testWidgets('both empty → today\'s empty copy, unchanged', (tester) async {
      await pumpCoach(tester, [
        clientPersonalRecordsProvider('c1').overrideWith((ref) async => []),
        clientRecentSessionsProvider('c1').overrideWith((ref) async => []),
      ]);
      expect(find.text('No personal records yet'), findsOneWidget);
      expect(find.text('No sessions recorded'), findsOneWidget);
      expect(find.textContaining("Couldn't load"), findsNothing);
    });
  });

  // ── Train hub: Personal Records section ─────────────────────────────────
  Future<void> pumpHub(WidgetTester tester, Override prs) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 6000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProfileProvider.overrideWith((ref) async => {'role': 'client'}),
        currentStreakProvider.overrideWith((ref) async => 0),
        weeklyWorkoutCountProvider.overrideWith((ref) async => 0),
        totalWorkoutCountProvider.overrideWith((ref) async => 0),
        completionRateProvider.overrideWith((ref) async => 0),
        activeSessionProvider.overrideWith((ref) async => null),
        assignedWorkoutsProvider.overrideWith((ref) async => []),
        prs,
      ],
      child: const MaterialApp(home: TrainHubScreen()),
    ));
    await tester.pumpAndSettle();
  }

  // The hub schedules a timer (scaffold chrome): unmount, then let it run out.
  Future<void> unmountHub(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  group('Train hub Personal Records', () {
    testWidgets('failure → error arm in place of the section; retry recovers', (tester) async {
      var calls = 0;
      await pumpHub(tester, personalRecordsProvider.overrideWith((ref) async {
        calls++;
        if (calls == 1) throw PostgrestException(message: 'boom', code: 'XX000');
        return [
          {'exercise_name': 'Bench Press', 'weight_kg': 80.0, 'reps': 5},
        ];
      }));
      expect(find.text("Couldn't load your personal records"), findsOneWidget,
          reason: 'THE defect: a failed read hid the section like "no records"');
      expect(find.text('PERSONAL RECORDS'), findsOneWidget);

      final button = find.widgetWithText(TextButton, 'Try again');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.textContaining("Couldn't load"), findsNothing);
      expect(find.text('Bench Press'), findsOneWidget);
      await unmountHub(tester);
    });

    testWidgets('empty → no section, unchanged', (tester) async {
      await pumpHub(tester, personalRecordsProvider.overrideWith((ref) async => []));
      expect(find.text('PERSONAL RECORDS'), findsNothing);
      expect(find.textContaining("Couldn't load"), findsNothing);
      await unmountHub(tester);
    });
  });
}
