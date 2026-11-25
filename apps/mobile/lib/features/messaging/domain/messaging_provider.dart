import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/domain/auth_provider.dart';
import '../data/messaging_service.dart';
import '../../../core/realtime/realtime.dart';

final messagingServiceProvider = Provider<MessagingService>((ref) => MessagingService());

final conversationsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  ref.watch(currentUserProvider);
  ref.watch(tableTickerProvider('messages'));       // live: new messages
  ref.watch(tableTickerProvider('conversations'));  // live: new conversations
  return ref.watch(messagingServiceProvider).getConversations();
});

final unreadCountProvider = FutureProvider<int>((ref) async {
  ref.watch(currentUserProvider);
  ref.watch(tableTickerProvider('messages'));
  return ref.watch(messagingServiceProvider).getUnreadCount();
});

// Holds the currently selected conversation context for ChatScreen.
// Set before navigating to /chat so the screen knows who it's talking to.
//
// Keyed by the signed-in uid (P0-FL-59c): it outlived a switch, so the next
// account's /chat opened the last one's conversation. The uid only, so a token
// refresh does not drop the member's own selection.
final selectedConversationProvider = StateProvider<Map<String, dynamic>?>((ref) {
  ref.watch(currentUserProvider.select((u) => u?.id));
  return null;
});
