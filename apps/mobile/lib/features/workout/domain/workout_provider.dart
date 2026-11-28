import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../coach/data/coach_program_service.dart';
import '../../../core/observability/app_failure.dart';
import '../../../core/realtime/realtime.dart';
import '../data/program_schedule.dart';
import '../data/workout_service.dart';
import '../data/workout_session_store.dart';
import '../data/workout_snapshot.dart';
import 'workout_restoration.dart';
import 'workout_session_manager.dart';
import '../data/models/exercise_model.dart';
import '../data/models/workout_model.dart';
import '../../ai_coach/data/ai_coach_service.dart';
import '../../auth/domain/auth_provider.dart';

/// Today's coaching adjustment from the AI coach's daily insight — drives an
/// intensity/focus banner on the workout screen. null when there's no brief yet.
final coachAdjustmentProvider = FutureProvider.autoDispose<CoachAdjustment?>((ref) async {
  // The signed-in member's own brief: re-read when the account changes, and
  // carrying whose it is.
  ref.watch(restoringUserIdProvider);
  final uid = Supabase.instance.client.auth.currentUser?.id;
  final insight = await AICoachService().getTodayInsight();
  if (insight == null) return null;
  final data = (insight['data'] as Map?) ?? const {};
  return CoachAdjustment(
    title: insight['title']?.toString() ?? 'Today’s Coaching',
    body: insight['body']?.toString() ?? '',
    focus: data['focus']?.toString(),
    intensityDelta: (data['intensity_delta'] as num?)?.round() ?? 0,
    readFor: uid,
  );
});

class CoachAdjustment {
  final String title;
  final String body;
  final String? focus;
  final int intensityDelta; // % vs planned (-30..+10)
  /// The member whose brief this is. Shown to nobody else.
  final String? readFor;
  const CoachAdjustment({required this.title, required this.body, this.focus, required this.intensityDelta, this.readFor});
}

/// Per-workout session status: the most recent session's
/// {status: in_progress|completed, started_at, completed_at, logged_sets}. Lets
/// the program list show "In Progress · started [date] · N%" instead of "Start".
///
/// Keyed by **workout id**, with the title kept only as a fallback for sessions
/// written before migration 103 persisted the id. The title is not an identity:
/// verified live on QA, the generated program contains "Upper Body" twice and
/// "Lower Body" twice, so a title-keyed map made starting one day show *both*
/// as in progress. Look a workout up with [sessionStatusFor], which applies the
/// same precedence.
final programSessionStatusProvider =
    FutureProvider<Map<String, Map<String, dynamic>>>((ref) async {
  // QAX-SES-01: recompute for whoever is signed in now, not whoever was.
  ref.watch(currentUserProvider);
  ref.watch(tableTickerProvider('workout_sessions'));
  ref.watch(tableTickerProvider('workout_set_logs'));
  final db = Supabase.instance.client;
  final uid = db.auth.currentUser?.id;
  if (uid == null) return {};
  {
    final sessions = await db
        .from('workout_sessions')
        .select('id, workout_id, workout_title, status, started_at, completed_at')
        .eq('user_id', uid)
        .inFilter('status', ['in_progress', 'completed'])
        .order('started_at', ascending: false);
    // Newest first, so putIfAbsent keeps the most recent session per key.
    final byKey = <String, Map<String, dynamic>>{};
    for (final s in (sessions as List)) {
      // Whose status this is travels with it: see [sessionStatusFor].
      final row = {...Map<String, dynamic>.from(s as Map), 'user_id': uid};
      final id = row['workout_id']?.toString();
      if (id != null && id.isNotEmpty) {
        byKey.putIfAbsent(id, () => row);
      }
      // The title entry is a fallback only — it never displaces an id entry.
      final title = row['workout_title']?.toString();
      if (title != null && title.isNotEmpty) byKey.putIfAbsent(title, () => row);
    }
    for (final e in byKey.entries) {
      if (e.value['status'] == 'in_progress' && e.value['logged_sets'] == null) {
        final logs = await db
            .from('workout_set_logs')
            .select('id')
            .eq('session_id', e.value['id'])
            // Confirmed sets only (104): a set merely typed into is not done.
            .eq('completed', true);
        e.value['logged_sets'] = (logs as List).length;
      }
    }
    return byKey;
  }
});

