import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// `DateTime.now().toIso8601String()` has no zone marker: "2026-11-15T17:40:00.000".
// Written into a timestamptz column, Postgres reads it in the session zone
// (UTC on Supabase), so a member in New York who acts at 17:40 is recorded at
// 17:40 UTC -- five hours early -- and a reader that calls `.toLocal()` shows
// 12:40. Earlier cycles fixed this one write at a time; these were left:
//   habit_logs.logged_at, custom_exercises.submitted_at / approved_at /
//   updated_at (the review queue orders by submitted_at), coach_reviews,
//   coach_video_responses, daily_scores, platform_settings, user_integrations,
//   event_registrations.checked_in_at.
// Every one is timestamptz. `.toUtc()` first makes the string end in "Z".
//
// A local DATE (`…toIso8601String().split('T')[0]`, `.substring(0, 10)`) is a
// calendar day, not an instant, and is correct as local -- not matched here.

final _zoneless = RegExp(r'DateTime\.now\(\)\.toIso8601String\(\)(?!\.(split|substring))');

/// Recorded, not fixed here: chat times and order await the owner's decision
/// (real-build QA 2026-11-07).
const _excluded = {
  'lib/features/messaging/presentation/chat_screen.dart',
};

/// One more zoneless write remains, in a feature area outside this
/// programme's scope; the failure output names it. A ceiling, so a new write
/// anywhere fails -- lower it to 0 when that area is fixed.
const _outOfScopeCeiling = 1;

Map<String, List<int>> _hits() {
  final hits = <String, List<int>>{};
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart')) continue;
    final lines = f.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trimLeft().startsWith('//')) continue;
      if (_zoneless.hasMatch(lines[i])) {
        hits.putIfAbsent(f.path.replaceAll(r'\', '/'), () => []).add(i + 1);
      }
    }
  }
  return hits;
}

void main() {
  test('no instant is written without a zone', () {
    final outside = Map.of(_hits())..removeWhere((f, _) => _excluded.contains(f));
    final lines = outside.values.fold<int>(0, (n, l) => n + l.length);
    printOnFailure('$outside');
    expect(lines, lessThanOrEqualTo(_outOfScopeCeiling),
        reason: 'use DateTime.now().toUtc().toIso8601String() for a timestamptz value');
  });

  test('the detector still sees (floor)', () {
    expect(_zoneless.hasMatch("'at': DateTime.now().toIso8601String(),"), isTrue);
    expect(_zoneless.hasMatch("'at': DateTime.now().toUtc().toIso8601String(),"), isFalse);
    expect(_zoneless.hasMatch("DateTime.now().toIso8601String().split('T')[0]"), isFalse);
    expect(_hits().keys.toSet(), containsAll(_excluded),
        reason: 'an excluded file no longer writes a zoneless instant -- '
            'remove it from _excluded so the guard tightens');
  });
}
