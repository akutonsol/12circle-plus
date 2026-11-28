import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/workout_log_model.dart';
import '../data/models/workout_model.dart';
import '../data/models/exercise_model.dart';
import '../data/workout_service.dart';
import '../data/workout_session_store.dart';
import '../domain/load_format.dart' show memberPrefersMetricProvider;
import '../domain/workout_provider.dart';
import '../domain/workout_restoration.dart';
import '../domain/workout_session_manager.dart';
import 'widgets/set_tracker_row.dart';
import 'widgets/rest_timer_widget.dart';
import 'widgets/section_load_failure.dart' show couldntMessage;
import 'widgets/zone_action.dart';
import 'widgets/exercise_guide_sheet.dart';
import 'widgets/swap_substitutes_list.dart';
import '../../../core/observability/app_failure.dart';
import '../../exercise_database/data/custom_exercise_service.dart';
import '../../exercise_database/data/exercise_database_service.dart';
import '../../../core/utils/rest_alarm.dart';
import '../../coach/data/score_service.dart';
import '../../scoring/data/score_engine.dart';
import '../../scoring/domain/score_provider.dart';
import '../../coach/domain/coach_ecosystem_provider.dart'
    show myAssignedProgramProvider, todaysWorkoutProvider, todayScoreProvider, weekScoresProvider;
import '../domain/session_complete.dart';
import '../domain/workout_save.dart';

const _bg       = Color(0xFF030303);
const _card     = Color(0xFF0E0B16);
const _border   = Color(0xFF1A1020);
const _primary  = Color(0xFFDDB7FF);
const _brand    = Color(0xFFA855F7);
const _white    = Colors.white;
const _muted    = Color(0xFFCFC2D6);
const _tertiary = Color(0xFF6FFBBE);
const _error    = Color(0xFFFFB4AB);
const _amber    = Color(0xFFFFD580);

// ── Superset / Circuit group helper ──────────────────────────────────────────
class _ExGroup {
  final List<int> indices;
  final List<WorkoutExercise> items;
  const _ExGroup(this.indices, this.items);
  bool get isCircuit  => items.isNotEmpty && items.first.isCircuit;
  bool get isSuperset => !isCircuit && items.length > 1;
  String get supersetLabel => items.first.supersetGroup ?? 'A';
  int get circuitRounds => items.first.circuitRounds;
}

List<_ExGroup> _buildGroups(List<WorkoutExercise> exercises) {
  final groups = <_ExGroup>[];
  var i = 0;
  while (i < exercises.length) {
    final e = exercises[i];
    if (e.isCircuit && e.circuitGroup != null) {
      final idxs = [i];
      final items = [e];
      while (i + 1 < exercises.length &&
          exercises[i + 1].isCircuit &&
          exercises[i + 1].circuitGroup == e.circuitGroup) {
        i++;
        idxs.add(i);
        items.add(exercises[i]);
      }
      groups.add(_ExGroup(idxs, items));
    } else if (e.isSuperset && e.supersetGroup != null) {
      final idxs = [i];
      final items = [e];
      while (i + 1 < exercises.length &&
          exercises[i + 1].isSuperset &&
          exercises[i + 1].supersetGroup == e.supersetGroup) {
        i++;
        idxs.add(i);
        items.add(exercises[i]);
      }
      groups.add(_ExGroup(idxs, items));
    } else {
      groups.add(_ExGroup([i], [e]));
    }
    i++;
  }
  return groups;
}

/// Route entry for the Workout Zone.
///
/// Its only job is hydration. In-memory state does not survive a browser
/// refresh, so on a cold start there is no selected workout — and the screen
/// used to read that as "nothing to do" and offer Browse Workouts to a client
/// who was mid-session. The active session has to be rebuilt from storage
/// before that question can be answered, and until it is, this shows a
/// restoring state rather than an empty one.
///
/// Three distinct outcomes, never conflated:
///   * still restoring     → "Restoring your workout…"
///   * genuinely no session → the empty state
///   * a session that could not be rebuilt → a recovery state with a retry;
///     the session row is untouched, so nothing is discarded.
class ActiveWorkoutScreen extends ConsumerWidget {
  const ActiveWorkoutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // One view per member: when the account changes, the previous member's view
    // — its session id, clock, idle total and typed fields — goes with them.
    final uid = ref.watch(restoringUserIdProvider);
    // A workout already in memory (started, or resumed from a Resume card) is
    // authoritative — the database has nothing to add. Not one read for
    // somebody else, however it got there (A-10).
    final workout = ref.watch(selectedWorkoutProvider);
    // And one per workout (P0-FL-62d): a view that filed or ended its workout
    // is closed for good, so another workout selected under it gets a view —
    // and a session — of its own. An exercise swap keeps the workout's id.
    final view = _ActiveWorkoutView(key: ValueKey((uid, workout?.id)));
    if (workout != null && workout.isFor(uid)) return view;

    final restoration = ref.watch(activeWorkoutRestorationProvider);
    return restoration.when(
      loading: () => const _RestoringWorkoutView(),
      error: (_, __) => _RestoreFailedView(
        onRetry: () => ref.invalidate(activeWorkoutRestorationProvider)),
      // Restoring hydrates `selectedWorkoutProvider`, so a restored session
      // lands in the Zone on the very next build.
      //
      // A refresh keeps the value it is replacing, and that value may be the
      // previous member's: it says nothing about this one, and the view would
      // open with no workout in it.
      data: (restored) => restored == null
          ? const _NoActiveWorkoutView()
          : restored.session.userId == uid
              ? view
              : const _RestoringWorkoutView(),
    );
  }
}

/// The Workout Zone proper, entered only once a workout is resolved.
class _ActiveWorkoutView extends ConsumerStatefulWidget {
  const _ActiveWorkoutView({super.key});
  @override
  ConsumerState<_ActiveWorkoutView> createState() => _ActiveWorkoutViewState();
}

class _ActiveWorkoutViewState extends ConsumerState<_ActiveWorkoutView> {
  int _elapsedSeconds = 0;
  int _idleSeconds = 0; // accumulated rest-overrun (overtime) across the session
  int _overtimePenalties = 0; // recurring overtime deductions for the current rest
  /// FIT-002 · "Pause session". The session clock stops; see [_togglePause].
  bool _paused = false;
  Timer? _timer;
  bool _saving = false;
  /// The round each circuit is on, keyed by the circuit's first exercise
  /// index. It lived in a local inside the circuit's StatefulBuilder builder,
  /// which every rebuild -- including the +/- taps' own setState -- reset to 1,
  /// so the counter could never leave "Round 1".
  final Map<int, int> _circuitRound = {};

  /// EC-05 / N-07: an essential write did not land, so the workout is not
  /// filed and the screen must not say it is.
  bool _saveFailedCompleting = false;
  /// The log is already in `workout_logs`, so a retry of a failed completion
  /// must not insert it again: one workout, one row.
  bool _logFiled = false;
  /// The member this workout belongs to: the one the in-memory workout is keyed
  /// by when this view is created (P0-FL-59b). Every write below is theirs or
  /// is not sent.
  late final String? _owner;
  /// The workout this view is for (P0-FL-62d); the view is keyed by it.
  late final String? _workoutId;

  /// Whether this view's workout is still the one selected. Not once another
  /// is: this view is then being torn down in the middle of a frame, and a
  /// row's flush from its dispose would write into the next workout's state
  /// (and, with no session bound, open a session for the next workout).
  bool get _stillSelected => _app.read(selectedWorkoutProvider)?.id == _workoutId;
  late final _workoutService = WorkoutService(owner: _owner);
  StreamSubscription<AuthState>? _authEvents;
  final _scrollController = ScrollController();
  /// Resolved on USE, not in the field initializer.
  ///
  /// `WorkoutService` in this same feature already does this, deliberately —
  /// "constructing the service must not require an initialised Supabase
  /// instance". This State did the opposite, so merely CONSTRUCTING it threw
  /// outside a Supabase app, which is why EC-05's completion path had no
  /// widget test: the screen could not be pumped at all with a workout
  /// selected. Both uses are inside async handlers that already require a
  /// live client.
  SupabaseClient get _db => Supabase.instance.client;
  /// Resolved once in initState so dispose() can persist elapsed time without
  /// reaching for `ref` during teardown.
  late final WorkoutSessionManager _sessions;
  /// This view's container, resolved in initState (P0-FL-62d). A set row
  /// flushes its pending save from its own dispose, when this view is already
  /// deactivated and `ref` may not look its container up any more: that threw
  /// in the middle of tearing the tree down (End Workout, or an account
  /// generation thrown away), and left the rest of the old tree mounted.
  late final ProviderContainer _app;
  String? _sessionId;
  /// The session was completed or ended (P0-FL-62d). Nothing typed into the
  /// workout afterwards — a field's blur when the finish dialog takes focus, a
  /// row's flush as the screen goes — may open another session for it.
  bool _closed = false;
  /// The activation in flight, shared by every caller so a session is never
  /// opened twice concurrently. Null when none is running.
  Future<WorkoutSessionRecord?>? _activation;
  /// The session's start from initState. It opens the session with the workout
  /// as it was when it began, so a swap made meanwhile is saved after it.
  Future<void>? _starting;
  /// Snapshot saves, one at a time and in the order they were asked for: a
  /// save that overtook a slower one could store a swap whose failure the
  /// slower one then undid on screen.
  Future<Object?> _snapshotSaves = Future<Object?>.value();
  /// Whether the warm-up question has been settled for this mount — either
  /// asked, or found already answered for the session.
  bool _warmupSettled = false;
  /// Per-exercise anchors, so a restored session can scroll to the exercise it
  /// stopped at instead of opening at exercise 1.
  final Map<int, GlobalKey> _exerciseAnchors = {};
  int? _pendingScrollTo;
  int _scrollAttempts = 0;
  /// The set the client is on, by [WorkoutSet.id]. Mirrored onto the session so
  /// a refresh restores the position rather than re-deriving one.
  String _currentSetId = '';
  // Per-exercise (by name) RPE-tracking flag from the library metadata.
  final Map<String, bool> _showRpe = {};

  /// Whether the member who owns this workout is still the one signed in.
  ///
  /// Asked right before every write, award and penalty, and after every await
  /// that could outlive them — from the auth client itself, not the widget
  /// tree: a hidden web tab runs timers but no frames, so nothing has rebuilt.
  /// When they are not, the caller does nothing; that is recorded here.
  ///
  /// Once per view: a hidden tab's clock and rest keep asking for as long as it
  /// is hidden, and one change of account is one event.
  bool _isOwner(String what) {
    if (_db.auth.currentUser?.id == _owner) return true;
    if (!_changeRecorded) {
      _changeRecorded = true;
      reportError('ActiveWorkoutScreen',
          StateError('$what: the signed-in account changed'));
    }
    return false;
  }

  bool _changeRecorded = false;

