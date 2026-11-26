import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/domain/auth_provider.dart';
import '../data/exercise_database_service.dart';
import '../data/models/exercise_detail_model.dart';

final exerciseDatabaseServiceProvider = Provider<ExerciseDatabaseService>(
  (ref) => ExerciseDatabaseService(),
);

final allExercisesProvider = Provider<List<ExerciseDetail>>((ref) {
  return ref.watch(exerciseDatabaseServiceProvider).getAllExercises();
});

final selectedCategoryProvider = StateProvider<String>((ref) => 'All');
final selectedMuscleGroupProvider = StateProvider<String>((ref) => 'All');
final selectedEquipmentProvider = StateProvider<String>((ref) => 'All');
final exerciseDbSearchProvider = StateProvider<String>((ref) => '');

/// P0-FL-59d (A-26) · the exercise being looked at goes with the account that
/// opened it: it may be a coach's private one. By uid only — a token refresh
/// or a profile edit is the same account and keeps it.
final selectedExerciseDetailProvider = StateProvider<ExerciseDetail?>((ref) {
  ref.watch(currentUserProvider.select((u) => u?.id));
  return null;
});

final filteredExerciseDbProvider = Provider<List<ExerciseDetail>>((ref) {
  final service = ref.watch(exerciseDatabaseServiceProvider);
  final exercises = ref.watch(allExercisesProvider);
  final category = ref.watch(selectedCategoryProvider);
  final muscleGroup = ref.watch(selectedMuscleGroupProvider);
  final equipment = ref.watch(selectedEquipmentProvider);
  final search = ref.watch(exerciseDbSearchProvider);

  return service.filterExercises(
    exercises: exercises,
    category: category,
    muscleGroup: muscleGroup,
    equipment: equipment,
    search: search,
  );
});
