import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/observability/app_failure.dart';

/// Receives what a send caught when the message was NOT saved, so the caller
/// can pick the connection hint (`isNetworkFailure`) or the try-later one.
///
/// A typedef, not an inline `void Function(Object)`: ERR-G1's declaration
/// detector reads a parameter list up to the first `)`, and an inline function
/// type would hide `sendMessage` from it.
typedef SendFailureHandler = void Function(Object error);

class MessagingService {
  final supabase = Supabase.instance.client;

  /// P0-FL-59c · every write below takes the signed-in uid synchronously, when
  /// it is called, and asks this again before each further step: after an await
  /// someone else may be signed in, and the step would run as them.
  bool _stillSignedIn(String userId) => supabase.auth.currentUser?.id == userId;

  // ── Conversations ─────────────────────────────────────────────────────────
  // Table schema: id, participant_1, participant_2, last_message, last_message_at

  /// Returns all conversations for the current user, each enriched with the
  /// other participant's display profile.
  ///
  /// Reads conversation_participant_profiles, NOT user_profiles: migration 102
  /// restricts the base table to the owner and their coach, and messaging has
  /// no business seeing a partner's contact, medical or billing columns. The
  /// view is row-scoped by shares_conversation_with(), so an id smuggled into
  /// `otherIds` that the caller shares no conversation with returns nothing.
  Future<List<Map<String, dynamic>>> getConversations() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return [];
    try {
      final convs = await supabase
          .from('conversations')
          .select('id, participant_1, participant_2, last_message, last_message_at')
          .or('participant_1.eq.$userId,participant_2.eq.$userId')
          .order('last_message_at', ascending: false);

      if ((convs as List).isEmpty) return [];

      final otherIds = convs.map<String>((c) =>
        c['participant_1'] == userId
          ? c['participant_2'] as String
          : c['participant_1'] as String
      ).toSet().toList();

      final profiles = await supabase
          .from('conversation_participant_profiles')
          .select('id, first_name, last_name, role, avatar_url')
          .inFilter('id', otherIds);

      final profileMap = <String, Map<String, dynamic>>{
        for (final p in profiles) p['id'] as String: p,
      };

      return convs.map<Map<String, dynamic>>((c) {
        final otherId = c['participant_1'] == userId
            ? c['participant_2'] as String
            : c['participant_1'] as String;
        return {
          ...Map<String, dynamic>.from(c),
          'participant': profileMap[otherId],
        };
      }).toList();
    } catch (e) {
      // P0-FL-13: recorded, then PROPAGATED. Returning `[]` here put "No
      // conversations yet" in front of a member whose inbox had simply failed
      // to load. The inbox screen states the failure and offers Try again.
      //
      // Kept as `reportError('<origin>', e);` on purpose: it is one of the
      // eleven mutation anchors `tool/negative_control/ec23_negative_control.sh`
      // counts, and `error_sink_test` pins this origin as a reporting site.
      reportError('MessagingService.getConversations', e);
      rethrow;
    }
  }

  /// For a CLIENT: finds or creates a conversation with the first available coach.
  Future<String?> getOrCreateClientCoachConversation() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return null;
    try {
      // Message the client's ASSIGNED coach — the active (accepted) relationship,
      // most recently activated — NOT just the first coach on the platform.
      final rel = await supabase
          .from('coach_client_relationships')
          .select('coach_id')
          .eq('client_id', userId)
          .eq('status', 'active')
          .order('activated_at', ascending: false, nullsFirst: false)
          .limit(1)
          .maybeSingle();
      final coachId = rel?['coach_id'] as String?;
      if (coachId == null) return null; // no accepted coach yet
      if (!_stillSignedIn(userId)) {
        // The RPC takes its caller from the session, and checks no relationship:
        // it would open a thread between the NEW account and this coach.
        throw StateError('conversation not opened: the signed-in account changed');
      }
      return getOrCreateConversationWith(coachId);
    } catch (e) {
      reportError('MessagingService.getOrCreateClientCoachConversation', e);
      return null;
    }
  }

  /// Finds (or creates) the 1:1 conversation between the current user and a
  /// specific other participant (e.g. a chosen coach).
  ///
  /// One RPC, not a check-then-insert. The read and the insert used to be two
  /// round trips with no arbiter between them, so two devices — or this method
  /// and [getOrCreateCoachClientConversation], which is the same operation
  /// entered from the coach's side — could each create a thread for one pair
  /// and split the message history in half with no error anywhere (I-NOT-05).
  /// `get_or_create_conversation` (migration 131) does both under the unique
  /// participant-pair index, so a race resolves to one id instead of two rows.
  Future<String?> getOrCreateConversationWith(String otherUserId) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return null;
    try {
      final id = await _getOrCreateConversation(otherUserId);
      if (!_stillSignedIn(userId)) {
        throw StateError('conversation not handed over: the signed-in account changed');
      }
      return id;
    } catch (e) {
      reportError('MessagingService.getOrCreateConversationWith', e);
      return null;
    }
  }

  /// For a COACH: finds or creates a conversation with a specific client.
  ///
  /// The same operation as [getOrCreateConversationWith], entered from the
  /// other side. Both now go through the one RPC, which is what I-NOT-05's
  /// fix means by "collapse both Dart paths": the participant pair is
  /// unordered, so which party is `participant_1` must not decide whether a
  /// second thread gets created.
  Future<String?> getOrCreateCoachClientConversation(String clientId) async {
    final coachId = supabase.auth.currentUser?.id;
    if (coachId == null) return null;
    try {
      final id = await _getOrCreateConversation(clientId);
      if (!_stillSignedIn(coachId)) {
        throw StateError('conversation not handed over: the signed-in account changed');
      }
      return id;
    } catch (e) {
      reportError('MessagingService.getOrCreateCoachClientConversation', e);
      return null;
    }
  }

  /// The single arbiter for "the conversation between me and [otherUserId]".
  ///
  /// **Propagates.** Each caller catches under its own name, which is what
  /// keeps the two entry points distinguishable in the failure sink — and what
  /// keeps them anchorable. `ec23_negative_control.sh` reproduces the seven
  /// pre-ERR-1 `print()` offenders by matching `reportError('<literal>', e);`
  /// in this file and `checkin_service.dart`; a single reporter taking the
  /// origin as a *parameter* is invisible to that regex, and collapsing these
  /// two catches into one is what took the harness's anchor set from 7 to 5.
  /// The RPC consolidation I-NOT-05 requires is unaffected: there is still
  /// exactly one path to `get_or_create_conversation` and no check-then-insert
  /// anywhere.
  ///
  /// `participant_1` is `auth.uid()` inside the RPC and is not a parameter, so
  /// this cannot open a conversation on someone else's behalf.
  Future<String?> _getOrCreateConversation(String otherUserId) async {
    final id = await supabase.rpc(
      'get_or_create_conversation',
      params: {'other_user': otherUserId},
    );
    return id as String?;
  }

  // ── Messages ──────────────────────────────────────────────────────────────

  /// Saves one message. `true` means the message ROW is saved; `false` means
  /// it is not, and [onNotSent] (when given) receives the caught error so the
  /// caller can tell a connection failure from any other.
  ///
  /// P0-FL-13 · two writes, two meanings. The `messages` insert IS the send.
  /// The `conversations` update after it only refreshes the inbox preview
  /// (`last_message` / `last_message_at`); no trigger maintains those columns
  /// server-side (migration 004's `notify_on_message` is the only trigger on
  /// `messages`). The two used to share one catch, so a saved message whose
  /// preview update failed came back as "not sent": the chat took the bubble
  /// away and handed the text back, and sending it again stored it twice. Now
  /// a preview failure — a 0-row update included — is recorded and the send
  /// still reports success.
  Future<bool> sendMessage({
    required String conversationId,
    required String content,
    Map<String, dynamic>? metadata,
    SendFailureHandler? onNotSent,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return false;
    // UTC, stated. Both columns are timestamptz, which reads a time with no zone
    // as UTC: local time written that way recorded the wrong moment.
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      final row = <String, dynamic>{
        'conversation_id': conversationId,
        'sender_id': userId,
        'content': content,
        'is_read': false,
        'sent_at': now,
      };
      if (metadata != null) row['metadata'] = metadata;
      await supabase.from('messages').insert(row);
    } catch (e, st) {
      // Not saved. Recorded (this catch used to record nothing) and handed to
      // the caller, which picks the connection hint or the try-later one.
      reportError('MessagingService.sendMessage', e, st);
      onNotSent?.call(e);
      return false;
    }
    // Recipient notification is handled server-side by the
    // trg_notify_on_message DB trigger (MSG-003) — no Dart-side insert here,
    // otherwise the recipient would get two notifications per message.
    if (!_stillSignedIn(userId)) {
      // The message is saved as its sender; the preview would go out as the
      // account that arrived meanwhile.
      reportError(
        'MessagingService.sendMessage.preview',
        StateError('conversation preview not updated: the signed-in account changed'),
        StackTrace.current,
      );
      return true;
    }
    try {
      final updated = await supabase.from('conversations').update({
        'last_message': content,
        'last_message_at': now,
      }).eq('id', conversationId).select('id');
      if ((updated as List).isEmpty) {
        // RLS or a wrong id filtered the update to nothing: the preview is
        // stale. Recorded; the message itself is saved.
        reportError(
          'MessagingService.sendMessage.preview',
          StateError('conversation preview update changed no row'),
          StackTrace.current,
        );
      }
    } catch (e, st) {
      reportError('MessagingService.sendMessage.preview', e, st);
    }
    return true;
  }

  /// A thread's messages, oldest first. **The error propagates** (EC-13): this
  /// returned `[]` on failure, so a thread that did not load read as one with
  /// nothing in it — "Start the conversation!" — and a client concluded their
  /// coach had never replied. The chat screen states the failure instead.
  Future<List<Map<String, dynamic>>> getMessages(String conversationId) async {
    final data = await supabase
        .from('messages')
        .select()
        .eq('conversation_id', conversationId)
        .order('sent_at', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }

  Stream<List<Map<String, dynamic>>> messagesStream(String conversationId) {
    // `ascending` must be stated: the stream's `.order()` defaults to descending,
    // unlike the query's. This replaces what `getMessages` loaded, so the two have
    // to agree, and the chat expects the newest message last.
    return supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('sent_at', ascending: true);
  }

  Future<void> markAsRead(String conversationId) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await supabase
          .from('messages')
          .update({'is_read': true})
          .eq('conversation_id', conversationId)
          .neq('sender_id', userId);
    } catch (e) {
      reportError('MessagingService.markAsRead', e);
    }
  }

  Future<int> getUnreadCount() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return 0;
    {
      final convs = await supabase
          .from('conversations')
          .select('id')
          .or('participant_1.eq.$userId,participant_2.eq.$userId');
      if ((convs as List).isEmpty) return 0;
      final convIds = convs.map((c) => c['id']).toList();

      final data = await supabase
          .from('messages')
          .select('id')
          .eq('is_read', false)
          .neq('sender_id', userId)
          .inFilter('conversation_id', convIds);
      return (data as List).length;
    }
    // ERR-3: no `catch` here. A failed read used to answer `0`, which is
    // "you have no unread messages" — the A-G5 class. Both consumers do
    // `.valueOrNull ?? 0`, so the badge is hidden either way TODAY; what
    // changes is that the error now reaches the provider instead of being
    // destroyed, so a consumer that wants to render it can. Destroying the
    // signal is what left `train_hub`'s `error: → '—'` arm unreachable.
    //
    // Signed out still returns 0 above: that is an answer, not a failure.
  }

  List<Map<String, dynamic>> getSampleMessages() {
    final now = DateTime.now();
    return [
      {'id': '1', 'sender_id': 'coach', 'content': "Hey! How are you feeling after yesterday's workout?", 'sent_at': now.subtract(const Duration(days: 1, hours: 2)).toIso8601String(), 'is_read': true},
      {'id': '2', 'sender_id': 'me', 'content': 'A bit sore but in a good way! The hip thrusts really hit different 😅', 'sent_at': now.subtract(const Duration(days: 1, hours: 1)).toIso8601String(), 'is_read': true},
      {'id': '3', 'sender_id': 'coach', 'content': "That's exactly what we want! Make sure you're hitting your protein today for recovery.", 'sent_at': now.subtract(const Duration(hours: 3)).toIso8601String(), 'is_read': true},
      {'id': '4', 'sender_id': 'coach', 'content': 'Focus on hitting your protein goal today. Your strength numbers will thank you tomorrow.', 'sent_at': now.subtract(const Duration(minutes: 5)).toIso8601String(), 'is_read': false},
    ];
  }
}
