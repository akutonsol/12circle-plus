import 'dart:async';

import 'package:circle_fitness/core/realtime/realtime.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/home/presentation/home_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Home's week bars count this week's meals and coaching calls, and nothing
// re-read them when a call changed: a call booked (or cancelled) left its day's
// bar as it was until the app restarted. The provider now follows
// coaching_calls through the realtime ticker the app uses everywhere else.
//
// HOW TO SEE IT FAIL: on main a coaching_calls change does not re-run the
// provider (1 build, not 2) — the wait for the second build times out.
//
// P0-FL-63e: this waited a fixed 50 ms twice, a race against machine load (the
// first build, or the re-run, had not settled yet under the full suite). It now
// waits for each SETTLED build as an event, bounded so that a re-run that never
// comes fails, naming it, instead of hanging.

/// Long enough that no load reaches it (the run is in-memory, no backend), and
/// well inside the test's own 30 s timeout so the reason below is what is said.
const _bound = Duration(seconds: 10);

void main() {
  test("a coaching_calls change re-reads Home's week", () async {
    final ticks = StreamController<int>();
    // Not awaited: when the provider does NOT follow coaching_calls (the
    // defect) nothing listened to [ticks], and its close() never completes —
    // the teardown would then hang the failure to the 30 s test timeout.
    addTearDown(() => unawaited(ticks.close()));
    var builds = 0;
    var settled = Completer<void>();
    final c = ProviderContainer(overrides: [
      // What is counted is purely whether the provider RE-RUNS (each run
      // settles, as data or as an error -- no backend here), not what it reads.
      currentUserProvider.overrideWithValue(null),
      tableTickerProvider.overrideWith((ref, table) {
        if (table == 'coaching_calls') return ticks.stream;
        return Stream.value(0);
      }),
    ]);
    addTearDown(c.dispose);
    c.listen(weeklyActivityProvider, (_, next) {
      if (next.isLoading) return;
      builds++;
      if (!settled.isCompleted) settled.complete();
    }, fireImmediately: true);

    Future<void> nextSettledBuild(String what) => settled.future.timeout(
        _bound,
        onTimeout: () => fail('No settled build of weeklyActivityProvider '
            'within ${_bound.inSeconds} s: $what (builds so far: $builds).'));

    await nextSettledBuild('premise: the first build');
    final before = builds;
    expect(before, 1, reason: 'premise: exactly one build before the tick');

    settled = Completer<void>(); // armed BEFORE the tick, so it cannot be missed
    ticks.add(1); // a call was booked
    await nextSettledBuild(
        "THE defect: a booked call left Home's week as it was");
    expect(builds, greaterThan(before),
        reason: "THE defect: a booked call left Home's week as it was");
  });
}
