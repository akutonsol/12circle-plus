import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/features/exercise_database/data/custom_exercise_service.dart';

/// VOICE-G2 — SEC-VOICE-2. What is **stored** for a coach voice note must be
/// an object path, never a public URL.
///
/// The previous wave added `signedCoachVoiceUrl` and recorded SEC-VOICE-1's
/// "Dart prerequisite" as DONE. Only the *display* half had been done:
/// `uploadCoachVoice` still returned `getPublicUrl(path)` and `setCoachVoice`
/// persisted it into `coach_exercise_media.voice_url`, so every row held a
/// permanent unauthenticated link to a recording of a coach's voice — on a
/// bucket confirmed public by live probe. Signing a value at render time does
/// nothing about the value already written to the database.
///
/// ── THE TRAP THIS GUARD EXISTS FOR ─────────────────────────────────────────
/// Changing the upload alone **silently breaks deletion**. `clearCoachVoice`
/// resolved its delete target with `coachVoiceObjectPath`, which parses the
/// public-URL form ONLY. Given a bare path it returns null, `remove()` is
/// skipped, the row is nulled and the method still returns `true` — the app
/// reporting a deletion it did not perform, leaving the audio in a public
/// bucket. That is the exact defect `coach_voice_deletion_guard_test` was
/// written to close, reintroduced by a one-line "fix" elsewhere.
///
/// Both halves are asserted here, and the resolver is exercised on real values
/// rather than grepped for a token.
void main() {
  late String src;

  setUpAll(() {
    src = File('lib/features/exercise_database/data/'
            'custom_exercise_service.dart')
        .readAsStringSync();
  });

  String body(String signature) {
    final start = src.indexOf(signature);
    expect(start, greaterThan(0), reason: '$signature has moved');
    final end = src.indexOf('\n  }', start);
    expect(end, greaterThan(start));
    return src.substring(start, end);
  }

  test('VOICE-G2 the guard is reading the right file', () {
    // An absent result must not read as "no leak" — the H-D1 lesson.
    expect(src, contains('class CustomExerciseService'));
    expect(src, contains("storage.from('coach-media').uploadBinary"));
  });

  test('VOICE-G2 the upload stores a path, not a public URL', () {
    final b = body('Future<String?> uploadCoachVoice(');

    expect(b.contains('getPublicUrl'), isFalse,
        reason: 'uploadCoachVoice is minting a permanent unauthenticated URL '
            'again. `coach-media` is PUBLIC, so that URL is readable by anyone '
            'who obtains it, forever, with no auth — and it is persisted into '
            'coach_exercise_media.voice_url. Return the object path; '
            'signedCoachVoiceUrl signs it at render time.');
    expect(b, contains('return path;'),
        reason: 'the value returned must be the storage object path');
    // The path must stay coach-scoped, not become a shared prefix.
    expect(b, contains(r"'voice/$uid/$exerciseId-"),
        reason: 'the object path no longer scopes by coach and exercise');
  });

  test('VOICE-G2 the stored path round-trips through the resolver', () {
    // Behavioural, not a grep: this is the value uploadCoachVoice now returns.
    const stored = 'voice/abc-123/ex-9-1699999999999.m4a';
    expect(CustomExerciseService.coachVoiceSigningPath(stored), stored,
        reason: 'a freshly stored path must resolve, or playback AND deletion '
            'both silently no-op for every new note');
  });

  test('VOICE-G2 legacy public-URL rows still resolve', () {
    // Rows written before this change still hold a full URL. If the resolver
    // stops accepting them, every existing note becomes unplayable and
    // undeletable — the migration-free property that let this land.
    const legacy =
        'https://x.supabase.co/storage/v1/object/public/coach-media/'
        'voice/abc-123/ex-9-1600000000000.m4a?t=1';
    expect(CustomExerciseService.coachVoiceSigningPath(legacy),
        'voice/abc-123/ex-9-1600000000000.m4a');
  });

  test('VOICE-G2 a foreign or malformed value is never resolved', () {
    // Deletion runs `storage.remove([path])` on whatever comes back, so a
    // permissive resolver is a delete against a path this code did not write.
    for (final bad in <String?>[
      null,
      '',
      'https://evil.example.com/object/public/other-bucket/x.m4a',
      '../../etc/passwd',
      'voice-but-not-a-prefix/x.m4a',
      'https://x.supabase.co/storage/v1/object/public/progress-photos/a.jpg',
    ]) {
      expect(CustomExerciseService.coachVoiceSigningPath(bad), isNull,
          reason: 'resolved a value it did not write: ${bad ?? "null"}');
    }
  });

  test('VOICE-G2 deletion resolves stored values with the same normaliser', () {
    // The trap in this file's header. If the delete path uses the URL-only
    // parser, every post-SEC-VOICE-2 row is skipped and the app claims a
    // deletion it did not perform.
    final b = body('Future<bool> clearCoachVoice(');
    expect(b, contains('coachVoiceSigningPath('),
        reason: 'clearCoachVoice must resolve through the normaliser that '
            'accepts both forms');
    expect(b.contains('coachVoiceObjectPath('), isFalse,
        reason: 'the URL-only parser is back in the delete path — new rows '
            'will be nulled without their audio being removed');
  });
}
