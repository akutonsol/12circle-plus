import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../../../core/observability/app_failure.dart';
import '../../auth/domain/auth_provider.dart';
import '../data/goal_service.dart';
import '../data/models/goal.dart';

final goalServiceProvider = Provider<GoalService>((ref) => GoalService());

/// One account's goals, kept by uid (P0-FL-60c): riverpod carries the last value
/// through loading, data and error alike, so a value never says whose it is.
///
/// Auto-disposed, so each visit to /goals reads them again: kept for the
/// session, a failed read would be the answer until the app restarted.
final goalsOfProvider =
    FutureProvider.autoDispose.family<List<Goal>, String?>((ref, uid) async {
  void mustBeSignedIn() {
    if (uid != null && Supabase.instance.client.auth.currentUser?.id != uid) {
      final e = StateError('reading goals: the signed-in account changed');
      reportError('goalsOfProvider', e, StackTrace.current);
      throw e;
    }
  }

  // The service reads for whoever is signed in, as the request is made.
  mustBeSignedIn();
  final goals = await ref.watch(goalServiceProvider).getMyGoals();
  mustBeSignedIn();
  return goals;
});

/// The signed-in member's goals. By uid only: a token refresh is the same
/// member, and reads nothing again.
final myGoalsProvider = Provider.autoDispose<AsyncValue<List<Goal>>>((ref) =>
    ref.watch(goalsOfProvider(ref.watch(currentUserProvider.select((u) => u?.id)))));
