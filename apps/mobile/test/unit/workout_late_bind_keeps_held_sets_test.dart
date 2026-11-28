import 'package:circle_fitness/features/workout/data/workout_service.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:flutter_test/flutter_test.dart';

// C14-62d-02 · what `ActiveWorkoutNotifier.beginSession` keeps when a session
// binds late. The Zone-level proof is
// test/widget/workout_held_sets_and_filed_once_test.dart; this pins the rule.
//
// HOW TO SEE IT FAIL: `git checkout 6d1611d --
// lib/features/workout/domain/workout_provider.dart` (no `heldFor:`, and the
// first test's set is cleared).

final _w1 = WorkoutService().getSampleWorkouts()[0];
final _w2 = WorkoutService().getSampleWorkouts()[1];
final _a = _w1.exercises.first.sets.first;
final _b = _w1.exercises.first.sets[1];

void main() {
  test('sets of the binding workout confirmed while unbound are kept', () {
    final n = ActiveWorkoutNotifier()
      ..completeSet(_a, {'reps': 8, 'weight': 60.0})
      ..setSetData(_b, {'weight': 62.5});
    n.beginSession('s1', heldFor: _w1);
    expect(n.sessionId, 's1');
    expect(n.isSetCompleted(_a.id), isTrue);
    expect(n.setData(_a.id)['reps'], 8);
    expect(n.setData(_b.id)['weight'], 62.5);
    expect(n.completedSetCount, 1);
  });

  test('held sets that are not the binding workout\'s are dropped', () {
    final n = ActiveWorkoutNotifier()..completeSet(_a, {'reps': 8});
    final other = _w2.exercises.first.sets.first;
    expect(_w2.exercises.expand((e) => e.sets).map((s) => s.id), isNot(contains(_a.id)),
        reason: 'premise: the two workouts share no set id');
    n.beginSession('s2', heldFor: _w2);
    expect(n.state, isEmpty);
    expect(n.isSetCompleted(other.id), isFalse);
  });

  test('a bind with no workout named (the restore path) starts empty', () {
    final n = ActiveWorkoutNotifier()..completeSet(_a, {'reps': 8});
    n.beginSession('s1');
    expect(n.state, isEmpty);
  });

  test('switching from one BOUND session to another starts empty', () {
    final n = ActiveWorkoutNotifier()..beginSession('s1', heldFor: _w1);
    n.completeSet(_a, {'reps': 8});
    n.beginSession('s2', heldFor: _w1);
    expect(n.state, isEmpty, reason: "s1's sets are not s2's");
  });

  test('re-binding the same session keeps everything', () {
    final n = ActiveWorkoutNotifier()..beginSession('s1', heldFor: _w1);
    n.completeSet(_a, {'reps': 8});
    n.beginSession('s1', heldFor: _w1);
    expect(n.isSetCompleted(_a.id), isTrue);
  });

  test('reset forgets what was held: nothing is carried into the next bind', () {
    final n = ActiveWorkoutNotifier()..completeSet(_a, {'reps': 8});
    n.reset();
    n.restoreSeated({_a.id: {'set_id': _a.id, 'completed': true}});
    n.beginSession('s1', heldFor: _w1);
    expect(n.state, isEmpty,
        reason: 'only sets entered while unbound since the last reset are held');
  });
}
