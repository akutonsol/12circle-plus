import 'dart:async';

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
