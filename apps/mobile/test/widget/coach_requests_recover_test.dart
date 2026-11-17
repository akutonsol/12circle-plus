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

// P0-FL-2 · journey 5 · the coach Requests tab recovers from a failed read.
//
// On main a failed pendingRequestsProvider read rendered "Error loading
// requests" over the raw exception string, with no way to try again and the
// Invite button gone; a failed sentInvitesProvider read rendered as "no invites
// sent" (`valueOrNull ?? []`). Every read the screen makes is overridden, so no
// request leaves the test.

typedef _Rows = List<Map<String, dynamic>>;

const _request = {
  'id': 'r1',
  'client_id': 'c1',
  'request_message': null,
  'profile': {'first_name': 'Ana', 'last_name': 'Lee', 'email': 'ana@x.test'},
};

const _invite = {
  'invitee_email': 'ben@x.test',
  'status': 'pending',
  'created_at': '2026-11-16T09:00:00Z',
};

Widget _dashboard({
  required FutureOr<_Rows> Function() requests,
  required FutureOr<_Rows> Function() invites,
}) => ProviderScope(
  overrides: [
    coachClientsProvider.overrideWith((ref) async => const []),
    clientCheckinsProvider.overrideWith((ref) async => const []),
    clientWorkoutLogsProvider.overrideWith((ref) async => const []),
    coachNotificationsProvider.overrideWith((ref) => Stream.value(const [])),
    currentUserProfileProvider.overrideWith((ref) async => null),
    currentUserDisplayNameProvider.overrideWithValue('Coach'),
    pendingRequestsProvider.overrideWith((ref) async => requests()),
    sentInvitesProvider.overrideWith((ref) async => invites()),
    coachSubmittedCheckinsProvider.overrideWith((ref) async => const []),
    coachLeaderboardProvider.overrideWith((ref) async => const []),
    coachTriageSignalsProvider.overrideWith((ref) async => const []),
  ],
  child: const MaterialApp(home: CoachDashboardScreen()),
);

