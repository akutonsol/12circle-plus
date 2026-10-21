import 'dart:io';

import 'package:flutter_test/flutter_test.dart';


/// VOICE-G1 — a voice note that did not send must not look like one that did,
/// and the capture must not be left on the device.
///
/// ── WHY THIS IS A SOURCE GUARD ─────────────────────────────────────────────
/// The file says so itself, in its own header:
///
/// > *"audio capture/playback is device/browser-specific and cannot be verified
/// > headlessly — this needs on-device testing (mic permission + capture +
/// > upload + playback across web/iOS/Android)."*
///
/// `AudioRecorder` and `CustomExerciseService` are both constructed as fields,
/// so neither can be substituted, and the widget cannot be pumped through a
/// real record → upload cycle in a test. These assertions prove the branches
/// exist; the header's on-device run is what proves they work. Recorded that
/// way rather than dressed up.
void main() {
  late String src;

  setUpAll(() {
    src = File('lib/features/exercise_database/presentation/widgets/'
            'coach_voice.dart')
        .readAsStringSync();
  });

  test('VOICE-G1 the guard is reading the right file', () {
    // An absent result must not read as "no defects" — the H-D1 lesson.
    expect(src, contains('class CoachVoiceRecorder'));
    expect(src, contains('_rec.hasPermission()'));
  });

  test('VOICE-G1 a refused microphone says so', () {
    // `if (!await _rec.hasPermission()) return;` — the hold gesture did
    // nothing at all, so a coach could not tell a denied permission from a
    // broken button.
    final start = src.indexOf('Future<void> _start() async {');
    final body = src.substring(start, src.indexOf('Future<void> _stop()', start));
    expect(body, contains('hasPermission()'));
    expect(body, contains('micDeniedMessage'),
        reason: 'a denied microphone is silent again');
  });

  test('VOICE-G1 a failed send is reported, not swallowed', () {
    final start = src.indexOf('Future<void> _stop() async {');
    final body = src.substring(start, src.indexOf('Future<void> _discard', start));

    // `uploadCoachVoice` reports failure by RETURNING NULL — it catches
    // internally and stashes `lastError`. The old code fell through that case
    // without a word, and ended in a bare `catch (_) {}`.
    // Checking the method merely CONTAINS the message is not enough: it also
    // appears in the catch and in the unsaved-row branch, so deleting it from
    // the `url == null` arm left this passing. Assert the arm itself.
    final nullArm = body.substring(
        body.indexOf('if (url == null) {'), body.indexOf('} else {'));
    expect(nullArm, contains('_say(voiceUploadFailedMessage)'),
        reason: 'a failed upload falls through without a word again — '
            '`uploadCoachVoice` reports failure by returning null');

    expect(body, contains('voiceUploadFailedMessage'),
        reason: 'a failed upload is silent again');
    expect(RegExp(r'catch\s*\(_\)\s*\{\s*\}').hasMatch(body), isFalse,
        reason: 'the empty catch is back — a failed send looks identical to a '
            'successful one');
    // And a failed `setCoachVoice` must not fire the success callback.
    expect(body, contains('if (saved)'),
        reason: 'the row write is unchecked again, so the note can be uploaded '
            'and never attached while the UI reports success');
  });

  test('VOICE-G1 the capture is removed from the device', () {
    // A real audio file of the coach's voice was written to the temp directory
    // on every hold — including sub-800ms taps that were discarded and never
    // uploaded — and nothing ever deleted it.
    expect(src, contains('Future<void> _discard('));
    expect(src, contains('await f.delete()'));

    final stop = src.substring(src.indexOf('Future<void> _stop() async {'),
        src.indexOf('Future<void> _discard'));
    expect(stop, contains('await _discard(path)'));
    expect(stop, contains('} finally {'),
        reason: 'cleanup must run on the failure paths too, which is where a '
            'capture is most likely to be left behind');
  });

  test('VOICE-G1 no setState crosses an await without a mounted check', () {
    // `_start` awaits twice before setState. A coach who releases and leaves
    // the screen disposed the widget mid-await.
    final start = src.indexOf('Future<void> _start() async {');
    final body = src.substring(start, src.indexOf('Future<void> _stop()', start));
    expect(body, contains('if (!mounted)'),
        reason: 'setState after dispose throws');
  });
}
