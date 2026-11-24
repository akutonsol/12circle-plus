import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/observability/app_failure.dart';
import '../../auth/domain/auth_provider.dart';
import '../data/custom_exercise_service.dart';
import '../data/models/exercise_detail_model.dart';

final customExerciseSvcProvider = Provider<CustomExerciseService>((_) => CustomExerciseService());

/// Who is signed in, by id: a token refresh or a profile edit is the same
/// coach, so it neither re-reads the list nor drops the exercise being opened.
final _signedInUid = Provider<String?>(
    (ref) => ref.watch(currentUserProvider.select((u) => u?.id)));

// Id of the exercise to edit — set before navigating to the create/edit screen.
// P0-FL-57a · cleared when the signed-in coach changes: the next one's "create"
// opened as an edit of the last one's exercise.
final editingExerciseProvider = StateProvider<String?>((ref) {
  ref.watch(_signedInUid);
  return null;
});

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

  int _loadSeq = 0;

  /// P0-FL-57a · only the newest load, for the coach it was started for, is
  /// shown. A failed re-read keeps the list already shown, beside the error.
  Future<void> _load() async {
    final seq = ++_loadSeq;
    state = const AsyncValue<List<ExerciseDetail>>.loading().copyWithPrevious(state);
    try {
      final list = await _svc.getMyExercises();
      if (!mounted || seq != _loadSeq) return;
      state = AsyncValue.data(list);
    } catch (e, st) {
      reportError('MyExercisesNotifier.load', e, st);
      if (!mounted || seq != _loadSeq) return;
      state = AsyncValue<List<ExerciseDetail>>.error(e, st).copyWithPrevious(state);
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
    if (id != null && mounted) await _load();
    return id;
  }

  /// P0-FL-50a · true only when the server deleted the row. The exercise was
  /// dropped from the list whatever happened — a refused or 0-row delete made
  /// it vanish until the next reload. It now stays; [CustomExerciseService
  /// .lastError] holds why (already recorded).
  Future<bool> delete(String id) async {
    final ok = await _svc.deleteExercise(id);
    if (!ok || !mounted) return ok;
    final shown = state;
    if (shown.hasValue) {
      final kept = AsyncValue.data(
          shown.requireValue.where((e) => e.id != id).toList());
      // (whenData drops the list kept beside a failed re-read.)
      state = shown is AsyncError<List<ExerciseDetail>>
          ? AsyncValue<List<ExerciseDetail>>.error(shown.error, shown.stackTrace)
              .copyWithPrevious(kept)
          : kept;
    }
    // A load that started before the delete may still carry the row.
    if (shown.isLoading) await _load();
    return ok;
  }

  Future<bool> submitForGlobal(String id) async {
    final ok = await _svc.submitForGlobalLibrary(id);
    if (ok && mounted) await _load();
    return ok;
  }

  Future<void> refresh() => _load();
}

// P0-FL-57a · one notifier per signed-in coach: it was built once for the
// app's lifetime, so the next coach kept the last one's list. The old one is
// disposed on a switch, and whatever it still had in flight is dropped.
final myExercisesNotifierProvider =
    StateNotifierProvider<MyExercisesNotifier, AsyncValue<List<ExerciseDetail>>>(
  (ref) {
    ref.watch(_signedInUid);
    return MyExercisesNotifier(ref.read(customExerciseSvcProvider));
  },
);
