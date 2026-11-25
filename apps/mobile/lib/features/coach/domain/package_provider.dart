import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/observability/app_failure.dart';
import '../../auth/domain/auth_provider.dart';
import '../../dashboard/domain/still_reading.dart' show readAsClientPageOwner;
import '../data/package_service.dart';

final packageServiceProvider = Provider<PackageService>((ref) => PackageService());

/// P0-FL-56b: a failed read reaches its screen as an error (said there with a
/// retry) and is recorded here, once, rather than by each screen.
Future<T> _recorded<T>(String origin, Future<T> Function() read) async {
  try {
    return await read();
  } catch (e, st) {
    reportError(origin, e, st);
    rethrow;
  }
}

/// The signed-in coach's own packages.
final myPackagesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  ref.watch(currentUserProvider);
  final svc = ref.watch(packageServiceProvider);
  // Called, not torn off: per_user_provider_scope_test finds a delegated user
  // read by its call, and a tear-off hid this provider from it.
  return _recorded('myPackagesProvider', () => svc.getMyPackages());
});

/// A coach's active packages, for clients browsing/selecting.
final coachPackagesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, coachId) async {
  final svc = ref.watch(packageServiceProvider);
  return _recorded('coachPackagesProvider', () => svc.getCoachPackages(coachId));
});

/// The signed-in client's current schedule (null if not set).
final myScheduleProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  ref.watch(currentUserProvider);
  final svc = ref.watch(packageServiceProvider);
  return _recorded('myScheduleProvider', () => svc.getMySchedule());
});

/// Coach view: a specific client's training schedule.
final clientScheduleProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>?, String>((ref, clientId) async {
  // P0-FL-59f: RLS answers for the signed-in coach (by id: see clientDetailProvider).
  readAsClientPageOwner(ref, clientId);
  final svc = ref.watch(packageServiceProvider);
  return _recorded('clientScheduleProvider', () => svc.getClientSchedule(clientId));
});
