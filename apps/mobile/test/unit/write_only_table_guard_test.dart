import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// WO-G1 — a table the app writes and never reads.
///
/// Found via SEC-VIDEO-1: `coach_video_responses` is inserted once and read
/// nowhere, so a coach uploads a personal video, the client is notified
/// *"Tap to watch"*, and nothing can ever play it. Sweeping for the shape
/// found it is not unique — `workout_feedback` does the same thing, telling a
/// coach *"A client rated their workout n/5 — tap to view"* with no surface
/// that reads the table.
///
/// The cost is not only the dead feature. Both tables accumulate rows about
/// identifiable people that no product surface justifies, which is a data
/// minimisation problem as well as a functional one.
///
/// ── THIS GUARD IS A SHRINKING ALLOWLIST ────────────────────────────────────
/// It fails in BOTH directions, the SEC-G3 shape:
///   * a NEW write-only table appears        → a third instance of the bug
///   * a KNOWN one gains a reader            → good; close the OD and delist
///
/// ── WHY THE READ DETECTION IS NOT JUST `from('x').select` ──────────────────
/// The first version of this sweep reported FOUR tables. Two were false
/// positives, and both would have been filed as defects:
///   * `accountability_pod_members` is read through PostgREST's embedded
///     resource syntax — `select('*, accountability_pod_members!inner(...)')`
///     — with no `from()` of its own.
///   * `weekly_feedback` is read through a DYNAMIC table name:
///     `avgOf('weekly_feedback', 'completion_pct')`.
/// A detector that only understood `from('x').select` would have called both
/// dead. Any read of the bare table name counts here, which is deliberately
/// generous: this guard must rather miss a dead table than invent one.
void main() {
  /// Written, read nowhere. Each carries the owner decision that governs it.
  const known = <String, String>{
    'coach_video_responses': 'OD-57 — no player; client is told "Tap to watch"',
    'workout_feedback': 'OD-59 — no coach surface; coach is told "tap to view"',
  };

  late Map<String, List<String>> writes;
  late Set<String> readNames;

  setUpAll(() {
    writes = <String, List<String>>{};
    readNames = <String>{};

    final write = RegExp(r"""from\('([a-z_]+)'\)\s*\.\s*(insert|upsert)""");
    // Any other mention of a quoted table-ish name: a `.select`, an embedded
    // resource inside a select string, or a dynamic helper's argument.
    final mention = RegExp(r"""'([a-z_]{4,})'""");

    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      for (final line in f.readAsStringSync().split('\n')) {
        final code = line.contains('//') ? line.substring(0, line.indexOf('//')) : line;

        for (final m in write.allMatches(code)) {
          writes.putIfAbsent(m.group(1)!, () => []).add('${f.path} :: ${line.trim()}');
        }

        // Everything that is NOT the write call itself is a candidate read.
        //
        // Except a NOTIFICATION TYPE that happens to share the table's name:
        // `'type': 'workout_feedback'` is a label on a notification row, not a
        // query, and counting it made a dead table read as live — which would
        // have hidden OD-59 behind a passing test.
        final withoutWrites = code
            .replaceAll(write, '')
            .replaceAll(RegExp(r"""'type'\s*:\s*'[a-z_]+'"""), '');
        for (final m in mention.allMatches(withoutWrites)) {
          readNames.add(m.group(1)!);
        }
        // Embedded resources appear inside one quoted string:
        // 'id, accountability_pod_members!inner(user_id)'
        for (final m in RegExp(r'([a-z_]{4,})\s*!?\s*(?:inner|left)?\s*\(')
            .allMatches(withoutWrites)) {
          readNames.add(m.group(1)!);
        }
      }
    }
  });

  test('WO-G1 the sweep actually found the app', () {
    // An empty sweep must not read as "no dead tables" — the H-D1 lesson.
    expect(writes.length, greaterThan(20),
        reason: 'the write detector found almost nothing; it has stopped '
            'matching this codebase and every assertion below is vacuous');
    expect(readNames, contains('user_profiles'));
    for (final t in known.keys) {
      expect(writes.keys, contains(t),
          reason: '$t is no longer written. If the feature was removed, '
              'delist it here in the same change.');
    }
  });

  test('WO-G1 no NEW table is written and never read', () {
    final dead = writes.keys.where((t) => !readNames.contains(t)).toSet();
    final novel = dead.difference(known.keys.toSet()).toList()..sort();

    expect(
      novel,
      isEmpty,
      reason: 'A table is being written that nothing reads:\n  '
          '${novel.map((t) => '$t\n      ${writes[t]!.first}').join('\n  ')}\n\n'
          'This is the SEC-VIDEO-1 / OD-57 shape: the app collects data about '
          'identifiable people, often announces it to someone, and has no '
          'surface that reads it back. Either build the reader or stop '
          'writing the row — do not add it to `known` without an OD.\n\n'
          'Before filing it, CHECK FOR A READ THIS SWEEP CANNOT SEE: a '
          'PostgREST embedded resource, a dynamic table name, an RPC or a '
          'view. Two of the first four hits were exactly that.',
    );
  });

  test('WO-G1 a known dead table that gains a reader must be delisted', () {
    final revived = known.keys.where(readNames.contains).toList()..sort();

    expect(
      revived,
      isEmpty,
      reason: 'These tables now have a reader:\n  '
          '${revived.map((t) => '$t  (${known[t]})').join('\n  ')}\n\n'
          'That is the outcome this guard wants. Two things must happen in '
          'the SAME change:\n'
          '  1. Close the owner decision named above and delist the table '
          'here.\n'
          '  2. For `coach_video_responses`, `video_url` now holds an OBJECT '
          'PATH, not a URL (SEC-VIDEO-1). Sign it at render time, and accept '
          'the full public URLs older rows still hold.\n'
          'Leaving it listed makes this guard protect a bug that is fixed.',
    );
  });

  test('WO-G1 the known cases are still genuinely unread', () {
    // Proves the detector can still SEE them — if `readNames` were somehow
    // matching everything, the test above would pass vacuously forever.
    for (final t in known.keys) {
      expect(readNames.contains(t), isFalse,
          reason: '$t reads as live; if that is real, the previous test '
              'should have caught it');
    }
    // And a table that IS read must be detected as read, or the whole
    // shrinking half of this allowlist is decorative.
    expect(readNames, contains('accountability_pod_members'),
        reason: 'the embedded-resource read at pods_screen.dart:39 is no '
            'longer detected — the false-positive protection is gone');
    expect(readNames, contains('weekly_feedback'),
        reason: 'the dynamic-table-name read at custom_exercise_service.dart:581 '
            'is no longer detected — the false-positive protection is gone');
  });
}
