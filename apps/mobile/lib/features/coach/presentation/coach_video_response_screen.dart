import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/observability/app_failure.dart';
import '../../../core/observability/network_failure.dart';
import '../../workout/presentation/widgets/section_load_failure.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
const _bg    = Color(0xFF030303);
const _card  = Color(0xFF0E0B16);
const _brd   = Color(0xFF1A1020);
const _brand = Color(0xFFA855F7);
const _tert  = Color(0xFF6FFBBE);
const _wht   = Colors.white;
const _mut   = Color(0xFFCFC2D6);
const _warn  = Color(0xFFF59E0B); // AppTheme.warning

// ── UC18: Coach Video Response ────────────────────────────────────────────────
class CoachVideoResponseScreen extends StatefulWidget {
  final String clientId;
  final String clientName;
  final String? checkinId;
  const CoachVideoResponseScreen({
    super.key, required this.clientId, required this.clientName, this.checkinId,
  });
  @override
  State<CoachVideoResponseScreen> createState() => _CoachVideoResponseScreenState();
}

class _CoachVideoResponseScreenState extends State<CoachVideoResponseScreen> {
  final _db = Supabase.instance.client;
  final _noteCtrl = TextEditingController();
  XFile? _videoFile;
  bool _uploading = false;
  /// The camera or the gallery is open.
  bool _choosing = false;
  bool _done = false;
  /// The client's notification was confirmed sent (best-effort; P0-FL-53b).
  bool _notified = false;
  double _progress = 0;

  /// P0-FL-59d · the coach this page was opened by: the client named on it,
  /// the video and the note are theirs. It stayed up over a switch on this
  /// device and Send sent them as the next coach.
  late final String? _owner = _uid;
  /// Somebody else (or nobody) is signed in: nothing of [_owner]'s is shown.
  bool _hidden = false;
  /// Nobody is: said, where the page would be. (To another account, nothing.)
  bool _signedOut = false;
  StreamSubscription<AuthState>? _authSub;

