// Coach Audio Coaching — Exercise Audio. A coach holds to record a short voice
// note on an exercise; every client performing it hears their coach. Recording
// is deliberately low-friction (hold → release → send, 30s cap, no trimming/
// naming). Playback is one tap with a lightweight waveform. Cached by the player.
//
// NOTE: audio capture/playback is device/browser-specific and cannot be verified
// headlessly — this needs on-device testing (mic permission + capture + upload +
// playback across web/iOS/Android). Structured against record ^7 / audioplayers ^6.
import 'dart:async';
import 'dart:io' show File;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsService;
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState, Supabase;
import '../../../../core/observability/app_failure.dart';
import '../../../../core/observability/network_failure.dart';
import '../../../workout/presentation/widgets/section_load_failure.dart';
import '../../data/custom_exercise_service.dart';

const _brand = Color(0xFFB76DFF);
const _mint  = Color(0xFFFF6B6B);
const _text  = Color(0xFFEDE7F3);
const _muted = Color(0xFFB6A9C4);
const _panel = Color(0xFF1B1526);

const _maxSeconds = 30;

/// Shown when the mic is refused. The hold gesture used to do nothing at all —
/// `if (!await _rec.hasPermission()) return;` — so a coach could not tell a
/// denied permission from a broken button.
const micDeniedMessage = 'Microphone access is off. Enable it in Settings to '
    'record a voice note.';

/// Shown when the note did not reach the server. `_stop()` ended in
/// `catch (_) {}`, and the `url == null` path fell through silently, so a
/// failed upload looked exactly like a successful one: the coach released, the
/// control reset, and nothing was saved.
///
/// P0-FL-59d · in the one voice, for a failure that is not the connection
/// (that one gets the connection hint). Said beside the control: a SnackBar
/// sat on the page, under the sheet the recorder is in.
const voiceUploadFailedMessage = "Couldn't send your voice note — try again in "
    'a moment. If it keeps happening, contact support.';

String? get _signedInUid => Supabase.instance.client.auth.currentUser?.id;

/// Text is scaled past 1.3×: the time goes under the text beside it.
bool _largeText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(12) > 12 * 1.3;

/// [bar] with what went wrong said under it, announced when it appears.
Widget _withFailure(Widget bar, String? failure) => Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    bar,
    if (failure != null) Padding(padding: const EdgeInsets.only(top: 8),
      child: Semantics(liveRegion: true, container: true,
        child: Text(failure, style: const TextStyle(color: _text, fontSize: 12.5, height: 1.4)))),
  ]);

// Fixed decorative bar heights — a waveform that "feels alive" without sampling
// the audio (transcription/analysis is intentionally out of scope for beta).
const _bars = [0.3, 0.6, 0.9, 0.5, 0.8, 1.0, 0.4, 0.7, 0.55, 0.85, 0.35, 0.65,
  0.95, 0.5, 0.75, 0.45, 0.9, 0.6, 0.3, 0.8, 0.5, 0.7, 0.4, 0.6];

// ── Recorder: hold to record, release to send ───────────────────────────────
class CoachVoiceRecorder extends StatefulWidget {
  final String exerciseId;
  final DateTime? Function() resolveExpiry;
  final VoidCallback onRecorded;
  const CoachVoiceRecorder({super.key,
    required this.exerciseId, required this.resolveExpiry, required this.onRecorded});
  @override
  State<CoachVoiceRecorder> createState() => _CoachVoiceRecorderState();
}

class _CoachVoiceRecorderState extends State<CoachVoiceRecorder> {
  final _rec = AudioRecorder();
  final _svc = CustomExerciseService();
  bool _recording = false, _busy = false;
  int _elapsed = 0;
  Timer? _timer;
  DateTime? _startedAt;

  /// The last thing that went wrong, said under the bar.
  String? _failure;

  /// `_start` is waiting (for the permission, for the recorder).
  bool _starting = false;

  /// Where the capture running now is written.
  String? _path;

