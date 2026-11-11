import 'dart:async';

import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/checkins/domain/checkin_provider.dart';
import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart';
import 'package:circle_fitness/features/dashboard/domain/coach_triage_provider.dart';
import 'package:circle_fitness/features/dashboard/presentation/coach_dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// F-15 reached one tab of three.
//
// A failed roster read says "Could not load your clients". A failed check-ins
// or workouts read still became `const []`, so the Check-Ins tab told the coach
// "No check-ins today", the Workouts tab "No workouts this week", and the
// summary strip counted the empty stand-in: "Checked In 0", "Needs Attention
// 0" — a failure shown as nobody needing them. And the failed state's own line,
// "Pull to refresh to try again", sat on a surface that could not be pulled.
//
// Every read the screen makes is overridden, so no request leaves the test.

typedef _Rows = List<Map<String, dynamic>>;

const _client = {'id': 'c1', 'first_name': 'Ana', 'last_name': 'Lee'};

Widget _dashboard({
  required FutureOr<_Rows> Function() clients,
  required FutureOr<_Rows> Function() checkins,
  required FutureOr<_Rows> Function() workouts,
}) =>
    ProviderScope(
      overrides: [
        coachClientsProvider.overrideWith((ref) async => clients()),
        clientCheckinsProvider.overrideWith((ref) async => checkins()),
        clientWorkoutLogsProvider.overrideWith((ref) async => workouts()),
        coachNotificationsProvider.overrideWith((ref) => Stream.value(const [])),
        currentUserProfileProvider.overrideWith((ref) async => null),
        currentUserDisplayNameProvider.overrideWithValue('Coach'),
        pendingRequestsProvider.overrideWith((ref) async => const []),
        coachSubmittedCheckinsProvider.overrideWith((ref) async => const []),
        coachLeaderboardProvider.overrideWith((ref) async => const []),
        coachTriageSignalsProvider.overrideWith((ref) async => const []),
      ],
      child: const MaterialApp(home: CoachDashboardScreen()),
    );

Future<void> _settle(WidgetTester tester) async {
  // The screen re-reads every list after its first frame; let that settle.
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
}

Future<void> _open(WidgetTester tester, String tab) async {
  await tester.tap(find.text(tab).first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Never _offline() => throw Exception('offline');

void main() {
  _Rows empty() => const [];
  _Rows roster() => const [_client];

  testWidgets('a failed check-ins read is not "No check-ins today"',
      (tester) async {
    await tester.pumpWidget(
        _dashboard(clients: roster, checkins: _offline, workouts: empty));
    await _settle(tester);
    await _open(tester, 'Check-Ins');

    expect(find.text('No check-ins today'), findsNothing,
        reason: 'the read failed; nothing is known about this week');
    expect(find.text('Could not load check-ins'), findsOneWidget);
  });

  testWidgets('a failed workouts read is not "No workouts this week"',
      (tester) async {
    await tester.pumpWidget(
        _dashboard(clients: roster, checkins: empty, workouts: _offline));
    await _settle(tester);
    await _open(tester, 'Workouts');

    expect(find.text('No workouts this week'), findsNothing,
        reason: 'the read failed; nothing is known about this week');
    expect(find.text('Could not load workouts'), findsOneWidget);
  });

  testWidgets('the summary strip does not count a list it could not read',
      (tester) async {
    // One client arrived; both weekly reads failed. "Checked In", "Needs
    // Attention" and "Workouts" are unknown, not zero.
    await tester.pumpWidget(
        _dashboard(clients: roster, checkins: _offline, workouts: _offline));
    await _settle(tester);

    expect(find.text('0'), findsNothing,
        reason: 'three zeros stood in for three unknowns');
    expect(find.text('1'), findsOneWidget, reason: 'the roster did arrive');
  });

  testWidgets('a failed roster read is not counted as 0 clients',
      (tester) async {
    await tester.pumpWidget(
        _dashboard(clients: _offline, checkins: empty, workouts: empty));
    await _settle(tester);

    expect(find.text('Could not load your clients'), findsOneWidget);
    // The weekly reads arrived empty, which IS an answer: three real zeros.
    expect(find.text('0'), findsNWidgets(3),
        reason: 'the Clients chip must not be one of them');
  });

  testWidgets('"Pull to refresh to try again" does try again', (tester) async {
    var calls = 0;
    var online = false;
    _Rows checkinsThenRows() {
      calls++;
      if (!online) _offline();
      return const [
        {'user_id': 'c1', 'status': 'submitted', 'mood': 4}
      ];
    }

    await tester.pumpWidget(_dashboard(
        clients: roster, checkins: checkinsThenRows, workouts: empty));
    await _settle(tester);
    await _open(tester, 'Check-Ins');
    expect(find.text('Could not load check-ins'), findsOneWidget);
    final before = calls;

    online = true;
    await tester.fling(
        find.text('Could not load check-ins'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(calls, greaterThan(before), reason: 'the pull re-read the list');
    expect(find.text('Could not load check-ins'), findsNothing);
    expect(find.text('Ana Lee'), findsOneWidget,
        reason: "the retried read's row is shown");
  });

  testWidgets('the failed roster state can be pulled too', (tester) async {
    var online = false;
    _Rows rosterThenRows() {
      if (!online) _offline();
      return const [_client];
    }

    await tester.pumpWidget(
        _dashboard(clients: rosterThenRows, checkins: empty, workouts: empty));
    await _settle(tester);
    expect(find.text('Could not load your clients'), findsOneWidget);

    online = true;
    await tester.fling(
        find.text('Could not load your clients'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(find.text('Could not load your clients'), findsNothing);
  });

  testWidgets('arrived empty weeks still say so', (tester) async {
    // The fix must not hide a real answer.
    await tester.pumpWidget(
        _dashboard(clients: roster, checkins: empty, workouts: empty));
    await _settle(tester);
    await _open(tester, 'Check-Ins');
    expect(find.text('No check-ins today'), findsOneWidget);
    await _open(tester, 'Workouts');
    expect(find.text('No workouts this week'), findsOneWidget);
  });
}
