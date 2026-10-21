import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/features/exercise_database/data/custom_exercise_service.dart';

/// SEC-VOICE-1 (deletion arm) — removing a voice note must remove the audio.
///
/// ── THE DEFECT ─────────────────────────────────────────────────────────────
/// `clearCoachVoice()` nulled the row's columns and left the object in place.
/// `coach-media` is a **public** bucket — verified live: it serves the public
/// object route with no credentials at all, while `progress-photos`,
/// `chat-media` and `messages` refuse it. The only `storage.remove()` in the
/// whole app was `chat_screen.dart:244`, for the private chat bucket.
///
/// So a coach removed a voice note, the app stopped showing it, and the
/// recording stayed permanently fetchable by anyone who had ever held the URL.
/// The row carries `voice_expires_at` — an expiry the object never honoured.
///
/// The path derivation is pure and is tested directly. The delete itself needs
/// a live authenticated coach session (OD-51), so the wiring is asserted from
/// source and labelled.
void main() {
  group('the object path is derived safely', () {
    test('a real public URL yields its object path', () {
      expect(
        CustomExerciseService.coachVoiceObjectPath(
            'https://ref.supabase.co/storage/v1/object/public/coach-media/voice/u1/e2-123.m4a'),
        'voice/u1/e2-123.m4a',
      );
    });

    test('a query string is not part of the path', () {
      expect(
        CustomExerciseService.coachVoiceObjectPath(
            'https://ref.supabase.co/storage/v1/object/public/coach-media/voice/u1/e2-123.m4a?t=9'),
        'voice/u1/e2-123.m4a',
      );
    });

    test('a foreign or malformed value never becomes a delete target', () {
      // A delete must never be issued against a path this code did not create.
      for (final u in <String?>[
        null,
        '',
        'https://evil.example/object/public/coach-media/',
        'https://ref.supabase.co/storage/v1/object/public/progress-photos/u1/front.jpg',
        'voice/u1/e2.m4a',
        'https://ref.supabase.co/storage/v1/object/public/coach-media/',
      ]) {
        expect(CustomExerciseService.coachVoiceObjectPath(u), isNull,
            reason: 'derived a delete path from: ${u ?? "null"}');
      }
    });
  });

  group('[SOURCE] the clear path is wired to it', () {
    late String src;
    setUpAll(() {
      src = File('lib/features/exercise_database/data/custom_exercise_service.dart')
          .readAsStringSync();
    });

    /// The method body, to its closing brace — NOT a fixed character window.
    ///
    /// This was `substring(start, start + 1400)`. Adding a comment to the
    /// method pushed `.remove([path])` outside the window and the guard failed
    /// on a change that altered no behaviour. A guard that a comment can break
    /// is a guard that will be edited to pass.
    String clearBody() {
      final start = src.indexOf('Future<bool> clearCoachVoice(');
      expect(start, greaterThan(0), reason: 'clearCoachVoice has moved');
      final end = src.indexOf('\n  }', start);
      expect(end, greaterThan(start), reason: 'could not find the method end');
      return src.substring(start, end);
    }

    test('clearCoachVoice removes the object', () {
      final body = clearBody();

      expect(body, contains("storage.from('coach-media').remove("),
          reason: 'the recording is left in a public bucket again');

      // SEC-VOICE-2. It must be `coachVoiceSigningPath`, NOT
      // `coachVoiceObjectPath`. The latter parses the public-URL form ONLY, so
      // once `uploadCoachVoice` began storing a bare object path it returned
      // null for every new row, `remove()` was skipped, the row was nulled and
      // the method still returned `true` — the app reporting a deletion it had
      // not performed, which is the defect this whole guard exists for.
      expect(body, contains('coachVoiceSigningPath('),
          reason: 'the delete target must be resolved by the normaliser that '
              'accepts BOTH a legacy public URL and a stored object path; '
              'coachVoiceObjectPath silently skips every post-SEC-VOICE-2 row');
      expect(body.contains('coachVoiceObjectPath('), isFalse,
          reason: 'the URL-only parser is back in the delete path');
    });

    test('the removal is not swallowed', () {
      final body = clearBody();
      // A swallowed remove would let the app claim a deletion it did not do.
      final removeAt = body.indexOf('.remove([path])');
      final updateAt = body.indexOf("'voice_url': null");
      expect(removeAt, greaterThan(0));
      expect(updateAt, greaterThan(removeAt),
          reason: 'the object must be removed BEFORE the row is cleared, or a '
              'failed delete leaves an unreferenced public recording');
      expect(RegExp(r'remove\(\[path\]\)\s*;\s*\}\s*catch').hasMatch(body), isFalse,
          reason: 'the remove must not sit in its own swallowing catch');
    });
  });
}