  bool _showRpeFor(String name) => _showRpe[name] ?? true;

  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    _owner = ref.read(restoringUserIdProvider);
    _workoutId = ref.read(selectedWorkoutProvider)?.id;
    _sessions = ref.read(workoutSessionManagerProvider);
    _app = ProviderScope.containerOf(context, listen: false);
    // A workout already filed and still selected — its complete dialog was
    // dismissed with back, and the Zone left and re-entered (C14-62d-03) — is
    // closed from the start: no new session, no second filing or award.
    final selected = ref.read(selectedWorkoutProvider);
    _closed = selected != null && identical(ref.read(filedWorkoutProvider), selected);
    // Not a frame: a siren already sounding in a hidden tab stops when its
    // member leaves. Stream errors are the auth provider's to report.
    _authEvents = _db.auth.onAuthStateChange.listen((_) {
      if (_db.auth.currentUser?.id != _owner) stopRestSiren();
    }, onError: (Object _, StackTrace __) {});
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_paused) return;
      setState(() => _elapsedSeconds++);
      // A checkpoint every 30 s of training. Elapsed time was saved only on
      // pause, Leave For Now and dispose, so a browser refresh or an app kill
      // (neither runs dispose) restored the clock to 0: 40 minutes in, the
      // session resumed at 0:00 and the finished workout recorded only the
      // time after the refresh — duration, minutes and calories alike.
      if (_elapsedSeconds % 30 == 0) _saveElapsed();
    });
    // And whenever the app goes to the background, which is often the last
    // chance before the OS kills it.
    _lifecycle = AppLifecycleListener(
      onHide: () => _saveElapsed(),
      onPause: () => _saveElapsed(),
    );
    _starting = _startSession();
    _loadExerciseMeta();
    // The warm-up prompt is raised by _startSession once the session is known:
    // it is the session that has (or hasn't) been warmed up, not the screen.
  }

  /// Reads per-exercise tracking flags from the library so the set tracker can
  /// hide RPE for exercises that don't support it.
  Future<void> _loadExerciseMeta() async {
    final workout = ref.read(selectedWorkoutProvider);
    if (workout == null) return;
    final svc = CustomExerciseService();
    final names = {for (final e in workout.exercises) e.exercise.name};
    for (final name in names) {
      final meta = await svc.metaForName(name);
      _showRpe[name] = meta.rpe;
    }
    if (mounted) setState(() {});
  }

  /// Raises the warm-up prompt only when this session hasn't answered it.
  ///
  /// The acknowledgement lives on the session (migration 105), not on the
  /// screen, so a browser refresh — or leaving the Zone and coming back —
  /// restores the answer instead of asking a client who is already three sets
  /// in. A null [session] means session activation failed and there is nothing
  /// to record against; the prompt still shows, because repeating a safety step
  /// is better than skipping one.
  void _promptWarmupIfNeeded(WorkoutSessionRecord? session) {
    if (_warmupSettled || !mounted) return;
    _warmupSettled = true;
    if (session != null && session.warmupAcknowledged) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isOwner('asking about the warm-up')) {
        _showWarmupDialog(session?.id);
      }
    });
  }

  /// Records the client's answer against the session, so it survives a reload.
  Future<void> _acknowledgeWarmup(String? sessionId) async {
    if (sessionId == null || !_isOwner('recording the warm-up')) return;
    try {
      await _sessions.acknowledgeWarmup(sessionId);
    } catch (e, st) {
      // Not shown: the worst a lost answer costs is being asked again.
      reportError('ActiveWorkoutScreen.acknowledgeWarmup', e, st);
    }
    if (!mounted || !_isOwner('recording the warm-up')) return;
    ref.invalidate(activeSessionProvider);
    ref.invalidate(activeWorkoutRestorationProvider);
  }

  void _showWarmupDialog(String? sessionId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dctx) => _OwnersOnly(owner: _owner, child: Dialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [_brand.withValues(alpha: 0.3), _primary.withValues(alpha: 0.15)])),
              child: const Icon(Icons.local_fire_department_rounded, color: _amber, size: 38)),
            const SizedBox(height: 18),
            const Text('Welcome to the Workout Zone',
              textAlign: TextAlign.center,
              style: TextStyle(color: _white, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            const Text(
              'Before you load up — spend 5–10 minutes warming up. Get the blood '
              'flowing, mobilize your joints, and activate the muscles you\'re about '
              'to train. A good warm-up means stronger lifts and fewer injuries.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 14, height: 1.5)),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(dctx);
                  _acknowledgeWarmup(sessionId);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _brand, foregroundColor: _white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.check_circle_outline_rounded, size: 20),
                  SizedBox(width: 8),
                  Text('I\'m Warmed Up — Let\'s Go',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                ]))),
          ]),
        ),
      )),
    );
  }

  /// Activates the session for the selected workout.
  ///
  /// All session identity decisions live in [WorkoutSessionManager]: this
  /// either resumes the session already open for this workout, or opens a new
  /// one and abandons any previously open session. Either way exactly one
  /// session is in progress afterwards, and it is the one this screen writes
  /// sets to.
  Future<void> _startSession() async {
    final workout = ref.read(selectedWorkoutProvider);
    if (workout == null || _closed) return;
    final uid = _owner;
    if (uid == null || !_isOwner('starting a workout')) return;
    try {
      final before = await _sessions.activeSession(uid);
      if (!_isOwner('starting a workout')) return;
      final session = await _activate(uid, workout);
      if (session == null || !_isOwner('starting a workout')) return;

      final isResume = before != null && before.id == session.id;

      if (isResume) {
        if (mounted) setState(() => _elapsedSeconds = session.elapsedSeconds);
        await _restoreLoggedSets(session.id, workout);
        if (!_isOwner('resuming a workout')) return;
        // Land on the set they stopped at, not on exercise 1 / set 1.
        _resumeAtPosition(workout, session);
      } else {
        ScoreEngine().workoutStarted(workout.id); // +5
      }

      _promptWarmupIfNeeded(session);

      // Every Resume surface reads activeSessionProvider — refresh it now that
      // the active session has changed.
      if (mounted) ref.invalidate(activeSessionProvider);
    } catch (e, st) {
      reportError('ActiveWorkoutScreen._startSession', e, st);
      // Not this member's workout any more: nothing to tell them.
      if (_db.auth.currentUser?.id != _owner) return;
      // Activation failed, so the *previous* session is still the authoritative
      // one — the client is looking at this workout but the app is not running
      // it. Say so rather than failing silently: a silent failure here is what
      // left an older workout as the resume candidate while the Zone showed a
      // newer one.
      _toastSave(couldntMessage('start this workout', e));
      // Session state is unknown, so the warm-up can't be looked up — ask.
      _promptWarmupIfNeeded(null);
    }
  }

  /// Activates the session for [workout], with at most one activation in
  /// flight at a time.
  ///
  /// Both entry points can run concurrently — `_startSession` from initState
  /// and `_ensureSession` from the first set the client confirms — and each
  /// reads the open sessions before writing. Run in parallel they both see the
  /// old session, both abandon it, and both insert; the second insert then
  /// violates `workout_sessions_one_active_per_user` and the workout is left
  /// with no session of its own. Sharing one future makes the second caller
  /// await the first's answer instead of racing it.
  Future<WorkoutSessionRecord?> _activate(String uid, Workout workout) {
    return _activation ??= _sessions
        .startWorkout(userId: uid, workout: workout)
        .then((session) {
      // The sets this would bind are the next member's by now.
      requireWorkoutOwner(_db, uid, 'starting a workout');
      _sessionId = session.id;
      // Bind the in-memory set state to this session — switching workouts
      // clears it so the previous workout's sets can't leak into this one.
      // Sets of THIS workout confirmed while the session was opening stay:
      // they are this session's, already sent to it (C14-62d-02).
      ref
          .read(activeWorkoutProvider.notifier)
          .beginSession(session.id, heldFor: workout);
      return session;
    }).whenComplete(() => _activation = null);
  }

  /// Puts previously logged sets back into the in-memory state.
  ///
  /// A failed read is surfaced rather than swallowed: silently resuming with no
  /// sets shows recorded work as outstanding and invites the client to redo it.
  Future<void> _restoreLoggedSets(String sessionId, Workout workout) async {
    try {
      final logs = await _workoutService.getSessionCompletedSets(sessionId);
      if (mounted && logs.isNotEmpty && _isOwner('restoring logged sets')) {
        // Seated against this workout, so each row goes back on the set whose
        // id it recorded rather than onto whatever slot is next.
        ref.read(activeWorkoutProvider.notifier).restoreFromLogs(workout, logs);
      }
    } catch (e, st) {
      reportError('ActiveWorkoutScreen._restoreLoggedSets', e, st);
      _toastSave(couldntMessage('restore your logged sets', e));
    }
  }

  /// Scrolls a resumed workout to the set the client left off on.
  ///
  /// [resumePosition] answers by identity: the session's stored cursor when it
  /// still names an outstanding set, otherwise the first set with no completion
  /// recorded against its id. Either way the answer names a set, and the index
  /// is only used to decide how far to scroll.
  void _resumeAtPosition(Workout workout, WorkoutSessionRecord? session) {
    if (!mounted) return;
    final position = resumePosition(workout, ref.read(activeWorkoutProvider),
        cursorSetId: session?.currentSetId);
    if (position.isComplete) return;
    _currentSetId = position.setId;
    // Cards are rendered per group, so a resume inside a superset or circuit
    // scrolls to the group that holds the exercise.
    final anchor = _groupAnchorIndex(workout, position.exerciseIndex);
    if (anchor == 0) return; // already at the top of the list
    _pendingScrollTo = anchor;
    _scrollAttempts = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToPending());
  }

  /// The index the exercise's card is anchored under: its own, or the first
  /// index of the superset/circuit group it belongs to.
  int _groupAnchorIndex(Workout workout, int exerciseIndex) {
    for (final group in _buildGroups(workout.exercises)) {
      if (group.indices.contains(exerciseIndex)) return group.indices.first;
    }
    return exerciseIndex;
  }

  void _scrollToPending() {
    final index = _pendingScrollTo;
    if (index == null || !mounted) return;
    final ctx = _exerciseAnchors[index]?.currentContext;
    if (ctx == null) {
      // The list hasn't laid out yet. Try a couple more frames, then give up
      // rather than spin — an un-scrolled list is a far smaller problem than a
      // callback that never stops rescheduling.
      if (_scrollAttempts++ >= 5) {
        _pendingScrollTo = null;
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToPending());
      return;
    }
    _pendingScrollTo = null;
    Scrollable.ensureVisible(ctx,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      alignment: 0.05);
  }

  /// Records the set the client is working on against the session.
  ///
  /// Identity only — the id of the set and of its exercise — so the stored
  /// cursor stays meaningful if the workout is later reordered or re-snapshot.
  /// Written on the first interaction with a set and when one is completed;
  /// unchanged positions are not re-written.
  void _markCurrentSet(WorkoutExercise we, WorkoutSet set) {
    if (_currentSetId == set.id) return;
    _currentSetId = set.id;
    _saveCursor(we.instanceId, set.id);
  }

  /// Moves the cursor past a just-completed set — forward first, so a client
  /// who started at a later exercise isn't sent back to a set they left open on
  /// purpose. [advancePosition] always names a real set, so the stored cursor
  /// stays resolvable.
  void _advanceCurrentSet(WorkoutExercise we, WorkoutSet set) {
    final workout = ref.read(selectedWorkoutProvider);
    if (workout == null) {
      _markCurrentSet(we, set);
      return;
    }
    final next =
        advancePosition(workout, ref.read(activeWorkoutProvider), set.id);
    _currentSetId = next.setId;
    _saveCursor(next.exerciseId, next.setId);
  }

  Future<void> _saveCursor(String exerciseId, String setId) async {
    final sid = _sessionId;
    if (sid == null || setId.isEmpty) return;
    if (!_isOwner('saving the workout position')) return;
    try {
      await _sessions.saveCursor(
          sessionId: sid, exerciseId: exerciseId, setId: setId);
    } catch (e, st) {
      reportError('ActiveWorkoutScreen.saveCursor', e, st);
      // Not shown: a lost cursor write costs the client a scroll, not their data: the
      // restore falls back to the first outstanding set.
    }
  }

  /// Stable scroll anchor for an exercise, by its index in the workout.
  GlobalKey _anchorFor(int exerciseIndex) =>
      _exerciseAnchors.putIfAbsent(exerciseIndex, GlobalKey.new);

  /// Display unit from the user's preference ('lb' for imperial, 'kg' for metric).
  ///
  /// P0-FL-45b: through [memberPrefersMetricProvider] — a unit read for the
  /// member signed in now. This read the profile's `valueOrNull`, which after
  /// a sign-out/sign-in was the PREVIOUS member's row while the new member's
  /// read was in flight or had failed: B's typed set correction was converted
  /// with A's unit and stored off by ~2.2x. [build] watches the provider so
  /// the unit follows the member.
  String get _unit => ref.read(memberPrefersMetricProvider) ? 'kg' : 'lb';

  /// Returns the active session id, creating the session row on demand so set
  /// logs can't be silently dropped when the session insert was delayed/failed.
  ///
  /// For the member who owns this workout, whoever is signed in now.
  Future<String?> _ensureSession() async {
    if (_sessionId != null) return _sessionId;
    // Not `ref`: also reached from a set row's flush in its dispose.
    final workout = _app.read(selectedWorkoutProvider);
    final uid = _owner;
    if (workout == null || uid == null) return null;
    // Joins the activation already started in initState rather than opening a
    // competing one.
    final session = await _activate(uid, workout);
    if (session == null) return null;
    if (mounted) ref.invalidate(activeSessionProvider);
    return _sessionId;
  }

  /// Waits for the session still being opened, if there is one (P0-FL-62d).
  ///
  /// Finish and End close the session by its id. Pressed while it was still
  /// being opened, they found none and closed nothing — and the session opened
  /// a moment later stayed `in_progress`, the finished workout offered for
  /// resume, while a set confirmed meanwhile was still waiting on it. A failed
  /// opening is reported and said by whoever started it; here it only means
  /// there is no session to close, as before.
  ///
  /// The warm-up is not asked once they are pressed: the question would go up
  /// over the finish dialog, or over Home after End.
  ///
  /// False when [what]'s member is no longer the one signed in.
  Future<bool> _sessionOpened(String what) async {
    final opening = _activation;
    if (opening != null) {
      _warmupSettled = true;
      await opening.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    }
    return _isOwner(what);
  }

  /// Persists a set (ensuring a session exists). Fire-and-forget so callers
  /// don't await across a widget-tree mutation. saveSetLog upserts, so this is
  /// safe to call repeatedly (on edit and on complete). Surfaces errors so a
  /// failed save is visible instead of silently dropped.
  Future<void> _persistSet(String exerciseName, String exerciseInstanceId,
      String? libraryExerciseId, String setId, int setNumber,
      String? tempo, int reps, double weightKg, double? rpe, String? notes,
      bool completed) async {
    // The workout is filed or ended: an edit now is not part of it.
    if (_closed) return;
    if (!_isOwner('saving a set')) return;
    try {
      final sid = await _ensureSession();
      if (!_isOwner('saving a set')) return;
      if (sid == null) {
        // No session could be opened to hold it.
        _toastSave(couldntMessage('save that set', null));
        return;
      }
      await _workoutService.saveSetLog(
        sessionId: sid,
        exerciseName: exerciseName,
        exerciseInstanceId: exerciseInstanceId,
        libraryExerciseId: libraryExerciseId,
        setId: setId,
        setNumber: setNumber,
        reps: reps,
        weightKg: weightKg,
        rpe: rpe,
        notes: notes,
        tempo: tempo,
        completed: completed,
      );
    } catch (e, st) {
      reportError('ActiveWorkoutScreen._persistSet', e, st);
      _toastSave(couldntMessage('save that set', e));
    }
  }

  void _toastSave(String msg) {
    if (!mounted) return;
    // A failure of this member's is not said to the next one.
    if (_db.auth.currentUser?.id != _owner) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: _error));
  }

  /// Heuristic: does this exercise use only bodyweight (no external load)?
  bool _isBodyweight(WorkoutExercise we) {
    final eq = we.exercise.equipment.toLowerCase();
    if (eq.contains('bodyweight') || eq.contains('body weight') || eq == 'none') return true;
    final n = we.exercise.name.toLowerCase();
    const kw = ['plank', 'push-up', 'push up', 'pushup', 'pull-up', 'pull up',
      'pullup', 'chin-up', 'dip', 'glute bridge', 'sit-up', 'situp', 'crunch',
      'mountain climber', 'burpee', 'inverted row', 'pike', 'air squat',
      'hollow', 'superman', 'bird dog', 'wall sit', 'hanging', 'leg raise'];
    return kw.any(n.contains);
  }

  /// Dismisses the rest/overtime alarm (the user is starting the next set).
  /// Banks any overtime as idle time, then clears the timer (which stops the
  /// siren via the widget's dispose).
  ///
  /// [app] for a caller past an await, when `ref` may already be disposed.
  void _dismissRest([ProviderContainer? app]) {
    final rt = app != null ? app.read(restTimerProvider) : ref.read(restTimerProvider);
    if (rt == null) return;
    final over = DateTime.now().difference(rt.end).inSeconds;
    if (over > 0) _idleSeconds += over;
    (app != null ? app.read(restTimerProvider.notifier) : ref.read(restTimerProvider.notifier))
        .state = null;
  }

  /// FIT-017 · "Add 30 seconds". The arithmetic and its two rules live in
  /// `extendRest()` in the domain, where they are testable; this is the part
  /// that touches screen state.
  void _extendRest() {
    final rt = ref.read(restTimerProvider);
    if (rt == null) return;
    final result = extendRest(rt, DateTime.now());
    if (result.bankedOvertime > 0) {
      _idleSeconds += result.bankedOvertime;
      // A fresh rest gets a fresh overtime budget, the same way logging a set
      // does — the drain that already happened stays banked above.
      _overtimePenalties = 0;
    }
    ref.read(restTimerProvider.notifier).state = result.next;
  }

  /// Caches entered values into the in-memory workout state so the row's fields
  /// reflect them across rebuilds (and survive navigation within the session).
  ///
  /// The notifier is the gate: it drops weight/reps/RPE aimed at a completed
  /// set. Returns whether anything was actually written, so an edit it refused
  /// isn't persisted either.
  bool _cacheSet(WorkoutExercise we, WorkoutSet set, int reps, double weightKg,
      double? rpe, String? notes) {
    // Not `ref`: a row's flush calls this from its dispose ([_app]).
    return _app.read(activeWorkoutProvider.notifier).setSetData(set, {
      'reps': reps,
      'weight': weightKg,
      'rpe': rpe,
      'notes': notes,
    }, exerciseInstanceId: we.instanceId);
  }

  /// Writes a set to the database from the in-memory state rather than from
  /// the values a row reported.
  ///
  /// State is the authority on what a set holds — it has already rejected any
  /// edit to a completed set — so persisting from it means the recorded result
  /// is what reaches `workout_set_logs`, whatever a widget emitted.
  void _persistFromState(WorkoutExercise we, WorkoutSet set) {
    final data = _app.read(activeWorkoutProvider.notifier).setData(set.id);
    _persistSet(
      we.exercise.name,
      we.instanceId,
      we.exercise.id,
      set.id,
      set.setNumber,
      set.tempo,
      (data['reps'] as num?)?.toInt() ?? set.reps,
      // A set with no prescribed load logs 0 when the client entered nothing —
      // there is no other honest number — but the prescription itself stays
      // absent, so the field shows no target rather than "0".
      (data['weight'] as num?)?.toDouble() ?? set.weightKg ?? 0,
      (data['rpe'] as num?)?.toDouble(),
      data['notes'] as String?,
      data['completed'] == true,
    );
  }

  /// FIT-002 · "Pause session" — the screen's second declared control, absent
  /// until now. The session clock ran from the moment the Zone opened until the
  /// workout was finished, whatever the client was actually doing.
  ///
  /// **Pausing suspends the rest countdown too, and that is the point.** Rest
  /// is wall-clock: left running, a paused session would keep sliding into
  /// overtime, sound its siren and take 5 points every 20 seconds for time the
  /// client has explicitly said they are not training. Overtime already accrued
  /// is still banked — `_dismissRest` does that — so pausing is not a way to
  /// erase a drain that has already happened, only to stop a new one.
  ///
  /// Elapsed time is persisted on pause so a crash or a kill while paused
  /// resumes at the right number rather than at the last set that was logged.
  void _togglePause() {
    final next = !_paused;
    setState(() => _paused = next);
    if (!next) return;
    _dismissRest();
    _saveElapsed();
  }

  Future<void> _saveElapsed() async {
    final sid = _sessionId;
    if (sid == null || !_isOwner('saving the workout clock')) return;
    try {
      await _sessions.saveElapsed(sid, _elapsedSeconds);
    } catch (e, st) {
      // Not shown: the next checkpoint writes it again.
      reportError('ActiveWorkoutScreen.saveElapsed', e, st);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_authEvents?.cancel());
    _lifecycle?.dispose();
    _scrollController.dispose();
    _saveElapsed(); // persist elapsed time so resume can restore it
    super.dispose();
  }

  String get _elapsedTime {
    final m = _elapsedSeconds ~/ 60;
    final s = _elapsedSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _completeWorkout() async {
    if (!_isOwner('finishing a workout')) return;
    // Filed already (C14-62d-03): Finish pressed again on the Zone that back
    // left open. One workout is one `workout_logs` row and one award — nothing
    // is sent, and it is not celebrated twice.
    if (_closed) {
      reportError('ActiveWorkoutScreen._completeWorkout',
          StateError('finishing a workout: it was already filed'));
      return;
    }
    setState(() => _saving = true);
    // Everything after the awaits below goes through the app's container, not
    // `ref`: the screen can be left while the save is in flight, and `ref`
    // throws once it is disposed — which skipped the reset, every re-read and
    // clearing the selection, so the finished workout was started again.
    final app = _app;
    // Before the wait: binding a session that was still opening clears the sets
    // held in memory, and the set confirmed meanwhile is one of them.
    final entered = app.read(activeWorkoutProvider);
    if (!await _sessionOpened('finishing a workout')) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    final workout = app.read(selectedWorkoutProvider);
    if (workout == null) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    final appState = app.read(appWorkoutStateProvider);
    final isStillThis = _stillThisWorkout(app, workout);

    _dismissRest(app); // bank any in-progress overtime + silence the siren
    _timer?.cancel();

    final log = WorkoutLog(
      workoutId: workout.id,
      workoutTitle: workout.title,
      durationMinutes: _elapsedSeconds ~/ 60,
      caloriesBurned: (_elapsedSeconds ~/ 60 * 8),
      category: workout.category,
      notes: '',
    );

    // EC-05 / N-07. Every one of these was either unguarded — so a throw left
    // `_saving` true and the Complete button permanently dead — or swallowed
    // with `catch (_) {}`, so a failed `completeSession` still reset the sets
    // and raised the celebration over a session the server never marked
    // complete.
    var logWritten = false;
    try {
      if (!_logFiled) await _workoutService.logWorkout(log);
      logWritten = true;
      _logFiled = true;
    } catch (e, st) {
      reportError('ActiveWorkoutScreen.logWorkout', e, st);
    }

    // From here to the end, each step first asks whether the member who pressed
    // Finish is still here: what is left belongs to them — the session, the
    // points — and the in-memory workout is the next member's.
    bool ownerLeft() {
      if (_isOwner('finishing a workout')) return false;
      if (mounted) setState(() => _saving = false);
      return true;
    }

    if (ownerLeft()) return;

    bool? sessionCompleted;
    if (_sessionId != null) {
      sessionCompleted = false;
      try {
        await _sessions.completeSession(
              sessionId: _sessionId!,
              durationSeconds: _elapsedSeconds,
              idleSeconds: _idleSeconds,
              caloriesBurned: log.caloriesBurned ?? 0,
            );
        sessionCompleted = true;
      } catch (e, st) {
        reportError('ActiveWorkoutScreen.completeSession', e, st);
      }
    }
    if (ownerLeft()) return;

    // Derived, and recomputable: worth recording, not worth making someone
    // retry a finished workout for.
    var scored = false;
    // Only for a workout that was filed: a client who gives up on a failed save
    // must not keep the points for it. The retry awards them.
    if (logWritten && sessionCompleted != false) {
      try {
        await ScoreService().addWorkoutPoints();
        if (ownerLeft()) return;
        await ScoreEngine().workoutCompleted(workout.id);
        scored = true;
      } catch (e, st) {
        reportError('ActiveWorkoutScreen.workoutPoints', e, st);
      }
    }
    if (ownerLeft()) return;

    final outcome = workoutSaveOutcome(
      logWritten: logWritten,
      sessionCompleted: sessionCompleted,
      scored: scored,
    );

    if (!mayFinishWorkout(outcome)) {
      // Nothing is reset and nothing is invalidated: the local sets are the
      // only remaining copy of what the user did, and resetting them to show a
      // celebration would destroy it.
      if (mounted) {
        setState(() {
          _saveFailedCompleting = true;
          _saving = false;
        });
      }
      return;
    }
    if (mounted) setState(() => _saveFailedCompleting = false);
    // The account change threw this app's state away; there is none to clear.
    if (!appState.alive) return;
    // The member may have gone and come back while this was saving: the
    // workout in memory is then another one, with entries of its own. What was
    // finished is filed, and re-read below; nothing of theirs is cleared (N4).
    final still = isStillThis();
    // Captured before the reset below wipes it — FIT-018's stats come from
    // here, and reading them after would make every session read 0 sets.
    final completedSets = (still
            ? {...entered, ...app.read(activeWorkoutProvider)}
            : entered)
        .values
        .where((st) => st['completed'] == true)
        .toList(growable: false);
    if (still) app.read(activeWorkoutProvider.notifier).reset();
    // The session id is spent for logging purposes, but the feedback sheet
    // still has to name the session it is rating, so hand it the captured id.
    final finishedSessionId = _sessionId;
    _sessionId = null;
    _closed = true;
    // Filed for as long as it stays selected (C14-62d-03): a view of it opened
    // after back dismissed the dialog starts, files and awards nothing.
    if (still) {
      app.read(filedWorkoutProvider.notifier).state =
          app.read(selectedWorkoutProvider);
    }
    // The session is archived — stop offering it as resumable, and drop the
    // restored copy so a later cold start doesn't rebuild a finished workout.
    app.invalidate(activeSessionProvider);
    app.invalidate(activeWorkoutRestorationProvider);
    // Its training day is now done: re-read the program so Home and the
    // Workouts tab stop offering it.
    app.invalidate(assignedWorkoutsProvider);
    app.invalidate(todaysWorkoutProvider);
    app.invalidate(myAssignedProgramProvider);
    // Nothing else re-reads these, and none of them dispose: without this the
    // streak, totals and score stay as they were before the workout until the
    // app restarts.
    app.invalidate(totalWorkoutCountProvider);
    app.invalidate(weeklyWorkoutCountProvider);
    app.invalidate(currentStreakProvider);
    app.invalidate(workoutHistoryProvider);
    app.invalidate(completionRateProvider);
    app.invalidate(programAdherenceProvider);
    app.invalidate(personalRecordsProvider);
    app.invalidate(loggedExerciseNamesProvider);
    app.invalidate(exerciseProgressionProvider);
    app.invalidate(todayScoreProvider);
    app.invalidate(weekScoresProvider);
    app.invalidate(myScoreProvider);
    app.invalidate(recentScoreEventsProvider);
    app.invalidate(myBadgeIdsProvider);

    if (mounted) {
      // Now, not at the tap: the screen behind the dialog can be gone by then.
      final router = GoRouter.maybeOf(context);
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => _OwnersOnly(owner: _owner, child: WorkoutCompleteDialog(
          ownerId: _owner,
          title: workout.title,
          duration: _elapsedTime,
          calories: log.caloriesBurned ?? 0,
          idleSeconds: _idleSeconds,
          sessionId: finishedSessionId,
          // FIT-018's three figures, from what the client actually logged.
          // `completedSets` is captured BEFORE the notifier is reset above —
          // reading it after would report every finished session as zero sets
          // and zero volume.
          elapsedSeconds: _elapsedSeconds,
          setsLogged: completedSets.length,
          volumeKg: sessionVolumeKg([
            for (final st in completedSets)
              (
                reps: (st['reps'] as num?)?.toInt() ?? 0,
                weightKg: (st['weight'] as num?)?.toDouble(),
              ),
          ]),
          // Both exits — Skip and Submit — come through here. The dialog is on
          // the root navigator; this screen's own context reaches the shell's.
          onDone: () {
            Navigator.pop(dialogContext);
            _leaveFinishedWorkout(app, isStillThis);
            router?.go('/home');
          },
        )),
      );
    } else {
      // Finish Early → Skip can pop this screen before the dialog is raised.
      // Clearing here too means a completed workout is never left selected.
      _leaveFinishedWorkout(app, isStillThis);
    }
    // Guarded: _completeWorkout awaits four network round-trips, and Finish
    // Early → Skip pops this screen while they are still in flight. An
    // unguarded setState there throws "setState() called after dispose()".
    if (mounted) setState(() => _saving = false);
  }

  /// Whether the workout in memory is still [workout], running the session it
  /// runs now — asked after an await, before clearing anything (N4).
  ///
  /// The owner is not enough: they can leave and come back while a save is in
  /// flight, and what they have open by then is not what they finished. False
  /// once the account change threw the whole container away.
  bool Function() _stillThisWorkout(ProviderContainer app, Workout? workout) {
    final state = app.read(appWorkoutStateProvider);
    final sets = app.read(activeWorkoutProvider.notifier);
    // Null: a session not bound yet, or let go by "Leave For Now".
    final ours = {null, _sessionId, sets.sessionId};
    return () =>
        state.alive &&
        identical(app.read(activeWorkoutProvider.notifier), sets) &&
        (ours.contains(sets.sessionId) || sets.sessionId == _sessionId) &&
        app.read(selectedWorkoutProvider)?.id == workout?.id;
  }

  /// Drops the finished workout from the selection.
  ///
  /// A completed workout that stays selected is still a workout "in memory",
  /// and the Zone treats in-memory as authoritative — so re-entering it
  /// skipped restoration and called startWorkout on the finished workout,
  /// opening a fresh in-progress session for it. That resurrected session then
  /// became the newest one and took over the Resume card. Clearing the
  /// selection is what makes completion final.
  ///
  /// Through [app], not `ref`: this also runs after the screen is gone.
  void _leaveFinishedWorkout(ProviderContainer app, bool Function() isStillThis) {
    if (!_isOwner('closing a finished workout') || !isStillThis()) return;
    // What was typed after Finish (a blur as the dialog took focus) is no part
    // of any session: it must not be kept for the next one (C14-62d-02).
    app.read(activeWorkoutProvider.notifier).reset();
    app.read(selectedWorkoutProvider.notifier).state = null;
  }

  @override
  Widget build(BuildContext context) {
    final workout = ref.watch(selectedWorkoutProvider);
    final activeData = ref.watch(activeWorkoutProvider);
    // Rebuild when the member's confirmed unit changes ([_unit] reads it).
    ref.watch(memberPrefersMetricProvider);

    // Rest countdown is driven by a wall-clock end time in a provider, so it
    // survives navigating away and resumes at the right remaining time.
    final rest = ref.watch(restTimerProvider);

    // The shell only mounts this view with a workout resolved; if it is cleared
    // out from under us the shell takes over on the next build, so hold the
    // hydration state for the frame in between rather than flashing an empty one.
    if (workout == null) return const _RestoringWorkoutView();

    // Counted over the workout's own sets, by id: state left behind by an
    // exercise that has since been swapped out is not progress through the
    // workout the client is doing now.
    final completedSets = workout.exercises
        .expand((e) => e.sets)
        .where((s) => activeData[s.id]?['completed'] == true)
        .length;
    final totalSets = workout.exercises
        .fold(0, (sum, e) => sum + e.sets.length);
    final progress = totalSets > 0 ? completedSets / totalSets : 0.0;

    final groups = _buildGroups(workout.exercises);

    return Scaffold(
      backgroundColor: _bg,
      // Tapping empty space unfocuses the active field → its blur listener
      // persists the entered values (so "type and click away" saves on web).
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
        child: Stack(children: [
        Column(children: [
          // ── Top bar ──
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: const BoxDecoration(
              color: _card,
              border: Border(bottom: BorderSide(color: _border))),
            child: Row(children: [
              // FIT-002 names this control "End session". It was an unlabelled
              // 36 dp cross: a screen reader announced nothing (F-22 / A-G8)
              // and the target was under the 44 dp floor (F-6's class).
              ZoneAction(
                icon: Icons.close,
                label: 'End session',
                color: _error,
                onTap: () => _showEndDialog(context)),
              const SizedBox(width: 4),
              // FIT-002 · "Pause session". See _togglePause.
              ZoneAction(
                icon: _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                // "Pause session" is the design's own wording; "Resume" is the
                // wording already shipping on the resume banner. Neither is
                // invented here.
                label: _paused ? 'Resume' : 'Pause session',
                color: _paused ? _tertiary : _brand,
                onTap: _togglePause),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Workout Zone',
                    style: TextStyle(color: _white, fontSize: 15, fontWeight: FontWeight.w700)),
                  Text(workout.title,
                    style: TextStyle(color: _primary.withValues(alpha: 0.7), fontSize: 11)),
                ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: (_paused ? _muted : _brand).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: (_paused ? _muted : _brand).withValues(alpha: 0.3))),
                child: Row(children: [
                  Icon(_paused ? Icons.pause_rounded : Icons.timer_outlined,
                    color: _paused ? _muted : _brand, size: 14),
                  const SizedBox(width: 5),
                  Text(_elapsedTime,
                    style: TextStyle(
                      color: _paused ? _muted : _white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
                ])),
            ])),

          // ── Progress bar ──
          LinearProgressIndicator(
            value: progress,
            backgroundColor: _border,
            valueColor: const AlwaysStoppedAnimation<Color>(_brand),
            minHeight: 3),

          // ── Fixed rest banner (above the list so it never shifts content) ──
          // Keep the rest banner mounted through overtime (negative countdown +
          // siren + recurring penalty). Dismissed by starting the next set
          // (weight-field focus) or STOP — NOT by the clock reaching zero.
          if (rest != null)
            RestTimerWidget(
              key: ValueKey(rest.end),
              endTime: rest.end,
              totalSeconds: rest.total,
              onOvertime: () {
                // The widget has just started the siren; it is not this
                // member's rest.
                if (!_isOwner('charging a rest overrun')) return stopRestSiren();
                _overtimePenalties = 1;
                ScoreEngine().idleTimePenalty(); // -5 the moment rest runs over
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('−5 points — rest overrun. Start your next set to '
                        'stop the drain!'),
                    backgroundColor: _error));
                }
              },
              // Keep draining points every interval they stay in overtime, until
              // they start the next set — capped so a forgotten timer can't zero
              // the whole score.
              onOvertimePenaltyTick: () {
                if (_overtimePenalties >= 8) return;
                if (!_isOwner('charging a rest overrun')) return stopRestSiren();
                _overtimePenalties++;
                ScoreEngine().idleTimePenalty();
              },
              onExtend: _extendRest,
              onComplete: _dismissRest),

          // ── Exercise list ──
          Expanded(
            child: ListView(
              controller: _scrollController,
              key: const PageStorageKey('active_workout_list'),
              padding: const EdgeInsets.all(16),
              children: [
                // Progress summary
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _border)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _StatChip(label: 'Sets Done', value: '$completedSets/$totalSets', color: _brand),
                      Container(width: 1, height: 30, color: _border),
                      _StatChip(label: 'Exercises', value: '${workout.exercises.length}', color: _primary),
                      Container(width: 1, height: 30, color: _border),
                      _StatChip(label: 'Est. Kcal', value: '${(_elapsedSeconds ~/ 60 * 8)}', color: _tertiary),
                    ])),

                // ── Today's coach adjustment (applied as load guidance) ──
                ref.watch(coachAdjustmentProvider).maybeWhen(
                  data: (adj) => adj == null || adj.readFor != _owner
                      ? const SizedBox.shrink()
                      : _ActiveCoachBanner(adj: adj),
                  orElse: () => const SizedBox.shrink()),

                // ── Render groups (superset / circuit / solo) ──
                ...groups.map((group) {
                  final Widget card;
                  if (group.isCircuit) {
                    card = _buildCircuitGroup(group, activeData, workout);
                  } else if (group.isSuperset) {
                    card = _buildSupersetGroup(group, activeData, workout);
                  } else {
                    card = _buildExerciseCard(group.indices[0], group.items[0], activeData, workout);
                  }
                  // Anchored by the group's first exercise index, which is what
                  // the resume position names.
                  return KeyedSubtree(
                    key: _anchorFor(group.indices.first), child: card);
                }),

                const SizedBox(height: 80),
              ])),

          // ── Complete button ──
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: const BoxDecoration(
              color: _card,
              border: Border(top: BorderSide(color: _border))),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
            // EC-05 / N-07. Nothing said a word when the writes failed: the
            // sets were reset and the celebration went up regardless. Voice
            // and recovery match `_RestoreFailedView` and the feedback
            // sheet's `_saveFailed` row — this screen's existing failure
            // language — and the exception is NOT interpolated (F-2/F-16).
            if (_saveFailedCompleting) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  const Icon(Icons.cloud_off_rounded, color: _error, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(workoutSaveFailedMessage,
                        style: TextStyle(
                            color: _error.withValues(alpha: 0.9),
                            fontSize: 12,
                            height: 1.4)),
                  ),
                ]),
              ),
            ],
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _completeWorkout,
                style: ElevatedButton.styleFrom(
                  backgroundColor: completedSets == totalSets ? _brand : _brand.withValues(alpha: 0.6),
                  foregroundColor: _white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0),
                child: _saving
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(completedSets == totalSets ? Icons.check_circle : Icons.flag_outlined,
                        size: 18),
                      const SizedBox(width: 8),
                      Text(
                        _saveFailedCompleting
                          ? workoutSaveRetryLabel
                          : completedSets == totalSets ? 'Complete Workout' : 'Finish Early ($completedSets/$totalSets sets)',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                    ])))]))
        ]),
        ]),
        ),
      ),
    );
  }

  // ── Single exercise card ──────────────────────────────────────────────────
  Widget _buildExerciseCard(
    int index,
    WorkoutExercise we,
    Map<String, Map<String, dynamic>> activeData,
    Workout workout,
  ) {

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _exerciseHeader(index, we),
        if (we.notes != null && we.notes!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(we.notes!,
              style: TextStyle(color: _muted.withValues(alpha: 0.6), fontSize: 11, fontStyle: FontStyle.italic))),
        const SizedBox(height: 12),
        _columnHeaders(showRpe: _showRpeFor(we.exercise.name)),
        ..._buildSetRows(we, activeData),
        const SizedBox(height: 8),
      ]));
  }

  // ── Superset group ────────────────────────────────────────────────────────
  Widget _buildSupersetGroup(
    _ExGroup group,
    Map<String, Map<String, dynamic>> activeData,
    Workout workout,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _amber.withValues(alpha: 0.4))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Superset label
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _amber.withValues(alpha: 0.4))),
              child: Row(children: [
                const Icon(Icons.swap_vert_rounded, color: _amber, size: 13),
                const SizedBox(width: 4),
                Text('SUPERSET ${group.supersetLabel.toUpperCase()}',
                  style: const TextStyle(color: _amber, fontSize: 10,
                    fontWeight: FontWeight.w700, letterSpacing: 1)),
              ])),
            const Spacer(),
            Text('${group.items.length} exercises',
              style: TextStyle(color: _muted.withValues(alpha: 0.5), fontSize: 10)),
          ])),
        // Each exercise in the superset
        ...group.items.asMap().entries.map((e) {
          final i = e.key;
          final we = e.value;
      
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  const Icon(Icons.arrow_downward_rounded, color: _amber, size: 14),
                  const SizedBox(width: 6),
                  Text('Then:', style: TextStyle(color: _amber.withValues(alpha: 0.7), fontSize: 11)),
                ])),
            _exerciseHeader(group.indices[i], we),
            if (we.notes != null && we.notes!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(we.notes!,
                  style: TextStyle(color: _muted.withValues(alpha: 0.6), fontSize: 11, fontStyle: FontStyle.italic))),
            const SizedBox(height: 10),
            _columnHeaders(),
            ..._buildSetRows(we, activeData),
            if (i < group.items.length - 1)
              Divider(color: _amber.withValues(alpha: 0.15), thickness: 1,
                indent: 16, endIndent: 16),
          ]);
        }),
        const SizedBox(height: 8),
      ]));
  }

  // ── Circuit group ─────────────────────────────────────────────────────────
  Widget _buildCircuitGroup(
    _ExGroup group,
    Map<String, Map<String, dynamic>> activeData,
    Workout workout,
  ) {
    const circuitColor = Color(0xFFA855F7); // brand purple
    final roundKey = group.indices.first;
    final currentRound = _circuitRound[roundKey] ?? 1;
    return StatefulBuilder(builder: (ctx, setSB) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: circuitColor.withValues(alpha: 0.5))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Circuit header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: circuitColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: circuitColor.withValues(alpha: 0.4))),
                child: Row(children: [
                  const Icon(Icons.loop_rounded, color: circuitColor, size: 13),
                  const SizedBox(width: 4),
                  Text('CIRCUIT  •  ${group.circuitRounds} ROUNDS',
                    style: const TextStyle(color: circuitColor, fontSize: 10,
                      fontWeight: FontWeight.w700, letterSpacing: 1)),
                ])),
              const Spacer(),
              // Round counter
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: circuitColor.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(999)),
                child: Row(children: [
                  GestureDetector(
                    onTap: () { if (currentRound > 1) setState(() => _circuitRound[roundKey] = currentRound - 1); },
                    child: const Icon(Icons.remove_rounded, color: _muted, size: 16)),
                  const SizedBox(width: 6),
                  Text('Round $currentRound',
                    style: const TextStyle(color: _white, fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () { if (currentRound < group.circuitRounds) setState(() => _circuitRound[roundKey] = currentRound + 1); },
                    child: const Icon(Icons.add_rounded, color: circuitColor, size: 16)),
                ])),
            ])),
          // Exercises in circuit
          ...group.items.asMap().entries.map((e) {
            final i = e.key;
            final we = e.value;
        
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(children: [
                    const Icon(Icons.arrow_downward_rounded, color: circuitColor, size: 13),
                    const SizedBox(width: 4),
                    Text('Next:', style: TextStyle(color: circuitColor.withValues(alpha: 0.7), fontSize: 11)),
                  ])),
              _exerciseHeader(group.indices[i], we),
              if (we.notes != null && we.notes!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Text(we.notes!, style: TextStyle(color: _muted.withValues(alpha: 0.6), fontSize: 11, fontStyle: FontStyle.italic))),
              const SizedBox(height: 10),
              _columnHeaders(),
              ..._buildSetRows(we, activeData),
              if (i < group.items.length - 1)
                Divider(color: circuitColor.withValues(alpha: 0.12), thickness: 1, indent: 16, endIndent: 16),
            ]);
          }),
          const SizedBox(height: 8),
        ]));
    });
  }

  Widget _exerciseHeader(int index, WorkoutExercise we) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Row(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: _brand.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(color: _brand.withValues(alpha: 0.3))),
          child: Center(
            child: Text('${index + 1}',
              style: const TextStyle(color: _brand, fontWeight: FontWeight.w800, fontSize: 13)))),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: () => showExerciseGuide(context, we.exercise.name),
            child: Row(children: [
              Flexible(
                child: Text(we.exercise.name,
                  style: const TextStyle(color: _white, fontSize: 15, fontWeight: FontWeight.w700))),
              const SizedBox(width: 6),
              const _GuideIconPulse(),
            ]),
          )),
        GestureDetector(
          onTap: () => _showSwapSheet(index, we), // swap this exercise
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.swap_horizontal_circle_rounded, color: _primary.withValues(alpha: 0.8), size: 22))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: _brand.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(999)),
          child: Text(we.exercise.muscleGroup,
            style: TextStyle(color: _primary.withValues(alpha: 0.8), fontSize: 10, fontWeight: FontWeight.w600))),
      ]));
  }

  /// Correct swap recommendations from the built-in library — never a random
  /// cross-muscle grab. Prefers the exercise's own curated `alternatives`
  /// (the recommendations authored in the app); if the exercise isn't in the
  /// library, falls back to same-muscle-group matches. An empty/unknown muscle
  /// group returns nothing rather than "any exercise".
  List<Map<String, dynamic>> _librarySubstitutes(WorkoutExercise we) {
    final lib = ExerciseDatabaseService().getAllExercises();
    final selfName = we.exercise.name.trim().toLowerCase();

    // Index by lowercased name for detail lookups.
    final byName = {for (final e in lib) e.name.trim().toLowerCase(): e};
    final self = byName[selfName];

    Map<String, dynamic> row(dynamic e) => {
      'name': e.name, 'equipment': e.equipment, 'difficulty': e.difficulty,
      'muscle_group': e.muscleGroup, 'video_url': e.videoUrl,
    };

    // 1) Curated alternatives for this exercise — the recommended swaps.
    if (self != null && self.alternatives.isNotEmpty) {
      final out = <Map<String, dynamic>>[];
      for (final alt in self.alternatives) {
        final match = byName[alt.trim().toLowerCase()];
        out.add(match != null
            ? row(match)
            : {'name': alt, 'equipment': '', 'difficulty': '', 'muscle_group': self.muscleGroup});
      }
      if (out.isNotEmpty) return out;
    }

    // 2) Same-muscle-group fallback (resolve the group from the library by name).
    final mg = (self?.muscleGroup ?? we.exercise.muscleGroup).trim().toLowerCase();
    if (mg.isEmpty) return const [];
    final out = <Map<String, dynamic>>[];
    for (final e in lib) {
      if (e.muscleGroup.trim().toLowerCase() == mg &&
          e.name.trim().toLowerCase() != selfName) {
        out.add(row(e));
        if (out.length >= 12) break;
      }
    }
    return out;
  }

  /// Swap an exercise for a same-muscle substitute (keeps the set structure).
  Future<void> _showSwapSheet(int index, WorkoutExercise we) async {
    // Prefer the built-in library (reliable same-muscle matches); only if it has
    // nothing do we consult approved global custom exercises.
    // P0-FL-50a · the global read happens inside the sheet, so a failure is
    // said there ("Couldn't load substitutes" + retry), not shown as "none".
    final subs = _librarySubstitutes(we);
    showModalBottomSheet(
      context: context, backgroundColor: _card, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _OwnersOnly(owner: _owner, child: SafeArea(child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Swap “${we.exercise.name}”',
              style: const TextStyle(color: _white, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Same muscle group · keeps your sets',
              style: TextStyle(color: _muted.withValues(alpha: 0.7), fontSize: 12)),
            const SizedBox(height: 12),
            Flexible(child: SwapSubstitutesList(
              librarySubs: subs,
              loadGlobal: () => CustomExerciseService()
                  .getSubstitutes(we.exercise.name, we.exercise.muscleGroup),
              onPick: (s) { Navigator.pop(ctx); _swapExercise(index, we, s); },
              text: _white, muted: _muted, accent: _primary)),
          ]))))));
  }

  /// Replaces one exercise instance with a substitute movement.
  ///
  /// A swap is a **new instance**, not an edit of the old one. [WorkoutExercise
  /// .replacedBy] mints a fresh instance id and fresh set ids, so:
  ///
  ///  * the new movement's sets start empty rather than inheriting the replaced
  ///    exercise's completion state (which the immutability rule would then
  ///    lock, against values the client never entered for it);
  ///  * the first set logged against it inserts under its own identity instead
  ///    of colliding with the row already written for the replaced set
  ///    (`uq_workout_set_logs_set_identity`, 23505);
  ///  * the replaced exercise's own logs are untouched — the client did that
  ///    work and it stays attributed to the movement they actually performed.
  ///
  /// Load is deliberately not carried over: the prescribed weight belongs to the
  /// movement being replaced. What carries is the structure — sets, reps, rest,
  /// tempo — which is what "keeps your sets" means to a client.
  Future<void> _swapExercise(
      int index, WorkoutExercise we, Map<String, dynamic> sub) async {
    if (!_isOwner('swapping an exercise')) return;
    final workout = ref.read(selectedWorkoutProvider);
    if (workout == null || index < 0 || index >= workout.exercises.length) return;
    final newEx = Exercise(
      id: sub['id']?.toString() ?? 'sub_${DateTime.now().millisecondsSinceEpoch}',
      name: sub['name']?.toString() ?? we.exercise.name,
      category: we.exercise.category,
      muscleGroup: sub['muscle_group']?.toString() ?? we.exercise.muscleGroup,
      equipment: sub['equipment']?.toString() ?? we.exercise.equipment,
      difficulty: sub['difficulty']?.toString() ?? we.exercise.difficulty,
      description: '', instructions: const []);

    final updated = workout.replacingExerciseAt(
      index,
      we.replacedBy(newEx,
          instanceId: 'swap-${DateTime.now().microsecondsSinceEpoch}'),
    );
    ref.read(selectedWorkoutProvider.notifier).state = updated;

    // The cursor pointed into the exercise that is gone. Re-point it at the
    // replacement's first set so a refresh lands somewhere that exists.
    final replacement = updated.exercises[index];
    final cursorBefore = _currentSetId;
    final repointed = shouldRepointCursor(
        currentSetId: _currentSetId, replaced: we, replacement: replacement);
    if (repointed) {
      _currentSetId = replacement.sets.first.id;
      _saveCursor(replacement.instanceId, replacement.sets.first.id);
    }

    setState(() {});
    // The session's stored definition follows the swap, so a refresh restores
    // the workout the client is doing rather than the one they started. Awaited
    // and surfaced: a lost re-snapshot silently resurrects the replaced
    // exercise on the next reload, along with its set ids.
    final first = await _saveSelectedSnapshot('swapping an exercise');
    if (!mounted || !_isOwner('swapping an exercise')) return;
    var landed = first.saved;
    var undone = false;
    if (first.error != null) {
      // A save that failed is undone, unless a set has been logged on the new
      // movement meanwhile: that is work done, and taking its row off the
      // screen would lose sight of it.
      undone = _revertSwap(we, replacement);
      if (undone && repointed && replacement.setById(_currentSetId) != null) {
        _currentSetId = cursorBefore;
        _saveCursor(we.instanceId, cursorBefore);
      }
      // The failure does not say what is stored: another swap's save may have
      // carried this one, or the write landed and only its answer was lost.
      // Screen and session agree again only once what is on screen is saved.
      landed = (await _saveSelectedSnapshot('swapping an exercise')).saved;
      if (!mounted || !_isOwner('swapping an exercise')) return;
    }
    final ok = landed && !undone;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(switch ((landed, undone)) {
        (true, false) => 'Swapped to ${newEx.name}',
        (true, true) => couldntMessage('swap to ${newEx.name}', first.error),
        // Not known what a reload would bring back, so nothing is promised.
        (false, true) =>
          '${we.exercise.name} is back — but the change could not be saved.',
        (false, false) =>
          'Swapped to ${newEx.name} — but the change could not be saved.',
      }),
      backgroundColor: ok ? null : _error));
  }

  /// Puts [replaced] back where [replacement] is now — another swap may have
  /// been made since — and answers whether it did.
  bool _revertSwap(WorkoutExercise replaced, WorkoutExercise replacement) {
    final workout = ref.read(selectedWorkoutProvider);
    final at = workout?.exercises
            .indexWhere((e) => e.instanceId == replacement.instanceId) ??
        -1;
    if (workout == null || at < 0) return false;
    final sets = ref.read(activeWorkoutProvider);
    if (replacement.sets.any((s) => sets.containsKey(s.id))) return false;
    ref.read(selectedWorkoutProvider.notifier).state =
        workout.replacingExerciseAt(at, replaced);
    setState(() {});
    return true;
  }

  /// Re-stores the session's workout snapshot after a mid-session change, so
  /// restoration rebuilds the same exercises in the same order.
  ///
  /// Queued behind any save still running, and stores the workout selected
  /// when its turn comes, so the last save to land is what is on screen.
  /// Returns whether it reached the database, and the failure if it was
  /// refused or its answer lost. A session still opening was given the workout
  /// as it was when it began, so this waits for it and saves after it. With no
  /// session at all there is neither saved nor an error: the next session is
  /// opened with the workout as it is then.
  Future<({bool saved, Object? error})> _saveSelectedSnapshot(String what) {
    final turn = _snapshotSaves.then((_) => _saveSnapshotNow(what));
    _snapshotSaves = turn;
    return turn;
  }

  Future<({bool saved, Object? error})> _saveSnapshotNow(String what) async {
    const none = (saved: false, error: null);
    final opening = _activation ?? _starting;
    if (_sessionId == null && opening != null) {
      // Its failure is reported, and said, by whoever started it.
      await opening.then<void>((_) {}, onError: (Object _) {});
    }
    final sid = _sessionId;
    if (sid == null || !mounted) return none;
    // The workout selected now is the next member's by now.
    if (!_isOwner(what)) return none;
    final workout = ref.read(selectedWorkoutProvider);
    if (workout == null) return none;
    try {
      await _sessions.saveSnapshot(sid, workout);
    } catch (e, st) {
      reportError('ActiveWorkoutScreen.saveSnapshot', e, st);
      return (saved: false, error: e);
    }
    if (!_isOwner(what)) return none;
    if (_sessionId != sid) {
      // Stored on a session this screen no longer runs.
      reportError('ActiveWorkoutScreen.saveSnapshot',
          StateError('$what: the session changed while it saved'));
      return none;
    }
    return (saved: true, error: null);
  }

  Widget _columnHeaders({bool showRpe = true}) {
    final hStyle = TextStyle(color: _muted.withValues(alpha: 0.5), fontSize: 10,
      fontWeight: FontWeight.w600, letterSpacing: 1);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(children: [
        SizedBox(width: 36,
          child: Text('SET', style: hStyle)),
        Expanded(child: Text('WEIGHT (${_unit.toUpperCase()})', textAlign: TextAlign.center, style: hStyle)),
        const SizedBox(width: 8),
        Expanded(child: Text('REPS', textAlign: TextAlign.center, style: hStyle)),
        if (showRpe) ...[
          const SizedBox(width: 8),
          Expanded(child: Text('RPE', textAlign: TextAlign.center, style: hStyle)),
        ],
        const SizedBox(width: 74), // notes icon (28) + gap (6) + check (32) + gap (8)
      ]));
  }

  List<Widget> _buildSetRows(
    WorkoutExercise we,
    Map<String, Map<String, dynamic>> activeData,
  ) {
    return we.sets.map((set) {
      // By id, never by position: a row shows the state recorded against this
      // set, whatever order the sets are in and however many of them loaded.
      final setData = activeData[set.id] ?? const <String, dynamic>{};
      final isCompleted = setData['completed'] == true;

      return SetTrackerRow(
        // The set's own identity is the widget's identity too, so Flutter never
        // recycles one set's field state onto another.
        key: ValueKey(set.id),
        setNumber: set.setNumber,
        targetReps: set.reps,
        targetWeight: set.weightKg,
        completed: isCompleted,
        tempo: set.tempo,
        unit: _unit,
        // Restore previously-logged values so they reappear on return.
        savedWeightKg: (setData['weight'] as num?)?.toDouble(),
        savedReps: (setData['reps'] as num?)?.toInt(),
        savedRpe: (setData['rpe'] as num?)?.toDouble(),
        savedNotes: setData['notes'] as String?,
        isBodyweight: _isBodyweight(we),
        showRpe: _showRpeFor(we.exercise.name),
        onWeightFocus: _dismissRest,
        // Persist field edits (on blur / enter) even if the set isn't completed.
        // A completed set only gets here for its note; the notifier drops the
        // rest, and a refused edit isn't written to the database either.
        onChanged: (reps, weight, rpe, notes) {
          // Also reached from the row's dispose, which flushes a pending
          // debounce: by then the in-memory sets may be another member's, or
          // another workout's, or the workout already filed or ended.
          if (_closed || !_isOwner('saving a set') || !_stillSelected) return;
          _markCurrentSet(we, set);
          if (_cacheSet(we, set, reps, weight, rpe, notes)) {
            _persistFromState(we, set);
          }
        },
        onCompleted: (reps, weight, rpe, notes) {
          if (!_isOwner('completing a set')) return;
          // Completion is one-way: the notifier records the final values and
          // refuses an already-completed set, so this can't reopen or rewrite
          // one. Corrections go through onEditCompleted instead.
          final justCompleted = ref.read(activeWorkoutProvider.notifier).completeSet(
            set,
            {'reps': reps, 'weight': weight, 'rpe': rpe, 'notes': notes},
            we.instanceId);
          if (!justCompleted) return;
          _advanceCurrentSet(we, set);
          if (set.restSeconds != null) {
            // Unlock audio now (this is a user gesture) so the later beep/voice
            // aren't blocked, then start the wall-clock rest countdown.
            primeRestAudio();
            _overtimePenalties = 0; // fresh overtime budget for this rest
            ref.read(restTimerProvider.notifier).state = RestTimerState(
              DateTime.now().add(Duration(seconds: set.restSeconds!)),
              set.restSeconds!);
          }
          // Persist the values as recorded (fire-and-forget).
          _persistFromState(we, set);
        },
        onEditCompleted: isCompleted
            ? () => _editCompletedSet(we, set)
            : null);
    }).toList();
  }

  /// Deliberate correction of an already-completed set.
  ///
  /// Completed values are locked everywhere else, so this is the only path
  /// that can change them. It names the set as already recorded, needs an
  /// explicit confirmation, and leaves completion untouched — a correction
  /// fixes what was logged, it doesn't reopen the set.
  Future<void> _editCompletedSet(WorkoutExercise we, WorkoutSet set) async {
    final notifier = ref.read(activeWorkoutProvider.notifier);
    final data = notifier.setData(set.id);
    final showRpe = _showRpeFor(we.exercise.name);

    final weightKg = (data['weight'] as num?)?.toDouble() ?? 0;
    final weightCtl = TextEditingController(
        text: weightKg > 0 ? _fmtNum(_toDisplayWeight(weightKg)) : '');
    final repsCtl = TextEditingController(
        text: (data['reps'] as num?)?.toInt().toString() ?? '');
    final rpeCtl = TextEditingController(
        text: data['rpe'] != null ? _fmtNum((data['rpe'] as num).toDouble()) : '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dctx) => _OwnersOnly(owner: _owner, child: AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _tertiary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6)),
            child: const Text('COMPLETED',
              style: TextStyle(color: _tertiary, fontSize: 10,
                fontWeight: FontWeight.w800, letterSpacing: 1))),
          const SizedBox(height: 10),
          Text('Edit Set ${set.setNumber} · ${we.exercise.name}',
            style: const TextStyle(
              color: _white, fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            'This set is already recorded in your workout history. Correcting '
            'it updates the logged result — it stays completed either way.',
            style: TextStyle(color: _muted.withValues(alpha: 0.75), fontSize: 13, height: 1.4)),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: _correctionField(weightCtl, 'WEIGHT (${_unit.toUpperCase()})')),
            const SizedBox(width: 10),
            Expanded(child: _correctionField(repsCtl, 'REPS')),
            if (showRpe) ...[
              const SizedBox(width: 10),
              Expanded(child: _correctionField(rpeCtl, 'RPE')),
            ],
          ]),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Cancel', style: TextStyle(color: _muted))),
          TextButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Save Correction',
              style: TextStyle(color: _primary, fontWeight: FontWeight.w700))),
        ])));

    final newWeight = double.tryParse(weightCtl.text.trim());
    final newReps = int.tryParse(repsCtl.text.trim());
    final rpeText = rpeCtl.text.trim();
    weightCtl.dispose();
    repsCtl.dispose();
    rpeCtl.dispose();
    if (confirmed != true || !_isOwner('correcting a set')) return;

    final applied = notifier.applyCorrection(
      set,
      exerciseInstanceId: we.instanceId,
      reps: newReps,
      weight: newWeight != null ? _toKgWeight(newWeight) : null,
      rpe: showRpe ? double.tryParse(rpeText) : null,
      clearRpe: showRpe && rpeText.isEmpty,
    );
    if (!applied) return;
    _persistFromState(we, set);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Set ${set.setNumber} corrected')));
    }
  }

  Widget _correctionField(TextEditingController controller, String label) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
        style: TextStyle(color: _muted.withValues(alpha: 0.5), fontSize: 9,
          fontWeight: FontWeight.w600, letterSpacing: 0.8)),
      const SizedBox(height: 5),
      TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: const TextStyle(color: _white, fontSize: 15, fontWeight: FontWeight.w700),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          filled: true,
          fillColor: _bg,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none))),
    ]);
  }

  static const double _kgPerLb = 0.45359237;
  double _toDisplayWeight(double kg) => _unit == 'lb' ? kg / _kgPerLb : kg;
  double _toKgWeight(double display) => _unit == 'lb' ? display * _kgPerLb : display;

  /// Trims trailing zeros so a corrected 88.18 lb prefills cleanly.
  String _fmtNum(double v) {
    final r = (v * 10).round() / 10;
    return r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toStringAsFixed(1);
  }

  /// Leaving the Workout Zone — the two things that can mean, asked honestly.
  ///
  /// The previous dialog offered one action, labelled "End", and told the client
  /// "your progress won't be saved". Both were wrong. Every set is written to
  /// `workout_set_logs` as it is completed *and* as it is edited, so nothing was
  /// being discarded — and the action never touched the session row, so a
  /// workout the client had explicitly ended stayed `in_progress` for ever:
  /// still offered by the Resume banner, still holding the one active-session
  /// slot, and never counted as abandoned by `getCompletionRate()`.
  ///
  /// The two intents are genuinely different and both are supported by the
  /// session state machine that already exists (see
  /// `docs/WORKOUT_DOMAIN_CONTRACT.md` §7):
  ///
  ///  * **Leave for now** — the session stays `in_progress` with its cursor and
  ///    elapsed time, and Resume picks it up. This is what the old button
  ///    actually did.
  ///  * **End workout** — the session is `abandoned`. Set logs are kept (the
  ///    work was performed and counts toward history and volume); it stops being
  ///    resumable.
  void _showEndDialog(BuildContext context) {
    showDialog(
      context: context,
      // The dialog is on the root navigator; [context] reaches the shell's.
      builder: (dialogContext) => _OwnersOnly(owner: _owner, child: AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Leave this workout?',
          style: TextStyle(color: _white, fontWeight: FontWeight.w700)),
        content: Text(
          'Every set you\'ve logged is already saved.\n\n'
          'Leave for now and you can pick up where you left off. '
          'End the workout and it stops being resumable — your logged sets are '
          'kept either way.',
          style: TextStyle(color: _muted.withValues(alpha: 0.7))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Keep Going', style: TextStyle(color: _primary))),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _leaveForNow();
            },
            child: const Text('Leave For Now',
                style: TextStyle(color: _primary))),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _endWorkout();
            },
            child: const Text('End Workout', style: TextStyle(color: _error))),
        ])));
  }

  /// Steps away without closing the session: it stays `in_progress`, so the
  /// Resume banner offers it and the stored cursor puts the client back on the
  /// set they left.
  void _leaveForNow() {
    if (!_isOwner('leaving a workout')) return;
    // Leaving is not training, as pausing is not (FIT-002): stop the rest
    // countdown. `restTimerProvider` is app-wide, so a rest left running sounded
    // the overtime alarm on return, took 5 points and then 5 every 20 seconds,
    // and booked the whole absence as rest overrun.
    _dismissRest();
    final sid = _sessionId;
    if (sid != null) {
      // Fire-and-forget: the elapsed clock is a convenience, and losing it must
      // not stop the client leaving.
      unawaited(_sessions.saveElapsed(sid, _elapsedSeconds).catchError(
          (Object e, StackTrace st) =>
              reportError('ActiveWorkoutScreen.saveElapsed', e, st)));
    }
    ref.read(activeWorkoutProvider.notifier).reset();
    ref.invalidate(activeSessionProvider);
    ref.invalidate(activeWorkoutRestorationProvider);
    context.go('/home');
  }

  /// Ends the session for good.
  ///
  /// Awaited, and a failure is surfaced rather than swallowed: navigating away
  /// from a session the database still believes is `in_progress` is precisely
  /// the defect this replaces, so the client is told when it did not close and
  /// is left on the screen to try again.
  Future<void> _endWorkout() async {
    if (!_isOwner('ending a workout')) return;
    // Through the app's container after the awaits, as in _completeWorkout:
    // `ref` throws once the screen is gone, and the ended workout stayed
    // selected.
    final app = _app;
    if (!await _sessionOpened('ending a workout')) return;
    final sid = _sessionId;
    final appState = app.read(appWorkoutStateProvider);
    final isStillThis = _stillThisWorkout(app, app.read(selectedWorkoutProvider));
    // App-wide: the rest running now is this workout's, and stops with it.
    final rest = app.read(restTimerProvider);
    if (sid != null) {
      try {
        await _sessions.abandonSession(sid);
      } catch (e, st) {
        reportError('ActiveWorkoutScreen._endWorkout', e, st);
        if (!mounted || _db.auth.currentUser?.id != _owner) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(couldntMessage('end the workout', e)),
          backgroundColor: _error));
        return;
      }
    }
    // The in-memory workout below is the next member's by now — or another
    // one of this member's (N4).
    if (!_isOwner('ending a workout') || !appState.alive) return;
    _timer?.cancel();
    _sessionId = null;
    _closed = true;
    if (!isStillThis()) {
      // Another workout is open by now. Its own rest is kept; the ended
      // one's would sound, and charge, over it.
      if (rest != null && identical(app.read(restTimerProvider), rest)) {
        _dismissRest(app);
      }
      app.invalidate(activeSessionProvider);
      if (mounted) context.go('/home');
      return;
    }
    _dismissRest(app);
    app.read(activeWorkoutProvider.notifier).reset();
    // The workout must not stay selected: the Zone treats an in-memory
    // selection as authoritative, so re-entering would start a fresh session
    // for a workout the client just ended.
    app.read(selectedWorkoutProvider.notifier).state = null;
    app.invalidate(activeSessionProvider);
    app.invalidate(activeWorkoutRestorationProvider);
    if (mounted) context.go('/home');
  }
}

