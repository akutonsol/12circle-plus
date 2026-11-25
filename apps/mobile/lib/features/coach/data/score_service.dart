import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/observability/app_failure.dart';

class ScoreService {
  /// P0-FL-59e · [forUid]: the member these points are for. Given, every award
  /// is written for that member or not at all: nothing is read or written once
  /// someone else is signed in. Not given, the member signed in when the award
  /// started is the one it stays with. Null is a member captured while nobody
  /// was signed in: nobody's, so nothing is awarded to whoever is by now.
  ScoreService({this.forUid = signedInAtCall});

  final String? forUid;

  /// "[forUid] was not given", which null is not.
  static const signedInAtCall = '<signed in at the call>';

  final _db = Supabase.instance.client;

  /// The one member an award is for, fixed at its start; null = award nothing
  /// (signed out, or [forUid] is no longer the member signed in: recorded).
  String? _awardOwner() {
    final owner =
        forUid == signedInAtCall ? _db.auth.currentUser?.id : forUid;
    return _stillSignedIn(owner) ? owner : null;
  }

  bool _stillSignedIn(String? owner) {
    if (_db.auth.currentUser?.id == owner) return true;
    reportError('ScoreService.identity',
        StateError('daily score: the signed-in account changed'));
    return false;
  }

  static const int maxWorkout = 30;
  static const int maxNutrition = 30;
  static const int maxHabits = 20;
  static const int maxCheckin = 10;
  static const int maxCommunity = 10;

  Future<Map<String, dynamic>> getTodayScore() async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return _emptyScore();
    return _todayScoreOf(userId);
  }

  Future<Map<String, dynamic>> _todayScoreOf(String userId) async {
    final today = DateTime.now().toIso8601String().split('T')[0];
    final row = await _db
        .from('daily_scores')
        .select()
        .eq('user_id', userId)
        .eq('score_date', today)
        .maybeSingle();
    return row ?? _emptyScore();
  }

  Future<List<Map<String, dynamic>>> getWeekScores() async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return [];
    final now = DateTime.now();
    final start = now.subtract(Duration(days: 6));
    final data = await _db
        .from('daily_scores')
        .select()
        .eq('user_id', userId)
        .gte('score_date', start.toIso8601String().split('T')[0])
        // Oldest first, stated: postgrest-dart orders DESCENDING when
        // `ascending` is omitted, and Activity reads `last` as the latest day.
        .order('score_date', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<void> addWorkoutPoints() async {
    await _updatePoints({'workout_points': maxWorkout});
  }

  Future<void> addNutritionPoints(double completionPct) async {
    final pts = (maxNutrition * completionPct).round().clamp(0, maxNutrition);
    await _updatePoints({'nutrition_points': pts});
  }

  Future<void> addHabitPoints(int completed, int total) async {
    if (total == 0) return;
    final pts = ((completed / total) * maxHabits).round().clamp(0, maxHabits);
    await _updatePoints({'habits_points': pts});
  }

  Future<void> addCheckinPoints() async {
    await _updatePoints({'checkin_points': maxCheckin});
  }

  Future<void> addCommunityPoints() async {
    final userId = _awardOwner();
    if (userId == null) return;
    final today = await _todayScoreOf(userId);
    if ((today['community_points'] as int? ?? 0) >= maxCommunity) return;
    if (!_stillSignedIn(userId)) return;
    await _updatePointsOf(userId, {'community_points': maxCommunity});
  }

  Future<void> _updatePoints(Map<String, dynamic> updates) async {
    final userId = _awardOwner();
    if (userId == null) return;
    await _updatePointsOf(userId, updates);
  }

  /// The day that is read and the day that is written are both [userId]'s.
  Future<void> _updatePointsOf(
      String userId, Map<String, dynamic> updates) async {
    final today = DateTime.now().toIso8601String().split('T')[0];
    final current = await _todayScoreOf(userId);
    if (!_stillSignedIn(userId)) return;
    final merged = {
      'user_id': userId,
      'score_date': today,
      'workout_points': current['workout_points'] ?? 0,
      'nutrition_points': current['nutrition_points'] ?? 0,
      'habits_points': current['habits_points'] ?? 0,
      'checkin_points': current['checkin_points'] ?? 0,
      'community_points': current['community_points'] ?? 0,
      ...updates,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    merged['total_score'] = (merged['workout_points'] as int) +
        (merged['nutrition_points'] as int) +
        (merged['habits_points'] as int) +
        (merged['checkin_points'] as int) +
        (merged['community_points'] as int);
    await _db.from('daily_scores').upsert(merged, onConflict: 'user_id,score_date');
  }

  // Coach leaderboard: top clients by total_score today
  Future<List<Map<String, dynamic>>> getCoachLeaderboard(String coachId) async {
    final rels = await _db
        .from('coach_client_relationships')
        .select('client_id')
        .eq('coach_id', coachId)
        .eq('status', 'active');
    final clientIds = (rels as List).map((r) => r['client_id'] as String).toList();
    if (clientIds.isEmpty) return [];
    final today = DateTime.now().toIso8601String().split('T')[0];
    final scores = await _db
        .from('daily_scores')
        .select('user_id, total_score, workout_points, nutrition_points, habits_points, score_date')
        .inFilter('user_id', clientIds)
        .eq('score_date', today)
        .order('total_score', ascending: false);
    if ((scores as List).isEmpty) return [];
    final profiles = await _db
        .from('user_profiles')
        .select('id, first_name, last_name, avatar_url')
        .inFilter('id', clientIds);
    // P0-FL-41: typed. An untyped `?? {}` here was a Map<dynamic, dynamic>,
    // and the Leaderboard tab's `as Map<String, dynamic>?` threw while
    // building whenever a client's profile row did not come back (deleted, or
    // not readable). The row is kept; the tab names them "Client".
    final profileMap = <String, Map<String, dynamic>>{
      for (final p in List<Map<String, dynamic>>.from(profiles as List))
        p['id'] as String: p,
    };
    return scores.map<Map<String, dynamic>>((s) => {
      ...s,
      'profile': profileMap[s['user_id']] ?? const <String, dynamic>{},
    }).toList();
  }

  Map<String, dynamic> _emptyScore() => {
    'workout_points': 0,
    'nutrition_points': 0,
    'habits_points': 0,
    'checkin_points': 0,
    'community_points': 0,
    'total_score': 0,
  };
}
