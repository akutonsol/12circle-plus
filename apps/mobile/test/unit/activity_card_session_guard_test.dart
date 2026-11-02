import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Activity screen's "TODAY'S WORKOUT" card must describe the client's
/// session exactly as Home's Today card does (`homeSession` /
/// `homeSessionBadges`, whose rules `home_session_card_test.dart` covers).
///
/// It used to read `name`, `duration_minutes` and `calories_burned` off a
/// program_workouts row — keys the row does not have — so every client saw
/// "Full Body Strength · 45 min · ~380 kcal" whatever their coach assigned, on
/// a rest day, and with no coach at all (F-20). This pins the wiring so the card
/// cannot drift back to its own private reading of the row.
void main() {
  final src = File('lib/features/activity/presentation/activity_screen.dart')
      .readAsStringSync();
  // Code only: the card's comment quotes the old fallback on purpose.
  final card = src
      .substring(src.indexOf('class _DailyWorkoutCard'), src.indexOf('class _WorkoutBadge'))
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  test('the card derives its session from the shared Home rules', () {
    expect(card, contains('homeSession(ref.watch(assignedWorkoutsProvider))'));
    expect(card, contains('homeSessionBadges(session.workout)'));
    expect(card, contains('session.emptyLine'));
  });

  test('the card invents nothing', () {
    expect(card, isNot(contains("'Full Body Strength'")));
    expect(card, isNot(contains('kcal')));
    expect(card, isNot(contains('todaysWorkoutProvider')));
    for (final key in ["'name'", "'duration_minutes'", "'calories_burned'"]) {
      expect(card, isNot(contains(key)), reason: '$key is not a program_workouts column');
    }
  });

  test('nothing to begin, nothing to start', () {
    expect(card, contains('if (session.canBegin)'));
  });
}