/// A dialog or sheet that belongs to [owner]: it closes when the account
/// changes. These are on the root navigator, so they outlive the Zone — and
/// they name the member's workout, loads and notes (P0-FL-59b).
class _OwnersOnly extends ConsumerWidget {
  final String? owner;
  final Widget child;
  const _OwnersOnly({required this.owner, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(restoringUserIdProvider) == owner) return child;
    final route = ModalRoute.of(context);
    final navigator = Navigator.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route == null || !route.isActive) return;
      route.isCurrent ? navigator.pop() : navigator.removeRoute(route);
    });
    return const SizedBox.shrink();
  }
}

// ── Hydration states ──────────────────────────────────────────────────────────

/// Shown while the app is still working out whether there is an active session.
///
/// Never "No workout selected": until the lookup answers, the app does not know
/// that there isn't one, and telling a mid-session client there is nothing to
/// resume is the wrong answer to give while still asking the question.
class _RestoringWorkoutView extends StatelessWidget {
  const _RestoringWorkoutView();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: _bg,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 34, height: 34,
            child: CircularProgressIndicator(color: _brand, strokeWidth: 3)),
          SizedBox(height: 20),
          Text('Restoring your workout…',
            style: TextStyle(color: _white, fontSize: 16, fontWeight: FontWeight.w700)),
          SizedBox(height: 6),
          Text('Picking up right where you left off',
            style: TextStyle(color: _muted, fontSize: 13)),
        ]),
      ),
    );
  }
}