/// The session status of [workout], by identity first.
///
/// The one lookup every surface uses, so no caller re-invents the precedence
/// and reintroduces the title-keyed reading.
///
/// Two clients of one coach program share workout ids, and the program and the
/// statuses are two reads: after an account change one can be B's while the
/// other is still A's. A status is only a status of its own member's workout.
Map<String, dynamic>? sessionStatusFor(
    Map<String, Map<String, dynamic>> statuses, Workout workout) {
  final status = _statusOf(statuses, workout);
  final whose = status?['user_id']?.toString();
  return whose == null || workout.isFor(whose) ? status : null;
}

Map<String, dynamic>? _statusOf(
    Map<String, Map<String, dynamic>> statuses, Workout workout) {
  if (workout.id.isNotEmpty) {
    final byId = statuses[workout.id];
    // An entry that names this workout's id is authoritative. An entry found
    // under the title is only trustworthy when it carries no id of its own —
    // otherwise it belongs to a different workout that happens to share a name.
    if (byId != null) return byId;
  }
  final byTitle = statuses[workout.title];
  final owner = byTitle?['workout_id']?.toString();
  if (byTitle == null) return null;
  if (owner == null || owner.isEmpty || owner == workout.id) return byTitle;
  return null;
}

final workoutServiceProvider = Provider<WorkoutService>((ref) => WorkoutService());

final workoutsProvider = Provider<List<Workout>>((ref) {
  return ref.watch(workoutServiceProvider).getSampleWorkouts();
});

final exercisesProvider = Provider<List<Exercise>>((ref) {
  return ref.watch(workoutServiceProvider).getSampleExercises();
});

/// The workout the member opened. Theirs alone: dropped when the account
/// changes, and only then — keyed by the uid, so a token refresh or a profile
/// edit cannot wipe a live workout (P0-FL-59b).
final selectedWorkoutProvider = StateProvider<Workout?>((ref) {
  ref.watch(restoringUserIdProvider);
  return null;
});

/// Active rest countdown as a wall-clock end time + its original duration (for
/// the progress ring). App-scoped so it survives navigating away and resumes at
/// the correct remaining time. Null = no rest running. Dropped when the account
/// changes: one member's rest must not sound over, or cost points to, another.
class RestTimerState {
  final DateTime end;
  final int total;
  const RestTimerState(this.end, this.total);
}

final restTimerProvider = StateProvider<RestTimerState?>((ref) {
  ref.watch(restoringUserIdProvider);
  return null;
});

/// The result of FIT-017's "Add 30 seconds": the rest that should now be
/// running, and the overtime seconds the caller must bank as idle time.
typedef ExtendedRest = ({RestTimerState next, int bankedOvertime});

/// FIT-017 · "Add 30 seconds", as a pure function.
///
/// It lives here rather than in `_ActiveWorkoutViewState` because the screen
/// touches `Supabase.instance`, `ScoreEngine` and a platform audio channel in
/// `initState`, which makes the arithmetic below untestable at the widget
/// layer. `plan_summary.dart` was extracted for the same reason.
///
/// TWO RULES ARE ENCODED HERE, AND BOTH ARE DELIBERATE.
///
/// **Extending adds to the end, not to now.** Tapping twice while the clock is
/// still running adds a minute. Restarting from `now` each time would silently
/// shorten a long rest that was nearly over.
///
/// **Overtime already accrued is banked, never erased.** Past zero, the siren
/// has been going and points have been draining. The seconds overrun are
/// returned for the caller to add to its idle total — exactly what dismissing
/// the rest does — and only then does a fresh [bonus] start from `now`.
/// Extending is "I need longer", not an undo for a drain that already
/// happened.
///
/// `total` grows with `end` so the progress ring keeps reading
/// remaining/total; leaving it alone would push the value past 1.0, where it
/// clamps and the bar appears frozen at full.
ExtendedRest extendRest(RestTimerState current, DateTime now, {int bonus = 30}) {
  final over = now.difference(current.end).inSeconds;
  if (over > 0) {
    return (
      next: RestTimerState(now.add(Duration(seconds: bonus)), bonus),
      bankedOvertime: over,
    );
  }
  return (
    next: RestTimerState(
        current.end.add(Duration(seconds: bonus)), current.total + bonus),
    bankedOvertime: 0,
  );
}

final exerciseSearchProvider = StateProvider<String>((ref) => '');

