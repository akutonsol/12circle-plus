import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/domain/auth_provider.dart';
import '../data/challenge_service.dart';
import '../data/live_challenge_service.dart';
import '../data/models/challenge_model.dart';

final challengeServiceProvider = Provider<ChallengeService>((ref) => ChallengeService());
final liveChallengeServiceProvider = Provider<LiveChallengeService>((ref) => LiveChallengeService());

final selectedChallengeProvider = StateProvider<Challenge?>((ref) => null);
final selectedChallengeTabProvider = StateProvider<int>((ref) => 0);

// ── Live challenges from Supabase ─────────────────────────────────────────────
final liveChallengesProvider = FutureProvider<List<Challenge>>((ref) async {
  ref.watch(currentUserProvider);
  final svc = ref.watch(liveChallengeServiceProvider);
  return svc.getActiveChallenges();
});

class ChallengeNotifier extends StateNotifier<List<Challenge>> {
  final LiveChallengeService _svc;
  ChallengeNotifier(super.state, this._svc);

  void initialize(List<Challenge> challenges) {
    state = challenges;
  }

  Future<bool> joinChallenge(String challengeId) async {
    try {
      await _svc.joinChallenge(challengeId);
    } catch (_) {
      return false;
    }
    state = state.map((c) {
      if (c.id != challengeId) return c;
      return Challenge(
        id: c.id, title: c.title, description: c.description,
        type: c.type, status: c.status, startDate: c.startDate,
        endDate: c.endDate, targetValue: c.targetValue, unit: c.unit,
        myProgress: c.myProgress, participantCount: c.participantCount + 1,
        leaderboard: c.leaderboard, rewards: c.rewards, badges: c.badges,
        isJoined: true, coachName: c.coachName, emoji: c.emoji,
      );
    }).toList();
    return true;
  }

  Future<void> updateProgress(String challengeId, double progress) async {
    await _svc.updateProgress(challengeId, progress);
    state = state.map((c) {
      if (c.id != challengeId) return c;
      return Challenge(
        id: c.id, title: c.title, description: c.description,
        type: c.type, status: c.status, startDate: c.startDate,
        endDate: c.endDate, targetValue: c.targetValue, unit: c.unit,
        myProgress: progress, participantCount: c.participantCount,
        leaderboard: c.leaderboard, rewards: c.rewards, badges: c.badges,
        isJoined: c.isJoined, coachName: c.coachName, emoji: c.emoji,
      );
    }).toList();
  }
}

final challengeNotifierProvider = StateNotifierProvider<ChallengeNotifier, List<Challenge>>((ref) {
  final svc = ref.watch(liveChallengeServiceProvider);
  final notifier = ChallengeNotifier([], svc);
  // Populate notifier from live DB data as soon as it loads
  ref.listen<AsyncValue<List<Challenge>>>(
    liveChallengesProvider,
    (_, next) => next.whenData(notifier.initialize),
    fireImmediately: true,
  );
  return notifier;
});

final activeChallengesProvider = Provider<List<Challenge>>((ref) {
  return ref.watch(challengeNotifierProvider).where((c) => c.status == ChallengeStatus.active).toList();
});

final upcomingChallengesProvider = Provider<List<Challenge>>((ref) {
  return ref.watch(challengeNotifierProvider).where((c) => c.status == ChallengeStatus.upcoming).toList();
});

final completedChallengesProvider = Provider<List<Challenge>>((ref) {
  return ref.watch(challengeNotifierProvider).where((c) => c.status == ChallengeStatus.completed).toList();
});
