import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/features/nutrition/presentation/widgets/meal_row_tile.dart';

/// FIT-003 · the "What you ate" row, mounted.
///
/// ── WHY THIS IS A WIDGET TEST AND NOT A SOURCE ASSERTION ───────────────────
/// It started as one, reading the committed source of the private `_MealCard`
/// and asserting `mealRowDetail(` appeared in it. A mutation killed that idea:
/// wrapping the render in `if (false)` left the CALL in the source, so the
/// assertion passed while the board's middle line was gone from the screen.
///
/// A source assertion can prove a value is computed. It cannot prove it is
/// rendered, and "computed" is not what the client sees. So the row was
/// extracted — the same move `PillTab` and `WeekRowTile` needed, for the same
/// reason — and this mounts it.
///
/// Three properties, each one a defect that shipped:
///
///   1. the row renders the meal's **type and time**. It did not, though
///      `nutrition_logs` has carried `meal_type` and `logged_at` since
///      migration 012 — the board's middle line was simply absent;
///   2. it does **not** announce itself a button. The manifest declares
///      `el: "button"`, the board draws no destination, and this app has no
///      edit or delete path for a logged meal — the old card's `more_horiz`
///      opened nothing. Recorded as **OD-23** rather than wired to an invented
///      destination, the same treatment OD-10 gave FIT-016's "More";
///   3. it carries no unnamed icon control, which is what `more_horiz` was.

Map<String, dynamic> _meal({
  String? name = 'Greek yoghurt, berries, seeds',
  String? type = 'breakfast',
  String? at = '2026-09-08T07:20:00Z',
  num? kcal = 380,
}) =>
    {
      'food_name': name,
      'meal_type': type,
      'logged_at': at,
      'calories': kcal,
    };

Future<void> _pump(WidgetTester tester, Map<String, dynamic> meal) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MealRowTile(meal: meal)),
    ));

void main() {
  testWidgets('the row renders the meal type and time', (tester) async {
    // Local time, so the row shows what the client's clock says.
    final at = DateTime(2026, 9, 8, 7, 20);
    await _pump(tester, _meal(at: at.toIso8601String()));

    expect(find.text('Greek yoghurt, berries, seeds'), findsOneWidget);
    expect(find.text('Breakfast · 07:20'), findsOneWidget,
        reason: "the board's middle line, absent before this change");
    // The board shows the number alone; `kcal` is carried by the header.
    expect(find.text('380'), findsOneWidget);
  });

  testWidgets('the spoken label restores the unit the row omits',
      (tester) async {
    final handle = tester.ensureSemantics();
    final at = DateTime(2026, 9, 8, 7, 20);
    await _pump(tester, _meal(at: at.toIso8601String()));

    final d = tester.getSemantics(find.byType(MealRowTile)).getSemanticsData();
    expect(d.label,
        'Greek yoghurt, berries, seeds Breakfast · 07:20 380 kcal');
    handle.dispose();
  });

  testWidgets('the row does not announce an affordance it does not have',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, _meal());

    final d = tester.getSemantics(find.byType(MealRowTile)).getSemanticsData();
    expect(d.hasFlag(SemanticsFlag.isButton), isFalse,
        reason: 'OD-23: no destination is drawn and none exists. A row that '
            'announces itself a button and answers nothing is the defect '
            'FIT-016 and FIT-014 both carried.');
    expect(d.hasAction(SemanticsAction.tap), isFalse);
    handle.dispose();
  });

  testWidgets('the inert more_horiz is gone', (tester) async {
    await _pump(tester, _meal());
    expect(find.byIcon(Icons.more_horiz), findsNothing,
        reason: 'an unnamed icon control that opened nothing — A-G8');
  });

  // The board's annotation, in as many words: "Macros read as three figures
  // against their targets on one rule, NOT three progress cards." A single
  // meal has no target to read against.
  testWidgets('no per-meal progress bars', (tester) async {
    await _pump(tester, _meal());
    expect(find.byType(LinearProgressIndicator), findsNothing);
    for (final w in const ['Protein', 'Carbs', 'Fats', 'Fat']) {
      expect(find.text(w), findsNothing);
    }
  });

  testWidgets('a nameless log is skipped rather than called "Meal"',
      (tester) async {
    await _pump(tester, _meal(name: null));
    expect(find.text('Meal'), findsNothing);
    expect(find.text('380'), findsNothing);
  });

  testWidgets('half a line is better than a fabricated one', (tester) async {
    await _pump(tester, _meal(type: null, at: null));
    expect(find.text('Greek yoghurt, berries, seeds'), findsOneWidget);
    expect(find.textContaining('·'), findsNothing,
        reason: 'a bare separator with nothing on either side');
  });

  testWidgets('the row meets the 44 dp tap floor even with one line',
      (tester) async {
    await _pump(tester, _meal(type: null, at: null));
    expect(tester.getSize(find.byType(MealRowTile)).height,
        greaterThanOrEqualTo(44.0));
  });
}
