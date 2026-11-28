import 'dart:async';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/observability/app_failure.dart';
import '../../../core/observability/network_failure.dart';
import '../../../core/widgets/named_icon_button.dart';
import '../data/chat_media_path.dart';
import '../data/messaging_service.dart';
import '../domain/messaging_provider.dart';
import '../../auth/domain/auth_provider.dart';
import '../../scoring/data/score_engine.dart';
import '../../workout/presentation/widgets/section_load_failure.dart';

const _bg      = Color(0xFF030303);
const _card    = Color(0xFF0E0B16);
const _border  = Color(0xFF1A1020);
const _brand  = Color(0xFFA855F7);
const _white  = Colors.white;
const _muted  = Color(0xFFCFC2D6);

const _sendFailedNetworkMessage =
    "Couldn't send your message — check your connection and try again.";
const _sendFailedOtherMessage =
    "Couldn't send your message — try again in a moment. "
    'If it keeps happening, contact support.';
const _notReadyMessage =
    "This conversation isn't ready yet — try again in a moment.";
const _noConversationMessage = 'Open a conversation from Messages.';
const _photoBusyMessage =
    'A photo is already being chosen or sent — wait for it to finish.';

/// P0-FL-63b · marks a message on screen whose insert has not answered yet. It
/// is drawn as [_sendingLabel], not with a sent time: nothing has said it was
/// sent (there is no client timeout, so a stalled connection can hold it).
/// Local only — never sent, and gone from the server's rows.
const _pendingKey = '_unconfirmed';
const _sendingLabel = 'Sending…';

