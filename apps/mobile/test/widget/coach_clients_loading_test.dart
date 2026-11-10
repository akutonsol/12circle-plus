import 'dart:async';

import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/checkins/domain/checkin_provider.dart';
import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart';
import 'package:circle_fitness/features/dashboard/domain/still_reading.dart';
import 'package:circle_fitness/features/dashboard/presentation/coach_dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// D4 · the coach dashboard said "No clients found" while it was still reading.
//
// The screen reads its three lists with `.valueOrNull ?? []`. That keeps a
// FAILED read apart (F-15) but not a read still in flight: until the roster
// arrived, a coach with clients was told they had none. The same collapse put
// "No check-ins today" and "No workouts this week" on the other two tabs, and
// zeros in the summary strip, for as long as each read took.
//
// Every read the screen makes is overridden, so no request leaves the test.

typedef _Rows = List<Map<String, dynamic>>;

Widget _dashboard({
  required FutureOr<_Rows> Function() clients,
  required FutureOr<_Rows> Function() checkins,
  required FutureOr<_Rows> Function() workouts,
}) =>
    ProviderScope(
      overrides: [
        coachClientsProvider.overrideWith((ref) => clients()),
        clientCheckinsProvider.overrideWith((ref) => checkins()),
        clientWorkoutLogsProvider.overrideWith((ref) => workouts()),
        coachNotificationsProvider.overrideWith((ref) => Stream.value(const [])),
        currentUserProfileProvider.overrideWith((ref) async => null),
        currentUserDisplayNameProvider.overrideWithValue('Coach'),
        pendingRequestsProvider.overrideWith((ref) async => const []),
        coachSubmittedCheckinsProvider.overrideWith((ref) async => const []),
        coachLeaderboardProvider.overrideWith((ref) async => const []),
      ],
      child: const MaterialApp(home: CoachDashboardScreen()),
    );

void main() {
  final pending = Completer<_Rows>();
  _Rows empty() => const [];

  testWidgets('D4 a roster still being read is not "No clients found"',
      (tester) async {
    await tester.pumpWidget(_dashboard(
        clients: () => pending.future,
        checkins: () => pending.future,
        workouts: () => pending.future));
    await tester.pump();

    expect(find.text('No clients found'), findsNothing,
        reason: 'the roster has not arrived; nothing is known about it yet');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('D4 the summary strip does not count a list it has not read',
      (tester) async {
    await tester.pumpWidget(_dashboard(
        clients: () => pending.future,
        checkins: () => pending.future,
        workouts: () => pending.future));
    await tester.pump();

    expect(find.text('0'), findsNothing,
        reason: 'four zeros were shown before any of the four was known');
  });

  testWidgets('D4 the Check-Ins and Workouts tabs wait for their reads too',
      (tester) async {
    await tester.pumpWidget(_dashboard(
        clients: empty,
        checkins: () => pending.future,
        workouts: () => pending.future));
    await tester.pump();

    await tester.tap(find.text('Check-Ins'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('No check-ins today'), findsNothing);

    await tester.tap(find.text('Workouts').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('No workouts this week'), findsNothing);
  });

  testWidgets('D4 the next coach to sign in is not told they have no clients',
      (tester) async {
    // The real roster provider watches `currentUserProvider`. Signing out
    // recomputes it to `[]`; signing in reloads it from there. This drives the
    // same dependency change with a stand-in for the signed-in account.
    final account = StateProvider<String?>((ref) => null);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        coachClientsProvider.overrideWith((ref) async {
          if (ref.watch(account) == null) return const <Map<String, dynamic>>[];
          return pending.future;
        }),
        clientCheckinsProvider.overrideWith((ref) async => const []),
        clientWorkoutLogsProvider.overrideWith((ref) async => const []),
        coachNotificationsProvider.overrideWith((ref) => Stream.value(const [])),
        currentUserProfileProvider.overrideWith((ref) async => null),
        currentUserDisplayNameProvider.overrideWithValue('Coach'),
        pendingRequestsProvider.overrideWith((ref) async => const []),
        coachSubmittedCheckinsProvider.overrideWith((ref) async => const []),
        coachLeaderboardProvider.overrideWith((ref) async => const []),
      ],
      child: const MaterialApp(home: CoachDashboardScreen()),
    ));
    // The screen re-reads every list after its first frame; let that settle.
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
    expect(find.text('No clients found'), findsOneWidget,
        reason: 'signed out: the roster really is empty');

    final scope = ProviderScope.containerOf(
        tester.element(find.byType(CoachDashboardScreen)));
    scope.read(account.notifier).state = 'coach-b';
    await tester.pump();

    expect(find.text('No clients found'), findsNothing,
        reason: "coach B's roster has not arrived yet");
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('D4 an empty roster that HAS arrived still says so',
      (tester) async {
    // The fix must not hide a real answer: a coach with no clients is told.
    await tester.pumpWidget(
        _dashboard(clients: empty, checkins: empty, workouts: empty));
    await tester.pump();

    expect(find.text('No clients found'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('D4 a failed roster read still says it failed', (tester) async {
    await tester.pumpWidget(_dashboard(
        clients: () => throw Exception('offline'),
        checkins: empty,
        workouts: empty));
    await tester.pump();

    expect(find.text('Could not load your clients'), findsOneWidget);
    expect(find.text('No clients found'), findsNothing);
  });

  group('D4 reloads (the shapes Riverpod hands the screen)', () {
    test('signing in after a sign-out is still reading', () {
      // Signing out recomputes the roster to `[]`; the next sign-in reloads
      // holding that empty value. `hasValue` is true, which is why the check
      // cannot be `!hasValue`.
      final afterSignOut = const AsyncLoading<_Rows>()
          .copyWithPrevious(const AsyncData<_Rows>([]), isRefresh: false);
      expect(afterSignOut.hasValue, isTrue, reason: 'guard the premise');
      expect(stillReading(afterSignOut), isTrue);
    });

    test('a reload that holds rows keeps showing them', () {
      // A realtime tick or a token refresh re-reads the roster. It must not
      // blank a list the coach is looking at.
      final tick = const AsyncLoading<_Rows>().copyWithPrevious(
          const AsyncData<_Rows>([{'id': 'c1'}]), isRefresh: false);
      expect(stillReading(tick), isFalse);
    });

    test('an arrived empty list is an answer, not a read', () {
      expect(stillReading(const AsyncData<_Rows>([])), isFalse);
    });
  });
}
