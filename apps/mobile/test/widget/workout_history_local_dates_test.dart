import 'dart:convert';

import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:circle_fitness/features/workout/presentation/workout_history_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// /workout-history dated each session with the month and day of
// `DateTime.parse(completed_at)`. `completed_at` is a timestamptz, so that is
// the UTC date: a 21:30 session in New York (02:30 UTC) was listed under the
// next day, and a 05:00 session in Tokyo (20:00 UTC) under the day before.
// The same sessions count toward the local-day streak on Home, so the two
// screens disagreed about which day a workout was done.
//
// ── RUN IT WEST AND EAST OF UTC ─────────────────────────────────────────────
// Dart has no injectable local zone, so this reads the process's. Under UTC
// (CI) both dates agree and the cases pass either way; the defect shows under
//   TZ=America/New_York flutter test test/widget/workout_history_local_dates_test.dart
//   TZ=Asia/Tokyo       flutter test test/widget/workout_history_local_dates_test.dart

class _EmptyClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(Stream.value(utf8.encode('[]')), 200,
          request: request, headers: {'content-type': 'application/json'});
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

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// The calendar day the person who did [utc] lived it on.
String _localDay(String utc) {
  final d = DateTime.parse(utc).toLocal();
  return '${_months[d.month - 1]} ${d.day}, ${d.year}';
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _EmptyClient(),
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryStore(),
      ),
      debug: false,
    );
  });

  Future<void> show(WidgetTester tester, String completedAt) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        workoutHistoryProvider.overrideWith((ref) async => [
              {
                'id': 's1',
                'workout_title': 'Lower Body A',
                'completed_at': completedAt,
                'duration_seconds': 2700,
                'calories_burned': 320,
              },
            ]),
      ],
      child: const MaterialApp(home: WorkoutHistoryScreen()),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Unmounts and lets the scaffold's bell-shake timer run out.
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  testWidgets('an evening session west of UTC is dated the day it was done',
      (tester) async {
    // 21:30 in New York on Nov 11.
    const at = '2026-11-12T02:30:00+00:00';
    await show(tester, at);
    expect(find.text('Lower Body A'), findsOneWidget,
        reason: 'guard the premise: the session is listed');
    expect(find.textContaining(_localDay(at)), findsOneWidget);
    await close(tester);
  });

  testWidgets('an early session east of UTC is dated the day it was done',
      (tester) async {
    // 05:00 in Tokyo on Nov 13.
    const at = '2026-11-12T20:00:00+00:00';
    await show(tester, at);
    expect(find.textContaining(_localDay(at)), findsOneWidget);
    await close(tester);
  });

  testWidgets('a midday session is the same day everywhere (control)',
      (tester) async {
    const at = '2026-11-12T12:00:00+00:00';
    await show(tester, at);
    expect(find.textContaining('Nov 12, 2026'), findsOneWidget);
    await close(tester);
  });
}
