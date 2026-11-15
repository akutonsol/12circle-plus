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
// provider (1 build, not 2).
void main() {
  test("a coaching_calls change re-reads Home's week", () async {
    final ticks = StreamController<int>();
    addTearDown(ticks.close);
    var builds = 0;
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
      if (!next.isLoading) builds++;
    }, fireImmediately: true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final before = builds;
    ticks.add(1); // a call was booked
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(builds, greaterThan(before),
        reason: "THE defect: a booked call left Home's week as it was");
  });
}
