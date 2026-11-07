import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/domain/auth_provider.dart';
import '../data/cycle_service.dart';
import 'cycle_phase.dart';

final cycleServiceProvider = Provider<CycleService>((ref) => CycleService());

/// Bumped after a log/setting change to refresh everything.
final cycleRefreshProvider = StateProvider<int>((ref) => 0);

/// The computed current cycle status (phase, day, predictions) from the latest
/// period + the user's averages.
final cycleStatusProvider = FutureProvider<CycleStatus>((ref) async {
  ref.watch(currentUserProvider);
  ref.watch(cycleRefreshProvider);
  final svc = ref.watch(cycleServiceProvider);
  final settings = await svc.getSettings();
  final periods = await svc.getPeriods(limit: 1);
  DateTime? lastStart;
  if (periods.isNotEmpty) {
    lastStart = DateTime.tryParse(periods.first['start_date'] as String? ?? '');
  }
  return computeCycleStatus(
    lastPeriodStart: lastStart,
    cycleLength: (settings?['avg_cycle_length'] as num?)?.toInt() ?? 28,
    periodLength: (settings?['avg_period_length'] as num?)?.toInt() ?? 5,
  );
});

final recentSymptomsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  ref.watch(currentUserProvider);
  ref.watch(cycleRefreshProvider);
  return ref.watch(cycleServiceProvider).getRecentSymptoms();
});

final todaySymptomsProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  ref.watch(currentUserProvider);
  ref.watch(cycleRefreshProvider);
  return ref.watch(cycleServiceProvider).getSymptomsForDate(DateTime.now());
});
