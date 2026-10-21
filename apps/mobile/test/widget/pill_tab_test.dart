import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/nutrition/presentation/widgets/pill_tab.dart';

/// FIT-019 · the Log Meal sheet's mode selector.
///
/// ── THE DEFECT ─────────────────────────────────────────────────────────────
/// Three pills that are ONE exclusive choice, announced as neither buttons nor
/// selected. A screen reader read "Search Scan Barcode" with no way to tell
/// which mode was active — on the sheet where a client logs everything they
/// eat. Identical to the defect found on the weekly check-in's pickers, in a
/// different feature, which is why the widget was extracted rather than fixed
/// in place three times.
void main() {
  Widget host(Widget child) => MaterialApp(
        home: Scaffold(
          body: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [Expanded(child: child)]),
          ]),
        ),
      );

  testWidgets('FIT-019 a pill announces its label, role and selection',
      (t) async {
    final handle = t.ensureSemantics();
    await t.pumpWidget(host(PillTab('Search', true, () {})));

    final d = t.getSemantics(find.bySemanticsLabel('Search')).getSemanticsData();
    expect(d.label, 'Search');
    expect(d.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(d.hasFlag(SemanticsFlag.isSelected), isTrue);
    expect(d.hasFlag(SemanticsFlag.isInMutuallyExclusiveGroup), isTrue,
        reason: 'the three pills are one choice, not three switches');
    handle.dispose();
  });

  testWidgets('FIT-019 an inactive pill is not reported as selected',
      (t) async {
    final handle = t.ensureSemantics();
    await t.pumpWidget(host(PillTab('Scan', false, () {})));

    expect(
        t.getSemantics(find.bySemanticsLabel('Scan')).getSemanticsData()
            .hasFlag(SemanticsFlag.isSelected),
        isFalse);
    handle.dispose();
  });

  testWidgets('FIT-019 a pill is pressable from the accessibility tree',
      (t) async {
    // `excludeSemantics: true` drops the child's ACTIONS along with its
    // labels — the defect F-9's device probe found on the intake back button.
    // Assert the action, not just the name.
    final handle = t.ensureSemantics();
    var taps = 0;
    await t.pumpWidget(host(PillTab('Search', false, () => taps++)));

    expect(
        t.getSemantics(find.bySemanticsLabel('Search')).getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue);
    await t.tap(find.text('Search'));
    expect(taps, 1);
    handle.dispose();
  });

  testWidgets('FIT-019 the pill clears the 44 dp target floor', (t) async {
    await t.pumpWidget(host(PillTab('Search', false, () {})));
    final size = t.getSize(find.byType(GestureDetector).first);
    expect(size.height, greaterThanOrEqualTo(44.0));
  });

  testWidgets('FIT-019 the label is not doubled in the announcement',
      (t) async {
    // The Semantics carries the name AND the child draws it. Without
    // `excludeSemantics` a screen reader says it twice — a mistake this
    // repository has already made once, in auth_design.dart.
    final handle = t.ensureSemantics();
    await t.pumpWidget(host(PillTab('Scan', true, () {})));

    expect(find.bySemanticsLabel('Scan'), findsOneWidget);
    expect(find.bySemanticsLabel('Scan\nScan'), findsNothing);
    handle.dispose();
  });
}