/// F-28 · the chat header's subtitle.
///
/// It was the constant **"Online now"**, beside a green presence dot. Nothing
/// in this repository tracks presence — no `is_online`, no `last_seen`, no
/// realtime channel for it — so **every conversation claimed the other person
/// was online, always**. A client could message their coach at midnight
/// believing they were there.
///
/// FIT-026's header reads "Nadia Rahman / Your coach": the **relationship**,
/// which is real data on the conversation the caller already carries. Where the
/// role is unknown the subtitle is omitted rather than guessed — an empty line
/// says nothing, and nothing is what the screen knows.
String? chatSubtitle(String? role) => switch (role?.trim().toLowerCase()) {
      'coach' => 'Your coach',
      'client' => 'Your client',
      _ => null,
    };

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  // Through the provider, not a fresh `MessagingService()`, so a test can answer
  // the sends. Read lazily: the first use is after the first frame.
  late final MessagingService _service = ref.read(messagingServiceProvider);
  final _msgCtrl    = TextEditingController();
  final _scrollCtrl = ScrollController();

  String? _conversationId;
  String  _participantName = 'Coach';
  /// F-28: the header subtitle. It used to be the constant "Online now" beside
  /// a green dot — see [chatSubtitle].
  String? _participantRole;
  List<Map<String, dynamic>> _messages = [];
  StreamSubscription? _sub;
  bool _sending  = false;
  bool _hasText  = false;
  bool _loading  = true;
  /// Distinct from "no messages". A thread that could not be reached is not an
  /// empty thread, and showing the empty state for it tells the user something
  /// false about their own conversation.
  bool _loadFailed = false;

  /// P0-FL-59c · who this conversation was opened as. Everything above belongs
  /// to them, and nothing is sent, marked read or awarded as anyone else: the
  /// server accepts a message from any signed-in account into any conversation.
  String? _owner = _signedInUid;

  /// Raised when the conversation is dropped, so an answer still on its way to
  /// it is discarded — even if the same member has signed in again by then.
  int _epoch = 0;

  /// The conversation was dropped (its owner left): no thread is open, which is
  /// neither an empty thread nor a failed one.
  bool _closed = false;

  static String? get _signedInUid =>
      Supabase.instance.client.auth.currentUser?.id;

  /// Still the conversation that was open at [epoch], for the member it was
  /// opened as. Asks the auth client, not a provider: a provider learns of a
  /// switch a moment later, and not at all in a hidden tab.
  bool _holds(int epoch) => epoch == _epoch && _signedInUid == _owner;

  /// Drops everything the last account had open. Says nothing: the one who
  /// arrived is told nothing about it.
  void _drop() {
    _epoch++;
    _owner = _signedInUid;
    _sub?.cancel();
    _sub = null;
    _msgCtrl.clear();
    _signedUrls.clear();
    // What it said to the member who left is not said to the one who arrived.
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..removeCurrentSnackBar();
    // Their picker can still be open; it is not this composer's any more.
    _pickingPhoto = false;
    setState(() {
      _closed = true;
      _conversationId = null;
      _participantName = '';
      _participantRole = null;
      _messages = const [];
      _photoFailure = '';
      _loadFailed = false;
      _loading = false;
      _sending = false;
    });
  }

  void _dropIfLeft() {
    if (mounted && _signedInUid != _owner) _drop();
  }

  /// A step that belonged to the account that left: not taken, and recorded.
  void _refuse(String origin, String what) {
    reportError(origin, StateError('$what: the signed-in account changed'),
        StackTrace.current);
    _dropIfLeft();
  }

  // chat-media is a PRIVATE bucket (migration 130 / DEC-3A-10): a message row
  // stores the object path, and display signs it here, once per path, so a
  // list rebuild does not re-sign every image. TTL matches progress_screen.
  final _signedUrls = <String, Future<String>>{};
  Future<String> _signedUrlFor(String path) => _signedUrls.putIfAbsent(
      path,
      () => Supabase.instance.client.storage
          .from(ChatMediaPath.bucket)
          .createSignedUrl(path, 3600));

  @override
  void initState() {
    super.initState();
    _msgCtrl.addListener(() =>
      setState(() => _hasText = _msgCtrl.text.trim().isNotEmpty));
    // Defer so we can safely read providers
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final epoch = _epoch;
    if (!_holds(epoch)) {
      _dropIfLeft();
      return;
    }
    // Read the conversation context set by the caller before navigating here
    final conv = ref.read(selectedConversationProvider);
    if (!conversationIsOf(conv, _owner)) {
      // Opened from an inbox that had outlived the account it was read for.
      reportError(
          'ChatScreen._init',
          StateError('conversation not opened: the signed-in account changed'),
          StackTrace.current);
      ref.read(selectedConversationProvider.notifier).state = null;
      if (mounted) _drop();
      return;
    }

    String? convId = conv?['id'] as String?;
    final participant = conv?['participant'] as Map<String, dynamic>?;
    final fn = participant?['first_name'] as String? ?? '';
    final ln = participant?['last_name'] as String? ?? '';
    final name = '$fn $ln'.trim();

    if (mounted) {
      setState(() {
        _participantName = name.isNotEmpty ? name : 'Coach';
        _participantRole = participant?['role'] as String?;
      });
    }

    // If no conversation was pre-selected, find/create one. Prefer the exact
    // participant the caller passed (e.g. the assigned coach), else fall back to
    // the client's active coach.
    if (convId == null) {
      final pid = participant?['id'] as String?;
      convId = (pid != null && pid.isNotEmpty)
          ? await _service.getOrCreateConversationWith(pid)
          : await _service.getOrCreateClientCoachConversation();
      if (!_holds(epoch)) {
        _dropIfLeft();
        return;
      }
    }

    if (convId != null && mounted) {
      setState(() => _conversationId = convId);
      final List<Map<String, dynamic>> msgs;
      try {
        msgs = await _service.getMessages(convId);
      } catch (e, st) {
        // Not an empty thread: the screen's failure state, with its retry.
        reportError('ChatScreen._init.getMessages', e, st);
        if (!_holds(epoch)) {
          _dropIfLeft();
          return;
        }
        if (mounted) {
          setState(() {
            _messages = const [];
            _loadFailed = true;
            _loading = false;
          });
        }
        return;
      }
      if (!_holds(epoch)) {
        _refuse('ChatScreen._init.markAsRead', 'messages not marked read');
        return;
      }
      if (mounted) {
        // An empty conversation is EMPTY. It previously fell back to
        // `getSampleMessages()`, which put four hardcoded messages on screen as
        // if they were this user's real coach thread — including one attributed
        // to the user ("A bit sore but in a good way!..."). A messaging surface
        // must never invent its own contents. The screen already renders the
        // correct "Start the conversation!" empty state; that fallback was the
        // only thing making it unreachable.
        setState(() {
          _messages = msgs;
          _loading = false;
        });
      }
      await _service.markAsRead(convId);
      if (!mounted || !_holds(epoch)) {
        _dropIfLeft();
        return;
      }
      _sub = _service.messagesStream(convId).listen((msgs) {
        if (!_holds(epoch)) {
          _dropIfLeft();
          return;
        }
        if (mounted) setState(() => _messages = msgs);
        _scrollToBottom();
      }, onError: (Object e, StackTrace st) {
        // The thread on screen stays; new messages no longer arrive by
        // themselves. Was an uncaught error.
        reportError('ChatScreen.messagesStream', e, st);
      });
    } else if (mounted) {
      // No conversation could be found or created. That is a failure, not an
      // empty thread, and it is emphatically not four invented messages.
      reportError('ChatScreen._init', StateError('no conversation for participant'));
      setState(() {
        _messages = const [];
        _loadFailed = true;
        _loading = false;
      });
    }
    _scrollToBottom();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // The list builds lazily and estimates its full length from what it has
      // built, so in a long thread the first target falls short of the newest
      // message. Go again until the end stops moving.
      for (var i = 0; i < 8; i++) {
        if (!mounted || !_scrollCtrl.hasClients) return;
        final target = _scrollCtrl.position.maxScrollExtent;
        await _scrollCtrl.animateTo(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut);
        if (!mounted || !_scrollCtrl.hasClients) return;
        final position = _scrollCtrl.position;
        // Short of the target means the client took over the scroll. Leave them.
        if (position.pixels < target - 1 || position.maxScrollExtent <= target) return;
      }
    });
  }

  /// [epoch] is the one the composer was built at: the member it sends as.
  Future<void> _send(int epoch) async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    final owner = _owner;
    if (!_holds(epoch)) {
      // Typed by the account that left, with their conversation still open.
      _refuse('ChatScreen._send', 'message not sent');
      return;
    }
    final conversationId = _conversationId;
    if (conversationId == null) {
      // Still resolving, or none could be found. Nothing can be sent yet. This used
      // to clear the input and drop the text without a word.
      _showSendFailure(_notReadyMessage);
      return;
    }
    _msgCtrl.clear();
    setState(() => _hasText = false);
    final userId = owner ?? 'me';
    // Optimistic update
    final optimistic = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'sender_id': userId,
      'content': text,
      'sent_at': DateTime.now().toIso8601String(),
      'is_read': false,
      _pendingKey: true,
    };
    setState(() => _messages = [..._messages, optimistic]);
    _scrollToBottom();
    Object? sendError;
    final ok = await _service.sendMessage(
        conversationId: conversationId,
        content: text,
        onNotSent: (e) => sendError = e);
    if (ok) {
      if (_signedInUid != owner) {
        // The points would go to whoever is signed in now.
        _refuse('ChatScreen._send.award', 'points not awarded');
        return;
      }
      // The server took the row: now it is shown as sent.
      if (mounted && epoch == _epoch) {
        setState(() => optimistic.remove(_pendingKey));
      }
      ScoreEngine().messageCoach(); // +5, once/day (server dedup)
      return;
    }
    // The row did not land. `sendMessage` reports that as `false`, which this used
    // to ignore: the bubble stayed as sent, the text was gone, and the score was
    // awarded for a message nobody received.
    reportError('ChatScreen._send', StateError('message was not sent'));
    if (!mounted || !_holds(epoch)) {
      // Their text is not handed to the account that arrived, nor the notice.
      // RM-2 (C15-63b-04) · the notice the sender never saw is recorded once,
      // as payments records its outcomes (the flow only, never the text). A
      // screen the same member closed meanwhile is not an account change.
      if (!_holds(epoch)) {
        _recordNoticeNotShown('ChatScreen._send', 'message send');
      }
      if (mounted) _dropIfLeft();
      return;
    }
    setState(() =>
        _messages = _messages.where((m) => m['id'] != optimistic['id']).toList());
    // Give the text back, unless the coach has already started something else.
    if (_msgCtrl.text.isEmpty) {
      _msgCtrl.value = TextEditingValue(
          text: text, selection: TextSelection.collapsed(offset: text.length));
    }
    // P0-FL-13: the connection hint only when the send never reached the
    // server. A refusal the server answered is not fixed by checking Wi-Fi.
    _showSendFailure(isNetworkFailure(sendError)
        ? _sendFailedNetworkMessage
        : _sendFailedOtherMessage);
  }

  /// The failure of [flow], meant for the member who sent it, was not said to
  /// them: another account (or nobody) is signed in now, or their conversation
  /// was dropped. Names the flow only (RM-2).
  static void _recordNoticeNotShown(String origin, String flow) => reportError(
      origin,
      StateError('$flow outcome not shown: the signed-in account changed'),
      StackTrace.current);

  void _showSendFailure(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// The photo picker is open: a second tap opens no second one (P0-FL-56a).
  bool _pickingPhoto = false;

  /// What [_showPhotoFailure] says about the photo send that just failed.
  String _photoFailure = '';

  // Photo send, in the order the storage contract requires (DEC-3A-10 §6):
  //   1. upload — authorization needs only the conversation, which exists;
  //   2. send the message carrying the object PATH (the bucket is private,
  //      so no URL is ever stored);
  //   3. if the row did not land, remove exactly the object just uploaded
  //      and report — never claim success.
  Future<void> _sendPhoto(int epoch) async {
    final conversationId = _conversationId;
    final uid = _signedInUid;
    // Attach used to do nothing in these states, without a word.
    if (uid == null) {
      _dropIfLeft();
      _showSendFailure("You're signed out — sign in again to send a photo.");
      return;
    }
    if (!_holds(epoch)) {
      _refuse('ChatScreen._sendPhoto', 'photo not sent');
      return;
    }
    if (_sending || _pickingPhoto) {
      _showSendFailure(_photoBusyMessage);
      return;
    }
    if (conversationId == null) {
      _showSendFailure(_notReadyMessage);
      return;
    }
    _pickingPhoto = true;
    final XFile? picked;
    try {
      picked = await ImagePicker()
          .pickImage(source: ImageSource.gallery, imageQuality: 80);
    } catch (e, st) {
      // P0-FL-56a · was unguarded: a denied permission was an uncaught error
      // and Attach did nothing. A denial (image_picker's codes end
      // `_access_denied`) says where to allow access.
      reportError('chat.photo.pick.gallery', e, st);
      if (!_holds(epoch)) {
        _recordNoticeNotShown('ChatScreen._sendPhoto', 'photo send');
        _dropIfLeft();
        return;
      }
      _showSendFailure(
          e is PlatformException && e.code.endsWith('_access_denied')
              ? "Couldn't open your photos — allow photo access in Settings, "
                  'then try again.'
              : couldntMessage('open your photos', e));
      return;
    } finally {
      // After a drop the composer is no longer this pick's.
      if (epoch == _epoch) _pickingPhoto = false;
    }
    // Null is the person cancelling: nothing is sent and nothing is said.
    if (picked == null || !mounted) return;
    if (_holds(epoch)) setState(() => _sending = true);
    final storage = Supabase.instance.client.storage.from(ChatMediaPath.bucket);
    String? uploadedPath;
    Object? sendError;
    // This send's own stop for a member who left: nothing more was sent, and
    // there is no failure of theirs to say (RM-2).
    Object? stop;
    try {
      final Uint8List bytes;
      try {
        bytes = await picked.readAsBytes();
      } catch (e, st) {
        reportError('chat.photo.read', e, st);
        if (_holds(epoch)) {
          _showSendFailure(couldntMessage('use that photo', e));
        } else {
          _recordNoticeNotShown('ChatScreen._sendPhoto', 'photo send');
        }
        return;
      }
      // Their member left meanwhile: not this account's message to send, nor
      // theirs if they are back, because the conversation was dropped.
      if (!_holds(epoch)) {
        throw stop = StateError('the member changed during a pick');
      }
      final ext = picked.path.split('.').last.toLowerCase();
      // messages/<conversation_id>/<uploader_uid>/<epoch>.<ext> — the
      // conversation is the authorization identity, never the uploader.
      final storagePath = ChatMediaPath.build(
        conversationId: conversationId,
        uploaderId: uid,
        epochMillis: DateTime.now().millisecondsSinceEpoch,
        extension: ext,
      );
      // upsert stays false: chat-media has no UPDATE policy. Media is immutable.
      await storage.uploadBinary(storagePath, bytes,
          fileOptions: FileOptions(contentType: 'image/$ext', upsert: false));
      uploadedPath = storagePath;
      // Checked again: `sendMessage` writes as whoever is signed in NOW, so a
      // switch during the upload sent this photo as B, in A's conversation.
      if (!_holds(epoch)) {
        throw stop = StateError('the member changed during an upload');
      }
      final ok = await _service.sendMessage(
        conversationId: conversationId,
        content: '[photo]',
        metadata: {
          ChatMediaPath.typeKey: ChatMediaPath.imageType,
          ChatMediaPath.mediaPathKey: storagePath,
        },
        onNotSent: (e) => sendError = e);
      if (!ok) {
        // Recorded by the service (`MessagingService.sendMessage`).
        await _removeOrphan(storage, storagePath);
        if (_holds(epoch)) {
          _photoFailure = couldntMessage('send your photo', sendError);
          _showPhotoFailure();
        } else {
          _recordNoticeNotShown('ChatScreen._sendPhoto', 'photo send');
        }
      }
    } catch (e, st) {
      // Upload itself failed, or something after it threw. If the object got
      // as far as storage, it has no message row and must not be left behind.
      reportError('ChatScreen._sendPhoto', e, st);
      if (uploadedPath != null) await _removeOrphan(storage, uploadedPath);
      // Another member signed in: it was not their photo, so nothing is said.
      if (_holds(epoch)) {
        _photoFailure = couldntMessage('send your photo', e);
        _showPhotoFailure();
      } else if (!identical(e, stop)) {
        _recordNoticeNotShown('ChatScreen._sendPhoto', 'photo send');
      }
    } finally {
      // After a drop the composer is no longer this send's.
      if (mounted && epoch == _epoch) setState(() => _sending = false);
      _dropIfLeft();
    }
  }

  /// Removes exactly [path] — the object this send just uploaded — because its
  /// message row never landed. The DELETE policy admits only the uploader, so
  /// this can never touch anyone else's media. A cleanup failure is reported,
  /// not hidden, and it never turns the send into a success.
  ///
  /// `remove` answers with the objects it removed and does NOT throw for one
  /// it could not delete, so an empty answer is checked: gone is fine (nothing
  /// is left behind), still there is a cleanup failure (P0-FL-56a). It is
  /// checked by listing the folder for the exact name, not with `exists`,
  /// which reads every 400/404 as "gone".
  ///
  /// The uploader is the path's third segment (see [ChatMediaPath]). Once
  /// someone else (or no one) is signed in, storage hides the object from the
  /// session, so every answer looks like "gone": nothing is asked as them, and
  /// the leftover is recorded.
  Future<void> _removeOrphan(StorageFileApi storage, String path) async {
    final uid = path.split('/')[2];
    void requireUploader() {
      if (Supabase.instance.client.auth.currentUser?.id != uid) {
        throw StateError('an unsent photo could not be cleaned up: '
            'its uploader is no longer signed in');
      }
    }

    try {
      requireUploader();
      final removed = await storage.remove([path]);
      if (removed.isNotEmpty) return;
      requireUploader();
      final slash = path.lastIndexOf('/');
      final name = path.substring(slash + 1);
      final left = await storage.list(
          path: path.substring(0, slash),
          searchOptions: SearchOptions(search: name));
      requireUploader();
      if (left.any((o) => o.name == name)) {
        throw StateError('an unsent photo is still in storage after remove');
      }
    } catch (e, st) {
      reportError('ChatScreen._sendPhoto.cleanup', e, st);
    }
  }

  void _showPhotoFailure() => _showSendFailure(_photoFailure);

  bool _isMe(Map<String, dynamic> msg) {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    return msg['sender_id'] == userId || msg['sender_id'] == 'me';
  }

  String _formatTime(String iso) {
    final dt = DateTime.parse(iso).toLocal();
    final h  = dt.hour > 12 ? dt.hour - 12 : dt.hour == 0 ? 12 : dt.hour;
    final m  = dt.minute.toString().padLeft(2, '0');
    return '$h:$m ${dt.hour >= 12 ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) {
    // The uid only: a token refresh or a profile edit is the same member, and
    // must not take their draft.
    ref.listen(currentUserProvider.select((u) => u?.id), (_, next) {
      if (next != _owner) _drop();
    });
    // Bound into every action below: it is taken as the member it was built for.
    final epoch = _epoch;
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(child: Column(children: [

        // ── Header ──
        Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
          decoration: const BoxDecoration(
            color: _card,
            border: Border(bottom: BorderSide(color: _border))),
          child: Row(children: [
            Semantics(
              button: true,
              label: 'Back',
              child: GestureDetector(
              onTap: () => context.go('/messages'),
              behavior: HitTestBehavior.opaque,
              child: Container(
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                alignment: Alignment.center,
                child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06), shape: BoxShape.circle),
                child: const Icon(Icons.arrow_back, color: _white, size: 18))))),
            const SizedBox(width: 10),
            // Avatar
            Stack(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _brand.withValues(alpha: 0.15),
                  border: Border.all(color: _brand.withValues(alpha: 0.4), width: 1.5)),
                alignment: Alignment.center,
                child: Text(
                  _participantName.isNotEmpty ? _participantName[0].toUpperCase()
                      : _closed ? '' : '?',
                  style: const TextStyle(color: _brand, fontSize: 16, fontWeight: FontWeight.w800))),
              // F-28: a green presence dot sat here, beside a hardcoded
              // "Online now". Nothing in this repository tracks presence, so
              // every conversation claimed the other person was online, always.
              // Removed rather than restyled — the fix for a fabricated fact is
              // not a quieter fabrication.
            ]),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_closed ? 'Messages' : _participantName,
                  style: const TextStyle(color: _white, fontSize: 15, fontWeight: FontWeight.w700)),
                // FIT-026's header reads "Nadia Rahman / Your coach" — the
                // RELATIONSHIP, not a presence claim.
                if (chatSubtitle(_participantRole) != null)
                  Text(chatSubtitle(_participantRole)!,
                    style: TextStyle(color: _muted.withValues(alpha: 0.75), fontSize: 11)),
              ])),
            // FIT-026 · "Booking sits in the header, because 'can we talk' is
            // the second thing you want in a coach thread."
            NamedIconButton(
              label: 'Book a call',
              onTap: () => context.push('/book-call'),
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06), shape: BoxShape.circle),
                child: const Icon(Icons.videocam_outlined, color: _white, size: 18)),
            ),
          ])),

        // ── Messages ──
        Expanded(
          child: _loading
            ? const Center(child: CircularProgressIndicator(color: _brand))
            : _loadFailed
              ? Center(child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.wifi_off_rounded, color: _muted.withValues(alpha: 0.5), size: 48),
                    const SizedBox(height: 12),
                    const Text("Couldn't open this conversation",
                      style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    Text('This is a connection problem, not an empty thread.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _muted.withValues(alpha: 0.8), fontSize: 13)),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () {
                        if (!_holds(epoch)) return _dropIfLeft();
                        setState(() { _loading = true; _loadFailed = false; });
                        _init();
                      },
                      child: const Text('Try again'),
                    ),
                  ]),
                ))
            : _closed
              ? Center(child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  // Announced: the thread went away without anyone asking.
                  child: Semantics(
                    liveRegion: true,
                    container: true,
                    child: Text(_noConversationMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _muted.withValues(alpha: 0.8), fontSize: 14)))))
            : _messages.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.chat_bubble_outline, color: _brand.withValues(alpha: 0.3), size: 48),
                  const SizedBox(height: 12),
                  Text("Start the conversation!",
                    style: TextStyle(color: _muted.withValues(alpha: 0.5), fontSize: 14)),
                ]))
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) {
                    final msg   = _messages[i];
                    final isMe  = _isMe(msg);
                    final showAvatar = !isMe && (i == 0 || _isMe(_messages[i - 1]));
                    final meta = msg['metadata'] as Map<String, dynamic>?;
                    return _MessageBubble(
                      content: msg['content'] ?? '',
                      mediaPath: meta?[ChatMediaPath.mediaPathKey] as String?,
                      resolveMediaUrl: _signedUrlFor,
                      isMe: isMe,
                      time: msg[_pendingKey] == true
                          ? _sendingLabel
                          : _formatTime(msg['sent_at'] ?? DateTime.now().toIso8601String()),
                      showAvatar: showAvatar,
                      participantInitial: _participantName.isNotEmpty
                        ? _participantName[0].toUpperCase() : '?');
                  })),

        // ── Input bar ──
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          decoration: const BoxDecoration(
            color: _card,
            border: Border(top: BorderSide(color: _border))),
          child: Row(children: [
            // FIT-026 names this "Attach" and draws it at 44x44.
            MergeSemantics(child: Semantics(
              // Off while no thread is open: there is nothing to attach to.
              enabled: !_closed,
              child: NamedIconButton(
              label: 'Attach',
              onTap: _closed ? null : () => _sendPhoto(epoch),
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06)),
                child: const Icon(Icons.image_outlined, color: _muted, size: 20))))),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _border)),
                // FIT-026 names the composer "Message". A `TextField` with
                // only a hint reports its VALUE and no name, so an empty
                // composer announced nothing at all.
                child: Semantics(
                  textField: true,
                  label: 'Message',
                  enabled: !_closed,
                  child: TextField(
                  // A new field after a drop: undo in the old one would bring
                  // the last member's draft back.
                  key: ValueKey('composer-$epoch'),
                  enabled: !_closed,
                  controller: _msgCtrl,
                  style: const TextStyle(color: _white, fontSize: 14),
                  maxLines: null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(epoch),
                  decoration: InputDecoration(
                    hintText: _closed ? 'Message...' : 'Message $_participantName...',
                    hintStyle: TextStyle(color: _muted.withValues(alpha: 0.35), fontSize: 13),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
                  onTapOutside: (_) => FocusScope.of(context).unfocus())))),
            const SizedBox(width: 8),
            // FIT-026 names this "Send".
            Semantics(
              button: true,
              label: 'Send',
              enabled: !_closed,
              excludeSemantics: true,
              onTap: _closed ? null : () => _send(epoch),
              child: GestureDetector(
              onTap: _closed ? null : () => _send(epoch),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 44, height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _hasText ? _brand : _border,
                  boxShadow: _hasText
                    ? [BoxShadow(color: _brand.withValues(alpha: 0.4), blurRadius: 12)]
                    : null),
                child: _sending
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.send_rounded, color: _white, size: 20)))),
          ])),

      ])));
  }
}

