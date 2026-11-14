import 'dart:io';

import 'package:circle_fitness/features/scoring/domain/score_provider.dart';
import 'package:flutter_test/flutter_test.dart';

// "This month" showed last month's points until the next award.
//
// `user_scores.current_cycle_score` resets only when `award_points` runs (035),
// so on the 1st — until the member earned something — Home's score ring, the
// Wellness Pulse, the Score screen and the AI insight all showed LAST month's
// total as this month's, while the leaderboard (which filters
// `current_period = to_char(now(), 'YYYY-MM')`) already left them out.

void main() {
  final now = DateTime.utc(2026, 12, 1, 9);

  test("a row from last month is no points this month", () {
    expect(cycleScoreOf({'current_period': '2026-11', 'current_cycle_score': 840}, now: now), 0,
        reason: "THE defect: November's 840 shown as December's");
  });

  test("this month's row is this month's points", () {
    expect(cycleScoreOf({'current_period': '2026-12', 'current_cycle_score': 35}, now: now), 35);
  });

  test('the period is the server\'s UTC month', () {
    // 23:30 on 30 Nov in New York is already December in UTC.
    final late = DateTime.utc(2026, 12, 1, 4, 30);
    expect(cycleScoreOf({'current_period': '2026-12', 'current_cycle_score': 5}, now: late), 5);
  });

  test('no row is no points', () => expect(cycleScoreOf(null, now: now), 0));

  test('guard: no screen reads current_cycle_score past the period check', () {
    // Source guard over the four places that show the figure.
    for (final p in [
      'lib/features/home/presentation/home_screen.dart',
      'lib/features/ai_coach/domain/ai_insights.dart',
      'lib/features/scoring/presentation/score_screen.dart',
    ]) {
      expect(File(p).readAsStringSync().contains("['current_cycle_score']"), isFalse, reason: p);
    }
  });
}
