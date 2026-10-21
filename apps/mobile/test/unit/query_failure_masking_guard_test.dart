import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ERR-G1 — a QUERY must not answer with a value when it failed.
///
/// ── THE CLASS ──────────────────────────────────────────────────────────────
/// ```dart
/// Future<int> getCurrentStreak() async {
///   …
///   } catch (_) { return 0; }      // "your streak is zero"
/// }
/// ```
///
/// `false` and `0` are **answers**. Returned from a `catch`, they are answers
/// the method does not have. This is the defect behind A-G5: `train_hub`
/// rendered `error: (_, __) => '—'` and that arm **could never run**, because
/// the service turned every failure into `AsyncData(0)` before the provider
/// saw it. The repair had been made at the presentation layer, over a service
/// that destroyed the signal it needed.
///
/// ── WHAT IS AND IS NOT COVERED ─────────────────────────────────────────────
/// This targets **queries** — methods whose name asks a question (`has…`,
/// `get…`, `is…`, `count…`, `fetch…`, `load…`, `check…`, `current…`,
/// `total…`) returning `bool`/`int`/`double`.
///
/// It deliberately does **not** target ACTIONS. `Future<bool> saveX()`
/// returning `false` from a catch is correct: "it did not work" is exactly
/// what the caller asked. Conflating the two would force a wrong fix on ~29
/// call sites.
///
/// It also does not cover `return []` / `return null`. An empty list is
/// sometimes a legitimate degraded answer and the nine harmful cases are
/// already closed and recorded (F-15, §3o). Widening this guard to catch them
/// would need product copy that does not exist, which is OD-8's ruling.
void main() {
  // Matches an `async { … }` body OR an expression body (`=> …`).
  //
  // THE REGEX USED TO REQUIRE `async {`, AND THAT WAS AN EVASION PATH. A
  // `Future<bool> canViewGuardian() => _can(...);` is a query returning bool that the
  // detector could not inspect at all — so anyone could step outside ERR-G1 by using an
  // expression body, without intending to. The self-consistency assertion below is what
  // caught it: the substring count found 65 declarations and the regex found 64.
  //
  // An expression body cannot contain a `catch` block, so widening adds no false
  // positive; it closes the hole in what the detector can SEE.
  final decl = RegExp(
      r'Future<(bool|int|double)>\s+(\w+)\([^)]*\)\s*(?:async\s*\{|=>)');
  final masks = RegExp(r'catch\s*\([^)]*\)\s*\{\s*return\s+(false|0|0\.0)\s*;');
  const question = ['has', 'is', 'get', 'count', 'fetch', 'load', 'check',
                    'current', 'total'];

  List<({String file, String method, String value})> scan() {
    final out = <({String file, String method, String value})>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      // Comments in this codebase quote the old defective code constantly —
      // five detectors here have read their own prose as evidence.
      final src = f
          .readAsStringSync()
          .split('\n')
          .map((l) {
            final i = l.indexOf('//');
            return i < 0 ? l : l.substring(0, i);
          })
          .join('\n');

      for (final m in decl.allMatches(src)) {
        final name = m.group(2)!;
        if (!question.any((q) => name.toLowerCase().startsWith(q))) continue;
        final rest = src.substring(m.end,
            (m.end + 2500).clamp(0, src.length));
        final next = rest.indexOf('\n  Future<');
        final body = next > 0 ? rest.substring(0, next) : rest;
        final hit = masks.firstMatch(body);
        if (hit != null) {
          out.add((file: f.path, method: name, value: hit.group(1)!));
        }
      }
    }
    return out;
  }

  test('ERR-G1 the regex agrees with a count computed without it', () {
    // A floor set to whatever the detector happens to find cannot contradict
    // it — that is how BACK-G1 shipped blind to 11 of 41 controls. So this
    // counts the same declarations by plain substring splitting, with no
    // regex and no knowledge of the signature shape, and requires the two to
    // agree within the overload tolerance below.
    var literal = 0;
    var viaRegex = 0;
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final src = f.readAsStringSync();
      for (final t in ['Future<bool> ', 'Future<int> ', 'Future<double> ']) {
        literal += src.split(t).length - 1;
      }
      viaRegex += decl.allMatches(src).length;
    }

    expect(literal, greaterThan(30),
        reason: 'almost no async value-returning methods found at all — the '
            'codebase cannot look like this, so the reader is broken');
    expect(viaRegex, literal,
        reason: 'the declaration regex matched a different number ($viaRegex) '
            'than a plain substring count ($literal). One of them is wrong, '
            'and a detector that silently stops matching a shape is exactly '
            'how a guard goes green while the defect ships.');
  });

  test('ERR-G1 no query answers its own failure with a value', () {
    final offenders = scan();
    final listed = offenders
        .map((o) => '  ${o.method} -> ${o.value}   ${o.file}')
        .join('\n');

    expect(
      offenders,
      isEmpty,
      reason: 'A query is returning a value from its catch. That value is an '
          'ANSWER the method does not have, and it destroys the error before '
          'the provider sees it — which is what left `train_hub`\'s '
          "`error: (_, __) => '—'` arm unreachable while A-G5 stayed green.\n"
          '$listed\n\n'
          'Let the exception out. The FutureProvider turns it into an '
          'AsyncError. A signed-out early return is a real answer and is fine.',
    );
  });

  test('ERR-G1 ACTIONS are deliberately not swept', () {
    // If this ever returns 0 the scan has widened to actions, and the guard
    // would be demanding a wrong fix.
    var actions = 0;
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final src = f.readAsStringSync();
      for (final m in decl.allMatches(src)) {
        final n = m.group(2)!;
        if (question.any((q) => n.toLowerCase().startsWith(q))) continue;
        final rest = src.substring(m.end, (m.end + 2000).clamp(0, src.length));
        if (masks.hasMatch(rest)) actions++;
      }
    }
    expect(actions, greaterThan(0),
        reason: 'actions returning false from a catch are CORRECT and must '
            'still exist; if none are found the detector has changed shape');
  });
}