// ── Message Bubble ────────────────────────────────────────────────────────────
class _MessageBubble extends StatelessWidget {
  final String content, time;
  /// Storage object path of an image message (`metadata.media_path`). The
  /// bucket is private, so it is resolved through [resolveMediaUrl] at render
  /// time — a signed URL, never a public one, and never one stored in the row.
  final String? mediaPath;
  final Future<String> Function(String path)? resolveMediaUrl;
  final String participantInitial;
  final bool isMe, showAvatar;
  const _MessageBubble({
    required this.content,
    required this.isMe,
    required this.time,
    required this.showAvatar,
    required this.participantInitial,
    this.mediaPath,
    this.resolveMediaUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            if (showAvatar)
              Container(
                width: 30, height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _brand.withValues(alpha: 0.15),
                  border: Border.all(color: _brand.withValues(alpha: 0.3))),
                alignment: Alignment.center,
                child: Text(participantInitial,
                  style: const TextStyle(color: _brand, fontSize: 12, fontWeight: FontWeight.w800)))
            else
              const SizedBox(width: 30),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.70),
                  decoration: BoxDecoration(
                    color: isMe ? _brand : _card,
                    borderRadius: BorderRadius.only(
                      topLeft:     const Radius.circular(18),
                      topRight:    const Radius.circular(18),
                      bottomLeft:  Radius.circular(isMe ? 18 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 18)),
                    border: isMe ? null : Border.all(color: _border),
                    boxShadow: isMe
                      ? [BoxShadow(color: _brand.withValues(alpha: 0.25), blurRadius: 8)]
                      : null),
                  child: mediaPath != null && resolveMediaUrl != null
                    ? _PrivateImage(
                        path: mediaPath!,
                        resolve: resolveMediaUrl!,
                        width: MediaQuery.of(context).size.width * 0.60)
                    : Text(content,
                        style: const TextStyle(color: _white, fontSize: 14, height: 1.4))),
                const SizedBox(height: 3),
                Text(time,
                  style: TextStyle(color: _muted.withValues(alpha: 0.4), fontSize: 10)),
              ])),
          if (isMe) const SizedBox(width: 4),
        ]));
  }
}

// ── Private image ─────────────────────────────────────────────────────────────
// Resolves a chat-media object path to a short-lived signed URL and renders it.
// Every state is explicit: signing, signed-and-loading, loaded, and failed. A
// failure shows a broken-image mark — never a placeholder that could pass for
// the real photo (closure-standard invariant I-1).
class _PrivateImage extends StatelessWidget {
  final String path;
  final Future<String> Function(String path) resolve;
  final double width;
  const _PrivateImage({required this.path, required this.resolve, required this.width});

  static const _spinner = SizedBox(height: 120,
    child: Center(child: CircularProgressIndicator(color: _brand, strokeWidth: 2)));
  static const _broken = Icon(Icons.broken_image_outlined, color: _muted, size: 40);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: resolve(path),
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) return _spinner;
        final url = snap.data;
        if (snap.hasError || url == null || url.isEmpty) return _broken;
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(url,
            width: width,
            fit: BoxFit.cover,
            loadingBuilder: (_, child, progress) => progress == null ? child : _spinner,
            errorBuilder: (_, __, ___) => _broken));
      });
  }
}
