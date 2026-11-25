import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/core/realtime/realtime.dart';
import 'package:circle_fitness/features/activity/presentation/activity_screen.dart';
import 'package:circle_fitness/features/ai_nutrition/presentation/meal_plan_screen.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/challenges/domain/challenge_provider.dart';
import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart';
import 'package:circle_fitness/features/coach/domain/coach_provider.dart';
import 'package:circle_fitness/features/community/domain/community_provider.dart';
import 'package:circle_fitness/features/dashboard/domain/dashboard_provider.dart';
import 'package:circle_fitness/features/dashboard/presentation/directory_screen.dart';
import 'package:circle_fitness/features/nutrition/domain/nutrition_provider.dart';
import 'package:circle_fitness/features/workout/data/models/workout_model.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/activity_server.dart';
import '../support/fit_matrix.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-60b round 3 · a read that is not finished says nothing about whose it
// is. A list invalidated before the change of account is flushed is
// `AsyncData(isLoading: true)` of A's rows under B's uid: at e708fda Activity's
// challenges took it as B's (A's JOINED rows), and kept it when B's own read
// failed; the meal plan form took A's targets the same way. And a refresh in
// flight at the switch is never notified, so a reader that does not watch the
// uid went on drawing A's.
//
// A real auth client, real transitions, no AccountScope. The streak, classes
// and events are the real providers; the challenges are the real read, keyed
// either way ([_Key]); the other reads are replaced, and keyed either way.
//
// HOW TO SEE IT FAIL: `git checkout e708fda --` activity_screen.dart,
// directory_screen.dart, meal_plan_screen.dart and dashboard_provider.dart;
// the controls pass, except where one says otherwise.

const _failed = "Couldn't load challenges";
const _streakFailed = "Couldn't load your streak";

Map<String, Object?> _row(String id) => {
      'id': id,
      'title': 'Challenge $id',
      'description': '',
      'type': 'steps',
      'status': 'active',
      'target_value': 1000,
      'unit': 'steps',
    };

Workout _workout(String title) => Workout(
      id: title,
      title: title,
      description: '',
      estimatedDuration: 40,
      difficulty: '',
      category: '',
      exercises: const [],
      scheduledDate: DateTime.now(),
    );

/// How a replaced read follows the sign-in. `AsyncData(isLoading)` of A's under
/// B's uid needs a read keyed by uid (P0-FL-59f keys the challenges so; the
/// ruled pattern). Keyed by the whole User, as the others are today, the same
/// moment is `AsyncLoading` of A's.
enum _Key { uid, user }

var _key = _Key.uid;

String? _signedIn(Ref ref) => _key == _Key.uid
    ? ref.watch(currentUserProvider.select((u) => u?.id))
    : ref.watch(currentUserProvider)?.id;

/// A read replaced here: it follows the uid, can be held or failed for one
/// member, and answers per member.
class _Reads<T> {
  _Reads(this.answers);
  final Map<String, T> answers;
  final holds = <String, Completer<void>>{};
  final fails = <String>{};

  Future<T> call(Ref ref) async {
    final uid = _signedIn(ref) ?? 'nobody';
    final hold = holds[uid];
    if (hold != null) await hold.future;
    if (fails.contains(uid)) throw StateError('SECRET read');
    return answers[uid]!;
  }
}

Iterable<(_Key, MapEntry<String, T>)> _ways<T>(Map<String, T> around) sync* {
  for (final key in _Key.values) {
    for (final way in around.entries) {
      yield (key, way);
    }
  }
}

