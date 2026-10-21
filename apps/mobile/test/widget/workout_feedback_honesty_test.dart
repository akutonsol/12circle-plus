import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/workout/presentation/active_workout_screen.dart';

/// F-23 — the session-complete dialog told the client their feedback had
/// reached their coach when it had not.
///
/// ── THE DEFECT ─────────────────────────────────────────────────────────────
/// `_saveFeedback` ended `catch (_) {}` and then set `_submitted = true`
/// unconditionally. Every failure — no network, RLS refusal, a malformed row —
/// produced the same screen as success: a green tick and the words
/// **"Feedback sent to your coach!"**. The dialog then offered only "Back to
/// Home", so the notes were gone and unrecoverable. The client had written
/// something for their coach, been told it was delivered, and it was not.
///
/// That is a fabricated UI state, which is the specific thing this programme's
/// brief forbids. It is also the F-15 error→empty pattern in its most harmful
/// form: not a failure shown as emptiness, but a failure shown as success.
///
/// ── WHY THREE OUTCOMES AND NOT TWO ─────────────────────────────────────────
/// The write is two inserts that fail independently. If the feedback row saves
/// but the coach's notification does not, retracting the save would be a second
/// falsehood — the notes *are* stored. And a client with **no coach at all**
/// was also being told their feedback had been sent to one. So:
///
///   failed    → nothing written; keep the form, keep the values, offer a retry
///   saved     → written, nobody notified; say saved, do not claim delivery
///   delivered → written and the coach pinged; the original line is true
///
/// ── WHY THE DIALOG TAKES A `submit` CALLBACK ───────────────────────────────
/// Its real path reads `Supabase.instance`, which no widget test can provide,
/// so before this change the defect was unreachable from a test — which is
/// part of why it survived. The seam exists to make each outcome assertable.
void main() {
  const failure = 'Could not send your feedback. Check your connection and try again.';
  const delivered = 'Feedback sent to your coach!';
  const saved = 'Feedback saved.';

  /// The primary action is `Done` — FIT-018's word. It said `Submit` until
  /// that anchor was built; the honesty properties below are unchanged, only
  /// the label moved. See QA_EVIDENCE §3at.
  ///
  /// The dialog is taller than the default 800x600 test surface, so Done
  /// falls outside it and a tap silently misses — which is exactly how a
  /// trivially-passing test gets written.
  ///
  /// The width is 700 and **that is not the phone width on purpose.** At 420 dp
  /// this harness reported `A RenderFlex overflowed by 18 pixels` from the
  /// Duration/Calories/Idle row. Widget tests render in Ahem, where every glyph
  /// is a full em square, so text measures wider than any real font — the
  /// overflow is the harness, not the product. That was settled by measuring on
  /// the device instead: `integration_test/fit018_complete_dialog_device_test`
  /// mounts the same dialog on `emulator-5554` at 411, 390 and 360 dp with the
  /// real font and reports zero overflows at all three, with the row at
  /// 283.4 / 262.0 / 232.0 dp inside its constraints.
  ///
  /// So layout is asserted on the device, where the measurement means
  /// something, and this file gets a surface wide enough that Ahem's inflation
  /// cannot drown the behaviour it is actually testing.
  Future<void> phone(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(700, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));
  }

  Future<void> open(
    WidgetTester t, {
    required FeedbackDelivery outcome,
    VoidCallback? onDone,
  }) async {
    await phone(t);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WorkoutCompleteDialog(
          title: 'Upper Body A',
          duration: '42:10',
          calories: 310,
          sessionId: 'session-1',
          onDone: onDone ?? () {},
          submit: ({required rating, required energy, required difficulty, required notes}) async =>
              outcome,
        ),
      ),
    ));
    await t.pumpAndSettle();
  }

  /// Done is disabled until an overall rating is given, so every test has to
  /// rate first. One star is enough.
  Future<void> rateAndSubmit(WidgetTester t) async {
    await t.tap(find.byIcon(Icons.star_border_rounded).first);
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Done'));
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
  }

  testWidgets('F-23 a failed save does NOT claim the coach received anything',
      (t) async {
    await open(t, outcome: FeedbackDelivery.failed);
    await rateAndSubmit(t);

    // The defect, stated as an assertion.
    expect(find.text(delivered), findsNothing);
    expect(find.text(saved), findsNothing);
    expect(find.text(failure), findsOneWidget);
  });

  testWidgets('F-23 a failed save keeps the form, the values and a way back in',
      (t) async {
    await open(t, outcome: FeedbackDelivery.failed);
    await rateAndSubmit(t);

    // The notes field is still there — losing what they wrote would make the
    // retry worthless.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('How was the workout?'), findsOneWidget);
    // And the action says what it now does.
    expect(find.text('Try Again'), findsOneWidget);
    expect(find.text('Done'), findsNothing);
  });

  testWidgets('F-23 the raw exception is never shown', (t) async {
    // F-2 and F-16 were raised about exactly this: `$e` interpolated into
    // user-facing text. The message is fixed copy in the voice this screen
    // already uses for `_RestoreFailedView`.
    await open(t, outcome: FeedbackDelivery.failed);
    await rateAndSubmit(t);

    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('PostgrestException'), findsNothing);
  });

  testWidgets('F-23 a retry that succeeds reaches the success state', (t) async {
    // The form has to be genuinely usable again, not merely present.
    var attempt = 0;
    await phone(t);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WorkoutCompleteDialog(
          title: 'Upper Body A',
          duration: '42:10',
          calories: 310,
          onDone: () {},
          submit: ({required rating, required energy, required difficulty, required notes}) async {
            attempt++;
            return attempt == 1 ? FeedbackDelivery.failed : FeedbackDelivery.delivered;
          },
        ),
      ),
    ));
    await t.pumpAndSettle();

    await rateAndSubmit(t);
    expect(find.text(failure), findsOneWidget);

    await t.ensureVisible(find.text('Try Again'));
    await t.tap(find.text('Try Again'));
    await t.pumpAndSettle();

    expect(attempt, 2);
    expect(find.text(delivered), findsOneWidget);
    expect(find.text(failure), findsNothing);
  });

  testWidgets('F-23 saved-but-not-delivered does not claim a coach got it',
      (t) async {
    // A client with no coach, or a coach notification that failed. The notes
    // are stored; nobody was told.
    await open(t, outcome: FeedbackDelivery.saved);
    await rateAndSubmit(t);

    expect(find.text(saved), findsOneWidget);
    expect(find.text(delivered), findsNothing);
    expect(find.text(failure), findsNothing);
    // It is still a success, so the form is done with.
    expect(find.text('Back to Home'), findsOneWidget);
  });

  testWidgets('F-23 a real delivery still says so', (t) async {
    // The fix must not have made the screen uselessly vague in the good case.
    await open(t, outcome: FeedbackDelivery.delivered);
    await rateAndSubmit(t);

    expect(find.text(delivered), findsOneWidget);
    expect(find.text(saved), findsNothing);
  });

  testWidgets('F-23 Done stays disabled until the client actually rates',
      (t) async {
    // Pre-existing behaviour the change must not have loosened: an unrated
    // submit would write a row that says nothing.
    var submits = 0;
    await phone(t);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WorkoutCompleteDialog(
          title: 'Upper Body A',
          duration: '42:10',
          calories: 310,
          onDone: () {},
          submit: ({required rating, required energy, required difficulty, required notes}) async {
            submits++;
            return FeedbackDelivery.delivered;
          },
        ),
      ),
    ));
    await t.pumpAndSettle();

    await t.ensureVisible(find.text('Done'));
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
    expect(submits, 0);
    expect(find.text(delivered), findsNothing);
  });

  testWidgets('F-23 the rating the client gave is what gets submitted',
      (t) async {
    int? seen;
    await phone(t);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WorkoutCompleteDialog(
          title: 'Upper Body A',
          duration: '42:10',
          calories: 310,
          onDone: () {},
          submit: ({required rating, required energy, required difficulty, required notes}) async {
            seen = rating;
            return FeedbackDelivery.delivered;
          },
        ),
      ),
    ));
    await t.pumpAndSettle();

    // Fourth star of the "Overall" row.
    await t.tap(find.byIcon(Icons.star_border_rounded).at(3));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Done'));
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();

    expect(seen, 4);
  });

  group('F-23 deliveryFor — what the database did, mapped to what we say', () {
    // The widget tests above inject the outcome, so they say nothing about how
    // the real path decides it. This is that decision, and the mixed cases are
    // the whole reason it is not a boolean.
    test('a failed feedback insert is a failure, coach or no coach', () {
      expect(deliveryFor(saved: false, coachId: 'c1', notified: false),
          FeedbackDelivery.failed);
      expect(deliveryFor(saved: false, coachId: null, notified: false),
          FeedbackDelivery.failed);
    });

    test('no coach means saved, never delivered', () {
      expect(deliveryFor(saved: true, coachId: null, notified: false),
          FeedbackDelivery.saved);
    });

    test('a failed NOTIFICATION does not retract the save', () {
      // The notes are in workout_feedback. Reporting a failure would send the
      // client to re-enter something already stored, and a second success
      // would show the coach the same feedback twice.
      expect(deliveryFor(saved: true, coachId: 'c1', notified: false),
          FeedbackDelivery.saved);
    });

    test('saved and notified is the only outcome that claims delivery', () {
      expect(deliveryFor(saved: true, coachId: 'c1', notified: true),
          FeedbackDelivery.delivered);
    });
  });
}
