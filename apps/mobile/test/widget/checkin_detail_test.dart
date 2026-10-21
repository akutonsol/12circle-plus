import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/features/checkins/data/models/checkin_model.dart';
import 'package:circle_fitness/features/checkins/domain/checkin_provider.dart';
import 'package:circle_fitness/features/checkins/presentation/checkin_detail_screen.dart';

/// FIT-024 · "Check-in detail — with the coach's reply" and
/// FIT-025 · "Awaiting reply — the empty state with a real answer".
///
/// ── WHAT THIS REPLACED ─────────────────────────────────────────────────────
/// A 23-line stub reading "Check-in details coming soon" — and FIT-023's
/// history rows, added earlier in this programme, navigated straight into it.
/// The dead end was mine.
void main() {
  WeeklyCheckin week({
    int number = 13,
    CheckinStatus status = CheckinStatus.reviewed,
    CoachFeedback? feedback,
    String? notes = 'Travel next week.',
    List<CheckinResponse> extra = const [],
  }) =>
      WeeklyCheckin(
        id: 'w$number',
        weekNumber: number,
        weekStartDate: DateTime(2026, 8, 25),
        status: status,
        responses: [
          CheckinResponse(questionId: 'energy', answer: 3),
          CheckinResponse(questionId: 'sleep_hours_avg', answer: 7.0),
          if (notes != null) CheckinResponse(questionId: 'notes', answer: notes),
          ...extra,
        ],
        feedback: feedback,
        overallScore: 0.8,
        submittedAt: DateTime(2026, 8, 31, 9, 12),
      );

  CoachFeedback reply({String coach = 'Nadia'}) => CoachFeedback(
        message: 'Two is fine.',
        recommendations: const [],
        reviewedAt: DateTime(2026, 9, 1),
        coachName: coach,
      );

  Future<void> mount(WidgetTester t, WeeklyCheckin? selected) async {
    await t.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(ProviderScope(
      overrides: [selectedCheckinProvider.overrideWith((ref) => selected)],
      child: const MaterialApp(home: CheckinDetailScreen()),
    ));
    await t.pump();
  }

  group('FIT-024 the reply is the one card', () {
    testWidgets('the board\'s structure, from real values', (t) async {
      await mount(t, week(feedback: reply()));

      expect(find.text('Week 13'), findsOneWidget);
      expect(find.text('Sent Monday 31 August'), findsOneWidget);
      expect(find.text('What you wrote'), findsOneWidget);
      expect(find.text('Travel next week.'), findsOneWidget);
      expect(find.text('Nadia'), findsOneWidget);
      expect(find.text('Replied Tuesday'), findsOneWidget);
      expect(find.text('Two is fine.'), findsOneWidget);
      expect(find.text('Reply to Nadia'), findsOneWidget);
    });

    testWidgets('answers read as label-value rows', (t) async {
      await mount(t, week(feedback: reply()));
      expect(find.text('Energy'), findsOneWidget);
      expect(find.text('3 of 5'), findsOneWidget);
      expect(find.text('Sleep'), findsOneWidget);
      expect(find.text('7 hours average'), findsOneWidget);
    });

    testWidgets('energy is STATED, never interpreted', (t) async {
      // The board writes "Steady". Mapping 1-5 onto three words is OD-16, the
      // same decision FIT-023's history row leaves alone. If this fails, it
      // was made silently.
      await mount(t, week(feedback: reply()));
      for (final w in ['Steady', 'Low', 'Strong']) {
        expect(find.text(w), findsNothing, reason: w);
      }
    });

    testWidgets('a reply with no coach name still offers a reply', (t) async {
      await mount(t, week(feedback: reply(coach: '  ')));
      expect(find.text('Reply to your coach'), findsOneWidget);
      expect(find.textContaining('Reply to  '), findsNothing,
          reason: 'a blank where a name should be is the bug this guards');
    });

    testWidgets('a week with no note omits the section', (t) async {
      await mount(t, week(feedback: reply(), notes: null));
      expect(find.text('What you wrote'), findsNothing);
    });
  });

  group('FIT-025 awaiting a reply', () {
    testWidgets('says so, and does not offer a reply button', (t) async {
      await mount(t, week(status: CheckinStatus.submitted));

      expect(find.text('No reply yet'), findsOneWidget);
      expect(find.textContaining('Reply to'), findsNothing,
          reason: 'there is nothing to reply to yet');
      expect(find.text('Your coach has it. Their reply will appear here.'),
          findsOneWidget);
    });

    testWidgets('a PENDING week says nothing was sent', (t) async {
      // Not yet sent and not yet answered are different, and the screen must
      // not tell a client their coach has something they never submitted.
      await mount(t, week(status: CheckinStatus.pending));
      expect(find.text('This check-in has not been sent yet.'), findsOneWidget);
      expect(find.textContaining('has it'), findsNothing);
    });

    testWidgets('no coach schedule is asserted', (t) async {
      // The board reads "<coach> reviews check-ins on Sundays and Mondays."
      // That schedule is not in this product's data — OD-20. Claiming it would
      // be inventing a commitment on a coach's behalf.
      await mount(t, week(status: CheckinStatus.submitted));
      // Weekday names are fine where they are a FACT — "Sent Monday 31
      // August" is when the client sent it. What must not appear is a claim
      // about when the coach will look.
      expect(find.textContaining('reviews check-ins'), findsNothing);
      expect(find.textContaining('Sundays and Mondays'), findsNothing);
      expect(find.textContaining('within a day'), findsNothing);
      expect(find.textContaining('usually'), findsNothing);
    });

    testWidgets('no gendered pronoun is used for a coach', (t) async {
      // The board writes "She usually replies" because Nadia is its example.
      // Applying that to a real coach would misgender them.
      await mount(t, week(status: CheckinStatus.submitted));
      for (final p in [' She ', ' she ', ' He ', ' he ', ' Her ', ' his ']) {
        expect(find.textContaining(p), findsNothing, reason: p);
      }
    });
  });

  testWidgets('FIT-024 opened with nothing selected says so', (t) async {
    // The screen is routable directly. Rendering an empty week as though it
    // were the client's would be a fabricated state.
    await mount(t, null);
    expect(find.text('Open a check-in from your history'), findsOneWidget);
    expect(find.text('What you wrote'), findsNothing);
  });

  testWidgets('FIT-024 Back is named and pressable', (t) async {
    final handle = t.ensureSemantics();
    await mount(t, week(feedback: reply()));

    final d = t.getSemantics(find.bySemanticsLabel('Back')).getSemanticsData();
    expect(d.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(d.hasAction(SemanticsAction.tap), isTrue);

    final size = t.getSize(find
        .ancestor(of: find.byIcon(Icons.arrow_back), matching: find.byType(GestureDetector))
        .first);
    expect(size.height, greaterThanOrEqualTo(44.0));
    handle.dispose();
  });
}
