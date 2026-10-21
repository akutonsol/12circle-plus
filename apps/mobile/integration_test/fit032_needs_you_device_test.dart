// FIT-032 · "Needs you today" — measured on the device.
//
// The host-VM tests prove the rules (22) and the wiring (8), and fourteen
// mutations kill them. Three things they cannot settle, all physical:
//
//  * the 44 dp `tap` floor on each row, at the device's real dpr — F-6/F-6b
//    are why this is measured rather than read from source;
//  * whether a row reaches the platform accessibility tree as a button WITH a
//    tap action. `excludeSemantics: true` drops a child's ACTIONS along with
//    its labels, which is how F-20 shipped `44x44 tap=false label="Back"`;
//  * whether a real client name beside a real reason and an action chip still
//    fits one row at 360 dp with the real font. The host harness renders in
//    Ahem, where every glyph is a full em square (F-24).
//
// The widget is mounted with in-memory `ClientSignals`. Nothing is signed in,
// NO backend is touched and NO row is written, so this leaves no fixture
// behind. It also does not touch F-21: the `Assign` row's rule is exercised
// here, but nothing claims the assignment behind it is authentic.
//
//   flutter test integration_test/fit032_needs_you_device_test.dart \
//     -d emulator-5554 --dart-define-from-file=dart_defines/qa.json

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import 'package:circle_fitness/features/dashboard/domain/coach_triage.dart';
import 'package:circle_fitness/features/dashboard/presentation/widgets/needs_you_today.dart';

void _mark(String line) => print('FIT032-MARK $line');

// The board's own four, with its own words.
const _clients = [
  ClientSignals(
    clientId: 'a',
    clientName: 'Amara Osei',
    unrepliedCheckinWeek: 14,
    unrepliedCheckinNote: 'travel next week',
  ),
  ClientSignals(
    clientId: 'b',
    clientName: 'Tomas Vidal',
    daysSinceLastSession: 9,
  ),
  ClientSignals(
    clientId: 'c',
    clientName: 'Priya Raman',
    daysUntilBlockEnds: 5,
    blockEndsOn: 'Sunday',
  ),
  ClientSignals(
    clientId: 'd',
    clientName: 'Lena Fischer',
    unansweredMessage: 'Asked about the split squat',
  ),
];

const _labels = [
  'Amara Osei Week 14 check-in · travel next week Review',
  'Tomas Vidal No sessions logged in 9 days At risk',
  'Priya Raman Block ends Sunday · needs next Assign',
  'Lena Fischer Asked about the split squat Reply',
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester tester, {int total = 24}) async {
    final router = GoRouter(
      initialLocation: '/coach-dashboard',
      routes: [
        for (final p in const [
          '/coach-dashboard',
          '/coach-checkin-review',
          '/messages',
          '/program-builder',
          '/coach-client-workouts',
        ])
          GoRoute(
            path: p,
            builder: (_, __) => Scaffold(
              backgroundColor: const Color(0xFF0A0A0B),
              body: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: p == '/coach-dashboard'
                      ? NeedsYouToday(
                          clients: _clients,
                          totalClients: total,
                          inactivityDays: 9,
                          blockEndHorizonDays: 7,
                        )
                      : Text('AT $p'),
                ),
              ),
            ),
          ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('the four rows, on the device', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);

    final dpr = tester.view.devicePixelRatio;
    _mark('viewport ${(tester.view.physicalSize.width / dpr).toStringAsFixed(1)}'
        ' dp @ dpr $dpr');

    for (final label in _labels) {
      final f = find.bySemanticsLabel(label);
      expect(f, findsOneWidget, reason: 'missing row: $label');
      final d = tester.getSemantics(f).getSemanticsData();
      final size = tester.getSize(f);
      _mark('${size.width.toStringAsFixed(1)}x'
          '${size.height.toStringAsFixed(1)} '
          'button=${d.hasFlag(SemanticsFlag.isButton)} '
          'tap=${d.hasAction(SemanticsAction.tap)} "$label"');

      expect(d.hasFlag(SemanticsFlag.isButton), isTrue);
      expect(d.hasAction(SemanticsAction.tap), isTrue,
          reason: 'F-20: a named button that cannot be activated is not one');
      expect(size.height, greaterThanOrEqualTo(44.0),
          reason: 'the `tap` floor, measured not assumed');
    }

    // The chips read as the board writes them — `.pill` has no text-transform.
    for (final w in const ['Review', 'At risk', 'Assign', 'Reply']) {
      expect(find.text(w), findsOneWidget);
      expect(find.text(w.toUpperCase()), findsNothing);
    }
    expect(find.text('All 24 clients'), findsOneWidget);

    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  testWidgets('a row opens where its action is performed', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Priya Raman'));
    await tester.pumpAndSettle();
    _mark('Assign -> /program-builder reached');
    expect(find.text('AT /program-builder'), findsOneWidget);
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

      // The longest row — a full name, a full reason and a chip.
      expect(find.text('Block ends Sunday · needs next'), findsOneWidget);
      final err = tester.takeException();
      _mark('$dp dp — four rows, exception=${err ?? 'none'}');
      expect(err, isNull,
          reason: 'an overflow at $dp dp is a layout defect, not a harness one');
    }
  });
}
