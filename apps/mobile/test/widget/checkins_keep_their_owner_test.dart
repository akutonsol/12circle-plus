import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/checkins/data/models/checkin_model.dart';
import 'package:circle_fitness/features/checkins/data/weekly_checkin_service.dart';
import 'package:circle_fitness/features/checkins/domain/checkin_hub.dart';
import 'package:circle_fitness/features/checkins/domain/checkin_known.dart';
import 'package:circle_fitness/features/checkins/domain/checkin_provider.dart';
import 'package:circle_fitness/features/checkins/presentation/checkin_screen.dart';
import 'package:circle_fitness/features/checkins/presentation/coach_checkin_review_screen.dart';
import 'package:circle_fitness/features/checkins/presentation/daily_checkin_screen.dart';
import 'package:circle_fitness/features/coach/domain/coach_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/owned_writes_postgrest.dart';
import '../support/pump_until.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-59c · a check-in belongs to the account that wrote it, a review to the
// coach who is writing it, and the hub's sessions to whose they are.
//
// At a82f993: the weekly form filled in by A was upserted over B's week (RLS
// `user_id = auth.uid()` accepts it); the coach queue and the selected check-in
// did not watch the user at all, so coach B was shown coach A's clients, and
// A's half-written feedback went out as B; the points and the notification
// after a save went to, or out as, whoever was signed in by then.
//
// The REAL services and auth client, AccountScope deliberately absent: every
// test asserts what was asked of the server, and by whom.
//
// HOW TO SEE IT FAIL: run against a82f993's checkins files.

const _notes = 'A: my knee is worse';

