import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/nutrition/presentation/widgets/nutrition_load_failed.dart';

/// FIT-022 · "Loading & failure — the two patterns every data screen inherits".
///
/// ── THE RULE, IN THE BOARD'S OWN WORDS ─────────────────────────────────────
/// *"The failure state names what did **not** happen — 'everything you've
/// logged is saved' — because the fear a failed screen creates is data loss,
/// not inconvenience."*
///
/// That annotation is the reason this state is not just another
/// "Could not load X". A client whose nutrition screen fails does not mainly
/// want to know the request failed; they want to know their morning's logging
/// is still there.
///
/// ── WHAT IT REPLACES ───────────────────────────────────────────────────────
/// `totals.valueOrNull?['calories'] ?? 0.0` — a failed read rendered **zero
/// calories** to a client who had logged three meals, who might reasonably log
/// them again.
void main() {
  Future<void> mount(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(420, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(const ProviderScope(
      child: MaterialApp(home: Scaffold(body: NutritionLoadFailed())),
    ));
    await t.pump();
  }

  testWidgets('FIT-022 the board\'s words, verbatim', (t) async {
    await mount(t);
    expect(find.text("Couldn't load today"), findsOneWidget);
    expect(
        find.text("Everything you've already logged is saved. Only today's "
            'totals failed to load.'),
        findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('FIT-022 it names what did NOT happen', (t) async {
    // The annotation's actual requirement, asserted rather than assumed: the
    // state has to say the logged data is safe. A failure card that only says
    // "could not load" satisfies the pattern and misses the point.
    await mount(t);
    expect(find.textContaining('is saved'), findsOneWidget);
  });

  testWidgets('FIT-022 no zero is presented as a total', (t) async {
    // The defect this replaces: zeros rendered as if they were the answer.
    await mount(t);
    expect(find.text('0'), findsNothing);
    expect(find.textContaining('0 kcal'), findsNothing);
  });

  testWidgets('FIT-022 the retry is reachable and clears the target floor',
      (t) async {
    final handle = t.ensureSemantics();
    await mount(t);

    final d = t.getSemantics(find.text('Try again')).getSemanticsData();
    expect(d.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(d.hasAction(SemanticsAction.tap), isTrue);

    final size = t.getSize(find
        .ancestor(of: find.text('Try again'), matching: find.byType(GestureDetector))
        .first);
    expect(size.height, greaterThanOrEqualTo(44.0));
    expect(size.width, greaterThanOrEqualTo(44.0));
    handle.dispose();
  });

  testWidgets('FIT-022 the heading is announced as one', (t) async {
    final handle = t.ensureSemantics();
    await mount(t);
    expect(
        t.getSemantics(find.text("Couldn't load today")).getSemanticsData()
            .hasFlag(SemanticsFlag.isHeader),
        isTrue);
    handle.dispose();
  });

  testWidgets('FIT-022 the raw exception never reaches the client', (t) async {
    await mount(t);
    expect(find.textContaining('Exception'), findsNothing);
  });

  test('FIT-022 the screen renders the state instead of zeros', () {
    // The card above is tested; this is the WIRING. Restoring the
    // `?? 0.0` path as the only one — the behaviour that shipped — is
    // otherwise a mutation that survives, because `MealsDashboardScreen`
    // reads Supabase and cannot be mounted in a widget test.
    //
    // Comments are stripped: this file's own header quotes the defect, and a
    // guard that trips on its own explanation is the mistake already recorded
    // against the FIT coverage metric and the MSG-003 guard.
    final code = File('lib/features/nutrition/presentation/meals_dashboard_screen.dart')
        .readAsStringSync()
        .split('\n')
        .map((l) {
          final i = l.indexOf('//');
          return i == -1 ? l : l.substring(0, i);
        })
        .join('\n');

    expect(code, contains('NutritionLoadFailed'),
        reason: 'a failed totals read must render FIT-022\'s state');
    expect(code, contains('totalsFailed'),
        reason: 'the failure has to reach the builder to be renderable');
    expect(code, contains('totals is AsyncError'),
        reason: 'matching on the STATE, not on a null value — an error\'s null '
            'and an empty result\'s null are the same null');
  });
}
