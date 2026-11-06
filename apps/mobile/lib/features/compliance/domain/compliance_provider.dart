import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/domain/auth_provider.dart';
import '../data/compliance_service.dart';

final complianceServiceProvider =
    Provider<ComplianceService>((ref) => ComplianceService());

/// Coach's active-client adherence roster, worst-first.
final complianceRosterProvider =
    FutureProvider<List<ComplianceSummary>>((ref) async {
  ref.watch(currentUserProvider);
  return ref.watch(complianceServiceProvider).getRoster();
});
