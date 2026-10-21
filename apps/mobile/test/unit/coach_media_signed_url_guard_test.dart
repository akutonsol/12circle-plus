import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/features/exercise_database/data/custom_exercise_service.dart';

/// SEC-VOICE-1 (prerequisite) — protected media must be signed at render time.
///
/// ── WHY THIS LANDS BEFORE THE MIGRATION ────────────────────────────────────
/// `docs/proposed/SEC_VOICE_1_coach_media_private.sql` is AUTHORED and
/// unnumbered, and it says plainly that it **must not be applied alone**:
/// three `getPublicUrl()` call sites would have to move to `createSignedUrl()`
/// in the same change, or every existing coach voice note and video stops
/// loading the moment the bucket goes private.
///
/// Signing works on a **public** bucket too. So this half lands now, safely,
/// and removes the regression that currently blocks the migration.
///
/// ── WHAT IT DOES AND DOES NOT CHANGE ───────────────────────────────────────
/// It does **not** close SEC-VOICE-1. The bucket is still public and an object
/// is still fetchable by anyone holding a path. What changes is that the app
/// stops *minting* permanent unauthenticated URLs at playback, and that the
/// migration can now land without breaking playback.
void main() {
  group('path derivation never signs something foreign', () {
    test('a coach-media public URL yields its path', () {
      expect(
        CustomExerciseService.coachVoiceObjectPath(
            'https://ref.supabase.co/storage/v1/object/public/coach-media/voice/u1/e2-1.m4a'),
        'voice/u1/e2-1.m4a',
      );
    });

    test('another bucket, a relative path, or junk yields nothing', () {
      for (final u in <String?>[
        null,
        '',
        'https://ref.supabase.co/storage/v1/object/public/progress-photos/u1/front.jpg',
        'https://evil.example/object/public/coach-media/',
        'voice/u1/e2.m4a', // bare path — not a URL, handled separately
      ]) {
        expect(CustomExerciseService.coachVoiceObjectPath(u), isNull,
            reason: 'would have derived a signing target from: ${u ?? "null"}');
      }
    });
  });

  group('only a coach-media object may be signed', () {
    test('a coach-media URL and a bare voice/ path are signable', () {
      expect(
        CustomExerciseService.coachVoiceSigningPath(
            'https://ref.supabase.co/storage/v1/object/public/coach-media/voice/u1/e2-1.m4a'),
        'voice/u1/e2-1.m4a',
      );
      expect(CustomExerciseService.coachVoiceSigningPath('voice/u1/e2-1.m4a'),
          'voice/u1/e2-1.m4a');
    });

    test('nothing else is', () {
      for (final u in <String?>[
        null,
        '',
        'https://ref.supabase.co/storage/v1/object/public/progress-photos/u1/front.jpg',
        'https://evil.example/voice/u1/e2.m4a',
        'voice/../../etc/passwd'.replaceFirst('voice/', 'other/'),
        'https://evil.example/object/public/coach-media/',
        'chat/u1/photo.jpg',
      ]) {
        expect(CustomExerciseService.coachVoiceSigningPath(u), isNull,
            reason: 'would sign: ${u ?? "null"}');
      }
    });
  });

  group('[SOURCE] the player signs rather than replaying the stored URL', () {
    late String player;
    late String service;

    setUpAll(() {
      player = File('lib/features/exercise_database/presentation/widgets/'
              'coach_voice.dart')
          .readAsStringSync();
      service = File('lib/features/exercise_database/data/'
              'custom_exercise_service.dart')
          .readAsStringSync();
    });

    test('the guard is reading the real playback path', () {
      // An absent result must not read as "it signs" — the H-D1 lesson.
      expect(player, contains('UrlSource('));
      expect(player, contains('class CoachVoicePlayer'));
    });

    test('playback resolves a signed URL first', () {
      expect(player, contains('signedCoachVoiceUrl(widget.url)'),
          reason: 'playback is replaying the stored permanent URL again');
      expect(player, contains('UrlSource(signed ?? widget.url)'),
          reason: 'the signed value must be what is played');
    });

    test('the signer uses createSignedUrl with an expiry, on coach-media', () {
      final start = service.indexOf('Future<String?> signedCoachVoiceUrl(');
      expect(start, greaterThan(0), reason: 'the signer has gone');
      final body = service.substring(start, start + 700);
      expect(body, contains("from('coach-media').createSignedUrl("));
      expect(RegExp(r'createSignedUrl\([^,]+,\s*\d+\)').hasMatch(body), isTrue,
          reason: 'a signed URL without an expiry is a permanent URL again');
      expect(body, contains('return null'),
          reason: 'a value that is not a coach-media reference must not be '
              'signed');
    });
  });
}
