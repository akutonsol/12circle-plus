import 'package:circle_fitness/features/workout/data/workout_service.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:flutter_test/flutter_test.dart';

// C14-62d-02 / RM-3 F1 · what `ActiveWorkoutNotifier.beginSession` keeps when
// a session binds late. Only a set whose SAVE is waiting on the session being
// opened (`holdForBind`) is kept; one whose save did not go out
// (`releaseUnsaved`) is let go and no longer reads as confirmed. The
// Zone-level proof is test/widget/workout_held_sets_and_filed_once_test.dart;
// this pins the rule.
//
// HOW TO SEE IT FAIL: `git checkout 6d1611d --
// lib/features/workout/domain/workout_provider.dart` (no `heldFor:` /
// `holdForBind` — the file does not load); at b5379aa (round 1) the file does
// not load either (no `holdForBind`), and the widget file shows the behaviour.

final _w1 = WorkoutService().getSampleWorkouts()[0];
final _w2 = WorkoutService().getSampleWorkouts()[1];
final _a = _w1.exercises.first.sets.first;
final _b = _w1.exercises.first.sets[1];

void main() {
  test('sets of the binding workout whose save waits on it are kept', () {
    final n = ActiveWorkoutNotifier()
      ..completeSet(_a, {'reps': 8, 'weight': 60.0})
      ..setSetData(_b, {'weight': 62.5});
    expect(n.holdForBind(_a.id), isTrue);
    expect(n.holdForBind(_b.id), isTrue);
    n.beginSession('s1', heldFor: _w1);
    expect(n.sessionId, 's1');
    expect(n.isSetCompleted(_a.id), isTrue);
    expect(n.setData(_a.id)['reps'], 8);
    expect(n.setData(_b.id)['weight'], 62.5);
    expect(n.completedSetCount, 1);
  });

  test('a set confirmed with no save waiting on the bind is not kept', () {
    // A tick on a filed Zone: nothing is sent for it, so nothing holds it.
    final n = ActiveWorkoutNotifier()..completeSet(_a, {'reps': 8});
    n.beginSession('s1', heldFor: _w1);
    expect(n.state, isEmpty,
        reason: 'only a save waiting on the session makes a set this session\'s');
  });

  test('a held set whose save failed is let go, and is not kept by the next bind', () {
    final n = ActiveWorkoutNotifier()..completeSet(_a, {'reps': 8, 'weight': 60.0});
    n.holdForBind(_a.id);
    n.releaseUnsaved(_a.id);
    expect(n.isSetCompleted(_a.id), isFalse, reason: 'not shown as done with no row');
    expect(n.setData(_a.id)['reps'], 8, reason: 'what was typed stays');
    n.beginSession('s1', heldFor: _w1);
    expect(n.state, isEmpty);
  });

  test('a bound state holds nothing: holdForBind answers false', () {
    final n = ActiveWorkoutNotifier()..beginSession('s1', heldFor: _w1);
    expect(n.holdForBind(_a.id), isFalse);
  });

  test('held sets that are not the binding workout\'s are dropped', () {
    final n = ActiveWorkoutNotifier()..completeSet(_a, {'reps': 8});
    n.holdForBind(_a.id);
    final other = _w2.exercises.first.sets.first;
    expect(_w2.exercises.expand((e) => e.sets).map((s) => s.id), isNot(contains(_a.id)),
        reason: 'premise: the two workouts share no set id');
    n.beginSession('s2', heldFor: _w2);
    expect(n.state, isEmpty);
    expect(n.isSetCompleted(other.id), isFalse);
  });

  test('a bind with no workout named (the restore path) starts empty', () {
    final n = ActiveWorkoutNotifier()..completeSet(_a, {'reps': 8});
    n.holdForBind(_a.id);
    n.beginSession('s1');
    expect(n.state, isEmpty);
  });

  test('switching from one BOUND session to another starts empty', () {
    final n = ActiveWorkoutNotifier()..beginSession('s1', heldFor: _w1);
    n.completeSet(_a, {'reps': 8});
    n.beginSession('s2', heldFor: _w1);
    expect(n.state, isEmpty, reason: "s1's sets are not s2's");
  });

  test('a set kept by a late bind is not kept again by the next session', () {
    // Held, kept by s1's bind — and s1 is then left for s2 (the next workout
    // started over it). What s1 kept is s1's, not s2's.
    final n = ActiveWorkoutNotifier()..completeSet(_a, {'reps': 8});
    n.holdForBind(_a.id);
    n.beginSession('s1', heldFor: _w1);
    expect(n.isSetCompleted(_a.id), isTrue, reason: 'premise: kept by the late bind');
    n.beginSession('s2', heldFor: _w1);
    expect(n.state, isEmpty,
        reason: 'the bind lets go of what it kept: s1\'s set is not s2\'s');
  });

  test('re-binding the same session keeps everything', () {
    final n = ActiveWorkoutNotifier()..beginSession('s1', heldFor: _w1);
    n.completeSet(_a, {'reps': 8});
    n.beginSession('s1', heldFor: _w1);
    expect(n.isSetCompleted(_a.id), isTrue);
  });

  test('reset forgets what was held: nothing is carried into the next bind', () {
    final n = ActiveWorkoutNotifier()..completeSet(_a, {'reps': 8});
    n.holdForBind(_a.id);
    n.reset();
    n.restoreSeated({_a.id: {'set_id': _a.id, 'completed': true}});
    n.beginSession('s1', heldFor: _w1);
    expect(n.state, isEmpty,
        reason: 'only saves waiting since the last reset are held');
  });
}
