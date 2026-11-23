import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/domain/auth_provider.dart';
import '../../../core/observability/app_failure.dart';
import '../../../core/realtime/realtime.dart';
import '../data/coach_program_service.dart';
import '../data/coach_relationship_service.dart';
import '../data/score_service.dart';

final _programSvc = CoachProgramService();
final _relSvc = CoachRelationshipService();
final _scoreSvc = ScoreService();

// ── Relationship ──────────────────────────────────────────────
final myRelationshipProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  ref.watch(currentUserProvider); // rerun on auth change
  ref.watch(tableTickerProvider('coach_client_relationships')); // live
  return _relSvc.getMyRelationship();
});

final pendingRequestsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  // QAX-SES-01: recompute for whoever is signed in now, not whoever was.
  ref.watch(currentUserProvider);
  ref.watch(tableTickerProvider('coach_client_relationships')); // live: new requests
  final coachId = Supabase.instance.client.auth.currentUser?.id;
  if (coachId == null) return [];
  return _relSvc.getPendingRequests(coachId);
});

// ── Programs ─────────────────────────────────────────────────
// QAX-SES-01: the providers below read the signed-in user inside a service, which
// the class guard in per_user_provider_scope_test.dart cannot see. Each watches
// the user so a change of account recomputes it instead of serving the last one's.
final myProgramsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  ref.watch(currentUserProvider);
  return _programSvc.getMyPrograms();
});

final myAssignedProgramProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  ref.watch(currentUserProvider);
  return _programSvc.getMyAssignedProgram();
});

// Workouts inside a single program — drives the Program Builder (Module 31).
final programWorkoutsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, programId) async {
  return _programSvc.getProgramWorkouts(programId);
});

final todaysWorkoutProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  ref.watch(currentUserProvider);
  return _programSvc.getTodaysWorkout();
});

// ── Nutrition plan ───────────────────────────────────────────
final myNutritionPlanProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  ref.watch(currentUserProvider);
  return _programSvc.getMyNutritionPlan();
});

// ── Habits ───────────────────────────────────────────────────
final myHabitsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  ref.watch(currentUserProvider);
  return _programSvc.getMyHabits();
});

final todayHabitLogsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  ref.watch(currentUserProvider);
  return _programSvc.getTodayHabitLogs();
});

// Computed: habits with completion status
final habitsWithStatusProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final habits = await ref.watch(myHabitsProvider.future);
  final logs = await ref.watch(todayHabitLogsProvider.future);
  final logMap = {for (final l in logs) l['habit_id'] as String: l};
  return habits.map((h) {
    final log = logMap[h['id'] as String];
    return {
      ...h,
      'is_completed_today': log?['completed'] == true,
      'today_value': log?['value'] ?? 0,
    };
  }).toList();
});

// ── Score ────────────────────────────────────────────────────
final todayScoreProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  ref.watch(currentUserProvider);
  // Live: `daily_scores` is written by habits, community posts, progress logs,
  // check-ins and workouts, and is in the realtime publication (037). Without
  // the ticker only a finished workout or check-in re-read this, so a habit
  // ticked or a post made left the Wellness Pulse and Activity as they were.
  ref.watch(tableTickerProvider('daily_scores'));
  return _scoreSvc.getTodayScore();
});

final weekScoresProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  ref.watch(currentUserProvider);
  // Live: `daily_scores` is written by habits, community posts, progress logs,
  // check-ins and workouts, and is in the realtime publication (037). Without
  // the ticker only a finished workout or check-in re-read this, so a habit
  // ticked or a post made left the Wellness Pulse and Activity as they were.
  ref.watch(tableTickerProvider('daily_scores'));
  return _scoreSvc.getWeekScores();
});

final monthScoresProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  // QAX-SES-01: recompute for whoever is signed in now, not whoever was.
  ref.watch(currentUserProvider);
  // Live: `daily_scores` is written by habits, community posts, progress logs,
  // check-ins and workouts, and is in the realtime publication (037). Without
  // the ticker only a finished workout or check-in re-read this, so a habit
  // ticked or a post made left the Wellness Pulse and Activity as they were.
  ref.watch(tableTickerProvider('daily_scores'));
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) return [];
  final now = DateTime.now();
  final startOfMonth = DateTime(now.year, now.month, 1);
  final data = await Supabase.instance.client
      .from('daily_scores')
      .select()
      .eq('user_id', userId)
      .gte('score_date', startOfMonth.toIso8601String().split('T')[0])
      .order('score_date');
  return List<Map<String, dynamic>>.from(data);
});

final sentInvitesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  // QAX-SES-01: recompute for whoever is signed in now, not whoever was.
  ref.watch(currentUserProvider);
  final coachId = Supabase.instance.client.auth.currentUser?.id;
  if (coachId == null) return [];
  final data = await Supabase.instance.client
      .from('coach_invites')
      .select()
      .eq('coach_id', coachId)
      .order('created_at', ascending: false)
      .limit(50);
  return List<Map<String, dynamic>>.from(data);
});

final coachLeaderboardProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  // QAX-SES-01: recompute for whoever is signed in now, not whoever was.
  ref.watch(currentUserProvider);
  // Live: ticks on the table it READS (P0-FL-47). It watched 'user_scores',
  // which only the award_points / apply_penalty RPCs write; a client's daily
  // score is the app's `daily_scores` upsert, so it never moved this tab.
  // `daily_scores` is published (migration 037) and a coach may read an
  // active client's rows (migration 100), so realtime delivers the change.
  ref.watch(tableTickerProvider('daily_scores'));
  final coachId = Supabase.instance.client.auth.currentUser?.id;
  if (coachId == null) return [];
  return _scoreSvc.getCoachLeaderboard(coachId);
});

// ── Client data (coach reads a specific client) ───────────────
// Disposed with the page: reopening a client must read them again, because
// what changes here is the client's doing and nothing else tells this device.
//
// P0-FL-37 (security ledger F3). This used to read the client's WHOLE
// user_profiles row (`select('*')`), so every PAR-Q answer, risk flag, medical
// condition and injury a coach saw on this page was read without a trace in
// `assessment_access_log`. The profile read now names only what the page needs
// that is NOT assessment data; the assessment comes from
// [clientAssessmentProvider], whose RPC logs the read before it returns.
// Names stay here: the page header, notes and video sheets need them even when
// the assessment read fails, and a coach already sees them on the roster.
const clientDetailProfileColumns =
    'id, first_name, last_name, avatar_url, coaching_mode, created_at, onboarding_complete';

final clientDetailProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, clientId) async {
  final db = Supabase.instance.client;
  final profile = await db
      .from('user_profiles')
      .select(clientDetailProfileColumns)
      .eq('id', clientId)
      .maybeSingle();
  if (profile == null) return {};

  final photoRows = await db
      .from('progress_photo_logs')
      .select()
      .eq('user_id', clientId)
      .order('logged_at', ascending: false)
      .limit(6);
  // Attach a short-lived signed URL for each stored photo so the coach view
  // can render them (bucket is private).
  final photos = <Map<String, dynamic>>[];
  for (final row in (photoRows as List)) {
    final m = Map<String, dynamic>.from(row as Map);
    final path = m['storage_path'] as String?;
    if (path != null && path.isNotEmpty) {
      try {
        m['url'] = await db.storage.from('progress-photos').createSignedUrl(path, 3600);
      } catch (_) {}
    }
    photos.add(m);
  }

  // Onboarding baseline photos (front/side/back) live as fixed files at
  // `<clientId>/<side>.<ext>` (separate from the progress_photo_logs gallery).
  // Sign each so the coach can see the client's "Day 1" starting point.
  final onboardingPhotos = <String, String>{};
  for (final side in const ['front', 'side', 'back']) {
    for (final ext in const ['jpg', 'jpeg', 'png', 'heic', 'webp']) {
      try {
        onboardingPhotos[side] = await db.storage
            .from('progress-photos')
            .createSignedUrl('$clientId/$side.$ext', 3600);
        break; // first existing extension wins
      } catch (_) {}
    }
  }

  final weights = await db
      .from('weight_logs')
      .select()
      .eq('user_id', clientId)
      .order('logged_at', ascending: false)
      .limit(10);

  final checkins = await db
      .from('weekly_checkins')
      .select()
      .eq('user_id', clientId)
      .order('week_start_date', ascending: false)
      .limit(4);

  final assignment = await db
      .from('workout_program_assignments')
      .select('*, workout_programs(name, goal, duration_weeks)')
      .eq('client_id', clientId)
      .eq('status', 'active')
      .maybeSingle();

  final nutrition = await db
      .from('client_nutrition_plans')
      .select()
      .eq('client_id', clientId)
      .eq('is_active', true)
      .maybeSingle();

  final habits = await db
      .from('client_habits')
      .select()
      .eq('client_id', clientId)
      .eq('is_active', true);

  // `workout_sessions`, not `workout_logs`: the latter is owner-only by
  // 003:193 and returns 200 + [] to a coach, so `client_detail_screen.dart:933`
  // showed every client as having trained never. Coach-readable by
  // 100_rls_harden_client_data.sql; `completed` only, because the screen reads
  // `completed_at` and an unfinished session has none.
  final workoutLogs = await db
      .from('workout_sessions')
      .select('user_id, workout_title, completed_at, duration_seconds')
      .eq('user_id', clientId)
      .eq('status', 'completed')
      .order('completed_at', ascending: false)
      .limit(20);

  final todayScore = await db
      .from('daily_scores')
      .select()
      .eq('user_id', clientId)
      .eq('score_date', DateTime.now().toIso8601String().split('T')[0])
      .maybeSingle();

  return {
    ...profile,
    'progress_photos': List.from(photos),
    'onboarding_photos': Map<String, String>.from(onboardingPhotos),
    'weight_logs': List.from(weights),
    'weekly_checkins': List.from(checkins),
    'workout_logs': List.from(workoutLogs),
    'program_assignment': assignment,
    'nutrition_plan': nutrition,
    'habits': List.from(habits),
    'today_score': todayScore,
  };
});

