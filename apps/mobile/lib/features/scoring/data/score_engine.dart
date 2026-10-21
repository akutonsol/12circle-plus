import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/observability/app_failure.dart';

/// 12 Circle Automated Scoring Engine — client side.
/// Every eligible action calls one of the typed helpers, which records an
/// auditable score_event via the `award_points` RPC. Points/levels/badges are
/// computed server-side; this class never sets a score directly.
class ScoreEngine {
  final _db = Supabase.instance.client;
  String? get _uid => _db.auth.currentUser?.id;
  String get _today => DateTime.now().toIso8601String().split('T').first;
  String get _week {
    final n = DateTime.now();
    final monday = n.subtract(Duration(days: n.weekday - 1));
    return '${monday.year}-${monday.month}-${monday.day}';
  }

  Future<void> _award({
    required String category, required String action, required int points,
    String? refType, String? refId, String? dedupKey,
  }) async {
    try {
      await _db.rpc('award_points', params: {
        'p_category': category, 'p_action': action, 'p_points': points,
        'p_ref_type': refType, 'p_ref_id': refId, 'p_dedup_key': dedupKey,
      });
    } catch (e) {
      // Rule O: scoring never blocks the user action, but a sanctioned
      // swallow that records is an engineering decision and one that does
      // not is an outage nobody will ever see. Behaviour is unchanged.
      reportError('ScoreEngine._award', e,
          null, <String, Object?>{'category': category, 'action': action});
    }
  }

  Future<void> _penalize({
    required String category, required String action, required int points,
    String? dedupKey,
  }) async {
    try {
      await _db.rpc('penalize_points', params: {
        'p_category': category, 'p_action': action, 'p_points': points,
        'p_dedup_key': dedupKey,
      });
    } catch (e) {
      // Rule O, as above. Still non-blocking, now visible.
      reportError('ScoreEngine._penalize', e,
          null, <String, Object?>{'category': category, 'action': action});
    }
  }

  // ── Penalties ─────────────────────────────────────────────
  /// −5 each time a rest period runs into idle/overtime.
  Future<void> idleTimePenalty() =>
      _penalize(category: 'workouts', action: 'idle_penalty', points: 5);

  // ── Workouts ──────────────────────────────────────────────
  Future<void> workoutStarted(String id) => _award(
      category: 'workouts', action: 'workout_start', points: 5,
      refType: 'workout', refId: id, dedupKey: 'workout_start:$id:$_today');
  Future<void> workoutCompleted(String id) => _award(
      category: 'workouts', action: 'workout_complete', points: 25,
      refType: 'workout', refId: id, dedupKey: 'workout_complete:$id');
  Future<void> workoutResumeFinished(String id) => _award(
      category: 'workouts', action: 'workout_resume_finish', points: 15,
      refType: 'workout', refId: id, dedupKey: 'workout_resume:$id');
  Future<void> allWorkoutsThisWeek() => _award(
      category: 'workouts', action: 'workout_week_bonus', points: 50,
      dedupKey: 'workout_week:$_week');

  // ── Nutrition ─────────────────────────────────────────────
  Future<void> mealLogged(String mealId) => _award(
      category: 'nutrition', action: 'meal_log', points: 5,
      refType: 'meal', refId: mealId, dedupKey: 'meal:$mealId');
  Future<void> proteinGoalHit() => _award(
      category: 'nutrition', action: 'protein_goal', points: 15,
      dedupKey: 'protein:$_today');
  Future<void> waterGoalHit() => _award(
      category: 'nutrition', action: 'water_goal', points: 10,
      dedupKey: 'water:$_today');
  Future<void> nutritionDayComplete() => _award(
      category: 'nutrition', action: 'nutrition_day', points: 20,
      dedupKey: 'nutrition_day:$_today');

  // ── Habits ────────────────────────────────────────────────
  Future<void> habitCompleted(String habitId) => _award(
      category: 'habits', action: 'habit_complete', points: 5,
      refType: 'habit', refId: habitId, dedupKey: 'habit:$habitId:$_today');
  Future<void> allHabitsToday() => _award(
      category: 'habits', action: 'habits_all', points: 20,
      dedupKey: 'habits_all:$_today');
  Future<void> habitStreak7() => _award(
      category: 'habits', action: 'habit_streak_7', points: 50,
      dedupKey: 'habit_streak7:$_today');

