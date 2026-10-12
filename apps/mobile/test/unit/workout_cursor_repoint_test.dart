import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/workout/data/models/exercise_model.dart';
import 'package:circle_fitness/features/workout/data/models/workout_model.dart';
import 'package:circle_fitness/features/workout/presentation/active_workout_screen.dart';

/// The set cursor after an exercise swap.
///
/// ── THE DEFECT ─────────────────────────────────────────────────────────────
/// `_swapExercise` re-points the cursor so that, as its own comment says, "a
/// refresh lands somewhere that exists". The condition was written
///
///     replacement.sets.isNotEmpty &&
///         (_currentSetId == null || we.setById(_currentSetId!) != null)
///
/// and the field is `String _currentSetId = ''` — NON-NULLABLE, with the empty
/// string as its "no cursor yet" sentinel. `== null` was therefore always false
/// (the analyzer said so twice, at warning level), and the case it meant to
/// cover fell through to `setById('')`, which matches no set and returns null.
///
/// So the condition was false exactly when it had to be true: a client who
/// swapped an exercise BEFORE touching any set kept a cursor pointing into the
/// exercise that no longer exists. That is the failure the comment claims to
/// prevent, and nothing tested it — the existing `replacedBy` coverage in
/// `workout_domain_contract_test.dart` tests the MODEL's swap, not the screen's
/// cursor.
Exercise _ex(String id, String name) => Exercise(
      id: id, name: name, category: 'Strength', muscleGroup: 'Chest',
      equipment: 'Barbell', difficulty: 'Intermediate',
      description: '', instructions: const []);

WorkoutExercise _we(String instanceId, String exId, int setCount) =>
    WorkoutExercise(
      instanceId: instanceId,
      exercise: _ex(exId, exId),
      sets: [
        for (var n = 1; n <= setCount; n++) WorkoutSet(setNumber: n, reps: 8),
      ],
    );

void main() {
  group('shouldRepointCursor · positive paths', () {
    test('NO CURSOR YET re-points — the case the null check silently lost', () {
      final replaced = _we('old-1', 'bench', 3);
      final replacement = _we('swap-1', 'goblet', 3);

      expect(
        shouldRepointCursor(
            currentSetId: '', replaced: replaced, replacement: replacement),
        isTrue,
        reason: 'the empty string is the field\'s "no cursor" sentinel, not '
            'null; before the fix this returned false and the cursor was left '
            'pointing into the exercise that had just been removed',
      );
    });

    test('a cursor INSIDE the replaced exercise re-points', () {
      final replaced = _we('old-1', 'bench', 3);
      final replacement = _we('swap-1', 'goblet', 3);
      final inside = replaced.sets.first.id;

      expect(inside, isNotEmpty,
          reason: 'putting a set in a WorkoutExercise assigns it an id; if this '
              'is empty the next assertion would pass for the wrong reason');
      expect(
        shouldRepointCursor(currentSetId: inside, replaced: replaced,
            replacement: replacement),
        isTrue,
      );
    });
  });

  group('shouldRepointCursor · negative paths', () {
    test('a cursor in some OTHER exercise is left alone', () {
      final replaced = _we('old-1', 'bench', 3);
      final replacement = _we('swap-1', 'goblet', 3);
      final elsewhere = _we('other-1', 'row', 2).sets.first.id;

      expect(replaced.setById(elsewhere), isNull,
          reason: 'the premise: this id does not belong to the replaced exercise');
      expect(
        shouldRepointCursor(currentSetId: elsewhere, replaced: replaced,
            replacement: replacement),
        isFalse,
        reason: 're-pointing here would move a cursor the swap did not disturb',
      );
    });

    test('a replacement with NO sets never re-points, even with no cursor', () {
      final replaced = _we('old-1', 'bench', 3);
      final empty = _we('swap-1', 'goblet', 0);

      expect(empty.sets, isEmpty);
      expect(
        shouldRepointCursor(
            currentSetId: '', replaced: replaced, replacement: empty),
        isFalse,
        reason: 'the caller reads `sets.first` immediately — a true here would '
            'throw rather than re-point',
      );
      // And the ordering matters: the empty-cursor arm must not win first.
      expect(
        shouldRepointCursor(currentSetId: replaced.sets.first.id,
            replaced: replaced, replacement: empty),
        isFalse,
      );
    });
  });

  group('shouldRepointCursor · the premise cannot drift', () {
    test('_currentSetId is a non-nullable String with an empty-string sentinel',
        () {
      // If this field is ever made nullable, the empty-string sentinel stops
      // being the "no cursor" value and the first test above silently stops
      // testing the real path. Pin the declaration.
      final src = File(
              'lib/features/workout/presentation/active_workout_screen.dart')
          .readAsStringSync();
      expect(src, contains("String _currentSetId = ''"),
          reason: 'the sentinel these tests are written against');
      expect(RegExp(r'String\?\s+_currentSetId').hasMatch(src), isFalse,
          reason: 'a nullable _currentSetId would reintroduce the null arm the '
              'analyzer flagged as dead');
    });

    test('the corrected call site no longer compares the cursor to null', () {
      final src = File(
              'lib/features/workout/presentation/active_workout_screen.dart')
          .readAsStringSync();
      expect(src, contains('shouldRepointCursor('),
          reason: 'the decision is the extracted predicate, not an inline condition');

      // CODE, not prose. The first version of this read `src` raw and FAILED in
      // CI — because `shouldRepointCursor`'s own doc comment QUOTES the defective
      // condition, `_currentSetId == null` included, to explain what was wrong
      // with it. A detector tripping over its own documentation is the third
      // instance of that shape here (SEC-G9's `can\w*`, the `<Icon>` glyph
      // check), and this time it was written into a test whose comment describes
      // that very pattern. Strip comments, and prove the strip worked.
      final code = src
          .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
          .replaceAll(RegExp(r'//[^\n]*'), '');
      expect(src.contains('_currentSetId == null'), isTrue,
          reason: 'the doc comment deliberately quotes the old condition; if this '
              'is false, the strip below is no longer testing anything');
      expect(code.contains('_currentSetId == null'), isFalse,
          reason: 'the dead null comparison must not survive as CODE');
    });
  });
}
