// FIT-018 · "Session complete" — measured on the device.
//
// The host tests prove the rules and the wiring, and nine mutations kill them.
// Three things they cannot settle, all physical:
//
//  * the 44 dp `tap` floor on each effort answer, at the device's real dpr
//    (F-6/F-6b);
//  * whether each answer reaches the platform accessibility tree as a
//    mutually-exclusive, selectable button WITH a tap action —
//    `excludeSemantics: true` drops a child's actions along with its labels,
//    which is how F-20 shipped `44x44 tap=false label="Back"`;
//  * whether three figures and three answers still fit at 360 dp with the real
//    font. The host harness renders in Ahem (F-24).
//
// The dialog is mounted directly with an injected submit. Nothing is signed
// in, NO backend is touched and NO row is written.
//
//   flutter test integration_test/fit018_session_complete_device_test.dart \
//     -d emulator-5554 --dart-define-from-file=dart_defines/qa.json

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:circle_fitness/features/workout/domain/session_complete.dart';
import 'package:circle_fitness/features/workout/presentation/active_workout_screen.dart';

void _mark(String line) => print('FIT018-MARK $line');

Future<FeedbackDelivery> _ok({
  required int rating,
  required int energy,
  required int difficulty,
  required String notes,
}) async =>
    FeedbackDelivery.saved;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF0A0A0B),
        body: SingleChildScrollView(
          child: WorkoutCompleteDialog(
            title: 'Lower body — strength',
            duration: '51:00',
            calories: 0,
            elapsedSeconds: 51 * 60,
            setsLogged: 18,
            volumeKg: 4200,
            onDone: () {},
            submit: _ok,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('the four declared interactions, on the device', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);

    final dpr = tester.view.devicePixelRatio;
    _mark('viewport ${(tester.view.physicalSize.width / dpr).toStringAsFixed(1)}'
        ' dp @ dpr $dpr');

    expect(find.text('Lower body, done.'), findsOneWidget);
    expect(find.text('Workout Complete!'), findsNothing);
    _mark('title="Lower body, done." (no confetti)');

    for (final e in SessionEffort.values) {
      final f = find.bySemanticsLabel(e.label);
      final d = tester.getSemantics(f).getSemanticsData();
      final size = tester.getSize(f);
      _mark('${e.label.padRight(6)} ${size.width.toStringAsFixed(1)}x'
          '${size.height.toStringAsFixed(1)} '
          'button=${d.hasFlag(SemanticsFlag.isButton)} '
          'tap=${d.hasAction(SemanticsAction.tap)} '
          'exclusive=${d.hasFlag(SemanticsFlag.isInMutuallyExclusiveGroup)} '
          'selected=${d.hasFlag(SemanticsFlag.isSelected)}');
      expect(d.hasFlag(SemanticsFlag.isButton), isTrue);
      expect(d.hasAction(SemanticsAction.tap), isTrue);
      expect(d.hasFlag(SemanticsFlag.isInMutuallyExclusiveGroup), isTrue);
      expect(size.height, greaterThanOrEqualTo(44.0));
    }

    // The board's three figures, from what was logged.
    for (final v in const ['51', '18', '4.2']) {
      expect(find.text(v), findsOneWidget);
    }
    _mark('stats 51 min / 18 sets / 4.2 t');

    expect(find.text(sessionDoneLabel), findsWidgets);
    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  testWidgets('choosing an answer selects exactly one', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);

    await tester.tap(find.text('Hard'));
    await tester.pumpAndSettle();

    bool sel(String l) => tester
        .getSemantics(find.bySemanticsLabel(l))
        .getSemanticsData()
        .hasFlag(SemanticsFlag.isSelected);
    _mark('after tapping Hard: easy=${sel('Easy')} right=${sel('Right')} '
        'hard=${sel('Hard')}');
    expect(sel('Hard'), isTrue);
    expect(sel('Easy'), isFalse);
    expect(sel('Right'), isFalse);
    handle.dispose();
  });

  testWidgets('it holds from 360 dp up, with the real font', (tester) async {
    final originalSize = tester.view.physicalSize;
    final dpr = tester.view.devicePixelRatio;
    addTearDown(() {
      tester.view.physicalSize = originalSize;
      tester.view.resetDevicePixelRatio();
    });

    for (final dp in const [360.0, 390.0, 411.4]) {
      tester.view.physicalSize = Size(dp * dpr, 844 * dpr);
      await pump(tester);
      expect(find.text('Lower body, done.'), findsOneWidget);
      final err = tester.takeException();
      _mark('$dp dp — exception=${err ?? 'none'}');
      expect(err, isNull);
    }
  });
}
