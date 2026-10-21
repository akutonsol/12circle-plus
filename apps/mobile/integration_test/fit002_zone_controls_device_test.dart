// FIT-002 · the Workout Zone's top-bar controls, measured on the device.
//
// Same reasoning as `fit017_rest_controls_device_test.dart`: the two claims
// that matter are physical. F-6 and F-6b were found by measuring the password
// toggle on `emulator-5554` at 19.8 × 20.2 dp *after* the source looked fine,
// and a host-VM harness can be wrong about its own constraints — the rest-timer
// harness measured 566 dp tall controls until it was corrected. So the naming
// and the 44 dp floor are re-measured here through the real embedder, at the
// device's own density.
//
// `ZoneAction` is a leaf. Nothing is signed in, read or written.
//
//   flutter test integration_test/fit002_zone_controls_device_test.dart \
//     -d emulator-5554 --dart-define-from-file=dart_defines/qa.json

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:circle_fitness/features/workout/presentation/widgets/zone_action.dart';

void _mark(String line) => print('FIT002-MARK $line');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('FIT-002 both Zone controls are named and reach 44 dp on device',
      (t) async {
    final handle = t.ensureSemantics();

    // The Zone's bar: a Row inside a Container inside a Column.
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(children: [
              ZoneAction(
                  icon: Icons.close,
                  label: 'End session',
                  color: Colors.red,
                  onTap: () {}),
              const SizedBox(width: 4),
              ZoneAction(
                  icon: Icons.pause_rounded,
                  label: 'Pause session',
                  color: Colors.purple,
                  onTap: () {}),
            ]),
          ),
        ]),
      ),
    ));
    await t.pump();

    _mark('DEVICE dpr=${t.view.devicePixelRatio} '
        'width=${t.binding.renderViews.first.size.width.toStringAsFixed(1)}dp');

    // FIT-002's wording for the control that was an unlabelled cross, and for
    // the one that did not exist.
    for (final entry in <(IconData, String)>[
      (Icons.close, 'End session'),
      (Icons.pause_rounded, 'Pause session'),
    ]) {
      final (icon, label) = entry;
      // `bySemanticsLabel` matches a semantics node, not a widget, so it cannot
      // be the `of:` of an ancestor search — find the target through its icon.
      expect(find.bySemanticsLabel(label), findsOneWidget);

      // Named AND pressable. A `Semantics` that excludes its child drops the
      // child's actions too, which produced a "Back" node a screen reader could
      // not activate on the intake flow. These do not exclude, but the
      // assertion is cheap and the failure mode is silent.
      final data =
          t.getSemantics(find.bySemanticsLabel(label)).getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(data.hasFlag(SemanticsFlag.isButton), isTrue);

      final size = t.getSize(find
          .ancestor(of: find.byIcon(icon), matching: find.byType(GestureDetector))
          .first);
      _mark('CONTROL "$label" '
          'target=${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)}dp');
      expect(size.width, greaterThanOrEqualTo(44.0));
      expect(size.height, greaterThanOrEqualTo(44.0));
    }

    _mark('PASS both Zone controls named from FIT-002, both >= 44dp');
    handle.dispose();
  });
}
