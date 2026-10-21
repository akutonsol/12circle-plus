// Characterization tests for the Women's Health cycle computation
// (`features/womens_health/domain/cycle_phase.dart`).
//
// Added by QA Workstream F. Before this file the Women's Health subsystem had
// ZERO test coverage. These tests lock in the behaviour that exists TODAY so
// that remediation step 3H (CON-10 / findings F-08…F-13) has a real
// fails-before / passes-after signal.
//
// IMPORTANT: several expectations below assert behaviour the Workstream F
// report classifies as DEFECTIVE. They are marked `DEFECT:` and are expected to
// flip when 3H lands — that is the point of a characterization test, not a
// statement that the current behaviour is correct.
//
// `computeCycleStatus` reads `DateTime.now()` internally (finding F-16), so
// every case is expressed relative to today.

import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/womens_health/domain/cycle_phase.dart';

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

DateTime _daysAgo(int n) => _today().subtract(Duration(days: n));

/// Mirrors what a correct UI would ask: is today inside the *computed* window?
bool _inComputedFertileWindow(CycleStatus s) {
  if (s.fertileStart == null || s.fertileEnd == null) return false;
  final t = _today();
  return !t.isBefore(s.fertileStart!) && !t.isAfter(s.fertileEnd!);
}

/// Mirrors the predicate `womens_health_screen.dart` actually uses to render
/// the "Fertile window now" label.
bool _uiSaysFertile(CycleStatus s) =>
    s.phase == CyclePhase.ovulation || s.phase == CyclePhase.follicular;

CycleStatus _at(int dayOffset, {int cl = 28, int pl = 5}) => computeCycleStatus(
      lastPeriodStart: _daysAgo(dayOffset),
      cycleLength: cl,
      periodLength: pl,
    );

