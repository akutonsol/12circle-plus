import 'dart:convert';
import 'dart:io';

import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/workout/domain/load_format.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:circle_fitness/features/workout/presentation/strength_progression_screen.dart';
import 'package:circle_fitness/features/workout/presentation/workout_history_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// Loads are stored in kilograms and entered in the member's unit: the workout
// screen converts a set typed as 135 lb to 61.23496995 kg before saving
// (`unit_preference` 'metric' is kg, anything else -- the default -- is lb).
// The screens that showed those loads back ignored the preference:
//   * workout history printed the raw column: "61.23496995kg";
//   * Strength Progression's Current PR, Total Gain and session pills, and the
//     Train hub's personal-record rows, printed kg to a member who lifts in lb.
// The member logged 135 and was shown a different number in a different unit.

/// A set the member entered as 135 lb, as the workout screen stores it.
const entered135lbInKg = 135 * kgPerLb; // 61.23496995

class _Server extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final rows = request.url.path.endsWith('/workout_set_logs')
        ? [
            {
              'id': 'l1',
              'session_id': 's1',
              'exercise_name': 'Bench Press',
              'set_number': 1,
              'weight_kg': entered135lbInKg,
              'reps': 8,
              'completed': true,
            },
          ]
        : const [];
    return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(rows))), 200,
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

Override _profile(String? unitPreference) => currentUserProfileProvider
    .overrideWith((ref) async => {'id': 'u1', 'unit_preference': unitPreference});

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _Server(),
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryStore(),
        detectSessionInUri: false,
      ),
      debug: false,
    );
  });

  group('formatLoad', () {
    test('a load entered in lb comes back as entered', () {
      expect(formatLoad(entered135lbInKg, metric: false), '135 lb');
      expect(formatLoad(100, metric: false), '220.5 lb');
    });
    test('metric shows kg rounded to 0.1, without a trailing .0', () {
      expect(formatLoad(entered135lbInKg, metric: true), '61.2 kg');
      expect(formatLoad(100, metric: true), '100 kg');
      expect(formatLoad(62.5, metric: true), '62.5 kg');
    });
    test('a loss keeps its sign', () {
      expect(formatLoad(-2.5, metric: true), '-2.5 kg');
      expect(formatLoad(-kgPerLb * 5, metric: false), '-5 lb');
    });
    test("only 'metric' is metric; no preference is the app's default, lb", () {
      expect(prefersMetric('metric'), isTrue);
      expect(prefersMetric('imperial'), isFalse);
      expect(prefersMetric(null), isFalse);
    });
  });

  group('workout history', () {
    Future<void> openSession(WidgetTester tester, String? unit) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          _profile(unit),
          workoutHistoryProvider.overrideWith((ref) async => [
                {
                  'id': 's1',
                  'workout_title': 'Upper Body A',
                  'completed_at': '2026-11-12T12:00:00+00:00',
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
      await tester.tap(find.text('Upper Body A'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Bench Press'), findsOneWidget,
          reason: "guard the premise: the session's sets are shown");
    }

    Future<void> close(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    }

    testWidgets('a set entered as 135 lb reads 135 lb', (tester) async {
      await openSession(tester, 'imperial');
      expect(find.textContaining('61.23'), findsNothing,
          reason: 'THE defect: the raw column, "61.23496995kg"');
      expect(find.text('135 lb'), findsOneWidget);
      await close(tester);
    });

    testWidgets('a metric member sees kg (control)', (tester) async {
      await openSession(tester, 'metric');
      expect(find.text('61.2 kg'), findsOneWidget);
      await close(tester);
    });
  });

  group('Strength Progression', () {
    Future<void> show(WidgetTester tester, String? unit) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(900, 2400);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          _profile(unit),
          loggedExerciseNamesProvider.overrideWith((ref) async => ['Deadlift']),
          exerciseProgressionProvider('Deadlift').overrideWith((ref) async => [
                {'date': '2026-11-05', 'max_weight': 90.0, 'total_volume': 450.0, 'sets_count': 1},
                {'date': '2026-11-12', 'max_weight': 100.0, 'total_volume': 500.0, 'sets_count': 1},
              ]),
        ],
        child: const MaterialApp(home: StrengthProgressionScreen()),
      ));
      await tester.pumpAndSettle();
    }

    String statValue(String label) {
      final card = find.ancestor(of: find.text(label), matching: find.byType(Column)).first;
      final texts = find.descendant(of: card, matching: find.byType(Text)).evaluate()
          .map((e) => (e.widget as Text).data)
          .where((t) => t != label);
      return texts.single!;
    }

    testWidgets('an imperial member sees PR, gain and sessions in lb', (tester) async {
      await show(tester, 'imperial');
      expect(statValue('Current PR'), '220.5 lb', reason: 'was "100.0kg"');
      expect(statValue('Total Gain'), '+22 lb', reason: 'was "+10.0kg"');
      expect(find.text('198.4 lb'), findsWidgets, reason: "the 90 kg session's pill");
    });

    testWidgets('a metric member sees kg (control)', (tester) async {
      await show(tester, 'metric');
      expect(statValue('Current PR'), '100 kg');
      expect(statValue('Total Gain'), '+10 kg');
    });
  });

  test("the Train hub's record rows use the member's unit", () {
    // The hub's _PRRow is private to a screen with a dozen providers behind it;
    // this pins its one load string to the shared formatter.
    final src = File('lib/features/workout/presentation/train_hub_screen.dart').readAsStringSync();
    expect(src, contains(r"Text('${formatLoad(weight, metric: metric)} × $reps'"));
    expect(src, isNot(contains(r"Text('${weight.toStringAsFixed(1)} kg × $reps'")));
  });
}