final filteredExercisesProvider = Provider<List<Exercise>>((ref) {
  final exercises = ref.watch(exercisesProvider);
  final search = ref.watch(exerciseSearchProvider).toLowerCase();
  if (search.isEmpty) return exercises;
  return exercises.where((e) =>
    e.name.toLowerCase().contains(search) ||
    e.muscleGroup.toLowerCase().contains(search) ||
    e.category.toLowerCase().contains(search)
  ).toList();
});

// ── Assigned program workouts from Supabase ───────────────────────────────────

/// The client's assigned program, decoded into startable workouts.
///
/// **Errors propagate.** This used to `catch (_) { return []; }`, which made a
/// failed read and a failed decode indistinguishable from "you have no
/// program" — so one coach-authored exercise with a `String` rep count silently
/// erased the client's entire program. An empty list now means exactly one
/// thing: there is no assigned program. Anything else is an error state with a
/// retry, per product bible §4.
///
/// A coach's program is dated from the assignment's `start_date`
/// (`program_schedule.dart`). Undated, none of its workouts was ever "today's",
/// so Home said "No session assigned for today" to every coached client.
///
/// A training day the client finished under this assignment is marked done, so
/// Home stops offering it. Completing a session invalidates this provider.
///
/// Each workout carries the member the program was read for
/// ([Workout.readFor]): a reload keeps the previous member's list on the cards
/// that read it, and none of them can say whose it is.
final assignedWorkoutsProvider = FutureProvider<List<Workout>>((ref) async {
  ref.watch(currentUserProvider);
  final db = Supabase.instance.client;
  // The same answer, in the same turn, as the read below takes.
  final uid = db.auth.currentUser?.id;
  final service = CoachProgramService();
  final program = await service.getMyAssignedProgram();
  if (program == null || uid == null) return [];
  // The second half of the read asks as whoever is signed in by then.
  requireWorkoutOwner(db, uid, 'reading the assigned program');
  final sessions = await service.getMyCompletedProgramSessions(program);
  return [
    for (final w in assignedProgramToWorkouts(program, sessions: sessions))
      w.asReadFor(uid),
  ];
});

/// Generate a one-off, library-grounded AI workout for today (personalized to
/// goal/equipment/injuries/recovery + the coach's focus & intensity) and return
/// it as a startable Workout. null on failure.
///
/// Throws on failure rather than returning null: "the generator could not be
/// reached" and "the generator declined" are different answers and the client
/// is owed the difference. A null return means the function answered with no
/// workout.
Future<Workout?> generateAiWorkout({int? minutes}) async {
  final res = await Supabase.instance.client.functions.invoke(
    'ai-generate-workout',
    body: {if (minutes != null) 'duration_minutes': minutes});
  if (res.status != 200) {
    throw StateError('Workout generator failed (HTTP ${res.status})');
  }
  final w = (res.data as Map?)?['workout'];
  if (w is! Map) return null;
  // A contract violation propagates: a generated workout the app cannot read is
  // a fault to show, not a workout to silently not offer.
  return programWorkoutToWorkout(Map<String, dynamic>.from(w));
}

// ── Workout session history ───────────────────────────────────────────────────
final workoutHistoryProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  ref.watch(currentUserProvider);
  return ref.watch(workoutServiceProvider).getWorkoutHistory();
});

// ── Active workout in-memory state ────────────────────────────────────────────

