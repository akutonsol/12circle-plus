// FIT-002 · "Adjust weight or reps" — the fifth declared control.
//
// It was recorded ABSENT although the control exists, because its visible label
// read "Edit". Overriding the accessible name with the design's phrase would
// have broken WCAG 2.5.3 (an accessible name must contain the visible label),
// so the VISIBLE label is what changed and the name follows it.
//
// Changing it is a layout decision, and this probe is what settled it. Measured
// on `emulator-5554` at 390 dp — the design's own viewport:
//
//   before   row 81.0 dp   control 54.8 x 13.0 dp   label "Edit" 18.8 dp wide
//   after    row 108.0 dp  control 140.8 x 44.0 dp  label 104.8 dp wide
//
// The control sits under every completed set, so the +27 dp multiplies: a
// 20-set workout scrolls ~540 dp further. That cost is accepted and recorded
// rather than hidden — the alternative was a 13 dp tap target, under a third of
// the floor F-6 was raised about, on one of the most-used screens in the app.
// Part of the height was given back by dropping the affordance's bottom
// padding.
//
//   flutter test integration_test/fit002_edit_affordance_device_test.dart \
//     -d emulator-5554 --dart-define-from-file=dart_defines/qa.json

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:circle_fitness/features/workout/presentation/widgets/set_tracker_row.dart';

void _mark(String line) => print('FIT002E-MARK $line');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('FIT-002 the correction control carries the design\'s label and '
      'clears the target floor', (t) async {
    final handle = t.ensureSemantics();
    await t.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));

    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(mainAxisSize: MainAxisSize.min, children: [
          SetTrackerRow(
            setNumber: 1,
            targetReps: 10,
            targetWeight: 60,
            completed: true,
            savedWeightKg: 60,
            savedReps: 10,
            savedRpe: 8,
            onCompleted: (_, __, ___, ____) {},
            onEditCompleted: () {},
          ),
        ]),
      ),
    ));
    await t.pump();

    final row = t.getSize(find.byType(SetTrackerRow));
    _mark('ROW height=${row.height.toStringAsFixed(1)}dp width=${row.width.toStringAsFixed(1)}dp');

    // FIT-002's own wording, drawn — not announced over a different word.
    const label = 'Adjust weight or reps';
    expect(find.text(label), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
    _mark('LABEL drawn="$label" '
        'textWidth=${t.getSize(find.text(label)).width.toStringAsFixed(1)}dp');

    final b = t.getSize(find.byType(TextButton).first);
    _mark('CONTROL size=${b.width.toStringAsFixed(1)}x${b.height.toStringAsFixed(1)}dp');
    expect(b.height, greaterThanOrEqualTo(44.0),
        reason: 'measured at 13.0 dp before this change');

    // Named AND pressable AND announced as a button. The accessible name comes
    // from the drawn text, so it contains the visible label by construction.
    final data = t.getSemantics(find.bySemanticsLabel(label)).getSemanticsData();
    _mark('SEMANTICS button=${data.hasFlag(SemanticsFlag.isButton)} '
        'tap=${data.hasAction(SemanticsAction.tap)}');
    expect(data.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);

    // The label must not wrap or clip at the design's own viewport.
    expect(t.getSize(find.text(label)).width, lessThan(390 - 46 - 40),
        reason: 'the phrase has to fit beside its icon inside the row');

    _mark('PASS FIT-002 5/5');
    handle.dispose();
  });
}
