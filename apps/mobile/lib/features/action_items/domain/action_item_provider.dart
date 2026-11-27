import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/action_item_service.dart';
import '../data/models/action_item.dart';
import '../../nutrition/domain/nutrition_provider.dart' show readForMember;

final actionItemServiceProvider =
    Provider<ActionItemService>((ref) => ActionItemService());

/// Client's own action items. Auto-disposed, so each visit reads them again:
/// kept for the session, a failed read — or the list before the coach's
/// latest task — was the answer until the app restarted. Drawn through
/// `ownRead`: kept with the member it was read for.
final myActionItemsProvider = FutureProvider.autoDispose<List<ActionItem>>(
    (ref) => readForMember(
        ref, ref.watch(actionItemServiceProvider).getMyActionItems));

/// Coach view: a given client's action items — those RLS shows the signed-in
/// coach, so it follows who that is (P0-FL-59f).
///
/// P0-FL-62c: keyed by the client only, so the answer is marked with the coach
/// it was read for ([readForMember], which also reads again the moment the
/// auth client names someone else). Riverpod keeps coach A's answer, and A's
/// failure, through coach B's read of the same client: whatever draws this
/// draws it through `ownRead`, which gives B nothing of A's. (Nothing in lib
/// draws it today; the assign sheet only invalidates it.)
final clientActionItemsProvider =
    FutureProvider.family<List<ActionItem>, String>((ref, clientId) {
  final service = ref.watch(actionItemServiceProvider);
  return readForMember(ref, () => service.getClientActionItems(clientId));
});

/// A client's action-item completion, as one coach was shown it. A class, not
/// a record: an answer is marked with its reader beside it ([readForMember]),
/// and a record cannot carry that mark.
final class ActionCompletion {
  final int assigned;
  final int completed;
  final double rate;
  const ActionCompletion(
      {required this.assigned, required this.completed, required this.rate});
}

/// Completion stats for a client (coach dashboard). Marked with the coach it
/// was read for, as [clientActionItemsProvider] is (P0-FL-62c).
final actionCompletionProvider =
    FutureProvider.family<ActionCompletion, String>((ref, clientId) {
  final service = ref.watch(actionItemServiceProvider);
  return readForMember(ref, () async {
    final s = await service.completionStats(clientId);
    return ActionCompletion(
        assigned: s.assigned, completed: s.completed, rate: s.rate);
  });
});