// ── Client assessment (logged read) ───────────────────────────
/// What the coach's assessment read answered (P0-FL-37).
enum ClientAssessmentStatus {
  /// The RPC returned the client's row. `has_assessment` may still be false.
  loaded,

  /// The RPC returned no row: there is no assessment on file.
  noRow,

  /// 42501: the signed-in coach is not this client's ACTIVE coach.
  notActiveCoach,
}

class ClientAssessment {
  final ClientAssessmentStatus status;

  /// The RPC row, keyed by the same column names `user_profiles` uses, so the
  /// screen's readers (`parq_answers`, `risk_level`, …) are unchanged. Empty
  /// unless [status] is [ClientAssessmentStatus.loaded].
  final Map<String, dynamic> row;
  const ClientAssessment(this.status, [this.row = const {}]);

  /// The client completed (some of) their intake. False for every status but
  /// [ClientAssessmentStatus.loaded].
  bool get hasAssessment =>
      status == ClientAssessmentStatus.loaded && row['has_assessment'] == true;
}

/// The client's assessment (PAR-Q, risk, medical, injuries, lifestyle, goals,
/// consent), read ONLY through `get_client_assessment` (migrations 140/141),
/// which writes an `assessment_access_log` row before it returns — so every
/// time a coach opens this, it is on the record (SEC-PHI-AUDIT).
///
/// Once per page open: autoDispose, and nothing here watches a ticker, so
/// rebuilds and re-reads of [clientDetailProvider] do not log extra reads.
///
/// A network or server failure is an ERROR (the page shows "Couldn't load"),
/// never an empty assessment: an empty one would read as no PAR-Q flags.
final clientAssessmentProvider = FutureProvider.autoDispose
    .family<ClientAssessment, String>((ref, clientId) async {
  final dynamic res;
  try {
    res = await Supabase.instance.client
        .rpc('get_client_assessment', params: {'p_client': clientId});
  } on PostgrestException catch (e, st) {
    if (e.code == '42501') {
      // Not this client's active coach. An answer, not an outage — but the
      // profile read admits the same coaches, so seeing it is worth a record.
      reportError('clientAssessmentProvider.notActiveCoach', e, st);
      return const ClientAssessment(ClientAssessmentStatus.notActiveCoach);
    }
    reportError('clientAssessmentProvider', e, st);
    rethrow;
  } catch (e, st) {
    reportError('clientAssessmentProvider', e, st);
    rethrow;
  }
  final Object? first = res is List ? (res.isEmpty ? null : res.first) : res;
  if (first is! Map) {
    return const ClientAssessment(ClientAssessmentStatus.noRow);
  }
  final row = Map<String, dynamic>.from(first)
    // `client_id` is the RPC's name for the profile's `id`; nothing on the
    // page reads it, and it must not shadow the profile's own keys.
    ..remove('client_id');
  return ClientAssessment(ClientAssessmentStatus.loaded, row);
});

// Services exposed as providers for use in screens
final coachProgramServiceProvider = Provider((_) => _programSvc);
final coachRelServiceProvider = Provider((_) => _relSvc);
final scoreServiceProvider = Provider((_) => _scoreSvc);

/// Whether the given client has paid for a plan with the current coach.
/// Coaches can only assign work (programs/nutrition/habits/etc.) once true.
final clientHasPaidPlanProvider =
    FutureProvider.autoDispose.family<bool, String>((ref, clientId) async {
  return _programSvc.clientHasPaidPlan(clientId);
});
