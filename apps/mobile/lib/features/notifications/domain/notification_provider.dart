import 'dart:async';
import 'package:flutter/foundation.dart' show AsyncCallback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../../../core/observability/app_failure.dart';
import '../../auth/domain/auth_provider.dart';
import '../data/notification_service.dart';
import '../data/notification_model.dart';

final _svc = NotificationService();

// All three follow who is signed in BY ID (P0-FL-60c): a token refresh is the
// same member, and keeps their list and its live feed.

final notificationsStreamProvider = StreamProvider<List<AppNotification>>((ref) {
  ref.watch(currentUserProvider.select((u) => u?.id));
  return _svc.streamNotifications();
});

final unreadCountProvider = FutureProvider<int>((ref) async {
  ref.watch(currentUserProvider.select((u) => u?.id));
  // Re-fetches whenever the stream fires (via invalidation from notifier)
  ref.watch(notificationsStreamProvider);
  return _svc.fetchUnreadCount();
});

typedef _ListEdit = List<AppNotification> Function(List<AppNotification>);

class NotificationsNotifier extends StateNotifier<AsyncValue<List<AppNotification>>> {
  StreamSubscription? _sub;

  /// Whose list this is. Nothing is read into it, or written from it, once
  /// another account is signed in.
  final String? _owner = _currentUid();

  static String? _currentUid() => Supabase.instance.client.auth.currentUser?.id;
  bool get _isOwners => mounted && _currentUid() == _owner;

  NotificationsNotifier() : super(const AsyncValue.loading()) {
    _load();
    // Live feed — new/updated notifications flow in without a manual refresh.
    _sub = _svc.streamNotifications().listen(
      (list) {
        if (_isOwners) state = AsyncValue.data(list);
      },
      onError: (Object e, StackTrace st) {
        // Keep the last good state; the stream reopens itself.
        reportError('NotificationsNotifier.stream', e, st);
      });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// The list that was read, if any — kept through a failed refresh.
  List<AppNotification>? get _shown => state.hasValue ? state.requireValue : null;

  Future<void> _load() async {
    if (!_isOwners) return;
    state = const AsyncValue<List<AppNotification>>.loading().copyWithPrevious(state);
    try {
      final list = await _svc.fetchNotifications();
      // Replaced when another account signs in, possibly mid-read.
      if (!_isOwners) return;
      state = AsyncValue.data(list);
    } catch (e, st) {
      reportError('NotificationsNotifier.load', e, st);
      if (_isOwners) {
        state = AsyncValue<List<AppNotification>>.error(e, st).copyWithPrevious(state);
      }
    }
  }

  // These three say whether the server took the change, and change the list
  // only when it did. They threw: a failed delete left a row the swipe had
  // already dismissed in the tree ("A dismissed Dismissible widget is still
  // part of the tree"), still unread, with the error unhandled; a failed
  // mark-read threw from a tap. A failure is recorded here (P0-FL-60c).

  /// Why the last change failed, for the next step the screen says.
  Object? lastError;

  Future<bool> _change(
      String origin, AsyncCallback write, _ListEdit apply) async {
    try {
      await write();
    } catch (e, st) {
      reportError('NotificationsNotifier.$origin', e, st);
      lastError = e;
      return false;
    }
    final shown = mounted ? _shown : null;
    if (shown != null) state = AsyncValue.data(apply(shown));
    return true;
  }

  Future<bool> markRead(String id) => _change(
      'markRead',
      () => _svc.markRead(id, owner: _owner),
      (list) => list
          .map((n) => n.id == id ? n.copyWith(read: true) : n)
          .toList());

  Future<bool> markAllRead() => _change(
      'markAllRead',
      () => _svc.markAllRead(owner: _owner),
      (list) => list.map((n) => n.copyWith(read: true)).toList());

  Future<bool> delete(String id) => _change(
      'delete',
      () => _svc.deleteNotification(id, owner: _owner),
      (list) => list.where((n) => n.id != id).toList());

  Future<void> refresh() => _load();
}

final notificationsProvider =
    StateNotifierProvider<NotificationsNotifier, AsyncValue<List<AppNotification>>>(
      (ref) {
        // A new list for each account: the notifier holds one account's rows
        // and its stream, and outlived sign-out.
        ref.watch(currentUserProvider.select((u) => u?.id));
        return NotificationsNotifier();
      },
    );
