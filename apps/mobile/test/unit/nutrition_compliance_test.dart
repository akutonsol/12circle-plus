import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/checkins/domain/nutrition_compliance.dart';

void main() {
  // Monday 2026-10-19; "now" is Sunday 2026-10-25 so all seven days have started.
  final monday = DateTime(2026, 10, 19);
  final sunday = DateTime(2026, 10, 25, 20);
  ({DateTime at, num calories}) log(int dayOffset, num cal, {int hour = 12}) =>
      (at: DateTime(2026, 10, 19 + dayOffset, hour), calories: cal);

  int? pct(List<({DateTime at, num calories})> logs, {num? target = 2000, DateTime? now}) =>
      nutritionCompliancePercent(
          logs: logs, target: target, weekStart: monday, now: now ?? sunday);

  group('nutritionCompliancePercent', () {
    test('every day on target is 100', () {
      expect(pct([for (var i = 0; i < 7; i++) log(i, 2000)]), 100);
    });

    test('±10 % is inside, just past it is a miss (boundary)', () {
      expect(pct([log(0, 2200), for (var i = 1; i < 7; i++) log(i, 2000)]), 100,
          reason: '+10.0 % exactly is within tolerance');
      expect(pct([log(0, 2201), for (var i = 1; i < 7; i++) log(i, 2000)]), 86,
          reason: '6 of 7 days');
      expect(pct([log(0, 1800), for (var i = 1; i < 7; i++) log(i, 2000)]), 100);
      expect(pct([log(0, 1799), for (var i = 1; i < 7; i++) log(i, 2000)]), 86);
    });

    test('several meals on one day are summed', () {
      expect(pct([log(0, 700), log(0, 800, hour: 18), log(0, 500, hour: 21),
                  for (var i = 1; i < 7; i++) log(i, 2000)]), 100);
    });

    test('a day with nothing logged is a MISS, not a skip', () {
      expect(pct([for (var i = 0; i < 6; i++) log(i, 2000)]), 86);
    });

    test('null — never 0 — when there is no usable target', () {
      expect(pct([log(0, 2000)], target: null), isNull);
      expect(pct([log(0, 2000)], target: 0), isNull);
    });

    test('null — never 0 — when nothing was logged all week', () {
      expect(pct(const []), isNull);
    });

    test('only days that have started count: Wednesday morning is 3 days', () {
      final wed = DateTime(2026, 10, 21, 9);
      expect(pct([log(0, 2000), log(1, 2000)], now: wed), 67,
          reason: 'Mon + Tue hit, Wed not yet logged → 2 of 3');
    });

    test('a week that crosses the DST change still has seven calendar days', () {
      // 2026-11-01 is the US fall-back date. A Duration(days: n) step from Monday
      // 2026-10-26 would land on the wrong date by Sunday.
      final w = DateTime(2026, 10, 26);
      final logs = [
        for (var i = 0; i < 7; i++)
          (at: DateTime(2026, 10, 26 + i, 12), calories: 2000 as num),
      ];
      expect(nutritionCompliancePercent(
          logs: logs, target: 2000, weekStart: w, now: DateTime(2026, 11, 1, 22)), 100);
    });
  });
}