/// An active session exists but could not be rebuilt.
///
/// Nothing is discarded to get here — the session row is untouched and still
/// in progress — so the recovery action is simply to try again.
class _RestoreFailedView extends StatelessWidget {
  final VoidCallback onRetry;
  const _RestoreFailedView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_rounded, color: _error, size: 44),
            const SizedBox(height: 18),
            const Text('We couldn\'t restore your workout.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _white, fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            const Text(
              'Your session is safe — we just couldn\'t load it right now. '
              'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 13, height: 1.5)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _brand, foregroundColor: _white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.refresh_rounded, size: 19),
                  SizedBox(width: 8),
                  Text('Try Again',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                ]))),
            TextButton(
              onPressed: () => context.go('/train'),
              child: const Text('Back to Train', style: TextStyle(color: _muted))),
          ]),
        ),
      ),
    );
  }
}

/// The genuine empty state: the lookup completed and there is no active session.
class _NoActiveWorkoutView extends StatelessWidget {
  const _NoActiveWorkoutView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.fitness_center, color: _primary, size: 48),
          const SizedBox(height: 16),
          const Text('No workout selected',
            style: TextStyle(color: _white, fontSize: 16)),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => context.go('/train'),
            child: const Text('Browse Workouts',
              style: TextStyle(color: _brand))),
        ]),
      ),
    );
  }
}

