import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/package_service.dart';

final packageServiceProvider = Provider<PackageService>((ref) => PackageService());

/// The signed-in coach's own packages.
final myPackagesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(packageServiceProvider).getMyPackages();
});

/// A coach's active packages, for clients browsing/selecting.
final coachPackagesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, coachId) async {
  return ref.watch(packageServiceProvider).getCoachPackages(coachId);
});

/// The signed-in client's current schedule (null if not set).
final myScheduleProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  return ref.watch(packageServiceProvider).getMySchedule();
});

/// Coach view: a specific client's training schedule.
final clientScheduleProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>?, String>((ref, clientId) async {
  return ref.watch(packageServiceProvider).getClientSchedule(clientId);
});
