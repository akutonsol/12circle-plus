import 'package:flutter_test/flutter_test.dart';

/// Pumps until [condition] holds, giving REAL time to real I/O between frames.
///
/// WHY (P0-FL-51): inside `testWidgets` the body runs on a fake clock and the
/// real event loop only turns inside `tester.runAsync`. Real `dart:io` work —
/// e.g. `XFile.readAsBytes()` after an image pick — is a chain of I/O hops
/// (open → length → read → close). Each hop's reply arrives during a
/// `runAsync` window, but its continuation is a fake-zone microtask that runs
/// only at the NEXT pump, so every window moves the chain forward by at most
/// one hop. A fixed budget ("8 × runAsync(30 ms) + pump") is therefore a race
/// against machine load: on a busy machine a hop misses its window, the budget
/// runs out before the request is sent, and the test's premise fails.
///
/// This waits for the observable event instead, up to [timeout] of real time,
/// and fails with [what] in the message if it never happens. Each frame is
/// `pump(step)`; the default [step] is zero so waiting on real I/O does not
/// age fake timers (a SnackBar's 4 s, an animation) — the fake clock moves
/// only where the test moves it.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String what,
  Duration timeout = const Duration(seconds: 30),
  Duration step = Duration.zero,
}) async {
  final clock = Stopwatch()..start();
  while (!condition()) {
    if (clock.elapsed > timeout) {
      fail('Timed out after ${timeout.inSeconds} s of real time waiting for '
          '$what.');
    }
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(step);
  }
}
