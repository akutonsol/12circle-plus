import 'dart:async';

import 'package:circle_fitness/core/realtime/realtime.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/dashboard/presentation/coach_dashboard_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// The coach dashboard's "this week" workouts and check-ins were read when the
// dashboard opened and never again: a client finishing a workout or submitting
// a check-in did not show until the coach left and came back. The client
// roster beside them already followed realtime (coach_client_relationships);
// these now follow workout_sessions and weekly_checkins -- both published for
// realtime -- through the same ticker.
//
// HOW TO SEE IT FAIL: on main a tick does not re-run the provider.

Future<void> _expectFollows(ProviderListenable<AsyncValue<Object?>> provider,
    String table, String what) async {
  final ticks = StreamController<int>();
  // Not awaited: on the pre-fix provider nothing listens, and close() on a
  // never-listened stream does not complete.
  addTearDown(() => unawaited(ticks.close()));
  var builds = 0;
  final c = ProviderContainer(overrides: [
    // Whether the provider RE-RUNS is what is counted (each run settles, as
    // data or as an error -- no backend here), not what it reads.
    currentUserProvider.overrideWithValue(null),
    tableTickerProvider.overrideWith((ref, t) => t == table ? ticks.stream : Stream.value(0)),
  ]);
  addTearDown(c.dispose);
  c.listen(provider, (_, next) {
    if (!next.isLoading) builds++;
  }, fireImmediately: true);
  await Future<void>.delayed(const Duration(milliseconds: 50));
  final before = builds;
  ticks.add(1);
  await Future<void>.delayed(const Duration(milliseconds: 50));
  expect(builds, greaterThan(before), reason: 'THE defect: $what');
}

void main() {
  test("a client's finished workout re-reads the coach's week", () =>
      _expectFollows(clientWorkoutLogsProvider, 'workout_sessions',
          'a finished workout did not reach the open dashboard'));

  test("a client's submitted check-in re-reads the coach's week", () =>
      _expectFollows(clientCheckinsProvider, 'weekly_checkins',
          'a submitted check-in did not reach the open dashboard'));

  test('an unrelated table does not re-read them (control)', () async {
    final ticks = StreamController<int>();
    // Not awaited: nothing listens to an unrelated table, and close() on a
    // never-listened stream does not complete.
    addTearDown(() => unawaited(ticks.close()));
    var builds = 0;
    final c = ProviderContainer(overrides: [
      currentUserProvider.overrideWithValue(null),
      tableTickerProvider.overrideWith((ref, t) => t == 'messages' ? ticks.stream : Stream.value(0)),
    ]);
    addTearDown(c.dispose);
    c.listen(clientWorkoutLogsProvider, (_, next) {
      if (!next.isLoading) builds++;
    }, fireImmediately: true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final before = builds;
    ticks.add(1);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(builds, before);
  });
}
