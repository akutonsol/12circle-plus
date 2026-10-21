import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/workout/presentation/widgets/rest_timer_widget.dart';

/// FIT-017 — "/active-workout · two states of the session". The rest state
/// declares exactly two controls: **"Skip rest, start set"** and **"Add 30
/// seconds"**.
///
/// Skip existed. Add 30 seconds did not — a client who needed longer had no
/// control at all, so the only available action was to let the clock run into
/// overtime, which starts a siren and drains points every 20 seconds. The
/// screen punished a need it gave no way to express.
///
/// Two things these tests hold, beyond "the button is there":
///
///  * **the short visible label is not the accessible name.** The banner is a
///    single row with a progress bar in it; "Skip rest, start set" does not fit
///    as visible text. So the design's phrase is what the semantics carry and
///    "SKIP" is what is drawn. A test that only looked for the drawn text would
///    pass on a control a screen reader announces as "SKIP" or as nothing.
///  * **the 44 dp floor.** A 12 pt label is about 30 dp tall on its own. F-6
///    was raised about exactly this on the password toggle (measured 19.8 ×
///    20.2 dp on-device), so a new control shipping under the floor would be
///    the same defect in a new place.
void main() {
  /// The banner sits in a `Column` on `/active-workout`, so it is laid out
  /// with an UNBOUNDED height and shrink-wraps its row. The first version of
  /// this harness used `Align`, which hands down loose-but-bounded
  /// constraints — under those the controls expand to 566 dp tall and the
  /// target-floor assertion below passes no matter what the widget declares.
  /// Reproduce production's constraints or measure nothing.
  Widget host(Widget child) => MaterialApp(
        home: Scaffold(
          body: Column(mainAxisSize: MainAxisSize.min, children: [child]),
        ),
      );

  /// A rest that is still counting down. Far enough out that the widget cannot
  /// tick into overtime mid-test.
  RestTimerWidget counting({
    VoidCallback? onExtend,
    VoidCallback? onComplete,
  }) =>
      RestTimerWidget(
        endTime: DateTime.now().add(const Duration(seconds: 90)),
        totalSeconds: 120,
        onExtend: onExtend,
        onComplete: onComplete ?? () {},
      );

  testWidgets('FIT-017 the rest state offers both declared controls', (t) async {
    await t.pumpWidget(host(counting(onExtend: () {})));
    await t.pump();

    expect(find.text('+30s'), findsOneWidget);
    expect(find.text('SKIP'), findsOneWidget);
  });

  testWidgets('FIT-017 both controls announce the design\'s wording', (t) async {
    final handle = t.ensureSemantics();
    await t.pumpWidget(host(counting(onExtend: () {})));
    await t.pump();

    // The phrases come from the design package, not from this repository's
    // imagination — FIT-017's two declared interactions verbatim.
    expect(find.bySemanticsLabel('Add 30 seconds'), findsOneWidget);
    expect(find.bySemanticsLabel('Skip rest, start set'), findsOneWidget);

    // And the abbreviations must not leak into the announcement, which is what
    // happens if the Semantics wrapper stops excluding its child.
    expect(find.bySemanticsLabel('+30s'), findsNothing);
    expect(find.bySemanticsLabel('SKIP'), findsNothing);
    handle.dispose();
  });

  testWidgets('FIT-017 both controls clear the 44 dp target floor', (t) async {
    await t.pumpWidget(host(counting(onExtend: () {})));
    await t.pump();

    for (final label in ['+30s', 'SKIP']) {
      // The TAP TARGET, not some ancestor of it. `find.ancestor(... Container)`
      // was the first attempt and it was worthless: it resolved to the banner,
      // which is 44 dp tall whatever the control does, so deleting the
      // constraint outright left the test green. Measure the thing that
      // receives the gesture.
      final box = find
          .ancestor(of: find.text(label), matching: find.byType(GestureDetector))
          .first;
      final size = t.getSize(box);
      expect(size.height, greaterThanOrEqualTo(44.0), reason: '$label is too short');
      expect(size.width, greaterThanOrEqualTo(44.0), reason: '$label is too narrow');
    }
  });

  testWidgets('FIT-017 each control reports to its own callback', (t) async {
    var extended = 0;
    var skipped = 0;
    await t.pumpWidget(host(counting(
      onExtend: () => extended++,
      onComplete: () => skipped++,
    )));
    await t.pump();

    await t.tap(find.text('+30s'));
    expect(extended, 1);
    expect(skipped, 0, reason: 'extending rest must not also dismiss it');

    await t.tap(find.text('SKIP'));
    expect(skipped, 1);
    expect(extended, 1);
  });

  testWidgets('FIT-017 no extend handler means no extend control', (t) async {
    // Rather than drawing a control that silently does nothing.
    await t.pumpWidget(host(counting()));
    await t.pump();

    expect(find.text('+30s'), findsNothing);
    expect(find.text('SKIP'), findsOneWidget);
  });
}
