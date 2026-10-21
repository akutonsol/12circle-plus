// F-24 probe · does the session-complete dialog overflow at phone width?
//
// A widget test at 420 dp reported `A RenderFlex overflowed by 18 pixels on the
// right` from the three-stat row (Duration / Calories / Idle). That is NOT
// enough to call it a defect: widget tests render in Ahem, where every glyph is
// a full em square, so text measures wider than any real font. Reporting an
// Ahem overflow as a product bug would be a fabricated finding.
//
// So the question is settled here instead — on `emulator-5554`, at the device's
// own width and density, with the real font the app ships.
//
// The dialog is mounted directly. It takes an injected `submit`, so nothing is
// signed in, read or written.
//
//   flutter test integration_test/fit018_complete_dialog_device_test.dart \
//     -d emulator-5554 --dart-define-from-file=dart_defines/qa.json

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:circle_fitness/features/workout/presentation/active_workout_screen.dart';

void _mark(String line) => print('F24-MARK $line');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// The emulator is 411 dp wide. The design draws for 390, and 360 is the
  /// narrowest width in common use, so the dialog is checked at all three —
  /// otherwise this proves only that it fits one particular emulator.
  const widths = <double?>[null, 390.0, 360.0];

  for (final width in widths) {
  testWidgets('F-24 the complete dialog fits at ${width?.toInt() ?? 'device'} dp',
      (t) async {
    final overflows = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final text = details.exceptionAsString();
      if (text.contains('overflowed')) {
        overflows.add(text.split('\n').first);
      } else {
        previous?.call(details);
      }
    };
    addTearDown(() => FlutterError.onError = previous);

    if (width != null) {
      final view = t.view;
      await t.binding
          .setSurfaceSize(Size(width, view.physicalSize.height / view.devicePixelRatio));
      addTearDown(() => t.binding.setSurfaceSize(null));
    }

    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WorkoutCompleteDialog(
          // The worst realistic case for the row's width: a two-digit minute
          // duration, four-digit calories, and a non-zero idle time so the
          // third stat carries its longest value.
          title: 'Upper Body A',
          duration: '1:42:10',
          calories: 1250,
          idleSeconds: 605,
          onDone: () {},
          submit: ({required rating, required energy, required difficulty, required notes}) async =>
              FeedbackDelivery.delivered,
        ),
      ),
    ));
    await t.pump();

    final logicalWidth = t.binding.renderViews.first.size.width;
    _mark('SURFACE width=${logicalWidth.toStringAsFixed(1)}dp '
        'dpr=${t.view.devicePixelRatio}');

    // Measure the row the widget test complained about, rather than trusting
    // the absence of an exception.
    final statsRow = find
        .ancestor(of: find.text('Duration'), matching: find.byType(Row))
        .last;
    final box = t.renderObject<RenderFlex>(statsRow);
    _mark('STATS_ROW size=${box.size.width.toStringAsFixed(1)}dp '
        'constraints=${box.constraints.maxWidth.toStringAsFixed(1)}dp');

    _mark('OVERFLOWS count=${overflows.length}'
        '${overflows.isEmpty ? '' : ' :: ${overflows.join(" | ")}'}');

    expect(overflows, isEmpty,
        reason: 'The session-complete dialog paints an overflow stripe across '
            'itself on the device it ships on.');
  });
  }
}
