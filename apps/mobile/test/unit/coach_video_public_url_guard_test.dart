import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// VIDEO-G1 — SEC-VIDEO-1 / OD-57.
///
/// A coach records a video discussing a named client and uploads it to the
/// `coach-media` bucket, which live probing confirmed is PUBLIC. The screen
/// then called `getPublicUrl(path)` and persisted that permanent,
/// unauthenticated URL into `coach_video_responses.video_url`.
///
/// It now stores the OBJECT PATH, so the value can be signed at render time —
/// the treatment SEC-VOICE-1 gave `coach_voice`, and the prerequisite that
/// lets the bucket be made private without stranding every existing row.
///
/// ── THE SECOND HALF THIS GUARD DELIBERATELY DOES NOT CLOSE ─────────────────
/// Nothing reads that column. The video is uploaded, the client is notified
/// "Tap to watch", and there is no player anywhere in the app — a tap on a
/// notification marks it read and navigates nowhere, for every type. That is
/// a feature gap, not something a test may invent, so it is recorded as OD-57
/// and left for the owner.
///
/// The last test here is a TRIPWIRE for exactly that moment: it asserts the
/// column still has no reader, and fails with instructions when one appears.
void main() {
  late String screen; // comments stripped — this guard reads code, not prose
  late String raw;

  setUpAll(() {
    raw = File('lib/features/coach/presentation/'
            'coach_video_response_screen.dart')
        .readAsStringSync();
    // The fix's own comment explains what `getPublicUrl` used to do, and an
    // unstripped read matched it. A guard that trips on the note describing
    // the repair is measuring the wrong thing.
    screen = raw
        .split('\n')
        .map((l) {
          final i = l.indexOf('//');
          return i < 0 ? l : l.substring(0, i);
        })
        .join('\n');
  });

  test('VIDEO-G1 the guard is reading the right file', () {
    // An absent result must not read as "no defect" — the H-D1 lesson.
    expect(screen, contains('class CoachVideoResponseScreen'));
    expect(screen, contains("from('coach-media').uploadBinary"),
        reason: 'the upload has moved; update this guard in the same change '
            'rather than letting it check nothing');
    expect(screen, contains("from('coach_video_responses').insert"));
    // And the stripper did not eat the file it is meant to inspect.
    expect(screen.length, greaterThan(raw.length ~/ 2),
        reason: 'comment stripping removed most of the source — every code '
            'assertion below would pass against almost nothing');
  });

  test('VIDEO-G1 the upload does not mint a public URL', () {
    expect(screen.contains('getPublicUrl'), isFalse,
        reason: 'a permanent unauthenticated URL to a coaching video is being '
            'minted again. `coach-media` is a PUBLIC bucket, so this URL is '
            'readable by anyone who obtains it, forever, with no auth. Store '
            'the object path and sign at render time, as '
            '`CustomExerciseService.signedCoachVoiceUrl` does for voice.');
  });

  test('VIDEO-G1 what is stored is the object path', () {
    // Absence of `getPublicUrl` is not sufficient on its own: the value could
    // be built by string concatenation instead. Assert the positive.
    final start = screen.indexOf('if (_videoFile != null) {');
    expect(start, greaterThan(0), reason: 'the upload branch has moved');
    final block = screen.substring(start, screen.indexOf('\n      }', start));

    expect(block, contains('videoUrl = path;'),
        reason: 'the stored value must be the storage object path');
    // Match on the SCHEME ONLY. The comment stripper cuts at `//`, so a real
    // `'https://…'` in code would arrive here as `'https:` and a `https?://`
    // pattern would never fire — the assertion would pass vacuously, which is
    // the RG3 failure this suite has already been bitten by once.
    expect(RegExp(r'''https?:''').hasMatch(block), isFalse,
        reason: 'a URL is being assembled by hand in the upload branch');

    // And the path itself must still be the per-coach/per-client one, not a
    // shared or guessable prefix.
    expect(block, contains(r"'coach-videos/$uid/${widget.clientId}/"),
        reason: 'the object path no longer scopes by coach and client');
  });

  test('VIDEO-G1 the column still has no reader — OD-57 tripwire', () {
    // Not a defect in itself; it is the trigger to finish the job.
    final lib = Directory('lib');
    final readers = <String>[];

    for (final f in lib.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      if (f.path.endsWith('coach_video_response_screen.dart')) continue;
      final src = f.readAsStringSync();
      for (final line in src.split('\n')) {
        // Comments discuss this table by name on purpose — see the corrected
        // OD-25 note in coach_checkin_review_screen.dart. Only code counts.
        final code = line.contains('//') ? line.substring(0, line.indexOf('//')) : line;
        if (code.contains('coach_video_responses')) {
          readers.add('${f.path}: ${line.trim()}');
        }
      }
    }

    expect(
      readers,
      isEmpty,
      reason: 'A reader of `coach_video_responses` has appeared:\n  '
          '${readers.join('\n  ')}\n\n'
          'Good — OD-57 is being closed. Two things must happen in the SAME '
          'change:\n'
          '  1. `video_url` now holds an OBJECT PATH, not a URL. Sign it via '
          '`createSignedUrl` at render time. Rows written before this guard '
          'existed still hold full public URLs, so the reader must accept '
          'both — `coachVoiceSigningPath` is the worked example.\n'
          '  2. The "Tap to watch" notification '
          '(coach_video_response_screen, type `coach_video`) still routes '
          'nowhere: notifications_screen.dart:157 marks a tap read and does '
          'not navigate. Give it a destination or the player stays '
          'unreachable.\n'
          'Then delete this test and record OD-57 closed.',
    );
  });
}
