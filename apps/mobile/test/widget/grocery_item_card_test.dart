import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/features/ai_nutrition/presentation/widgets/grocery_item_card.dart';

/// FIT-095 · a grocery row is a checkbox.
///
/// `test/unit/grocery_list_test.dart` pins what the rules SAY. This pins what
/// the row DOES — the part a rule cannot assert:
///
///   * the board marks every item `role="checkbox"`. The row shipped with no
///     `Semantics` at all, so a reader announced the item's name and nothing
///     about whether it was bought;
///   * the tap target was the row's padding, about 34 dp, under the floor;
///   * ticks were keyed by list INDEX, so rebuilding the list moved them onto
///     different groceries.
void main() {
  Future<void> pump(WidgetTester tester, List<String> items,
          {String category = 'Produce'}) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GroceryItemCard(category: category, items: items),
          ),
        ),
      ));

  testWidgets('a row announces a checkbox, its state, and a usable tap',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, ['Spinach, 2 bags', 'Bananas, 7']);

    final row = find.bySemanticsLabel('Spinach, 2 bags');
    var data = tester.getSemantics(row).getSemanticsData();

    expect(data.hasFlag(SemanticsFlag.hasCheckedState), isTrue,
        reason: 'the board says role="checkbox"; without the state flag a '
            'reader cannot announce checked or unchecked at all');
    expect(data.hasFlag(SemanticsFlag.isChecked), isFalse);
    expect(data.hasAction(SemanticsAction.tap), isTrue,
        reason: '`excludeSemantics` drops the child\'s ACTIONS with its '
            'labels — the tap has to be re-declared on the Semantics or the '
            'row announces a checkbox a reader cannot operate (F-20)');
    expect(data.hint, 'Mark as bought');

    await tester.tap(row);
    await tester.pump();

    data = tester.getSemantics(row).getSemanticsData();
    expect(data.hasFlag(SemanticsFlag.isChecked), isTrue);
    expect(data.hint, 'Mark as not bought');

    handle.dispose();
  });

  testWidgets('the row clears the 44 dp floor', (tester) async {
    await pump(tester, ['Olive oil']);
    // The tappable's own box, not the text's.
    final size = tester.getSize(find.ancestor(
      of: find.text('Olive oil'),
      matching: find.byType(GestureDetector),
    ));
    expect(size.height, greaterThanOrEqualTo(44.0),
        reason: 'the shipped row was ~34 dp: a 22 dp circle with 6 dp of '
            'padding either side');
  });

  testWidgets('the header counts what is checked', (tester) async {
    await pump(tester, ['Eggs, 18', 'Oats, 1 kg', 'Quinoa, 500 g']);
    expect(find.text('0/3'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Oats, 1 kg'));
    await tester.pump();
    expect(find.text('1/3'), findsOneWidget);
  });

  // The defect that matters. This card carries no key in the shipped tree, so
  // a rebuild reuses this State BY POSITION. With ticks held as indices, a
  // tick on the first item stayed on whatever became first.
  testWidgets('a tick does not migrate to a different grocery on rebuild',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, ['Spinach, 2 bags', 'Bananas, 7']);

    await tester.tap(find.bySemanticsLabel('Spinach, 2 bags'));
    await tester.pump();
    expect(
        tester
            .getSemantics(find.bySemanticsLabel('Spinach, 2 bags'))
            .getSemanticsData()
            .hasFlag(SemanticsFlag.isChecked),
        isTrue);

    // "Rebuild the list" — same position, entirely different groceries.
    await pump(tester, ['Kale, 1 bag', 'Salmon fillets, 4']);
    await tester.pump();

    for (final item in ['Kale, 1 bag', 'Salmon fillets, 4']) {
      expect(
        tester
            .getSemantics(find.bySemanticsLabel(item))
            .getSemanticsData()
            .hasFlag(SemanticsFlag.isChecked),
        isFalse,
        reason: '$item was never ticked. Keyed by index, the tick that was on '
            'Spinach would now be sitting on it.',
      );
    }
    expect(find.text('0/2'), findsOneWidget);

    handle.dispose();
  });
}