/// What the client has entered against each set of the running workout, keyed
/// by [WorkoutSet.id].
///
/// Keyed by identity, not by exercise-and-position. A set's entry is found by
/// asking for that set, so nothing depends on where the set sits in a list, on
/// the list being contiguously numbered, or on the order rows came back from
/// the database in. Each entry also carries its own `set_id`, `exercise_id` and
/// `set_number`, so a caller holding one set's state knows what it belongs to.
class ActiveWorkoutNotifier
    extends StateNotifier<Map<String, Map<String, dynamic>>> {
  ActiveWorkoutNotifier() : super({});

  /// Session these sets belong to. Entered sets are meaningless without it —
  /// keeping them together is what stops one workout's sets showing up under
  /// another.
  String? _sessionId;
  String? get sessionId => _sessionId;

  /// Sets entered while no session was bound — a slow or failed session start
  /// — by [WorkoutSet.id]. They are the workout's that binds next ([beginSession]).
  final Set<String> _held = {};

  /// Binds this state to [sessionId], clearing it when the session changes.
  ///
  /// Called on entering the Workout Zone. Re-entering the same session keeps
  /// whatever was already typed; switching to a different session starts empty
  /// rather than inheriting the previous workout's sets.
  ///
  /// A session that binds LATE — after the member confirmed sets while it was
  /// still being opened — keeps those sets when [heldFor] is the workout they
  /// were entered against (C14-62d-02): they are this session's, and each was
  /// already sent to it once. Clearing them showed confirmed sets as
  /// outstanding. Anything held that is not one of [heldFor]'s sets, and
  /// everything when [heldFor] is not given, is dropped as before.
  void beginSession(String sessionId, {Workout? heldFor}) {
    if (_sessionId == sessionId) return;
    final wasUnbound = _sessionId == null;
    _sessionId = sessionId;
    final ids = heldFor == null
        ? const <String>{}
        : {for (final e in heldFor.exercises) for (final s in e.sets) s.id};
    final kept = wasUnbound
        ? {
            for (final e in state.entries)
              if (_held.contains(e.key) && ids.contains(e.key)) e.key: e.value,
          }
        : const <String, Map<String, dynamic>>{};
    _held.clear();
    state = kept;
  }

  /// A completed set is a recorded result, so its numbers are frozen.
  ///
  /// Only these fields stay writable once `completed` is true — a note is
  /// commentary, not the result. Weight/reps/RPE change only through
  /// [applyCorrection], never through an ordinary field edit.
  static const _editableWhenCompleted = {'notes'};

  /// The recorded state of the set with this id, or an empty map if nothing is
  /// logged against it yet.
  Map<String, dynamic> setData(String setId) => state[setId] ?? const {};

  /// Whether this set has been completed — the single test every edit path
  /// asks before writing.
  bool isSetCompleted(String setId) => setData(setId)['completed'] == true;

  /// Every set logged against the exercise instance [exerciseInstanceId], in no
  /// particular order. Callers that need order read the workout's own sets and
  /// look each one up by id.
  ///
  /// Keyed by the *instance*, not by the library exercise: a workout may
  /// prescribe the same movement twice, and those are two instances whose sets
  /// must not pool together.
  Iterable<Map<String, dynamic>> setsForExercise(String exerciseInstanceId) =>
      state.values
          .where((s) => s['exercise_instance_id'] == exerciseInstanceId);

  /// How many sets the client has confirmed across the whole workout.
  int get completedSetCount =>
      state.values.where((s) => s['completed'] == true).length;

  /// Single-field edit, routed through [setSetData] so it obeys exactly the
  /// same rules — there is no cheaper way in.
  bool updateSet(WorkoutSet set, String field, dynamic value,
          {String? exerciseInstanceId}) =>
      setSetData(set, {field: value},
          exerciseInstanceId: exerciseInstanceId);

  /// Merge entered values (reps/weight/rpe/notes) into a set's in-memory state
  /// so the UI reflects them across rebuilds even if a row's State is recreated.
  ///
  /// This is the ordinary edit path, and it refuses to rewrite a completed
  /// set: everything outside [_editableWhenCompleted] is dropped. Enforcing it
  /// here rather than in the widget means no UI path — mis-tap, stale row
  /// state, or a debounced save arriving after completion — can alter a
  /// recorded result. Completion itself is never carried by a value edit.
  /// Returns true when anything was written.
  bool setSetData(WorkoutSet set, Map<String, dynamic> data,
      {String? exerciseInstanceId}) {
    final locked = isSetCompleted(set.id);
    final existing = setData(set.id);
    final incoming = <String, dynamic>{
      for (final e in data.entries)
        if (e.key != 'completed' &&
            (!locked || _editableWhenCompleted.contains(e.key)) &&
            existing[e.key] != e.value)
          e.key: e.value,
    };
    // Nothing new: an unchanged re-emit (a blur after a debounce already
    // saved, say) is not a write, so callers don't re-persist it either.
    if (incoming.isEmpty) return false;
    _write(set, incoming, exerciseInstanceId);
    return true;
  }

  /// Marks a set complete, recording [data] as its final values.
  ///
  /// Completion is one-way from the client: an already-completed set is left
  /// exactly as it was recorded (no toggle-off, no value rewrite), so resuming
  /// a workout can never undo or drift a finished set. Returns true when this
  /// call is what completed the set.
  bool completeSet(WorkoutSet set,
      [Map<String, dynamic> data = const {}, String? exerciseInstanceId]) {
    if (isSetCompleted(set.id)) return false;
    _write(set, {
      for (final e in data.entries)
        if (e.key != 'completed') e.key: e.value,
      'completed': true,
    }, exerciseInstanceId);
    return true;
  }

  /// Applies a deliberate correction to an already-completed set.
  ///
  /// The escape hatch behind the explicit "Edit Completed Set" action: it is
  /// the only way weight/reps/RPE on a completed set can change, it never
  /// touches completion (the set stays completed), and it refuses sets that
  /// were never completed — those go through [setSetData] like any other edit.
  /// Returns true when the correction was applied.
  bool applyCorrection(
    WorkoutSet set, {
    int? reps,
    double? weight,
    double? rpe,
    String? notes,
    bool clearRpe = false,
    bool clearNotes = false,
    String? exerciseInstanceId,
  }) {
    if (!isSetCompleted(set.id)) return false;
    _write(set, {
      if (reps != null) 'reps': reps,
      if (weight != null) 'weight': weight,
      if (rpe != null) 'rpe': rpe else if (clearRpe) 'rpe': null,
      if (notes != null) 'notes': notes else if (clearNotes) 'notes': null,
      // Restated, not toggled: a correction must not change completion state.
      'completed': true,
    }, exerciseInstanceId);
    return true;
  }

  /// Merges [data] into a set's entry. The one place set state is mutated, so
  /// every write goes past the rules above — and the one place identity is
  /// stamped, so an entry can always say which set and exercise it is.
  void _write(WorkoutSet set, Map<String, dynamic> data,
      String? exerciseInstanceId) {
    final existing = state[set.id];
    if (_sessionId == null) _held.add(set.id);
    state = {
      ...state,
      set.id: {
        ...?existing,
        ...data,
        'set_id': set.id,
        'set_number': set.setNumber,
        if (exerciseInstanceId != null)
          'exercise_instance_id': exerciseInstanceId
        else if (existing?['exercise_instance_id'] != null)
          'exercise_instance_id': existing!['exercise_instance_id'],
      },
    };
  }

  /// Pre-populate from saved set logs when resuming a session.
  ///
  /// Seating is [seatSetLogs]: a row is attached to the set whose id it
  /// recorded, so logging only set 3 resumes with set 3 completed and set 1
  /// untouched. Shared with the restore path, so the sets the screen shows and
  /// the position it resumes at are computed from the same arrangement.
  void restoreFromLogs(
      Workout workout, Map<String, List<Map<String, dynamic>>> logs) {
    restoreSeated(seatSetLogs(workout, logs));
  }

  /// Pre-populate from already-seated state, as [WorkoutSessionRestorer]
  /// produces it — the same result as [restoreFromLogs] without re-seating.
  void restoreSeated(Map<String, Map<String, dynamic>> seated) {
    state = {
      ...state,
      for (final e in seated.entries) e.key: {...?state[e.key], ...e.value},
    };
  }

  void reset() {
    _sessionId = null;
    _held.clear();
    state = {};
  }
}

