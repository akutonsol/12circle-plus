// P0-FL-59e · points, and the follow-ups of a save, stay with the member who
// earned them (A-11, A-14, W11, W24, S6, S7).
//
// `ScoreService`/`ScoreEngine` asked "who is signed in?" at each step, after
// awaits. One member's action finishing under the next one's session wrote the
// next one's `daily_scores` (addHabitPoints SETS habits_points), points and
// plan. Everything here uses the real services and the real auth client, and
// reads the request log: whose token, which row, how many writes.
//
// HOW TO SEE IT FAIL: put back a82f993's score_service, habit_provider,
// community_provider, nutrition_service, action_item_service and
// coaching_mode_provider; every test but the POSITIVE/NEGATIVE CONTROLs fails.
import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/action_items/data/action_item_service.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/coach/data/coach_program_service.dart';
import 'package:circle_fitness/features/coach/data/score_service.dart';
import 'package:circle_fitness/features/coaching_mode/domain/coaching_mode_provider.dart';
import 'package:circle_fitness/features/community/data/community_service.dart';
import 'package:circle_fitness/features/community/data/live_community_service.dart';
import 'package:circle_fitness/features/community/domain/community_provider.dart';
import 'package:circle_fitness/features/habits/data/models/habit_model.dart';
import 'package:circle_fitness/features/habits/domain/habit_provider.dart';
import 'package:circle_fitness/features/nutrition/data/nutrition_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/member_switch_server.dart';

Future<void> until(bool Function() done, String what) async {
  final clock = Stopwatch()..start();
  while (!done()) {
    if (clock.elapsed > const Duration(seconds: 10)) fail('never: $what');
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 60));