// ── Stat chip ─────────────────────────────────────────────────────────────────
class _StatChip extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StatChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(color: _muted.withValues(alpha: 0.5), fontSize: 10, fontWeight: FontWeight.w500)),
    ]);
  }
}

// ── Workout Complete Dialog ────────────────────────────────────────────────────
/// What actually happened when the client pressed Submit. Three outcomes, not
/// two — see [FeedbackDelivery].
enum FeedbackDelivery {
  /// Nothing was written. The form must stay up.
  failed,

  /// The feedback row is saved, but no coach was notified — either the client
  /// has no active coach, or the notification insert failed. Either way the
  /// notes are safe and the screen must not claim a delivery.
  saved,

  /// Saved, and the client's coach was notified.
  delivered,
}

/// The mapping from "what actually happened at the database" to "what the
/// client is told", separated from the I/O that produces it so it can be
/// tested. The three inputs fail independently and the interesting cases are
/// the mixed ones.
///
/// **A notification failure must not retract the save.** The client's notes
/// are in `workout_feedback`; telling them the submission failed would send
/// them to re-enter something that is already stored, and on a second success
/// the coach would see it twice. The coach loses a ping, which is recoverable;
/// the client is not lied to, which is the point.
FeedbackDelivery deliveryFor({
  required bool saved,
  required String? coachId,
  required bool notified,
}) {
  if (!saved) return FeedbackDelivery.failed;
  if (coachId == null) return FeedbackDelivery.saved;
  return notified ? FeedbackDelivery.delivered : FeedbackDelivery.saved;
}

