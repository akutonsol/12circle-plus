import 'dart:convert';

import 'package:circle_fitness/features/workout/data/workout_service.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// F-15 one screen further: the coach's client-workouts screen told a coach
// they had "No Active Clients" when the read had failed.
//
// `getClientWorkoutStats` ended `catch (_) { return []; }`. The screen draws
// `error: … 'Error loading stats'` for a failure and "No Active Clients /
// Your clients will appear here once they start training." for an empty
// list — and the catch made the first arm unreachable, so every failure was
// the second, a false statement about the coach's whole roster. This is the
// screen "Needs you today" sends a coach to for an AT-RISK client.
//
// The A-G5/A-G6 lesson: the repair existed at the presentation layer, over a
// service that destroyed the signal it needed.

class _Server extends http.BaseClient {
  bool fails = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = fails
        ? {'message': 'offline'}
        : [
            {'client_id': 'c1', 'coach_id': 'coach-a', 'workouts_this_week': 2},
          ];
    return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))),
        fails ? 503 : 200,
        request: request, headers: {'content-type': 'application/json'});
  }
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
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryStore(),
      ),
      debug: false,
    );
  });

  test('a failed read is a failure, not an empty roster', () async {
    server.fails = true;
    await expectLater(WorkoutService().getClientWorkoutStats('coach-a'),
        throwsA(anything),
        reason: '`[]` here is drawn as "No Active Clients"');
  });

  test('the screen\'s provider reaches its error arm', () async {
    server.fails = true;
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final sub = c.listen(clientWorkoutStatsProvider('coach-a'), (_, __) {});
    addTearDown(sub.close);
    await expectLater(
        c.read(clientWorkoutStatsProvider('coach-a').future), throwsA(anything));
    expect(c.read(clientWorkoutStatsProvider('coach-a')).hasError, isTrue,
        reason: "'Error loading stats' must be reachable");
  });

  test('a read that worked still returns its rows', () async {
    server.fails = false;
    final rows = await WorkoutService().getClientWorkoutStats('coach-a');
    expect(rows, hasLength(1));
  });
}
