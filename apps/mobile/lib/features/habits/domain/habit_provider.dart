import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../../../core/observability/app_failure.dart';
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
  ref.watch(currentUserProvider.select((u) => u?.id));
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

  // No habits is no habits. This returned `getDefaultHabits()` — eight sample
  // habits with invented streaks (7, 4, 12…), "Supplements" already done today
  // and ids '1'–'8' that are not rows — so a client with none was shown a week
  // of progress they never made, the Habits screen's "No habits yet" state could
  // never appear, and reminders were scheduled for habits that do not exist.
  if (raw.isEmpty) return const [];

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

/// The habit to log is not in this member's list (deactivated meanwhile, say):
/// trying again cannot help, looking at the list again can (P0-FL-59e).
class HabitNotListed implements Exception {
  const HabitNotListed();
  @override
  String toString() => "habit log: not one of this member's habits";
}

// ── Notifier that persists to Supabase ────────────────────────────────────────
class LiveHabitNotifier extends StateNotifier<AsyncValue<List<Habit>>> {
  final CoachProgramService _svc;
  final ScoreService _score;

  LiveHabitNotifier(this._svc, this._score) : super(const AsyncValue.loading()) {
    _load();
  }

  /// P0-FL-59e · whose habits these are: the member signed in when this was
  /// made (a new one is made for each member).
  final String? _owner = _signedIn;

  static String? get _signedIn =>
      Supabase.instance.client.auth.currentUser?.id;

