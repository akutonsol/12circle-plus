import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/observability/app_failure.dart';
import '../../auth/domain/auth_provider.dart';
import '../data/challenge_service.dart';
import '../data/live_challenge_service.dart';
import '../data/models/challenge_model.dart';

final challengeServiceProvider = Provider<ChallengeService>((ref) => ChallengeService());
final liveChallengeServiceProvider = Provider<LiveChallengeService>((ref) => LiveChallengeService());

/// Who is signed in, by id: a token refresh or a profile edit is the same
/// member, so it neither drops the list nor closes the open challenge.
final _signedInUid = Provider<String?>(
    (ref) => ref.watch(currentUserProvider.select((u) => u?.id)));

/// The challenge the member opened (their progress, joined, "You" on the
/// board). Cleared when the signed-in member changes (P0-FL-57a).
final selectedChallengeProvider = StateProvider<Challenge?>((ref) {
  ref.watch(_signedInUid);
  return null;
});
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

  /// Whether this member's list has been read. Until it has, an empty [state]
  /// is not "no challenges" (P0-FL-57a).
  bool hasLoaded = false;

  void initialize(List<Challenge> challenges) {
    hasLoaded = true;
    state = challenges;
  }

  /// The last failed join's error, for the caller's next-step hint
  /// (connection or not). Null after a join that succeeded.
  Object? lastJoinError;

  Future<bool> joinChallenge(String challengeId) async {
    try {
      await _svc.joinChallenge(challengeId);
      lastJoinError = null;
    } catch (e, st) {
      // P0-FL-53b · a failed join was swallowed unrecorded.
      reportError('ChallengeNotifier.joinChallenge', e, st);
      lastJoinError = e;
      return false;
    }
    // P0-FL-57a · the join was made, but another member has signed in since:
    // this list is gone and theirs is not marked joined.
    if (!mounted) return true;
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
    if (!mounted) return; // another member has signed in since
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

/// The signed-in member's challenges. P0-FL-57a · it was built once for the
/// app's lifetime, so the next member was shown the last one's joined state
/// and progress until their own read landed — for good if it failed. A
/// different member (or nobody) gets a new, empty notifier; the old one is
/// disposed, so nothing still in flight for it can land in the new one.
final challengeNotifierProvider = StateNotifierProvider<ChallengeNotifier, List<Challenge>>((ref) {
  ref.watch(_signedInUid);
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
