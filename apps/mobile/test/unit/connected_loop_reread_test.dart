import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:circle_fitness/core/notifications/notification_watcher.dart';
import 'package:circle_fitness/features/checkins/domain/checkin_provider.dart';
import 'package:circle_fitness/features/checkins/presentation/checkin_hub_sections.dart'
    show checkinHistoryProvider;
import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart';
import 'package:circle_fitness/features/coach/domain/coach_provider.dart';
import 'package:circle_fitness/features/payments/domain/entitlements.dart';
import 'package:circle_fitness/features/coach/domain/package_provider.dart';
import 'package:circle_fitness/features/coach/data/coach_program_service.dart';
import 'package:circle_fitness/features/coach/data/score_service.dart';
import 'package:circle_fitness/features/habits/domain/habit_provider.dart';
import 'package:circle_fitness/features/nutrition/domain/nutrition_provider.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// The two people in the loop could not see each other's work.
//
//   * The coach's page for a client was cached for the life of the app. A coach
//     who looked at a client this morning, and came back after that client
//     trained, saw this morning's page until the app was restarted. The same
//     cache is why a client's new plan did not unlock Assign without a reload.
//   * The client's program was cached the same way. The notification that a
//     program had been assigned arrived, and Home went on saying there was none.

const _uid = '00000000-0000-4000-8000-00000000100f';

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

/// See workout_finish_truth's sibling harnesses: the token is read, never verified.
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

class _CountingClient extends http.BaseClient {
  int reads = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'GET') reads++;
    return http.StreamedResponse(
      Stream.value(utf8.encode('[]')),
      200,
      request: request,
      headers: {'content-type': 'application/json'},
    );
  }
}

/// Loading real habits schedules device reminders, which a unit test cannot
/// host. The read failing ends the load before that, and the count is taken
/// when the notifier is created, which is what is being asserted.
class _NoHabitsRead extends CoachProgramService {
  @override
  Future<List<Map<String, dynamic>>> getMyHabits() async =>
      throw StateError('not read in this test');
}

