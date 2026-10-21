import 'dart:io';

import 'package:flutter_test/flutter_test.dart';


// EC-05 / N-07 · "Workout completion swallows persistence and celebrates
// anyway" — docs/MASTER_REMEDIATION_REGISTRY.md:53, CONFIRMED.
//
// `test/unit/workout_save_test.dart` pins what the RULE says. This pins that
// the SCREEN is wired to it.
//
// ── WHY THIS IS SOURCE AND NOT A PUMPED SCREEN ─────────────────────────────
// `ActiveWorkoutScreen` cannot be pumped with a workout selected. Two of the
// three obstacles were genuine testability defects and were fixed — an eager
// `final _db = Supabase.instance.client` on the State, and the same in
// `CustomExerciseService`, both now resolved on use, which is the rule
// `WorkoutService` already states for itself.
//
// The third is not a defect: `initState` calls `_startSession`, which reads
// `_db.auth.currentUser`. Starting a session on mount is what this screen is
// FOR. Getting past it needs a Supabase test harness with a signed-in user,
// which does not exist in this repository.
//
// So these are source assertions, labelled as such, and worth exactly what
// source assertions are worth: they prove the guard is wired, not that it
// behaves. The behaviour is pinned one layer down, on rules a test can reach.
// A Supabase-backed harness is recorded as the missing dependency.

void main() {
  late String src;

  setUpAll(() {
    src = File('lib/features/workout/presentation/active_workout_screen.dart')
        .readAsStringSync()
        .split('\n')
        .map((l) {
          final i = l.indexOf('//');
          return i < 0 ? l : l.substring(0, i);
        })
        .join('\n');
  });

  test('EC-05 [SOURCE] no write in the completion path is unguarded', () {
    // `await _workoutService.logWorkout(log);` stood alone. A throw propagated
    // out of `_completeWorkout`, so `setState(() => _saving = false)` never
    // ran and the Complete button — `onPressed: _saving ? null : ...` — was
    // permanently dead.
    // A regex for "the call is on its own line" would match either way — the
    // call still looks identical inside a `try`. What changed is that it sits
    // between a `try {` and the flag that records success, so that is what is
    // asserted.
    final decl = src.indexOf('var logWritten = false;');
    final ok = src.indexOf('logWritten = true;');
    expect(decl, greaterThan(0), reason: 'the success flag is gone');
    expect(ok, greaterThan(decl));

    final block = src.substring(decl, ok);
    expect(block, contains('try {'),
        reason: 'logWorkout is unguarded again — a throw propagates out of '
            '_completeWorkout and leaves _saving true, which disables the '
            'Complete button permanently');
    expect(block, contains('await _workoutService.logWorkout(log);'),
        reason: 'and the guarded call must still be the real one');
  });

  test('EC-05 [SOURCE] completeSession is no longer discarded', () {
    // It was `catch (_) {}` — the failure vanished and the flow celebrated.
    expect(src, contains('sessionCompleted = true'));
    expect(src, contains('sessionCompleted: sessionCompleted'));
  });

  test('EC-05 [SOURCE] the finish is gated on the outcome', () {
    // reset() + invalidate() + the celebration dialog all ran unconditionally.
    expect(src, contains('workoutSaveOutcome('));
    expect(src, contains('if (!mayFinishWorkout(outcome))'));
  });

  test('EC-05 [SOURCE] a failure clears _saving so the control comes back',
      () {
    // Without this the user is left with a finished workout, a dead button and
    // nothing said.
    final failureBranch = src.substring(
      src.indexOf('if (!mayFinishWorkout(outcome))'),
      src.indexOf('if (!mayFinishWorkout(outcome))') + 400,
    );
    expect(failureBranch, contains('_saving = false'));
    expect(failureBranch, contains('_saveFailedCompleting = true'));
    expect(failureBranch, contains('return;'),
        reason: 'the failure path must not fall through into the reset and '
            'the celebration');
  });

  test('EC-05 [SOURCE] the failure is visible, in this screen\'s own words',
      () {
    expect(src, contains('workoutSaveFailedMessage'));
    expect(src, contains('workoutSaveRetryLabel'));
  });

  test('EC-05 [SOURCE] nothing is reset before the outcome is known', () {
    // The local sets are the only remaining copy of what the user did.
    final gate = src.indexOf('if (!mayFinishWorkout(outcome))');
    final reset = src.indexOf('activeWorkoutProvider.notifier).reset()');
    expect(gate, greaterThan(0));
    expect(reset, greaterThan(gate),
        reason: 'the reset must come AFTER the gate, or a failed save still '
            'destroys the session');
  });

  test('EC-05 [SOURCE] the client is resolved on use, not at construction',
      () {
    // An eager `final _db = Supabase.instance.client` made merely
    // CONSTRUCTING this State throw outside a Supabase app.
    expect(RegExp(r'final _db = Supabase\.instance\.client').hasMatch(src),
        isFalse);
    expect(src, contains('SupabaseClient get _db'));
  });
}
