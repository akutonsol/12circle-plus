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

  Future<void> toggleComplete(String habitId) async {
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

    // Persist to Supabase (only if real DB habit)
    try {
      await _svc.logHabit(habitId, completed: newCompleted, value: newCompleted ? habit.targetValue.toDouble() : 0);
      // Update score
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
  }

  Future<void> updateValue(String habitId, int value) async {
    final habits = state.valueOrNull ?? [];
    final habit = habits.firstWhere((h) => h.id == habitId);
    final isCompleted = value >= habit.targetValue;
    state = AsyncValue.data(habits.map((h) {
      if (h.id != habitId) return h;
      return h.copyWith(currentValue: value, isCompletedToday: isCompleted);
    }).toList());
    try {
      await _svc.logHabit(habitId, value: value.toDouble(), completed: isCompleted);
    } catch (_) {}
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
