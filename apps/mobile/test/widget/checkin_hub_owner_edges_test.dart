import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/checkins/domain/checkin_hub.dart';
import 'package:circle_fitness/features/checkins/domain/checkin_provider.dart';
import 'package:circle_fitness/features/checkins/presentation/checkin_detail_screen.dart';
import 'package:circle_fitness/features/checkins/presentation/checkin_hub_sections.dart';
import 'package:circle_fitness/features/checkins/presentation/checkin_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/owned_writes_postgrest.dart';
import '../support/owner_harness.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-59c round 2 · A-25, the check-in hub's history: riverpod keeps the last
// member's weeks through the next one's read, and a row can be tapped after its
// member has left. Both put A's answers and coach's reply in front of B.
//
// HOW TO SEE IT FAIL: run against 6f8c693's checkins files.

void main() {
  late OwnedWritesPostgrest server;
  late ProviderContainer container;
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = OwnedWritesPostgrest();
    await initTwoMemberSupabase(server);
  });

  Map<String, Object?> week(String member, int number) => {
        'id': 'w$number',
        'user_id': member,
        'week_number': number,
        'week_start_date': '2026-11-16',
        'status': 'submitted',
        'energy_level': 4,
        'notes': 'private note of week $number',
        'submitted_at': '2026-11-20T10:00:00Z',
      };
  const rowA = 'Week 41 · Energy 4 of 5 · Awaiting reply';
  const rowB = 'Week 7 · Energy 4 of 5 · Awaiting reply';

  setUp(() async {
    await signInAs(memberA);
    server.reset();
    server.rows['weekly_checkins:$memberA'] = [week(memberA, 41)];
    server.rows['weekly_checkins:$memberB'] = [week(memberB, 7)];
    reported.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  Iterable<String> origins() => reported.map((f) => f.origin);

  Future<void> open(WidgetTester t) async {
    tallView(t);
    container = ProviderContainer();
    addTearDown(container.dispose);
    container.listen(selectedCheckinProvider, (_, __) {});
    final router = GoRouter(initialLocation: '/checkins', routes: [
      GoRoute(
          path: '/checkins',
          builder: (_, __) => const Scaffold(
              body: SingleChildScrollView(child: CheckinHubSections()))),
      GoRoute(
          path: '/checkin-detail',
          builder: (_, __) => const CheckinDetailScreen()),
    ]);
    addTearDown(router.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await settleReal(t);
  }

  VoidCallback rowTap(WidgetTester t, String row) => t
      .widget<GestureDetector>(find
          .ancestor(of: find.text(row), matching: find.byType(GestureDetector))
          .first)
      .onTap!;

  group('history', () {
    testWidgets("B's read pending: a spinner, none of A's weeks; then B's own",
        (t) async {
      await open(t);
      expect(find.text(rowA), findsOneWidget);
      final hold =
          server.holds['GET weekly_checkins:$memberB'] = Completer<void>();
      await switchNoFrame(t, memberB);
      await settleReal(t);
      expect(find.text(rowA), findsNothing, reason: 'THE defect');
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      hold.complete();
      await settleReal(t);
      expect(find.text(rowB), findsOneWidget);
      expect(find.text(rowA), findsNothing);
      await closeApp(t);
    });

    testWidgets("B's read failed: a failure, none of A's weeks", (t) async {
      server.fails.add('GET weekly_checkins:$memberB');
      await open(t);
      await switchNoFrame(t, memberB);
      await settleReal(t);
      expect(find.text(checkinHistoryFailure), findsOneWidget);
      expect(find.text(rowA), findsNothing);
      await closeApp(t);
    });

    testWidgets('asked again before the switch is flushed (a notification, or '
        "Try again, with no frame): none of A's weeks", (t) async {
      await open(t);
      final hold =
          server.holds['GET weekly_checkins:$memberB'] = Completer<void>();
      await switchNoFrame(t, memberB);
      container.invalidate(checkinHistoryProvider);
      container.read(checkinHistoryProvider);
      await settleReal(t);
      expect(find.text(rowA), findsNothing);
      hold.complete();
      await settleReal(t);
      expect(find.text(rowB), findsOneWidget);
      await closeApp(t);
    });

    testWidgets("a row of A tapped with no frame since A->B: not stored under B, "
        'not opened, recorded, nothing said', (t) async {
      await open(t);
      final tap = rowTap(t, rowA);
      await switchNoFrame(t, memberB);
      tap();
      expect(container.read(selectedCheckinProvider), isNull,
          reason: "THE defect: A's answers and reply under B's uid");
      await settleReal(t);
      expect(container.read(selectedCheckinProvider), isNull);
      expect(find.byType(CheckinDetailScreen), findsNothing);
      expect(find.textContaining('private note'), findsNothing);
      expect(origins(), ['CheckinHubSections.open']);
      expect(find.byType(SnackBar), findsNothing);
      await closeApp(t);
    });

    testWidgets("a row of A tapped signed out: not stored", (t) async {
      await open(t);
      final tap = rowTap(t, rowA);
      await signOutNoFrame(t);
      tap();
      expect(container.read(selectedCheckinProvider), isNull);
      await settleReal(t);
      expect(find.text(rowA), findsNothing);
      await closeApp(t);
    });

    testWidgets('POSITIVE CONTROL: a token refresh and a profile edit read '
        'nothing again, and the row still opens the member\'s week', (t) async {
      await open(t);
      final reads = server.sent('GET', 'weekly_checkins').length;
      await refreshToken(t);
      await editUser(t);
      await settleReal(t);
      expect(server.sent('GET', 'weekly_checkins'), hasLength(reads),
          reason: 'THE defect: the whole User was watched');
      await t.tap(find.text(rowA));
      await settleReal(t);
      expect(container.read(selectedCheckinProvider)?.id, 'w41');
      expect(find.text('private note of week 41'), findsOneWidget);
      expect(reported, isEmpty);
      await closeApp(t);
    });

    testWidgets("the same member's failed refresh keeps the weeks, openable, "
        'and says so', (t) async {
      await open(t);
      server.fails.add('GET weekly_checkins:$memberA');
      container.invalidate(checkinHistoryProvider);
      await settleReal(t);
      expect(find.text(checkinHistoryFailure), findsOneWidget);
      expect(find.text(rowA), findsOneWidget, reason: 'THE defect: dropped');
      expect(origins(), ['CheckinHubSections.history']);
      await t.tap(find.text(rowA));
      await settleReal(t);
      expect(find.text('private note of week 41'), findsOneWidget);
      await closeApp(t);
    });

    testWidgets("the same member's refresh in flight keeps the weeks",
        (t) async {
      await open(t);
      final hold =
          server.holds['GET weekly_checkins:$memberA'] = Completer<void>();
      container.invalidate(checkinHistoryProvider);
      await settleReal(t);
      expect(find.text(rowA), findsOneWidget);
      hold.complete();
      await settleReal(t);
      await closeApp(t);
    });

    testWidgets("a row that names another member is not shown, whoever was asked "
        'for', (t) async {
      server.rows['weekly_checkins:$memberA'] = [
        week(memberB, 7),
        week(memberA, 41),
      ];
      await open(t);
      expect(find.text(rowA), findsOneWidget);
      expect(find.text(rowB), findsNothing);
      await closeApp(t);
    });

    testWidgets('NEGATIVE CONTROL: no weeks is none, not a failure', (t) async {
      server.rows['weekly_checkins:$memberA'] = const [];
      await open(t);
      expect(find.textContaining('Week'), findsNothing);
      expect(find.text(checkinHistoryFailure), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await closeApp(t);
    });
  });

  group('upcoming sessions', () {
    Map<String, Object?> call(DateTime at) => {
          'id': 'call-1',
          'client_id': memberA,
          'scheduled_at': at.toUtc().toIso8601String(),
          'duration_minutes': 30,
          'call_type': 'check_in',
          'status': 'scheduled',
          'coach': {'first_name': 'Avery', 'last_name': 'Park'},
        };

    Future<void> openHub(WidgetTester t) async {
      tallView(t);
      await t.pumpWidget(
          const ProviderScope(child: MaterialApp(home: CheckinScreen())));
      await settleReal(t);
    }

    int dots(WidgetTester t) => t
        .widgetList<Container>(find.byWidgetPredicate((w) =>
            w is Container &&
            w.constraints?.maxWidth == 5 &&
            (w.decoration! as BoxDecoration).color != Colors.transparent))
        .length;

    testWidgets("B's read pending: the days A's sessions fall on are not marked",
        (t) async {
      server.rows['coaching_calls:$memberA'] = [call(DateTime.now())];
      await openHub(t);
      expect(dots(t), 1, reason: 'premise');
      server.holds['GET coaching_calls:$memberB'] = Completer<void>();
      await switchNoFrame(t, memberB);
      await settleReal(t);
      expect(dots(t), 0);
      server.holds['GET coaching_calls:$memberB']!.complete();
      await settleReal(t);
      await closeApp(t);
    });

    testWidgets('signed out is not "No upcoming sessions"', (t) async {
      await openHub(t);
      expect(find.text('No upcoming sessions'), findsOneWidget,
          reason: 'NEGATIVE CONTROL: signed in with none');
      await signOutNoFrame(t);
      await settleReal(t);
      expect(find.text('No upcoming sessions'), findsNothing);
      expect(find.textContaining("You're signed out"), findsOneWidget);
      await switchNoFrame(t, memberA);
      await settleReal(t);
      expect(find.text('No upcoming sessions'), findsOneWidget);
      expect(find.textContaining("You're signed out"), findsNothing);
      await closeApp(t);
    });

    testWidgets("the same member's retry: pending is not none, a second failure "
        'is said, and the sessions then show', (t) async {
      server.rows['coaching_calls:$memberA'] = [
        call(DateTime.now().add(const Duration(days: 2)))
      ];
      server.fails.add('GET coaching_calls:$memberA');
      await openHub(t);
      expect(find.text(checkinSessionsFailure), findsOneWidget);
      final hold =
          server.holds['GET coaching_calls:$memberA'] = Completer<void>();
      await t.tap(find.text('Try again').last);
      await settleReal(t);
      expect(find.text('No upcoming sessions'), findsNothing,
          reason: 'THE defect: the retry in flight read as none');
      hold.complete();
      await settleReal(t);
      expect(find.text(checkinSessionsFailure), findsOneWidget);
      server.fails.clear();
      server.holds.clear();
      await t.tap(find.text('Try again').last);
      await settleReal(t);
      expect(find.text('with Coach Avery Park'), findsOneWidget);
      await closeApp(t);
    });
  });
}
