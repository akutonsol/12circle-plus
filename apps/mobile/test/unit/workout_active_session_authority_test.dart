// WKT-113 — one authoritative active workout session.
//
// The reported defect: an existing Full Body Strength session stayed the
// resume candidate after a Lower Body workout had been started, completed a
// set and been left. The Train screen offered the old workout back.
//
// Two things caused it, and both are covered here.
//
//  1. Recency was not trustworthy. `started_at` was stamped by the client with
//     `DateTime.now().toIso8601String()`, which renders a *local* time with no
//     zone marker; Postgres reads that into `timestamptz` as UTC. A client
//     behind UTC therefore stored every session in the past, so a session
//     started later could sort earlier than the one it superseded — and since
//     the app abandons every session it does not pick, the *current* session
//     was the one closed. Migration 108 hands the stamp back to the database
//     and re-reconciles the rows the skew produced.
//
//  2. Completion did not release the workout. A finished workout stayed in
//     `selectedWorkoutProvider`, and the Zone treats an in-memory workout as
//     authoritative — so re-entering it called startWorkout on the finished
//     workout and opened a brand-new in-progress session for it.
//
// These drive the production rules — `WorkoutSessionManager` and
// `WorkoutSessionRestorer` — against the in-memory store, which enforces the
// same `workout_sessions_one_active_per_user` invariant the database does.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/workout/data/models/exercise_model.dart';
import 'package:circle_fitness/features/workout/data/models/workout_model.dart';
import 'package:circle_fitness/features/workout/data/workout_session_store.dart';
import 'package:circle_fitness/features/workout/data/workout_snapshot.dart';
import 'package:circle_fitness/features/workout/domain/workout_restoration.dart';
import 'package:circle_fitness/features/workout/domain/workout_session_manager.dart';

import '../support/in_memory_workout_session_store.dart';

const _uid = 'user-1';

Exercise _ex(String id, String name) => Exercise(
      id: id,
      name: name,
      category: 'Strength',
      muscleGroup: 'Legs',
      equipment: 'Barbell',
      difficulty: 'Intermediate',
      description: '',
      instructions: const [],
    );

/// Full Body Strength — the stale session in the report.
final _fullBody = Workout(
  id: '1',
  title: 'Full Body Strength',
  description: '',
  estimatedDuration: 45,
  difficulty: 'Intermediate',
  category: 'Strength',
  coachName: 'Coach Sarah',
  exercises: [
    WorkoutExercise(
      exercise: _ex('ex-fb-1', 'Barbell Squat'),
      sets: [
        for (var n = 1; n <= 3; n++)
          WorkoutSet(setNumber: n, reps: 8, weightKg: 60, restSeconds: 90),
      ],
    ),
  ],
);

/// Lower Body — 15 sets across three exercises, so "1/15" is literal.
final _lowerBody = Workout(
  id: '2',
  title: 'Lower Body',
  description: '',
  estimatedDuration: 50,
  difficulty: 'Intermediate',
  category: 'Strength',
  coachName: 'Coach Sarah',
  exercises: [
    for (final e in const [
      ('ex-lb-1', 'Back Squat'),
      ('ex-lb-2', 'Romanian Deadlift'),
      ('ex-lb-3', 'Walking Lunge'),
    ])
      WorkoutExercise(
        exercise: _ex(e.$1, e.$2),
        sets: [
          for (var n = 1; n <= 5; n++)
            WorkoutSet(setNumber: n, reps: 8, weightKg: 60, restSeconds: 90),
        ],
      ),
  ],
);

int _totalSets(Workout w) =>
    w.exercises.fold(0, (n, e) => n + e.sets.length);

