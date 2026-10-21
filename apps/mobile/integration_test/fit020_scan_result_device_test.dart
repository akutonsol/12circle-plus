// FIT-020 · the AI scan result, measured on the device.
//
// Two questions the host VM cannot answer:
//
//  * does the result card's TITLE ROW fit a realistic food name at real
//    widths? It is a pre-existing `Row` with no `Expanded` on the name, and in
//    Ahem the anchor's own "Chicken, rice, greens" overflows it by 131 px. That
//    is the harness, not the product — F-24 is the recorded instance of
//    mistaking one for the other — so it is measured here with the real font.
//  * do FIT-020's three portion words reach the platform as pressable buttons
//    at 44 dp? `excludeSemantics: true` drops the child's ACTIONS along with
//    its labels, which shipped once and was caught only on device (F-9).
//
// `AiScanView` is seeded with a result, so no camera, upload or model call
// happens and no backend is touched.
//
//   flutter test integration_test/fit020_scan_result_device_test.dart \
//     -d emulator-5554 --dart-define-from-file=dart_defines/qa.json

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:circle_fitness/features/nutrition/presentation/widgets/ai_scan_view.dart';

void _mark(String line) => print('FIT020-MARK $line');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // The anchor's own row, and a longer one, at the design's width and below it.
  for (final width in <double>[411.4, 390, 360]) {
    testWidgets('FIT-020 the result card at ${width.toInt()} dp', (t) async {
      final handle = t.ensureSemantics();
      final overflows = <String>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (d) {
        if (d.exceptionAsString().contains('overflowed')) {
          overflows.add(d.exceptionAsString().split('\n').first);
        } else {
          previous?.call(d);
        }
      };
      addTearDown(() => FlutterError.onError = previous);

      final view = t.view;
      await t.binding.setSurfaceSize(
          Size(width, view.physicalSize.height / view.devicePixelRatio));
      addTearDown(() => t.binding.setSurfaceSize(null));

      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AiScanView(
            onAccept: (_) {},
            mealType: 'Lunch',
            onSearchInstead: () {},
            initialResult: const ScanResult(
              name: 'Chicken, rice, greens',
              calories: 640,
              protein: 45,
              carbs: 60,
              fat: 18,
              confidence: 88,
              items: [],
            ),
          ),
        ),
      ));
      await t.pump();

      _mark('SURFACE width=${t.binding.renderViews.first.size.width.toStringAsFixed(1)}dp '
          'dpr=${t.view.devicePixelRatio}');

      for (final w in ['Smaller', 'As shown', 'Larger']) {
        final d = t.getSemantics(find.bySemanticsLabel(w)).getSemanticsData();
        final size = t.getSize(find
            .ancestor(of: find.text(w), matching: find.byType(GestureDetector))
            .first);
        _mark('PORTION "$w" button=${d.hasFlag(SemanticsFlag.isButton)} '
            'tap=${d.hasAction(SemanticsAction.tap)} '
            'selected=${d.hasFlag(SemanticsFlag.isSelected)} '
            'target=${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)}dp');
        expect(d.hasFlag(SemanticsFlag.isButton), isTrue, reason: w);
        expect(d.hasAction(SemanticsAction.tap), isTrue, reason: w);
        expect(size.height, greaterThanOrEqualTo(44.0), reason: w);
      }

      expect(find.text('Save to lunch'), findsOneWidget);
      expect(find.text('Search instead'), findsOneWidget);

      _mark('OVERFLOWS count=${overflows.length}'
          '${overflows.isEmpty ? '' : ' :: ${overflows.join(" | ")}'}');
      expect(overflows, isEmpty,
          reason: 'the result card paints an overflow stripe at this width — '
              'the title row has no Expanded on the food name');

      _mark('PASS ${width.toInt()}dp');
      handle.dispose();
    });
  }
}
