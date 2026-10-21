// FIT-003 · the "What you ate" rows — measured on the device.
//
// The host-VM tests prove the rules (16) and the render (8), and nine
// mutations kill them. Two things they cannot settle, both physical:
//
//  * the 44 dp `tap` floor at the device's real dpr (F-6/F-6b);
//  * whether a real meal name, its type and time, and a calorie figure still
//    fit one row at 360 dp with the real font. The host harness renders in
//    Ahem, where every glyph is a full em square and a width means nothing
//    (F-24).
//
// The rows are mounted with in-memory maps. Nothing is signed in, NO backend
// is touched and NO row is written, so this leaves no fixture behind.
//
//   flutter test integration_test/fit003_meal_rows_device_test.dart \
//     -d emulator-5554 --dart-define-from-file=dart_defines/qa.json

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:circle_fitness/features/nutrition/presentation/widgets/meal_row_tile.dart';

void _mark(String line) => print('FIT003-MARK $line');

// The board's three rows, with its own names and figures.
final _meals = [
  {
    'food_name': 'Greek yoghurt, berries, seeds',
    'meal_type': 'breakfast',
    'logged_at': DateTime(2026, 9, 8, 7, 20).toIso8601String(),
    'calories': 380,
  },
  {
    'food_name': 'Chicken, rice, greens',
    'meal_type': 'lunch',
    'logged_at': DateTime(2026, 9, 8, 12, 45).toIso8601String(),
    'calories': 640,
  },
  {
    'food_name': 'Protein shake, banana',
    'meal_type': 'protein_shake',
    'logged_at': DateTime(2026, 9, 8, 18, 10).toIso8601String(),
    'calories': 620,
  },
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF050510),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                children: [for (final m in _meals) MealRowTile(meal: m)]),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('the three rows, on the device', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);

    final dpr = tester.view.devicePixelRatio;
    _mark('viewport ${(tester.view.physicalSize.width / dpr).toStringAsFixed(1)}'
        ' dp @ dpr $dpr');

    final tiles = find.byType(MealRowTile);
    expect(tiles, findsNWidgets(3));

    for (var i = 0; i < 3; i++) {
      final d = tester.getSemantics(tiles.at(i)).getSemanticsData();
      final size = tester.getSize(tiles.at(i));
      _mark('row$i ${size.width.toStringAsFixed(1)}x'
          '${size.height.toStringAsFixed(1)} '
          'button=${d.hasFlag(SemanticsFlag.isButton)} "${d.label}"');
      expect(size.height, greaterThanOrEqualTo(44.0));
      // OD-23 — no destination is drawn and none exists.
      expect(d.hasFlag(SemanticsFlag.isButton), isFalse);
    }

    // The board's middle lines, which did not render before this change.
    expect(find.text('Breakfast · 07:20'), findsOneWidget);
    expect(find.text('Lunch · 12:45'), findsOneWidget);
    // OD-22 — the board writes "After training"; the schema has no such value
    // and nothing links a meal to a session.
    expect(find.text('Protein shake · 18:10'), findsOneWidget);
    expect(find.textContaining('After training'), findsNothing);

    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  testWidgets('the rows hold from 360 dp up, with the real font',
      (tester) async {
    final originalSize = tester.view.physicalSize;
    final dpr = tester.view.devicePixelRatio;
    addTearDown(() {
      tester.view.physicalSize = originalSize;
      tester.view.resetDevicePixelRatio();
    });

    for (final dp in const [360.0, 390.0, 411.4]) {
      tester.view.physicalSize = Size(dp * dpr, 844 * dpr);
      await pump(tester);
      expect(find.text('Greek yoghurt, berries, seeds'), findsOneWidget);
      final err = tester.takeException();
      _mark('$dp dp — three rows, exception=${err ?? 'none'}');
      expect(err, isNull);
    }
  });
}
