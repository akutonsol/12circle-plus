// FIT-016 · the session row's info control — measured on the device.
//
// The host-VM tests (test/unit/exercise_brief_test.dart,
// test/widget/workout_detail_exercise_brief_test.dart) prove the rules and the
// wiring, and six mutations kill them. Three things they cannot settle, all
// physical:
//
//  * the row's 44 dp `tap` floor, at the device's real dpr. F-6/F-6b are why
//    this is measured rather than read: the password toggle looked correct in
//    source and measured 19.8 x 20.2 dp;
//  * whether the row actually reaches the platform accessibility tree as a
//    button WITH a tap action. `excludeSemantics: true` drops a child's
//    ACTIONS along with its labels, and F-20 shipped a back button reading
//    `44x44 tap=false label="Back"` for exactly that reason;
//  * whether the sheet presents and dismisses on a real touch, with the real
//    font — the host harness renders in Ahem, where a width means nothing
//    (F-24).
//
// The screen is mounted with `selectedWorkoutProvider` overridden to an
// in-memory workout. Nothing is signed in, NO backend is touched and NO row is
// written, so this leaves no fixture behind — which also keeps it clear of
// F-21/OD-14: `/workout-detail` renders the assigned programme in production
// and is blocked for integrity claims, but this measures the widget's own
// geometry and semantics, not the authenticity of any assignment.
//
//   flutter test integration_test/fit016_exercise_brief_device_test.dart \
//     -d emulator-5554 --dart-define-from-file=dart_defines/qa.json

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:circle_fitness/features/workout/data/models/exercise_model.dart';
import 'package:circle_fitness/features/workout/data/models/workout_model.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:circle_fitness/features/workout/presentation/workout_detail_screen.dart';

void _mark(String line) => print('FIT016-MARK $line');

Exercise _ex(String id, String name,
        {String description = '', List<String> instructions = const []}) =>
    Exercise(
      id: id,
      name: name,
      category: 'Strength',
      muscleGroup: 'Legs',
      equipment: 'Barbell',
      difficulty: 'Intermediate',
      description: description,
      instructions: instructions,
    );

WorkoutExercise _we(Exercise e,
        {String? notes, int reps = 6, double? kg = 65, int? rest = 120}) =>
    WorkoutExercise(
      exercise: e,
      notes: notes,
      sets: List.generate(
        4,
        (i) => WorkoutSet(
            setNumber: i + 1, reps: reps, weightKg: kg, restSeconds: rest),
      ),
    );

