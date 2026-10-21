import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/features/workout/domain/session_complete.dart';

/// FIT-018 · "Session complete".
///
/// The anchor was carried as **4/4 and is 0/4**. All four of its declared
/// interactions are one word — `Easy`, `Right`, `Hard`, `Done` — and the old
/// measurement matched one-word labels as substrings, so `Done` found
/// `abandoned` and `Right` found `Alignment.centerRight`. `Easy` and `Hard`
/// appear nowhere in `lib`.

void main() {
  group('the effort question', () {
    test('is the board\'s, with the board\'s three answers', () {
      expect(effortQuestion, 'How did it feel?');
      expect(SessionEffort.values.map((e) => e.label).toList(),
          ['Easy', 'Right', 'Hard']);
      expect(sessionDoneLabel, 'Done');
    });

    // Three answers onto a 1–5 column, using the extremes and the middle.
    test('encodes onto workout_feedback.difficulty', () {
      expect(SessionEffort.easy.difficulty, 1);
      expect(SessionEffort.right.difficulty, 3);
      expect(SessionEffort.hard.difficulty, 5);
      for (final e in SessionEffort.values) {
        expect(e.difficulty, inInclusiveRange(1, 5),
            reason: 'the column is CHECK (difficulty BETWEEN 1 AND 5)');
      }
    });

    test('is reversible', () {
      for (final e in SessionEffort.values) {
        expect(effortFromDifficulty(e.difficulty), e);
      }
    });

    // A 2 or a 4 did not come from this question. Guessing which word it was
    // nearest would invent an answer the client never gave — the same refusal
    // OD-16 makes in the other direction.
    test('a value this app never writes reads back as nothing', () {
      expect(effortFromDifficulty(2), isNull);
      expect(effortFromDifficulty(4), isNull);
      expect(effortFromDifficulty(0), isNull);
      expect(effortFromDifficulty(null), isNull);
    });
  });

  group('the title', () {
    // FIT-016 titles the session `Lower body — strength`; FIT-018 says
    // `Lower body, done.` — the qualifier goes, because what is being said is
    // that a session finished.
    test('drops the qualifier after the em dash', () {
      expect(sessionDoneTitle('Lower body — strength'), 'Lower body, done.');
      expect(sessionDoneTitle('Upper body — push'), 'Upper body, done.');
    });

    test('a title with no em dash is used whole', () {
      expect(sessionDoneTitle('Conditioning'), 'Conditioning, done.');
      expect(sessionDoneTitle('Full Body Strength'), 'Full Body Strength, done.');
    });

    // A hyphen is not an em dash, and cutting at one would mangle a real title.
    test('a hyphen is left alone', () {
      expect(sessionDoneTitle('Push-pull split'), 'Push-pull split, done.');
    });

    test('no title still says what happened', () {
      expect(sessionDoneTitle(null), 'Session done.');
      expect(sessionDoneTitle('   '), 'Session done.');
    });
  });

  group('the three stats', () {
    test('read as the board draws them', () {
      final s = sessionStats(
          elapsedSeconds: 51 * 60, setsLogged: 18, volumeKg: 4200);
      expect(s.map((x) => x.spoken).toList(), [
        '51 min Duration',
        '18 Sets logged',
        '4.2 t Volume',
      ]);
    });

    test('are spoken as sentences, not fragments', () {
      final s = sessionStats(
          elapsedSeconds: 51 * 60, setsLogged: 18, volumeKg: 4200);
      expect(s.map((x) => x.spoken).toList(),
          ['51 min Duration', '18 Sets logged', '4.2 t Volume']);
    });

    // Three stats being two beats one of them being a confident zero.
    test('a bodyweight session has no volume stat', () {
      final s =
          sessionStats(elapsedSeconds: 30 * 60, setsLogged: 12, volumeKg: 0);
      expect(s.map((x) => x.label).toList(), ['Duration', 'Sets logged']);
      expect(s.map((x) => x.value), isNot(contains('0.0')));
    });

    test('a session under a minute has no duration stat', () {
      final s = sessionStats(elapsedSeconds: 45, setsLogged: 2, volumeKg: 100);
      expect(s.map((x) => x.label).toList(), ['Sets logged', 'Volume']);
    });

    test('nothing logged produces no stats at all', () {
      expect(sessionStats(elapsedSeconds: 0, setsLogged: 0, volumeKg: 0),
          isEmpty);
    });

    test('volume rounds to one decimal, as the board writes it', () {
      expect(
          sessionStats(elapsedSeconds: 0, setsLogged: 0, volumeKg: 4250)
              .single
              .value,
          '4.3');
      // A light session reads in tonnes too — the board's unit, not a
      // threshold invented here.
      expect(
          sessionStats(elapsedSeconds: 0, setsLogged: 0, volumeKg: 400)
              .single
              .value,
          '0.4');
    });
  });

  group('volume', () {
    test('is reps times load, summed', () {
      expect(
        sessionVolumeKg([
          (reps: 6, weightKg: 65.0),
          (reps: 8, weightKg: 62.5),
        ]),
        6 * 65.0 + 8 * 62.5,
      );
    });

    // Bodyweight work is real work, but this figure is about LOAD and the
    // board labels it in tonnes.
    test('a set with no load contributes nothing', () {
      expect(sessionVolumeKg([(reps: 12, weightKg: null)]), 0);
      expect(sessionVolumeKg([(reps: 12, weightKg: 0.0)]), 0);
    });

    test('a set with no reps contributes nothing', () {
      expect(sessionVolumeKg([(reps: 0, weightKg: 60.0)]), 0);
    });

    test('a negative load is refused rather than subtracted', () {
      expect(sessionVolumeKg([(reps: 5, weightKg: -60.0)]), 0);
    });

    test('nothing logged is zero', () {
      expect(sessionVolumeKg(const []), 0);
    });
  });
}
