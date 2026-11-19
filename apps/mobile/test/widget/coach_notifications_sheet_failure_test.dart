import 'dart:async';

import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/checkins/domain/checkin_provider.dart';
import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart';
import 'package:circle_fitness/features/dashboard/domain/coach_triage_provider.dart';
import 'package:circle_fitness/features/dashboard/presentation/coach_dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

// P0-FL-14 · the coach's bell and Notifications sheet during a failed read.
//
// At 2ecd6e2 the sheet read `coachNotificationsProvider.valueOrNull ?? []`, so
// a failure was drawn as "No notifications yet", and the bell's count read 0
// (no badge) — the coach told nothing was waiting. The real provider is
// covered by coach_notifications_failure_is_said_test.dart; here it is
// overridden so the screen's own handling is what is tested. Every other read
// the dashboard makes is overridden too, so no request leaves the test.

typedef _Rows = List<Map<String, dynamic>>;

const _secret = 'PostgrestException(message: SECRET_TABLE_X, code: 42501)';

Map<String, dynamic> _notification(String id, {bool read = false}) => {
      'id': id,
      'title': 'New client $id',
      'body': 'Jo signed up',
      'read': read,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };

Widget _dashboard(Stream<_Rows> Function() notifications) => ProviderScope(
      overrides: [
        coachClientsProvider.overrideWith((ref) async => const []),
        clientCheckinsProvider.overrideWith((ref) async => const []),
        clientWorkoutLogsProvider.overrideWith((ref) async => const []),
        coachNotificationsProvider.overrideWith((ref) => notifications()),
        currentUserProfileProvider.overrideWith((ref) async => null),
        currentUserDisplayNameProvider.overrideWithValue('Coach'),
        pendingRequestsProvider.overrideWith((ref) async => const []),
        sentInvitesProvider.overrideWith((ref) async => const []),
        coachSubmittedCheckinsProvider.overrideWith((ref) async => const []),
        coachLeaderboardProvider.overrideWith((ref) async => const []),
        coachTriageSignalsProvider.overrideWith((ref) async => const []),
      ],
      child: const MaterialApp(home: CoachDashboardScreen()),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.notifications_outlined));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

const _unknown = ValueKey('coach-bell-unread-unknown');

Finder _bell() => find.ancestor(
    of: find.byIcon(Icons.notifications_outlined), matching: find.byType(Stack)).first;

Finder _badgeText() => find.descendant(of: _bell(), matching: find.byType(Text));

void main() {
  testWidgets('a failed read is said in the sheet, never "No notifications"',
      (tester) async {
    await tester.pumpWidget(_dashboard(() => Stream.error(Exception(_secret))));
    await _settle(tester);
    await _openSheet(tester);

    expect(find.text("Couldn't load your notifications"), findsOneWidget,
        reason: 'THE defect: the failure was drawn as an empty list');
    expect(find.text('No notifications yet'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
    // Not a connection failure, so no connection hint; and no exception text.
    expect(find.textContaining('Check your connection'), findsNothing);
    expect(find.textContaining('contact support'), findsOneWidget);
    expect(find.textContaining('SECRET_TABLE_X'), findsNothing);
    // Mark all read / Clear all act on a list the coach cannot see.
    expect(find.text('Mark all read'), findsNothing);
    expect(find.text('Clear all'), findsNothing);
  });

  testWidgets('a connection failure says to check the connection',
      (tester) async {
    await tester.pumpWidget(_dashboard(() =>
        Stream.error(http.ClientException('Connection refused'))));
    await _settle(tester);
    await _openSheet(tester);
    expect(find.text('Check your connection and try again.'), findsOneWidget);
  });

  testWidgets('the bell does not claim 0 unread during a failure: a quiet '
      'unknown marker, no number', (tester) async {
    await tester.pumpWidget(_dashboard(() => Stream.error(Exception(_secret))));
    await _settle(tester);
    expect(find.byKey(_unknown), findsOneWidget,
        reason: 'THE defect: no badge at all, i.e. "0 unread"');
    expect(_badgeText(), findsNothing, reason: 'no number on the bell');
  });

  testWidgets('Try again re-subscribes, is busy while in flight, then shows '
      'the notifications', (tester) async {
    var subscriptions = 0;
    final second = StreamController<_Rows>();
    addTearDown(() => unawaited(second.close()));
    await tester.pumpWidget(_dashboard(() {
      subscriptions++;
      return subscriptions == 1 ? Stream.error(Exception(_secret)) : second.stream;
    }));
    await _settle(tester);
    await _openSheet(tester);
    expect(find.text("Couldn't load your notifications"), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(subscriptions, 2, reason: 'the tap re-subscribed');
    final button = tester.widget<TextButton>(find.ancestor(
        of: find.text('Try again'), matching: find.byType(TextButton)));
    expect(button.onPressed, isNull, reason: 'busy: no double fire');

    // Read, so the header carries no "1 new" / "Mark all read": with unread
    // rows that header row overflows a 600 px sheet (a pre-existing layout
    // issue, reported separately; the sheet is capped at 600 px wide).
    second.add([_notification('n-1', read: true)]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text("Couldn't load your notifications"), findsNothing);
    expect(find.text('New client n-1'), findsOneWidget);
    expect(find.byKey(_unknown), findsNothing);
  });

  // ── Controls ──────────────────────────────────────────────────────────────

  testWidgets('control: a successful empty read keeps today\'s copy and no '
      'badge', (tester) async {
    await tester.pumpWidget(_dashboard(() => Stream.value(const [])));
    await _settle(tester);
    expect(find.byKey(_unknown), findsNothing);
    await _openSheet(tester);
    expect(find.text('No notifications yet'), findsOneWidget);
    expect(find.text("Couldn't load your notifications"), findsNothing);
  });

  testWidgets('control: unread notifications still show their count',
      (tester) async {
    await tester.pumpWidget(_dashboard(
        () => Stream.value([_notification('a'), _notification('b')])));
    await _settle(tester);
    expect(find.descendant(of: _bell(), matching: find.text('2')), findsOneWidget);
    expect(find.byKey(_unknown), findsNothing);
  });
}