  String? get _uid => _db.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _hidden = _signedOut = _owner == null;
    // Same coach (a token refresh, the stream's replay) changes nothing.
    _authSub = _db.auth.onAuthStateChange.listen((_) => _followAccount(),
        onError: (Object e, StackTrace s) =>
            reportError('CoachVideoResponseScreen.onAuthStateChange', e, s));
  }

  void _followAccount() {
    final hidden = _owner == null || _uid != _owner;
    final signedOut = _uid == null;
    if (!mounted || (hidden == _hidden && signedOut == _signedOut)) return;
    setState(() {
      _hidden = hidden;
      _signedOut = signedOut;
      _videoFile = null;
      _noteCtrl.clear();
      _uploading = false;
      _done = false;
    });
    ScaffoldMessenger.of(context)..clearSnackBars()..removeCurrentSnackBar();
  }

  /// True when [_owner] is no longer signed in: recorded, the page is cleared,
  /// and the caller sends nothing.
  bool _accountChanged(String what) {
    if (_owner != null && _uid == _owner) return false;
    reportError('CoachVideoResponseScreen._send',
        StateError('$what: the signed-in account changed'));
    _followAccount();
    return true;
  }

  @override
  void dispose() { _authSub?.cancel(); _noteCtrl.dispose(); super.dispose(); }

  // P0-FL-58 · a failed record / pick was said but never recorded, and not in
  // the shared voice. Cancelling (null) is legitimate: nothing is said or
  // recorded, and a video already chosen stays — as it does after a failure.
  Future<void> _recordVideo() => _choose('_recordVideo', ImageSource.camera);

  Future<void> _pickVideo() => _choose('_pickVideo', ImageSource.gallery);

  Future<void> _choose(String method, ImageSource source) async {
    if (_choosing) return; // one picker at a time
    _choosing = true;
    try {
      final video = await ImagePicker().pickVideo(
        source: source,
        maxDuration: source == ImageSource.camera ? const Duration(minutes: 5) : null);
      if (video != null && mounted && _uid == _owner && !_hidden) {
        setState(() => _videoFile = video);
      }
    } catch (e, st) {
      reportError('CoachVideoResponseScreen.$method', e, st);
      if (_uid == _owner) _err(_chooseFailure(source, e));
    } finally {
      _choosing = false;
    }
  }

  /// image_picker's permission codes are `camera_access_denied` and
  /// `photo_access_denied`: trying again cannot help, Settings can.
  static String _chooseFailure(ImageSource source, Object e) {
    final camera = source == ImageSource.camera;
    final what = camera ? 'open the camera' : 'open your videos';
    if (e is PlatformException && e.code.endsWith('_access_denied')) {
      return "Couldn't $what — allow ${camera ? 'camera' : 'photo'} access in "
          'Settings, then try again.';
    }
    // P0-FL-58 r2 · the device may have no camera (desktop web): trying again
    // cannot help, the gallery can. Unless it IS the connection.
    if (camera && !isNetworkFailure(e)) {
      return "Couldn't $what — you can use From Gallery instead.";
    }
    return couldntMessage(what, e);
  }

  void _removeVideo() => setState(() => _videoFile = null);

  void _err(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Semantics(liveRegion: true, child: Text(m)),
      backgroundColor: Colors.red));
  }

  Future<void> _send() async {
    if (_accountChanged('Sending a response')) return;
    if (_videoFile == null && _noteCtrl.text.trim().isEmpty) return;
    final uid = _owner;
    // What was typed when Send was tapped (a switch clears the field).
    final note = _noteCtrl.text.trim();
    setState(() { _uploading = true; _progress = 0; });

    try {
      String? videoUrl;

      if (_videoFile != null) {
        final file = _videoFile!;
        // Read bytes + uploadBinary so it works on web AND mobile (no dart:io).
        final ext = file.name.contains('.') ? file.name.split('.').last.toLowerCase() : 'mp4';
        final mime = ext == 'mov' ? 'video/quicktime' : ext == 'webm' ? 'video/webm' : 'video/mp4';
        final bytes = await file.readAsBytes();
        final path = 'coach-videos/$uid/${widget.clientId}/${DateTime.now().millisecondsSinceEpoch}.$ext';
        if (!mounted) return;
        // Before the upload: no orphan is stored for a response never sent.
        if (_accountChanged('Uploading a response')) return;
        setState(() => _progress = 0.3);
        await _db.storage.from('coach-media').uploadBinary(path, bytes,
          fileOptions: FileOptions(contentType: mime, upsert: true));
        // SEC-VIDEO-1. This was `getPublicUrl(path)`, which minted a permanent
        // unauthenticated URL to a video of a coach discussing a named client
        // and persisted it in the database. Store the OBJECT PATH instead and
        // let whatever eventually plays it sign at render time — the treatment
        // SEC-VOICE-1 gave `coach_voice` (`coachVoiceSigningPath`), and the
        // prerequisite that lets `coach-media` be made private without
        // stranding rows.
        //
        // This is safe to change here because NOTHING reads this column:
        // `coach_video_responses` is written at the insert below and read
        // nowhere in the app. Which is also the defect — see OD-57. The video
        // is uploaded, the client is told "Tap to watch", and there is no
        // player, so this change repairs the storage of the value without
        // pretending the feature works.
        videoUrl = path;
        if (!mounted) return;
        setState(() => _progress = 0.7);
        if (_accountChanged('Sending a response')) return;
      }

      await _db.from('coach_video_responses').insert({
        'coach_id': uid,
        'client_id': widget.clientId,
        'checkin_id': widget.checkinId,
        'video_url': videoUrl,
        'notes': note.isEmpty ? null : note,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      // P0-FL-53b · best-effort, and reported: the response above is saved.
      // A failed notification thrown from here read as "Failed to send", and
      // sending again saved the response twice.
      if (_accountChanged('New-video notification')) return;
      var notified = false;
      try {
        await _db.from('notifications').insert({
          'recipient_id': widget.clientId,
          'type': 'coach_video',
          'title': 'New video from your coach!',
          'body': 'Your coach recorded a personal video response for you. Tap to watch.',
          'read': false,
        });
        notified = true;
      } catch (e, st) {
        reportError('CoachVideoResponseScreen._send.notify', e, st);
      }

      if (!mounted || _uid != uid) return;
      setState(() {
        _progress = 1.0; _done = true; _uploading = false; _notified = notified;
      });
    } catch (e, st) {
      // ERR-2: was `Text('Error: \$e')`. A Postgres/Storage error carries
      // table, column and constraint text; a coach does not need it and
      // should not be shown it. P0-FL-53b · recorded, and said in the one voice.
      reportError('CoachVideoResponseScreen._send', e, st);
      if (!mounted || _uid != uid) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Semantics(liveRegion: true,
              child: Text(couldntMessage('send your response', e))),
          backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    // P0-FL-58 · past 1.3× the two buttons go under one another.
    final large = MediaQuery.textScalerOf(context).scale(12) > 12 * 1.3;
    final record = _ActionBtn(
      icon: Icons.videocam_rounded, label: 'Record Now',
      semanticLabel: 'Record Now, for ${widget.clientName}',
      color: _brand, onTap: _uploading ? null : _recordVideo);
    final gallery = _ActionBtn(
      icon: Icons.video_library_rounded, label: 'From Gallery',
      semanticLabel: 'From Gallery, for ${widget.clientName}',
      color: const Color(0xFF1A1020), onTap: _uploading ? null : _pickVideo);
    // P0-FL-58 r2 · nothing changes the video while a response is being sent.
    final removeVideo = _uploading ? null : _removeVideo;
    final selectVideo = _videoFile == null && !_uploading ? _pickVideo : null;
    // P0-FL-58 r2 · this screen's SnackBars are failures on red: their text is
    // white (the dark theme's default is dark text).
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(snackBarTheme: theme.snackBarTheme.copyWith(
        contentTextStyle: (theme.snackBarTheme.contentTextStyle ??
            theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(color: _wht))),
      child: Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _card, elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: _wht),
          tooltip: 'Close video response',
          onPressed: () => Navigator.pop(context)),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Video Response', style: TextStyle(color: _wht, fontSize: 17, fontWeight: FontWeight.w700)),
          if (!_hidden) Text('To ${widget.clientName}', style: const TextStyle(color: _mut, fontSize: 12)),
        ]),
      ),
      body: _signedOut
          ? Center(child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Semantics(liveRegion: true, child: const Text(
                "You're signed out — sign in again to send a video response.",
                textAlign: TextAlign.center, style: TextStyle(color: _wht, fontSize: 15)))))
          : _hidden ? const SizedBox.shrink()
          : _done ? _DoneView(clientName: widget.clientName, notified: _notified, onDone: () => Navigator.pop(context))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // ── Video preview / picker ────────────────────────────────────
                Semantics(
                  container: true,
                  button: _videoFile == null,
                  enabled: _videoFile == null ? !_uploading : null,
                  label: _videoFile == null ? 'Select a video for ${widget.clientName}, up to 5 minutes' : null,
                  onTap: selectVideo,
                  excludeSemantics: _videoFile == null,
                  child: GestureDetector(
                  onTap: selectVideo,
                  child: Container(
                    // P0-FL-58 · 200px at least: it grows with large text.
                    constraints: const BoxConstraints(minHeight: 200),
                    padding: EdgeInsets.symmetric(vertical: 8, horizontal: large ? 8 : 0),
                    decoration: BoxDecoration(
                      color: _card, borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _videoFile != null ? _tert.withValues(alpha: 0.4) : _brd, width: 2)),
                    child: _videoFile != null
                        ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            const Icon(Icons.videocam_rounded, color: _tert, size: 48),
                            const SizedBox(height: 8),
                            Text(_videoFile!.name,
                              style: const TextStyle(color: _tert, fontSize: 12),
                              textAlign: TextAlign.center,
                              maxLines: large ? null : 1,
                              overflow: large ? null : TextOverflow.ellipsis),
                            const SizedBox(height: 8),
                            Semantics(
                              container: true,
                              button: true,
                              enabled: removeVideo != null,
                              label: 'Remove ${_videoFile!.name}',
                              onTap: removeVideo,
                              excludeSemantics: true,
                              child: TextButton(
                                onPressed: removeVideo,
                                style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                                child: Text('Remove', style: TextStyle(
                                  color: removeVideo == null ? _mut.withValues(alpha: 0.4) : _mut,
                                  fontSize: 12)))),
                          ])
                        : const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(Icons.video_library_rounded, color: _mut, size: 40),
                            SizedBox(height: 12),
                            Text('Tap to select a video', textAlign: TextAlign.center,
                              style: TextStyle(color: _mut, fontSize: 14)),
                            SizedBox(height: 4),
                            Text('Up to 5 minutes', textAlign: TextAlign.center,
                              style: TextStyle(color: _mut, fontSize: 12)),
                          ]),
                  ),
                )),
                const SizedBox(height: 12),
                if (large) ...[
                  SizedBox(width: double.infinity, child: record),
                  const SizedBox(height: 12),
                  SizedBox(width: double.infinity, child: gallery),
                ] else
                  // Equal heights when one label wraps and the other does not.
                  IntrinsicHeight(child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(child: record),
                    const SizedBox(width: 12),
                    Expanded(child: gallery),
                  ])),
                const SizedBox(height: 24),
                // ── Written notes ────────────────────────────────────────────
                const Text('Written Notes (optional)',
                  style: TextStyle(color: _wht, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                // P0-FL-58 r2 · a name that stays once the hint is gone.
                MergeSemantics(child: Semantics(label: 'Written Notes (optional)', child: TextField(
                  controller: _noteCtrl,
                  maxLines: 4,
                  style: const TextStyle(color: _wht, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Add a written note to accompany your video...',
                    hintStyle: const TextStyle(color: _mut),
                    filled: true, fillColor: _card,
                    contentPadding: const EdgeInsets.all(16),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _brd)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _brd)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _brand))),
                ))),
                const SizedBox(height: 32),
                if (_uploading) ...[
                  LinearProgressIndicator(value: _progress, color: _brand, backgroundColor: _brd),
                  const SizedBox(height: 8),
                  Text('${(_progress * 100).round()}% uploaded...',
                    style: const TextStyle(color: _mut, fontSize: 12), textAlign: TextAlign.center),
                ] else
                  // P0-FL-58 · follows the note as it is typed: nothing rebuilt
                  // this screen, so a note alone could never be sent. The same
                  // rule as _send: a blank note is nothing to send (it enabled
                  // a Send that did nothing).
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _noteCtrl,
                    builder: (context, note, _) => SizedBox(width: double.infinity, child: ElevatedButton.icon(
                      onPressed: (_videoFile != null || note.text.trim().isNotEmpty) ? _send : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _brand, foregroundColor: _wht,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                      icon: const Icon(Icons.send_rounded),
                      label: Text('Send to Client',
                        semanticsLabel: 'Send to Client, ${widget.clientName}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ))),
              ]),
            ),
    ));
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final String semanticLabel;
  final Color color;
  /// Null is disabled: dimmed, and said so.
  final VoidCallback? onTap;
  const _ActionBtn({required this.icon, required this.label, required this.semanticLabel,
    required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    enabled: onTap != null,
    label: semanticLabel,
    onTap: onTap,
    excludeSemantics: true,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: onTap == null ? color.withValues(alpha: 0.4) : color,
          borderRadius: BorderRadius.circular(14)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: onTap == null ? _wht.withValues(alpha: 0.5) : _wht, size: 18),
          const SizedBox(width: 8),
          // P0-FL-58 · wraps instead of overflowing.
          Flexible(child: Text(label, style: TextStyle(
            color: onTap == null ? _wht.withValues(alpha: 0.5) : _wht,
            fontSize: 13, fontWeight: FontWeight.w600))),
        ]),
      ),
    ),
  );
}