  /// False (recorded) once someone else is signed in: the habits here are not
  /// theirs, so neither is a log, nor points counted from them. Nothing of
  /// them stays up either. A refusal answers `true` to the caller: it is
  /// another member's tick, and there is nothing to tell the one signed in.
  bool _isOwner(String what) {
    if (_signedIn == _owner) return true;
    reportError('LiveHabitNotifier.identity',
        StateError('$what: the signed-in account changed'));
    if (mounted) state = const AsyncValue.loading();
    return false;
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    // These reads ask as whoever is signed in. Not this list's member any
    // more, the answer is not for it (its replacement loads its own).
    if (_signedIn != _owner) return;
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
        // None assigned or added: the screen says so (see liveHabitsProvider).
        habits = const [];
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
      if (!mounted || _signedIn != _owner) return;
      state = AsyncValue.data(habits);
      // Schedule device notifications for all habits that have a reminder time
      HabitReminderService().scheduleHabitReminders(habits);
    } catch (e, st) {
      if (mounted) state = AsyncValue.error(e, st);
    }
  }

  Future<void> reload() => _load();

  final _failures = <String, Object>{};

  /// Why [habitId]'s last write was not saved, for the next step said to the
  /// member (the connection only when it IS the connection).
  Object? failureOf(String habitId) => _failures[habitId];

  /// The habit to log, or null (recorded) when this member has no such habit:
  /// another member's card that is still up, or one deactivated meanwhile.
  Habit? _mine(String habitId) {
    for (final h in state.valueOrNull ?? const <Habit>[]) {
      if (h.id == habitId) return h;
    }
    const error = HabitNotListed();
    reportError('LiveHabitNotifier.unknownHabit', error);
    _failures[habitId] = error;
    return null;
  }

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
    if (!_isOwner('habit log')) return true; // nothing was sent, or is said
    final habit = _mine(habitId);
    if (habit == null) return false; // nothing was sent
    final habits = state.valueOrNull ?? [];
    final newCompleted = !habit.isCompletedToday;

    // Optimistic update
    final ticked = habits.map((h) {
      if (h.id != habitId) return h;
      return h.copyWith(
        isCompletedToday: newCompleted,
        currentValue: newCompleted ? h.targetValue : 0);
    }).toList();
    state = AsyncValue.data(ticked);

    try {
      await _svc.logHabit(habitId, completed: newCompleted, value: newCompleted ? habit.targetValue.toDouble() : 0);
    } catch (e, st) {
      reportError('LiveHabitNotifier.toggleComplete', e, st);
      _failures[habitId] = e;
      // Not the signed-in member's tick: nothing to say to them about it.
      if (!_isOwner('habit log')) return true;
      _restore(habit);
      return false;
    }
    // Saved. Scoring is best-effort and never undoes a saved tick.
    // P0-FL-59e · counted from THIS member's habits, so for this member only:
    // `addHabitPoints` SETS the day's habits_points, and after a switch it set
    // the next member's from these counts.
    if (!_isOwner('habit points')) return true;
    try {
      // Replaced meanwhile (`habits_assigned`): the list that was ticked.
      final updated = mounted ? state.valueOrNull ?? [] : ticked;
      final completed = updated.where((h) => h.isCompletedToday).length;
      await _score.addHabitPoints(completed, updated.length);
      // 12 Circle Score (each once-per-day via server dedup).
      if (newCompleted) {
        final engine = ScoreEngine(forUid: _owner);
        await engine.habitCompleted(habitId);
        if (habit.name.toLowerCase().contains('water')) await engine.waterGoalHit();
        if (updated.isNotEmpty && completed >= updated.length) await engine.allHabitsToday();
      }
    } catch (e, st) {
      reportError('LiveHabitNotifier.toggleComplete.points', e, st);
    }
    return true;
  }

  /// Sets a counted habit's value and says whether it was saved; a failed
  /// write puts the habit back (EC-12).
  Future<bool> updateValue(String habitId, int value) async {
    if (!_isOwner('habit log')) return true; // nothing was sent, or is said
    final habit = _mine(habitId);
    if (habit == null) return false; // nothing was sent
    final habits = state.valueOrNull ?? [];
    final isCompleted = value >= habit.targetValue;
    state = AsyncValue.data(habits.map((h) {
      if (h.id != habitId) return h;
      return h.copyWith(currentValue: value, isCompletedToday: isCompleted);
    }).toList());
    try {
      await _svc.logHabit(habitId, value: value.toDouble(), completed: isCompleted);
      return true;
    } catch (e, st) {
      reportError('LiveHabitNotifier.updateValue', e, st);
      _failures[habitId] = e;
      if (!_isOwner('habit log')) return true;
      _restore(habit);
      return false;
    }
  }

  void incrementValue(String habitId) {
    final habit = _mine(habitId);
    if (habit == null) return;
    updateValue(habitId, (habit.currentValue + 1).clamp(0, habit.targetValue * 3));
  }

  void decrementValue(String habitId) {
    final habit = _mine(habitId);
    if (habit == null) return;
    updateValue(habitId, (habit.currentValue - 1).clamp(0, habit.targetValue * 3));
  }
}

final liveHabitNotifierProvider = StateNotifierProvider<LiveHabitNotifier, AsyncValue<List<Habit>>>((ref) {
  // The habits of whoever is signed in now, not of whoever opened Habits first.
  // By the id alone: a token refresh does not throw away what is on screen.
  final uid = ref.watch(currentUserProvider.select((u) => u?.id));
  return LiveHabitNotifier(CoachProgramService(), ScoreService(forUid: uid));
});

// Backwards-compat shim for screens that watch habitNotifierProvider
final habitNotifierProvider = Provider<List<Habit>>((ref) {
  // Nothing known yet is nothing — never the sample habits' invented streaks.
  return ref.watch(liveHabitNotifierProvider).valueOrNull ?? const [];
});

final adherenceScoreProvider = Provider<double>((ref) {
  final habits = ref.watch(habitNotifierProvider);
  return ref.watch(habitServiceProvider).calculateAdherenceScore(habits);
});

final totalStreakProvider = Provider<int>((ref) {
  final habits = ref.watch(habitNotifierProvider);
  return ref.watch(habitServiceProvider).calculateTotalStreak(habits);
});
