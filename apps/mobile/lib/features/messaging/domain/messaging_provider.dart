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
final selectedConversationProvider = StateProvider<Map<String, dynamic>?>((ref) => null);
