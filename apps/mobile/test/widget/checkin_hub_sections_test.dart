import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/checkins/data/models/checkin_model.dart';
import 'package:circle_fitness/features/checkins/domain/checkin_provider.dart';
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
        // P0-FL-59c: the history is drawn for the member signed in.
        checkinUidProvider.overrideWithValue('member-1'),
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

  // P0-FL-2 · journey 9 · the history recovers from errors and shows loading.
  testWidgets('P0-FL-2 a loading history shows an announced indicator, not blank',
      (t) async {
    final handle = t.ensureSemantics();
    await mount(t, const AsyncLoading());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.bySemanticsLabel('Loading check-in history'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('P0-FL-2 a failed history offers "Try again" that re-reads',
      (t) async {
    final handle = t.ensureSemantics();
    var calls = 0;
    var online = false;
    await t.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(ProviderScope(
      overrides: [
        // P0-FL-59c: the history is drawn for the member signed in.
        checkinUidProvider.overrideWithValue('member-1'),
        checkinHistoryProvider.overrideWith((ref) async {
          calls++;
          if (!online) throw Exception('offline');
          return [week(number: 9)];
        }),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: CheckinHubSections()),
        ),
      ),
    ));
    await t.pump();
    await t.pump();

    expect(find.text('Could not load check-ins'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    // Screen readers hear the failure when it appears.
    final region = find.ancestor(
        of: find.text('Could not load check-ins'),
        matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.liveRegion == true));
    expect(region, findsWidgets);

    final before = calls;
    online = true;
    await t.tap(find.text('Try again'));
    await t.pumpAndSettle();

    expect(calls, greaterThan(before));
    expect(find.text('Could not load check-ins'), findsNothing);
    expect(find.text('Week 9 · Energy 3 of 5 · Awaiting reply'), findsOneWidget);
    handle.dispose();
  });

  // P0-FL-2 follow-up · U1 + F2: a retry in flight is visible, a second
  // failure is shown again, and each failure is recorded once.
  testWidgets('P0-FL-2 U1 "Try again" shows progress and is disabled while '
      'the retry is in flight; a second failure is stated again', (t) async {
    final reported = <AppFailure>[];
    setFailureSink(reported.add);
    addTearDown(resetFailureSink);
    var calls = 0;
    final second = Completer<List<WeeklyCheckin>>();
    await t.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(ProviderScope(
      overrides: [
        // P0-FL-59c: the history is drawn for the member signed in.
        checkinUidProvider.overrideWithValue('member-1'),
        checkinHistoryProvider.overrideWith((ref) async {
          calls++;
          if (calls == 1) throw Exception('offline');
          return second.future;
        }),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: CheckinHubSections()),
        ),
      ),
    ));
    await t.pump();
    await t.pump();
    expect(find.text('Could not load check-ins'), findsOneWidget);

    TextButton retryButton() => t.widget<TextButton>(find.ancestor(
        of: find.text('Try again'), matching: find.byType(TextButton)));
    expect(retryButton().onPressed, isNotNull);

    await t.tap(find.text('Try again'));
    await t.pump();

    // In flight: disabled, a progress indicator in place of the icon.
    expect(calls, 2);
    expect(retryButton().onPressed, isNull,
        reason: 'a second tap during the retry must not look like a dead tap');
    expect(
        find.descendant(
            of: find.byType(TextButton),
            matching: find.byType(CircularProgressIndicator)),
        findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsNothing);

    second.completeError(Exception('offline again'));
    await t.pump();
    await t.pump();

    expect(find.text('Could not load check-ins'), findsOneWidget);
    expect(retryButton().onPressed, isNotNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    // F2, checked last so the U1 assertions above prove U1 on their own.
    expect(reported.map((f) => f.origin),
        ['CheckinHubSections.history', 'CheckinHubSections.history'],
        reason: 'one record per failed read, none per rebuild');
    // Nothing new reaches the screen: no exception text.
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('P0-FL-2 U4 the failure row does not overflow at 2x text on a '
      'narrow screen', (t) async {
    await t.binding.setSurfaceSize(const Size(320, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(ProviderScope(
      overrides: [
        // P0-FL-59c: the history is drawn for the member signed in.
        checkinUidProvider.overrideWithValue('member-1'),
        checkinHistoryProvider.overrideWith(
            (ref) => Future<List<WeeklyCheckin>>.error(Exception('offline'))),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2.0)),
          child: child!,
        ),
        home: const Scaffold(
          body: SingleChildScrollView(child: CheckinHubSections()),
        ),
      ),
    ));
    await t.pump();
    await t.pump();
    expect(find.text('Could not load check-ins'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(t.takeException(), isNull, reason: 'no RenderFlex overflow');
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
