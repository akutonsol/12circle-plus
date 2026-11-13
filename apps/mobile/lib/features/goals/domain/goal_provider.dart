import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/domain/auth_provider.dart';
import '../data/goal_service.dart';
import '../data/models/goal.dart';

final goalServiceProvider = Provider<GoalService>((ref) => GoalService());

/// Auto-disposed, so each visit to /goals reads them again: kept for the
/// session, a failed read would be the answer until the app restarted.
final myGoalsProvider = FutureProvider.autoDispose<List<Goal>>((ref) async {
  ref.watch(currentUserProvider);
  return ref.watch(goalServiceProvider).getMyGoals();
});
