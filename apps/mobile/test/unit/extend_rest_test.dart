import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';

/// FIT-017 · "Add 30 seconds" — the arithmetic.
///
/// `test/widget/rest_timer_controls_test.dart` proves the control exists, is
/// named in the design's wording, clears the target floor and calls the right
/// callback. It says nothing about what the callback should compute, and the
/// two interesting rules are both there:
///
///  1. extending adds to the **end**, not to now; and
///  2. overtime already accrued is **banked, not erased**.
///
/// Rule 2 is the one worth a test. Past zero, the siren has been sounding and
/// `ScoreEngine().idleTimePenalty()` has been draining points every 20 seconds.
/// If extending restarted the clock and reported no overtime, a client could
/// tap "+30s" the moment the siren began and wipe the overrun out of the
/// session's idle total. That is not a rest control, it is an undo button for
/// a penalty that already fired.
void main() {
  final t0 = DateTime(2026, 9, 23, 7, 0, 0);

  group('FIT-017 extendRest — while the clock is still running', () {
    test('adds 30s to the end, not to now', () {
      // 40s left of a 120s rest; 25s have already elapsed in real time.
      final rest = RestTimerState(t0.add(const Duration(seconds: 40)), 120);
      final r = extendRest(rest, t0.add(const Duration(seconds: 25)));

      expect(r.next.end, t0.add(const Duration(seconds: 70)));
      expect(r.bankedOvertime, 0);
    });

    test('two taps add a minute — they do not restart a short rest twice', () {
      var rest = RestTimerState(t0.add(const Duration(seconds: 10)), 60);
      rest = extendRest(rest, t0).next;
      rest = extendRest(rest, t0).next;

      expect(rest.end, t0.add(const Duration(seconds: 70)));
      expect(rest.total, 120);
    });

    test('total grows with end so the ring does not clamp at full', () {
      // remaining/total must stay <= 1. Without growing total, a 50s rest
      // extended to 80s reads 80/50 = 1.6, clamps to 1.0, and the bar looks
      // frozen for the first 30 seconds.
      final rest = RestTimerState(t0.add(const Duration(seconds: 50)), 50);
      final r = extendRest(rest, t0);

      final remaining = r.next.end.difference(t0).inSeconds;
      expect(remaining / r.next.total, lessThanOrEqualTo(1.0));
      expect(r.next.total, 80);
    });
  });

  group('FIT-017 extendRest — once the rest has run into overtime', () {
    test('the overrun is reported for banking, not discarded', () {
      final rest = RestTimerState(t0, 60);
      final r = extendRest(rest, t0.add(const Duration(seconds: 47)));

      expect(r.bankedOvertime, 47,
          reason: 'the 47s already spent in overtime must still count as idle '
              'time — extending is not an undo for a penalty that fired');
    });

    test('the new rest starts from now, at the full bonus', () {
      final now = t0.add(const Duration(seconds: 47));
      final r = extendRest(RestTimerState(t0, 60), now);

      expect(r.next.end, now.add(const Duration(seconds: 30)));
      expect(r.next.total, 30,
          reason: 'the ring should show the 30s that were asked for, not the '
              'original rest duration');
    });

    test('repeated extensions in overtime bank each overrun separately', () {
      // Tap at +47s, let it run over again, tap at +95s.
      final first = extendRest(RestTimerState(t0, 60),
          t0.add(const Duration(seconds: 47)));
      final second =
          extendRest(first.next, t0.add(const Duration(seconds: 95)));

      // first rest ends at t0+77; second tap at t0+95 is 18s past it.
      expect(second.bankedOvertime, 18);
      expect(first.bankedOvertime + second.bankedOvertime, 65);
    });
  });

  test('FIT-017 the exact instant of zero is not treated as overtime', () {
    // Boundary: difference == 0 is "the clock just hit zero", and the widget
    // only enters its overtime branch strictly past it.
    final r = extendRest(RestTimerState(t0, 60), t0);
    expect(r.bankedOvertime, 0);
    expect(r.next.end, t0.add(const Duration(seconds: 30)));
    expect(r.next.total, 90);
  });

  test('FIT-017 the bonus is a parameter, and the rules hold for any value', () {
    final r = extendRest(RestTimerState(t0.add(const Duration(seconds: 10)), 60),
        t0, bonus: 15);
    expect(r.next.end, t0.add(const Duration(seconds: 25)));
    expect(r.next.total, 75);
  });
}
