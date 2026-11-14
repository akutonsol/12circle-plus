import 'package:circle_fitness/features/ai_coach/domain/ai_insights.dart';
import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart';
import 'package:circle_fitness/features/workout/data/models/workout_model.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// The AI briefing named a different workout from Home.
//
// Home's hero (`homeSession`) shows `todaysSession()`: the session scheduled
// for today that is not yet done. The briefing's "Train today" took
// `assigned.first.title` — the plan's first workout — so on a Wednesday Home
// said "Lower Body" while the briefing said 'Your plan has "Upper Body"', and it
// named a workout on rest days and after the day's session was done.

Workout _w(String title, DateTime day, {bool done = false}) => Workout(
      id: title, title: title, description: '', estimatedDuration: 45,
      difficulty: 'intermediate', category: 'strength', exercises: const [],
      isCompleted: done, scheduledDate: day);

Future<String> _body(List<Workout> plan) async {
  final c = ProviderContainer(overrides: [
    todayScoreProvider.overrideWith((ref) async => const <String, dynamic>{}),
    currentStreakProvider.overrideWith((ref) async => 0),
    assignedWorkoutsProvider.overrideWith((ref) async => plan),
  ]);
  addTearDown(c.dispose);
  await c.read(assignedWorkoutsProvider.future);
  await c.read(todayScoreProvider.future);
  await c.read(currentStreakProvider.future);
  return c.read(aiDailySuggestionsProvider).firstWhere((s) => s.title == 'Train today').body;
}

void main() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 9);
  final yesterday = today.subtract(const Duration(days: 1));
  final tomorrow = today.add(const Duration(days: 1));

  test("the briefing names today's session, as Home does", () async {
    final body = await _body([_w('Upper Body', yesterday), _w('Lower Body', today)]);
    expect(body, contains('"Lower Body"'),
        reason: "THE defect: the plan's first workout was named instead");
  });

  test('on a day with nothing scheduled, it names no workout', () async {
    final body = await _body([_w('Upper Body', yesterday), _w('Full Body', tomorrow)]);
    expect(body, isNot(contains('Your plan has')));
  });

  test("today's session once done is not offered again", () async {
    final body = await _body([_w('Lower Body', today, done: true)]);
    expect(body, isNot(contains('"Lower Body"')));
  });
}
