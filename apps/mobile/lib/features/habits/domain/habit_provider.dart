import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/domain/auth_provider.dart';
import '../data/habit_service.dart';
import '../data/models/habit_model.dart';
import '../data/habit_reminder_service.dart';
import '../../coach/data/coach_program_service.dart';
import '../../coach/data/score_service.dart';
import '../../scoring/data/score_engine.dart';

final habitServiceProvider = Provider<HabitService>((ref) => HabitService());

// ── Live habits from Supabase (coach-assigned or default) ─────────────────────
final liveHabitsProvider = FutureProvider<List<Habit>>((ref) async {
  ref.watch(currentUserProvider);
  final svc = CoachProgramService();
  final results = await Future.wait([
    svc.getMyHabits(),
    svc.getTodayHabitLogs(),
    svc.getHabitStreaks(),
  ]);
  final raw     = results[0] as List<Map<String, dynamic>>;
  final logs    = results[1] as List<Map<String, dynamic>>;
  final streaks = results[2] as Map<String, int>;
  final logMap  = {for (final l in logs) l['habit_id'] as String: l};

  if (raw.isEmpty) {
    return HabitService().getDefaultHabits();
  }

  return raw.map((h) {
    final id = h['id'] as String;
    final log = logMap[id];
    final target = (h['target_value'] as num?)?.toDouble() ?? 1;
    final currentVal = (log?['value'] as num?)?.toDouble() ?? 0;
    final streak = streaks[id] ?? 0;
    return Habit(
      id: id,
      name: h['name'] as String,
      emoji: h['emoji'] as String? ?? '⭐',
      category: _parseCategory(h['category'] as String?),
      targetValue: target.toInt(),
      unit: h['unit'] as String? ?? 'times',
      currentStreak: streak,
      longestStreak: streak,
      completedDates: [],
      isCompletedToday: log?['completed'] == true,
      currentValue: currentVal.toInt(),
      reminderTime: h['reminder_time'] as String?,
    );
  }).toList();
});

HabitCategory _parseCategory(String? s) => switch (s) {
  'fitness' => HabitCategory.fitness,
  'nutrition' => HabitCategory.nutrition,
  'sleep' => HabitCategory.sleep,
  'mindfulness' => HabitCategory.mindfulness,
  'recovery' => HabitCategory.health,
  _ => HabitCategory.health,
};

// ── Notifier that persists to Supabase ────────────────────────────────────────
class LiveHabitNotifier extends StateNotifier<AsyncValue<List<Habit>>> {
  final CoachProgramService _svc;
  final ScoreService _score;

