import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/features/checkins/data/models/checkin_model.dart';
import 'package:circle_fitness/features/checkins/presentation/checkin_hub_sections.dart';

/// FIT-023 · the check-in hub's declared controls and history, mounted.
///
/// The rules are proved in `test/unit/checkin_hub_test.dart`. These assert the
/// wiring — that the rule is acted on, not merely written. That distinction
/// mattered on `/profile`, where the decision function was correct and the
/// screen went on rendering the denial, and the mutation survived until it was
/// run.
void main() {
  WeeklyCheckin week({int number = 13, CoachFeedback? feedback}) => WeeklyCheckin(
        id: 'w$number',
        weekNumber: number,
        weekStartDate: DateTime(2026, 9, 7),
        status: CheckinStatus.submitted,
        responses: [CheckinResponse(questionId: 'energy_level', answer: 3)],
        feedback: feedback,
        overallScore: 0.8,
        submittedAt: DateTime(2026, 9, 13),
      );

  Future<void> mount(
    WidgetTester t,
    AsyncValue<List<WeeklyCheckin>> history,
  ) async {
    await t.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(ProviderScope(
      overrides: [
        checkinHistoryProvider.overrideWith((ref) => history.when(
              data: (d) => d,
              error: (e, s) => Future<List<WeeklyCheckin>>.error(e, s),
              loading: () => Completer<List<WeeklyCheckin>>().future,
            )),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: CheckinHubSections()),
        ),
      ),
    ));
    await t.pump();
  }

  testWidgets('FIT-023 both declared controls are present and reachable',
      (t) async {
    final handle = t.ensureSemantics();
    await mount(t, const AsyncData([]));

    for (final label in ['Start check-in', 'Measurements']) {
      expect(find.text(label), findsOneWidget);
      final d = t.getSemantics(find.text(label)).getSemanticsData();
      expect(d.hasFlag(SemanticsFlag.isButton), isTrue, reason: label);
      expect(d.hasAction(SemanticsAction.tap), isTrue, reason: label);

      final size = t.getSize(find
          .ancestor(of: find.text(label), matching: find.byType(GestureDetector))
          .first);
      expect(size.height, greaterThanOrEqualTo(44.0), reason: label);
    }
    handle.dispose();
  });

  testWidgets('FIT-023 a failed history says so, and is NOT "no history"',
      (t) async {
    await mount(t, AsyncError(Exception('offline'), StackTrace.empty));

    expect(find.text('Could not load check-ins'), findsOneWidget);
    // And the way forward stays available — a failed read does not remove the
    // client's ability to start this week's check-in.
    expect(find.text('Start check-in'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('offline'), findsNothing);
  });

  testWidgets('FIT-023 a real history renders the anchor\'s row', (t) async {
    await mount(t, AsyncData([
      week(
          number: 13,
          feedback: CoachFeedback(
            message: '',
            recommendations: const [],
            reviewedAt: DateTime(2026, 9, 14),
            coachName: 'Nadia',
          )),
      week(number: 12),
    ]));

    expect(find.text('Week 13 · Energy 3 of 5 · Nadia replied'), findsOneWidget);
    expect(find.text('Week 12 · Energy 3 of 5 · Awaiting reply'), findsOneWidget);
    expect(find.text('Could not load check-ins'), findsNothing);
  });

  testWidgets('FIT-023 a history row keeps its content as its name', (t) async {
    // Same judgement as FIT-005's conversation rows: the week, the energy and
    // whether the coach replied are what a client needs in order to choose a
    // row, so the action goes in the hint.
    final handle = t.ensureSemantics();
    await mount(t, AsyncData([week(number: 11)]));

    final node = t.getSemantics(find.text('Week 11 · Energy 3 of 5 · Awaiting reply'));
    expect(node.label, contains('Week 11'));
    expect(node.hint, 'Open check-in');
    expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
    handle.dispose();
  });

  testWidgets('FIT-023 rows clear the 44 dp target floor', (t) async {
    await mount(t, AsyncData([week()]));
    final size = t.getSize(find
        .ancestor(
            of: find.text('Week 13 · Energy 3 of 5 · Awaiting reply'),
            matching: find.byType(GestureDetector))
        .first);
    expect(size.height, greaterThanOrEqualTo(44.0));
  });

  testWidgets('FIT-023 an empty history states nothing rather than guessing',
      (t) async {
    // The anchor declares no empty copy, so the screen is quiet and leaves
    // "Start check-in" as the way forward. Writing a sentence would be OD-8.
    await mount(t, const AsyncData([]));
    expect(find.textContaining('Could not load'), findsNothing);
    expect(find.textContaining('Week'), findsNothing);
  });

  testWidgets('FIT-023 History is announced as a heading', (t) async {
    final handle = t.ensureSemantics();
    await mount(t, const AsyncData([]));
    expect(
        t.getSemantics(find.text('History')).getSemanticsData()
            .hasFlag(SemanticsFlag.isHeader),
        isTrue);
    handle.dispose();
  });
}
