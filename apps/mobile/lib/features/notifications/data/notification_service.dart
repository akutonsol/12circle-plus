import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
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

  /// The signed-in user's notifications, live, for as long as it is listened
  /// to.
  ///
  /// supabase's `.stream()` ends for good when one of its reads fails: it
  /// unsubscribes and closes on a failed fetch, at start or on a reconnect.
  /// Returned as it was, one offline moment froze the bell badge (re-counted
  /// only when this emits) and the open Notifications list for the rest of
  /// the session. When it ends it is now opened again, backing off while it
  /// keeps failing. Errors are still passed on.
  Stream<List<AppNotification>> streamNotifications() {
    final uid = _uid;
    if (uid == null) return const Stream.empty();
    late final StreamController<List<AppNotification>> out;
    StreamSubscription<List<AppNotification>>? sub;
    Timer? retry;
    var delay = _firstRetry;
    void open() {
      sub = _db
          .from('notifications')
          .stream(primaryKey: ['id'])
          .eq('recipient_id', uid)
          .order('created_at', ascending: false)
          .map((rows) => rows.map(AppNotification.fromJson).toList())
          .listen(
        (list) {
          delay = _firstRetry;
          out.add(list);
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

  Future<int> fetchUnreadCount() async {
    final uid = _uid;
    if (uid == null) return 0;
    final rows = await _db
        .from('notifications')
        .select('id')
        .eq('recipient_id', uid)
        .eq('read', false);
    return (rows as List).length;
  }

  Future<void> markRead(String id) async {
    await _db.from('notifications').update({'read': true}).eq('id', id);
  }

  Future<void> markAllRead() async {
    final uid = _uid;
    if (uid == null) return;
    await _db
        .from('notifications')
        .update({'read': true})
        .eq('recipient_id', uid)
        .eq('read', false);
  }

  Future<void> deleteNotification(String id) async {
    await _db.from('notifications').delete().eq('id', id);
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
  /// client -> coach). Never throws so callers can fire-and-forget.
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
    } catch (_) {
      // ignore notification failures
    }
  }
}