void main() {
  final server = MemberSwitchServer();
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dexterous.com/flutter/local_notifications'),
            (call) async => call.method == 'initialize' ? true : null);
    await initTwoMemberSupabase(server);
  });

  setUp(() async {
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
    await signInAs(memberA);
  });
  tearDown(resetFailureSink);

  Iterable<String> origins() => reported.map((f) => f.origin);

  /// Writes the request log shows under B's token.
  Iterable<SeenRequest> asB() => server.writes().where((w) => w.who == memberB);

  Map<String, Object?> habit(String id) =>
      {'id': id, 'name': 'Walk $id', 'target_value': 1};

  Future<void> loaded(LiveHabitNotifier n) => until(
      () => n.state is AsyncData, 'the habits');

  void twoHabits() => server.rows['client_habits'] = {
        memberA: [habit('a1'), habit('a2')],
        memberB: [habit('b1')],
      };

  group('ScoreService', () {
    test("A's community points, the day's read answers after B signed in: B's "
        'day is neither read nor written', () async {
      final hold = server.holds['GET daily_scores:$memberA'] = Completer();
      final award = ScoreService().addCommunityPoints();
      await until(() => server.reads('daily_scores').isNotEmpty, 'the read');
      await signInAs(memberB);
      hold.complete();
      await award;
      await settle();
      expect(server.writes('daily_scores'), isEmpty,
          reason: "A's post was scored into B's daily_scores");
      expect(server.reads('daily_scores', memberB), isEmpty);
      expect(origins(), contains('ScoreService.identity'));
    });

    test("A's habit count, B signs in mid-award: nothing is written", () async {
      final hold = server.holds['GET daily_scores:$memberA'] = Completer();
      final award = ScoreService().addHabitPoints(2, 2);
      await until(() => server.reads('daily_scores').isNotEmpty, 'the read');
      await signInAs(memberB);
      hold.complete();
      await award.catchError((_) {});
      await settle();
      expect(server.writes('daily_scores'), isEmpty);
    });

    test('signed out mid-award: nothing is written', () async {
      final hold = server.holds['GET daily_scores:$memberA'] = Completer();
      final award = ScoreService().addCheckinPoints();
      await until(() => server.reads('daily_scores').isNotEmpty, 'the read');
      await signOut();
      hold.complete();
      await award.catchError((_) {});
      await settle();
      expect(server.writes('daily_scores'), isEmpty);
    });

    test('POSITIVE CONTROL: same member, token refreshed mid-award: one row, '
        'theirs, the other points kept', () async {
      server.rows['daily_scores'] = {
        memberA: [
          {'workout_points': 30, 'nutrition_points': 7},
        ],
      };
      final hold = server.holds['GET daily_scores:$memberA'] = Completer();
      final award = ScoreService().addHabitPoints(1, 2);
      await until(() => server.reads('daily_scores').isNotEmpty, 'the read');
      await refreshSession();
      hold.complete();
      await award;
      final w = server.writes('daily_scores').single;
      expect((w.who, w.row['user_id']), (memberA, memberA));
      expect(w.row['habits_points'], 10);
      expect(w.row['total_score'], 47);
      expect(reported, isEmpty);
    });
  });

  group('habit toggle', () {
    test("A's tick answers after B signed in: B's habits_points are not "
        "overwritten with A's count, and B gets no habit points", () async {
      twoHabits();
      final n = LiveHabitNotifier(CoachProgramService(), ScoreService());
      await loaded(n);
      final hold = server.holds['POST habit_logs:$memberA'] = Completer();
      final toggle = n.toggleComplete('a1');
      await until(() => server.writes('habit_logs').isNotEmpty, 'the log');
      await signInAs(memberB);
      hold.complete();
      await toggle;
      await settle();
      expect(server.writes('habit_logs').single.row['user_id'], memberA);
      expect(asB(), isEmpty,
          reason: "B's daily_scores and score events were written from A's "
              'habits: ${asB().toList()}');
      expect(n.state.valueOrNull, isNull,
          reason: "A's habits do not stay up");
    });

    test("the log itself fails after B signed in: B is not told about A's tick",
        () async {
      twoHabits();
      final n = LiveHabitNotifier(CoachProgramService(), ScoreService());
      await loaded(n);
      final hold = server.holds['POST habit_logs:$memberA'] = Completer();
      server.fails.add('POST habit_logs:$memberA');
      final toggle = n.toggleComplete('a1');
      await until(() => server.writes('habit_logs').isNotEmpty, 'the log');
      await signInAs(memberB);
      hold.complete();
      expect(await toggle, isTrue, reason: 'false says "Couldn\'t save that"');
      expect(origins(), contains('LiveHabitNotifier.toggleComplete'));
    });

    test("B taps a habit of A's still up: nothing is sent", () async {
      twoHabits();
      final n = LiveHabitNotifier(CoachProgramService(), ScoreService());
      await loaded(n);
      await signInAs(memberB);
      expect(await n.toggleComplete('a1'), isFalse);
      expect(await n.updateValue('a1', 1).catchError((_) => false), isFalse);
      await settle();
      expect(asB(), isEmpty);
    });

    test("A's reload answers after B signed in: A's habits do not appear",
        () async {
      twoHabits();
      final n = LiveHabitNotifier(CoachProgramService(), ScoreService());
      await loaded(n);
      final hold = server.holds['GET client_habits:$memberA'] = Completer();
      final reload = n.reload();
      await signInAs(memberB);
      hold.complete();
      await reload;
      expect(n.state.valueOrNull, isNull);
    });

    test('POSITIVE CONTROL: a saved tick awards its own member', () async {
      twoHabits();
      final n = LiveHabitNotifier(CoachProgramService(), ScoreService());
      await loaded(n);
      expect(await n.toggleComplete('a1'), isTrue);
      await until(() => server.writes('award_points').isNotEmpty, 'the award');
      final day = server.writes('daily_scores').single;
      expect((day.who, day.row['user_id'], day.row['habits_points']),
          (memberA, memberA, 10));
      expect(server.writes('award_points').single.who, memberA);
      expect(n.state.valueOrNull!.first.isCompletedToday, isTrue);
      expect(reported, isEmpty);
    });

    test('a token refresh keeps the list; another member gets a new one',
        () async {
      twoHabits();
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.listen(liveHabitNotifierProvider, (_, __) {});
      List<Habit>? shown() => c.read(liveHabitNotifierProvider).valueOrNull;
      await until(() => shown()?.length == 2, "A's habits");
      final before = c.read(liveHabitNotifierProvider.notifier);
      final reads = server.reads('client_habits').length;
      await refreshSession();
      await settle();
      expect(identical(c.read(liveHabitNotifierProvider.notifier), before),
          isTrue, reason: 'a refresh threw the list away');
      expect(server.reads('client_habits').length, reads);
      // Delayed: B's own read pending, then failed — never A's habits.
      final hold = server.holds['GET client_habits:$memberB'] = Completer();
      server.fails.add('GET client_habits:$memberB');
      await signInAs(memberB);
      await settle();
      expect(shown(), isNull);
      hold.complete();
      await until(() => c.read(liveHabitNotifierProvider).hasError, 'the fail');
      expect(shown(), isNull);
      // Signed out, and the same member back in: their own list again.
      await signOut();
      await settle();
      await signInAs(memberA);
      await until(() => shown()?.length == 2, "A's habits again");
    });
  });

  group('community', () {
    PostNotifier notifier() =>
        PostNotifier(LiveCommunityService(), CommunityService(), ScoreService());

    test("A's post answers after B signed in: no points for B", () async {
      final n = notifier();
      await until(() => n.state is AsyncData, 'the feed');
      final hold = server.holds['POST community_posts:$memberA'] = Completer();
      final post = n.addPost('Leg day');
      await until(() => server.writes('community_posts').isNotEmpty, 'post');
      await signInAs(memberB);
      hold.complete();
      await post.catchError((_) {});
      await settle();
      expect(server.writes('community_posts').single.row['user_id'], memberA);
      expect(asB(), isEmpty);
      expect(server.reads('daily_scores', memberB), isEmpty);
      expect(origins(), contains('PostNotifier.identity'));
    });

    test("A's draft, posted, commented or reacted once B is signed in: nothing "
        'is sent, and it is not taken for saved', () async {
      final n = notifier();
      await until(() => n.state is AsyncData, 'the feed');
      await signInAs(memberB);
      await expectLater(n.addPost('Leg day'), throwsStateError);
      await expectLater(n.addComment('p1', 'nice'), throwsStateError);
      await expectLater(n.toggleLike('p1'), throwsStateError);
      expect(asB(), isEmpty);
    });

    test('S7: the feed is disposed while the post is out: no state error',
        () async {
      final n = notifier();
      await until(() => n.state is AsyncData, 'the feed');
      final hold = server.holds['POST community_posts:$memberA'] = Completer();
      final post = n.addPost('Leg day');
      await until(() => server.writes('community_posts').isNotEmpty, 'post');
      n.dispose();
      hold.complete();
      await post;
    });

    test('POSITIVE CONTROL: the post is shown and its member awarded', () async {
      final n = notifier();
      await until(() => n.state is AsyncData, 'the feed');
      await n.addPost('Leg day');
      await until(() => server.writes('daily_scores').isNotEmpty, 'the day');
      expect(n.state.valueOrNull!.single.content, 'Leg day');
      expect(server.writes('daily_scores').single.row['community_points'], 10);
      expect(server.writes().map((w) => w.who).toSet(), {memberA});
      expect(reported, isEmpty);
    });
  });

  group('meal log', () {
    Future<void> log() => NutritionService().logMeal(
        mealType: 'lunch', foodName: 'Rice', calories: 1, protein: 1, carbs: 1,
        fat: 1, servingSize: 1, servingUnit: 'g');

    test("A's meal answers after B signed in: no points for B, B's day and "
        'plan are not read', () async {
      final hold = server.holds['POST nutrition_logs:$memberA'] = Completer();
      final done = log();
      await until(() => server.writes('nutrition_logs').isNotEmpty, 'meal');
      await signInAs(memberB);
      hold.complete();
      await done;
      await settle();
      expect(server.writes('nutrition_logs').single.row['user_id'], memberA);
      expect(asB(), isEmpty);
      expect(server.seen.where((r) => r.who == memberB), isEmpty);
    });

    test("B signs in while A's totals are read: A's % is not written for B",
        () async {
      final hold = server.holds['GET nutrition_logs:$memberA'] = Completer();
      final done = log();
      await until(() => server.reads('nutrition_logs').isNotEmpty, 'totals');
      await signInAs(memberB);
      hold.complete();
      await done;
      await settle();
      expect(asB(), isEmpty);
      expect(server.writes('daily_scores'), isEmpty);
    });

    test('POSITIVE CONTROL: the meal and its points are one member\'s',
        () async {
      server.rows['nutrition_logs'] = {
        memberA: [
          {'calories': 2000, 'protein': 120},
        ],
      };
      await log();
      await until(
          () => server.writes('award_points').length == 3, 'the awards');
      expect(server.writes('daily_scores').single.row['nutrition_points'], 30);
      expect(server.writes().map((w) => w.who).toSet(), {memberA});
      expect(reported, isEmpty);
    });
  });

  group('action item', () {
    test('S6: 0 rows (not this member\'s item) is not success: false, no '
        'points, recorded', () async {
      server.zeroRows.add('PATCH action_items:$memberA');
      expect(await ActionItemService().completeActionItem('i1'), isFalse);
      await settle();
      expect(server.writes('award_points'), isEmpty);
      expect(origins(), ['ActionItemService.completeActionItem']);
    });

    test("A's completion answers after B signed in: no points for B", () async {
      final hold = server.holds['PATCH action_items:$memberA'] = Completer();
      final done = ActionItemService().completeActionItem('i1');
      await until(() => server.writes('action_items').isNotEmpty, 'the update');
      await signInAs(memberB);
      hold.complete();
      expect(await done, isTrue);
      await settle();
      expect(asB(), isEmpty);
    });

    test('S6: reopening 0 rows is recorded', () async {
      server.zeroRows.add('PATCH action_items:$memberA');
      await ActionItemService().reopen('i1');
      expect(origins(), ['ActionItemService.reopen']);
    });

    test('POSITIVE CONTROL: completed, and its member awarded', () async {
      expect(await ActionItemService().completeActionItem('i1'), isTrue);
      await until(() => server.writes('award_points').isNotEmpty, 'the award');
      expect(server.writes('award_points').single.who, memberA);
      expect(reported, isEmpty);
    });
  });

  group('coaching mode', () {
    late ProviderContainer c;
    Future<CoachingModeNotifier> open() async {
      server.rows['user_profiles'] = {
        memberA: [
          {'coaching_mode': 'coach_guided'},
        ],
        memberB: [
          {'coaching_mode': 'ai_guided'},
        ],
      };
      c = ProviderContainer();
      addTearDown(c.dispose);
      c.listen(coachingModeNotifierProvider, (_, __) {});
      await until(
          () => c.read(coachingModeNotifierProvider).hasValue, 'the mode');
      return c.read(coachingModeNotifierProvider.notifier);
    }

    Iterable<SeenRequest> planRpcs() => server.writes().where((w) =>
        w.target == 'generate_client_plan' ||
        w.target == 'deactivate_self_generated_plan');

    for (final mode in [CoachingMode.selfGuided, CoachingMode.coachGuided]) {
      test("${mode.name}: A's save answers after B signed in: B's plan is not "
          'touched', () async {
        final n = await open();
        final hold = server.holds['PATCH user_profiles:$memberA'] = Completer();
        final save = n.setMode(mode);
        await until(() => server.writes('user_profiles').isNotEmpty, 'save');
        await signInAs(memberB);
        await settle();
        hold.complete();
        await save.catchError((_) {});
        await settle();
        expect(planRpcs(), isEmpty,
            reason: "B's plan was rebuilt or deactivated");
        expect(c.read(coachingModeNotifierProvider).value,
            CoachingMode.aiGuided, reason: "B's own mode");
        expect(origins(), contains('CoachingModeNotifier.setMode.identity'));
      });
    }

    test("the save fails after B signed in: A's old mode is not put back over "
        'a disposed notifier', () async {
      final n = await open();
      final hold = server.holds['PATCH user_profiles:$memberA'] = Completer();
      server.fails.add('PATCH user_profiles:$memberA');
      final save = n.setMode(CoachingMode.selfGuided);
      await until(() => server.writes('user_profiles').isNotEmpty, 'save');
      await signInAs(memberB);
      await settle();
      hold.complete();
      await expectLater(save, throwsA(isA<PostgrestException>()),
          reason: 'not a "used after dispose" StateError');
      expect(c.read(coachingModeNotifierProvider).value, CoachingMode.aiGuided);
    });

    test("A's notifier, asked once B is signed in: nothing is sent", () async {
      final n = await open();
      await signInAs(memberB);
      await settle();
      await expectLater(
          n.setMode(CoachingMode.selfGuided), throwsA(isA<StateError>()));
      expect(server.writes(), isEmpty);
    });

    test('POSITIVE CONTROL: saved, plan synced, and a token refresh keeps the '
        'notifier', () async {
      final n = await open();
      await n.setMode(CoachingMode.selfGuided);
      expect(server.writes('user_profiles').single.query['id'], 'eq.$memberA');
      expect(planRpcs().single.who, memberA);
      expect(c.read(coachingModeNotifierProvider).value,
          CoachingMode.selfGuided);
      final reads = server.reads('user_profiles').length;
      await refreshSession();
      await settle();
      expect(identical(c.read(coachingModeNotifierProvider.notifier), n),
          isTrue);
      expect(server.reads('user_profiles').length, reads);
      expect(c.read(currentUserProvider)?.id, memberA);
    });
  });
}