/// The selected workout once it has been FILED (C14-62d-03), or null.
///
/// Android back dismisses the "workout complete" dialog without its Skip or
/// Done, so the filed workout stays selected and the Zone stays on it. Its
/// view, or a new one after leaving and coming back, must not file, award or
/// start it again: one workout, one `workout_logs` row, one award. Compared by
/// identity with [selectedWorkoutProvider]'s value, and dropped whenever the
/// selection changes (cleared by Skip/Done, or another workout picked) — a
/// workout picked again is a new workout. The member's alone, as the selection.
final filedWorkoutProvider = StateProvider<Workout?>((ref) {
  ref.watch(restoringUserIdProvider);
  ref.watch(selectedWorkoutProvider);
  return null;
});

final activeWorkoutProvider = StateNotifierProvider<ActiveWorkoutNotifier,
    Map<String, Map<String, dynamic>>>((ref) {
  // One member's sets are never another's: two clients on the same coach
  // program share set ids.
  ref.watch(restoringUserIdProvider);
  return ActiveWorkoutNotifier();
});

// ── Stat providers ────────────────────────────────────────────────────────────
final weeklyWorkoutCountProvider = FutureProvider<int>((ref) async {
  ref.watch(currentUserProvider);
  return ref.watch(workoutServiceProvider).getWeeklyWorkoutCount();
});

