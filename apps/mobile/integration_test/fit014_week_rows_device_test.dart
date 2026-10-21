// FIT-014 · the "This week" rows — measured on the device.
//
// The host-VM tests prove the rules and the wiring, and nine mutations kill
// them. Three things they cannot settle, all physical:
//
//  * the 44 dp `tap` floor the board's `.row` declares (`min-height: 44px`),
//    at the device's real dpr. F-6/F-6b are why this is measured rather than
//    read from source;
//  * whether a row reaches the platform accessibility tree as a button WITH a
//    tap action — `excludeSemantics: true` drops a child's actions along with
//    its labels, which is how F-20 shipped `44x44 tap=false label="Back"`;
//  * whether a long title plus a spelled-out day (`Saturday · 44 min`) still
//    fits beside its chip at 360 dp, with the real font. The host harness
//    renders in Ahem, where every glyph is a full em square and a width means
//    nothing (F-24).
//
// The rows are mounted directly with an in-memory workout list. Nothing is
// signed in, NO backend is touched and NO row is written, so this leaves no
// fixture behind — and it stays clear of F-21/OD-14, which blocks integrity
// claims about the assigned programme but not the geometry of a widget.
//
//   flutter test integration_test/fit014_week_rows_device_test.dart \
//     -d emulator-5554 --dart-define-from-file=dart_defines/qa.json

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import 'package:circle_fitness/features/workout/data/models/exercise_model.dart';
import 'package:circle_fitness/features/workout/data/models/workout_model.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:circle_fitness/features/workout/presentation/widgets/week_row_tile.dart';

void _mark(String line) => print('FIT014-MARK $line');

Workout _w({
  required String title,
  bool completed = false,
  DateTime? on,
  int minutes = 44,
}) =>
    Workout(
      id: title,
      title: title,
      description: '',
      estimatedDuration: minutes,
      difficulty: 'Intermediate',
      category: 'Strength',
      isCompleted: completed,
      scheduledDate: on,
      exercises: [
        WorkoutExercise(
          exercise: Exercise(
            id: 'e1',
            name: 'Back squat',
            category: 'Strength',
            muscleGroup: 'Legs',
            equipment: 'Barbell',
            difficulty: 'Intermediate',
            description: '',
            instructions: const [],
          ),
          sets: const [WorkoutSet(setNumber: 1, reps: 6)],
        ),
      ],
    );

// The board's own four rows, with its own titles and durations.
List<Workout> _rows() {
  final now = DateTime.now();
  DateTime onWeekday(int weekday) {
    final delta = weekday - now.weekday;
    return DateTime(now.year, now.month, now.day).add(Duration(days: delta));
  }

  return [
    _w(title: 'Upper body — push', completed: true, on: onWeekday(1), minutes: 44),
    _w(title: 'Lower body — strength', on: now, minutes: 48),
    _w(title: 'Conditioning', on: onWeekday(4), minutes: 30),
    _w(title: 'Upper body — pull', on: onWeekday(6), minutes: 44),
  ];
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> pump(WidgetTester tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/train',
      routes: [
        GoRoute(
          path: '/train',
          builder: (_, __) => Scaffold(
            body: ListView(
                children: [for (final w in _rows()) WeekRowTile(workout: w)]),
          ),
        ),
        GoRoute(
          path: '/workout-detail',
          builder: (_, __) => const Scaffold(body: Text('DETAIL')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('every row is an activatable button, at the tap floor',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);

    final dpr = tester.view.devicePixelRatio;
    _mark('viewport ${(tester.view.physicalSize.width / dpr).toStringAsFixed(1)}'
        ' dp @ dpr $dpr');

    final tiles = find.byType(WeekRowTile);
    expect(tiles, findsNWidgets(4));

    for (var i = 0; i < 4; i++) {
      final tile = tiles.at(i);
      final d = tester.getSemantics(tile).getSemanticsData();
      final size = tester.getSize(tile);
      _mark('row$i ${size.width.toStringAsFixed(1)}x'
          '${size.height.toStringAsFixed(1)} '
          'button=${d.hasFlag(SemanticsFlag.isButton)} '
          'tap=${d.hasAction(SemanticsAction.tap)} label="${d.label}"');

      expect(d.hasFlag(SemanticsFlag.isButton), isTrue);
      expect(d.hasAction(SemanticsAction.tap), isTrue,
          reason: 'the board draws <button class="tap row">');
      expect(size.height, greaterThanOrEqualTo(44.0),
          reason: '`.row { min-height: 44px }`, measured not assumed');
    }

    // The chips, as the stylesheet renders them.
    expect(find.text('DONE'), findsOneWidget);
    expect(find.text('Now'), findsOneWidget); // `.pill` — no text-transform
    expect(find.text('NOW'), findsNothing);

    handle.dispose();
  });

  testWidgets('a tap selects that workout and opens the detail route',
      (tester) async {
    final container = await pump(tester);
    expect(container.read(selectedWorkoutProvider), isNull);

    // The fourth row — a test that tapped the first would pass while the
    // screen always selected the same session, which is F-20's defect.
    await tester.tap(find.text('Upper body — pull'));
    await tester.pumpAndSettle();

    _mark('selected="${container.read(selectedWorkoutProvider)?.title}"');
    expect(find.text('DETAIL'), findsOneWidget);
    expect(container.read(selectedWorkoutProvider)?.title, 'Upper body — pull');
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

      expect(find.text('Saturday · 44 min'), findsOneWidget);
      final err = tester.takeException();
      _mark('$dp dp — four rows, exception=${err ?? 'none'}');
      expect(err, isNull,
          reason: 'an overflow at $dp dp is a layout defect, not a harness one');
    }
  });
}
