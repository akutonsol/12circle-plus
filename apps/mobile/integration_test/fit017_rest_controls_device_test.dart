// FIT-017 · the rest controls, measured on the device itself.
//
// WHY A SECOND COPY OF ASSERTIONS THE WIDGET TEST ALREADY MAKES
// -------------------------------------------------------------
// `test/widget/rest_timer_controls_test.dart` runs on the host VM at a fixed
// 800×600 logical surface with the test font. The two claims that matter here
// are physical ones — "a screen reader announces the design's wording" and
// "the target clears 44 dp" — and neither is settled by a host-VM measurement:
//
//  * F-6 and F-6b were found by measuring the password toggle on
//    `emulator-5554` (19.8 × 20.2 dp at 2.625 px/dp) *after* it looked fine in
//    source. The device is where that class of defect becomes visible.
//  * A host-VM harness can also be wrong about its own constraints. The first
//    version of the widget test measured 566 dp tall controls because `Align`
//    hands down bounded constraints where the real screen's `Column` does not,
//    so deleting the 44 dp constraint left it green. It is recorded in that
//    file. This test is laid out at the device's real width and density.
//
// So this runs the same two claims through the real embedder: real text
// metrics, real device pixel ratio, and the real semantics tree as Flutter
// hands it to the platform — rather than `uiautomator`, which returns an empty
// tree unless an accessibility service is enabled on the emulator.
//
// IT TOUCHES NO BACKEND. `RestTimerWidget` is a leaf: a wall-clock end time in,
// a countdown out. Nothing is signed in, nothing is read, nothing is written.
//
//   flutter test integration_test/fit017_rest_controls_device_test.dart \
//     -d emulator-5554 --dart-define-from-file=dart_defines/qa.json
//
// The FIT017-MARK lines carry the measurements into the evidence ledger.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:circle_fitness/features/workout/presentation/widgets/rest_timer_widget.dart';

void _mark(String line) => print('FIT017-MARK $line');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('FIT-017 both rest controls are named and reach 44 dp on device',
      (t) async {
    final handle = t.ensureSemantics();

    // Laid out the way `/active-workout` lays it out: in a Column, at the
    // device's own width, at the device's own density.
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(mainAxisSize: MainAxisSize.min, children: [
          RestTimerWidget(
            endTime: DateTime.now().add(const Duration(seconds: 90)),
            totalSeconds: 120,
            onExtend: () {},
            onComplete: () {},
          ),
        ]),
      ),
    ));
    await t.pump();

    final view = t.view;
    _mark('DEVICE dpr=${view.devicePixelRatio} '
        'physical=${view.physicalSize.width.toInt()}x${view.physicalSize.height.toInt()}');

    // FIT-017's two declared interactions, verbatim.
    for (final entry in const {
      '+30s': 'Add 30 seconds',
      'SKIP': 'Skip rest, start set',
    }.entries) {
      final drawn = entry.key;
      final announced = entry.value;

      expect(find.bySemanticsLabel(announced), findsOneWidget,
          reason: '"$announced" is FIT-017\'s own wording for this control');

      // A node announced as a button that carries no tap action is a button a
      // screen reader cannot press. `excludeSemantics: true` drops the child's
      // ACTIONS along with its labels — found on the intake back button, and
      // these two had it as well.
      final data = t.getSemantics(find.bySemanticsLabel(announced)).getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isTrue,
          reason: '"$announced" announces as a button but cannot be activated');

      final target = find
          .ancestor(of: find.text(drawn), matching: find.byType(GestureDetector))
          .first;
      final size = t.getSize(target);
      _mark('CONTROL drawn="$drawn" announced="$announced" '
          'target=${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)}dp');

      expect(size.width, greaterThanOrEqualTo(44.0));
      expect(size.height, greaterThanOrEqualTo(44.0));
    }

    // The abbreviation must not be what gets announced — that is the whole
    // reason the Semantics wrapper excludes its child.
    expect(find.bySemanticsLabel('+30s'), findsNothing);
    expect(find.bySemanticsLabel('SKIP'), findsNothing);
    _mark('PASS both controls named in the design\'s wording, both >= 44dp');

    handle.dispose();
  });
}
