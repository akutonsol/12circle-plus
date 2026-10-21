// QAX-COR-06 — the weight and measurement sheets on /progress.
//
// Before the fix both sheets wrapped the write in `catch (_) { _saving = false }`:
// a failed save just re-enabled the button with no message, and a signed-out
// save returned early with the spinner stuck forever. The measurement sheet
// awarded check-in points inside the same try, so a points failure AFTER a
// successful insert looked like a failed save and invited a duplicate row.
//
// These drive the real sheets with an injected row writer. A failure must say
// so; success must still close the sheet (positive control).
import 'package:circle_fitness/features/progress/presentation/progress_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _launcher(Widget Function() sheet) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => showModalBottomSheet(
              context: ctx,
              isScrollControlled: true,
              builder: (_) => sheet(),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

/// A realistic phone viewport (390x844 logical).
///
/// The weight sheet has two PRE-EXISTING layout overflows, recorded as their own
/// findings (QAX-UI-01 date/unit row, QAX-UI-02 ruler ticks) and reproduced by
/// tool/qa_exhaustion/progress_sheet_overflow_repro_test.dart. Only RenderFlex
/// overflow reports are filtered here, so they cannot mask what THIS file tests;
/// every other framework error still fails the test.
void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('A RenderFlex overflowed')) return;
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
}

Future<void> _open(WidgetTester tester) async {
  _phone(tester);
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _tapSave(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  group('QAX-COR-06 a failed progress save is surfaced', () {
    testWidgets('weight: failure shows a message and re-enables Save', (tester) async {
      var writes = 0;
      await tester.pumpWidget(_launcher(() => LogWeightSheet(
            writeRow: (table, row) async {
              writes++;
              throw Exception('simulated write failure');
            },
          )));
      await _open(tester);
      await _tapSave(tester, 'Save Entry');

      expect(tester.takeException(), isNull);
      expect(writes, 1);
      expect(find.text(progressSaveFailedMessage), findsOneWidget);
      expect(find.text('Save Entry'), findsOneWidget, reason: 'spinner must not stick');
    });

    testWidgets('measurements: failure shows a message and re-enables Save', (tester) async {
      await tester.pumpWidget(_launcher(() => LogMeasurementSheet(
            writeRow: (table, row) async => throw Exception('simulated write failure'),
          )));
      await _open(tester);
      await _tapSave(tester, 'Save Measurements');

      expect(tester.takeException(), isNull);
      expect(find.text(progressSaveFailedMessage), findsOneWidget);
      expect(find.text('Save Measurements'), findsOneWidget);
    });
  });

  group('QAX-COR-06 positive controls — success closes the sheet', () {
    testWidgets('weight: success writes weight_logs, closes, calls onSaved', (tester) async {
      String? table;
      var saved = 0;
      await tester.pumpWidget(_launcher(() => LogWeightSheet(
            initialKg: 70,
            onSaved: () => saved++,
            writeRow: (t, row) async => table = t,
          )));
      await _open(tester);
      await _tapSave(tester, 'Save Entry');

      expect(table, 'weight_logs');
      expect(saved, 1);
      expect(find.text('Save Entry'), findsNothing);
      expect(find.text(progressSaveFailedMessage), findsNothing);
    });

    testWidgets('measurements: a stored row counts as saved even if the points '
        'award afterwards fails (no duplicate-inviting error)', (tester) async {
      var saved = 0;
      await tester.pumpWidget(_launcher(() => LogMeasurementSheet(
            onSaved: () => saved++,
            writeRow: (t, row) async {},
          )));
      await _open(tester);
      await _tapSave(tester, 'Save Measurements');

      // No Supabase in the test harness, so the check-in points award fails —
      // exactly the "insert succeeded, follow-up failed" case.
      expect(tester.takeException(), isNull);
      expect(saved, 1);
      expect(find.text('Save Measurements'), findsNothing);
    });
  });
}
