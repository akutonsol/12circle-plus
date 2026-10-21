import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/onboarding/presentation/onboarding_screen.dart';

/// FIT-006 · Welcome — and F-26, the app's front door.
///
/// ── THE DEFECT ─────────────────────────────────────────────────────────────
/// "Get Started" was a **slide-to-confirm** control: `onHorizontalDragUpdate`
/// and `onHorizontalDragEnd`, no tap, no semantics. A screen-reader user, or
/// anyone who cannot perform a precise horizontal drag — switch access,
/// tremor, limited dexterity — **could not create an account at all.**
///
/// Not a labelling gap. The first screen of the product had no accessible path
/// past it.
///
/// The slide stays: it is what the design draws and the friction is deliberate.
/// What was added is a single activatable node for the accessibility APIs,
/// which changes nothing on screen.
void main() {
  Future<void> mount(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(420, 1000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(const MaterialApp(home: OnboardingScreen()));
    await t.pump();
  }

  testWidgets('F-26 the account CTA is activatable without a drag', (t) async {
    final handle = t.ensureSemantics();
    await mount(t);

    final finder = find.bySemanticsLabel('Create your account');
    expect(finder, findsOneWidget,
        reason: 'the front door must expose one node assistive tech can press');

    final d = t.getSemantics(finder).getSemanticsData();
    expect(d.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(d.hasAction(SemanticsAction.tap), isTrue,
        reason: 'a drag-only control is unreachable by switch access and by a '
            'screen reader — this is the whole finding');
    handle.dispose();
  });

  testWidgets('FIT-006 both declared controls carry the design\'s wording',
      (t) async {
    await mount(t);
    expect(find.text('Create your account'), findsOneWidget);
    expect(find.text('I already have one'), findsOneWidget);
    // The words they replaced, which the locked screen overrides.
    expect(find.text('Get Started'), findsNothing);
    expect(find.textContaining('Already a member?'), findsNothing);
  });

  testWidgets('FIT-006 the sign-in control is named by its visible text',
      (t) async {
    // WCAG 2.5.3: the accessible name must contain the visible label. The
    // visible text is what changed, not an override announced over it.
    final handle = t.ensureSemantics();
    await mount(t);

    final d = t.getSemantics(find.text('I already have one')).getSemanticsData();
    expect(d.label, contains('I already have one'));
    expect(d.hasFlag(SemanticsFlag.isButton), isTrue);
    handle.dispose();
  });

  testWidgets('FIT-006 the sign-in control clears the 44 dp floor', (t) async {
    await mount(t);
    final size = t.getSize(find
        .ancestor(
            of: find.text('I already have one'), matching: find.byType(GestureDetector))
        .first);
    expect(size.height, greaterThanOrEqualTo(44.0));
  });

  testWidgets('F-26 the slide still exists — the fix adds, it does not replace',
      (t) async {
    // The design draws a slide and the friction is deliberate. If this stops
    // finding a drag handler the visual interaction was removed, not fixed.
    await mount(t);
    final gestures = t.widgetList<GestureDetector>(find.byType(GestureDetector));
    expect(gestures.any((g) => g.onHorizontalDragEnd != null), isTrue,
        reason: 'the slide-to-confirm gesture must survive');
  });
}
