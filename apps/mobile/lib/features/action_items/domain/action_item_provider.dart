import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/domain/auth_provider.dart';
import '../data/action_item_service.dart';
import '../data/models/action_item.dart';

final actionItemServiceProvider =
    Provider<ActionItemService>((ref) => ActionItemService());

/// Client's own action items. Auto-disposed, so each visit reads them again:
/// kept for the session, a failed read — or the list before the coach's
/// latest task — was the answer until the app restarted.
final myActionItemsProvider =
    FutureProvider.autoDispose<List<ActionItem>>((ref) async {
  ref.watch(currentUserProvider);
  return ref.watch(actionItemServiceProvider).getMyActionItems();
});

/// Coach view: a given client's action items — those RLS shows the signed-in
/// coach, so it follows who that is (P0-FL-59f).
final clientActionItemsProvider =
    FutureProvider.family<List<ActionItem>, String>((ref, clientId) async {
  ref.watch(currentUserProvider.select((u) => u?.id));
  return ref.watch(actionItemServiceProvider).getClientActionItems(clientId);
});

/// Completion stats for a client (coach dashboard).
final actionCompletionProvider = FutureProvider.family<
    ({int assigned, int completed, double rate}), String>((ref, clientId) async {
  ref.watch(currentUserProvider.select((u) => u?.id));
  return ref.watch(actionItemServiceProvider).completionStats(clientId);
});