final _workout = Workout(
  id: 'fit016-device',
  title: 'Lower body — strength',
  description: "Keep last week's loads.",
  estimatedDuration: 48,
  difficulty: 'Intermediate',
  category: 'Strength',
  coachName: 'Nadia',
  exercises: [
    // Row 1 has something behind it.
    _we(
      _ex('e1', 'Back squat',
          description: 'A knee-dominant pattern under load.',
          instructions: ['Set the bar on your back.', 'Descend under control.']),
      notes: 'Hold the depth before we add weight.',
    ),
    // Row 2 has nothing — no description, no instructions, no note. Equipment
    // and muscle group ARE set, which is the case that would restore the inert
    // control if metadata were allowed to count as content.
    _we(_ex('e2', 'Romanian deadlift'), reps: 8, kg: 62.5, rest: 90),
  ],
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [selectedWorkoutProvider.overrideWith((ref) => _workout)],
      child: const MaterialApp(home: WorkoutDetailScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('the session rows, on the device', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);

    final dpr = tester.view.devicePixelRatio;
    final width = tester.view.physicalSize.width / dpr;
    _mark('viewport ${width.toStringAsFixed(1)} dp @ dpr $dpr');

    const withContent = '1 Back squat 4 × 6 · 65 kg · rest 120 s';
    const without = '2 Romanian deadlift 4 × 8 · 62.5 kg · rest 90 s';

    // ── The row that opens something ────────────────────────────────────────
    final a = tester.getSemantics(find.bySemanticsLabel(withContent));
    final ad = a.getSemanticsData();
    final aSize = tester.getSize(find.bySemanticsLabel(withContent));
    _mark('row1 ${aSize.width.toStringAsFixed(1)}x${aSize.height.toStringAsFixed(1)} '
        'button=${ad.hasFlag(SemanticsFlag.isButton)} '
        'tap=${ad.hasAction(SemanticsAction.tap)} hint="${ad.hint}"');

    expect(ad.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(ad.hasAction(SemanticsAction.tap), isTrue,
        reason: 'F-20: a named button that cannot be activated is not a button');
    expect(ad.hint, 'Shows form and instructions');
    expect(aSize.height, greaterThanOrEqualTo(44.0),
        reason: 'the design\'s `tap` floor, measured not assumed');

    // ── The row that opens nothing claims nothing ───────────────────────────
    final b = tester.getSemantics(find.bySemanticsLabel(without));
    final bd = b.getSemanticsData();
    _mark('row2 button=${bd.hasFlag(SemanticsFlag.isButton)} '
        'tap=${bd.hasAction(SemanticsAction.tap)} hint="${bd.hint}"');
    expect(bd.hasFlag(SemanticsFlag.isButton), isFalse);
    expect(bd.hasAction(SemanticsAction.tap), isFalse);

    // Exactly one info icon on screen — row 1's.
    expect(find.byIcon(Icons.info_outline), findsOneWidget);

    // ── Present, read, dismiss — on a real touch ────────────────────────────
    expect(find.text('Done'), findsNothing);
    await tester.tap(find.bySemanticsLabel(withContent));
    await tester.pumpAndSettle();

    expect(find.text('Hold the depth before we add weight.'), findsOneWidget);
    expect(find.text('A knee-dominant pattern under load.'), findsOneWidget);
    expect(find.text('Set the bar on your back.'), findsOneWidget);
    expect(find.text('Descend under control.'), findsOneWidget);

    final done = find.text('Done');
    expect(done, findsOneWidget);

    final doneNode = find.bySemanticsLabel('Done');
    final doneBox = tester.getSize(doneNode);
    final doneData = tester.getSemantics(doneNode).getSemanticsData();
    _mark('sheet open; Done ${doneBox.width.toStringAsFixed(1)}x'
        '${doneBox.height.toStringAsFixed(1)} '
        'button=${doneData.hasFlag(SemanticsFlag.isButton)} '
        'tap=${doneData.hasAction(SemanticsAction.tap)}');
    expect(doneData.hasAction(SemanticsAction.tap), isTrue);
    expect(doneBox.height, greaterThanOrEqualTo(44.0));

    await tester.tap(done);
    await tester.pumpAndSettle();
    expect(find.text('Done'), findsNothing);
    _mark('sheet dismissed');

    // ── No overflow, at the device's real width and the real font ───────────
    expect(tester.takeException(), isNull);
    _mark('no exceptions; row1 width ${aSize.width.toStringAsFixed(1)} dp');

    handle.dispose();
  });

  // The design viewport is 390 dp and the device is 411.4. Neither says what
  // happens at 360, which is the narrowest width this product still supports —
  // and an exercise name plus a four-part prescription is the row most likely
  // to run out of it. Measured with the real font, for the F-24 reason.
  testWidgets('the row and the sheet hold from 360 dp up', (tester) async {
    final originalSize = tester.view.physicalSize;
    final dpr = tester.view.devicePixelRatio;
    addTearDown(() {
      tester.view.physicalSize = originalSize;
      tester.view.resetDevicePixelRatio();
    });

    for (final dp in const [360.0, 390.0, 411.4]) {
      tester.view.physicalSize = Size(dp * dpr, 844 * dpr);
      await pump(tester);

      await tester.tap(find.text('Back squat'));
      await tester.pumpAndSettle();
      expect(find.text('Set the bar on your back.'), findsOneWidget);

      final err = tester.takeException();
      _mark('$dp dp — sheet open, exception=${err ?? 'none'}');
      expect(err, isNull,
          reason: 'an overflow at $dp dp is a layout defect, not a harness one');

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