/// Visible for testing. The dialog is where F-23 lived — a failed insert
/// produced the words "Feedback sent to your coach!" — so the three outcomes
/// have to be reachable from a test, and the default submit path reads
/// `Supabase.instance` which no widget test can provide.
class WorkoutCompleteDialog extends StatefulWidget {
  final String title, duration;
  final int calories;
  final int idleSeconds;
  final String? sessionId;
  final VoidCallback onDone;

  /// The member who finished the workout. The feedback is theirs: it is sent
  /// as them or not at all. Null is whoever is signed in when it is submitted.
  final String? ownerId;

  /// FIT-018's three figures. Passed in rather than read here so the dialog
  /// stays testable — it already carries an injection seam for the same
  /// reason (F-23).
  final int elapsedSeconds;
  final int setsLogged;
  final double volumeKg;

  /// Injection seam. Null uses the real Supabase path below.
  final Future<FeedbackDelivery> Function({
    required int rating,
    required int energy,
    required int difficulty,
    required String notes,
  })? submit;

  const WorkoutCompleteDialog({
    super.key,
    required this.title, required this.duration,
    required this.calories, this.idleSeconds = 0, this.sessionId,
    this.elapsedSeconds = 0, this.setsLogged = 0, this.volumeKg = 0,
    required this.onDone, this.ownerId, this.submit});
  @override
  State<WorkoutCompleteDialog> createState() => _WorkoutCompleteDialogState();
}

