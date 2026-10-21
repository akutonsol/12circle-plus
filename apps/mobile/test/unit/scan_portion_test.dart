import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/nutrition/presentation/widgets/ai_scan_view.dart';

/// FIT-020 · the AI scan result's portion control and save label.
///
/// ── THE DECISION THIS FILE REFUSES TO MAKE ─────────────────────────────────
/// The anchor gives three words — `Smaller`, `As shown`, `Larger` — and no
/// numbers. Turning them into fixed multipliers (0.75×, 1.5×) would be
/// deciding, on the owner's behalf, **how much food a client just ate**. That
/// number goes into their day's calories and to their coach.
///
/// So `Smaller` and `Larger` are *relative*, which is what the words mean, and
/// the step is the granularity the shipped slider already defines:
/// `(3.0 - 0.25) / 11`. `As shown` returns to 1.0 — the scan's own estimate,
/// the one value in this control that is not a judgement.
void main() {
  group('FIT-020 the step comes from the control that already shipped', () {
    test('one division of the existing slider, not a chosen figure', () {
      expect(scanPortionStep, closeTo((3.0 - 0.25) / 11, 1e-9));
      expect(scanPortionMin, 0.25);
      expect(scanPortionMax, 3.0);
      expect(scanPortionDivisions, 11);
    });

    test('Smaller moves down by exactly one step', () {
      expect(portionSmaller(1.0), closeTo(1.0 - scanPortionStep, 1e-9));
    });

    test('Larger moves up by exactly one step', () {
      expect(portionLarger(1.0), closeTo(1.0 + scanPortionStep, 1e-9));
    });

    test('Smaller then Larger returns to where it started', () {
      expect(portionLarger(portionSmaller(1.5)), closeTo(1.5, 1e-9));
    });
  });

  group('FIT-020 the control cannot leave its own range', () {
    test('Smaller stops at the floor rather than going negative', () {
      // A negative portion would scale the macros negative — a meal that
      // subtracts calories from the day.
      var p = scanPortionMin;
      for (var i = 0; i < 10; i++) {
        p = portionSmaller(p);
      }
      expect(p, scanPortionMin);
      expect(p, greaterThan(0));
    });

    test('Larger stops at the ceiling', () {
      var p = scanPortionMax;
      for (var i = 0; i < 10; i++) {
        p = portionLarger(p);
      }
      expect(p, scanPortionMax);
    });

    test('As shown is the scan\'s own estimate, not a step', () {
      expect(portionAsShown, 1.0);
    });
  });

  group('FIT-020 the save label names the meal being saved to', () {
    test('the anchor\'s own example, from real data', () {
      // The design draws "Save to lunch" because lunch was the selected chip.
      expect(scanSaveLabel('Lunch'), 'Save to lunch');
      expect(scanSaveLabel('Breakfast'), 'Save to breakfast');
    });

    test('a multi-word meal type reads as words, not as a database value', () {
      expect(scanSaveLabel('protein_shake'), 'Save to protein shake');
    });

    test('no meal type falls back rather than trailing off', () {
      // "Save to " with nothing after it is the bug this guards.
      expect(scanSaveLabel(''), 'Save');
      expect(scanSaveLabel('   '), 'Save');
      expect(scanSaveLabel('').endsWith(' '), isFalse);
    });
  });
}
