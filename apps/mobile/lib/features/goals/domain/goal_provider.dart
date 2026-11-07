import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/domain/auth_provider.dart';
import '../data/goal_service.dart';
import '../data/models/goal.dart';

final goalServiceProvider = Provider<GoalService>((ref) => GoalService());

final myGoalsProvider = FutureProvider<List<Goal>>((ref) async {
  ref.watch(currentUserProvider);
  return ref.watch(goalServiceProvider).getMyGoals();
});
