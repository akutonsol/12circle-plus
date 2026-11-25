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

/// Coach view: a given client's action items.
final clientActionItemsProvider =
    FutureProvider.family<List<ActionItem>, String>((ref, clientId) async {
  return ref.watch(actionItemServiceProvider).getClientActionItems(clientId);
});

/// Completion stats for a client (coach dashboard).
final actionCompletionProvider = FutureProvider.family<
    ({int assigned, int completed, double rate}), String>((ref, clientId) async {
  return ref.watch(actionItemServiceProvider).completionStats(clientId);
});
