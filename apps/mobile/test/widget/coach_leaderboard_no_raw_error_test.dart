import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/checkins/domain/checkin_provider.dart';
import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart';
import 'package:circle_fitness/features/dashboard/domain/coach_triage_provider.dart';
import 'package:circle_fitness/features/dashboard/presentation/coach_dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// P0-FL-5 · A · the coach Leaderboard tab never shows the raw exception.
//
// At 918c8dc a failed coachLeaderboardProvider read rendered "Error loading
// leaderboard" over `e.toString()` — database internals on screen — with no
// way to read it again. Every read the dashboard makes is overridden, so no
// request leaves the test.

typedef _Rows = List<Map<String, dynamic>>;

const _secret =
    'PostgrestException(message: new row violates row-level security policy '
    'SECRET_TABLE_X, code: 42501)';

Never _fail() => throw Exception(_secret);

Widget _dashboard(FutureOr<_Rows> Function() leaderboard) => ProviderScope(
      overrides: [
        coachClientsProvider.overrideWith((ref) async => const []),
        clientCheckinsProvider.overrideWith((ref) async => const []),
        clientWorkoutLogsProvider.overrideWith((ref) async => const []),
        coachNotificationsProvider
            .overrideWith((ref) => Stream.value(const [])),
        currentUserProfileProvider.overrideWith((ref) async => null),
        currentUserDisplayNameProvider.overrideWithValue('Coach'),
        pendingRequestsProvider.overrideWith((ref) async => const []),
        sentInvitesProvider.overrideWith((ref) async => const []),
        coachSubmittedCheckinsProvider.overrideWith((ref) async => const []),
        coachLeaderboardProvider.overrideWith((ref) async => leaderboard()),
        coachTriageSignalsProvider.overrideWith((ref) async => const []),
      ],
      child: const MaterialApp(home: CoachDashboardScreen()),
    );

Future<void> _openLeaderboard(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
  await tester.ensureVisible(find.text('Leaderboard').first);
  await tester.pump();
  await tester.tap(find.text('Leaderboard').first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets(
      'a failed leaderboard read says so in plain words, with no '
      'exception text, and is recorded once', (tester) async {
    final reported = <AppFailure>[];
    setFailureSink(reported.add);
    addTearDown(resetFailureSink);

    await tester.pumpWidget(_dashboard(_fail));
    await _openLeaderboard(tester);

    // The defect first: the raw exception text was on screen.
    expect(find.textContaining('SECRET_TABLE_X'), findsNothing);
    expect(find.textContaining('row-level security'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.text("Couldn't load the leaderboard"), findsOneWidget);
    expect(find.text('Check your connection and try again.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('No scores yet today'), findsNothing,
        reason: 'a failure is not an empty leaderboard');
    expect(
      reported.map((f) => f.origin),
      ['CoachDashboardScreen.leaderboard'],
    );
    expect(reported.single.error.toString(), contains('SECRET_TABLE_X'),
        reason: 'the raw error is recorded, not shown');
  });

  testWidgets(
      '"Try again" is busy while the re-read is in flight, then '
      'shows the arrived rows', (tester) async {
    var calls = 0;
    var retried = false;
    final second = Completer<_Rows>();
    Future<_Rows> leaderboard() async {
      calls++;
      if (!retried) _fail();
      return second.future;
    }

    await tester.pumpWidget(_dashboard(leaderboard));
    await _openLeaderboard(tester);
    expect(find.text("Couldn't load the leaderboard"), findsOneWidget);

    final before = calls;
    retried = true;
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(calls, greaterThan(before), reason: 'the tap re-read the board');
    final button = tester.widget<TextButton>(find.ancestor(
        of: find.text('Try again'), matching: find.byType(TextButton)));
    expect(button.onPressed, isNull, reason: 'disabled while in flight');

    second.complete(const [
      {
        'total_score': 80,
        'profile': {'first_name': 'Ana', 'last_name': 'Lee'},
      },
    ]);
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load the leaderboard"), findsNothing);
    expect(find.text('Ana Lee'), findsOneWidget);
  });

  // Review Q1: one record per failed read, none per rebuild (mirrors #173's
  // F2 test). A record made from the error builder would add one per rebuild.
  testWidgets(
      'Q1 a failure is recorded exactly once however often the error '
      'rebuilds; a failed retry is recorded once more', (tester) async {
    final reported = <AppFailure>[];
    setFailureSink(reported.add);
    addTearDown(resetFailureSink);
    var calls = 0;
    Future<_Rows> leaderboard() async {
      calls++;
      _fail();
    }

    await tester.pumpWidget(_dashboard(leaderboard));
    await _openLeaderboard(tester);
    expect(find.text("Couldn't load the leaderboard"), findsOneWidget);
    expect(reported.map((f) => f.origin), ['CoachDashboardScreen.leaderboard']);

    // Force the screen (and so the leaderboard tab) to rebuild while the
    // failure is on screen.
    final screen = tester.element(find.byType(CoachDashboardScreen));
    for (var i = 0; i < 5; i++) {
      screen.markNeedsBuild();
      await tester.pump();
    }
    expect(find.text("Couldn't load the leaderboard"), findsOneWidget);
    expect(reported.length, 1, reason: 'a rebuild is not a second failure');

    final before = calls;
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();
    expect(calls, greaterThan(before), reason: 'the tap re-read the board');
    expect(find.text("Couldn't load the leaderboard"), findsOneWidget);
    expect(
      reported.map((f) => f.origin),
      [
        'CoachDashboardScreen.leaderboard',
        'CoachDashboardScreen.leaderboard',
      ],
      reason: 'one record per failed read, none per rebuild',
    );
  });

  testWidgets('arrived data is unchanged: the empty copy', (tester) async {
    await tester.pumpWidget(_dashboard(() => const []));
    await _openLeaderboard(tester);
    expect(find.text('No scores yet today'), findsOneWidget);
    expect(find.textContaining("Couldn't load"), findsNothing);
  });
}
