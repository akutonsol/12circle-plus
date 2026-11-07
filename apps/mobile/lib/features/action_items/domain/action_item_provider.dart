import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/domain/auth_provider.dart';
import '../data/action_item_service.dart';
import '../data/models/action_item.dart';

final actionItemServiceProvider =
    Provider<ActionItemService>((ref) => ActionItemService());

/// Client's own action items.
final myActionItemsProvider = FutureProvider<List<ActionItem>>((ref) async {
  ref.watch(currentUserProvider);
  return ref.watch(actionItemServiceProvider).getMyActionItems();
});

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
