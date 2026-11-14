import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/domain/auth_provider.dart';
import '../data/notification_service.dart';
import '../data/notification_model.dart';

final _svc = NotificationService();

final notificationsStreamProvider = StreamProvider<List<AppNotification>>((ref) {
  ref.watch(currentUserProvider);
  return _svc.streamNotifications();
});

final unreadCountProvider = FutureProvider<int>((ref) async {
  ref.watch(currentUserProvider);
  // Re-fetches whenever the stream fires (via invalidation from notifier)
  ref.watch(notificationsStreamProvider);
  return _svc.fetchUnreadCount();
});

class NotificationsNotifier extends StateNotifier<AsyncValue<List<AppNotification>>> {
  StreamSubscription? _sub;

  NotificationsNotifier() : super(const AsyncValue.loading()) {
    _load();
    // Live feed — new/updated notifications flow in without a manual refresh.
    _sub = _svc.streamNotifications().listen(
      (list) => state = AsyncValue.data(list),
      onError: (_) {/* keep last good state */});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    try {
      final list = await _svc.fetchNotifications();
      // Replaced when another account signs in, possibly mid-read.
      if (!mounted) return;
      state = AsyncValue.data(list);
    } catch (e, st) {
      if (mounted) state = AsyncValue.error(e, st);
    }
  }

  // These three say whether the server took the change, and change the list
  // only when it did. They threw: a failed delete left a row the swipe had
  // already dismissed in the tree ("A dismissed Dismissible widget is still
  // part of the tree"), still unread, with the error unhandled; a failed
  // mark-read threw from a tap.

  Future<bool> markRead(String id) async {
    try {
      await _svc.markRead(id);
    } catch (_) {
      return false;
    }
    if (mounted) {
      state = state.whenData((list) => list
          .map((n) => n.id == id ? n.copyWith(read: true) : n)
          .toList());
    }
    return true;
  }

  Future<bool> markAllRead() async {
    try {
      await _svc.markAllRead();
    } catch (_) {
      return false;
    }
    if (mounted) {
      state = state.whenData((list) => list
          .map((n) => n.copyWith(read: true))
          .toList());
    }
    return true;
  }

  Future<bool> delete(String id) async {
    try {
      await _svc.deleteNotification(id);
    } catch (_) {
      return false;
    }
    if (mounted) {
      state = state.whenData((list) => list.where((n) => n.id != id).toList());
    }
    return true;
  }

  Future<void> refresh() => _load();
}

final notificationsProvider =
    StateNotifierProvider<NotificationsNotifier, AsyncValue<List<AppNotification>>>(
      (ref) {
        // A new list for each account: the notifier holds one account's rows
        // and its stream, and outlived sign-out.
        ref.watch(currentUserProvider);
        return NotificationsNotifier();
      },
    );
