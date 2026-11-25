import 'dart:async';
import 'package:flutter/foundation.dart' show AsyncCallback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../../../core/observability/app_failure.dart';
import '../../auth/domain/auth_provider.dart';
import '../data/notification_service.dart';
import '../data/notification_model.dart';

final _svc = NotificationService();

/// Who is signed in, BY ID (P0-FL-60c): a token refresh is the same member, and
/// keeps their list, their count and their live feed.
final _uid = currentUserProvider.select((u) => u?.id);

// P0-FL-60c · whose a value is never follows from loading/data/error: riverpod
// carries the last value through all three. The feed is kept per account; the
// count remembers whose it was and is forgotten for anybody else.

final _feedOf =
    StreamProvider.autoDispose.family<List<AppNotification>, String>(
        (ref, uid) => _svc.streamNotifications(owner: uid));

/// The signed-in member's live feed; nothing while nobody is signed in.
final notificationsStreamProvider =
    Provider<AsyncValue<List<AppNotification>>>((ref) {
  final uid = ref.watch(_uid);
  return uid == null ? const AsyncLoading() : ref.watch(_feedOf(uid));
});

class _CountOwner {
  bool read = false;
  String? uid;
}

final _countOwner = Provider<_CountOwner>((ref) => _CountOwner());

/// The signed-in member's unread count; null while it is not known (nobody is
/// signed in, or their own count was never read).
final unreadCountProvider = FutureProvider<int?>((ref) async {
  final uid = ref.watch(_uid);
  // Re-fetches whenever the stream fires (via invalidation from notifier)
  ref.watch(notificationsStreamProvider);
  final last = ref.read(_countOwner);
  if (last.read && last.uid != uid) {
    // Not loading: a reload of the last account's count to a load of this
    // one's would not be announced, and the badge would keep the old number.
    ref.state = const AsyncData(null);
  }
  last
    ..read = true
    ..uid = uid;
  if (uid == null) return null;
  try {
    return await _svc.fetchUnreadCount(owner: uid);
  } catch (e, st) {
    reportError('unreadCountProvider', e, st);
    // Not uid's to be told any more, and nothing of theirs is kept.
    if (Supabase.instance.client.auth.currentUser?.id != uid) return null;
    rethrow;
  }
});

typedef _ListEdit = List<AppNotification> Function(List<AppNotification>);

class NotificationsNotifier extends StateNotifier<AsyncValue<List<AppNotification>>> {
  StreamSubscription? _sub;

  /// Whose list this is. Nothing is read into it, or written from it, once
  /// another account is signed in.
  final String? owner = _currentUid();

  static String? _currentUid() => Supabase.instance.client.auth.currentUser?.id;
  bool get _isOwners => mounted && _currentUid() == owner;

  NotificationsNotifier() : super(const AsyncValue.loading()) {
    _load();
    // Live feed — new/updated notifications flow in without a manual refresh.
    // It carries nothing once another account is signed in.
    _sub = _svc.streamNotifications(owner: owner).listen(
      (list) => state = AsyncValue.data(list),
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
    final shown = _isOwners ? _shown : null;
    if (shown != null) _show(apply(shown));
    return true;
  }

  /// The changed list; a refresh still running, or one that failed, is still
  /// that — the rest of the list is no newer for it.
  void _show(List<AppNotification> list) {
    final was = state;
    AsyncValue<List<AppNotification>> next = AsyncValue.data(list);
    if (was is AsyncError<List<AppNotification>>) {
      next = AsyncValue<List<AppNotification>>.error(was.error, was.stackTrace)
          .copyWithPrevious(next);
    }
    state = was.isLoading
        ? const AsyncValue<List<AppNotification>>.loading().copyWithPrevious(next)
        : next;
  }

  Future<bool> markRead(String id) => _change(
      'markRead',
      () => _svc.markRead(id, owner: owner),
      (list) => list
          .map((n) => n.id == id ? n.copyWith(read: true) : n)
          .toList());

  Future<bool> markAllRead() => _change(
      'markAllRead',
      () => _svc.markAllRead(owner: owner),
      (list) => list.map((n) => n.copyWith(read: true)).toList());

  Future<bool> delete(String id) => _change(
      'delete',
      () => _svc.deleteNotification(id, owner: owner),
      (list) => list.where((n) => n.id != id).toList());

  Future<void> refresh() => _load();
}

final notificationsProvider =
    StateNotifierProvider<NotificationsNotifier, AsyncValue<List<AppNotification>>>(
      (ref) {
        // A new list for each account: the notifier holds one account's rows
        // and its stream, and outlived sign-out.
        ref.watch(_uid);
        return NotificationsNotifier();
      },
    );
