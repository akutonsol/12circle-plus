// WKT-110 — the Workout Zone set row renders a completed set as a record.
//
// The state layer already refuses edits to a completed set
// (test/unit/workout_set_immutability_test.dart); these tests cover the other
// half of the fix: the row must not *look* editable when it isn't, and its
// completion check must not be a toggle.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/workout/presentation/widgets/set_tracker_row.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: Material(child: child)),
    );

/// Mounts the row in the shape the FIT-002 group asserts against. The 420 dp
/// width is the phone the design draws for; the row is laid out in an
/// unbounded-height Column on `/active-workout`, so the target measurement
/// means something.
Future<void> pumpRow(WidgetTester t, {required bool completed}) async {
  await t.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(_host(Column(mainAxisSize: MainAxisSize.min, children: [
    SetTrackerRow(
      setNumber: 1,
      targetReps: 10,
      targetWeight: 60,
      completed: completed,
      savedWeightKg: completed ? 60 : null,
      savedReps: completed ? 10 : null,
      onCompleted: (_, __, ___, ____) {},
    ),
  ])));
  await t.pump();
}

void main() {
  // The row runs a looping "notes" pulse animation, so tests pump frames
  // explicitly rather than settling (which would never finish).
  group('WKT-110 an incomplete set offers editable fields', () {
    testWidgets('weight, reps and RPE are text inputs', (tester) async {
      await tester.pumpWidget(_host(SetTrackerRow(
        setNumber: 1,
        targetReps: 10,
        targetWeight: 60,
        completed: false,
        onCompleted: (_, __, ___, ____) {},
      )));
      await tester.pump();

      expect(find.byType(TextField), findsNWidgets(3));
      expect(find.text('Adjust weight or reps'), findsNothing);
    });

    testWidgets('tapping the check reports the entered values', (tester) async {
      int? reps;
      double? weightKg;
      await tester.pumpWidget(_host(SetTrackerRow(
        setNumber: 1,
        targetReps: 10,
        targetWeight: 60,
        completed: false,
        unit: 'kg',
        onCompleted: (r, w, _, __) {
          reps = r;
          weightKg = w;
        },
      )));
      await tester.pump();

      await tester.enterText(find.byType(TextField).at(0), '90');
      await tester.enterText(find.byType(TextField).at(1), '8');
      await tester.tap(find.byIcon(Icons.check));
      await tester.pump();

      expect(reps, 8);
      expect(weightKg, 90);
    });
  });

  group('WKT-110 a completed set is shown, not offered for editing', () {
    testWidgets('weight, reps and RPE are read-only values', (tester) async {
      await tester.pumpWidget(_host(SetTrackerRow(
        setNumber: 1,
        targetReps: 10,
        targetWeight: 60,
        completed: true,
        unit: 'lb',
        savedWeightKg: 90.718474, // 200 lb
        savedReps: 10,
        savedRpe: 5,
        onCompleted: (_, __, ___, ____) {},
      )));
      await tester.pump();

      expect(find.byType(TextField), findsNothing,
          reason: 'a recorded set must not present editable inputs');
      expect(find.text('200'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('tapping the check cannot deselect it', (tester) async {
      var completions = 0;
      await tester.pumpWidget(_host(SetTrackerRow(
        setNumber: 1,
        targetReps: 10,
        targetWeight: 60,
        completed: true,
        savedWeightKg: 90,
        savedReps: 10,
        onCompleted: (_, __, ___, ____) => completions++,
      )));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.check));
      await tester.pump();

      expect(completions, 0,
          reason: 'completion is one-way; the check is not a toggle');
    });

    testWidgets('the correction affordance is the only way in, and is opt-in',
        (tester) async {
      var edits = 0;
      await tester.pumpWidget(_host(SetTrackerRow(
        setNumber: 1,
        targetReps: 10,
        targetWeight: 60,
        completed: true,
        savedWeightKg: 90,
        savedReps: 10,
        onCompleted: (_, __, ___, ____) {},
        onEditCompleted: () => edits++,
      )));
      await tester.pump();

      expect(find.text('Adjust weight or reps'), findsOneWidget);
      await tester.tap(find.text('Adjust weight or reps'));
      await tester.pump();

      expect(edits, 1);
      expect(find.byType(TextField), findsNothing,
          reason: 'the correction affordance opens the correction flow; it does '
              'not unlock the row');
    });

    testWidgets('no correction action is shown when it is unavailable',
        (tester) async {
      await tester.pumpWidget(_host(SetTrackerRow(
        setNumber: 1,
        targetReps: 10,
        targetWeight: 60,
        completed: true,
        savedWeightKg: 90,
        savedReps: 10,
        onCompleted: (_, __, ___, ____) {},
      )));
      await tester.pump();

      expect(find.text('Adjust weight or reps'), findsNothing);
    });

    testWidgets('a note stays editable and re-emits the recorded numbers',
        (tester) async {
      int? reps;
      double? weightKg;
      String? notes;
      await tester.pumpWidget(_host(SetTrackerRow(
        setNumber: 1,
        targetReps: 10,
        targetWeight: 60,
        completed: true,
        unit: 'kg',
        savedWeightKg: 90,
        savedReps: 10,
        savedNotes: 'solid',
        onCompleted: (_, __, ___, ____) {},
        onChanged: (r, w, _, n) {
          reps = r;
          weightKg = w;
          notes = n;
        },
      )));
      await tester.pump();

      // The note field is the one input a completed row still shows.
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'felt heavier');
      await tester.pump(const Duration(milliseconds: 700)); // debounce

      expect(notes, 'felt heavier');
      expect(reps, 10, reason: 'the recorded reps travel back unchanged');
      expect(weightKg, 90, reason: 'the recorded weight travels back unchanged');
    });
  });

  group('FIT-002 the completion control is named "Log set"', () {
    // The most-used control on "the most focus-critical screen in the app" was
    // an unlabelled 32 dp check: a screen reader announced nothing, and the
    // target was under the 44 dp floor F-6 was raised about. FIT-002 supplies
    // the wording, so none of it is invented.

    testWidgets('an incomplete set announces it as an enabled button', (t) async {
      final handle = t.ensureSemantics();
      await pumpRow(t, completed: false);

      final node = t.getSemantics(find.bySemanticsLabel('Log set'));
      expect(node.label, 'Log set');
      expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
      expect(node.hasFlag(SemanticsFlag.isEnabled), isTrue);
      handle.dispose();
    });

    testWidgets('a completed set announces the SAME control, disabled', (t) async {
      // Completion is one-way. A second label ("Set logged") would be product
      // copy the design does not supply; `enabled: false` is the fact, and it
      // is what a screen reader needs in order to say the right thing.
      final handle = t.ensureSemantics();
      await pumpRow(t, completed: true);

      final node = t.getSemantics(find.bySemanticsLabel('Log set'));
      expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
      expect(node.hasFlag(SemanticsFlag.isEnabled), isFalse,
          reason: 'a logged set cannot be logged again — say so rather than '
              'offering a control that silently does nothing');
      handle.dispose();
    });

    testWidgets('the target clears 44 dp while the check stays 32 dp', (t) async {
      await pumpRow(t, completed: false);

      final target = find
          .ancestor(of: find.byIcon(Icons.check), matching: find.byType(GestureDetector))
          .first;
      final size = t.getSize(target);
      expect(size.width, greaterThanOrEqualTo(44.0));
      expect(size.height, greaterThanOrEqualTo(44.0));

      // The row's appearance is not a casualty of the fix.
      final check = t.getSize(find
          .ancestor(of: find.byIcon(Icons.check), matching: find.byType(Container))
          .first);
      expect(check.width, 32.0);
      expect(check.height, 32.0);
    });
  });
}
