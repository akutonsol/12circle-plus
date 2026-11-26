import 'package:circle_fitness/features/workout/data/models/workout_log_model.dart';
import 'package:circle_fitness/features/workout/data/workout_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/two_member_postgrest.dart'
    show initTwoMemberSupabase, memberA, memberB, signInAs, signOut;
import '../support/workout_members_server.dart';

// P0-FL-59b · a [WorkoutService] bound to the member whose live workout it
// writes for (the Workout Zone's). Its own file because `owner:` is new: it does
// not compile on a82f993. The behaviour it replaces is proven there by
// workout_zone_belongs_to_its_member_test.dart.

void main() {
  late WorkoutMembersServer server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = WorkoutMembersServer();
    await initTwoMemberSupabase(server);
  });

  setUp(() async {
    server.reset();
    await signInAs(memberA);
  });

  Future<void> save(WorkoutService s) => s.saveSetLog(
      sessionId: 'session', exerciseName: 'Squat', exerciseInstanceId: 'i1', setId: 's1',
      setNumber: 1, reps: 8, weightKg: 60, completed: true);

  test("A's service saves nothing once B is signed in", () async {
    final s = WorkoutService(owner: memberA);
    await signInAs(memberB);
    await expectLater(save(s), throwsStateError);
    await expectLater(
        s.logWorkout(WorkoutLog(workoutId: 'w', workoutTitle: 'W')), throwsStateError);
    expect(server.writes(), isEmpty);
  });

  test("A's service saves nothing signed out, and does not call it saved", () async {
    final s = WorkoutService(owner: memberA);
    await signOut();
    await expectLater(save(s), throwsStateError);
    await expectLater(
        s.logWorkout(WorkoutLog(workoutId: 'w', workoutTitle: 'W')), throwsStateError);
    expect(server.writes(), isEmpty);
  });

  test('control: the member\'s own set and workout are saved', () async {
    final s = WorkoutService(owner: memberA);
    await save(s);
    await s.logWorkout(WorkoutLog(workoutId: 'w', workoutTitle: 'W'));
    expect(server.setLogs.single['user_id'], memberA);
    expect(server.writes(to: 'workout_logs').map((w) => w.who), [memberA]);
  });
}
