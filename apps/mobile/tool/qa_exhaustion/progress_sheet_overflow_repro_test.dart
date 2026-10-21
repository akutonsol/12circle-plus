// QA-ONLY REPRODUCTION — QAX-UI-01 / QAX-UI-02. Lives outside test/ on purpose:
// it FAILS today (it reproduces open defects) and must not redden the default
// suite until the layout owners fix them. Run explicitly:
//
//   flutter test tool/qa_exhaustion/progress_sheet_overflow_repro_test.dart
//
// QAX-UI-01 (P3): the weight sheet's date + kg/lbs row (progress_screen.dart,
//   "Date + unit toggle") overflows horizontally on every phone width <= 414:
//   360 -> 55px, 375 -> 40px, 390 -> 25px, 393 -> 22px, 414 -> 0.5px. In release
//   builds the unit toggle is clipped.
// QAX-UI-02 (P4): each weight-ruler tick column overflows 2px vertically at
//   every size.
//
// When both are fixed this file passes; then move it into test/widget/.
import 'package:circle_fitness/features/progress/presentation/progress_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final w in [360.0, 375.0, 390.0, 393.0, 414.0, 430.0]) {
    testWidgets('weight sheet lays out without overflow at ${w.toInt()}x844',
        (tester) async {
      tester.view.physicalSize = Size(w, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showModalBottomSheet(
                context: ctx,
                isScrollControlled: true,
                builder: (_) => const LogWeightSheet(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // A RenderFlex overflow is reported through FlutterError and fails the test.
    });
  }
}
