import 'dart:convert';

import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/coach/data/coach_program_service.dart';
import 'package:circle_fitness/features/coach/data/score_service.dart';
import 'package:circle_fitness/features/habits/domain/habit_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// A client with no habits was shown eight that are not theirs.
//
// When `getMyHabits()` returned no rows, both habit reads fell back to
// `HabitService().getDefaultHabits()`: Water, Sleep, Steps… with invented
// streaks (7, 4, 12, 3, 9, 5, 6, 2), "Supplements" already done today, and ids
// '1'–'8' that are not rows (`habit_logs.habit_id` is a uuid FK, so ticking one
// failed silently). The Habits screen's own "No habits yet" state could never
// appear, and on a device reminders were scheduled for the samples. The
// `habitNotifierProvider` shim did the same while the real read was in flight,
// and the header's adherence and streak figures are computed from it.

class _Habits extends CoachProgramService {
  _Habits(this.rows);
  final List<Map<String, dynamic>> rows;
  @override
  Future<List<Map<String, dynamic>>> getMyHabits() async => rows;
  @override
  Future<List<Map<String, dynamic>>> getTodayHabitLogs() async => const [];
  @override
  Future<Map<String, int>> getHabitStreaks() async => const {};
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

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Habit reminders are scheduled on load; the plugin answers nothing here.
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

  ProviderContainer container(List<Map<String, dynamic>> rows) {
    final c = ProviderContainer(overrides: [
      currentUserProvider.overrideWithValue(null),
      liveHabitNotifierProvider.overrideWith(
          (ref) => LiveHabitNotifier(_Habits(rows), ScoreService())),
    ]);
    addTearDown(c.dispose);
    c.listen<Object?>(liveHabitNotifierProvider, (_, __) {});
    return c;
  }

  test('no habits read back is no habits on the Habits screen', () async {
    final c = container(const []);
    await _settle();
    final habits = c.read(liveHabitNotifierProvider).valueOrNull;
    expect(habits, isNotNull);
    expect(habits!.map((h) => h.name), isEmpty,
        reason: 'THE defect: eight sample habits with invented streaks were shown');
  });

  test('the header shows no invented adherence or streak', () async {
    final c = container(const []);
    await _settle();
    expect(c.read(totalStreakProvider), 0,
        reason: "the samples' streaks summed to 48 days the client never had");
    expect(c.read(adherenceScoreProvider), 0);
  });

  test('before the read answers, nothing is claimed', () {
    final c = container(const []);
    expect(c.read(habitNotifierProvider), isEmpty);
    expect(c.read(totalStreakProvider), 0);
  });

  test("control: a client's own habits are shown", () async {
    final c = container([
      {'id': '11111111-1111-4111-8111-111111111111', 'name': 'Walk', 'emoji': '🚶',
       'category': 'fitness', 'target_value': 1, 'unit': 'times'},
    ]);
    await _settle();
    expect(c.read(liveHabitNotifierProvider).valueOrNull!.map((h) => h.name), ['Walk']);
  });
}