class _WorkoutCompleteDialogState extends State<WorkoutCompleteDialog> {
  int _rating = 0;
  int _energy = 0;
  int _difficulty = 0;
  final _notes = TextEditingController();
  bool _submitted = false;
  bool _saving = false;
  /// Set when the insert failed. Its presence is what keeps the form on screen.
  bool _saveFailed = false;
  /// F-23: whether the feedback actually reached a coach. The success line used
  /// to say "sent to your coach" unconditionally; a client with no coach was
  /// told their notes had been delivered to nobody.
  bool _reachedCoach = false;

  @override
  void dispose() { _notes.dispose(); super.dispose(); }

  /// F-23 — this used to end `catch (_) {}` and then set `_submitted = true`
  /// unconditionally, so a failed insert produced the words **"Feedback sent to
  /// your coach!"** on screen. The client believed their session notes had
  /// reached their coach; nothing had been written and nothing could be
  /// recovered, because the dialog then offered only "Back to Home".
  ///
  /// Two separate claims are now told apart, because they can fail
  /// independently:
  ///
  ///   * the **feedback row** — if this fails, nothing was saved, so the form
  ///     stays up with its values intact and the button says try again;
  ///   * the **coach's notification** — if only this fails, the feedback IS
  ///     saved and saying otherwise would be a second falsehood. The success
  ///     line drops the delivery claim instead of retracting the save.
  Future<void> _saveFeedback() async {
    if (_rating == 0) return;
    final owner = widget.ownerId;
    if (owner != null && !_stillIs(owner)) return _discardDraft();
    setState(() { _saving = true; _saveFailed = false; });
    final outcome = await (widget.submit ?? _submitToSupabase)(
      rating: _rating,
      energy: _energy,
      difficulty: _difficulty,
      notes: _notes.text,
    );
    if (!mounted) return;
    if (owner != null && !_stillIs(owner)) return _discardDraft();
    setState(() {
      _saving = false;
      _saveFailed = outcome == FeedbackDelivery.failed;
      _submitted = outcome != FeedbackDelivery.failed;
      _reachedCoach = outcome == FeedbackDelivery.delivered;
    });
  }

  /// The account changed: the draft is not the next member's to read or send.
  void _discardDraft() {
    _notes.clear();
    setState(() {
      _rating = _energy = _difficulty = 0;
      _saving = _saveFailed = false;
    });
  }

  /// Records that the account changed when it did.
  bool _stillIs(String owner) {
    if (Supabase.instance.client.auth.currentUser?.id == owner) return true;
    reportError('WorkoutCompleteDialog',
        StateError('sending workout feedback: the signed-in account changed'));
    return false;
  }

