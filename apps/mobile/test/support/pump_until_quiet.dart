import 'package:flutter_test/flutter_test.dart';

/// Pumps until [quiet] has held for [calm] frames in a row, giving REAL time
/// to real I/O between frames (P0-FL-61 round 3).
///
/// WHY: a fixed budget of frames ("8 × pump(20 ms)") is a race against machine
/// load whenever an answer travels through real time (an auth call inside
/// `runAsync`, a platform channel, a file read): on a busy machine it lands
/// after the budget, and a test that asserts "nothing is shown" passes for the
/// wrong reason, or one that asserts "it is shown" flakes. This waits for the
/// observable thing instead — typically "every request the fake server took
/// has been answered, or is held by the test" — and then for [calm] more
/// frames, so what an answer schedules is drawn before the test looks.
///
/// Each frame advances the fake clock by [step] (as the fixed budgets did),
/// so a debounce or a SnackBar's timer still moves the way it used to.
Future<void> pumpUntilQuiet(
  WidgetTester tester,
  bool Function() quiet, {
  required String what,
  int calm = 3,
  Duration step = const Duration(milliseconds: 20),
  Duration timeout = const Duration(seconds: 30),
}) async {
  final clock = Stopwatch()..start();
  var still = 0;
  while (still < calm) {
    if (clock.elapsed > timeout) {
      fail('Timed out after ${timeout.inSeconds} s of real time waiting for '
          '$what.');
    }
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)));
    await tester.pump(step);
    still = quiet() ? still + 1 : 0;
  }
}