Future<void> _openRequests(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
  await tester.tap(find.textContaining('Requests').first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Never _offline() => throw Exception('offline: SocketException 42');

void main() {
  _Rows none() => const [];

  testWidgets(
    'a failed requests read says so in plain words, no exception text',
    (tester) async {
      await tester.pumpWidget(_dashboard(requests: _offline, invites: none));
      await _openRequests(tester);

      expect(find.text("Couldn't load requests"), findsOneWidget);
      expect(find.text('Try again'), findsWidgets);
      expect(find.textContaining('Exception'), findsNothing);
      expect(find.textContaining('SocketException'), findsNothing);
      expect(
        find.text('No pending requests'),
        findsNothing,
        reason: 'a failure is not an empty inbox',
      );
      // The way to invite a client stays available while the read is failed.
      expect(find.text('Invite Client by Email'), findsOneWidget);
    },
  );

  testWidgets('"Try again" re-reads the requests and then shows them', (
    tester,
  ) async {
    var calls = 0;
    var online = false;
    _Rows requestsThenRows() {
      calls++;
      if (!online) _offline();
      return const [_request];
    }

    await tester.pumpWidget(
      _dashboard(requests: requestsThenRows, invites: none),
    );
    await _openRequests(tester);
    expect(find.text("Couldn't load requests"), findsOneWidget);
    final before = calls;

    online = true;
    await tester.tap(find.text('Try again').first);
    await tester.pumpAndSettle();

    expect(calls, greaterThan(before), reason: 'the tap re-read the list');
    expect(find.text("Couldn't load requests"), findsNothing);
    expect(find.text('Ana Lee'), findsOneWidget);
  });

  testWidgets('a failed sent-invites read is stated, not shown as none', (
    tester,
  ) async {
    var online = false;
    _Rows invitesThenRows() {
      if (!online) _offline();
      return const [_invite];
    }

    await tester.pumpWidget(
      _dashboard(requests: none, invites: invitesThenRows),
    );
    await _openRequests(tester);

    expect(find.text("Couldn't load sent invites"), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
    // The requests half did arrive and still says so.
    expect(find.text('No pending requests'), findsOneWidget);

    online = true;
    await tester.tap(find.text('Try again').first);
    await tester.pumpAndSettle();

    expect(find.text("Couldn't load sent invites"), findsNothing);
    expect(find.text('ben@x.test'), findsOneWidget);
  });

  testWidgets('sent invites still loading are not shown as none', (
    tester,
  ) async {
    final pending = Completer<_Rows>();
    await tester.pumpWidget(
      _dashboard(requests: none, invites: () => pending.future),
    );
    await _openRequests(tester);

    expect(find.bySemanticsLabel('Loading sent invites'), findsOneWidget);
    pending.complete(const [_invite]);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Loading sent invites'), findsNothing);
    expect(find.text('ben@x.test'), findsOneWidget);
  });

  // P0-FL-2 follow-up · U1 + F2 + U5.
  TextButton retryButton(WidgetTester tester) => tester.widget<TextButton>(
    find.ancestor(
      of: find.text('Try again').first,
      matching: find.byType(TextButton),
    ),
  );
  Finder progressInButton() => find.descendant(
    of: find.byType(TextButton),
    matching: find.byType(CircularProgressIndicator),
  );

  testWidgets('U1 a requests retry in flight disables "Try again" and shows '
      'progress; a second failure is stated again', (tester) async {
    final reported = <AppFailure>[];
    setFailureSink(reported.add);
    addTearDown(resetFailureSink);
    var calls = 0;
    var retried = false;
    final second = Completer<_Rows>();
    // Fails until "Try again" is tapped; the retry then waits on [second].
    Future<_Rows> requests() async {
      calls++;
      if (!retried) _offline();
      return second.future;
    }

    await tester.pumpWidget(_dashboard(requests: requests, invites: none));
    await _openRequests(tester);
    expect(find.text("Couldn't load requests"), findsOneWidget);
    expect(retryButton(tester).onPressed, isNotNull);

    final before = calls;
    retried = true;
    await tester.tap(find.text('Try again').first);
    await tester.pump();

    expect(calls, greaterThan(before));
    expect(retryButton(tester).onPressed, isNull,
        reason: 'disabled while the retry is in flight');
    expect(progressInButton(), findsOneWidget);

    second.completeError(Exception('offline again'));
    await tester.pump();
    await tester.pump();

    expect(find.text("Couldn't load requests"), findsOneWidget);
    expect(retryButton(tester).onPressed, isNotNull);
    expect(progressInButton(), findsNothing);
    // F2, checked last so the U1 assertions above prove U1 on their own.
    expect(
      reported.map((f) => f.origin),
      [
        'CoachDashboardScreen.pendingRequests',
        'CoachDashboardScreen.pendingRequests',
      ],
      reason: 'one record per failed read, none per rebuild',
    );
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('U1 a sent-invites retry in flight disables "Try again" and '
      'shows progress; a second failure is stated again', (tester) async {
    final reported = <AppFailure>[];
    setFailureSink(reported.add);
    addTearDown(resetFailureSink);
    var calls = 0;
    var retried = false;
    final second = Completer<_Rows>();
    // Fails until "Try again" is tapped; the retry then waits on [second].
    Future<_Rows> invites() async {
      calls++;
      if (!retried) _offline();
      return second.future;
    }

    await tester.pumpWidget(_dashboard(requests: none, invites: invites));
    await _openRequests(tester);
    expect(find.text("Couldn't load sent invites"), findsOneWidget);

    final before = calls;
    retried = true;
    await tester.tap(find.text('Try again').first);
    await tester.pump();

    expect(calls, greaterThan(before));
    expect(retryButton(tester).onPressed, isNull);
    expect(progressInButton(), findsOneWidget);

    second.completeError(Exception('offline again'));
    await tester.pump();
    await tester.pump();

    expect(find.text("Couldn't load sent invites"), findsOneWidget);
    expect(retryButton(tester).onPressed, isNotNull);
    expect(progressInButton(), findsNothing);
    // F2, checked last so the U1 assertions above prove U1 on their own.
    expect(
      reported.map((f) => f.origin),
      ['CoachDashboardScreen.sentInvites', 'CoachDashboardScreen.sentInvites'],
      reason: 'one record per failed read, none per rebuild',
    );
  });

  testWidgets('U4 the requests failure does not overflow at 2x text, 320 wide',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 900),
          textScaler: TextScaler.linear(2.0),
        ),
        child: _dashboard(requests: _offline, invites: none),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    // At 2x on 320 wide the tab bar scrolls; bring the tab into view first.
    await tester.ensureVisible(find.textContaining('Requests').first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Requests').first);
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load requests"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    // The Invite button sits above the failure in the same list.
    expect(find.text('Invite Client by Email'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'no RenderFlex overflow');
  });

  testWidgets('U5 the failure helper copy is at alpha 0.8', (tester) async {
    await tester.pumpWidget(_dashboard(requests: _offline, invites: none));
    await _openRequests(tester);
    final helper = tester.widget<Text>(
      find.text('Check your connection and try again.'),
    );
    expect(helper.style!.color!.a, closeTo(0.8, 0.01));
  });

  testWidgets('arrived data is unchanged: empty copy, rows, invites', (
    tester,
  ) async {
    await tester.pumpWidget(_dashboard(requests: none, invites: none));
    await _openRequests(tester);
    expect(find.text('No pending requests'), findsOneWidget);
    expect(find.text('SENT INVITES'), findsNothing);
    expect(find.textContaining("Couldn't load"), findsNothing);
  });
}
