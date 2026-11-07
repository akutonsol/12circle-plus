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
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> markRead(String id) async {
    await _svc.markRead(id);
    state = state.whenData((list) => list
        .map((n) => n.id == id ? n.copyWith(read: true) : n)
        .toList());
  }

  Future<void> markAllRead() async {
    await _svc.markAllRead();
    state = state.whenData((list) => list
        .map((n) => n.copyWith(read: true))
        .toList());
  }

  Future<void> delete(String id) async {
    await _svc.deleteNotification(id);
    state = state.whenData((list) => list.where((n) => n.id != id).toList());
  }

  Future<void> refresh() => _load();
}

final notificationsProvider =
    StateNotifierProvider<NotificationsNotifier, AsyncValue<List<AppNotification>>>(
      (_) => NotificationsNotifier(),
    );
