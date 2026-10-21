import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
const _bg    = Color(0xFF030303);
const _card  = Color(0xFF0E0B16);
const _brd   = Color(0xFF1A1020);
const _brand = Color(0xFFA855F7);
const _tert  = Color(0xFF6FFBBE);
const _wht   = Colors.white;
const _mut   = Color(0xFFCFC2D6);

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
  bool _done = false;
  double _progress = 0;

  @override
  void dispose() { _noteCtrl.dispose(); super.dispose(); }

  Future<void> _recordVideo() async {
    try {
      final video = await ImagePicker().pickVideo(
        source: ImageSource.camera, maxDuration: const Duration(minutes: 5));
      if (video != null && mounted) setState(() => _videoFile = video);
    } catch (e) {
      _err('Recording not available here — try “From Gallery”.');
    }
  }

  Future<void> _pickVideo() async {
    try {
      final video = await ImagePicker().pickVideo(source: ImageSource.gallery);
      if (video != null && mounted) setState(() => _videoFile = video);
    } catch (e) {
      _err('Could not open that video. Try another file.');
    }
  }

  void _err(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), backgroundColor: Colors.red));
  }

  Future<void> _send() async {
    if (_videoFile == null && _noteCtrl.text.trim().isEmpty) return;
    setState(() { _uploading = true; _progress = 0; });

    try {
      final uid = _db.auth.currentUser?.id;
      String? videoUrl;

      if (_videoFile != null) {
        // Read bytes + uploadBinary so it works on web AND mobile (no dart:io).
        final ext = _videoFile!.name.contains('.') ? _videoFile!.name.split('.').last.toLowerCase() : 'mp4';
        final mime = ext == 'mov' ? 'video/quicktime' : ext == 'webm' ? 'video/webm' : 'video/mp4';
        final bytes = await _videoFile!.readAsBytes();
        final path = 'coach-videos/$uid/${widget.clientId}/${DateTime.now().millisecondsSinceEpoch}.$ext';
        if (!mounted) return;
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
      }

      await _db.from('coach_video_responses').insert({
        'coach_id': uid,
        'client_id': widget.clientId,
        'checkin_id': widget.checkinId,
        'video_url': videoUrl,
        'notes': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        'created_at': DateTime.now().toIso8601String(),
      });

      await _db.from('notifications').insert({
        'recipient_id': widget.clientId,
        'type': 'coach_video',
        'title': 'New video from your coach!',
        'body': 'Your coach recorded a personal video response for you. Tap to watch.',
        'read': false,
      });

      if (!mounted) return;
      setState(() { _progress = 1.0; _done = true; _uploading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        // ERR-2: was `Text('Error: \$e')`. A Postgres/Storage error carries
        // table, column and constraint text; a coach does not need it and
        // should not be shown it. Copy matches this repository's own
        // `Failed to … Try again.` pattern.
        const SnackBar(content: Text('Failed to send your response. Try again.'),
            backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _card, elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: _wht),
          onPressed: () => Navigator.pop(context)),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Video Response', style: TextStyle(color: _wht, fontSize: 17, fontWeight: FontWeight.w700)),
          Text('To ${widget.clientName}', style: const TextStyle(color: _mut, fontSize: 12)),
        ]),
      ),
      body: _done ? _DoneView(clientName: widget.clientName, onDone: () => Navigator.pop(context))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // ── Video preview / picker ────────────────────────────────────
                GestureDetector(
                  onTap: _videoFile == null ? _pickVideo : null,
                  child: Container(
                    height: 200,
                    decoration: BoxDecoration(
                      color: _card, borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _videoFile != null ? _tert.withValues(alpha: 0.4) : _brd, width: 2)),
                    child: _videoFile != null
                        ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            const Icon(Icons.videocam_rounded, color: _tert, size: 48),
                            const SizedBox(height: 8),
                            Text(_videoFile!.name,
                              style: const TextStyle(color: _tert, fontSize: 12),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () => setState(() => _videoFile = null),
                              child: const Text('Remove', style: TextStyle(color: _mut, fontSize: 12))),
                          ])
                        : const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(Icons.video_library_rounded, color: _mut, size: 40),
                            SizedBox(height: 12),
                            Text('Tap to select a video', style: TextStyle(color: _mut, fontSize: 14)),
                            SizedBox(height: 4),
                            Text('Up to 5 minutes', style: TextStyle(color: _mut, fontSize: 12)),
                          ]),
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _ActionBtn(
                    icon: Icons.videocam_rounded, label: 'Record Now',
                    color: _brand, onTap: _recordVideo)),
                  const SizedBox(width: 12),
                  Expanded(child: _ActionBtn(
                    icon: Icons.video_library_rounded, label: 'From Gallery',
                    color: const Color(0xFF1A1020), onTap: _pickVideo)),
                ]),
                const SizedBox(height: 24),
                // ── Written notes ────────────────────────────────────────────
                const Text('Written Notes (optional)',
                  style: TextStyle(color: _wht, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
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
                ),
                const SizedBox(height: 32),
                if (_uploading) ...[
                  LinearProgressIndicator(value: _progress, color: _brand, backgroundColor: _brd),
                  const SizedBox(height: 8),
                  Text('${(_progress * 100).round()}% uploaded...',
                    style: const TextStyle(color: _mut, fontSize: 12), textAlign: TextAlign.center),
                ] else
                  SizedBox(width: double.infinity, child: ElevatedButton.icon(
                    onPressed: (_videoFile != null || _noteCtrl.text.isNotEmpty) ? _send : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _brand, foregroundColor: _wht,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    icon: const Icon(Icons.send_rounded),
                    label: const Text('Send to Client', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  )),
              ]),
            ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn({required this.icon, required this.label, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: _wht, size: 18),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: _wht, fontSize: 13, fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}

class _DoneView extends StatelessWidget {
  final String clientName;
  final VoidCallback onDone;
  const _DoneView({required this.clientName, required this.onDone});
  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 80, height: 80, decoration: BoxDecoration(
        color: _tert.withValues(alpha: 0.15), shape: BoxShape.circle),
        child: const Icon(Icons.check_rounded, color: _tert, size: 44)),
      const SizedBox(height: 20),
      const Text('Video Sent!', style: TextStyle(color: _wht, fontSize: 24, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Text('$clientName has been notified and can watch your response.',
        style: const TextStyle(color: _mut, fontSize: 14), textAlign: TextAlign.center),
      const SizedBox(height: 32),
      SizedBox(width: double.infinity, child: ElevatedButton(
        onPressed: onDone,
        style: ElevatedButton.styleFrom(
          backgroundColor: _brand, foregroundColor: _wht,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)))),
    ]),
  ));
}
