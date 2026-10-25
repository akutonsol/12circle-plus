import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/workout/data/workout_snapshot.dart';

/// The client's side of "Generate week 1": does the app read what the engine
/// writes?
///
/// The fixture is NOT hand-built. It is a program_workouts row exactly as
/// migration 186 stored it on a local replay (2026-10-25, after the canonical-
/// prescription trigger ran), captured with row_to_json. The client reads
/// assigned days through getMyAssignedProgram() -> programWorkoutToWorkout()
/// (workout_provider.dart assignedWorkoutsProvider) and picks today's by
/// week_number + full English day name (getTodaysWorkout).
const _engineRow = r'''{"id":"ee420e68-774d-4809-baf0-982ed4178346","program_id":"c0000000-0000-0000-0000-0000000000a1","week_number":1,"day_of_week":"Monday","title":"Week 1 · Push","description":null,"estimated_minutes":45,"exercises":[{"rpe": null, "name": "Seated Cable Row", "reps": 10, "sets": 3, "notes": null, "tempo": null, "position": 0, "weight_kg": null, "exercise_id": "a80b1a11-9df7-4471-8736-9bd0777bd2c0", "rest_seconds": null, "duration_seconds": null, "movement_pattern": "horizontal_pull", "exercise_instance_id": "14e3bd5f-bdcc-4612-ad2d-cd126eb8002b"}, {"rpe": null, "name": "Shoulder Press", "reps": 10, "sets": 3, "notes": null, "tempo": null, "position": 1, "weight_kg": null, "exercise_id": "5b92e23e-bbe8-456c-ac53-b435a435bd1a", "rest_seconds": null, "duration_seconds": null, "movement_pattern": "vertical_push", "exercise_instance_id": "347c4196-12fc-48f8-8976-72ad99b999f9"}, {"rpe": null, "name": "Face Pull", "reps": 10, "sets": 3, "notes": null, "tempo": null, "position": 2, "weight_kg": null, "exercise_id": "8fdaf084-7c76-4c19-8bf4-1ab21e735932", "rest_seconds": null, "duration_seconds": null, "movement_pattern": "rear_delt", "exercise_instance_id": "356d4126-4c0e-4668-804f-8f6321d6f97d"}, {"rpe": null, "name": "Farmers Carry", "reps": 10, "sets": 3, "notes": null, "tempo": null, "position": 3, "weight_kg": null, "exercise_id": "8412a49d-2cb6-481c-9d0f-85d32e6453de", "rest_seconds": null, "duration_seconds": null, "movement_pattern": "carry", "exercise_instance_id": "a5981205-7fbd-4a6c-9921-0102c4920bdb"}, {"rpe": null, "name": "Incline Barbell Bench Press", "reps": 10, "sets": 3, "notes": null, "tempo": null, "position": 4, "weight_kg": null, "exercise_id": "b7a2fd89-79f0-4fd5-aacd-fd643519491e", "rest_seconds": null, "duration_seconds": null, "movement_pattern": "Horizontal Push", "exercise_instance_id": "3bab9ada-10bb-4c7d-a137-96acc0045c8e"}],"sort_order":0}''';

void main() {
  final row = Map<String, dynamic>.from(jsonDecode(_engineRow) as Map);

  test('the row is a real engine day (premise)', () {
    expect(row['title'], startsWith('Week 1 · '));
    expect((row['exercises'] as List), hasLength(5));
  });

  test('the client decodes every exercise with no contract deviation', () {
    final d = decodeProgramWorkout(row);
    expect(d.deviations, isEmpty,
        reason: 'the engine must write the canonical contract, not a dialect the codec translates');
    expect(d.workout.exercises, hasLength(5));
  });

  test('each exercise shows the prescribed 3 x 10 and NO invented load', () {
    final w = programWorkoutToWorkout(row);
    for (final e in w.exercises) {
      expect(e.exercise.name, isNotEmpty);
      expect(e.sets, hasLength(3));
      for (final s in e.sets) {
        expect(s.reps, 10);
        expect(s.weightKg, isNull,
            reason: 'null load is "none prescribed"; 0.0 would tell the client to lift nothing');
      }
    }
  });

  test("today's-workout matching can find it: week 1 and a full English day name", () {
    expect(row['week_number'], 1);
    expect(const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'],
        contains(row['day_of_week']));
  });
}
