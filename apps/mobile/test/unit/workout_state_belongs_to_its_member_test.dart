import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/core/realtime/realtime.dart';
import 'package:circle_fitness/features/workout/data/models/workout_log_model.dart';
import 'package:circle_fitness/features/workout/data/models/workout_model.dart';
import 'package:circle_fitness/features/workout/data/workout_service.dart';
import 'package:circle_fitness/features/workout/data/workout_session_store.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:circle_fitness/features/workout/domain/workout_session_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/two_member_postgrest.dart'
    show initTwoMemberSupabase, memberA, memberB, refreshSession, signInAs, signOut;
import '../support/workout_members_server.dart';

// P0-FL-59b, below the screen: the workout state providers, the session store
// and the set-log / workout-log writes, across real auth transitions.
//
// HOW TO SEE IT FAIL: `git checkout a82f993 --` the lib/features/workout files.

final Workout _w = WorkoutService().getSampleWorkouts().first;
final Workout _w2 = WorkoutService().getSampleWorkouts()[1];

Future<void> _tick([int n = 20]) async {
  for (var i = 0; i < n; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late WorkoutMembersServer server;
  late ProviderContainer c;
  late List<AppFailure> failures;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = WorkoutMembersServer();
    await initTwoMemberSupabase(server);
  });

  setUp(() async {
    server.reset();
    failures = [];
    setFailureSink(failures.add);
    await signInAs(memberA);
    c = ProviderContainer(overrides: [
      tableTickerProvider.overrideWith((ref, t) => Stream.value(0)),
    ]);
  });

  tearDown(() {
    resetFailureSink();
    c.dispose();
  });

  void aIsMidWorkout() {
    c.read(selectedWorkoutProvider.notifier).state = _w;
    c.read(activeWorkoutProvider.notifier)
      ..beginSession('a-session')
      ..completeSet(_w.exercises.first.sets.first, {'reps': 8});
    c.read(restTimerProvider.notifier).state =
        RestTimerState(DateTime.now().add(const Duration(seconds: 90)), 90);
  }

  void expectEmpty() {
    expect(c.read(selectedWorkoutProvider), isNull, reason: "THE defect: A's workout");
    expect(c.read(activeWorkoutProvider), isEmpty, reason: "THE defect: A's sets");
    expect(c.read(activeWorkoutProvider.notifier).sessionId, isNull);
    expect(c.read(restTimerProvider), isNull, reason: "THE defect: A's rest");
  }

  Future<void> become(String? uid) async {
    uid == null ? await signOut() : await signInAs(uid);
    await _tick();
    expect(c.read(restoringUserIdProvider), uid, reason: 'premise');
  }

  group('the in-memory workout', () {
    test('A -> B drops it', () async {
      aIsMidWorkout();
      await become(memberB);
      expectEmpty();
    });

    test('sign-out drops it', () async {
      aIsMidWorkout();
      await become(null);
      expectEmpty();
    });

    test('sign-out -> the same member, nothing reading in between, still drops it', () async {
      aIsMidWorkout();
      await signOut();
      await _tick();
      await signInAs(memberA);
      await _tick();
      expectEmpty();
    });

    test('control: a token refresh of the same member keeps all three', () async {
      aIsMidWorkout();
      final rest = c.read(restTimerProvider);
      final notifier = c.read(activeWorkoutProvider.notifier);
      await refreshSession();
      await _tick();
      expect(c.read(selectedWorkoutProvider), same(_w));
      expect(c.read(activeWorkoutProvider.notifier), same(notifier));
      expect(c.read(activeWorkoutProvider), hasLength(1));
      expect(c.read(restTimerProvider), same(rest));
    });
  });

  group('restoring', () {
    test("A's restore landing after B arrived hydrates nothing", () async {
      server.seedSession(memberA, workoutId: _w.id, title: _w.title);
      final hold = server.holds['GET workout_set_logs:$memberA'] = Completer<void>();
      c.listen(activeWorkoutRestorationProvider, (_, __) {});
      await _tick();
      expect(server.asked.map((a) => a.table), contains('workout_set_logs'),
          reason: "premise: A's restore is in flight");
      await become(memberB);
      hold.complete();
      await _tick(40);
      expectEmpty();
      expect((await c.read(activeWorkoutRestorationProvider.future)), isNull);
    });

    test('the same, with nobody watching the restore any more', () async {
      server.seedSession(memberA, workoutId: _w.id, title: _w.title);
      final hold = server.holds['GET workout_set_logs:$memberA'] = Completer<void>();
      unawaited(c.read(activeWorkoutRestorationProvider.future).then((_) {}, onError: (_) {}));
      await _tick();
      await become(memberB);
      hold.complete();
      await _tick(40);
      expectEmpty();
    });

    test("A's restore landing BEFORE B's own read: B's is the one hydrated", () async {
      server.seedSession(memberA, workoutId: _w.id, title: _w.title);
      final b = server.seedSession(memberB, workoutId: _w2.id, title: _w2.title);
      final holdA = server.holds['GET workout_set_logs:$memberA'] = Completer<void>();
      final holdB = server.holds['GET workout_sessions:$memberB'] = Completer<void>();
      c.listen(activeWorkoutRestorationProvider, (_, __) {});
      await _tick();
      await become(memberB);
      await _tick();
      holdA.complete();
      await _tick(40);
      expectEmpty();
      expect(c.read(activeWorkoutRestorationProvider).isLoading, isTrue, reason: 'B is not answered');
      holdB.complete();
      await _tick(40);
      expect((await c.read(activeWorkoutRestorationProvider.future))?.sessionId, b['id']);
      expect(c.read(selectedWorkoutProvider)?.title, _w2.title);
      expect(c.read(activeWorkoutProvider.notifier).sessionId, b['id']);
    });

    test('control: A\'s own restore hydrates', () async {
      final row = server.seedSession(memberA, workoutId: _w.id, title: _w.title);
      c.listen(activeWorkoutRestorationProvider, (_, __) {});
      final r = await c.read(activeWorkoutRestorationProvider.future);
      expect(r?.sessionId, row['id']);
      expect(c.read(selectedWorkoutProvider)?.title, _w.title);
      expect(c.read(activeWorkoutProvider.notifier).sessionId, row['id']);
    });
  });

  group('the session store', () {
    WorkoutSessionStore store() => SupabaseWorkoutSessionStore();
    final changed = throwsA(isA<StateError>()
        .having((e) => e.message, 'message', contains('the signed-in account changed')));

    Future<void> complete(WorkoutSessionStore s, String id) => s.completeSession(
        sessionId: id, durationSeconds: 60, idleSeconds: 0, caloriesBurned: 8);

    test("A's session: no write of any kind is sent once B is signed in", () async {
      final id = server.seedSession(memberA, workoutId: 'w', title: 'W')['id'] as String;
      final s = store();
      await s.inProgressSessions(memberA);
      await signInAs(memberB);
      for (final write in <Future<void> Function()>[
        () => complete(s, id),
        () => s.abandonSessions([id]),
        () => s.saveElapsed(id, 30),
        () => s.acknowledgeWarmup(id),
        () => s.saveSnapshot(id, const {}),
        () => s.saveCursor(id, 'e', 's'),
        () => s.createSession(
            userId: memberA, workoutId: 'w', workoutTitle: 'W', workoutSnapshot: const {}),
      ]) {
        await expectLater(write(), changed);
      }
      await expectLater(s.inProgressSessions(memberA), changed,
          reason: 'asked as B it answers "none", which opens a new session');
      expect(server.writes(), isEmpty);
    });

    test('a completion that matched no row is a failure', () async {
      await expectLater(complete(store(), 'not-there'), throwsStateError,
          reason: 'THE defect: 0 rows counted as completed');
    });

    test('an abandon that matched no row is a failure', () async {
      await expectLater(store().abandonSessions(['not-there']), throwsStateError);
    });

    test('an abandon that matched one of two is a failure: the other is still open', () async {
      final mine = server.seedSession(memberA, workoutId: 'w', title: 'W')['id'] as String;
      await expectLater(store().abandonSessions([mine, 'not-there']), throwsStateError);
    });

    test('control: an abandon that matched them all is not', () async {
      final ids = [
        for (final w in ['w1', 'w2'])
          server.seedSession(memberA, workoutId: w, title: w)['id'] as String
      ];
      await store().abandonSessions(ids);
      expect([for (final s in server.sessions) s['status']], ['abandoned', 'abandoned']);
    });

    test('a swapped workout that matched no row is a failure', () async {
      await expectLater(store().saveSnapshot('not-there', const {}), throwsStateError,
          reason: 'THE defect: 0 rows counted as saved');
    });

    test('control: a swapped workout is stored', () async {
      final row = server.seedSession(memberA, workoutId: 'w', title: 'W');
      await store().saveSnapshot(row['id'] as String, const {'title': 'New'});
      expect(row['workout_snapshot'], {'title': 'New'});
    });

    test('negative control: nothing to abandon sends nothing and is not a failure', () async {
      await store().abandonSessions(const []);
      expect(server.asked, isEmpty);
    });

    test('negative control: no open session is an empty list', () async {
      expect(await store().inProgressSessions(memberA), isEmpty);
    });

    test('startWorkout: a switch after the read opens nothing, abandons nothing', () async {
      server.seedSession(memberA, workoutId: 'other', title: 'Other');
      final hold = server.holds['GET workout_sessions:$memberA'] = Completer<void>();
      final started = WorkoutSessionManager(store()).startWorkout(userId: memberA, workout: _w);
      final outcome = expectLater(started, changed);
      await _tick();
      await signInAs(memberB);
      hold.complete();
      await outcome;
      expect(server.writes(), isEmpty);
    });

    test('startWorkout: a switch after the abandon opens nothing', () async {
      server.seedSession(memberA, workoutId: 'other', title: 'Other');
      final hold = server.holds['PATCH workout_sessions:$memberA'] = Completer<void>();
      final started = WorkoutSessionManager(store()).startWorkout(userId: memberA, workout: _w);
      final outcome = expectLater(started, changed);
      await _tick();
      await signInAs(memberB);
      hold.complete();
      await outcome;
      expect(server.writes().map((w) => w.method), ['PATCH']);
      expect(server.writes(by: memberB), isEmpty);
    });

    test('control: A starts, switches workout and completes', () async {
      final s = store();
      final m = WorkoutSessionManager(s);
      final old = server.seedSession(memberA, workoutId: 'other', title: 'Other');
      final session = await m.startWorkout(userId: memberA, workout: _w);
      expect(old['status'], 'abandoned');
      await complete(s, session.id);
      expect(server.sessions.last['status'], 'completed');
      await refreshSession();
      await s.saveElapsed(session.id, 90);
      expect(server.sessions.last['elapsed_seconds'], 90, reason: 'a refreshed token is the same member');
    });
  });

  group('set logs and workout logs', () {
    Future<void> save(WorkoutService s, {String set = 's1', int reps = 8}) => s.saveSetLog(
        sessionId: 'session', exerciseName: 'Squat', exerciseInstanceId: 'i1', setId: set,
        setNumber: 1, reps: reps, weightKg: 60, completed: true);

    test('a save queued behind a slow one is not sent as B', () async {
      final s = WorkoutService();
      final hold = server.holds['POST workout_set_logs:$memberA'] = Completer<void>();
      final first = save(s);
      await _tick();
      final second = expectLater(save(s, reps: 9), throwsStateError);
      await signInAs(memberB);
      hold.complete();
      await first;
      await second;
      expect(server.writes(by: memberB), isEmpty);
      expect(server.setLogs.single['reps'], 8);
    });

    test('a switch between the update and the insert: no row of B\'s', () async {
      final s = WorkoutService(); // no owner given: fixed when the save was asked for
      final hold = server.holds['PATCH workout_set_logs:$memberA'] = Completer<void>();
      final saved = expectLater(save(s), throwsStateError);
      await _tick();
      await signInAs(memberB);
      hold.complete();
      await saved;
      expect(server.writes(by: memberB), isEmpty);
      expect(server.setLogs, isEmpty);
    });

    test('a 23505 retry that updates no row is a failure', () async {
      server.setLogs.add(
          {'id': 'x', 'session_id': 'session', 'set_id': 's1', 'user_id': memberB});
      await expectLater(save(WorkoutService()), throwsStateError,
          reason: "THE defect: A's set was lost and called saved");
    });

    test('control: a 23505 whose row IS ours is updated and saved', () async {
      // Another device created A's row between our update and our insert.
      final s = WorkoutService();
      final hold = server.holds['PATCH workout_set_logs:$memberA'] = Completer<void>();
      final saved = save(s);
      await _tick();
      server.setLogs.add(
          {'id': 'x', 'session_id': 'session', 'set_id': 's1', 'user_id': memberA, 'reps': 1});
      server.holds.clear();
      hold.complete();
      await saved;
      expect(server.setLogs.single['reps'], 8);
    });

    test('control: A logs a set and a workout, as A', () async {
      final s = WorkoutService();
      await save(s);
      await save(s, reps: 10);
      await s.logWorkout(WorkoutLog(workoutId: 'w', workoutTitle: 'W'));
      expect(server.setLogs.single['reps'], 10);
      expect(server.setLogs.single['user_id'], memberA);
      expect(server.writes(to: 'workout_logs'), hasLength(1));
    });
  });

  group('the member\'s own reads', () {
    Future<int> reads(String table, String who, void Function() listen) async {
      listen();
      await _tick(40);
      await become(memberB);
      await _tick(40);
      return server.asked.where((a) => a.table == table && a.who == who).length;
    }

    test('the AI adjustment is re-read for B, and A\'s is not shown meanwhile', () async {
      server.rows['ai_insights:$memberA'] = [
        {'title': 'Easy day, A', 'body': '', 'data': {'intensity_delta': -20}}
      ];
      server.holds['GET ai_insights:$memberB'] = Completer<void>();
      final n = await reads('ai_insights', memberB,
          () => c.listen(coachAdjustmentProvider, (_, __) {}));
      expect(n, 1, reason: "THE defect: A's brief stayed");
      expect(
          c.read(coachAdjustmentProvider).maybeWhen(data: (a) => a?.title, orElse: () => null),
          isNull);
      server.holds['GET ai_insights:$memberB']!.complete();
      await _tick(40);
      expect(c.read(coachAdjustmentProvider).requireValue, isNull);
    });

    test('program adherence is re-read for B', () async {
      expect(
          await reads('workout_logs', memberB,
              () => c.listen(programAdherenceProvider, (_, __) {})),
          1);
    });

    test('a client\'s records and sessions are re-read for coach B', () async {
      expect(
          await reads('workout_set_logs', memberB,
              () => c.listen(clientPersonalRecordsProvider('client'), (_, __) {})),
          1);
      await become(memberA);
      expect(
          await reads('workout_sessions', memberB,
              () => c.listen(clientRecentSessionsProvider('client'), (_, __) {})),
          1);
    });

    for (final (table, read) in [
      ('workout_set_logs', () => clientPersonalRecordsProvider('client')),
      ('workout_sessions', () => clientRecentSessionsProvider('client')),
    ]) {
      test("a client's $table: A's late answer, before and after B's, is not B's", () async {
        for (final aFirst in [true, false]) {
          await become(memberA);
          final own = ProviderContainer();
          addTearDown(own.dispose);
          final holdA = server.holds['GET $table:$memberA'] = Completer<void>();
          final holdB = server.holds['GET $table:$memberB'] = Completer<void>();
          server.fails.add('GET $table:$memberA'); // A's answer, recognisably A's
          own.listen<Object?>(read(), (_, __) {});
          await _tick(40);
          await become(memberB);
          own.read(restoringUserIdProvider);
          await _tick(40);
          (aFirst ? holdA : holdB).complete();
          await _tick(40);
          final between = own.read(read());
          expect(between.hasError, isFalse, reason: "THE defect: A's answer stood as B's");
          expect(between.isLoading, aFirst);
          (aFirst ? holdB : holdA).complete();
          await _tick(40);
          expect(own.read(read()).requireValue, isEmpty);
          server.holds.clear();
          server.fails.clear();
        }
      });
    }

    test('the AI adjustment says whose it is', () async {
      server.rows['ai_insights:$memberA'] = [
        {'title': 'Easy day, A', 'body': '', 'data': {'intensity_delta': -20}}
      ];
      c.listen(coachAdjustmentProvider, (_, __) {});
      // dynamic: the member is new, and this file must compile on 3f17006.
      final dynamic brief = await c.read(coachAdjustmentProvider.future);
      expect(brief.readFor, memberA);
    });

    test('control: a token refresh re-reads none of them', () async {
      c.listen(coachAdjustmentProvider, (_, __) {});
      c.listen(clientPersonalRecordsProvider('client'), (_, __) {});
      await _tick(40);
      final before = server.asked.length;
      await refreshSession();
      await _tick(40);
      expect(server.asked, hasLength(before));
    });
  });
}