/// Holds the habits read open until the test lets it finish.
class _GatedHabits extends CoachProgramService {
  _GatedHabits(this.gate);
  final Completer<List<Map<String, dynamic>>> gate;
  @override
  Future<List<Map<String, dynamic>>> getMyHabits() => gate.future;
}

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late _CountingClient client;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    client = _CountingClient();
    await Supabase.initialize(
      // Unroutable, and every request is answered by the client above.
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: client,
      authOptions: FlutterAuthClientOptions(
        localStorage: _SeededSession(),
        pkceAsyncStorage: _MemoryStore(),
      ),
      debug: false,
    );
  });

  group('the coach reopening a client page reads it again', () {
    final pages = <String, ProviderListenable<Object?>>{
      'the client page': clientDetailProvider('c1'),
      'whether a plan unlocks Assign': clientHasPaidPlanProvider('c1'),
      'the client\'s schedule': clientScheduleProvider('c1'),
      'recent sessions': clientRecentSessionsProvider('c1'),
      'personal records': clientPersonalRecordsProvider('c1'),
      'the roster\'s workout stats': clientWorkoutStatsProvider('coach1'),
      'the coach\'s check-in queue': coachSubmittedCheckinsProvider,
      'the client\'s check-in history': checkinHistoryProvider,
    };

    pages.forEach((name, provider) {
      test(name, () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        client.reads = 0;
        final firstVisit = container.listen<Object?>(provider, (_, __) {});
        await _settle();
        final afterFirst = client.reads;
        expect(afterFirst, greaterThan(0), reason: 'it reads the network at all');

        firstVisit.close();
        await container.pump();
        await _settle();

        container.listen<Object?>(provider, (_, __) {});
        await _settle();
        expect(client.reads, greaterThan(afterFirst),
            reason: 'the second visit must not be served the first visit\'s answer');
      });
    });
  });

  group('a notification that something was assigned re-reads it', () {
    late Map<String, int> reads;
    late ProviderContainer container;

    setUp(() {
      reads = {};
      Override counted<T>(String name, FutureProvider<T?> p, T? value) =>
          p.overrideWith((ref) async {
            reads[name] = (reads[name] ?? 0) + 1;
            return value;
          });
      container = ProviderContainer(overrides: [
        assignedWorkoutsProvider.overrideWith((ref) async {
          reads['workouts'] = (reads['workouts'] ?? 0) + 1;
          return const [];
        }),
        counted<Map<String, dynamic>>('program', myAssignedProgramProvider, null),
        counted<Map<String, dynamic>>('today', todaysWorkoutProvider, null),
        counted<Map<String, dynamic>>('nutrition', myNutritionPlanProvider, null),
        coachSubmittedCheckinsProvider.overrideWith((ref) async {
          reads['queue'] = (reads['queue'] ?? 0) + 1;
          return const [];
        }),
        checkinHistoryProvider.overrideWith((ref) async {
          reads['history'] = (reads['history'] ?? 0) + 1;
          return const [];
        }),
        // What the client's nutrition screens actually read (Nutrition, Meals,
        // Meal plan) — not `myNutritionPlanProvider`, which no screen reads.
        nutritionGoalsProvider.overrideWith((ref) async {
          reads['goals'] = (reads['goals'] ?? 0) + 1;
          return const <String, double>{};
        }),
        myHabitsProvider.overrideWith((ref) async {
          reads['habits'] = (reads['habits'] ?? 0) + 1;
          return const <Map<String, dynamic>>[];
        }),
        // The Habits screen. A new notifier is a new read (it loads on creation).
        liveHabitNotifierProvider.overrideWith((ref) {
          reads['live habits'] = (reads['live habits'] ?? 0) + 1;
          return LiveHabitNotifier(_NoHabitsRead(), ScoreService());
        }),
        // N10: what the client is shown about their coach, and the plan an
        // active relationship grants (`client_plan()` answers coach_guided).
        counted<Map<String, dynamic>>('coach', assignedCoachProvider, null),
        counted<Map<String, dynamic>>('pending', pendingCoachProvider, null),
        counted<Map<String, dynamic>>('relationship', clientRelationshipProvider, null),
        myCoachesProvider.overrideWith((ref) async {
          reads['coaches'] = (reads['coaches'] ?? 0) + 1;
          return const <Map<String, dynamic>>[];
        }),
        clientPlanProvider.overrideWith((ref) async {
          reads['plan'] = (reads['plan'] ?? 0) + 1;
          return ClientPlan.free;
        }),
      ]);
      addTearDown(container.dispose);
      for (final p in <ProviderListenable<Object?>>[
        assignedWorkoutsProvider,
        myAssignedProgramProvider,
        todaysWorkoutProvider,
        myNutritionPlanProvider,
        coachSubmittedCheckinsProvider,
        checkinHistoryProvider,
        nutritionGoalsProvider,
        myHabitsProvider,
        liveHabitNotifierProvider,
        assignedCoachProvider,
        pendingCoachProvider,
        clientRelationshipProvider,
        myCoachesProvider,
        clientPlanProvider,
      ]) {
        container.listen<Object?>(p, (_, __) {});
      }
    });

    Future<Map<String, int>> after(String? type) async {
      await _settle();
      final before = Map.of(reads);
      refreshForNotification(type, container.invalidate);
      await _settle();
      return {
        for (final k in reads.keys)
          if (reads[k] != before[k]) k: reads[k]! - before[k]!,
      };
    }

    test('program_assigned: the program, its workouts and today', () async {
      expect((await after('program_assigned')).keys.toSet(),
          {'workouts', 'program', 'today'});
    });

    test('nutrition_assigned: the plan, and the goals the screens show',
        () async {
      // The coach's new targets reached `myNutritionPlanProvider` only; the
      // client's open Nutrition screen went on showing the old goals.
      expect((await after('nutrition_assigned')).keys.toSet(),
          {'nutrition', 'goals'});
    });

    test('habits_assigned: the habits list and the Habits screen', () async {
      // Unhandled: a client on Habits kept the list they opened, which for a
      // new client is the made-up defaults (I6), until the app restarted.
      expect((await after('habits_assigned')).keys.toSet(),
          {'habits', 'live habits'});
    });

    test('weekly_checkins: the coach\'s review queue', () async {
      expect((await after('weekly_checkins')).keys.toSet(), {'queue'});
    });

    test('checkin: the client\'s history, where the coach\'s reply is shown',
        () async {
      // `submitCoachFeedback` is the only sender of this type, and it sends it
      // to the client: "Coach Feedback Ready".
      expect((await after('checkin')).keys.toSet(), {'history'});
    });

    test('request_approved: the coach, the request, and the plan it grants',
        () async {
      // N10: unhandled. The client was told "Coach Request Approved" over a
      // profile still showing the request as sent and a plan still gated as
      // before, until the app restarted.
      expect((await after('request_approved')).keys.toSet(),
          {'coach', 'pending', 'relationship', 'coaches', 'plan'});
    });

    test('request_declined: the request, which is no longer pending', () async {
      expect((await after('request_declined')).keys.toSet(),
          {'pending', 'relationship'});
    });

    test('anything else re-reads nothing', () async {
      expect(await after('message'), isEmpty);
      expect(await after(null), isEmpty);
    });

    test('[SOURCE] the watcher does this for a new row, not for history', () {
      final src = File('lib/core/notifications/notification_watcher.dart').readAsStringSync();
      final primed = src.indexOf('if (_primed)');
      final call = src.indexOf('refreshForNotification(r[');
      expect(primed, greaterThan(0));
      expect(call, greaterThan(primed),
          reason: 'the first batch only primes the seen set: it is not new');
    });
  });

  test('habits replaced mid-load: the replaced list writes nothing', () async {
    // `habits_assigned` can land while the Habits screen is still loading. The
    // notifier it replaces then finished its read and wrote to itself after
    // disposal — "Tried to use LiveHabitNotifier after `dispose`".
    final gate = Completer<List<Map<String, dynamic>>>();
    final container = ProviderContainer(overrides: [
      liveHabitNotifierProvider.overrideWith(
          (ref) => LiveHabitNotifier(_GatedHabits(gate), ScoreService())),
    ]);
    addTearDown(container.dispose);
    container.listen<Object?>(liveHabitNotifierProvider, (_, __) {});
    await _settle();

    refreshForNotification('habits_assigned', container.invalidate);
    await _settle();
    gate.completeError(StateError('the read ends after the notifier was replaced'));
    await _settle();

    expect(container.read(liveHabitNotifierProvider).hasError, isTrue,
        reason: 'the live notifier still reports its own read');
  });
}