  Future<FeedbackDelivery> _submitToSupabase({
    required int rating,
    required int energy,
    required int difficulty,
    required String notes,
  }) async {
    final db = Supabase.instance.client;
    String? coachId;
    final uid = widget.ownerId ?? db.auth.currentUser?.id;
    try {
      requireWorkoutOwner(db, uid!, 'sending workout feedback');
      final rel = await db
          .from('coach_client_relationships')
          .select('coach_id')
          .eq('client_id', uid)
          .eq('status', 'active')
          .maybeSingle();
      coachId = rel?['coach_id'] as String?;
      requireWorkoutOwner(db, uid, 'sending workout feedback');
      await db.from('workout_feedback').insert({
        'session_id': widget.sessionId,
        'user_id': uid,
        'coach_id': coachId,
        'rating': rating,
        'energy_level': energy > 0 ? energy : null,
        'difficulty': difficulty > 0 ? difficulty : null,
        'notes': notes.isEmpty ? null : notes,
      });
    } catch (e, st) {
      reportError('WorkoutCompleteDialog.submit', e, st);
      // Nothing was written.
      return deliveryFor(saved: false, coachId: coachId, notified: false);
    }

    // Saved from here on. A failure below costs the coach their ping, not the
    // client their notes.
    var notified = false;
    if (coachId != null && _stillIs(uid)) {
      try {
        await db.from('notifications').insert({
          'recipient_id': coachId,
          'type': 'workout_feedback',
          'title': 'Workout Feedback Received',
          'body': 'A client rated their workout $rating/5 — tap to view.',
          'read': false,
        });
        notified = true;
      } catch (e, st) {
        // Saved, just not announced.
        reportError('WorkoutCompleteDialog.notifyCoach', e, st);
      }
    }
    return deliveryFor(saved: true, coachId: coachId, notified: notified);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _brand.withValues(alpha: 0.15),
              border: Border.all(color: _brand.withValues(alpha: 0.4))),
            child: const Icon(Icons.emoji_events_rounded, color: _brand, size: 34)),
          const SizedBox(height: 16),
          // FIT-018: "rewarding, not celebratory ... No confetti."
          // `Workout Complete!` with an exclamation mark is the confetti.
          Text(sessionDoneTitle(widget.title),
            style: TextStyle(color: _white, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(widget.title, style: TextStyle(color: _primary.withValues(alpha: 0.8), fontSize: 13)),
          const SizedBox(height: 20),
          // FIT-018 draws THREE figures — Duration, Sets logged, Volume —
          // and the row this replaces drew Duration, Calories and Idle.
          //
          // `Calories` was `_elapsedSeconds ~/ 60 * 8`: a flat 8 kcal a minute,
          // the same number for every person, every load and every movement.
          // A fabricated figure presented as a measurement, on the screen that
          // closes a session. It goes because the locked design does not draw
          // it, not because of a preference here — and the `calories_burned`
          // column it also writes is untouched, so nothing else changes.
          // Recorded as OD-30.
          //
          // `Idle` goes too, but its warning line survives immediately below,
          // which is where the rest-overrun finding is actually stated.
          if (widget.idleSeconds > 0) ...[
            const SizedBox(height: 8),
            Text('${widget.idleSeconds ~/ 60}m ${widget.idleSeconds % 60}s of rest overrun — tighten it up next time.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _error.withValues(alpha: 0.8), fontSize: 11)),
          ],
          const SizedBox(height: 20),

          // FIT-018's three figures: `51 min Duration · 18 Sets logged ·
          // 4.2 t Volume`. Each is omitted when the session does not support
          // it — a bodyweight session has no volume, and `0.0 t` on a finished
          // workout is worse than two stats.
          Builder(builder: (_) {
            final stats = sessionStats(
              elapsedSeconds: widget.elapsedSeconds,
              setsLogged: widget.setsLogged,
              volumeKg: widget.volumeKg,
            );
            if (stats.isEmpty) return const SizedBox.shrink();
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final st in stats)
                  Semantics(
                    container: true,
                    label: st.spoken,
                    excludeSemantics: true,
                    child: Column(children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(st.value,
                              style: const TextStyle(
                                  color: _white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700)),
                          if (st.unit.isNotEmpty) ...[
                            const SizedBox(width: 2),
                            Text(st.unit,
                                style: const TextStyle(
                                    color: _muted, fontSize: 12)),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(st.label,
                          style:
                              const TextStyle(color: _muted, fontSize: 11)),
                    ]),
                  ),
              ],
            );
          }),

          const SizedBox(height: 24),
          if (!_submitted) ...[
            const Divider(color: Color(0xFF1A1020)),
            const SizedBox(height: 16),

            // FIT-018 asks ONE question with three answers — "the effort
            // question is asked while it's fresh — it's what the coach reads
            // next week." The 1–5 Difficulty row it replaces asked the same
            // thing in a shape the board rejects ("one real fact rather than
            // a score"). `Overall`, `Energy` and the notes field are KEPT:
            // the board not drawing something is not the design saying to
            // delete it (OD-15), and they are recorded as OD-29.
            const Text(effortQuestion,
                style: TextStyle(
                    color: _white, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Row(children: [
              for (final e in SessionEffort.values) ...[
                Expanded(
                  child: Semantics(
                    button: true,
                    inMutuallyExclusiveGroup: true,
                    selected: _difficulty == e.difficulty,
                    label: e.label,
                    excludeSemantics: true,
                    onTap: () => setState(() => _difficulty = e.difficulty),
                    child: GestureDetector(
                      onTap: () => setState(() => _difficulty = e.difficulty),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 44),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _difficulty == e.difficulty
                              ? _primary.withValues(alpha: 0.18)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: _difficulty == e.difficulty
                                  ? _primary
                                  : const Color(0xFF1A1020)),
                        ),
                        child: Text(e.label,
                            style: TextStyle(
                                color: _difficulty == e.difficulty
                                    ? _primary
                                    : _muted,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ),
                if (e != SessionEffort.values.last) const SizedBox(width: 8),
              ],
            ]),
            const SizedBox(height: 16),
            const Text('How was the workout?', style: TextStyle(color: _white, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            _StarRow(label: 'Overall', value: _rating, onChanged: (v) => setState(() => _rating = v)),
            const SizedBox(height: 8),
            _StarRow(label: 'Energy', value: _energy, onChanged: (v) => setState(() => _energy = v)),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 2,
              style: const TextStyle(color: _white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Any notes for your coach? (optional)',
                hintStyle: const TextStyle(color: _muted),
                filled: true, fillColor: _bg,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF1A1020))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF1A1020))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _brand))),
            ),
            if (_saveFailed) ...[
              const SizedBox(height: 12),
              // Voice and recovery match `_RestoreFailedView` above, which is
              // this screen's existing failure language. The exception is NOT
              // interpolated — F-2/F-16 were raised about exactly that.
              Row(children: [
                const Icon(Icons.cloud_off_rounded, color: _error, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Could not send your feedback. Check your connection and '
                    'try again.',
                    style: TextStyle(color: _error.withValues(alpha: 0.9), fontSize: 12, height: 1.4)),
                ),
              ]),
            ],
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: TextButton(
                onPressed: widget.onDone,
                child: const Text('Skip', style: TextStyle(color: _muted)))),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: ElevatedButton(
                onPressed: _rating == 0 || _saving ? null : _saveFeedback,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _brand, foregroundColor: _white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: _white, strokeWidth: 2))
                  // FIT-018's primary action is `Done`, not `Submit`. The
                  // device test caught this: `Done` measured PRESENT because
                  // `sessionDoneLabel` is a const in the resolved file set,
                  // and the button on screen said `Submit`. Eighth false
                  // positive in this measurement, and the first one this
                  // programme introduced itself.
                  //
                  // `Try Again` stays for the failure state — a distinct
                  // outcome that the board's single frame does not cover, and
                  // F-23 is the record of what collapsing it costs.
                  : Text(_saveFailed ? 'Try Again' : sessionDoneLabel,
                      style: const TextStyle(fontWeight: FontWeight.w700)))),
            ]),
          ] else ...[
            const SizedBox(height: 8),
            const Icon(Icons.check_circle, color: _tertiary, size: 40),
            const SizedBox(height: 8),
            Text(_reachedCoach ? 'Feedback sent to your coach!' : 'Feedback saved.',
              style: const TextStyle(color: _tertiary, fontSize: 13)),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: widget.onDone,
              style: ElevatedButton.styleFrom(
                backgroundColor: _brand, foregroundColor: _white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              child: const Text('Back to Home', style: TextStyle(fontWeight: FontWeight.w800)))),
          ],
        ]),
      ),
    );
  }
}

class _StarRow extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  const _StarRow({required this.label, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => Row(children: [
    SizedBox(width: 80, child: Text(label, style: const TextStyle(color: _muted, fontSize: 12))),
    ...List.generate(5, (i) => GestureDetector(
      onTap: () => onChanged(i + 1),
      child: Icon(i < value ? Icons.star_rounded : Icons.star_border_rounded,
        color: i < value ? _brand : _muted, size: 28))),
  ]);
}

class _GuideIconPulse extends StatefulWidget {
  const _GuideIconPulse();
  @override
  State<_GuideIconPulse> createState() => _GuideIconPulseState();
}

class _GuideIconPulseState extends State<_GuideIconPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = Curves.easeInOut.transform(_c.value);
        return Transform.scale(
          scale: 1.0 + t * 0.22,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _primary.withValues(alpha: 0.10 + t * 0.18),
              boxShadow: [BoxShadow(color: _primary.withValues(alpha: t * 0.45), blurRadius: 6 + t * 6)],
            ),
            child: Icon(Icons.menu_book_rounded,
              color: Color.lerp(_primary.withValues(alpha: 0.7), _white, t), size: 14),
          ),
        );
      },
    );
  }
}

// ── Today's coach adjustment, applied as load guidance during the workout ─────
class _ActiveCoachBanner extends StatelessWidget {
  final CoachAdjustment adj;
  const _ActiveCoachBanner({required this.adj});

  String _cue() {
    final d = adj.intensityDelta;
    if (d <= -5) return 'Recovery focus — aim ~${d.abs()}% lighter today. Quality over quantity.';
    if (d >= 5) return 'You’re primed — push ~$d% heavier if your form holds.';
    return 'Train at your normal working loads today.';
  }

  @override
  Widget build(BuildContext context) {
    final d = adj.intensityDelta;
    final accent = d == 0 ? _primary : (d < 0 ? _amber : _tertiary);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [accent.withValues(alpha: 0.14), _card],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.35))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.auto_awesome_rounded, color: accent, size: 16),
          const SizedBox(width: 8),
          Text('COACH ADJUSTMENT',
            style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
          const Spacer(),
          if (d != 0) Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
            child: Text('${d > 0 ? '+' : ''}$d%',
              style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 8),
        Text(_cue(), style: const TextStyle(color: _muted, fontSize: 13, height: 1.4)),
      ]),
    );
  }
}

/// Whether the set cursor must be re-pointed after `replaced` is swapped out for
/// `replacement`.
///
/// Extracted and CORRECTED. It was written inline as
///
///     replacement.sets.isNotEmpty &&
///         (_currentSetId == null || we.setById(_currentSetId!) != null)
///
/// and `_currentSetId` is declared `String _currentSetId = ''` — **non-nullable,
/// with the EMPTY STRING as its "no cursor yet" sentinel**. So `== null` was
/// always false (the analyzer said so, twice, at warning level) and the case it
/// was meant to cover fell through to `replaced.setById('')`, which finds
/// nothing and returns null. The condition was therefore false exactly when it
/// needed to be true: **a client who swapped an exercise before touching any set
/// kept a cursor pointing into the exercise that no longer exists** — the precise
/// failure the comment at the call site says this prevents.
///
/// It is a function rather than a condition so the three cases can be asserted
/// without pumping a widget.
bool shouldRepointCursor({
  required String currentSetId,
  required WorkoutExercise replaced,
  required WorkoutExercise replacement,
}) {
  // Nowhere to point. The caller reads `sets.first`, so this must stay first.
  if (replacement.sets.isEmpty) return false;
  // No cursor yet — the case the null check silently lost.
  if (currentSetId.isEmpty) return true;
  // The cursor was inside the exercise being replaced, so it is now dangling.
  return replaced.setById(currentSetId) != null;
}