  // ── Check-Ins ─────────────────────────────────────────────
  Future<void> weeklyCheckin(String weekStart) => _award(
      category: 'checkins', action: 'checkin_weekly', points: 25,
      refType: 'checkin', refId: weekStart, dedupKey: 'checkin:$weekStart');
  Future<void> progressPhotos() => _award(
      category: 'checkins', action: 'photos_upload', points: 20,
      dedupKey: 'photos:$_today');
  Future<void> assessmentComplete() => _award(
      category: 'checkins', action: 'assessment', points: 25,
      dedupKey: 'assessment');

  // ── Community / Events / Challenges ───────────────────────
  Future<void> attendEvent(String eventId) => _award(
      category: 'community', action: 'event_attend', points: 50,
      refType: 'event', refId: eventId, dedupKey: 'event:$eventId');
  Future<void> joinChallenge(String challengeId) => _award(
      category: 'challenges', action: 'challenge_join', points: 25,
      refType: 'challenge', refId: challengeId, dedupKey: 'challenge_join:$challengeId');
  Future<void> completeChallenge(String challengeId) => _award(
      category: 'challenges', action: 'challenge_complete', points: 100,
      refType: 'challenge', refId: challengeId, dedupKey: 'challenge_done:$challengeId');
  Future<void> communityPost() => _award(
      category: 'community', action: 'community_post', points: 5,
      dedupKey: 'post:$_today');

  // ── Coach-assigned action items ───────────────────────────
  Future<void> actionItemComplete(String itemId) => _award(
      category: 'coaching', action: 'action_item_complete', points: 10,
      refType: 'action_item', refId: itemId, dedupKey: 'action_item:$itemId');

  // ── Coaching engagement ───────────────────────────────────
  Future<void> messageCoach() => _award(
      category: 'coaching', action: 'message_coach', points: 5,
      dedupKey: 'message_coach:$_today');
  Future<void> reviewCoachFeedback() => _award(
      category: 'coaching', action: 'review_feedback', points: 5,
      dedupKey: 'review_feedback:$_today');
  Future<void> bookSession(String callId) => _award(
      category: 'coaching', action: 'book_session', points: 15,
      refType: 'call', refId: callId, dedupKey: 'book:$callId');
  Future<void> attendSession(String callId) => _award(
      category: 'coaching', action: 'attend_session', points: 25,
      refType: 'call', refId: callId, dedupKey: 'attend:$callId');

  // ── Reads ─────────────────────────────────────────────────
  Future<Map<String, dynamic>?> myScore() async {
    final uid = _uid;
    if (uid == null) return null;
    return await _db.from('user_scores').select().eq('user_id', uid).maybeSingle();
  }

  Future<Map<String, dynamic>?> clientScore(String clientId) async {
    return await _db.from('user_scores').select().eq('user_id', clientId).maybeSingle();
  }

  Future<List<Map<String, dynamic>>> recentEvents({int limit = 30}) async {
    final uid = _uid;
    if (uid == null) return [];
    final rows = await _db.from('score_events').select()
        .eq('user_id', uid).order('created_at', ascending: false).limit(limit);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> allBadges() async {
    final rows = await _db.from('badges').select().order('sort_order');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<Set<String>> myBadgeIds() async {
    final uid = _uid;
    if (uid == null) return {};
    final rows = await _db.from('user_badges').select('badge_id').eq('user_id', uid);
    return {for (final r in rows as List) r['badge_id'] as String};
  }

  Future<List<Map<String, dynamic>>> leaderboardGlobal({int limit = 50}) async {
    final rows = await _db.rpc('leaderboard_global', params: {'p_limit': limit});
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<List<Map<String, dynamic>>> leaderboardCoach(String coachId, {int limit = 50}) async {
    final rows = await _db.rpc('leaderboard_coach', params: {'p_coach': coachId, 'p_limit': limit});
    return List<Map<String, dynamic>>.from(rows as List);
  }
}
