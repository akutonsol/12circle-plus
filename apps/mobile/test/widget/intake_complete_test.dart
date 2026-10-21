import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/features/coach/domain/coach_provider.dart';
import 'package:circle_fitness/features/onboarding/presentation/widgets/intake_complete_page.dart';

/// FIT-009 · "Intake complete" — the state that did not exist.
///
/// The flow called `context.go('/home')` the instant the last answer saved, so
/// the client's work ended in a screen transition. The anchor draws a state,
/// and the board carries its words:
///
///   "That's everything we needed."
///   "<coach> has your answers and will have your first week ready by
///    tomorrow morning."
///   "While you wait" / "Have a look at the exercise library, or log what you
///   ate today."
///   "Go to my home"
///
/// And its annotation: *"Success is quiet: a mark, a sentence, what happens
/// next. No confetti, no celebration animation."*
void main() {
  Future<void> mount(
    WidgetTester t, {
    required AsyncValue<Map<String, dynamic>?> coach,
    VoidCallback? onGoHome,
  }) async {
    await t.binding.setSurfaceSize(const Size(420, 1000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(ProviderScope(
      overrides: [
        assignedCoachProvider.overrideWith((ref) => coach.when(
              data: (d) => d,
              error: (e, s) => Future<Map<String, dynamic>?>.error(e, s),
              loading: () => Completer<Map<String, dynamic>?>().future,
            )),
      ],
      child: MaterialApp(
        home: IntakeCompletePage(onGoHome: onGoHome ?? () {}),
      ),
    ));
    await t.pump();
  }

  const noCoach = AsyncData<Map<String, dynamic>?>(null);

  testWidgets('FIT-009 the board\'s own words are on screen', (t) async {
    await mount(t, coach: noCoach);
    expect(find.text("That's everything we needed."), findsOneWidget);
    expect(find.text('While you wait'), findsOneWidget);
    expect(
        find.text('Have a look at the exercise library, or log what you ate today.'),
        findsOneWidget);
    expect(find.text('Go to my home'), findsOneWidget);
  });

  testWidgets('FIT-009 a coach-guided client sees their coach named',
      (t) async {
    await mount(t,
        coach: const AsyncData<Map<String, dynamic>?>({'first_name': 'Nadia'}));
    expect(
        find.text('Nadia has your answers and will have your first week ready '
            'by tomorrow morning.'),
        findsOneWidget);
  });

  testWidgets('FIT-009 a FAILED coach read does not name a coach', (t) async {
    // The same rule as everywhere else: naming a coach on a failed read is
    // /profile's collapse turned inside out. The sentence stays true instead.
    //
    // NOTE ON WHAT THIS CANNOT CATCH. Swapping `coachAddressed`'s input for
    // `AsyncData(provider.valueOrNull)` — which drops the error state — is a
    // mutation that SURVIVES here, because the override harness turns an
    // `AsyncError` into `Future.error` and the provider rebuilds with no
    // previous value, so `.valueOrNull` is null either way. The stale-error
    // case cannot be constructed through a provider override; it is
    // constructed directly, and that mutation killed, in
    // `test/unit/coach_name_test.dart`. Recorded rather than left to look
    // like coverage it is not.
    await mount(t,
        coach: AsyncError<Map<String, dynamic>?>(
            Exception('offline'), StackTrace.empty));
    expect(find.textContaining('Nadia'), findsNothing);
    expect(
        find.text('We have your answers and will have your first week ready by '
            'tomorrow morning.'),
        findsOneWidget);
  });

  testWidgets('FIT-009 a client with no coach gets a sentence that is true',
      (t) async {
    await mount(t, coach: noCoach);
    // "We have your answers…" — grammatical without a name, which is the
    // point. The bug this guards is a sentence that reads " has your
    // answers", with a hole where the name should be.
    expect(
        find.text('We have your answers and will have your first week ready by '
            'tomorrow morning.'),
        findsOneWidget);
    expect(find.textContaining(' has your answers'), findsNothing);
  });

  testWidgets('FIT-009 success is quiet — no celebration', (t) async {
    // The board's annotation, applied literally: "a mark, a sentence, what
    // happens next. No confetti, no celebration animation."
    await mount(t, coach: noCoach);
    expect(find.text('🎉'), findsNothing);
    expect(find.byIcon(Icons.celebration), findsNothing);
    expect(find.byIcon(Icons.emoji_events_rounded), findsNothing);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget,
        reason: 'a mark, which is what the board asks for');
  });

  testWidgets('FIT-009 the action leaves, and clears the target floor',
      (t) async {
    final handle = t.ensureSemantics();
    var went = 0;
    await mount(t, coach: noCoach, onGoHome: () => went++);

    final size = t.getSize(find
        .ancestor(of: find.text('Go to my home'), matching: find.byType(GestureDetector))
        .first);
    expect(size.height, greaterThanOrEqualTo(44.0));

    final d = t.getSemantics(find.text('Go to my home')).getSemanticsData();
    expect(d.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(d.hasAction(SemanticsAction.tap), isTrue);

    await t.tap(find.text('Go to my home'));
    expect(went, 1);
    handle.dispose();
  });

  testWidgets('FIT-009 the headings are announced as headings', (t) async {
    final handle = t.ensureSemantics();
    await mount(t, coach: noCoach);
    for (final h in ["That's everything we needed.", 'While you wait']) {
      expect(
          t.getSemantics(find.text(h)).getSemanticsData()
              .hasFlag(SemanticsFlag.isHeader),
          isTrue,
          reason: h);
    }
    handle.dispose();
  });

  test('FIT-009 the flow renders the state instead of skipping it', () {
    // The page above is tested; this is the WIRING. Deleting the render and
    // going straight to /home — the behaviour that shipped — is otherwise a
    // mutation that survives, because `IntakeFlowScreen` reads Supabase and
    // cannot be driven to completion in a widget test.
    final src = File('lib/features/onboarding/presentation/intake_flow_screen.dart')
        .readAsStringSync();
    final code = src
        .split('\n')
        .map((l) {
          final i = l.indexOf('//');
          return i == -1 ? l : l.substring(0, i);
        })
        .join('\n');

    expect(code, contains('IntakeCompletePage'),
        reason: 'FIT-009 is a state the flow must render, not a redirect');
    expect(code.contains("_finish") && code.contains("_done = true"), isTrue,
        reason: 'finishing must reach the state rather than navigate away');
  });
}