final currentStreakProvider = FutureProvider<int>((ref) async {
  ref.watch(currentUserProvider);
  return ref.watch(workoutServiceProvider).getCurrentStreak();
});

final totalWorkoutCountProvider = FutureProvider<int>((ref) async {
  ref.watch(currentUserProvider);
  return ref.watch(workoutServiceProvider).getTotalWorkoutCount();
});

/// The one active workout session, or null.
///
/// The single source of truth for "is there a workout to resume". It watches
/// the `workout_sessions` ticker so starting, abandoning or completing a
/// session refreshes every surface that shows a Resume card — previously this
/// cached its first result for the lifetime of the app, which is why the same
/// build could show different workouts at different moments.
final activeSessionProvider = FutureProvider<WorkoutSessionRecord?>((ref) async {
  // QAX-SES-01: recompute for whoever is signed in now, not whoever was.
  ref.watch(currentUserProvider);
  ref.watch(tableTickerProvider('workout_sessions'));
  final uid = Supabase.instance.client.auth.currentUser?.id;
  if (uid == null) return null;
  // Errors propagate. A failed lookup returned as `null` is indistinguishable
  // from "there is nothing to resume", and hiding the Resume affordance from a
  // client who is mid-workout is the exact failure the restoration work exists
  // to prevent. Surfaces here become an error state with a retry.
  return ref.watch(workoutSessionManagerProvider).activeSession(uid);
});

final workoutSessionStoreProvider = Provider<WorkoutSessionStore>(
  (ref) => SupabaseWorkoutSessionStore(),
);

final workoutSessionManagerProvider = Provider<WorkoutSessionManager>(
  (ref) => WorkoutSessionManager(ref.watch(workoutSessionStoreProvider)),
);

final workoutSessionRestorerProvider = Provider<WorkoutSessionRestorer>((ref) {
  final service = ref.watch(workoutServiceProvider);
  return WorkoutSessionRestorer(
    manager: ref.watch(workoutSessionManagerProvider),
    loadSetLogs: service.getSessionCompletedSets,
    // Sessions written before workout snapshots existed are matched against
    // the workouts the client can actually see.
    candidates: () async => [
      ...await ref.read(assignedWorkoutsProvider.future),
      ...ref.read(workoutsProvider),
    ],
  );
});

/// The signed-in user, as a provider so the restore path can be exercised
/// without a live Supabase client.
///
/// Derived from the auth stream, so signing out drops the restore cache rather
/// than leaving one client's session to be restored under the next. A token
/// refresh yields the same id and so changes nothing.
///
/// Also the key of the live workout itself ([selectedWorkoutProvider],
/// [activeWorkoutProvider], [restTimerProvider]).
final restoringUserIdProvider = Provider<String?>(
  (ref) => ref.watch(currentUserProvider.select((u) => u?.id)),
);

/// Hydration of the active workout session — the startup / browser-refresh path.
///
/// In-memory state (`selectedWorkoutProvider`, `activeWorkoutProvider`) does not
/// survive a reload, so this rebuilds it from the authoritative session row:
/// the workout as snapshotted, the sets as logged, and the position to resume
/// at. Surfaces read it as three distinct answers, which is what stops a
/// restoring app from claiming there is no workout:
///
///  * loading — still determining whether a session exists;
///  * data `null` — genuinely no active session;
///  * error — a session exists but could not be rebuilt; the row is untouched
///    and still resumable, so the client is offered a retry.
///
/// Invalidate to retry. Kept alive (not autoDispose) so leaving and returning
/// to the Workout Zone doesn't re-run a restore that already succeeded.
final activeWorkoutRestorationProvider =
    FutureProvider<RestoredWorkoutSession?>((ref) async {
  final uid = ref.watch(restoringUserIdProvider);
  if (uid == null) return null;

  final restored = await ref.read(workoutSessionRestorerProvider).restore(uid);
  if (restored == null) return null;

  // Through the container: this provider may already be outdated. A restore
  // that finishes after the account changed hydrates nothing — the state it
  // would write into is the next member's.
  final app = ref.container;
  if (app.read(restoringUserIdProvider) != uid) {
    reportError('activeWorkoutRestorationProvider',
        StateError('restoring a workout: the signed-in account changed'));
    return null;
  }

  // Hydrate the in-memory state the Workout Zone reads. Doing it here rather
  // than in a screen means every entry point — refresh, route change, a resume
  // tap — lands on the same rebuilt session.
  app.read(selectedWorkoutProvider.notifier).state = restored.workout;
  final active = app.read(activeWorkoutProvider.notifier);
  active.beginSession(restored.sessionId);
  active.restoreSeated(restored.setState);

  return restored;
});

