import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/domain/auth_provider.dart';
import '../data/custom_exercise_service.dart';
import '../data/models/exercise_detail_model.dart';

final customExerciseSvcProvider = Provider<CustomExerciseService>((_) => CustomExerciseService());

// Id of the exercise to edit — set before navigating to the create/edit screen.
final editingExerciseProvider = StateProvider<String?>((ref) => null);

// Coach's own exercises
final myExercisesProvider = FutureProvider<List<ExerciseDetail>>((ref) async {
  ref.watch(currentUserProvider);
  return ref.read(customExerciseSvcProvider).getMyExercises();
});

// Global approved exercises from the platform library
final globalApprovedExercisesProvider = FutureProvider<List<ExerciseDetail>>((ref) async {
  return ref.read(customExerciseSvcProvider).getGlobalApprovedExercises();
});

/// Re-reads the two lists the Exercise Database shows. They do not dispose and
/// nothing else re-reads them: a coach who saved, edited or submitted an
/// exercise went "Back to Library" to a list without it.
void refreshExerciseLists(void Function(ProviderOrFamily) invalidate) {
  invalidate(myExercisesProvider);
  invalidate(globalApprovedExercisesProvider);
}

// Notifier for create/update/delete operations
class MyExercisesNotifier extends StateNotifier<AsyncValue<List<ExerciseDetail>>> {
  final CustomExerciseService _svc;
  MyExercisesNotifier(this._svc) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    try {
      final list = await _svc.getMyExercises();
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<String?> create({required Map<String, dynamic> fields}) async {
    final id = await _svc.createExercise(
      name: fields['name'] as String,
      category: fields['category'] as String,
      muscleGroup: fields['muscle_group'] as String,
      secondaryMuscles: List<String>.from(fields['secondary_muscles'] as List? ?? []),
      equipment: fields['equipment'] as String,
      difficulty: fields['difficulty'] as String,
      description: fields['description'] as String? ?? '',
      instructions: List<String>.from(fields['instructions'] as List? ?? []),
      coachingCues: List<String>.from(fields['coaching_cues'] as List? ?? []),
      commonMistakes: List<String>.from(fields['common_mistakes'] as List? ?? []),
      alternatives: List<String>.from(fields['alternatives'] as List? ?? []),
      beginnerModification: fields['beginner_modification'] as String?,
      advancedProgression: fields['advanced_progression'] as String?,
      tags: List<String>.from(fields['tags'] as List? ?? []),
      videoVariants: List.from(fields['video_variants'] as List? ?? []),
      imageUrl: fields['image_url'] as String?,
      visibility: fields['visibility'] as String? ?? 'private',
      extra: fields['extra'] as Map<String, dynamic>?,
    );
    if (id != null) await _load();
    return id;
  }

  Future<void> delete(String id) async {
    await _svc.deleteExercise(id);
    state = state.whenData((list) => list.where((e) => e.id != id).toList());
  }

  Future<bool> submitForGlobal(String id) async {
    final ok = await _svc.submitForGlobalLibrary(id);
    if (ok) await _load();
    return ok;
  }

  Future<void> refresh() => _load();
}

final myExercisesNotifierProvider =
    StateNotifierProvider<MyExercisesNotifier, AsyncValue<List<ExerciseDetail>>>(
  (ref) => MyExercisesNotifier(ref.read(customExerciseSvcProvider)),
);
