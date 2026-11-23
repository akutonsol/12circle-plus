import 'dart:async';

import 'package:circle_fitness/core/realtime/realtime.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/row_checking_postgrest.dart';

// P0-FL-47 — the coach dashboard Leaderboard tab did not follow a client's
// daily score.
//
// coachLeaderboardProvider (coach_ecosystem_provider.dart) reads
// `daily_scores` (ScoreService.getCoachLeaderboard) but re-read on
// tableTickerProvider('user_scores'). The two tables are written by
// different paths: `daily_scores` by the client app's ScoreService upsert
// (workout, nutrition, habits, check-in, community points), `user_scores` only
// by the award_points / apply_penalty RPCs (migrations 035, 054). A client
// finishing a workout or ticking habits changes `daily_scores` and nothing
// told the coach's leaderboard.
//
// App-only: `daily_scores` is already in the supabase_realtime publication
// (migration 037) and a coach may SELECT an active client's rows (migration
// 100, "coaches read client scores": user_id = auth.uid() OR
// is_active_coach_of(user_id)), so realtime delivers the client's change to
// the coach. No migration needed.
//
// HOW TO SEE IT FAIL: `git checkout 185261e -- lib/features/coach/domain/
// coach_ecosystem_provider.dart` — a daily_scores change does not re-read the
// leaderboard.

const _uid = '00000000-0000-4000-8000-0000000f2047';
const _client = '00000000-0000-4000-8000-00000000a247';

class _Server extends RowCheckingPostgrest {
  _Server() : super(_uid);
  int dailyReads = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'GET' &&
        request.url.path.endsWith('/rest/v1/daily_scores')) {
      dailyReads++;
    }
    return super.send(request);
  }
}

void main() {
  late _Server server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = _Server();
    await initSignedInSupabase(server);
  });

  setUp(() {
    server.reset();
    server.dailyReads = 0;
    // An active client, so the leaderboard read reaches daily_scores.
    server.reads['coach_client_relationships'] = [
      {'client_id': _client}
    ];
  });

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 60));

  test('a change to daily_scores re-reads the coach leaderboard', () async {
    final daily = StreamController<int>();
    final others = <String, StreamController<int>>{};
    addTearDown(() {
      unawaited(daily.close());
      for (final c in others.values) {
        unawaited(c.close());
      }
    });
    final c = ProviderContainer(overrides: [
      currentUserProvider
          .overrideWithValue(Supabase.instance.client.auth.currentUser),
      tableTickerProvider.overrideWith((ref, table) => table == 'daily_scores'
          ? daily.stream
          : (others[table] ??= StreamController<int>()).stream),
    ]);
    addTearDown(c.dispose);
    c.listen(coachLeaderboardProvider, (_, __) {});
    daily.add(0);
    for (final o in others.values) {
      o.add(0);
    }
    await settle();
    await c.read(coachLeaderboardProvider.future);
    final before = server.dailyReads;
    expect(before, greaterThan(0), reason: 'the leaderboard reads daily_scores');

    daily.add(1); // a client finished a workout: their daily score was written
    await settle();
    await c.read(coachLeaderboardProvider.future);

    expect(server.dailyReads, greaterThan(before),
        reason: "THE defect: the coach's leaderboard kept the old daily score");
  });
}