class _DoneView extends StatelessWidget {
  final String clientName;
  final VoidCallback onDone;
  final bool notified;
  const _DoneView({required this.clientName, required this.notified, required this.onDone});
  @override
  // P0-FL-53b r3 · scrolls when the not-notified line, large text or a
  // short phone make it taller than the screen; centred otherwise.
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) =>
    SingleChildScrollView(child: ConstrainedBox(
    constraints: BoxConstraints(minHeight: box.maxHeight),
    child: Center(child: Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      // P0-FL-53b r2 · not notified: the warning colour and icon, a next step,
      // and a live region (the Done view replaces the form, so nothing else
      // would announce it). The notified path is unchanged.
      Container(width: 80, height: 80, decoration: BoxDecoration(
        color: (notified ? _tert : _warn).withValues(alpha: 0.15), shape: BoxShape.circle),
        child: notified
            ? const Icon(Icons.check_rounded, color: _tert, size: 44)
            : const Icon(Icons.warning_amber_rounded, color: _warn, size: 44)),
      const SizedBox(height: 20),
      const Text('Video Sent!', style: TextStyle(color: _wht, fontSize: 24, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      // P0-FL-53b · "has been notified" only when the notification was sent.
      if (notified)
        Text('$clientName has been notified and can watch your response.',
          style: const TextStyle(color: _mut, fontSize: 14), textAlign: TextAlign.center)
      else
        Semantics(liveRegion: true, child: Text(
          "Your response is saved, but $clientName wasn't notified — let them know another way.",
          style: const TextStyle(color: _warn, fontSize: 14), textAlign: TextAlign.center)),
      const SizedBox(height: 32),
      SizedBox(width: double.infinity, child: ElevatedButton(
        onPressed: onDone,
        style: ElevatedButton.styleFrom(
          backgroundColor: _brand, foregroundColor: _wht,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)))),
    ]),
  )))));
}
