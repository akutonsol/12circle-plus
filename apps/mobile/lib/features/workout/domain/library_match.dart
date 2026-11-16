import '../../exercise_database/data/exercise_database_service.dart';
import '../../exercise_database/data/models/exercise_detail_model.dart';

/// The app's built-in library entry for a prescribed movement, by name.
///
/// A program row (`program_workouts.exercises`) names its movements in free
/// text and carries no library id, description or instructions, so a workout
/// built from it showed no form or steps even for a movement the library
/// covers -- the Exercise Library screen shows clients "Push-Up" with its
/// instructions while the assigned workout's "Push Up" showed nothing.
///
/// The match is EXACT after normalising case, spaces and punctuation
/// ("Push Up" = "Push-Up" = "push-up"). Nothing looser: "Bench Press" does not
/// become "Barbell Bench Press", because a near match could show the form of a
/// different movement. No match is the honest answer, and is null.
String normalizeExerciseName(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

final Map<String, ExerciseDetail> _bundledByName = {
  for (final e in ExerciseDatabaseService().getAllExercises())
    normalizeExerciseName(e.name): e,
};

ExerciseDetail? bundledLibraryEntry(String name) {
  final key = normalizeExerciseName(name);
  return key.isEmpty ? null : _bundledByName[key];
}
