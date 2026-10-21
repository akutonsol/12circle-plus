import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/payments/domain/entitlements.dart';
import 'package:circle_fitness/features/payments/presentation/paywall_gate.dart';

/// FIT-021 · the entitlement gate — one component behind **twelve routes**.
///
/// ── WHY THIS ONE MATTERED ──────────────────────────────────────────────────
/// The anchor declares three controls. The screen had one and a half: a
/// `See Plans` button, and a back arrow named by Material's default tooltip
/// rather than by the package.
///
/// **`Not now` did not exist at all.** A client who hit a paywall could only
/// leave by the system back gesture — there was nothing on screen that said
/// they were allowed to. On a screen whose whole job is to ask for money, the
/// absence of a visible way to decline is not a cosmetic gap.
void main() {
  Future<void> mount(WidgetTester t, {VoidCallback? onPopped}) async {
    await t.binding.setSurfaceSize(const Size(420, 1000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(
      // A route beneath, so `maybePop` has somewhere to go and a pop is
      // observable — asserting the control exists says nothing about whether
      // it leaves.
      home: Builder(builder: (context) {
        return Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(
                      builder: (_) => const PaywallLocked(
                          required: ClientPlan.selfGuided,
                          feature: 'Nutrition Tracking')))
                  .then((_) => onPopped?.call()),
              child: const Text('open'),
            ),
          ),
        );
      }),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  testWidgets('FIT-021 all three declared controls are present', (t) async {
    await mount(t);
    expect(find.text('See plans'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
    expect(find.bySemanticsLabel('Back'), findsOneWidget);
  });

  testWidgets('FIT-021 "Not now" actually leaves the gate', (t) async {
    // The control existing is not the point; being able to decline is.
    var popped = 0;
    await mount(t, onPopped: () => popped++);
    expect(find.text('Not now'), findsOneWidget);

    await t.tap(find.text('Not now'));
    await t.pumpAndSettle();

    expect(popped, 1);
    expect(find.text('Not now'), findsNothing);
  });

  testWidgets('FIT-021 "Back" leaves too, and is named from the package',
      (t) async {
    var popped = 0;
    await mount(t, onPopped: () => popped++);

    await t.tap(find.bySemanticsLabel('Back'));
    await t.pumpAndSettle();
    expect(popped, 1);
  });

  testWidgets('FIT-021 both exits clear the 44 dp target floor', (t) async {
    await mount(t);
    for (final label in ['Not now']) {
      final size = t.getSize(find
          .ancestor(of: find.text(label), matching: find.byType(GestureDetector))
          .first);
      expect(size.height, greaterThanOrEqualTo(44.0), reason: label);
    }
    final back = t.getSize(find
        .ancestor(
            of: find.byIcon(Icons.arrow_back), matching: find.byType(GestureDetector))
        .first);
    expect(back.height, greaterThanOrEqualTo(44.0));
    expect(back.width, greaterThanOrEqualTo(44.0));
  });

  testWidgets('FIT-021 both exits are pressable from the accessibility tree',
      (t) async {
    final handle = t.ensureSemantics();
    await mount(t);

    final back = t.getSemantics(find.bySemanticsLabel('Back')).getSemanticsData();
    expect(back.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(back.hasAction(SemanticsAction.tap), isTrue,
        reason: 'excludeSemantics drops the child\'s actions with it');

    final notNow = t.getSemantics(find.text('Not now')).getSemanticsData();
    expect(notNow.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(notNow.hasAction(SemanticsAction.tap), isTrue);
    handle.dispose();
  });

  testWidgets('FIT-021 the gate still names the feature it is gating',
      (t) async {
    // Pre-existing behaviour the change must not have flattened: a paywall
    // that does not say what is locked is just a wall.
    await mount(t);
    expect(find.textContaining('Nutrition Tracking'), findsOneWidget);
  });
}
