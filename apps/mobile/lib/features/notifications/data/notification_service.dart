import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/observability/app_failure.dart';
import 'notification_model.dart';

class NotificationService {
  final _db = Supabase.instance.client;

  String? get _uid => _db.auth.currentUser?.id;

  Future<List<AppNotification>> fetchNotifications({int limit = 50}) async {
    final uid = _uid;
    if (uid == null) return [];
    final rows = await _db
        .from('notifications')
        .select()
        .eq('recipient_id', uid)
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List).map((r) => AppNotification.fromJson(r)).toList();
  }

  static const _firstRetry = Duration(seconds: 2);
  static const _maxRetry = Duration(minutes: 1);

  /// [owner]'s notifications, live, for as long as it is listened to; nothing
  /// while somebody else, or nobody, is signed in (P0-FL-60c).
  ///
  /// supabase's `.stream()` ends for good when one of its reads fails: it
  /// unsubscribes and closes on a failed fetch, at start or on a reconnect.
  /// Returned as it was, one offline moment froze the bell badge (re-counted
  /// only when this emits) and the open Notifications list for the rest of
  /// the session. When it ends it is now opened again, backing off while it
  /// keeps failing. Errors are still passed on.
  Stream<List<AppNotification>> streamNotifications({required String? owner}) {
    if (owner == null || _uid != owner) return const Stream.empty();
    late final StreamController<List<AppNotification>> out;
    StreamSubscription<List<AppNotification>>? sub;
    Timer? retry;
    var delay = _firstRetry;
    void open() {
      sub = _db
          .from('notifications')
          .stream(primaryKey: ['id'])
          .eq('recipient_id', owner)
          .order('created_at', ascending: false)
          .map((rows) => rows.map(AppNotification.fromJson).toList())
          .listen(
        (list) {
          delay = _firstRetry;
          if (_uid == owner) out.add(list);
        },
        onError: out.addError,
        onDone: () {
          if (out.isClosed) return;
          retry = Timer(delay, open);
          delay = delay * 2 > _maxRetry ? _maxRetry : delay * 2;
        },
      );
    }

    out = StreamController<List<AppNotification>>(
      onListen: open,
      onCancel: () {
        retry?.cancel();
        out.close();
        return sub?.cancel();
      },
    );
    return out.stream;
  }

  /// [owner]'s; throws when it is no longer [owner] who is signed in, before
  /// the read or by the time it answers: the count would be somebody else's.
  Future<int> fetchUnreadCount({required String owner}) async {
    _mustBeSignedIn(owner, 'counting unread notifications');
    final rows = await _db
        .from('notifications')
        .select('id')
        .eq('recipient_id', owner)
        .eq('read', false);
    _mustBeSignedIn(owner, 'counting unread notifications');
    return (rows as List).length;
  }

  // P0-FL-60c · the three changes below are made for [owner], the account
  // whose list is on screen. Once another account is signed in nothing is
  // sent, and a change the server made to no row throws: no error is raised
  // for one.

  void _mustBeSignedIn(String? owner, String what) {
    if (owner == null || _uid != owner) {
      throw StateError('$what: the signed-in account changed');
    }
  }

  Future<void> markRead(String id, {required String? owner}) async {
    _mustBeSignedIn(owner, 'marking a notification read');
    final rows = await _db
        .from('notifications')
        .update({'read': true})
        .eq('id', id)
        .eq('recipient_id', owner!)
        .select('id');
    if (rows.isEmpty) throw StateError('no notification was marked read');
  }

  Future<void> markAllRead({required String? owner}) async {
    _mustBeSignedIn(owner, 'marking all notifications read');
    final rows = await _db
        .from('notifications')
        .update({'read': true})
        .eq('recipient_id', owner!)
        .eq('read', false)
        .select('id');
    if (rows.isNotEmpty) return;
    // Nothing changed: either nothing was unread (fine), or the change was
    // refused in silence. Asked as the same member, or not asked.
    _mustBeSignedIn(owner, 'marking all notifications read');
    final unread = await _db
        .from('notifications')
        .select('id')
        .eq('recipient_id', owner)
        .eq('read', false);
    if (unread.isNotEmpty) {
      throw StateError('no notification was marked read');
    }
  }

  Future<void> deleteNotification(String id, {required String? owner}) async {
    _mustBeSignedIn(owner, 'deleting a notification');
    final rows = await _db
        .from('notifications')
        .delete()
        .eq('id', id)
        .eq('recipient_id', owner!)
        .select('id');
    if (rows.isEmpty) throw StateError('no notification was deleted');
  }

  // Insert a test notification (used from settings / debug)
  Future<void> insertTestNotification({
    required String type,
    required String title,
    required String body,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    await _db.from('notifications').insert({
      'recipient_id': uid,
      'type': type,
      'title': title,
      'body': body,
      'read': false,
    });
  }

  /// Send a notification to an arbitrary recipient (e.g. coach -> client,
  /// client -> coach). Never throws so callers can fire-and-forget: a failure
  /// is recorded here, and is NOT a delivery — a caller that means to say
  /// "notified" cannot learn that from this.
  Future<void> notifyUser({
    required String recipientId,
    required String type,
    required String title,
    required String body,
  }) async {
    try {
      await _db.from('notifications').insert({
        'recipient_id': recipientId,
        'type': type,
        'title': title,
        'body': body,
        'read': false,
      });
    } catch (e, st) {
      reportError('NotificationService.notifyUser', e, st);
    }
  }
}
