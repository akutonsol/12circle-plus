import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/features/nutrition/domain/meal_row.dart';

/// FIT-003 · the "What you ate" rows.
///
/// The board's three rows are sample meals. What is testable is the shape they
/// take — and the middle line, `Breakfast · 07:20`, which the shipped card did
/// not render at all despite `nutrition_logs` carrying `meal_type` and
/// `logged_at` since migration 012.

void main() {
  group('mealRowDetail — the line that was missing', () {
    test('the board\'s first two rows, exactly', () {
      expect(
        mealRowDetail(
            mealType: 'breakfast', loggedAt: DateTime(2026, 9, 8, 7, 20)),
        'Breakfast · 07:20',
      );
      expect(
        mealRowDetail(mealType: 'lunch', loggedAt: DateTime(2026, 9, 8, 12, 45)),
        'Lunch · 12:45',
      );
    });

    test('a single-digit hour keeps its zero', () {
      expect(mealTime(DateTime(2026, 9, 8, 7, 5)), '07:05');
      expect(mealTime(DateTime(2026, 9, 8, 0, 0)), '00:00');
      expect(mealTime(DateTime(2026, 9, 8, 23, 59)), '23:59');
    });

    test('half a line is better than a fabricated one', () {
      expect(mealRowDetail(mealType: 'lunch'), 'Lunch');
      expect(mealRowDetail(loggedAt: DateTime(2026, 9, 8, 12, 45)), '12:45');
      expect(mealRowDetail(), '');
    });

    // A value the CHECK constraint does not permit is not title-cased into a
    // plausible word. A word invented from a database value is still invented.
    test('an unknown meal type produces no word', () {
      expect(mealTypeLabel('brunch'), isNull);
      expect(mealTypeLabel(''), isNull);
      expect(mealTypeLabel(null), isNull);
      expect(mealRowDetail(mealType: 'brunch'), '');
    });

    test('every value the schema permits has a word', () {
      for (final t in mealTypeOrder) {
        expect(mealTypeLabel(t), isNotNull, reason: '$t has no label');
      }
      expect(mealTypeOrder, hasLength(5));
    });

    test('case and padding from the database do not matter', () {
      expect(mealTypeLabel('  BREAKFAST '), 'Breakfast');
    });
  });

  // OD-22. The board's third row reads `After training · 18:10`, but
  // `meal_type` is a CHECK over five values and "after training" is not one.
  // It states WHEN a meal was taken relative to a session, and nothing in this
  // product links a nutrition log to a workout. Rendering it would assert a
  // training session that may not have happened.
  group('OD-22 · the board\'s third row cannot be followed', () {
    test('protein_shake reads as itself, never as "After training"', () {
      expect(mealTypeLabel('protein_shake'), 'Protein shake');
    });

    test('the board\'s phrase is produced by nothing', () {
      for (final t in mealTypeOrder) {
        expect(mealTypeLabel(t), isNot(contains('training')),
            reason: 'OD-22 must not be resolved silently — if a link between '
                'a meal and a session is added, decide this deliberately');
      }
    });
  });

  group('the row label', () {
    test('is the shape the manifest declares, plus a spoken unit', () {
      expect(
        mealRowLabel(
          name: 'Greek yoghurt, berries, seeds',
          mealType: 'breakfast',
          loggedAt: DateTime(2026, 9, 8, 7, 20),
          calories: 380,
        ),
        'Greek yoghurt, berries, seeds Breakfast · 07:20 380 kcal',
      );
    });

    // The board can let the header carry `kcal`. A spoken label cannot — a
    // bare "380" at the end of a sentence tells a screen-reader user nothing.
    test('kcal is spoken even though the row does not draw it', () {
      expect(mealRowLabel(name: 'Toast', calories: 200), 'Toast 200 kcal');
    });

    test('calories round rather than reading 380.0', () {
      expect(mealCalories(380.0), '380');
      expect(mealCalories(379.6), '380');
      expect(mealCalories(null), '0');
    });
  });

  group('the macro rule — three figures against their targets', () {
    test('reads as the board writes it', () {
      const p = MacroFigure(name: 'Protein', value: 118, target: 140);
      expect(p.reading, '118 g');
      expect(p.against, 'Protein · 140');
      expect(p.spoken, 'Protein 118 of 140 grams');
    });

    // A macro with no target must not read against a zero it was never
    // measured against.
    test('no target means no comparison, spoken or drawn', () {
      const c = MacroFigure(name: 'Carbs', value: 164);
      expect(c.against, 'Carbs');
      expect(c.spoken, 'Carbs 164 grams');
      expect(c.against, isNot(contains('·')));
    });

    test('the board\'s three, in full', () {
      const figures = [
        MacroFigure(name: 'Protein', value: 118, target: 140),
        MacroFigure(name: 'Carbs', value: 164, target: 210),
        MacroFigure(name: 'Fat', value: 52, target: 68),
      ];
      expect(figures.map((f) => '${f.reading} ${f.against}').toList(), [
        '118 g Protein · 140',
        '164 g Carbs · 210',
        '52 g Fat · 68',
      ]);
    });
  });

  group('the calorie readout', () {
    test('thousands are separated, as the board writes them', () {
      expect(kcalReading(1640), '1,640');
      expect(kcalReading(2050), '2,050');
      expect(kcalReading(999), '999');
      expect(kcalReading(1000), '1,000');
      expect(kcalReading(1234567), '1,234,567');
      expect(kcalReading(0), '0');
      expect(kcalReading(null), '0');
    });

    // The tenth F-15 case: `/meals-dashboard` read the goal with `?? 0.0`, so
    // "no goal set" rendered as a goal of zero and every day read as over
    // budget. A zero target is not a target.
    test('no goal set is not a goal of zero', () {
      expect(kcalTargetLine(2050), 'of 2,050 kcal');
      expect(kcalTargetLine(null), 'kcal');
      expect(kcalTargetLine(0), 'kcal');
      expect(kcalTargetLine(-1), 'kcal');
    });
  });
}
