import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/nutrition/presentation/widgets/ai_scan_view.dart';

/// FIT-020 · the AI scan result state, mounted.
///
/// `test/unit/scan_portion_test.dart` proves the rules. These assert the rules
/// are **acted on** — the distinction that mattered on `/profile`, where the
/// decision function was correct and the screen went on rendering the denial,
/// and the mutation survived until it was run.
void main() {
  // A short name on purpose. The result card's title row is a pre-existing
  // `Row` with no `Expanded` on the name, and in Ahem — where every glyph is a
  // full em square — a realistic title overflows it by 131 px. That is the
  // harness, not the product: F-24 is the recorded instance of taking an Ahem
  // overflow for a defect. Whether a real title fits at real widths is
  // measured on the device in
  // `integration_test/fit020_scan_result_device_test.dart`, with the anchor's
  // own "Chicken, rice, greens".
  const result = ScanResult(
    name: 'Rice',
    calories: 640,
    protein: 45,
    carbs: 60,
    fat: 18,
    confidence: 88,
    items: [],
  );

  Future<void> mount(
    WidgetTester t, {
    String mealType = 'Lunch',
    VoidCallback? onSearchInstead,
    void Function(ScanResult)? onAccept,
  }) async {
    await t.binding.setSurfaceSize(const Size(600, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AiScanView(
          onAccept: onAccept ?? (_) {},
          mealType: mealType,
          onSearchInstead: onSearchInstead,
          initialResult: result,
        ),
      ),
    ));
    await t.pump();
  }

  testWidgets('FIT-020 the three portion words are drawn', (t) async {
    await mount(t);
    for (final w in ['Smaller', 'As shown', 'Larger']) {
      expect(find.text(w), findsOneWidget);
    }
  });

  testWidgets('FIT-020 the save button names the meal, not the anchor\'s example',
      (t) async {
    await mount(t, mealType: 'Breakfast');
    expect(find.text('Save to breakfast'), findsOneWidget);
    // The design draws "Save to lunch" because lunch was selected. Hard-coding
    // it would label the button for one meal regardless of the chip.
    expect(find.text('Save to lunch'), findsNothing);
  });

  testWidgets('FIT-020 "As shown" starts selected and the others do not',
      (t) async {
    final handle = t.ensureSemantics();
    await mount(t);
    expect(
        t.getSemantics(find.bySemanticsLabel('As shown')).getSemanticsData()
            .hasFlag(SemanticsFlag.isSelected),
        isTrue,
        reason: 'the scan\'s own estimate is where the control starts');
    for (final w in ['Smaller', 'Larger']) {
      expect(
          t.getSemantics(find.bySemanticsLabel(w)).getSemanticsData()
              .hasFlag(SemanticsFlag.isSelected),
          isFalse,
          reason: '"$w" is a step, not a place');
    }
    handle.dispose();
  });

  testWidgets('FIT-020 Smaller moves the portion and As shown brings it back',
      (t) async {
    await mount(t);
    expect(find.text('1.00×'), findsOneWidget);

    await t.tap(find.text('Smaller'));
    await t.pump();
    expect(find.text('1.00×'), findsNothing,
        reason: 'the portion must actually change, not only the chip');
    expect(find.text('0.75×'), findsOneWidget);

    await t.tap(find.text('As shown'));
    await t.pump();
    expect(find.text('1.00×'), findsOneWidget);
  });

  testWidgets('FIT-020 the displayed macros scale with the portion', (t) async {
    // The point of the control: the numbers that reach the client's day and
    // their coach have to follow it.
    await mount(t);
    expect(find.text('640 kcal'), findsOneWidget);

    await t.tap(find.text('Larger'));
    await t.pump();
    expect(find.text('640 kcal'), findsNothing);
    expect(find.text('800 kcal'), findsOneWidget, reason: '640 × 1.25');
  });

  testWidgets('FIT-020 "Search instead" is offered, and only when wired',
      (t) async {
    var searched = 0;
    await mount(t, onSearchInstead: () => searched++);
    expect(find.text('Search instead'), findsOneWidget);

    final size = t.getSize(find
        .ancestor(of: find.text('Search instead'), matching: find.byType(GestureDetector))
        .first);
    expect(size.height, greaterThanOrEqualTo(44.0));

    await t.tap(find.text('Search instead'));
    expect(searched, 1);

    await mount(t);
    expect(find.text('Search instead'), findsNothing,
        reason: 'a control that does nothing must not be drawn');
  });

  testWidgets('FIT-020 each portion word is pressable from the tree', (t) async {
    // `excludeSemantics` drops the child's actions with its labels — F-9.
    final handle = t.ensureSemantics();
    await mount(t);
    for (final w in ['Smaller', 'As shown', 'Larger']) {
      final d = t.getSemantics(find.bySemanticsLabel(w)).getSemanticsData();
      expect(d.hasFlag(SemanticsFlag.isButton), isTrue, reason: w);
      expect(d.hasAction(SemanticsAction.tap), isTrue,
          reason: '"$w" announces as a button it must be able to press');
    }
    handle.dispose();
  });

  testWidgets('FIT-020 accepting hands back the SCALED result', (t) async {
    ScanResult? accepted;
    await mount(t, mealType: 'Lunch', onAccept: (r) => accepted = r);

    await t.tap(find.text('Larger'));
    await t.pump();
    await t.tap(find.text('Save to lunch'));
    await t.pump();

    expect(accepted, isNotNull);
    expect(accepted!.calories, closeTo(800, 0.001),
        reason: 'logging the unscaled value would record a meal the client '
            'said they did not eat');
  });
}
