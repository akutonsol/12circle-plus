import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A-G6 — a stat's failure must be able to REACH the tile that renders it.
///
/// ── WHY THIS EXISTS: A-G5 WAS GREEN AND THE DEFECT WAS LIVE ────────────────
/// `A-G5` ratchets that *"no AsyncValue error branch returns a bare numeral"*,
/// and `train_hub_screen.dart` duly renders:
///
/// ```dart
/// value: streakAsync.when(
///   data: (v) => '$v', loading: () => '—', error: (_, __) => '—')),
/// ```
///
/// with a note in the file saying *"Showing '0' told the member their streak
/// was broken when the app had simply failed to ask."*
///
/// **That `error:` arm could never run.** `WorkoutService` caught the failure
/// and returned `0`:
///
/// ```dart
/// Future<int> getCurrentStreak() async {
///   …
///   } catch (_) { return 0; }
/// }
/// ```
///
/// so the `FutureProvider` was **always** `AsyncData(0)` and the member was
/// still told their streak was zero. The repair had been made at the
/// presentation layer, over a service that destroyed the signal it needed —
/// and the ratchet guarding it passed, because it only ever read the widget.
///
/// A guard that checks one layer of a two-layer defect reports the half it can
/// see. This checks the other half.
void main() {
  /// Reads whose failure a screen renders as `—`. Each one's service method
  /// must let the exception out.
  const mustSurface = <String, String>{
    'getWeeklyWorkoutCount': 'train_hub THIS WEEK',
    'getCurrentStreak': 'train_hub STREAK',
    'getTotalWorkoutCount': 'train_hub TOTAL',
    'getCompletionRate': 'train_hub DONE RATE',
    'getTotalVolumeLifted': 'volume stat',
  };

  late String service;

  setUpAll(() {
    service = File('lib/features/workout/data/workout_service.dart')
        .readAsStringSync();
  });

  test('A-G6 the guard is looking at the right file', () {
    // An absent result must not read as "nothing swallows" — the H-D1 lesson.
    for (final name in mustSurface.keys) {
      expect(service, contains('$name() async {'),
          reason: '$name has moved or been renamed; update this guard in the '
              'same change rather than letting it check nothing');
    }
  });

  test('A-G6 no stat read turns its own failure into a figure', () {
    final offenders = <String>[];

    for (final entry in mustSurface.entries) {
      final start = service.indexOf('${entry.key}() async {');
      if (start < 0) continue;
      // To the next method, or the next section banner.
      final ends = [
        service.indexOf('\n  Future<', start + 1),
        service.indexOf('\n  // ──', start + 1),
      ].where((i) => i > 0);
      final end = ends.isEmpty ? service.length : ends.reduce((a, b) => a < b ? a : b);
      final body = service.substring(start, end);

      if (RegExp(r'catch\s*\([^)]*\)\s*\{\s*return\s+-?[\d.]+\s*;?\s*\}')
          .hasMatch(body)) {
        offenders.add('${entry.key}  (${entry.value})');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'A stat read is answering with a number when it failed. The '
          "tile's `error: (_, __) => '—'` arm cannot run, so the member is "
          'told a figure the app never obtained:\n  '
          '${offenders.join('\n  ')}\n\n'
          'Let the exception out. The FutureProvider turns it into an '
          'AsyncError and the placeholder the screen already has takes over.',
    );
  });

  test('A-G6 the tiles still have a placeholder to fall back to', () {
    // The other half of the pair: surfacing the error is only an improvement
    // if something renders it. If these arms are ever removed, the exception
    // reaches a screen with nothing to say.
    final hub = File(
            'lib/features/workout/presentation/train_hub_screen.dart')
        .readAsStringSync();
    expect(RegExp(r"error:\s*\(_, __\)\s*=>\s*'—'").allMatches(hub).length,
        greaterThanOrEqualTo(4),
        reason: 'the four stat tiles must keep their no-figure placeholder');
  });

  test('A-G6 a signed-out user is still a real zero', () {
    // Not every `0` here is a swallowed failure. "You are not signed in" is an
    // answer, and removing it would turn a known state into an error.
    for (final name in mustSurface.keys) {
      final start = service.indexOf('$name() async {');
      final body = service.substring(start, start + 220);
      expect(body, contains('if (uid == null) return 0;'),
          reason: '$name lost its signed-out answer');
    }
  });
}
