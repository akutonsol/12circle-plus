import 'dart:convert';

import 'package:circle_fitness/features/coach/data/coach_program_service.dart';
import 'package:circle_fitness/features/coach/data/score_service.dart';
import 'package:circle_fitness/features/habits/domain/habit_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// A habit tick that failed to save stayed ticked, and was scored (EC-12).
//
// `toggleComplete` and `updateValue` changed the habit on screen first and then
// ended `catch (_) {}`: offline, or on any RLS / FK failure, the habit showed as
// done with nothing said, the next load quietly reverted it, and
// `addHabitPoints` had already been awarded from the unsaved state.
// EC-12 (docs/QA_WORKSTREAM_B_ERROR_CONTRACT_REPORT.md) expects the `setMode`
// pattern: roll back and surface; never derive a persisted score from
// unpersisted state.

const _id = '11111111-1111-4111-8111-111111111111';

class _Habits extends CoachProgramService {
  _Habits({required this.fails});
  final bool fails;
  @override
  Future<List<Map<String, dynamic>>> getMyHabits() async => [
        {'id': _id, 'name': 'Walk', 'emoji': '🚶', 'category': 'fitness',
         'target_value': 4, 'unit': 'times'},
      ];
  @override
  Future<List<Map<String, dynamic>>> getTodayHabitLogs() async => const [];
  @override
  Future<Map<String, int>> getHabitStreaks() async => const {};
  @override
  Future<void> logHabit(String habitId, {double value = 1, bool completed = true}) async {
    if (fails) throw const PostgrestException(message: 'offline', code: '500');
  }
}

class _Score extends ScoreService {
  int awards = 0;
  @override
  Future<void> addHabitPoints(int completed, int total) async => awards++;
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

class _Offline extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(Stream.value(utf8.encode('[]')), 200,
          request: request, headers: {'content-type': 'application/json'});
}

Future<LiveHabitNotifier> _loaded(LiveHabitNotifier n) async {
  for (var i = 0; i < 50 && !n.state.hasValue; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return n;
}

bool _done(LiveHabitNotifier n) =>
    n.state.requireValue.firstWhere((h) => h.id == _id).isCompletedToday;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dexterous.com/flutter/local_notifications'),
            (call) async => call.method == 'initialize' ? true : null);
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _Offline(),
      authOptions: FlutterAuthClientOptions(
          localStorage: const EmptyLocalStorage(),
          pkceAsyncStorage: _MemoryStore(),
          detectSessionInUri: false),
      debug: false,
    );
  });

  test('a tick that did not save is put back, and not scored', () async {
    final score = _Score();
    final n = await _loaded(LiveHabitNotifier(_Habits(fails: true), score));
    addTearDown(n.dispose);
    final Object? ok = await (n.toggleComplete(_id) as Future<Object?>);
    expect(_done(n), isFalse,
        reason: 'THE defect: the habit stayed ticked though nothing was saved');
    expect(score.awards, 0, reason: 'points were awarded for an unsaved tick');
    expect(ok, false, reason: 'the screen must be told so it can say so');
  });

  test('a counted value that did not save is put back', () async {
    final n = await _loaded(LiveHabitNotifier(_Habits(fails: true), _Score()));
    addTearDown(n.dispose);
    final Object? ok = await (n.updateValue(_id, 3) as Future<Object?>);
    expect(n.state.requireValue.single.currentValue, 0);
    expect(ok, false);
  });

  test('control: a tick that saved stays, and is scored', () async {
    final score = _Score();
    final n = await _loaded(LiveHabitNotifier(_Habits(fails: false), score));
    addTearDown(n.dispose);
    final Object? ok = await (n.toggleComplete(_id) as Future<Object?>);
    expect(_done(n), isTrue);
    expect(score.awards, 1);
    expect(ok, true);
  });
}
