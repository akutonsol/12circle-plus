import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/domain/auth_provider.dart';
import '../../dashboard/domain/still_reading.dart';
import '../data/compliance_service.dart';

final complianceServiceProvider =
    Provider<ComplianceService>((ref) => ComplianceService());

/// Coach's active-client adherence roster, worst-first.
///
/// P0-FL-59f: follows the coach by id (a refreshed token reads nothing again)
/// and its rows, and its failure, are marked as theirs: Riverpod keeps both
/// through a change of account. The service answers for whoever is signed in
/// as it asks, so an answer asked across a change is nobody's.
final complianceRosterProvider =
    FutureProvider<List<ComplianceSummary>>((ref) async {
  final uid = ref.watch(currentUserProvider.select((u) => u?.id));
  final service = ref.watch(complianceServiceProvider);
  return ownedRead(uid, () async {
    void stillTheirs() {
      if (!accountLeft(uid)) return;
      throw StateError('compliance roster: the signed-in account changed');
    }

    stillTheirs();
    final roster = await service.getRoster();
    stillTheirs();
    return roster;
  });
});
