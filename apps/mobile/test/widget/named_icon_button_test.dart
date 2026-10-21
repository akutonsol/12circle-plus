import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/core/widgets/named_icon_button.dart';

// `NamedIconButton` is the one place the "icon-only control, done correctly"
// shape lives, and its three promises — a name, a pressable button role, and a
// 44 dp target around an UNCHANGED chip — are load-bearing for every caller.
//
// Nothing tested them. Deleting the widget's `BoxConstraints(minWidth:
// minTarget, minHeight: minTarget)` left the entire 1,483-test suite green.
// That gap mattered more the moment seven more call sites were routed through
// it in this session's back-control work: each of those sites gave up its own
// constraint and took this one on trust.
//
// The harness is a `Column`, not a full-height `body:`. A `Container` with
// `alignment:` EXPANDS TO FILL bounded constraints, so under a `Scaffold` body
// this widget measures the screen height and the floor assertion passes with
// the constraint deleted — which is exactly how the /ai-coach tab test failed
// to test anything.

const _chipKey = Key('chip');

Future<void> _pump(
  WidgetTester tester, {
  String label = 'Back',
  VoidCallback? onTap,
  double minTarget = 44,
  double chip = 20,
}) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                NamedIconButton(
                  label: label,
                  onTap: onTap,
                  minTarget: minTarget,
                  child: SizedBox(
                      key: _chipKey,
                      width: chip,
                      height: chip,
                      child: const Icon(Icons.arrow_back, size: 18)),
                ),
              ],
            ),
          ],
        ),
      ),
    ));

void main() {
  testWidgets('it carries the caller\'s name and a pressable button role',
      (tester) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await _pump(tester, label: 'End session', onTap: () => taps++);

    final data = tester
        .getSemantics(find.bySemanticsLabel('End session'))
        .getSemanticsData();

    expect(data.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue,
        reason: '`excludeSemantics` drops the child\'s ACTIONS with its '
            'labels. Without `onTap` on the Semantics the node announces as a '
            'button a screen reader CANNOT press — worse than the unnamed '
            'control it replaced. That shipped once (F-20).');

    await tester.tap(find.bySemanticsLabel('End session'));
    expect(taps, 1, reason: 'and the gesture must fire for sighted users too');

    handle.dispose();
  });

  testWidgets('the target reaches 44 dp while the chip stays its own size',
      (tester) async {
    await _pump(tester, chip: 20);

    final target = tester.getSize(find.byType(NamedIconButton));
    expect(target.width, greaterThanOrEqualTo(44.0));
    expect(target.height, greaterThanOrEqualTo(44.0));
    // A floor, not a box: if this is huge the finder has climbed out of the
    // widget and the assertion above means nothing.
    expect(target.height, lessThan(200.0));

    // The design's `tap` component is a 44 dp TARGET, not a 44 dp box — the
    // hit area grows and the decoration does not.
    expect(tester.getSize(find.byKey(_chipKey)), const Size(20, 20),
        reason: 'the chip must be left exactly as the caller drew it');
  });

  testWidgets('a chip already larger than the floor is not shrunk to it',
      (tester) async {
    await _pump(tester, chip: 64);

    expect(tester.getSize(find.byKey(_chipKey)), const Size(64, 64));
    expect(tester.getSize(find.byType(NamedIconButton)).height,
        greaterThanOrEqualTo(64.0),
        reason: 'minTarget is a minimum, not a size');
  });

  testWidgets('a caller may raise the floor', (tester) async {
    await _pump(tester, minTarget: 56, chip: 20);
    expect(tester.getSize(find.byType(NamedIconButton)).height,
        greaterThanOrEqualTo(56.0));
  });

  testWidgets('a disabled control still announces its name', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, label: 'Back', onTap: null);

    final data =
        tester.getSemantics(find.bySemanticsLabel('Back')).getSemanticsData();
    expect(data.label, 'Back',
        reason: 'a control with nothing to do is still a control with a name');

    handle.dispose();
  });

  // ── A property this test CANNOT establish, stated rather than implied ────
  //
  // `NamedIconButton`'s doc credits `container: true` with stopping the node
  // absorbing adjacent text — F-9 measured an intake header merged into a back
  // button, the resulting node covering the whole 411 x 914 dp screen.
  //
  // Mutating `container: true` to `false` changes NOTHING in a widget test:
  // not the label, not the node's rect. Almost certainly because
  // `excludeSemantics: true` already forces a node boundary here, so the flag
  // is redundant in this shape rather than load-bearing.
  //
  // So this asserts only what it can observe — the node is the control's own,
  // and its neighbour is not inside it. It does NOT prove `container: true`
  // is what achieves that, and the comment in `named_icon_button.dart` should
  // be read with that in mind. F-9's evidence was a real semantics tree on a
  // device; this is a widget test, and the difference is the whole point of
  // the RUNTIME_VERIFIED rung.
  testWidgets('the node is the control\'s own, and excludes its neighbour',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            NamedIconButton(
              label: 'Back',
              onTap: () {},
              child: const Icon(Icons.arrow_back, size: 18),
            ),
            const Text('Weekly Check-In'),
          ]),
        ]),
      ),
    ));

    final node = tester.getSemantics(find.bySemanticsLabel('Back'));
    expect(node.getSemanticsData().label, 'Back');
    expect(node.getSemanticsData().label, isNot(contains('Weekly')));
    expect(node.rect.width, lessThan(120));
    expect(node.rect.height, lessThan(120));

    handle.dispose();
  });
}