  /// P0-FL-59d · the coach this recorder was opened by: what it captures is
  /// theirs, and is sent as theirs or not at all.
  String? _owner;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _owner = _signedInUid;
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen(
        (_) => _followAccount(),
        onError: (Object e, StackTrace s) =>
            reportError('CoachVoiceRecorder.onAuthStateChange', e, s));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _authSub?.cancel();
    // Closed while recording (or while it was starting): the capture is
    // stopped and removed, not left running or on the device.
    if (_recording || _starting) {
      unawaited(_abandon(release: true));
    } else {
      _rec.dispose();
    }
    super.dispose();
  }

  /// The previous coach's recording stops and is dropped; the next account
  /// starts with nothing said.
  void _followAccount() {
    final uid = _signedInUid;
    if (!mounted || uid == _owner) return;
    final wasRecording = _recording;
    _timer?.cancel();
    setState(() {
      _owner = uid;
      _recording = false;
      _busy = false;
      _failure = null;
    });
    if (wasRecording) unawaited(_abandon());
  }

  /// Stops the capture running now and removes it. Nothing is sent.
  Future<void> _abandon({bool release = false}) async {
    final capture = _path; // [_path] is the next coach's once they record
    try {
      final path = await _rec.stop();
      await _discard(path ?? capture);
    } catch (e, st) {
      reportError('CoachVoiceRecorder._abandon', e, st);
      await _discard(capture);
    }
    if (release) await _rec.dispose();
  }

  void _say(String message) {
    if (!mounted) return;
    setState(() => _failure = message);
  }

  /// Says it when [error] IS the connection; false otherwise.
  bool _saidOffline(Object? error) {
    if (!isNetworkFailure(error)) return false;
    _say(couldntMessage('send your voice note', error));
    return true;
  }

  /// True when [owner] is no longer signed in: recorded; nothing is sent.
  bool _accountChanged(String method, String? owner) {
    if (owner != null && _signedInUid == owner) return false;
    reportError('CoachVoiceRecorder.$method',
        StateError('Voice note: the signed-in account changed'));
    _followAccount();
    return true;
  }

  /// P0-FL-59d · the screen reader's way in: the bar is a hold gesture, which
  /// assistive tech cannot make. One activation starts, the next one stops
  /// and sends. (Touch is unchanged: hold, release.)
  void _toggle() => _recording ? _stop() : _start();

  Future<void> _start() async {
    if (_busy || _recording || _starting) return;
    final owner = _owner;
    if (_accountChanged('_start', owner)) return;
    _starting = true;
    if (_failure != null) setState(() => _failure = null);
    try {
      if (!await _rec.hasPermission()) {
        if (_signedInUid == owner) _say(micDeniedMessage);
        return;
      }
      final String path;
      if (kIsWeb) {
        path = 'coach-voice.m4a';
      } else {
        final dir = await getTemporaryDirectory();
        path = '${dir.path}/coach-voice-${DateTime.now().millisecondsSinceEpoch}.m4a';
      }
      if (!mounted) return;
      // The microphone is not opened for the next account.
      if (_accountChanged('_start', owner)) return;
      _path = path;
      await _rec.start(const RecordConfig(encoder: AudioEncoder.aacLc, numChannels: 1), path: path);
      _startedAt = DateTime.now();
      // `_start` awaits twice before this; the widget can be gone by now
      // (then `dispose` has stopped and removed the capture) — or the coach.
      if (!mounted) return;
      if (_accountChanged('_start', owner)) return _abandon();
      setState(() { _recording = true; _elapsed = 0; });
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return;
        setState(() => _elapsed++);
        if (_elapsed >= _maxSeconds) _stop();
      });
    } catch (e, st) {
      // P0-FL-59d · swallowed, and nothing said: a recorder that would not
      // start looked like a broken button.
      reportError('CoachVoiceRecorder._start', e, st);
      if (mounted) setState(() => _recording = false);
      if (_signedInUid == owner) _say(couldntMessage('start recording', e));
    } finally {
      _starting = false;
    }
  }

  Future<void> _stop() async {
    if (!_recording) return;
    final owner = _owner;
    if (_accountChanged('_stop', owner)) return; // dropped, not sent
    final capture = _path;
    _timer?.cancel();
    setState(() { _recording = false; _busy = true; });
    String? path;
    try {
      path = await _rec.stop();
      final durationMs = _startedAt == null ? 0 : DateTime.now().difference(_startedAt!).inMilliseconds;
      if (path == null && durationMs >= 800) {
        // Held long enough, and the recorder has nothing: that is a failure,
        // not a discarded tap.
        throw StateError('the recorder returned no recording');
      }
      if (path == null || durationMs < 800) { // discard taps
        if (mounted && _owner == owner) setState(() => _busy = false);
        return;
      }
      final bytes = await XFile(path).readAsBytes();
      // One coach across both steps: their path, their overlay row.
      if (_accountChanged('_stop', owner)) return;
      final url = await _svc.uploadCoachVoice(widget.exerciseId, bytes,
          expectedUid: owner);
      // `url == null` is how `uploadCoachVoice` reports failure — it catches
      // internally and stashes `lastError`. Falling through silently here is
      // what made a failed send indistinguishable from a successful one.
      // (The service has recorded it.)
      if (url == null) {
        if (_signedInUid != owner) return; // not said to the next account
        if (!_saidOffline(_svc.lastError)) _say(voiceUploadFailedMessage);
      } else {
        final saved = await _svc.setCoachVoice(
            widget.exerciseId, url, durationMs, widget.resolveExpiry(),
            expectedUid: owner);
        if (_signedInUid != owner) return;
        if (saved) {
          // The bar only goes back to rest: said once, to assistive tech.
          if (mounted) {
            unawaited(SemanticsService.sendAnnouncement(
                View.of(context), 'Voice note sent', Directionality.of(context)));
          }
          widget.onRecorded();
        } else if (!_saidOffline(_svc.lastError)) {
          _say(voiceUploadFailedMessage);
        }
      }
    } catch (e, st) {
      // P0-FL-59d · a recording that could not be stopped or read was said
      // but never recorded.
      reportError('CoachVoiceRecorder._stop', e, st);
      if (_signedInUid == owner && !_saidOffline(e)) _say(voiceUploadFailedMessage);
    } finally {
      // The capture is a real audio file of the coach's voice sitting in the
      // device's temp directory. It was never removed, so every recording
      // accumulated there for the lifetime of the install — including the
      // sub-800ms ones discarded as taps, which were never even uploaded.
      // (A recorder that would not stop may still have left its file.)
      path ??= capture;
      await _discard(path);
    }
    if (mounted && _owner == owner) setState(() => _busy = false);
  }

  /// Removes the local capture once it has been read.
  ///
  /// Web records to an in-memory/blob path that is not a filesystem entry, so
  /// there is nothing to unlink there.
  Future<void> _discard(String? path) async {
    if (path == null || kIsWeb) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (e, st) {
      // Best effort: a temp file that will not delete must not fail the send —
      // but a recording left on the device is recorded.
      reportError('CoachVoiceRecorder._discard', e, st);
    }
  }

  @override
  Widget build(BuildContext context) {
    final large = _largeText(context);
    final left = Text('${_maxSeconds - _elapsed}s',
        style: const TextStyle(color: _muted, fontSize: 11));
    // The label changes with the state and is announced; the seconds are not
    // in it (one announcement, not thirty). It starts with the words on the
    // bar, so "tap Hold to record" finds it.
    return _withFailure(Semantics(
      container: true,
      button: true,
      enabled: !_busy,
      liveRegion: _recording || _busy,
      label: _busy ? 'Sending… voice note'
          : _recording ? 'Recording… Double-tap to stop and send'
          : 'Hold to record a voice note, up to $_maxSeconds seconds. '
              'Double-tap to start or stop',
      onTap: _busy ? null : _toggle,
      excludeSemantics: true,
      child: GestureDetector(
      onLongPressStart: (_) => _start(),
      onLongPressEnd: (_) => _stop(),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: _recording ? _mint.withValues(alpha: 0.18) : _panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: (_recording ? _mint : _brand).withValues(alpha: 0.4))),
        child: Row(children: [
          if (_busy)
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: _brand, strokeWidth: 2))
          else
            Icon(_recording ? Icons.stop_circle_rounded : Icons.mic_rounded,
                color: _recording ? _mint : _brand, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              _busy ? 'Sending…'
                    : _recording ? 'Recording… ${_elapsed}s  (release to send)'
                                 : 'Hold to record a voice note',
              style: TextStyle(color: _recording ? _mint : _text, fontSize: 13.5, fontWeight: FontWeight.w600)),
            if (_recording && large) left,
          ])),
          if (_recording && !large) left,
        ]),
      ),
    )), _failure);
  }
}