void main() {
  late ActivityServer server;
  late _Reads<List<Map<String, dynamic>>> month;
  late _Reads<List<Map<String, dynamic>>> week;
  late _Reads<List<Workout>> workouts;
  late _Reads<Map<String, Map<String, dynamic>>> statuses;
  late _Reads<Map<String, double>> goals;
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = ActivityServer();
    await initTwoMemberSupabase(server);
  });

  setUp(() async {
    server
      ..reset()
      ..challenges.addAll([_row('one'), _row('two')])
      ..participants.add(
          {'challenge_id': 'one', 'user_id': memberA, 'current_progress': 500})
      ..days[memberA] = 9
      ..days[memberB] = 2;
    month = _Reads({memberA: const [], memberB: const [], 'nobody': const []});
    week = _Reads({memberA: const [], memberB: const [], 'nobody': const []});
    workouts = _Reads({
      memberA: [_workout("Avery's Leg Day")],
      memberB: [_workout('Blake Push')],
      'nobody': const [],
    });
    statuses =
        _Reads({memberA: const {}, memberB: const {}, 'nobody': const {}});
    goals = _Reads({
      memberA: {'calories': 2600, 'protein': 190, 'carbs': 300, 'fat': 90},
      memberB: {'calories': 1500, 'protein': 100, 'carbs': 150, 'fat': 50},
      'nobody': {'calories': 2000},
    });
    _key = _Key.uid;
    reported.clear();
    setFailureSink(reported.add);
    await signInAs(memberA);
  });
  tearDown(resetFailureSink);

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 8; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<ProviderContainer> show(WidgetTester t, Widget screen) async {
    fitWindow(t, 430, 9000, 1);
    t.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final c = ProviderContainer(overrides: [
      currentFirstNameProvider.overrideWithValue('Sam'),
      confirmedCurrentProfileProvider.overrideWithValue(null),
      tableTickerProvider.overrideWith((ref, table) => Stream.value(0)),
      liveGroupsProvider.overrideWith((ref) async => const []),
      assignedCoachProvider.overrideWith((ref) async => null),
      todayNutritionProvider.overrideWith((ref) async => const {}),
      monthScoresProvider.overrideWith((ref) => month(ref)),
      weekScoresProvider.overrideWith((ref) => week(ref)),
      assignedWorkoutsProvider.overrideWith((ref) => workouts(ref)),
      programSessionStatusProvider.overrideWith((ref) => statuses(ref)),
      nutritionGoalsProvider.overrideWith((ref) => goals(ref)),
      liveChallengesProvider.overrideWith((ref) {
        _signedIn(ref);
        return ref.watch(liveChallengeServiceProvider).getActiveChallenges();
      }),
    ]);
    addTearDown(c.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
        container: c, child: MaterialApp(home: screen)));
    await settle(t);
    return c;
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
  }

  /// The transition is delivered on the real auth stream; NO frame runs.
  Future<void> hear(WidgetTester t, Future<void> Function() transition) async {
    final heard = <AuthChangeEvent>[];
    await t.runAsync(() async {
      final sub = Supabase.instance.client.auth.onAuthStateChange
          .skip(1)
          .listen((s) => heard.add(s.event));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await transition();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await sub.cancel();
    });
    expect(heard, isNotEmpty, reason: 'premise: the event arrived');
  }

  Future<void> switchTo(WidgetTester t, String? uid) =>
      hear(t, () => uid == null ? signOut() : signInAs(uid));

  Future<void> noFrame(WidgetTester t) => t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)));

  Completer<void> holdServer(String table, String uid) =>
      server.holds['GET $table:$uid'] = Completer<void>();

  /// [provider] is read again around a switch to B, each way the old value is
  /// carried into B's read; on return the switch has happened and no frame has
  /// run since (except [inFlight], where A's refresh was under way and drawn).
  final around = <String,
      Future<void> Function(WidgetTester, ProviderContainer,
          ProviderBase<Object?> provider, Completer<void> Function(String) hold)>{
    'invalidated, then B signs in before the flush': (t, c, p, hold) async {
      hold(memberB);
      c.invalidate(p);
      await switchTo(t, memberB);
    },
    'B signs in, then invalidated before the flush': (t, c, p, hold) async {
      hold(memberB);
      await switchTo(t, memberB);
      c.invalidate(p);
    },
    "A's refresh in flight, then B signs in": (t, c, p, hold) async {
      hold(memberB);
      hold(memberA);
      c.invalidate(p);
      await settle(t);
      await switchTo(t, memberB);
    },
  };

  group('challenges', () {
    final joined = find.text('JOINED');
    final one = find.text('Challenge one');
    final notice = find.text(_failed);
    Completer<void> hold(String uid) => holdServer('challenges', uid);

    Future<ProviderContainer> asA(WidgetTester t) async {
      final c = await show(t, const ActivityScreen());
      expect(joined, findsOneWidget, reason: "premise: A's own list");
      return c;
    }

    for (final (key, way) in _ways(around)) {
      testWidgets("${way.key} (by ${key.name}), B's read pending: nothing of A, from the first "
          'frame; then B\'s own', (t) async {
        _key = key;
        final c = await asA(t);
        await way.value(t, c, liveChallengesProvider, hold);
        await t.pump();
        expect(joined, findsNothing, reason: "THE defect: A's JOINED row");
        expect(one, findsNothing);
        expect(find.text('No active challenges'), findsNothing);
        await settle(t);
        expect(joined, findsNothing);
        expect(one, findsNothing);
        for (final h in server.holds.values) {
          h.complete();
        }
        await settle(t);
        expect(one, findsOneWidget, reason: "B's own list");
        expect(joined, findsNothing, reason: 'B has joined nothing');
        expect(find.text('Join'), findsNWidgets(2));
        await close(t);
      });

      testWidgets("${way.key} (by ${key.name}), B's read failed: the failure, and nothing of A "
          'under it, nor while B tries again', (t) async {
        _key = key;
        server.fails.add('GET challenges:$memberB');
        final c = await asA(t);
        await way.value(t, c, liveChallengesProvider, hold);
        await t.pump();
        for (final h in server.holds.values) {
          h.complete();
        }
        await settle(t);
        expect(notice, findsOneWidget);
        expect(joined, findsNothing, reason: "THE defect: kept as B's");
        expect(one, findsNothing);
        expect(find.textContaining('loaded earlier'), findsNothing);
        server.holds.clear();
        final again = hold(memberB);
        await t.tap(find.text('Try again'));
        await settle(t);
        expect(joined, findsNothing);
        expect(one, findsNothing);
        server.fails.clear();
        again.complete();
        await settle(t);
        expect(one, findsOneWidget);
        expect(joined, findsNothing);
        await close(t);
      });

      testWidgets("${way.key} (by ${key.name}): A's failure is not B's", (t) async {
        _key = key;
        server.fails.add('GET challenges:$memberA');
        final c = await show(t, const ActivityScreen());
        expect(notice, findsOneWidget, reason: 'premise');
        await way.value(t, c, liveChallengesProvider, hold);
        await t.pump();
        expect(notice, findsNothing, reason: "THE defect: A's failure");
        await settle(t);
        expect(notice, findsNothing);
        for (final h in server.holds.values) {
          h.complete();
        }
        await settle(t);
        expect(one, findsOneWidget);
        await close(t);
      });
    }

    testWidgets("A's refresh lands after the switch: never B's", (t) async {
      final c = await asA(t);
      final a = hold(memberA);
      final b = hold(memberB);
      c.invalidate(liveChallengesProvider);
      await settle(t);
      await switchTo(t, memberB);
      a.complete(); // no frame since the switch
      await noFrame(t);
      await t.pump();
      expect(joined, findsNothing);
      await settle(t);
      expect(joined, findsNothing);
      b.complete();
      await settle(t);
      expect(one, findsOneWidget);
      expect(joined, findsNothing);
      await close(t);
    });

    testWidgets("invalidated, then signed out before the flush: A's rows go; "
        'A back has them', (t) async {
      final c = await asA(t);
      hold('anon');
      c.invalidate(liveChallengesProvider);
      await switchTo(t, null);
      await t.pump();
      expect(joined, findsNothing, reason: 'THE defect');
      await settle(t);
      expect(joined, findsNothing);
      await switchTo(t, memberA);
      await settle(t);
      expect(joined, findsOneWidget);
      await close(t);
    });

    testWidgets('CONTROL: a refresh of the same member keeps the rows while it '
        'is in flight; a failed one keeps them under the notice', (t) async {
      final c = await asA(t);
      final gate = hold(memberA);
      c.invalidate(liveChallengesProvider);
      await settle(t);
      expect(joined, findsOneWidget);
      server.fails.add('GET challenges:$memberA');
      gate.complete();
      await settle(t);
      expect(notice, findsOneWidget);
      expect(joined, findsOneWidget);
      expect(find.textContaining('Showing the challenges loaded earlier.'),
          findsOneWidget);
      await close(t);
    });

    // At e708fda the rows gave way to a spinner until the re-read landed.
    testWidgets("CONTROL: a token refresh keeps the same member's rows",
        (t) async {
      final c = await asA(t);
      final before = c.read(currentUserProvider);
      final gate = hold(memberA);
      await hear(t, refreshSession);
      await t.pump();
      expect(c.read(currentUserProvider), isNot(before), reason: 'premise');
      expect(joined, findsOneWidget);
      await settle(t);
      expect(joined, findsOneWidget);
      gate.complete();
      await settle(t);
      expect(joined, findsOneWidget);
      await close(t);
    });

    testWidgets('CONTROL: invalidated, then a token refresh before the flush: '
        'the rows stay', (t) async {
      final c = await asA(t);
      hold(memberA);
      c.invalidate(liveChallengesProvider);
      await hear(t, refreshSession);
      await t.pump();
      expect(joined, findsOneWidget);
      await settle(t);
      expect(joined, findsOneWidget);
      await close(t);
    });

    // ── Join ────────────────────────────────────────────────────────────────
    const write = 'POST challenge_participants';
    Iterable<String> writes() => server.calls.where((k) => k.startsWith(write));
    Iterable<String> origins() => reported.map((f) => f.origin);
    const identity = 'activity.challenges.join';

    for (final to in [memberB, null]) {
      final event = to == null ? 'sign-out' : 'B signed in';
      testWidgets("Join tapped on A's row after $event, no frame: nothing is "
          'sent or said; recorded', (t) async {
        await asA(t);
        await switchTo(t, to);
        await t.tap(find.text('Join'));
        await noFrame(t);
        expect(writes(), isEmpty,
            reason: 'THE defect: joined as whoever is signed in');
        expect(origins(), [identity]);
        await settle(t);
        expect(find.byType(SnackBar), findsNothing);
        await close(t);
      });

      testWidgets("A's join failing after $event: not said; recorded",
          (t) async {
        await asA(t);
        final gate = server.holds['$write:$memberA'] = Completer<void>();
        server.fails.add('$write:$memberA');
        await t.tap(find.text('Join'));
        await noFrame(t);
        expect(writes(), ['$write:$memberA'], reason: 'premise: in flight');
        await switchTo(t, to);
        gate.complete();
        await noFrame(t);
        await settle(t);
        expect(find.byType(SnackBar), findsNothing,
            reason: "THE defect: A's failure was said");
        expect(
            origins(), containsAll(['ChallengeNotifier.joinChallenge', identity]));
        await close(t);
      });
    }

    testWidgets('CONTROL: the same member joins across a token refresh: the row '
        'is joined, nothing recorded', (t) async {
      await asA(t);
      final gate = server.holds['$write:$memberA'] = Completer<void>();
      await t.tap(find.text('Join'));
      await noFrame(t);
      await hear(t, refreshSession);
      server.participants.add(
          {'challenge_id': 'two', 'user_id': memberA, 'current_progress': 0});
      gate.complete();
      await settle(t);
      expect(joined, findsNWidgets(2));
      expect(reported, isEmpty);
      await close(t);
    });

    testWidgets('CONTROL: the same member\'s failed join is said once',
        (t) async {
      await asA(t);
      server.fails.add('$write:$memberA');
      await t.tap(find.text('Join'));
      await settle(t);
      expect(find.textContaining("Couldn't join this challenge"),
          findsOneWidget);
      expect(origins(), ['ChallengeNotifier.joinChallenge']);
      await close(t);
    });
  });

  // QA mutant 7: `if (!read.isLoading)` → `if (read is! AsyncLoading)`. These
  // pass at e708fda and fail under the mutant.
  group('the refresh guard (q7)', () {
    for (final way in around.entries) {
      for (final (what, aFails) in [('number', false), ('failure', true)]) {
        testWidgets("streak, ${way.key}: A's $what is not B's", (t) async {
          if (aFails) server.fails.add('GET daily_scores:$memberA');
          final mine = find.text(aFails ? _streakFailed : '9');
          final c = await show(t, const ActivityScreen());
          expect(mine, findsOneWidget, reason: 'premise');
          await way.value(
              t, c, streakProvider, (u) => holdServer('daily_scores', u));
          await t.pump();
          expect(mine, findsNothing);
          expect(find.text('day streak'), findsNothing);
          await settle(t);
          expect(mine, findsNothing);
          expect(find.text('day streak'), findsNothing);
          for (final h in server.holds.values) {
            h.complete();
          }
          await settle(t);
          expect(find.text('2'), findsOneWidget);
          await close(t);
        });
      }
    }

    for (final (name, provider, member, table)
        in <(String, FutureProvider<Object?>,
            ProviderListenable<MemberRead<Object>>, String)>[
      ('streak', streakProvider, memberStreakProvider, 'daily_scores'),
      ('classes', upcomingClassesProvider, memberUpcomingClassesProvider,
          'classes'),
      ('events', upcomingEventsProvider, memberUpcomingEventsProvider, 'events'),
    ]) {
      for (final aFails in [false, true]) {
        test(
            "$name, invalidated and B's event delivered, unflushed: A's "
            '${aFails ? 'failure' : 'answer'} is not B\'s', () async {
          Future<void> turn() =>
              Future<void>.delayed(const Duration(milliseconds: 20));
          server.classes.add({'id': 'k1'});
          server.events.add({'id': 'e1'});
          if (aFails) server.fails.add('GET $table:$memberA');
          final c = ProviderContainer(overrides: [
            tableTickerProvider.overrideWith((ref, table) => Stream.value(0)),
          ]);
          addTearDown(c.dispose);
          c.listen(member, (_, __) {});
          await turn();
          await turn();
          expect(c.read(member).error, aFails ? isNotNull : isNull);
          expect(c.read(member).value, aFails ? isNull : isNotNull);

          final b = holdServer(table, memberB);
          c.invalidate(provider);
          await signInAs(memberB);
          await turn();
          final read = c.read(member);
          final raw = c.read(provider);
          expect(raw is AsyncLoading, isFalse,
              reason: "premise: A's answer under B's uid, by its type B's");
          expect(raw.isLoading, isTrue);
          expect(read.value, isNull);
          expect(read.error, isNull);
          expect(read.busy, isTrue);
          b.complete();
          await turn();
          expect(c.read(member).value, isNotNull, reason: "B's own");
          expect(c.read(member).error, isNull);
        });
      }
    }

    testWidgets('CONTROL: the same member, invalidated and a token refresh, '
        'unflushed: their number stays', (t) async {
      final c = await show(t, const ActivityScreen());
      holdServer('daily_scores', memberA);
      c.invalidate(streakProvider);
      await hear(t, refreshSession);
      await settle(t);
      expect(find.text('day streak'), findsOneWidget);
      expect(find.text('9'), findsOneWidget);
      await close(t);
    });
  });

  group('the monthly card', () {
    List<Map<String, dynamic>> rows(List<int> totals) => [
          for (final n in totals) {'total_score': n, 'workout_points': 10}
        ];
    final aDiff = find.text('30 pts vs last week');

    testWidgets("A's weekly change is not B's, whose month is the same",
        (t) async {
      month.answers
        ..[memberA] = rows([10])
        ..[memberB] = rows([10]);
      week.answers[memberA] = rows([10, 40]);
      await show(t, const ActivityScreen());
      await t.pump(const Duration(seconds: 2));
      expect(aDiff, findsOneWidget, reason: 'premise');
      await switchTo(t, memberB);
      await settle(t);
      await t.pump(const Duration(seconds: 2));
      expect(find.text('0 pts vs last week'), findsOneWidget);
      expect(aDiff, findsNothing, reason: "THE defect: A's figure, kept");
      await close(t);
    });

    for (final (key, way) in _ways(around)) {
      testWidgets("${way.key} (by ${key.name}): A's month is not B's", (t) async {
        _key = key;
        month.answers[memberA] = rows(List.filled(31, 100));
        final c = await show(t, const ActivityScreen());
        expect(find.text("You're Crushing it"), findsOneWidget,
            reason: 'premise');
        await way.value(t, c, monthScoresProvider,
            (u) => month.holds[u] = Completer<void>());
        await t.pump();
        expect(find.text("You're Crushing it"), findsNothing,
            reason: "THE defect: A's month");
        await settle(t);
        expect(find.text("You're Crushing it"), findsNothing);
        for (final h in month.holds.values) {
          h.complete();
        }
        await settle(t);
        expect(find.text("Let's Pick It Up"), findsOneWidget);
        await close(t);
      });

      testWidgets("${way.key} (by ${key.name}): A's week is not in B's card", (t) async {
        _key = key;
        month.answers
          ..[memberA] = rows([10])
          ..[memberB] = rows([10, 10]);
        week.answers[memberA] = rows([10, 40]);
        final c = await show(t, const ActivityScreen());
        await t.pump(const Duration(seconds: 2));
        expect(aDiff, findsOneWidget, reason: 'premise');
        await way.value(t, c, weekScoresProvider,
            (u) => week.holds[u] = Completer<void>());
        await settle(t);
        await t.pump(const Duration(seconds: 2));
        expect(aDiff, findsNothing, reason: "THE defect: A's change");
        await close(t);
      });
    }

    testWidgets('CONTROL: a token refresh keeps the card; a failed refresh and '
        'one in flight are as before', (t) async {
      month.answers[memberA] = rows([10]);
      week.answers[memberA] = rows([10, 40]);
      final c = await show(t, const ActivityScreen());
      await t.pump(const Duration(seconds: 2));
      await hear(t, refreshSession);
      await settle(t);
      expect(aDiff, findsOneWidget);
      final gate = month.holds[memberA] = Completer<void>();
      c.invalidate(monthScoresProvider);
      await settle(t);
      expect(aDiff, findsOneWidget);
      month.fails.add(memberA);
      gate.complete();
      await settle(t);
      expect(aDiff, findsNothing, reason: 'the card goes away, as before');
      await close(t);
    });
  });

  for (final (name, screen, title) in <(String, Widget, String)>[
    ('Activity', const ActivityScreen(), "Avery's Leg Day"),
    ('Directory', const DirectoryScreen(), "Avery's Leg Day"),
  ]) {
    group("$name › the workout card", () {
      final a = find.text(title);
      final b = find.text('Blake Push');

      for (final (key, way) in _ways(around)) {
        testWidgets("${way.key} (by ${key.name}): A's workout is not B's", (t) async {
          _key = key;
          final c = await show(t, screen);
          expect(a, findsOneWidget, reason: 'premise');
          await way.value(t, c, assignedWorkoutsProvider,
              (u) => workouts.holds[u] = Completer<void>());
          await t.pump();
          expect(a, findsNothing, reason: "THE defect: A's workout");
          await settle(t);
          expect(a, findsNothing);
          for (final h in workouts.holds.values) {
            h.complete();
          }
          await settle(t);
          expect(a, findsNothing);
          expect(b, findsOneWidget);
          await close(t);
        });
      }

      testWidgets("A → B, B's read pending, then failed: never A's", (t) async {
        _key = _Key.user; // as today
        await show(t, screen);
        final gate = workouts.holds[memberB] = Completer<void>();
        workouts.fails.add(memberB);
        await switchTo(t, memberB);
        await t.pump();
        expect(a, findsNothing, reason: "THE defect: A's workout");
        gate.complete();
        await settle(t);
        expect(a, findsNothing, reason: "THE defect: A's, for good");
        await close(t);
      });

      testWidgets('CONTROL: the same member: kept through a token refresh and a '
          'refresh in flight', (t) async {
        final c = await show(t, screen);
        await hear(t, refreshSession);
        await settle(t);
        expect(a, findsOneWidget);
        final gate = workouts.holds[memberA] = Completer<void>();
        c.invalidate(assignedWorkoutsProvider);
        await settle(t);
        expect(a, findsOneWidget);
        gate.complete();
        await settle(t);
        expect(a, findsOneWidget);
        await close(t);
      });
    });
  }

  testWidgets("Directory: A's session status is not put on B's workout",
      (t) async {
    // Two clients on one coach's program share workout ids.
    workouts.answers[memberB] = workouts.answers[memberA]!;
    statuses.answers[memberA] = {
      "Avery's Leg Day": {
        'workout_id': "Avery's Leg Day",
        'workout_title': "Avery's Leg Day",
        'status': 'in_progress',
        'logged_sets': 3,
      },
    };
    final c = await show(t, const DirectoryScreen());
    expect(find.text('Resume Workout'), findsOneWidget, reason: 'premise');
    statuses.holds[memberB] = Completer<void>();
    c.invalidate(programSessionStatusProvider);
    await switchTo(t, memberB);
    await settle(t);
    expect(find.text('Resume Workout'), findsNothing,
        reason: "THE defect: A's session");
    expect(find.text('Start Workout'), findsOneWidget);
    await close(t);
  });

  group('meal plan targets', () {
    final a = find.text('2600 kcal');

    for (final (key, way) in _ways(around)) {
      testWidgets("${way.key} (by ${key.name}): A's targets are not taken as B's", (t) async {
        _key = key;
        final c = await show(t, const MealPlanScreen());
        expect(a, findsOneWidget, reason: 'premise');
        await way.value(t, c, nutritionGoalsProvider,
            (u) => goals.holds[u] = Completer<void>());
        await t.pump();
        expect(a, findsNothing, reason: "THE defect: A's targets");
        await settle(t);
        expect(a, findsNothing);
        for (final h in goals.holds.values) {
          h.complete();
        }
        await settle(t);
        expect(find.text('1500 kcal'), findsOneWidget,
            reason: 'THE defect: the first ones taken were A\'s, for good');
        await close(t);
      });
    }

    testWidgets('CONTROL: the same member: the form keeps its targets through a '
        'refresh, a failed one and a token refresh', (t) async {
      final c = await show(t, const MealPlanScreen());
      goals.fails.add(memberA);
      c.invalidate(nutritionGoalsProvider);
      await settle(t);
      expect(a, findsOneWidget);
      await hear(t, refreshSession);
      await settle(t);
      expect(a, findsOneWidget);
      await close(t);
    });
  });

  for (final (name, screen) in <(String, Widget)>[
    ('Activity', const ActivityScreen()),
    ('Directory', const DirectoryScreen()),
  ]) {
    testWidgets('$name › a closed Upcoming panel: its reads are not made again '
        'on sign-out, nor for B, until B opens it', (t) async {
      Iterable<String> reads() => server.calls
          .where((k) => k.contains('classes') || k.contains('events'));
      await show(t, screen);
      await t.tap(find.byIcon(Icons.notifications_outlined));
      await settle(t);
      expect(reads(), hasLength(2), reason: 'premise');
      Navigator.of(t.element(find.byType(BottomSheet))).pop();
      await settle(t);
      await t.pump(const Duration(seconds: 1));
      await switchTo(t, null);
      await settle(t);
      await switchTo(t, memberB);
      await settle(t);
      expect(reads(), hasLength(2), reason: 'THE defect: read again, unopened');
      await t.tap(find.byIcon(Icons.notifications_outlined));
      await settle(t);
      expect(reads().skip(2),
          unorderedEquals(['GET classes:$memberB', 'GET events:$memberB']));
      await close(t);
    });
  }
}
