import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/checkins/domain/checkin_provider.dart';
import 'package:circle_fitness/features/checkins/presentation/coach_checkin_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/owned_writes_postgrest.dart';
import '../support/owner_harness.dart';
import '../support/pump_until.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-59c round 2 · the coach's review: the same coach keeps the open check-in,
// the draft and the place in the queue through a re-read and its failure; nobody
// else is ever shown them, and an action is taken as the coach it was drawn for.
//
// HOW TO SEE IT FAIL: run against 6f8c693's checkins files (a82f993's for the
// two marked so).

void main() {
  late OwnedWritesPostgrest server;
  late ProviderContainer container;
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = OwnedWritesPostgrest();
    await initTwoMemberSupabase(server);
  });

  Map<String, Object?> row(String id, String first) => {
        'id': id,
        'user_id': 'client-$id',
        'week_number': 47,
        'status': 'submitted',
        'mood': 4,
        'notes': 'note of $first',
        'user_profiles': {'first_name': first, 'last_name': 'Osei'},
      };

  setUp(() async {
    await signInAs(memberA);
    server.reset();
    server.rows['weekly_checkins:$memberA'] = [
      row('a1', 'Amara'),
      row('a2', 'Anton'),
    ];
    server.rows['weekly_checkins:$memberB'] = [row('b1', 'Bea')];
    reported.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  Iterable<String> origins() => reported.map((f) => f.origin);

  Future<void> open(WidgetTester t) async {
    tallView(t);
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
    await settleReal(t);
    expect(find.text('Amara Osei'), findsOneWidget, reason: 'premise');
  }

  Finder reply() => find.byType(TextField).at(0);
  Finder recommendation() => find.byType(TextField).at(1);
  String text(WidgetTester t, Finder f) =>
      t.widget<TextField>(f).controller!.text;
  Finder send() => find.byType(ElevatedButton);
  Future<void> draft(WidgetTester t) async {
    await t.enterText(reply(), 'feedback by A');
    await t.pump();
  }

  void nothingOfA() {
    expect(find.textContaining('Amara'), findsNothing);
    expect(find.textContaining('Anton'), findsNothing);
    expect(find.textContaining('of 2'), findsNothing);
  }

  void formOfA(WidgetTester t, {String header = 'Week 47 · 1 of 2'}) {
    expect(find.text('Amara Osei'), findsOneWidget);
    expect(find.text(header), findsOneWidget);
    expect(text(t, reply()), 'feedback by A');
    expect(find.text('Send and open next'), findsOneWidget);
  }

  group('the same coach, with a draft and nothing selected (UX B1)', () {
    testWidgets('a re-read in flight keeps the form, the place and the next one',
        (t) async {
      await open(t);
      await draft(t);
      final hold =
          server.holds['GET weekly_checkins:$memberA'] = Completer<void>();
      container.invalidate(coachSubmittedCheckinsProvider);
      await settleReal(t);
      expect(container.read(coachSubmittedCheckinsProvider).isLoading, isTrue,
          reason: 'premise');
      formOfA(t);
      hold.complete();
      await settleReal(t);
      formOfA(t);
      await closeApp(t);
    });

    testWidgets('an AsyncLoading re-read (a dependency of the queue changed) '
        'keeps them too', (t) async {
      await open(t);
      await draft(t);
      server.holds['GET weekly_checkins:$memberA'] = Completer<void>();
      container.invalidate(weeklyCheckinServiceProvider);
      await settleReal(t);
      final state = container.read(coachSubmittedCheckinsProvider);
      expect(state, isA<AsyncLoading<List<Map<String, dynamic>>>>(),
          reason: 'premise');
      formOfA(t);
      server.holds['GET weekly_checkins:$memberA']!.complete();
      await settleReal(t);
      await closeApp(t);
    });

    testWidgets('a failed re-read keeps them and says so, announced, with a '
        'busy-aware retry; Send then opens the next one', (t) async {
      final handle = t.ensureSemantics();
      await open(t);
      await draft(t);
      server.fails.add('GET weekly_checkins:$memberA');
      container.invalidate(coachSubmittedCheckinsProvider);
      await settleReal(t);
      const header = "Week 47 · 1 of 2 · couldn't load your review queue";
      formOfA(t, header: header);
      expect(find.text("Couldn't load your review queue"), findsOneWidget);
      expect(liveRegion("Couldn't load your review queue"), findsOneWidget);
      final retry = find.widgetWithText(TextButton, 'Try again');
      expect(t.getSize(retry).height, greaterThanOrEqualTo(44));
      expect(find.bySemanticsLabel('Try again: load your review queue'),
          findsOneWidget);

      server.fails.clear();
      final hold =
          server.holds['GET weekly_checkins:$memberA'] = Completer<void>();
      await t.tap(retry);
      await t.pump();
      expect(find.bySemanticsLabel('Retrying'), findsOneWidget);
      formOfA(t, header: header);
      server.holds.clear();
      server.rows['weekly_checkins:$memberA'] = [row('a2', 'Anton')];
      await t.tap(send());
      await settleReal(t);
      expect(server.sent('PATCH', 'weekly_checkins').single.query['id'], 'eq.a1');
      expect(find.text('BEHIND'), findsNothing,
          reason: 'THE defect: the held queue was empty, so "the last one"');
      expect(find.text('Anton Osei'), findsOneWidget);
      hold.complete();
      await settleReal(t);
      handle.dispose();
      await closeApp(t);
    });

    testWidgets('NEGATIVE CONTROL: a queue that empties is empty, and the open '
        'one is not kept', (t) async {
      await open(t);
      server.rows['weekly_checkins:$memberA'] = const [];
      container.invalidate(coachSubmittedCheckinsProvider);
      await settleReal(t);
      expect(find.text('No check-in selected'), findsOneWidget);
      await closeApp(t);
    });

    testWidgets('CONTROL: a profile edit (userUpdated) keeps them and reads '
        'nothing again', (t) async {
      await open(t);
      await draft(t);
      final reads = server.sent('GET', 'weekly_checkins').length;
      await editUser(t);
      await settleReal(t);
      formOfA(t);
      expect(server.sent('GET', 'weekly_checkins'), hasLength(reads));
      await closeApp(t);
    });
  });

  group('another coach', () {
    testWidgets("A's queue had failed, no-frame A->B, B's own read fails, then a "
        'frame: nothing of A (the kept check-in)', (t) async {
      await open(t);
      await draft(t);
      server.fails.add('GET weekly_checkins:$memberA');
      container.invalidate(coachSubmittedCheckinsProvider);
      await settleReal(t);
      expect(find.text('Amara Osei'), findsOneWidget, reason: 'premise: kept');
      server.fails.add('GET weekly_checkins:$memberB');
      await switchNoFrame(t, memberB);
      for (var i = 0; i < 5; i++) {
        container.read(coachSubmittedCheckinsProvider);
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)));
        await t.idle();
      }
      expect(container.read(coachSubmittedCheckinsProvider),
          isA<AsyncError<List<Map<String, dynamic>>>>(),
          reason: 'premise: failed for B before any frame');
      expect(container.read(coachSubmittedCheckinsProvider).hasValue, isTrue,
          reason: "premise: riverpod still holds A's rows");
      await settleReal(t);
      nothingOfA();
      expect(find.text("Couldn't load your review queue"), findsOneWidget);
      await closeApp(t);
    });

    testWidgets('sign-out -> the same coach, the new read pending: the old '
        'check-in is not kept', (t) async {
      await open(t);
      await draft(t);
      await signOutNoFrame(t);
      await settleReal(t);
      nothingOfA();
      final hold =
          server.holds['GET weekly_checkins:$memberA'] = Completer<void>();
      await switchNoFrame(t, memberA);
      await settleReal(t);
      nothingOfA();
      hold.complete();
      await settleReal(t);
      expect(find.text('Amara Osei'), findsOneWidget);
      expect(text(t, reply()), isEmpty);
      await closeApp(t);
    });

    testWidgets("the queue refreshed before the switch is flushed (no frame): "
        "B's read pending shows no row of A", (t) async {
      await open(t);
      final hold =
          server.holds['GET weekly_checkins:$memberB'] = Completer<void>();
      await switchNoFrame(t, memberB);
      container.invalidate(coachSubmittedCheckinsProvider);
      container.read(coachSubmittedCheckinsProvider);
      await t.pump();
      nothingOfA();
      hold.complete();
      await settleReal(t);
      expect(find.text('Bea Osei'), findsOneWidget);
      await closeApp(t);
    });

    testWidgets("Next tapped with no frame since A->B: A's next client is not "
        'opened as B, recorded, nothing said', (t) async {
      await open(t);
      await draft(t);
      final next = t
          .widget<GestureDetector>(find
              .ancestor(
                  of: find.byIcon(Icons.arrow_forward),
                  matching: find.byType(GestureDetector))
              .first)
          .onTap!;
      await switchNoFrame(t, memberB);
      next();
      await settleReal(t);
      nothingOfA();
      expect(find.text('Bea Osei'), findsOneWidget);
      expect(container.read(selectedCoachCheckinProvider), isNull,
          reason: "THE defect: A's client stored as B's selection");
      expect(origins(), ['CoachCheckinReviewScreen._openNext']);
      expect(find.byType(SnackBar), findsNothing);
      await closeApp(t);
    });

    testWidgets("Send built for A, tapped after the drop: nothing is sent or "
        'said as B, even with a reply B typed', (t) async {
      await open(t);
      await draft(t);
      final submit = t.widget<ElevatedButton>(send()).onPressed!;
      await switchNoFrame(t, memberB);
      await settleReal(t);
      await t.enterText(reply(), 'B types');
      submit();
      await settleReal(t);
      expect(server.writesAs(memberB), isEmpty,
          reason: "THE defect: B's words on A's client's check-in");
      expect(text(t, reply()), 'B types');
      expect(find.byType(SnackBar), findsNothing);
      await closeApp(t);
    });

    for (final (what, leave) in [
      ('A->B', (WidgetTester t) => switchNoFrame(t, memberB)),
      ('sign-out', signOutNoFrame),
    ]) {
      // At a82f993: a notification as B, the notice and the pop.
      testWidgets('$what with no frame during the review PATCH: no write after '
          'it, nothing said, not popped', (t) async {
        await open(t);
        await draft(t);
        final hold =
            server.holds['PATCH weekly_checkins:$memberA'] = Completer<void>();
        await t.tap(send());
        await pumpUntil(
            t, () => server.sent('PATCH', 'weekly_checkins').isNotEmpty,
            what: 'the review');
        await leave(t);
        hold.complete();
        await settleReal(t);
        expect(server.sent('PATCH', 'weekly_checkins').single.who, memberA);
        expect(server.sent('POST', 'notifications'), isEmpty);
        expect(origins(), ['WeeklyCheckinService.submitCoachFeedback.notify']);
        expect(find.byType(SnackBar), findsNothing);
        expect(find.text('BEHIND'), findsNothing);
        expect(container.read(selectedCoachCheckinProvider), isNull);
        nothingOfA();
        await closeApp(t);
      });
    }

    testWidgets('a notice shown to A goes when A does', (t) async {
      await open(t);
      await t.tap(send());
      await t.pump();
      expect(find.text('Please write a feedback message.'), findsOneWidget);
      await switchNoFrame(t, memberB);
      await t.pump();
      await t.pump();
      expect(find.byType(SnackBar), findsNothing);
      await closeApp(t);
    });

    testWidgets("undo does not bring A's reply or recommendation back",
        (t) async {
      await open(t);
      for (final field in [reply, recommendation]) {
        await t.tap(field());
        await t.enterText(field(), 'private to A');
        await t.pump(const Duration(seconds: 1));
      }
      await switchNoFrame(t, memberB);
      // B's queue answers before any frame, so the form is never unmounted and
      // the fields, with their undo history, would be the same ones.
      for (var i = 0; i < 5; i++) {
        container.read(coachSubmittedCheckinsProvider);
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)));
        await t.idle();
      }
      await settleReal(t);
      expect(find.text('Bea Osei'), findsOneWidget, reason: 'premise');
      for (final field in [reply, recommendation]) {
        await t.tap(field());
        await t.pump();
        await undo(t);
        expect(text(t, field()), isEmpty);
      }
      await closeApp(t);
    }, variant: const TargetPlatformVariant({TargetPlatform.linux}));

    testWidgets('CONTROL: the same coach can undo', (t) async {
      await open(t);
      await t.tap(reply());
      await t.enterText(reply(), 'one');
      await t.pump(const Duration(seconds: 1));
      await t.enterText(reply(), 'one two');
      await t.pump(const Duration(seconds: 1));
      await refreshToken(t);
      await settleReal(t);
      await undo(t);
      expect(text(t, reply()), 'one');
      await closeApp(t);
    }, variant: const TargetPlatformVariant({TargetPlatform.linux}));
  });

  group('the fallback queue read', () {
    test("A's first read fails, then B signs in: the second is not asked as B",
        () async {
      server.fails.add('GET weekly_checkins:$memberA');
      final hold =
          server.holds['GET weekly_checkins:$memberA'] = Completer<void>();
      final service = container = ProviderContainer();
      addTearDown(service.dispose);
      final answer = service
          .read(weeklyCheckinServiceProvider)
          .getSubmittedCheckinsForCoach();
      final failed = expectLater(answer, throwsA(anything));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await signInAs(memberB);
      hold.complete();
      await failed;
      expect(server.sent('GET', 'weekly_checkins', memberB), isEmpty);
    });

    test('CONTROL: the same coach falls back to the plain read', () async {
      server.gate = (_) {
        // Only the first one fails.
        scheduleMicrotask(server.fails.clear);
        return null;
      };
      server.fails.add('GET weekly_checkins:$memberA');
      final service = ProviderContainer();
      addTearDown(service.dispose);
      final rows = await service
          .read(weeklyCheckinServiceProvider)
          .getSubmittedCheckinsForCoach();
      expect(rows, hasLength(2));
      expect(server.sent('GET', 'weekly_checkins', memberA), hasLength(2),
          reason: 'premise: the first one failed');
    });
  });
}
