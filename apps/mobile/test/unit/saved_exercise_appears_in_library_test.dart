import 'dart:io';

import 'package:circle_fitness/features/exercise_database/data/models/exercise_detail_model.dart';
import 'package:circle_fitness/features/exercise_database/domain/custom_exercise_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// A coach's saved exercise did not appear in the Exercise Database.
//
// The library lists `myExercisesProvider` and `globalApprovedExercisesProvider`.
// Create went through `MyExercisesNotifier`, which reloads only its own state
// (shown nowhere); edits and media went straight to the service; nothing re-read
// the two lists, which never dispose. "Back to Library" showed the list without
// the exercise just saved, edited or submitted. "Submit to Global Library" also
// ignored the result and said "Published…" for a submission that failed.

void main() {
  test('saving re-reads both lists the library shows', () async {
    final reads = <String, int>{};
    final c = ProviderContainer(overrides: [
      myExercisesProvider.overrideWith((ref) async {
        reads['mine'] = (reads['mine'] ?? 0) + 1;
        return const <ExerciseDetail>[];
      }),
      globalApprovedExercisesProvider.overrideWith((ref) async {
        reads['global'] = (reads['global'] ?? 0) + 1;
        return const <ExerciseDetail>[];
      }),
    ]);
    addTearDown(c.dispose);
    c.listen(myExercisesProvider, (_, __) {});
    c.listen(globalApprovedExercisesProvider, (_, __) {});
    await c.read(myExercisesProvider.future);
    await c.read(globalApprovedExercisesProvider.future);

    refreshExerciseLists(c.invalidate);
    await c.read(myExercisesProvider.future);
    await c.read(globalApprovedExercisesProvider.future);

    expect(reads, {'mine': 2, 'global': 2});
  });

  test('guard: the create screen refreshes after a save and checks a submission', () {
    // Source guard: proves the calls are made, not how the screen renders.
    final src = File('lib/features/exercise_database/presentation/create_exercise_screen.dart')
        .readAsStringSync();
    expect('refreshExerciseLists(ref.invalidate)'.allMatches(src).length, 2,
        reason: 'THE defect: nothing re-read the library after a save or a submission');
    expect(src.contains('submitForGlobal(_savedId!).then((_)'), isFalse,
        reason: 'the submission result was ignored');
  });
}