void main() {
  late InMemoryWorkoutSessionStore store;
  late WorkoutSessionManager manager;

  setUp(() {
    store = InMemoryWorkoutSessionStore();
    manager = WorkoutSessionManager(store);
  });

  /// A cold start: everything the app held in RAM is gone, stored rows remain.
  WorkoutSessionRestorer reload() {
    store.restart();
    return WorkoutSessionRestorer(
      manager: WorkoutSessionManager(store),
      loadSetLogs: store.loadSetLogs,
      candidates: () async => [_fullBody, _lowerBody],
    );
  }

  /// Confirms the first set of Lower Body's first exercise, the way the Zone
  /// does: recorded against the session, by set identity.
  void completeFirstSet(String sessionId) {
    final we = _lowerBody.exercises.first;
    store.logSet(sessionId, we.exercise.id, 1,
        setId: we.sets.first.id, reps: 8, weight: 60);
  }

  // ── Required regression 1 ─────────────────────────────────────────────────
  group('WKT-113 Full Body active → start Lower Body → 1 set → reload', () {
    test('Lower Body remains the one active session after a reload', () async {
      // An older Full Body Strength session is already persisted and active.
      final stale = await manager.startWorkout(userId: _uid, workout: _fullBody);
      expect(stale.workoutTitle, 'Full Body Strength');

      // Start Lower Body. It must take ownership immediately, not on completion.
      final lower = await manager.startWorkout(userId: _uid, workout: _lowerBody);
      expect(lower.id, isNot(stale.id));
      expect(lower.workoutId, '2');

      // The old session is closed, not left competing.
      expect(store.rowById(stale.id)!['status'],
          WorkoutSessionStatus.abandoned);
      expect(store.withStatus(WorkoutSessionStatus.inProgress), hasLength(1));

      // Complete 1 of 15 sets.
      completeFirstSet(lower.id);
      expect(_totalSets(_lowerBody), 15);

      // Leave the app entirely and come back.
      final restored = await reload().restore(_uid);

      expect(restored, isNotNull);
      expect(restored!.sessionId, lower.id,
          reason: 'the same session, not a new one');
      expect(restored.workout.id, '2');
      expect(restored.workout.title, 'Lower Body',
          reason: 'Resume must name Lower Body, never Full Body Strength');

      // Exactly 1 of 15 completed comes back.
      final completed =
          restored.setState.values.where((s) => s['completed'] == true);
      expect(completed, hasLength(1));
      expect(restored.setState[_lowerBody.exercises.first.sets.first.id]
          ?['completed'], isTrue);

      // And it resumes on set 2, the first outstanding one.
      expect(restored.position.setId,
          _lowerBody.exercises.first.sets[1].id);
    });

    test('the abandoned Full Body session is never eligible again', () async {
      final stale = await manager.startWorkout(userId: _uid, workout: _fullBody);
      await manager.startWorkout(userId: _uid, workout: _lowerBody);

      // Reading the active session repeatedly must never drift back.
      for (var i = 0; i < 3; i++) {
        final active = await manager.activeSession(_uid);
        expect(active!.workoutTitle, 'Lower Body');
        expect(active.id, isNot(stale.id));
      }
    });

    test('the superseded session keeps its own set logs', () async {
      final stale = await manager.startWorkout(userId: _uid, workout: _fullBody);
      store.logSet(stale.id, 'ex-fb-1', 1, setId: _fullBody.exercises.first.sets.first.id);

      final lower = await manager.startWorkout(userId: _uid, workout: _lowerBody);
      completeFirstSet(lower.id);

      // Abandoning closes a session; it never destroys what was recorded.
      expect(store.setsFor(stale.id), hasLength(1));
      expect(store.setsFor(lower.id), hasLength(1));
    });
  });

  // ── Required regression 2 ─────────────────────────────────────────────────
  group('WKT-113 Lower Body active → refresh → Lower Body remains active', () {
    test('repeated refreshes are idempotent', () async {
      final lower = await manager.startWorkout(userId: _uid, workout: _lowerBody);
      completeFirstSet(lower.id);

      for (var refresh = 1; refresh <= 3; refresh++) {
        final restored = await reload().restore(_uid);
        expect(restored!.sessionId, lower.id, reason: 'refresh $refresh');
        expect(restored.workout.title, 'Lower Body', reason: 'refresh $refresh');
        expect(
            restored.setState.values.where((s) => s['completed'] == true),
            hasLength(1),
            reason: 'refresh $refresh keeps 1/15');
        // A refresh must not open, close or duplicate anything.
        expect(store.withStatus(WorkoutSessionStatus.inProgress), hasLength(1),
            reason: 'refresh $refresh');
      }
    });

    test('a refresh does not re-ask the warm-up', () async {
      final lower = await manager.startWorkout(userId: _uid, workout: _lowerBody);
      await manager.acknowledgeWarmup(lower.id);

      final restored = await reload().restore(_uid);
      expect(restored!.warmupAcknowledged, isTrue);
    });
  });

  // ── Required regression 3 ─────────────────────────────────────────────────
  group('WKT-113 Lower Body active → Finish Early → Skip', () {
    test('finishing early archives the session and clears Resume', () async {
      final lower = await manager.startWorkout(userId: _uid, workout: _lowerBody);
      completeFirstSet(lower.id);

      // Finish Early with 1/15 done. Skip only dismisses the feedback sheet —
      // the session is already resolved by this point, which is why skipping
      // cannot leave one dangling.
      await manager.completeSession(
        sessionId: lower.id,
        durationSeconds: 372,
        idleSeconds: 0,
        caloriesBurned: 48,
      );

      expect(store.rowById(lower.id)!['status'],
          WorkoutSessionStatus.completed);
      expect(await manager.activeSession(_uid), isNull,
          reason: 'nothing is offered for resume');
      expect(await reload().restore(_uid), isNull,
          reason: 'a reload finds no session, rather than failing');
      // The partial work is kept as history.
      expect(store.setsFor(lower.id), hasLength(1));
    });

    test('a completed workout is not resurrected by re-entering the Zone',
        () async {
      final lower = await manager.startWorkout(userId: _uid, workout: _lowerBody);
      await manager.completeSession(
        sessionId: lower.id,
        durationSeconds: 372,
        idleSeconds: 0,
        caloriesBurned: 48,
      );

      // This is what the screen used to do: a finished workout stayed selected,
      // so re-entering called startWorkout on it again. The screen now clears
      // the selection on completion; if it ever stops doing so, the resurrected
      // session is a *new* id and the old one stays completed — so assert both
      // that the history is intact and that nothing silently reuses it.
      final resurrected =
          await manager.startWorkout(userId: _uid, workout: _lowerBody);
      expect(resurrected.id, isNot(lower.id),
          reason: 'a completed session is never reopened');
      expect(store.rowById(lower.id)!['status'],
          WorkoutSessionStatus.completed,
          reason: 'completed history is untouched');
    });

    test('finishing early then starting Full Body makes Full Body active',
        () async {
      final lower = await manager.startWorkout(userId: _uid, workout: _lowerBody);
      await manager.completeSession(
        sessionId: lower.id,
        durationSeconds: 10,
        idleSeconds: 0,
        caloriesBurned: 1,
      );

      final next = await manager.startWorkout(userId: _uid, workout: _fullBody);
      final active = await manager.activeSession(_uid);
      expect(active!.id, next.id);
      expect(active.workoutTitle, 'Full Body Strength');
      expect(store.withStatus(WorkoutSessionStatus.inProgress), hasLength(1));
    });
  });

  // ── The invariant itself ──────────────────────────────────────────────────
  group('WKT-113 one active session per user is an invariant, not a habit', () {
    test('the store rejects a second active session, as the database does',
        () async {
      await manager.startWorkout(userId: _uid, workout: _fullBody);
      // Bypassing the manager is the database's problem to catch, and it does.
      expect(
        () => store.createSession(
          userId: _uid,
          workoutId: '2',
          workoutTitle: 'Lower Body',
          workoutSnapshot: workoutToSnapshot(_lowerBody),
        ),
        throwsA(isA<StateError>()),
        reason: 'workout_sessions_one_active_per_user',
      );
    });

    test('two activations racing cannot both insert', () async {
      // Why the Workout Zone shares one activation future: `_startSession`
      // (initState) and `_ensureSession` (the first confirmed set) can both be
      // in flight. Unserialized they both read the same open sessions, both
      // abandon them and both insert — and the second insert violates the
      // unique index, leaving the workout with no session of its own.
      await manager.startWorkout(userId: _uid, workout: _fullBody);

      final results = await Future.wait([
        manager.startWorkout(userId: _uid, workout: _lowerBody),
        manager.startWorkout(userId: _uid, workout: _lowerBody),
      ].map((f) => f.then<Object?>((v) => v).catchError((Object e) => e)));

      expect(results.whereType<StateError>(), isNotEmpty,
          reason: 'the race is real; the screen must serialize activation');
    });

    test('a sequence of starts always leaves exactly one active', () async {
      for (final w in [_fullBody, _lowerBody, _fullBody, _lowerBody]) {
        await manager.startWorkout(userId: _uid, workout: w);
        expect(store.withStatus(WorkoutSessionStatus.inProgress), hasLength(1));
      }
      final active = await manager.activeSession(_uid);
      expect(active!.workoutTitle, 'Lower Body');
    });

    test('another user is unaffected', () async {
      final other = await manager.startWorkout(userId: 'user-2', workout: _fullBody);
      await manager.startWorkout(userId: _uid, workout: _lowerBody);
      expect(store.rowById(other.id)!['status'],
          WorkoutSessionStatus.inProgress);
    });
  });

  // ── The recency defect, at the source ─────────────────────────────────────
  group('WKT-113 session recency is server-stamped, not client-stamped', () {
    test('a naive local timestamp is zone-ambiguous; a UTC one is not', () {
      final naive = DateTime.now().toIso8601String();
      // No zone marker at all — Postgres reads this into timestamptz as UTC,
      // so a client behind UTC stores the session in the past.
      expect(naive.endsWith('Z'), isFalse);
      expect(RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(naive), isFalse);

      expect(DateTime.now().toUtc().toIso8601String().endsWith('Z'), isTrue);
    });

    test('createSession leaves started_at to the database default', () {
      // The fix is an absence, so it is asserted at the source: sending any
      // client-rendered start time reintroduces the skew that made a newer
      // session sort older than the one it replaced.
      final src = _sourceOf('lib/features/workout/data/workout_session_store.dart');
      final insert = src.substring(
          src.indexOf('Future<WorkoutSessionRecord> createSession'),
          src.indexOf('Future<void> abandonSessions'));
      expect(insert.contains("'started_at':"), isFalse,
          reason: 'started_at must come from the column default now()');
    });

    test('no session timestamp is written without its zone', () {
      final src = _sourceOf('lib/features/workout/data/workout_session_store.dart');
      // Comments explain the hazard; code must not reproduce it.
      final code = src
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(code.contains('DateTime.now().toIso8601String()'), isFalse,
          reason: 'use DateTime.now().toUtc().toIso8601String()');
    });
  });
}

String _sourceOf(String relativePath) {
  final file = File(relativePath);
  if (!file.existsSync()) {
    fail('expected to find $relativePath relative to the package root');
  }
  return file.readAsStringSync();
}
