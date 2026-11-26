// P0-FL-59e · the optional `forUid` of ScoreService, ScoreEngine and
// NutritionService: for that member, or not at all. Without it, as before.
//
// New API: on a82f993 this file does not compile (there was no way to say whose
// award it is). The behaviour failures are in awards_stay_with_their_member.
// The "captured while nobody was signed in" test fails on 5f8b7f3, where null
// meant "not given".
import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/coach/data/score_service.dart';
import 'package:circle_fitness/features/nutrition/data/nutrition_service.dart';
import 'package:circle_fitness/features/scoring/data/score_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/member_switch_server.dart';

void main() {
  final server = MemberSwitchServer();
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(server);
  });

  setUp(() async {
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
    await signInAs(memberB);
  });
  tearDown(resetFailureSink);

  Iterable<String> origins() => reported.map((f) => f.origin);

  Future<void> meal(NutritionService s) => s.logMeal(
      mealType: 'lunch', foodName: 'Rice', calories: 1, protein: 1, carbs: 1,
      fat: 1, servingSize: 1, servingUnit: 'g');

  Future<void> everyScore(ScoreService s) async {
    await s.addWorkoutPoints();
    await s.addNutritionPoints(1);
    await s.addHabitPoints(1, 1);
    await s.addCheckinPoints();
    await s.addCommunityPoints();
  }

  for (final signedOut in [false, true]) {
    final who = signedOut ? 'nobody' : 'B';
    test("A's awards and meal while $who is signed in: no request at all, each "
        'recorded', () async {
      if (signedOut) await signOut();
      await everyScore(ScoreService(forUid: memberA));
      expect(origins(), List.filled(5, 'ScoreService.identity'));
      reported.clear();
      await ScoreEngine(forUid: memberA).mealLogged('m');
      await ScoreEngine(forUid: memberA).idleTimePenalty();
      expect(origins(), List.filled(2, 'ScoreEngine.identity'));
      reported.clear();
      await expectLater(
          meal(NutritionService(forUid: memberA)), throwsStateError);
      expect(origins(), ['NutritionService.identity']);
      expect(server.seen, isEmpty);
    });
  }

  test('POSITIVE CONTROL: forUid is the member signed in: written for them',
      () async {
    await everyScore(ScoreService(forUid: memberB));
    expect(server.writes('daily_scores').map((w) => w.row['user_id']),
        List.filled(5, memberB));
    await ScoreEngine(forUid: memberB).mealLogged('m');
    await ScoreEngine(forUid: memberB).idleTimePenalty();
    expect(server.writes('award_points'), hasLength(1));
    expect(server.writes('penalize_points'), hasLength(1));
    await meal(NutritionService(forUid: memberB));
    expect(server.writes('nutrition_logs').single.row['user_id'], memberB);
    expect(reported, isEmpty);
  });

  test('captured while nobody was signed in (null) is nobody\'s, not "no owner '
      'given": nothing is sent for whoever is signed in by now, recorded',
      () async {
    await everyScore(ScoreService(forUid: null));
    expect(origins(), List.filled(5, 'ScoreService.identity'));
    reported.clear();
    await ScoreEngine(forUid: null).mealLogged('m');
    await ScoreEngine(forUid: null).idleTimePenalty();
    expect(origins(), List.filled(2, 'ScoreEngine.identity'));
    reported.clear();
    await expectLater(meal(NutritionService(forUid: null)), throwsStateError);
    expect(origins(), ['NutritionService.identity']);
    expect(server.seen, isEmpty, reason: 'sent as B: ${server.seen}');
    // Still nobody: nothing, and nothing to record.
    reported.clear();
    await signOut();
    await everyScore(ScoreService(forUid: null));
    await ScoreEngine(forUid: null).mealLogged('m');
    expect(server.seen, isEmpty);
    expect(reported, isEmpty);
    await expectLater(meal(NutritionService(forUid: null)), throwsException);
    expect(server.seen, isEmpty);
  });

  test('BACKWARD COMPATIBLE: without forUid, the member signed in; signed out, '
      'nothing and no failure', () async {
    await ScoreService().addCheckinPoints();
    await ScoreEngine().weeklyCheckin('2026-11-23');
    expect(server.writes().map((w) => w.who).toSet(), {memberB});
    server.seen.clear();
    await signOut();
    await ScoreService().addCheckinPoints();
    expect(server.writes('daily_scores'), isEmpty);
    expect(reported, isEmpty);
  });
}
