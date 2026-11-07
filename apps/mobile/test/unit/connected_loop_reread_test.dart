import 'dart:convert';
import 'dart:io';

import 'package:circle_fitness/core/notifications/notification_watcher.dart';
import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart';
import 'package:circle_fitness/features/coach/domain/package_provider.dart';
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
      ]);
      addTearDown(container.dispose);
      for (final p in [
        assignedWorkoutsProvider,
        myAssignedProgramProvider,
        todaysWorkoutProvider,
        myNutritionPlanProvider,
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

    test('nutrition_assigned: the plan', () async {
      expect((await after('nutrition_assigned')).keys.toSet(), {'nutrition'});
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
}