  LiveHabitNotifier(this._svc, this._score) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    try {
      final results = await Future.wait([
        _svc.getMyHabits(),
        _svc.getTodayHabitLogs(),
        _svc.getHabitStreaks(),
      ]);
      final raw     = results[0] as List<Map<String, dynamic>>;
      final logs    = results[1] as List<Map<String, dynamic>>;
      final streaks = results[2] as Map<String, int>;
      final logMap  = {for (final l in logs) l['habit_id'] as String: l};

      List<Habit> habits;
      if (raw.isEmpty) {
        habits = HabitService().getDefaultHabits();
      } else {
        habits = raw.map((h) {
          final id = h['id'] as String;
          final log = logMap[id];
          final target = (h['target_value'] as num?)?.toDouble() ?? 1;
          final currentVal = (log?['value'] as num?)?.toDouble() ?? 0;
          final streak = streaks[id] ?? 0;
          return Habit(
            id: id,
            name: h['name'] as String,
            emoji: h['emoji'] as String? ?? '⭐',
            category: _parseCategory(h['category'] as String?),
            targetValue: target.toInt(),
            unit: h['unit'] as String? ?? 'times',
            currentStreak: streak,
            longestStreak: streak,
            completedDates: [],
            isCompletedToday: log?['completed'] == true,
            currentValue: currentVal.toInt(),
            reminderTime: h['reminder_time'] as String?,
          );
        }).toList();
      }
      // Replaced mid-load (`habits_assigned`, or another account signing in):
      // the replaced one must not write its stale answer, or schedule reminders.
      if (!mounted) return;
      state = AsyncValue.data(habits);
      // Schedule device notifications for all habits that have a reminder time
      HabitReminderService().scheduleHabitReminders(habits);
    } catch (e, st) {
      if (mounted) state = AsyncValue.error(e, st);
    }
  }

  Future<void> reload() => _load();

  /// Puts back [original] — only that habit, so a toggle that failed does not
  /// undo another one that saved meanwhile.
  void _restore(Habit original) {
    if (!mounted) return;
    final now = state.valueOrNull;
    if (now == null) return;
    state = AsyncValue.data(
        [for (final h in now) h.id == original.id ? original : h]);
  }

  /// Ticks or unticks a habit and says whether it was saved (EC-12).
  ///
  /// The tick shows at once, as before. It ended `catch (_) {}`: a write that
  /// failed stayed ticked on screen with nothing said, the next load reverted
  /// it, and the score had already been awarded from the unsaved state. Now a
  /// failed write puts the habit back and returns false for the screen to say
  /// so, and points are awarded only for a tick that was saved.
  Future<bool> toggleComplete(String habitId) async {
    final habits = state.valueOrNull ?? [];
    final habit = habits.firstWhere((h) => h.id == habitId, orElse: () => habits.first);
    final newCompleted = !habit.isCompletedToday;

    // Optimistic update
    state = AsyncValue.data(habits.map((h) {
      if (h.id != habitId) return h;
      return h.copyWith(
        isCompletedToday: newCompleted,
        currentValue: newCompleted ? h.targetValue : 0);
    }).toList());

    try {
      await _svc.logHabit(habitId, completed: newCompleted, value: newCompleted ? habit.targetValue.toDouble() : 0);
    } catch (_) {
      _restore(habit);
      return false;
    }
    // Saved. Scoring is best-effort and never undoes a saved tick.
    try {
      final updated = state.valueOrNull ?? [];
      final completed = updated.where((h) => h.isCompletedToday).length;
      await _score.addHabitPoints(completed, updated.length);
      // 12 Circle Score (each once-per-day via server dedup).
      if (newCompleted) {
        final engine = ScoreEngine();
        await engine.habitCompleted(habitId);
        if (habit.name.toLowerCase().contains('water')) await engine.waterGoalHit();
        if (updated.isNotEmpty && completed >= updated.length) await engine.allHabitsToday();
      }
    } catch (_) {}
    return true;
  }

  /// Sets a counted habit's value and says whether it was saved; a failed
  /// write puts the habit back (EC-12).
  Future<bool> updateValue(String habitId, int value) async {
    final habits = state.valueOrNull ?? [];
    final habit = habits.firstWhere((h) => h.id == habitId);
    final isCompleted = value >= habit.targetValue;
    state = AsyncValue.data(habits.map((h) {
      if (h.id != habitId) return h;
      return h.copyWith(currentValue: value, isCompletedToday: isCompleted);
    }).toList());
    try {
      await _svc.logHabit(habitId, value: value.toDouble(), completed: isCompleted);
      return true;
    } catch (_) {
      _restore(habit);
      return false;
    }
  }

  void incrementValue(String habitId) {
    final habit = (state.valueOrNull ?? []).firstWhere((h) => h.id == habitId);
    updateValue(habitId, (habit.currentValue + 1).clamp(0, habit.targetValue * 3));
  }

  void decrementValue(String habitId) {
    final habit = (state.valueOrNull ?? []).firstWhere((h) => h.id == habitId);
    updateValue(habitId, (habit.currentValue - 1).clamp(0, habit.targetValue * 3));
  }
}

final liveHabitNotifierProvider = StateNotifierProvider<LiveHabitNotifier, AsyncValue<List<Habit>>>((ref) {
  // The habits of whoever is signed in now, not of whoever opened Habits first.
  ref.watch(currentUserProvider);
  return LiveHabitNotifier(CoachProgramService(), ScoreService());
});

// Backwards-compat shim for screens that watch habitNotifierProvider
final habitNotifierProvider = Provider<List<Habit>>((ref) {
  return ref.watch(liveHabitNotifierProvider).valueOrNull ?? HabitService().getDefaultHabits();
});

final adherenceScoreProvider = Provider<double>((ref) {
  final habits = ref.watch(habitNotifierProvider);
  return ref.watch(habitServiceProvider).calculateAdherenceScore(habits);
});

final totalStreakProvider = Provider<int>((ref) {
  final habits = ref.watch(habitNotifierProvider);
  return ref.watch(habitServiceProvider).calculateTotalStreak(habits);
});
