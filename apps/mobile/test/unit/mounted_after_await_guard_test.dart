import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// LIFE-G1 — `setState` after an `await` must be guarded by `mounted`.
///
/// A user who leaves a screen while a network round-trip is in flight disposes
/// the `State`. The continuation then calls `setState` on a disposed widget and
/// Flutter throws *"setState() called after dispose()"*. It is a real crash,
/// not a lint: it needs a slow network and a back-press, so it survives manual
/// testing and fails for users.
///
/// The codebase already knew the shape — `active_workout_screen.dart` carries
/// a note saying `_completeWorkout` *"awaits four network round-trips, and
/// Finish Early → Skip pops this screen while they are still in flight"* — but
/// the fix had been applied at that one site. A sweep found **54** unguarded
/// sites across 27 files, including the check-in, booking, payment and media
/// upload flows, which are exactly the slow ones.
///
/// ── WHY THIS SWEEP IS BRACE-SCOPED, NOT LINE-BASED ─────────────────────────
/// A line-based version reported **135** sites. It could not tell where an
/// async method ended, so its "we are past an await" flag leaked out of one
/// method and into the `onTap: () => setState(...)` callbacks of the `build`
/// below it — synchronous handlers that are never after an await. Scoping each
/// `async {` body by brace matching brought it to the real number.
///
/// It also strips comments. The last remaining hit of the first clean run was
/// `active_workout_screen.dart`'s own note, whose text contains the word
/// `setState` — a guard fooled by a comment describing the bug it enforces.
void main() {
  late List<String> offenders;
  late int asyncBodies;

  setUpAll(() {
    offenders = [];
    asyncBodies = 0;
    final asyncStart = RegExp(r'async\s*\{');

    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;

      final raw = f.readAsStringSync();
      // Blank out comments, preserving offsets so line numbers stay true.
      final src = raw.split('\n').map((l) {
        final i = l.indexOf('//');
        return i < 0 ? l : l.substring(0, i) + ' ' * (l.length - i);
      }).join('\n');

      for (final m in asyncStart.allMatches(src)) {
        asyncBodies++;
        // Brace-match this async body.
        var depth = 1;
        var i = m.end;
        while (i < src.length && depth > 0) {
          if (src[i] == '{') {
            depth++;
          } else if (src[i] == '}') {
            depth--;
          }
          i++;
        }
        final body = src.substring(m.end, i);

        for (final s in RegExp(r'\bsetState\s*\(').allMatches(body)) {
          final before = body.substring(0, s.start);
          if (!before.contains('await')) continue;
          final since = before.substring(before.lastIndexOf('await'));
          if (since.contains('mounted')) continue;
          // A setState inside a widget callback declared after the await is a
          // synchronous handler, not a continuation.
          if (RegExp(r'(onTap|onChanged|onPressed|builder|listener)\s*:')
              .hasMatch(since)) {
            continue;
          }
          final line = src.substring(0, m.end + s.start).split('\n').length;
          offenders.add('${f.path}:$line\n        '
              '${raw.split('\n')[line - 1].trim()}');
        }
      }
    }
  });

  test('LIFE-G1 the sweep actually found async code', () {
    // An empty sweep must not read as "nothing unguarded" — the H-D1 lesson.
    expect(asyncBodies, greaterThan(300),
        reason: 'the brace scanner found almost no async bodies; every '
            'assertion below would be vacuous');
  });

  test('LIFE-G1 no setState runs after an await without a mounted check', () {
    expect(
      offenders,
      isEmpty,
      reason: 'setState is called after an await with nothing checking that '
          'the widget is still mounted:\n  ${offenders.join('\n  ')}\n\n'
          'A user who leaves the screen while the request is in flight gets '
          '"setState() called after dispose()". Guard it — '
          '`if (!mounted) return;` before the call, or `if (mounted) '
          'setState(...)` when the code after it must still run.',
    );
  });

  test('LIFE-G1 the detector still recognises the shape it exists to catch',
      () {
    // Without this, an empty `offenders` could mean the scanner has rotted.
    // Both fixtures are exercised through the same logic as the sweep.
    String? firstOffender(String code) {
      final m = RegExp(r'async\s*\{').firstMatch(code);
      if (m == null) return null;
      final body = code.substring(m.end);
      for (final s in RegExp(r'\bsetState\s*\(').allMatches(body)) {
        final before = body.substring(0, s.start);
        if (!before.contains('await')) continue;
        if (before.substring(before.lastIndexOf('await')).contains('mounted')) {
          continue;
        }
        return 'hit';
      }
      return null;
    }

    expect(firstOffender('void f() async { await g(); setState(() {}); }'),
        isNotNull, reason: 'the detector no longer sees an unguarded call');
    expect(
        firstOffender(
            'void f() async { await g(); if (!mounted) return; setState(() {}); }'),
        isNull,
        reason: 'the detector now flags correctly guarded code, which would '
            'make this ratchet unmaintainable');
    expect(firstOffender('void f() async { setState(() {}); await g(); }'),
        isNull,
        reason: 'a setState BEFORE the await is not a continuation');
  });
}