Future<void> _tick() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  late OwnedWritesPostgrest server;
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = OwnedWritesPostgrest();
    await initTwoMemberSupabase(server);
  });

  setUp(() async {
    await signInAs(memberA);
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  Iterable<String> origins() => reported.map((f) => f.origin);

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 10; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  /// The real auth transition, WITHOUT a frame: what a hidden tab does.
  Future<void> switchTo(WidgetTester t, String uid) async {
    await t.runAsync(() => signInAs(uid));
    expect(Supabase.instance.client.auth.currentUser?.id, uid, reason: 'premise');
  }

  void tall(WidgetTester t) {
    t.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 3200);
    addTearDown(t.view.reset);
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 7));
  }

  // ── The weekly form ────────────────────────────────────────────────────────
  group('the weekly check-in form (W6, S5, A-14)', () {
    Future<void> open(WidgetTester t) async {
      tall(t);
      await t.pumpWidget(ProviderScope(
        overrides: [assignedCoachProvider.overrideWith((ref) async => null)],
        child: const MaterialApp(home: DailyCheckinScreen()),
      ));
      await settle(t);
    }

    Finder notesField() => find.byType(TextField);
    Finder submitButton() => find.byIcon(Icons.check_circle_outline);

    Future<void> fillIn(WidgetTester t) async {
      await t.enterText(notesField(), _notes);
      await t.tap(find.text('Amazing'));
      await t.pump();
    }

    VoidCallback submitCallback(WidgetTester t) => t
        .widget<GestureDetector>(find
            .ancestor(
                of: submitButton(), matching: find.byType(GestureDetector))
            .first)
        .onTap!;

    String notes(WidgetTester t) =>
        t.widget<TextField>(notesField()).controller!.text;

    testWidgets('POSITIVE CONTROL: saved once, as the member, with its points',
        (t) async {
      await open(t);
      await fillIn(t);
      await t.tap(submitButton());
      await settle(t);
      final row = server.sent('POST', 'weekly_checkins').single;
      expect(row.who, memberA);
      expect(row.json['user_id'], memberA);
      expect(row.json['notes'], _notes);
      expect(row.json['mood'], 5);
      expect(server.sent('POST', 'daily_scores').single.json['user_id'], memberA);
      expect(server.sent('POST', 'award_points').single.who, memberA);
      expect(find.text('Weekly Check-In Complete!'), findsOneWidget);
      expect(reported, isEmpty);
      await close(t);
    });

    testWidgets('POSITIVE CONTROL: a token refresh keeps the answers, and they '
        'save once', (t) async {
      await open(t);
      await fillIn(t);
      final reads = server.sent('GET', 'weekly_checkins').length;
      await t.runAsync(refreshSession);
      await settle(t);
      expect(notes(t), _notes);
      expect(server.sent('GET', 'weekly_checkins'), hasLength(reads));
      await t.tap(submitButton());
      await settle(t);
      expect(server.sent('POST', 'weekly_checkins').single.json['mood'], 5);
      await close(t);
    });

    testWidgets("A->B: A's answers are gone, and B's save carries none of them",
        (t) async {
      await open(t);
      await fillIn(t);
      await switchTo(t, memberB);
      await settle(t);
      expect(notes(t), isEmpty, reason: "THE defect: A's notes stayed for B");
      await t.tap(submitButton());
      await settle(t);
      final row = server.sent('POST', 'weekly_checkins').single;
      expect(row.who, memberB);
      expect(row.json['user_id'], memberB);
      expect(row.json['notes'], isEmpty);
      expect(row.json['mood'], 3, reason: "the form's own starting value");
      await close(t);
    });

    testWidgets('sign-out -> the same member back in: the answers went',
        (t) async {
      await open(t);
      await fillIn(t);
      await t.runAsync(signOut);
      await settle(t);
      expect(notes(t), isEmpty);
      await switchTo(t, memberA);
      await settle(t);
      expect(notes(t), isEmpty);
      expect(server.sent('POST', 'weekly_checkins'), isEmpty);
      await close(t);
    });

    testWidgets('A->B with no frame in between (a hidden tab): nothing is '
        'written, recorded, nothing is said', (t) async {
      await open(t);
      await fillIn(t);
      final submit = submitCallback(t);
      await switchTo(t, memberB);
      submit();
      await settle(t);
      expect(server.writesAs(memberB), isEmpty,
          reason: "THE defect: A's answers were upserted over B's week");
      expect(origins(), ['DailyCheckinScreen._submit']);
      expect(find.byType(SnackBar), findsNothing);
      expect(notes(t), isEmpty);
      await close(t);
    });

    for (final table in ['client_nutrition_plans', 'weekly_checkins']) {
      testWidgets('a switch during the save\'s $table read: nothing is written',
          (t) async {
        await open(t);
        await fillIn(t);
        final before = server.sent('GET', table).length;
        final hold = server.holds['GET $table:$memberA'] = Completer<void>();
        await t.tap(submitButton());
        await pumpUntil(t, () => server.sent('GET', table).length > before,
            what: 'the read');
        await switchTo(t, memberB);
        hold.complete();
        await settle(t);
        expect(
            server.log.where((a) => a.method != 'GET'), isEmpty,
            reason: "THE defect: a row for A sent as B, and B's points");
        expect(origins(),
            contains('WeeklyCheckinService.submitWeeklyCheckin'));
        expect(find.byType(SnackBar), findsNothing);
        expect(find.text('Weekly Check-In Complete!'), findsNothing);
        await close(t);
      });
    }

    testWidgets("a switch during the save itself: A's row is kept, B is awarded "
        'nothing and shown nothing', (t) async {
      await open(t);
      await fillIn(t);
      final hold =
          server.holds['POST weekly_checkins:$memberA'] = Completer<void>();
      await t.tap(submitButton());
      await pumpUntil(t, () => server.sent('POST', 'weekly_checkins').isNotEmpty,
          what: 'the save');
      await switchTo(t, memberB);
      hold.complete();
      await settle(t);
      expect(server.sent('POST', 'weekly_checkins').single.who, memberA);
      expect(server.writesAs(memberB), isEmpty,
          reason: 'THE defect: daily_scores and award_points ran as B');
      expect(origins(), [
        'WeeklyCheckinService.submitWeeklyCheckin.dailyPoints',
        'WeeklyCheckinService.submitWeeklyCheckin.weeklyPoints',
      ]);
      expect(find.text('Weekly Check-In Complete!'), findsNothing);
      await close(t);
    });

    testWidgets('a switch during the daily points: no weekly award for B',
        (t) async {
      await open(t);
      final hold =
          server.holds['POST daily_scores:$memberA'] = Completer<void>();
      await t.tap(submitButton());
      await pumpUntil(t, () => server.sent('POST', 'daily_scores').isNotEmpty,
          what: 'the daily points');
      await switchTo(t, memberB);
      hold.complete();
      await settle(t);
      expect(server.writesAs(memberB), isEmpty);
      expect(origins(),
          ['WeeklyCheckinService.submitWeeklyCheckin.weeklyPoints']);
      await close(t);
    });

    testWidgets('a refused save by A says nothing to B', (t) async {
      await open(t);
      final hold =
          server.holds['POST weekly_checkins:$memberA'] = Completer<void>();
      server.fails.add('POST weekly_checkins:$memberA');
      await t.tap(submitButton());
      await pumpUntil(t, () => server.sent('POST', 'weekly_checkins').isNotEmpty,
          what: 'the save');
      await switchTo(t, memberB);
      hold.complete();
      await settle(t);
      expect(find.byType(SnackBar), findsNothing);
      expect(server.writesAs(memberB), isEmpty);
      await close(t);
    });

    testWidgets('CONTROL: a refused save by the same member says so and keeps '
        'the answers', (t) async {
      await open(t);
      await fillIn(t);
      server.fails.add('POST weekly_checkins:$memberA');
      await t.tap(submitButton());
      await settle(t);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(notes(t), _notes);
      expect(server.sent('POST', 'award_points'), isEmpty);
      await close(t);
    });

    testWidgets("the finished dialog (A's mood) goes when A does", (t) async {
      await open(t);
      await fillIn(t);
      await t.tap(submitButton());
      await settle(t);
      expect(find.text('Weekly Check-In Complete!'), findsOneWidget);
      await t.runAsync(refreshSession);
      await settle(t);
      expect(find.text('Weekly Check-In Complete!'), findsOneWidget,
          reason: 'the same member keeps it');
      await switchTo(t, memberB);
      await settle(t);
      expect(find.text('Weekly Check-In Complete!'), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(notesField().hitTestable(), findsOneWidget,
          reason: 'no barrier is left over the form');
      await close(t);
    });

    group("the load: A's week is not B's", () {
      const done = 'Already Checked In!';
      final doneRow = [
        {'status': 'submitted', 'week_start_date': '2026-11-23'}
      ];

      testWidgets("A's answer lands after B's own", (t) async {
        server.rows['weekly_checkins:$memberA'] = doneRow;
        final hold =
            server.holds['GET weekly_checkins:$memberA'] = Completer<void>();
        await open(t);
        await switchTo(t, memberB);
        await settle(t);
        hold.complete();
        await settle(t);
        expect(find.text(done), findsNothing,
            reason: "THE defect: B was told they had checked in (A's week)");
        expect(server.sent('GET', 'weekly_checkins', memberB), isNotEmpty);
        expect(notesField(), findsOneWidget);
        await close(t);
      });

      testWidgets("A's answer lands while B's read is pending, with no frame "
          'in between', (t) async {
        server.rows['weekly_checkins:$memberA'] = doneRow;
        final hold =
            server.holds['GET weekly_checkins:$memberA'] = Completer<void>();
        server.holds['GET weekly_checkins:$memberB'] = Completer<void>();
        await open(t);
        await switchTo(t, memberB);
        hold.complete();
        await settle(t);
        expect(find.text(done), findsNothing);
        server.holds['GET weekly_checkins:$memberB']!.complete();
        await settle(t);
        expect(find.text(done), findsNothing,
            reason: "THE defect (S5): A's week beside B's streak");
        expect(notesField(), findsOneWidget);
        await close(t);
      });

      testWidgets("B's own read failing is B's failure, not A's week",
          (t) async {
        server.rows['weekly_checkins:$memberA'] = doneRow;
        server.fails.add('GET weekly_checkins:$memberB');
        await open(t);
        expect(find.text(done), findsOneWidget, reason: 'control: A is done');
        await switchTo(t, memberB);
        await settle(t);
        expect(find.text(done), findsNothing);
        expect(find.text("Couldn't load this week's check-in"), findsOneWidget);
        await close(t);
      });

      testWidgets("B's own done week is shown to B", (t) async {
        server.rows['weekly_checkins:$memberB'] = doneRow;
        await open(t);
        expect(find.text(done), findsNothing);
        await switchTo(t, memberB);
        await settle(t);
        expect(find.text(done), findsOneWidget);
        await close(t);
      });
    });
  });

  group('the check-in service', () {
    test('NEGATIVE CONTROL: no row this week is still "not done", not unknown',
        () async {
      expect(await WeeklyCheckinService().weekStatus(), CheckinKnown.notDone);
    });

    test('the review: saved as the coach who wrote it, and the client is not '
        'notified as the account that arrived', () async {
      final hold =
          server.holds['PATCH weekly_checkins:$memberA'] = Completer<void>();
      final answer = WeeklyCheckinService().submitCoachFeedback(
          checkinId: 'c1', message: 'm', recommendations: const [], coachName: 'A');
      await _tick();
      await signInAs(memberB);
      hold.complete();
      expect(await answer, isTrue, reason: 'the review was saved');
      expect(server.sent('POST', 'notifications'), isEmpty,
          reason: "THE defect: sent as B, in A's name");
      expect(origins(), ['WeeklyCheckinService.submitCoachFeedback.notify']);
    });
  });

  // ── The coach's review ─────────────────────────────────────────────────────
  group("the coach's review (A-12, A-13, W18, E2)", () {
    Map<String, Object?> row(String id, String first, {String? note}) => {
          'id': id,
          'user_id': 'client-1',
          'week_number': 47,
          'status': 'submitted',
          'mood': 4,
          'notes': note ?? 'note of $first',
          'user_profiles': {'first_name': first, 'last_name': 'Osei'},
        };

    late ProviderContainer container;

    Future<void> open(WidgetTester t) async {
      tall(t);
      container = ProviderContainer();
      addTearDown(container.dispose);
      final router = GoRouter(initialLocation: '/review', routes: [
        GoRoute(
            path: '/',
            builder: (_, __) => const Scaffold(body: Text('BEHIND')),
            routes: [
              GoRoute(
                  path: 'review',
                  builder: (_, __) => const CoachCheckinReviewScreen()),
            ]),
      ]);
      addTearDown(router.dispose);
      await t.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ));
      await settle(t);
    }

    setUp(() {
      server.rows['weekly_checkins:$memberA'] = [row('a1', 'Amara')];
    });

    Future<void> draft(WidgetTester t) async {
      await t.enterText(find.byType(TextField).at(0), 'feedback by A');
      await t.enterText(find.byType(TextField).at(1), 'rest by A');
      await t.tap(find.byIcon(Icons.add));
      await t.enterText(find.byType(TextField).at(1), 'half by A');
      await t.pump();
    }

    String text(WidgetTester t, int i) =>
        t.widget<TextField>(find.byType(TextField).at(i)).controller!.text;

    Finder send() => find.byType(ElevatedButton);

    testWidgets('POSITIVE CONTROL: sent once, as the coach, notifying once',
        (t) async {
      await open(t);
      await draft(t);
      await t.tap(send());
      await settle(t);
      final patch = server.sent('PATCH', 'weekly_checkins').single;
      expect(patch.who, memberA);
      expect(patch.query['id'], 'eq.a1');
      expect(patch.json['feedback_message'], 'feedback by A');
      expect(patch.json['feedback_recommendations'], ['rest by A']);
      expect(server.sent('POST', 'notifications').single.who, memberA);
      expect(find.text('BEHIND'), findsOneWidget, reason: 'the last one: popped');
      expect(reported, isEmpty);
      await close(t);
    });

    testWidgets('POSITIVE CONTROL: a token refresh keeps the drafts, and the '
        'queue is not read again', (t) async {
      await open(t);
      await draft(t);
      final reads = server.sent('GET', 'weekly_checkins').length;
      await t.runAsync(refreshSession);
      await settle(t);
      expect(text(t, 0), 'feedback by A');
      expect(find.text('rest by A'), findsOneWidget);
      expect(find.textContaining('Amara Osei'), findsOneWidget);
      expect(server.sent('GET', 'weekly_checkins'), hasLength(reads));
      await close(t);
    });

    testWidgets("A->B: B sees B's own client, and none of A's client or drafts",
        (t) async {
      server.rows['weekly_checkins:$memberB'] = [row('b1', 'Bea')];
      await open(t);
      await draft(t);
      await switchTo(t, memberB);
      await settle(t);
      expect(find.textContaining('Amara'), findsNothing,
          reason: "THE defect: nothing re-read, and A's client stayed");
      expect(find.textContaining('Bea Osei'), findsOneWidget);
      expect(text(t, 0), isEmpty);
      expect(text(t, 1), isEmpty);
      expect(find.text('rest by A'), findsNothing);
      expect(server.writesAs(memberB), isEmpty);
      await close(t);
    });

    testWidgets("B's read pending: no row of A, even when asked again meanwhile",
        (t) async {
      final hold =
          server.holds['GET weekly_checkins:$memberB'] = Completer<void>();
      await open(t);
      await switchTo(t, memberB);
      await t.pump();
      await t.pump();
      expect(find.textContaining('Amara'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      container.invalidate(coachSubmittedCheckinsProvider);
      await settle(t);
      expect(find.textContaining('Amara'), findsNothing);
      hold.complete();
      await settle(t);
      expect(find.text('No check-in selected'), findsOneWidget,
          reason: "NEGATIVE CONTROL: B's empty queue is empty");
      await close(t);
    });

    testWidgets("B's read failed: a failure, and no row of A", (t) async {
      server.fails.add('GET weekly_checkins:$memberB');
      await open(t);
      await draft(t);
      await switchTo(t, memberB);
      await settle(t);
      expect(find.textContaining('Amara'), findsNothing);
      expect(find.text("Couldn't load your review queue"), findsOneWidget);
      await close(t);
    });

    testWidgets("A's answer landing after B's own is not shown", (t) async {
      server.rows['weekly_checkins:$memberB'] = [row('b1', 'Bea')];
      final hold =
          server.holds['GET weekly_checkins:$memberA'] = Completer<void>();
      await open(t);
      await switchTo(t, memberB);
      await settle(t);
      hold.complete();
      await settle(t);
      expect(find.textContaining('Amara'), findsNothing);
      expect(find.textContaining('Bea Osei'), findsOneWidget);
      await close(t);
    });

    testWidgets('a check-in A opened is not kept for B', (t) async {
      await open(t);
      container.read(selectedCoachCheckinProvider.notifier).state =
          row('a2', 'Anton');
      await t.pump();
      expect(find.textContaining('Anton'), findsWidgets);
      await t.runAsync(refreshSession);
      await settle(t);
      expect(find.textContaining('Anton'), findsWidgets,
          reason: 'POSITIVE CONTROL: the same coach keeps it');
      await switchTo(t, memberB);
      await settle(t);
      expect(find.textContaining('Anton'), findsNothing);
      await close(t);
    });

    testWidgets('signed out: no client on screen, and nothing is asked; the '
        'same coach back in reads the queue again without the old draft',
        (t) async {
      await open(t);
      await draft(t);
      server.log.clear();
      await t.runAsync(signOut);
      await settle(t);
      expect(find.textContaining('Amara'), findsNothing);
      expect(server.log, isEmpty);
      await switchTo(t, memberA);
      await settle(t);
      expect(find.textContaining('Amara Osei'), findsOneWidget);
      expect(text(t, 0), isEmpty);
      await close(t);
    });

    testWidgets('a submit after a switch no frame has seen: nothing is sent, '
        'recorded, nothing said', (t) async {
      await open(t);
      await draft(t);
      final submit = t.widget<ElevatedButton>(send()).onPressed!;
      await switchTo(t, memberB);
      submit();
      await settle(t);
      expect(server.writesAs(memberB), isEmpty,
          reason: "THE defect: A's feedback saved as B's review");
      expect(origins(), ['CoachCheckinReviewScreen._submit']);
      expect(find.byType(SnackBar), findsNothing);
      await close(t);
    });

    testWidgets('a switch during the send: the client is not notified as B, and '
        "B's screen is not popped, paged or told", (t) async {
      server.rows['weekly_checkins:$memberB'] = [row('b1', 'Bea')];
      await open(t);
      await draft(t);
      final hold =
          server.holds['PATCH weekly_checkins:$memberA'] = Completer<void>();
      await t.tap(send());
      await pumpUntil(t, () => server.sent('PATCH', 'weekly_checkins').isNotEmpty,
          what: 'the review');
      await switchTo(t, memberB);
      await settle(t);
      await t.enterText(find.byType(TextField).at(0), 'B types');
      hold.complete();
      await settle(t);
      expect(server.writesAs(memberB), isEmpty);
      expect(origins(), ['WeeklyCheckinService.submitCoachFeedback.notify']);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('BEHIND'), findsNothing);
      expect(text(t, 0), 'B types', reason: "B's own draft is B's");
      expect(find.textContaining('Bea Osei'), findsOneWidget);
      expect(t.widget<ElevatedButton>(send()).onPressed, isNotNull);
      await close(t);
    });

    testWidgets("the same coach's failed refresh keeps the open check-in and "
        'the draft, and says so', (t) async {
      await open(t);
      await draft(t);
      server.fails.add('GET weekly_checkins:$memberA');
      container.invalidate(coachSubmittedCheckinsProvider);
      await settle(t);
      expect(find.textContaining('Amara Osei'), findsOneWidget);
      expect(text(t, 0), 'feedback by A');
      expect(find.textContaining("couldn't load your review queue"),
          findsOneWidget);
      await switchTo(t, memberB);
      server.fails.add('GET weekly_checkins:$memberB');
      await settle(t);
      expect(find.textContaining('Amara'), findsNothing);
      await close(t);
    });
  });

  // ── The client's selection ─────────────────────────────────────────────────
  group('the check-in a client opened is keyed by the uid (A-35)', () {
    Future<ProviderContainer> picked() async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.listen(selectedCheckinProvider, (_, __) {});
      c.read(selectedCheckinProvider.notifier).state = WeeklyCheckin(
        id: 'a-week',
        weekNumber: 47,
        weekStartDate: DateTime(2026, 11, 16),
        status: CheckinStatus.submitted,
        responses: const [],
        overallScore: 0,
      );
      await _tick();
      return c;
    }

    test('kept through a token refresh (a new User, the same member)', () async {
      final c = await picked();
      await refreshSession();
      await _tick();
      expect(c.read(selectedCheckinProvider)?.id, 'a-week',
          reason: 'THE defect: the whole User was watched');
    });

    test('dropped for B, and on sign-out', () async {
      final c = await picked();
      await signInAs(memberB);
      await _tick();
      expect(c.read(selectedCheckinProvider), isNull);
      final d = await picked();
      await signOut();
      await _tick();
      expect(d.read(selectedCheckinProvider), isNull);
    });
  });

  // ── The hub's sessions ─────────────────────────────────────────────────────
  group('the check-in hub: upcoming sessions (E9)', () {
    Map<String, Object?> call(String client, String coach) => {
          'id': 'call-$client',
          'client_id': client,
          'scheduled_at': DateTime.now()
              .add(const Duration(days: 2))
              .toUtc()
              .toIso8601String(),
          'duration_minutes': 30,
          'call_type': 'check_in',
          'status': 'scheduled',
          'coach': {'first_name': coach, 'last_name': 'Park'},
        };

    setUp(() {
      server.rows['coaching_calls:$memberA'] = [call(memberA, 'Avery')];
    });

    Future<void> open(WidgetTester t) async {
      tall(t);
      await t.pumpWidget(
          const ProviderScope(child: MaterialApp(home: CheckinScreen())));
      await settle(t);
    }

    testWidgets("A->B: A's session and coach are gone; B's own are shown",
        (t) async {
      server.rows['coaching_calls:$memberB'] = [call(memberB, 'Blake')];
      await open(t);
      expect(find.text('with Coach Avery Park'), findsOneWidget);
      await switchTo(t, memberB);
      await settle(t);
      expect(find.text('with Coach Avery Park'), findsNothing,
          reason: 'THE defect: never read again');
      expect(find.text('with Coach Blake Park'), findsOneWidget);
      await close(t);
    });

    testWidgets("B's read pending, then failed: nothing of A", (t) async {
      final hold =
          server.holds['GET coaching_calls:$memberB'] = Completer<void>();
      server.fails.add('GET coaching_calls:$memberB');
      await open(t);
      await switchTo(t, memberB);
      await settle(t);
      expect(find.textContaining('Avery'), findsNothing);
      expect(find.text('1 APPT'), findsNothing);
      expect(find.text('No upcoming sessions'), findsNothing,
          reason: 'pending is not empty');
      hold.complete();
      await settle(t);
      expect(find.textContaining('Avery'), findsNothing);
      expect(find.text(checkinSessionsFailure), findsOneWidget);
      expect(origins(), contains('CheckinScreen._loadCalls'));
      await close(t);
    });

    for (final frame in [true, false]) {
      testWidgets("A's answer landing after B ${frame ? "and after B's own" : 'with no frame in between'}"
          ' is not shown', (t) async {
        server.rows['coaching_calls:$memberB'] = [call(memberB, 'Blake')];
        final hold =
            server.holds['GET coaching_calls:$memberA'] = Completer<void>();
        await open(t);
        await switchTo(t, memberB);
        if (frame) await settle(t);
        hold.complete();
        await settle(t);
        expect(find.textContaining('Avery'), findsNothing);
        expect(find.text('with Coach Blake Park'), findsOneWidget);
        await close(t);
      });
    }

    testWidgets("A's failure landing after B's own sessions is not B's",
        (t) async {
      server.rows['coaching_calls:$memberB'] = [call(memberB, 'Blake')];
      final hold =
          server.holds['GET coaching_calls:$memberA'] = Completer<void>();
      server.fails.add('GET coaching_calls:$memberA');
      await open(t);
      await switchTo(t, memberB);
      await settle(t);
      hold.complete();
      await t.idle();
      await t.pump();
      expect(find.text(checkinSessionsFailure), findsNothing);
      await settle(t);
      expect(find.text('with Coach Blake Park'), findsOneWidget);
      await close(t);
    });

    testWidgets('CONTROLS: a token refresh reads nothing again; signed out '
        "shows nothing of A's; no calls is still none", (t) async {
      await open(t);
      await t.runAsync(refreshSession);
      await settle(t);
      expect(server.sent('GET', 'coaching_calls'), hasLength(1));
      expect(find.text('with Coach Avery Park'), findsOneWidget);
      await t.runAsync(signOut);
      await settle(t);
      expect(find.textContaining('Avery'), findsNothing);
      await switchTo(t, memberA);
      await settle(t);
      expect(find.text('with Coach Avery Park'), findsOneWidget,
          reason: 'the same member back in');
      await switchTo(t, memberB);
      await settle(t);
      expect(find.text('No upcoming sessions'), findsOneWidget);
      await close(t);
    });
  });
}
