import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/observability/app_failure.dart';
import '../../auth/domain/auth_provider.dart';
import '../../checkins/domain/checkin_provider.dart' show ownedRead;
import '../data/messaging_service.dart';
import '../../../core/realtime/realtime.dart';

final messagingServiceProvider = Provider<MessagingService>((ref) => MessagingService());

/// The signed-in uid, which everything below is keyed by: not the whole `User`,
/// which a token refresh or a profile edit replaces for the same member.
///
/// A provider of its own, because a `select` watched directly is not flushed
/// with a provider's dependencies: the inbox refreshed after an account change
/// and before the next frame was then a refresh by the same member to riverpod
/// 2.6.1, which handed the last member's threads over as data (P0-FL-59c).
final messagingUidProvider = Provider<String?>(
    (ref) => ref.watch(currentUserProvider.select((u) => u?.id)));

/// Whether an action built for [uid] may be taken. If not, it belonged to the
/// account that left: recorded, and nothing is said (P0-FL-59c).
bool mayActAs(String? uid, String origin, String what) {
  if (Supabase.instance.client.auth.currentUser?.id == uid) return true;
  reportError(origin, StateError('$what: the signed-in account changed'),
      StackTrace.current);
  return false;
}

/// The inbox. Its rows carry the account that read them (`OwnedRows`): being
/// keyed by the uid does not clear the screen when a refresh is in flight at the
/// switch, because riverpod 2.6.1 tells nobody when one loading state replaces
/// another, and both hold the last member's threads (P0-FL-59c).
final conversationsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  ref.watch(currentUserProvider.select((u) => u?.id));
  ref.watch(messagingUidProvider);
  ref.watch(tableTickerProvider('messages'));       // live: new messages
  ref.watch(tableTickerProvider('conversations'));  // live: new conversations
  return ownedRead(ref.watch(messagingServiceProvider).getConversations);
});

/// One member's unread count, kept under that member's uid. Not asked for while
/// anyone else is signed in: the read answers for whoever is, when it is sent.
final _unreadCountOf =
    FutureProvider.autoDispose.family<int, String?>((ref, uid) async {
  if (uid == null) return 0;
  ref.watch(tableTickerProvider('messages'));
  final service = ref.watch(messagingServiceProvider);
  if (Supabase.instance.client.auth.currentUser?.id != uid) {
    throw StateError('unread count not read: the signed-in account changed');
  }
  return service.getUnreadCount();
});

/// The signed-in member's unread count. By uid (P0-FL-59c): as one provider it
/// held the last member's number while the next one's read was pending or had
/// failed, and the Messages badge shows whatever it holds.
final unreadCountProvider = Provider.autoDispose<AsyncValue<int>>(
    (ref) => ref.watch(_unreadCountOf(ref.watch(messagingUidProvider))));

// Holds the currently selected conversation context for ChatScreen.
// Set before navigating to /chat so the screen knows who it's talking to.
//
// Keyed by the signed-in uid (P0-FL-59c): it outlived a switch, so the next
// account's /chat opened the last one's conversation. The uid only, so a token
// refresh does not drop the member's own selection.
final selectedConversationProvider = StateProvider<Map<String, dynamic>?>((ref) {
  ref.watch(messagingUidProvider);
  return null;
});

/// Whether the conversation row [conv] is one of [uid]'s. A row from the inbox
/// names its two participants; a context that names none (a person to message,
/// with no thread yet) is nobody's row. The list a row is tapped in can be older
/// than the account that taps it.
bool conversationIsOf(Map<String, dynamic>? conv, String? uid) {
  final ids = [conv?['participant_1'], conv?['participant_2']].nonNulls;
  return ids.isEmpty || ids.contains(uid);
}