/// The member signed in NOW, by the auth client itself.
///
/// For the moment of a tap, and for what follows an await: the providers hear
/// of a change through the auth stream, a turn later than the client. Where
/// [restoringUserIdProvider] is supplied without an auth stream (a test), it is
/// the answer.
String? signedInNow(WidgetRef ref) => ref.exists(authStateProvider)
    ? Supabase.instance.client.auth.currentUser?.id
    : ref.read(restoringUserIdProvider);

/// Whether the workout state held by a [ProviderContainer] is still the app's.
///
/// An in-flight finish outlives its screen on purpose, through the container —
/// and an account change may throw the container itself away. Read before the
/// first await, it says so without touching the container again.
class AppWorkoutState {
  bool _alive = true;
  bool get alive => _alive;
}

final appWorkoutStateProvider = Provider<AppWorkoutState>((ref) {
  final state = AppWorkoutState();
  ref.onDispose(() => state._alive = false);
  return state;
});

/// Rebuilds the workout an active session belongs to and makes it the selected
/// workout, so every "Resume" entry point lands in the Workout Zone bound to
/// the session's own workout instead of whatever was last left in memory.
///
/// Null when there is nothing to bind — including a [session] that is not the
/// signed-in member's, or an account that changed while the program was read.
Future<Workout?> bindSessionToSelectedWorkout(
  WidgetRef ref,
  WorkoutSessionRecord session,
) async {
  final uid = signedInNow(ref);
  if (session.userId != uid) {
    reportError('bindSessionToSelectedWorkout',
        StateError('resuming a workout: the signed-in account changed'));
    return null;
  }
  final manager = ref.read(workoutSessionManagerProvider);
  final assigned = await ref.read(assignedWorkoutsProvider.future);
  if (!ref.context.mounted) return null;
  if (signedInNow(ref) != uid) {
    reportError('bindSessionToSelectedWorkout',
        StateError('resuming a workout: the signed-in account changed'));
    return null;
  }
  final workout = manager.workoutForSession(
    session,
    candidates: [...assigned, ...ref.read(workoutsProvider)],
  );
  if (workout != null) {
    ref.read(selectedWorkoutProvider.notifier).state = workout;
  }
  return workout;
}

final personalRecordsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  ref.watch(currentUserProvider);
  return ref.watch(workoutServiceProvider).getPersonalRecords();
});

final totalVolumeProvider = FutureProvider<double>((ref) async {
  ref.watch(currentUserProvider);
  return ref.watch(workoutServiceProvider).getTotalVolumeLifted();
});

final completionRateProvider = FutureProvider<double>((ref) async {
  ref.watch(currentUserProvider);
  return ref.watch(workoutServiceProvider).getCompletionRate();
});

final programAdherenceProvider = FutureProvider<double>((ref) async {
  ref.watch(restoringUserIdProvider);
  return ref.watch(workoutServiceProvider).getProgramAdherence();
});

// ── Exercise progression (family: keyed by exercise name) ────────────────────
final exerciseProgressionProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, exerciseName) async {
  ref.watch(currentUserProvider);
  return ref.watch(workoutServiceProvider).getExerciseProgression(exerciseName);
});

final loggedExerciseNamesProvider = FutureProvider<List<String>>((ref) async {
  ref.watch(currentUserProvider);
  return ref.watch(workoutServiceProvider).getLoggedExerciseNames();
});

// ── Coach: client workout stats ───────────────────────────────────────────────
// The stats are keyed by the coach themselves. The two per-client reads are not
// — a client id does not say whose coach is asking — so they are re-read when
// the account changes.
final clientWorkoutStatsProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, coachId) async => WorkoutService().getClientWorkoutStats(coachId),
);

final clientPersonalRecordsProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, clientId) async {
    ref.watch(restoringUserIdProvider);
    return WorkoutService().getClientPersonalRecords(clientId);
  },
);

final clientRecentSessionsProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, clientId) async {
    ref.watch(restoringUserIdProvider);
    return WorkoutService().getClientRecentSessions(clientId);
  },
);
