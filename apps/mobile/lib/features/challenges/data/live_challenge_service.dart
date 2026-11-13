import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/observability/app_failure.dart';
import '../../scoring/data/score_engine.dart';
import 'models/challenge_model.dart';

class LiveChallengeService {
  final _db = Supabase.instance.client;

  /// Throws on a failed read. Every reader states a failure — Challenges'
  /// own F-15 state, What's On and Activity — and the `[]` this returned
  /// instead reached all three as "No challenges here".
  Future<List<Challenge>> getActiveChallenges() async {
    try {
      final uid = _db.auth.currentUser?.id;
      final data = await _db
          .from('challenges')
          .select()
          .eq('status', 'active')
          .order('created_at', ascending: false);
      if ((data as List).isEmpty) return [];

      final challengeIds = data.map((c) => c['id'] as String).toList();

      List<Map<String, dynamic>> myParticipations = [];
      List<Map<String, dynamic>> allParticipants = [];

      if (uid != null) {
        myParticipations = List<Map<String, dynamic>>.from(
          await _db.from('challenge_participants')
              .select('challenge_id, current_progress, joined_at')
              .eq('user_id', uid)
              .inFilter('challenge_id', challengeIds));
      }

      allParticipants = List<Map<String, dynamic>>.from(
        await _db.from('challenge_participants')
            .select('challenge_id, user_id, current_progress')
            .inFilter('challenge_id', challengeIds));

      final myMap = {for (final p in myParticipations) p['challenge_id'] as String: p};

      return data.map<Challenge>((c) {
        final id = c['id'] as String;
        final myEntry = myMap[id];
        final participants = allParticipants.where((p) => p['challenge_id'] == id).toList();
        final target = (c['target_value'] as num?)?.toDouble() ?? 100;
        final myProgress = (myEntry?['current_progress'] as num?)?.toDouble() ?? 0;

        return Challenge(
          id: id,
          title: c['title'] as String,
          description: c['description'] as String? ?? '',
          type: _parseType(c['type'] as String),
          status: ChallengeStatus.active,
          startDate: c['start_date'] != null ? DateTime.parse(c['start_date']) : DateTime.now(),
          endDate: c['end_date'] != null ? DateTime.parse(c['end_date']) : DateTime.now().add(const Duration(days: 30)),
          targetValue: target.toInt(),
          unit: c['unit'] as String? ?? 'units',
          myProgress: myProgress,
          participantCount: participants.length,
          isJoined: myEntry != null,
          coachName: '',
          emoji: c['emoji'] as String? ?? '🏆',
          leaderboard: _buildLeaderboard(participants, uid, target),
          rewards: [],
          badges: [],
        );
      }).toList();
    } catch (e) {
      reportError('LiveChallengeService.getActiveChallenges', e);
      rethrow;
    }
  }

  Future<void> joinChallenge(String challengeId) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await _db.from('challenge_participants').insert({
        'challenge_id': challengeId,
        'user_id': uid,
        'current_progress': 0,
      });
      ScoreEngine().joinChallenge(challengeId); // +25
    } catch (e) {
      final s = e.toString();
      if (s.contains('23505') || s.contains('duplicate') || s.contains('unique')) {
        return; // already joined — treat as success
      }
      rethrow;
    }
  }

  Future<void> updateProgress(String challengeId, double progress) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    await _db.from('challenge_participants').upsert({
      'challenge_id': challengeId,
      'user_id': uid,
      'current_progress': progress,
    }, onConflict: 'challenge_id,user_id');
    if (progress >= 1.0) ScoreEngine().completeChallenge(challengeId); // +100, once
  }

  Future<void> createChallenge(Map<String, dynamic> data) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    await _db.from('challenges').insert({
      ...data,
      'coach_id': uid,
      'status': 'active',
    });
  }

  ChallengeType _parseType(String t) => switch (t) {
    'steps' => ChallengeType.steps,
    'workout' => ChallengeType.workout,
    'nutrition' => ChallengeType.nutrition,
    _ => ChallengeType.workout,
  };

  List<LeaderboardEntry> _buildLeaderboard(
    List<Map<String, dynamic>> participants,
    String? myId,
    double target,
  ) {
    final sorted = [...participants]..sort((a, b) =>
      ((b['current_progress'] as num?) ?? 0).compareTo((a['current_progress'] as num?) ?? 0));
    return sorted.take(10).toList().asMap().entries.map((e) {
      final p = e.value;
      final progress = (p['current_progress'] as num?)?.toDouble() ?? 0;
      return LeaderboardEntry(
        userId: p['user_id'] as String,
        userName: 'Participant',
        rank: e.key + 1,
        progress: target > 0 ? (progress / target).clamp(0, 1) : 0,
        score: progress.toInt(),
        isMe: p['user_id'] == myId,
      );
    }).toList();
  }
}
