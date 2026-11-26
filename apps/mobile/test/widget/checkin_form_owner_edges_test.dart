import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/checkins/data/weekly_checkin_service.dart';
import 'package:circle_fitness/features/checkins/presentation/daily_checkin_screen.dart';
import 'package:circle_fitness/features/coach/domain/coach_provider.dart';
import 'package:circle_fitness/features/workout/presentation/widgets/section_load_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/owned_writes_postgrest.dart';
import '../support/owner_harness.dart';
import '../support/pump_until.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-59c round 2 (and FL-60 for the form) · the weekly check-in: what has not
// been read is not "not done", nothing is submitted over it, and each read of a
// save is sent as the member it is for.
//
// HOW TO SEE IT FAIL: run against 6f8c693's checkins files (a82f993's where
// marked).

const _done = 'Already Checked In!';
const _failed = "Couldn't load this week's check-in";

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

  bool isStreak(Asked a) =>
      a.table == 'weekly_checkins' && a.query['select'] == 'week_start_date';

  Future<void> open(WidgetTester t) async {
    tallView(t);
    await t.pumpWidget(ProviderScope(
      overrides: [assignedCoachProvider.overrideWith((ref) async => null)],
      child: const MaterialApp(home: DailyCheckinScreen()),
    ));
    await settleReal(t);
  }

  Finder notes() => find.byType(TextField);
  Finder submitButton() => find.byIcon(Icons.check_circle_outline);
  VoidCallback? submitTap(WidgetTester t) => t
      .widget<GestureDetector>(find
          .ancestor(of: submitButton(), matching: find.byType(GestureDetector))
          .first)
      .onTap;

  group('the week that has not been read (FL-60)', () {
    testWidgets('pending: no form and no submit, announced; then the form',
        (t) async {
      final handle = t.ensureSemantics();
      final hold =
          server.holds['GET weekly_checkins:$memberA'] = Completer<void>();
      await open(t);
      expect(notes(), findsNothing,
          reason: 'THE defect: a blank form, "not done", over an unread week');
      expect(submitButton(), findsNothing);
      expect(find.bySemanticsLabel('Loading your check-in'), findsOneWidget);
      hold.complete();
      await settleReal(t);
      expect(notes(), findsOneWidget, reason: 'NEGATIVE CONTROL: absent is not done');
      expect(submitTap(t), isNotNull);
      expect(reported, isEmpty);
      handle.dispose();
      await closeApp(t);
    });

    testWidgets("after A->B, B's read pending shows no form either", (t) async {
      await open(t);
      expect(notes(), findsOneWidget);
      final hold =
          server.holds['GET weekly_checkins:$memberB'] = Completer<void>();
      await switchNoFrame(t, memberB);
      await settleReal(t);
      expect(notes(), findsNothing);
      hold.complete();
      await settleReal(t);
      expect(notes(), findsOneWidget);
      await closeApp(t);
    });

    testWidgets('failed: recorded, said with a busy-aware 44px retry in a live '
        'region, no submit; the retry opens the form', (t) async {
      final handle = t.ensureSemantics();
      server.fails.add('GET weekly_checkins:$memberA');
      await open(t);
      expect(find.text(_failed), findsOneWidget);
      expect(liveRegion(_failed), findsOneWidget);
      expect(notes(), findsNothing);
      expect(submitButton(), findsNothing);
      expect(find.textContaining('SECRET'), findsNothing);
      expect(origins(), contains('WeeklyCheckinService.weekStatus'),
          reason: 'THE defect: recorded nowhere');
      final retry = find.byType(TextButton);
      expect(t.getSize(retry).height, greaterThanOrEqualTo(44));

      server.fails.clear();
      final hold =
          server.holds['GET weekly_checkins:$memberA'] = Completer<void>();
      final before = server.sent('GET', 'weekly_checkins').length;
      await t.tap(retry);
      await t.pump();
      expect(find.text(_failed), findsOneWidget, reason: 'busy, not blinking away');
      expect(t.widget<TextButton>(retry).onPressed, isNull);
      await t.tap(retry, warnIfMissed: false);
      await settleReal(t);
      expect(server.sent('GET', 'weekly_checkins').length, before + 1);
      hold.complete();
      await settleReal(t);
      expect(find.text(_failed), findsNothing);
      expect(notes(), findsOneWidget);
      handle.dispose();
      await closeApp(t);
    });

    testWidgets('a retry built for A, tapped with no frame since A->B: reads '
        "B's week, once, and A's failure is not B's", (t) async {
      server.fails.add('GET weekly_checkins:$memberA');
      await open(t);
      final retry = t.widget<TextButton>(find.byType(TextButton)).onPressed!;
      await switchNoFrame(t, memberB);
      retry();
      await settleReal(t);
      expect(find.text(_failed), findsNothing);
      expect(notes(), findsOneWidget);
      expect(
          server
              .sent('GET', 'weekly_checkins', memberB)
              .where((a) => !isStreak(a)),
          hasLength(1));
      await closeApp(t);
    });

    for (final scale in [2.0, 3.0]) {
      testWidgets('the failure fits 320dp at ${scale}x, its retry reachable',
          (t) async {
        t.view
          ..devicePixelRatio = 1
          ..physicalSize = const Size(320, 640);
        addTearDown(t.view.reset);
        server.fails.add('GET weekly_checkins:$memberA');
        await t.pumpWidget(ProviderScope(
          overrides: [assignedCoachProvider.overrideWith((ref) async => null)],
          child: MaterialApp(
            // The header is not this test's; only the failure is measured.
            home: Builder(
              builder: (c) => MediaQuery(
                data: MediaQuery.of(c)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: const DailyCheckinScreen(),
              ),
            ),
          ),
        ));
        await settleReal(t);
        // The header overflows here, before and after this change; not the
        // failure, which is measured itself.
        t.takeException();
        for (final f in [
          find.byType(SectionLoadFailure),
          find.text(_failed),
          find.byType(TextButton),
        ]) {
          expect(t.getRect(f).left, greaterThanOrEqualTo(0));
          expect(t.getRect(f).right, lessThanOrEqualTo(320));
        }
        expect(t.widget<Text>(find.text(_failed)).style!.fontSize, 13);
        await t.ensureVisible(find.text('Try again'));
        await t.pump();
        final before = server.sent('GET', 'weekly_checkins').length;
        server.holds['GET weekly_checkins:$memberA'] = Completer<void>();
        await t.tap(find.text('Try again'));
        await settleReal(t);
        expect(server.sent('GET', 'weekly_checkins').length, before + 1,
            reason: 'reachable');
        await closeApp(t);
        server.holds['GET weekly_checkins:$memberA']!.complete();
        await settleReal(t);
      });
    }

    test('getCurrentWeekCheckin: a failure is thrown and recorded, not a pending '
        'week; a missing row is pending', () async {
      server.fails.add('GET weekly_checkins:$memberA');
      await expectLater(WeeklyCheckinService().getCurrentWeekCheckin(),
          throwsA(isA<PostgrestException>()));
      expect(origins(), ['WeeklyCheckinService.getCurrentWeekCheckin']);
      server.fails.clear();
      expect((await WeeklyCheckinService().getCurrentWeekCheckin()).id,
          startsWith('pending-'));
    });

    testWidgets('a failed streak is no number, recorded; the form is still there',
        (t) async {
      server.rows['weekly_checkins:$memberA'] = const [];
      server.gate = (a) {
        if (isStreak(a)) server.fails.add('GET weekly_checkins:$memberA');
        return null;
      };
      await open(t);
      expect(origins(), ['WeeklyCheckinService.getCheckinStreak']);
      expect(find.text('0'), findsNothing);
      expect(notes(), findsOneWidget);
      await closeApp(t);
    });
  });

  group('the streak read', () {
    final streakRows = [
      for (final back in [7, 14, 21])
        {
          // Not this week's status, so the form shows.
          'status': 'pending',
          'week_start_date': DateTime(DateTime.now().year, DateTime.now().month,
                  DateTime.now().day - (DateTime.now().weekday - 1) - back)
              .toIso8601String()
              .split('T')[0],
        }
    ];

    testWidgets('CONTROL: the member sees their own', (t) async {
      server.rows['weekly_checkins:$memberA'] = streakRows;
      await open(t);
      expect(find.byIcon(Icons.local_fire_department), findsOneWidget);
      await closeApp(t);
    });

    // At a82f993 (and the mutant that removes the second check).
    for (final frame in [true, false]) {
      testWidgets(
          "A->B ${frame ? '' : 'with no frame '}during it: A's done week and "
          'streak are not shown to B', (t) async {
        server.rows['weekly_checkins:$memberA'] = [
          {...streakRows.first, 'status': 'submitted'},
          ...streakRows.skip(1),
        ];
        final hold = Completer<void>();
        server.gate =
            (a) => isStreak(a) && a.who == memberA ? hold : null;
        await open(t);
        expect(server.log.where(isStreak), hasLength(1), reason: 'premise');
        await switchNoFrame(t, memberB);
        if (frame) await settleReal(t);
        hold.complete();
        await settleReal(t);
        expect(find.text(_done), findsNothing);
        expect(find.byIcon(Icons.local_fire_department), findsNothing,
            reason: "A's streak in B's header");
        expect(notes(), findsOneWidget);
        await closeApp(t);
      });
    }
  });

  group('a save in flight', () {
    final plan = [
      {'calories_target': 2000}
    ];

    Future<bool> submit() => WeeklyCheckinService().submitWeeklyCheckin(
        mood: 3, energy: 3, stress: 2, sleepHoursAvg: 7);

    for (final (held, next) in [
      ('client_nutrition_plans', 'nutrition_logs'),
      ('client_nutrition_plans', 'weekly_checkins'),
      ('weekly_checkins', 'coach_client_relationships'),
    ]) {
      test('A->B during the $held read: $next is not read as B, nothing is '
          'written', () async {
        server.rows['client_nutrition_plans:$memberA'] = plan;
        final hold = server.holds['GET $held:$memberA'] = Completer<void>();
        final answer = submit();
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await signInAs(memberB);
        hold.complete();
        expect(await answer, isFalse);
        expect(server.log.where((a) => a.who == memberB), isEmpty,
            reason: 'a read sent as B says nothing of A\'s week');
        expect(server.sent('GET', next).where((a) => a.who != memberA), isEmpty);
      });
    }

    testWidgets('A->B->A, with frames, during the week read: the dropped form '
        'does not save over the week', (t) async {
      await open(t);
      await t.enterText(notes(), 'typed before');
      final before = server.sent('GET', 'weekly_checkins').length;
      final hold =
          server.holds['GET weekly_checkins:$memberA'] = Completer<void>();
      await t.tap(submitButton());
      await pumpUntil(
          t, () => server.sent('GET', 'weekly_checkins').length > before,
          what: 'the week read');
      server.holds.clear();
      await switchNoFrame(t, memberB);
      await settleReal(t);
      await switchNoFrame(t, memberA);
      await settleReal(t);
      hold.complete();
      await settleReal(t);
      expect(server.log.where((a) => a.method != 'GET'), isEmpty,
          reason: 'THE defect: the dropped answers were saved');
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Weekly Check-In Complete!'), findsNothing);
      await closeApp(t);
    });

    // Round 4 (lead mutant 59c-10: the owner check on the "not saved" path
    // removed). The save is refused as A's, so it answers `false`; with the
    // switch already drawn, that refusal was said to B as B's own failure.
    for (final frame in [true, false]) {
      testWidgets(
          'A->B ${frame ? 'drawn' : 'with no frame'} during the save: A\'s '
          'refused save is not said to B as a failure', (t) async {
        await open(t);
        await t.enterText(notes(), 'private to A');
        final before = server.sent('GET', 'weekly_checkins').length;
        final hold =
            server.holds['GET weekly_checkins:$memberA'] = Completer<void>();
        await t.tap(submitButton());
        await pumpUntil(
            t, () => server.sent('GET', 'weekly_checkins').length > before,
            what: 'the week read of the save');
        server.holds.clear();
        await switchNoFrame(t, memberB);
        if (frame) {
          await settleReal(t);
          expect(t.widget<TextField>(notes()).controller!.text, isEmpty,
              reason: 'premise: the form was dropped before the answer');
        }
        hold.complete();
        await settleReal(t);
        expect(server.log.where((a) => a.method != 'GET'), isEmpty);
        expect(origins(), contains('WeeklyCheckinService.submitWeeklyCheckin'),
            reason: 'the refusal is recorded');
        expect(find.text('Failed to save. Please try again.'), findsNothing,
            reason: "A's refused save said to B");
        expect(find.byType(SnackBar), findsNothing);
        expect(find.text('Weekly Check-In Complete!'), findsNothing);
        expect(notes(), findsOneWidget, reason: "B's own form");
        await closeApp(t);
      });
    }

    testWidgets('CONTROL: the same member, a failed save is said once and the '
        'answers stay', (t) async {
      await open(t);
      await t.enterText(notes(), 'mine');
      server.fails.add('POST weekly_checkins:$memberA');
      await t.tap(submitButton());
      await settleReal(t);
      expect(find.text('Failed to save. Please try again.'), findsOneWidget);
      expect(t.widget<TextField>(notes()).controller!.text, 'mine');
      await closeApp(t);
    });

    testWidgets('sign-out during the save: the row is kept, nothing is awarded, '
        'nothing is said', (t) async {
      await open(t);
      final hold =
          server.holds['POST weekly_checkins:$memberA'] = Completer<void>();
      await t.tap(submitButton());
      await pumpUntil(t, () => server.sent('POST', 'weekly_checkins').isNotEmpty,
          what: 'the save');
      await signOutNoFrame(t);
      hold.complete();
      await settleReal(t);
      expect(server.log.where((a) => a.method != 'GET'), hasLength(1));
      expect(origins(), [
        'WeeklyCheckinService.submitWeeklyCheckin.dailyPoints',
        'WeeklyCheckinService.submitWeeklyCheckin.weeklyPoints',
      ]);
      expect(find.text('Weekly Check-In Complete!'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      await closeApp(t);
    });
  });

  group('the form', () {
    testWidgets('CONTROL: a profile edit (userUpdated) keeps the answers, reads '
        'nothing again, and they save once', (t) async {
      await open(t);
      await t.enterText(notes(), 'kept');
      final reads = server.sent('GET', 'weekly_checkins').length;
      await editUser(t);
      await settleReal(t);
      expect(t.widget<TextField>(notes()).controller!.text, 'kept');
      expect(server.sent('GET', 'weekly_checkins'), hasLength(reads));
      await t.tap(submitButton());
      await settleReal(t);
      expect(server.sent('POST', 'weekly_checkins').single.json['notes'], 'kept');
      await closeApp(t);
    });

    testWidgets("Submit built for A, tapped after the drop: B's week is not "
        'saved by it', (t) async {
      await open(t);
      final submit = submitTap(t)!;
      await switchNoFrame(t, memberB);
      await settleReal(t);
      submit();
      await settleReal(t);
      expect(server.log.where((a) => a.method != 'GET'), isEmpty,
          reason: 'the button was drawn for A');
      expect(origins(), ['DailyCheckinScreen._submit']);
      await closeApp(t);
    });

    testWidgets('a notice shown to A goes when A does', (t) async {
      await open(t);
      server.fails.add('POST weekly_checkins:$memberA');
      await t.tap(submitButton());
      await settleReal(t);
      expect(find.byType(SnackBar), findsOneWidget, reason: 'premise');
      await switchNoFrame(t, memberB);
      await t.pump();
      await t.pump();
      expect(find.byType(SnackBar), findsNothing);
      await settleReal(t);
      await closeApp(t);
    });

    testWidgets("undo does not bring A's notes back", (t) async {
      await open(t);
      await t.tap(notes());
      await t.enterText(notes(), 'private to A');
      await t.pump(const Duration(seconds: 1));
      final submit = submitTap(t)!;
      await switchNoFrame(t, memberB);
      // Dropped by the tap, and B's week read, before any frame: the form is
      // never unmounted, and the field would be the same one.
      submit();
      for (var i = 0; i < 8; i++) {
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)));
        await t.idle();
      }
      expect(server.sent('GET', 'weekly_checkins', memberB), isNotEmpty,
          reason: 'premise');
      await settleReal(t);
      await t.tap(notes());
      await t.pump();
      await undo(t);
      expect(t.widget<TextField>(notes()).controller!.text, isEmpty);
      await closeApp(t);
    }, variant: const TargetPlatformVariant({TargetPlatform.linux}));
  });
}
