import 'dart:async';

import 'package:circle_fitness/core/realtime/realtime.dart';
import 'package:circle_fitness/features/scoring/data/score_engine.dart';
import 'package:circle_fitness/features/scoring/domain/score_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// The leaderboards did not follow score changes.
//
// myScoreProvider watches tableTickerProvider('user_scores'), so the hero card
// moved when points were earned. globalLeaderboardProvider and
// coachLeaderboardProvider watched only scoreRefreshProvider -- bumped by
// pull-to-refresh on the My Score tab -- so the member's own leaderboard row and
// rank kept the old total for the rest of the session.
//
// HOW TO SEE IT FAIL: on main a user_scores change does not re-read either
// leaderboard (1 read, not 2).

class _CountingEngine implements ScoreEngine {
  int global = 0;
  int coach = 0;
  @override
  Future<List<Map<String, dynamic>>> leaderboardGlobal({int limit = 50}) async {
    global++;
    return const [];
  }

  @override
  Future<List<Map<String, dynamic>>> leaderboardCoach(String coachId, {int limit = 50}) async {
    coach++;
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('a change to user_scores re-reads both leaderboards', () async {
    final ticks = StreamController<int>();
    addTearDown(ticks.close);
    final engine = _CountingEngine();
    final c = ProviderContainer(overrides: [
      scoreEngineProvider.overrideWithValue(engine),
      tableTickerProvider('user_scores').overrideWith((ref) => ticks.stream),
    ]);
    addTearDown(c.dispose);
    c.listen(globalLeaderboardProvider, (_, __) {});
    c.listen(coachLeaderboardProvider('coach-1'), (_, __) {});
    await c.read(globalLeaderboardProvider.future);
    await c.read(coachLeaderboardProvider('coach-1').future);
    expect((engine.global, engine.coach), (1, 1));

    ticks.add(1); // points were earned somewhere
    await Future<void>.delayed(Duration.zero);
    await c.read(globalLeaderboardProvider.future);
    await c.read(coachLeaderboardProvider('coach-1').future);
    expect(engine.global, 2,
        reason: 'THE defect: the leaderboard kept the old total after points changed');
    expect(engine.coach, 2);
  });
}