// ── Player: one tap, waveform fills with progress ───────────────────────────
class CoachVoicePlayer extends StatefulWidget {
  final String url;
  final int? durationMs;
  final String? coachName;
  const CoachVoicePlayer({super.key, required this.url, this.durationMs, this.coachName});
  @override
  State<CoachVoicePlayer> createState() => _CoachVoicePlayerState();
}

class _CoachVoicePlayerState extends State<CoachVoicePlayer> {
  final _player = AudioPlayer();
  final _svc = CustomExerciseService();
  bool _playing = false;
  double _progress = 0; // 0..1
  Duration _total = Duration.zero;

  /// Paused part-way (not "never played", nor a play that failed).
  bool _paused = false;

  /// The last thing that went wrong, said under the player.
  String? _failure;

  /// This attempt's playing failed: its other streams repeat it.
  bool _playFailed = false;

  /// Starting (or pausing) is in flight: no second one.
  bool _busy = false;

  /// Announce its states once it has been used.
  bool _used = false;

  /// P0-FL-59d · the account this note is shown to. It goes quiet when that
  /// account leaves — a hidden tab draws nothing, so nothing else would — and
  /// plays for nobody else.
  String? _owner;
  bool _away = false;

  /// Counts what was started for an owner who stayed: earlier ones are dropped.
  int _run = 0;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _owner = _signedInUid;
    // Same account (a token refresh, the stream's replay) changes nothing.
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen(
        (_) => _followAccount(),
        onError: (Object e, StackTrace s) =>
            reportError('CoachVoicePlayer.onAuthStateChange', e, s));
    if (widget.durationMs != null) _total = Duration(milliseconds: widget.durationMs!);
    // P0-FL-59d · the player's own failures (a recording that will not load
    // or stops part-way) arrive as errors on EVERY one of its streams, and
    // nothing listened for them: recorded and said once, here.
    _player.onDurationChanged.listen((d) { if (mounted && d > Duration.zero) setState(() => _total = d); },
        onError: (Object e, StackTrace st) => _failed(e, st));
    _player.onPositionChanged.listen((p) {
      // (A position that lands once it has stopped is not a place to resume.)
      if (!mounted || !_playing || _total == Duration.zero) return;
      setState(() => _progress = (p.inMilliseconds / _total.inMilliseconds).clamp(0, 1));
    }, onError: (Object _) {/* said by the first listener */});
    _player.onPlayerComplete.listen((_) { if (mounted) setState(() { _playing = _paused = false; _progress = 0; }); },
        onError: (Object _) {/* said by the first listener */});
  }

  void _followAccount() {
    final away = _signedInUid != _owner;
    if (!mounted || away == _away) return;
    _away = away;
    if (!away) return; // theirs again: at rest
    _run++;
    if (_used) unawaited(_silence());
    setState(() {
      _playing = _paused = _busy = _used = _playFailed = false;
      _progress = 0;
      _failure = null;
    });
  }

  /// Stops what plays (or is about to) and lets its source go.
  Future<void> _silence() async {
    try {
      await _player.release();
    } catch (e, st) {
      // (Disposed meanwhile: that stopped it.)
      if (mounted) reportError('CoachVoicePlayer._silence', e, st);
    }
  }

  /// What is playing now is not playing, and that is said. Play starts again
  /// from a fresh link: what failed cannot be resumed.
  void _failed(Object e, StackTrace st) {
    if (!mounted) return;
    // `play` throws what the streams also carry: one failure, recorded once.
    if (!_playFailed) reportError('CoachVoicePlayer._toggle', e, st);
    if (_signedInUid != _owner) return _followAccount(); // not said to them
    setState(() {
      _playing = _paused = false;
      _playFailed = true;
      _progress = 0;
      _failure = couldntMessage('play this voice note', e);
    });
  }

  @override
  void dispose() { _authSub?.cancel(); _player.dispose(); super.dispose(); }

  Future<void> _toggle() async {
    if (_busy) return;
    if (_signedInUid != _owner) {
      reportError('CoachVoicePlayer._toggle',
          StateError('Playing a voice note: the signed-in account changed'));
      return _followAccount();
    }
    final run = _run;
    // Still this attempt's account; otherwise it has gone quiet (or does now).
    bool mine() {
      if (!mounted || run != _run) return false;
      if (_signedInUid == _owner) return true;
      _followAccount();
      return false;
    }

    setState(() { _busy = _used = true; _failure = null; _playFailed = false; });
    try {
      if (_playing) {
        try {
          await _player.pause();
        } catch (e, st) {
          // It plays on, and Pause stays what the control does.
          reportError('CoachVoicePlayer._toggle', e, st);
          if (mounted && mine()) {
            setState(() => _failure = couldntMessage('pause this voice note', e));
          }
          return;
        }
        if (mounted && mine() && _playing) setState(() { _playing = false; _paused = true; });
        return;
      }
      if (_progress == 0) {
        // SEC-VOICE-1: sign at render time rather than replaying the stored
        // public URL. A signed URL expires; the stored one never does. The
        // fallback keeps legacy rows playable while the bucket is still
        // public — once it is private, an unsigned URL cannot play and the
        // fallback becomes a no-op rather than a silent bypass.
        final signed = await _svc.signedCoachVoiceUrl(widget.url);
        // Gone, or another account's now: nothing is played to them.
        if (!mounted || !mine()) return;
        if (signed == null && _svc.lastError != null && !widget.url.contains('://')) {
          // A stored path is not a URL: unsigned, there is nothing to play.
          // (The service has recorded why.)
          setState(() => _failure =
              couldntMessage('play this voice note', _svc.lastError));
          return;
        }
        await _player.play(UrlSource(signed ?? widget.url));
      } else {
        await _player.resume();
      }
      if (!mounted || !mine() || _playFailed) return;
      setState(() { _playing = true; _paused = false; });
    } catch (e, st) {
      // P0-FL-59d · swallowed: a note that would not play did nothing.
      if (run == _run) {
        _failed(e, st);
      } else {
        reportError('CoachVoicePlayer._toggle', e, st); // not this account's
      }
    } finally {
      if (mounted && run == _run) setState(() => _busy = false);
    }
  }

  String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final name = widget.coachName != null ? 'Listen to ${widget.coachName}' : 'Coach voice note';
    final large = _largeText(context);
    final time = Text(_fmt(_total), style: const TextStyle(color: _muted, fontSize: 11));
    return _withFailure(Semantics(
      container: true,
      button: true,
      enabled: !_busy,
      liveRegion: _used,
      label: '$name: ${_playing ? 'pause' : 'play'}'
          '${_total == Duration.zero ? '' : ', ${_total.inSeconds} seconds'}',
      value: _playing ? 'Playing' : _busy ? 'Loading' : _paused ? 'Paused' : null,
      onTap: _busy ? null : _toggle,
      excludeSemantics: true,
      child: GestureDetector(
      onTap: _toggle,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _brand.withValues(alpha: 0.3))),
        child: Row(children: [
          Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: _brand, size: 22),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name,
                style: const TextStyle(color: _text, fontSize: 12.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            SizedBox(height: 20, child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [for (var i = 0; i < _bars.length; i++)
                Expanded(child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  height: 4 + _bars[i] * 16,
                  decoration: BoxDecoration(
                    color: (i / _bars.length) <= _progress ? _brand : _brand.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2)),
                ))],
            )),
            if (large) ...[const SizedBox(height: 6), time],
          ])),
          if (!large) ...[const SizedBox(width: 8), time],
        ]),
      ),
    )), _failure);
  }
}
