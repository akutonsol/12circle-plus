import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// HOME-H1 · the Home coach card never speaks for a coach who did not speak.
///
/// ── THE DEFECT THIS CLOSES (I-LEG-03 / M-08, retired by decision-log 2026-10-21)
/// `coach_tips` has never existed in any migration, so `coachTipProvider` always
/// returned null and the card fell back to a hard-coded sentence — shown under
/// the assigned coach's NAME and AVATAR with a "TIP" badge. Every member saw a
/// message attributed to their coach that the coach never wrote.
///
/// The card keeps what is real (the coach's identity and the Rate entry point).
/// A tip may return, but only with a backing table and an authoring surface; at
/// that point this guard is deliberately rewritten, not deleted.
void main() {
  String strip(String s) =>
      s.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '').replaceAll(RegExp(r'//[^\n]*'), '');

  final home = strip(
      File('lib/features/home/presentation/home_screen.dart').readAsStringSync());
  final provider = strip(
      File('lib/features/coach/domain/coach_provider.dart').readAsStringSync());

  test('the Home screen source is readable and non-trivial', () {
    expect(home.length, greaterThan(5000),
        reason: 'the file did not load — every assertion below is vacuous');
    expect(home, contains('_CoachCard'),
        reason: 'premise: the coach card still exists');
  });

  test('no hard-coded sentence is presented as the coach\'s tip', () {
    expect(home, isNot(contains('Stay consistent. Small daily actions')),
        reason: 'a fabricated tip is shown under the coach\'s name again');
    expect(home, isNot(contains("'TIP'")),
        reason: 'a TIP badge implies authored content the card cannot have');
  });

  test('nothing reads the table that does not exist', () {
    expect(home, isNot(contains('coachTipProvider')));
    expect(provider, isNot(contains('coach_tips')));
    expect(provider, isNot(contains('coachTipProvider')));
  });
}