void main() {
  group('phase boundaries (28/5)', () {
    test('menstrual spans cycle days 1..periodLength', () {
      for (var d = 0; d < 5; d++) {
        final s = _at(d);
        expect(s.cycleDay, d + 1);
        expect(s.phase, CyclePhase.menstrual);
      }
    });

    test('follicular 6..12, ovulation 13..15, luteal 16..28', () {
      for (var d = 5; d < 12; d++) {
        expect(_at(d).phase, CyclePhase.follicular, reason: 'day ${d + 1}');
      }
      for (var d = 12; d < 15; d++) {
        expect(_at(d).phase, CyclePhase.ovulation, reason: 'day ${d + 1}');
      }
      for (var d = 15; d < 28; d++) {
        expect(_at(d).phase, CyclePhase.luteal, reason: 'day ${d + 1}');
      }
    });
  });

  group('fertile window', () {
    test('computed window is cycle days 12..16 (5 days)', () {
      final s = _at(0);
      expect(s.fertileStart, _today().add(const Duration(days: 11)));
      expect(s.fertileEnd, _today().add(const Duration(days: 15)));
      expect(s.fertileEnd!.difference(s.fertileStart!).inDays + 1, 5);
    });

    test('DEFECT F-10: `ovulation` is used as a 1-based cycle day by the '
        'phase classifier but as a 0-based offset by the window arithmetic, '
        'so the two disagree about which day ovulation is (14 vs 15)', () {
      // Classifier: ovulation phase = cycle days 13..15, i.e. ovulation == 14.
      expect(_at(11).phase, CyclePhase.follicular); // day 12
      expect(_at(12).phase, CyclePhase.ovulation);  // day 13
      expect(_at(14).phase, CyclePhase.ovulation);  // day 15
      expect(_at(15).phase, CyclePhase.luteal);     // day 16

      // Window arithmetic: fertileEnd == cycleStart + (ovulation + 1), which is
      // cycle day 16 -- consistent only if ovulation day were 15, not 14.
      final s = _at(0);
      expect(s.fertileEnd, _today().add(const Duration(days: 15))); // day 16

      // Net effect: the comment says "ovulation-3 .. ovulation+1" (asymmetric,
      // mostly BEFORE ovulation) but the delivered window is day 14 +/- 2,
      // i.e. two days AFTER the labelled ovulation day. The window WIDTH and
      // placement are a clinical parameter (Q-5); this internal disagreement
      // is not.
      final centre = s.fertileStart!.add(const Duration(days: 2));
      expect(centre, _today().add(const Duration(days: 13))); // cycle day 14
    });

    test('DEFECT F-08: the UI label disagrees with the computed window on '
        '7 of 28 days', () {
      final falsePositives = <int>[]; // UI says fertile, window says no
      final falseNegatives = <int>[]; // window says fertile, UI stays silent
      for (var d = 0; d < 28; d++) {
        final s = _at(d);
        final ui = _uiSaysFertile(s);
        final real = _inComputedFertileWindow(s);
        if (ui && !real) falsePositives.add(s.cycleDay);
        if (real && !ui) falseNegatives.add(s.cycleDay);
      }
      expect(falsePositives, [6, 7, 8, 9, 10, 11]);
      expect(falseNegatives, [16]);
    });
  });

  group('stale data', () {
    test('DEFECT F-09: a year-old log still reports a confident current phase',
        () {
      final s = _at(400);
      expect(s.hasData, isTrue);
      expect(s.phase, isNot(CyclePhase.unknown));
      expect(s.cycleDay, 9);
      expect(s.daysUntilNextPeriod, 20);
    });

    test('DEFECT F-09: no staleness bound exists at any age', () {
      for (final age in [45, 90, 200, 400, 1000]) {
        expect(_at(age).hasData, isTrue, reason: '$age days old');
      }
    });
  });

  group('missing / invalid input', () {
    test('PASS: a null last period yields unknown, and hasData is false', () {
      final s = computeCycleStatus(lastPeriodStart: null);
      expect(s.phase, CyclePhase.unknown);
      expect(s.hasData, isFalse);
      expect(s.cycleDay, 0);
      expect(s.fertileStart, isNull);
      expect(s.nextPeriodStart, isNull);
      expect(phaseGuides[s.phase], isNotNull);
    });

    test('DEFECT F-13: a future-dated start fabricates "Menstrual, day 1"', () {
      final s = computeCycleStatus(
          lastPeriodStart: _today().add(const Duration(days: 10)));
      expect(s.hasData, isTrue);
      expect(s.phase, CyclePhase.menstrual);
      expect(s.cycleDay, 1);
    });

    test('DEFECT F-14: out-of-range lengths are silently clamped', () {
      final s = computeCycleStatus(
          lastPeriodStart: _daysAgo(3), cycleLength: 0, periodLength: 0);
      expect(s.cycleLength, 21);
      expect(s.periodLength, 2);
    });
  });

  group('short-cycle phase collapse', () {
    Set<CyclePhase> reachable(int cl, int pl) => {
          for (var d = 0; d < cl; d++) _at(d, cl: cl, pl: pl).phase,
        };

    test('DEFECT F-11: cl=21 pl=5 never produces a follicular phase', () {
      expect(reachable(21, 5), isNot(contains(CyclePhase.follicular)));
    });

    test('DEFECT F-11: cl=21 pl=10 loses follicular AND ovulation, and the '
        'fertile window lands inside a "Menstrual" readout', () {
      final phases = reachable(21, 10);
      expect(phases, isNot(contains(CyclePhase.follicular)));
      expect(phases, isNot(contains(CyclePhase.ovulation)));

      final s = _at(5, cl: 21, pl: 10); // cycle day 6
      expect(s.phase, CyclePhase.menstrual);
      expect(_inComputedFertileWindow(s), isTrue);
    });

    test('follicular requires cycleLength >= periodLength + 17', () {
      expect(reachable(22, 5), contains(CyclePhase.follicular));
      expect(reachable(21, 5), isNot(contains(CyclePhase.follicular)));
    });
  });

  group('next-period prediction', () {
    test('DEFECT F-12: daysUntilNextPeriod is never <= 0, so the '
        '"Period expected today" branch is unreachable and the app can never '
        'report an overdue period', () {
      for (var cl = 21; cl <= 40; cl++) {
        for (var d = 0; d < 200; d++) {
          final n = _at(d, cl: cl).daysUntilNextPeriod;
          expect(n, isNotNull);
          expect(n, greaterThan(0), reason: 'cl=$cl age=$d');
          expect(n, lessThanOrEqualTo(cl));
        }
      }
    });
  });

  group('guidance content', () {
    test('every phase has a guide with training/recovery/nutrition copy', () {
      for (final p in CyclePhase.values) {
        final g = phaseGuides[p];
        expect(g, isNotNull, reason: '$p');
        expect(g!.training, isNotEmpty);
        expect(g.recovery, isNotEmpty);
        expect(g.nutrition, isNotEmpty);
      }
    });

    test('guidance is static per phase — it does not vary with cycle day, '
        'symptoms, energy or mood', () {
      final early = phaseGuides[_at(16).phase]!;
      final late = phaseGuides[_at(27).phase]!;
      expect(early.training, late.training);
    });
  });
}
