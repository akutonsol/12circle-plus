import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/features/habits/domain/habit_row.dart';

/// FIT-058 · the habit row's rules.
///
/// The board: *"Tapping the row is the whole interaction — no separate
/// checkbox to hit — with `role="checkbox"` so the state is announced."*

final _now = DateTime(2026, 9, 24, 12, 0);
DateTime _ago(int days) => _now.subtract(Duration(days: days));

void main() {
  group('completions this week', () {
    test('counts the last seven days including today', () {
      expect(
        completionsThisWeek(
            [for (var i = 0; i < 7; i++) _ago(i)], now: _now),
        7,
      );
      expect(completionsThisWeek([_ago(0), _ago(2), _ago(5)], now: _now), 3);
    });

    // `completedDates` is a raw list and can legitimately hold two entries for
    // one day. "6 of 7 this week" counts DAYS.
    test('two entries on one day count once', () {
      expect(
        completionsThisWeek([
          DateTime(2026, 9, 24, 7, 0),
          DateTime(2026, 9, 24, 21, 30),
        ], now: _now),
        1,
      );
    });

    test('anything older than seven days is outside the week', () {
      expect(completionsThisWeek([_ago(7), _ago(30)], now: _now), 0);
      // The seventh day back IS in the week; the eighth is not.
      expect(completionsThisWeek([_ago(6)], now: _now), 1);
    });

    test('a future date is not counted', () {
      expect(completionsThisWeek([_now.add(const Duration(days: 2))],
          now: _now), 0);
    });

    test('never done is zero, not an error', () {
      expect(completionsThisWeek(const [], now: _now), 0);
    });

    test('the count cannot exceed seven', () {
      expect(
        completionsThisWeek([for (var i = 0; i < 40; i++) _ago(i)], now: _now),
        7,
      );
    });
  });

  group('the week line', () {
    test('is the board\'s phrasing', () {
      expect(weekLine([for (var i = 0; i < 6; i++) _ago(i)], now: _now),
          '6 of 7 this week');
      expect(weekLine([for (var i = 0; i < 7; i++) _ago(i)], now: _now),
          '7 of 7 this week');
      expect(weekLine(const [], now: _now), '0 of 7 this week');
    });
  });

  group('the accessible name', () {
    test('carries the habit and its week', () {
      expect(
        habitRowLabel('10 minutes of walking',
            [for (var i = 0; i < 6; i++) _ago(i)], now: _now),
        '10 minutes of walking, 6 of 7 this week',
      );
    });

    // The state belongs to the checkbox role, not the name — a reader
    // announces "checked" in the user's own language rather than an English
    // word baked into a string.
    test('does not write the state into the name', () {
      final label = habitRowLabel('Protein at breakfast', [_ago(0)], now: _now);
      for (final w in const ['done', 'Done', 'checked', 'complete']) {
        expect(label, isNot(contains(w)));
      }
    });
  });

  group('the hint', () {
    // Both directions. A completed habit could not be undone AT ALL before
    // this — the completed state rendered a plain container.
    test('says what the tap will do, either way', () {
      expect(habitRowHint(completedToday: false), 'Mark as done today');
      expect(habitRowHint(completedToday: true), 'Mark as not done today');
    });
  });
}
