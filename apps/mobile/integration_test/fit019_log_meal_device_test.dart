// FIT-019 · the Log Meal sheet's mode selector, measured on the device.
//
// The claims are physical: the pills really do reach the platform as one
// exclusive choice with a selection, they are really pressable from the
// accessibility tree, and the targets really clear 44 dp at the device's own
// density. `excludeSemantics: true` drops the child's ACTIONS along with its
// labels — a defect that shipped once and was caught only by reading the real
// tree (F-9).
//
// `PillTab` is a leaf. Nothing is signed in and no backend is touched.
//
//   flutter test integration_test/fit019_log_meal_device_test.dart \
//     -d emulator-5554 --dart-define-from-file=dart_defines/qa.json

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:circle_fitness/features/nutrition/presentation/widgets/pill_tab.dart';

void _mark(String line) => print('FIT019-MARK $line');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('FIT-019 the sheet\'s three pills on device', (t) async {
    final handle = t.ensureSemantics();

    // The sheet's own layout: a 54 dp pill row, three Expanded children.
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            height: 54,
            child: Row(children: [
              Expanded(child: PillTab('Search', true, () {})),
              Expanded(child: PillTab('Scan', false, () {})),
              Expanded(child: PillTab('Barcode', false, () {})),
            ]),
          ),
        ]),
      ),
    ));
    await t.pump();

    _mark('DEVICE dpr=${t.view.devicePixelRatio} '
        'width=${t.binding.renderViews.first.size.width.toStringAsFixed(1)}dp');

    for (final entry in <(String, bool)>[
      ('Search', true),
      ('Scan', false),
      ('Barcode', false),
    ]) {
      final (label, selected) = entry;
      final d = t.getSemantics(find.bySemanticsLabel(label)).getSemanticsData();
      final size = t.getSize(find
          .ancestor(of: find.text(label), matching: find.byType(GestureDetector))
          .first);
      _mark('PILL "$label" selected=${d.hasFlag(SemanticsFlag.isSelected)} '
          'button=${d.hasFlag(SemanticsFlag.isButton)} '
          'exclusive=${d.hasFlag(SemanticsFlag.isInMutuallyExclusiveGroup)} '
          'tap=${d.hasAction(SemanticsAction.tap)} '
          'target=${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)}dp');

      expect(d.hasFlag(SemanticsFlag.isSelected), selected, reason: label);
      expect(d.hasFlag(SemanticsFlag.isButton), isTrue, reason: label);
      expect(d.hasFlag(SemanticsFlag.isInMutuallyExclusiveGroup), isTrue,
          reason: label);
      expect(d.hasAction(SemanticsAction.tap), isTrue,
          reason: '$label announces as a button it must be able to press');
      expect(size.height, greaterThanOrEqualTo(44.0), reason: label);
    }

    _mark('PASS three pills, one choice, all pressable');
    handle.dispose();
  });
}
