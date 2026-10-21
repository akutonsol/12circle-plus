import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/workout/presentation/widgets/zone_action.dart';

/// FIT-002 · the Workout Zone's top-bar controls.
///
/// The bar held exactly one control: an unlabelled 36 dp cross. Two defects in
/// a single widget — a screen reader announced nothing for it (F-22 / A-G8),
/// and the target was under the 44 dp floor F-6 was raised about. FIT-002 names
/// it "End session" and declares a second control, "Pause session", which did
/// not exist at all.
///
/// The widget is extracted from `active_workout_screen.dart` so these claims
/// can be asserted: the screen itself reads `Supabase.instance` in a field
/// initializer and opens a session in `initState`, which no widget test can
/// satisfy. `plan_summary.dart` and `extendRest()` were extracted for the same
/// reason — the pattern is that a thing worth asserting gets moved somewhere it
/// can be.
void main() {
  /// The Zone's bar lays its children out in an unbounded-height Row inside a
  /// Container, so the control shrink-wraps. Reproduce that: a harness that
  /// hands down loose-but-bounded constraints lets the control stretch and the
  /// target-floor assertion stops measuring anything. That mistake is recorded
  /// in `rest_timer_controls_test.dart`.
  Widget host(Widget child) => MaterialApp(
        home: Scaffold(
          body: Column(
            mainAxisSize: MainAxisSize.min,
            children: [Row(children: [child])],
          ),
        ),
      );

  testWidgets('FIT-002 the control carries the name it is given', (t) async {
    final handle = t.ensureSemantics();
    await t.pumpWidget(host(ZoneAction(
      icon: Icons.close,
      label: 'End session',
      color: Colors.red,
      onTap: () {},
    )));

    expect(find.bySemanticsLabel('End session'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('FIT-002 an icon-only control is never left unnamed', (t) async {
    final handle = t.ensureSemantics();
    await t.pumpWidget(host(ZoneAction(
      icon: Icons.pause_rounded,
      label: 'Pause session',
      color: Colors.purple,
      onTap: () {},
    )));

    // The whole defect class: a tappable whose entire content is an Icon
    // reports with no name, and a screen reader announces nothing.
    final node = t.getSemantics(find.bySemanticsLabel('Pause session'));
    expect(node.label, 'Pause session');
    expect(node.hasFlag(SemanticsFlag.isButton), isTrue,
        reason: 'it must be announced as a button, not as a label');
    handle.dispose();
  });

  testWidgets('FIT-002 the target clears the 44 dp floor', (t) async {
    await t.pumpWidget(host(ZoneAction(
      icon: Icons.close,
      label: 'End session',
      color: Colors.red,
      onTap: () {},
    )));

    final size = t.getSize(find.byType(GestureDetector).first);
    expect(size.width, greaterThanOrEqualTo(44.0));
    expect(size.height, greaterThanOrEqualTo(44.0));
  });

  testWidgets('FIT-002 the visible chip stays 36 dp — the target is what grew',
      (t) async {
    // The bar's appearance is not a casualty of the fix. FIT-001's top nav took
    // the same approach: constrain the hit area, leave the decoration alone.
    await t.pumpWidget(host(ZoneAction(
      icon: Icons.close,
      label: 'End session',
      color: Colors.red,
      onTap: () {},
    )));

    final chip = t.getSize(
        find.ancestor(of: find.byType(Icon), matching: find.byType(Container)).first);
    expect(chip.width, 36.0);
    expect(chip.height, 36.0);
  });

  testWidgets('FIT-002 the whole 44 dp area is tappable, not just the chip',
      (t) async {
    // `behavior: HitTestBehavior.opaque` is what makes the reserved space
    // actually receive the gesture. Without it the target is 44 dp of empty
    // padding around a 36 dp button, which is the defect wearing a fix.
    var taps = 0;
    await t.pumpWidget(host(ZoneAction(
      icon: Icons.close,
      label: 'End session',
      color: Colors.red,
      onTap: () => taps++,
    )));

    final box = t.getRect(find.byType(GestureDetector).first);
    // A point inside the 44 dp target but outside the 36 dp chip.
    await t.tapAt(Offset(box.left + 2, box.top + 2));
    await t.pump();
    expect(taps, 1);
  });
}
