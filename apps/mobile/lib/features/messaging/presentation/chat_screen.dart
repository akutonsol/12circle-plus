import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/observability/app_failure.dart';
import '../../../core/widgets/named_icon_button.dart';
import '../data/chat_media_path.dart';
import '../data/messaging_service.dart';
import '../domain/messaging_provider.dart';
import '../../scoring/data/score_engine.dart';

const _bg      = Color(0xFF030303);
const _card    = Color(0xFF0E0B16);
const _border  = Color(0xFF1A1020);
const _brand  = Color(0xFFA855F7);
const _white  = Colors.white;
const _muted  = Color(0xFFCFC2D6);

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
  final _service    = MessagingService();
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
    // Read the conversation context set by the caller before navigating here
    final conv = ref.read(selectedConversationProvider);

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
    }

    if (convId != null && mounted) {
      setState(() => _conversationId = convId);
      final msgs = await _service.getMessages(convId);
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
      _sub = _service.messagesStream(convId).listen((msgs) {
        if (mounted) setState(() => _messages = msgs);
        _scrollToBottom();
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    _msgCtrl.clear();
    setState(() => _hasText = false);
    final userId = Supabase.instance.client.auth.currentUser?.id ?? 'me';
    // Optimistic update
    final optimistic = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'sender_id': userId,
      'content': text,
      'sent_at': DateTime.now().toIso8601String(),
      'is_read': false,
    };
    setState(() => _messages = [..._messages, optimistic]);
    _scrollToBottom();
    if (_conversationId != null) {
      await _service.sendMessage(conversationId: _conversationId!, content: text);
      ScoreEngine().messageCoach(); // +5, once/day (server dedup)
    }
  }

  // Photo send, in the order the storage contract requires (DEC-3A-10 §6):
  //   1. upload — authorization needs only the conversation, which exists;
  //   2. send the message carrying the object PATH (the bucket is private,
  //      so no URL is ever stored);
  //   3. if the row did not land, remove exactly the object just uploaded
  //      and report — never claim success.
  Future<void> _sendPhoto() async {
    final conversationId = _conversationId;
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (conversationId == null || uid == null || _sending) return;
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null || !mounted) return;
    setState(() => _sending = true);
    final storage = Supabase.instance.client.storage.from(ChatMediaPath.bucket);
    String? uploadedPath;
    try {
      final bytes = await picked.readAsBytes();
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
      final ok = await _service.sendMessage(
        conversationId: conversationId,
        content: '[photo]',
        metadata: {
          ChatMediaPath.typeKey: ChatMediaPath.imageType,
          ChatMediaPath.mediaPathKey: storagePath,
        });
      if (!ok) {
        await _removeOrphan(storage, storagePath);
        _showPhotoFailure();
      }
    } catch (e) {
      // Upload itself failed, or something after it threw. If the object got
      // as far as storage, it has no message row and must not be left behind.
      if (uploadedPath != null) await _removeOrphan(storage, uploadedPath);
      _showPhotoFailure();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Removes exactly [path] — the object this send just uploaded — because its
  /// message row never landed. The DELETE policy admits only the uploader, so
  /// this can never touch anyone else's media. A cleanup failure is reported,
  /// not hidden, and it never turns the send into a success.
  Future<void> _removeOrphan(StorageFileApi storage, String path) async {
    try {
      await storage.remove([path]);
    } catch (e) {
      reportError('ChatScreen._sendPhoto.cleanup', e);
    }
  }

  void _showPhotoFailure() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Failed to send photo'),
        backgroundColor: Colors.red));
  }

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
                  _participantName.isNotEmpty ? _participantName[0].toUpperCase() : '?',
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
                Text(_participantName,
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
                      onPressed: () { setState(() { _loading = true; _loadFailed = false; }); _init(); },
                      child: const Text('Try again'),
                    ),
                  ]),
                ))
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
                      time: _formatTime(msg['sent_at'] ?? DateTime.now().toIso8601String()),
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
            NamedIconButton(
              label: 'Attach',
              onTap: _sendPhoto,
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06)),
                child: const Icon(Icons.image_outlined, color: _muted, size: 20))),
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
                  child: TextField(
                  controller: _msgCtrl,
                  style: const TextStyle(color: _white, fontSize: 14),
                  maxLines: null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: 'Message $_participantName...',
                    hintStyle: TextStyle(color: _muted.withValues(alpha: 0.35), fontSize: 13),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
                  onTapOutside: (_) => FocusScope.of(context).unfocus())))),
            const SizedBox(width: 8),
            // FIT-026 names this "Send".
            Semantics(
              button: true,
              label: 'Send',
              excludeSemantics: true,
              onTap: _send,
              child: GestureDetector(
              onTap: _send,
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
