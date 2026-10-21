import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/home/presentation/home_screen.dart';

/// F-15 · `/home` — "This Week's Progress" answered a question it could not
/// answer.
///
/// ── THE DEFECT ─────────────────────────────────────────────────────────────
/// `weeklyActivityProvider` ended `catch (_) { return List.filled(7, 0.0); }`,
/// so a failed read reached the card as a real week with nothing in it. The
/// card does not merely look empty — it **answers**. A client who had logged
/// six meals saw:
///
///   * **"0%"** in 28 pt brand colour, and
///   * "Log meals or workouts to see progress" underneath, and
///   * seven flat bars with today's lit at 15%.
///
/// A failure shown as a confident wrong number, with a nudge blaming the client
/// for it. `docs/QA_EVIDENCE.md` §6c lists this as one of nine error→empty
/// collapses and records it against the locked FIT-001.
///
/// ── WHY THIS ONE IS FIXED AND EIGHT ARE NOT ────────────────────────────────
/// The other eight need **user-facing error copy**, which the design package
/// does not supply for these frames, and writing it would be inventing product
/// copy (recorded as OD-8). This one needs none: a number the screen cannot
/// support becomes `'—'`, a nudge it cannot justify is omitted, and a bar that
/// would assert "nothing today" is drawn as the unknown track. The same
/// copy-free move was already made on `train_hub_screen`'s three
/// `error: (_, __) => '0'` stats.
///
/// A full error state with a retry — the `booking_screen.dart:612` pattern —
/// still awaits OD-8. This is strictly better than what shipped, and it
/// invents nothing.
void main() {
  const week = AsyncData<List<double>>([0.5, 0.0, 1.0, 0.0, 0.2, 0.0, 0.0]);

  group('F-15 a FAILED read is never reported as a number', () {
    final failed = AsyncError<List<double>>(Exception('offline'), StackTrace.empty);

    test('the headline is an em dash, not 0%', () {
      final p = weekProgressFrom(failed);
      expect(p.headline, '—');
      expect(p.headline, isNot(contains('%')));
    });

    test('the nudge is omitted rather than guessed', () {
      // "Log meals or workouts to see progress" is an accusation when the read
      // failed: the client may have logged all week.
      expect(weekProgressFrom(failed).nudge, isNull);
    });

    test('the bars are flat and the day is not highlighted', () {
      final p = weekProgressFrom(failed);
      expect(p.failed, isTrue);
      expect(p.bars, List.filled(7, 0.0));
    });

    test('a failed read that carries stale data still does not answer', () {
      // AsyncError can arrive holding a previous value. The screen must go by
      // the state, not by whatever happens to be in the box.
      final stale = AsyncError<List<double>>(Exception('offline'), StackTrace.empty)
          .copyWithPrevious(week);
      final p = weekProgressFrom(stale);
      expect(p.headline, '—');
      expect(p.nudge, isNull);
      expect(p.failed, isTrue);
    });
  });

  group('F-15 a real read still answers, exactly as before', () {
    test('a genuinely empty week is 0% with the nudge', () {
      // The fix must not have made an empty week indistinguishable from a
      // failure in the other direction — an empty week IS a real answer.
      final p = weekProgressFrom(const AsyncData<List<double>>([0, 0, 0, 0, 0, 0, 0]));
      expect(p.headline, '0%');
      expect(p.nudge, 'Log meals or workouts to see progress');
      expect(p.failed, isFalse);
    });

    test('three active days of seven is 43%', () {
      final p = weekProgressFrom(week);
      expect(p.headline, '43%');
      expect(p.nudge, 'Keep building your streak');
    });

    test('five active days of seven earns the top line', () {
      final p = weekProgressFrom(
          const AsyncData<List<double>>([1, 1, 1, 1, 1, 0.5, 0.5]));
      expect(p.headline, '100%');
      expect(p.nudge, 'Excellent consistency!');
    });

    test('the bar values are passed through untouched', () {
      expect(weekProgressFrom(week).bars, week.value);
    });

    test('a 0.05 value does not count as an active day', () {
      // 0.05 is the clamp floor the provider applies to a day with activity
      // that rounds to nothing against the week's maximum; the card's own
      // threshold is strictly greater than it.
      final p = weekProgressFrom(
          const AsyncData<List<double>>([0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05]));
      expect(p.headline, '0%');
    });
  });

  test('F-15 a loading read is not a failure and not an answer', () {
    final p = weekProgressFrom(const AsyncLoading<List<double>>());
    // The card shows a spinner in place of the headline while loading, so what
    // matters here is that it is not reported as failed and not given a nudge
    // derived from zeros it does not have.
    expect(p.failed, isFalse);
    expect(p.bars, List.filled(7, 0.0));
  });
}
