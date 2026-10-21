import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// BACK-G1 — a back control must carry a name.
///
/// ── WHY BACK, SPECIFICALLY ─────────────────────────────────────────────────
/// `Back` is the single most declared interaction in the design package — it
/// appears on most frames — and it is always drawn as a bare glyph. An
/// `IconButton` whose child is an `Icon` and which has no `tooltip:` has **no
/// accessible name at all**: a screen reader announces "button" and stops.
/// Flutter's own `BackButton` gets its name from `MaterialLocalizations`; a
/// hand-rolled `IconButton(icon: Icon(Icons.arrow_back))` gets nothing.
///
/// A bare `GestureDetector` around the same icon is worse again — no name and
/// no button role.
///
/// ── THE COUNT THIS GUARD ALMOST SHIPPED WITH ───────────────────────────────
/// The first sweep reported **40 unnamed back buttons**. That number was
/// wrong, threefold, for two reasons worth keeping written down:
///
///   1. it matched `IconButton(` as a **substring of `NamedIconButton(`**, so
///      six controls this programme had already fixed were counted as
///      defects — the "string substrings being counted as controls" failure
///      exactly;
///   2. it never looked far enough out to see a `Semantics(button: true,
///      label: 'Back')` wrapper, so four more correct sites were counted too.
///
/// The verified figure was **16**: thirteen unnamed `IconButton`s and three
/// bare `GestureDetector`s. All sixteen are fixed, so this guard sits at
/// **zero** — and matches constructor names as whole words.
/// Does anything give this back control a name?
///
/// Lifted out of the scan so it can be pinned on its own. Left inline, a
/// mutation making it unconditionally `true` SURVIVED the whole guard: the
/// floor test only counted controls, and the ratchet then had nothing to find.
/// A predicate that never says "no" is not a predicate.
bool namesBackControl(String owner, String around) =>
    owner == 'NamedIconButton' ||
    owner == 'IntakeBackButton' ||
    owner == 'BackButton' ||
    around.contains('tooltip:') ||
    around.contains("label: 'Back'") ||
    around.contains('semanticLabel:');

void main() {
  group('BACK-G1 the predicate actually discriminates', () {
    test('a bare gesture around the glyph is NOT named', () {
      expect(
        namesBackControl('GestureDetector',
            'GestureDetector(onTap: pop, child: Icon(Icons.arrow_back))'),
        isFalse,
      );
      expect(
        namesBackControl('IconButton',
            'IconButton(icon: Icon(Icons.arrow_back), onPressed: pop)'),
        isFalse,
      );
    });

    test('each naming route is recognised, and only those', () {
      expect(namesBackControl('NamedIconButton', 'child: Icon(x)'), isTrue);
      expect(
          namesBackControl(
              'IconButton', "tooltip: 'Back', icon: Icon(x)"),
          isTrue);
      expect(
          namesBackControl(
              'GestureDetector', "Semantics(button: true, label: 'Back')"),
          isTrue);
      // A label that is not the back control's own does not count.
      expect(namesBackControl('GestureDetector', "label: 'Close'"), isFalse);
    });
  });

  // `\w*`, not an alternation of the spellings I happened to have seen.
  //
  // The first version was `Icons\.arrow_back(_ios_new|_ios)?\b`, and `\b`
  // after an optional suffix cannot match `Icons.arrow_back_ios_new_ROUNDED`
  // — the next character is `_`, a word character. That spelling is used
  // ELEVEN times in lib, so this guard shipped at "baseline 0" while blind to
  // a quarter of the controls it claims to cover, including an unnamed one on
  // `/ai-coach`. The floor test did not catch it because the floor had been
  // set to whatever the broken pattern found.
  final backIcon = RegExp(r'Icons\.arrow_back\w*');
  final owner = RegExp(
      r'\b(NamedIconButton|IconButton|GestureDetector|InkWell|InkResponse|'
      r'TextButton|BackButton|IntakeBackButton)\s*\(');

  /// Every back glyph in `lib`, with the nearest enclosing widget constructor
  /// and whether anything names it.
  List<({String file, int line, String owner, bool named})> scan() {
    final out = <({String file, int line, String owner, bool named})>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      // Comments name 'Back' constantly in this codebase — five detectors here
      // have read their own prose as evidence.
      final src = f
          .readAsStringSync()
          .split('\n')
          .map((l) {
            final i = l.indexOf('//');
            return i < 0 ? l : l.substring(0, i);
          })
          .join('\n');

      for (final m in backIcon.allMatches(src)) {
        final before = src.substring((m.start - 600).clamp(0, src.length), m.start);
        final around = before +
            src.substring(m.start, (m.start + 300).clamp(0, src.length));
        final owners = owner.allMatches(before).toList();
        final nearest = owners.isEmpty ? '?' : owners.last.group(1)!;

        final named = namesBackControl(nearest, around);

        out.add((
          file: f.path,
          line: src.substring(0, m.start).split('\n').length,
          owner: nearest,
          named: named,
        ));
      }
    }
    return out;
  }

  // ── A floor the detector does not compute ────────────────────────────────
  //
  // The v1 regex found 30 of 41 and the floor, being set to 30, agreed with
  // it. H-D1 and A-G8 failed the same way. A floor derived from the detector's
  // own output cannot contradict it.
  //
  // So this counts the glyph by a DIFFERENT mechanism — plain substring
  // splitting, no regex, no knowledge of which suffixes exist — and requires
  // the two to agree. A pattern that silently stops matching one spelling now
  // disagrees with a count that never knew about spellings at all.
  test('BACK-G1 the regex agrees with a count computed without it', () {
    var literal = 0;
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final src = f
          .readAsStringSync()
          .split('\n')
          .map((l) {
            final i = l.indexOf('//');
            return i < 0 ? l : l.substring(0, i);
          })
          .join('\n');
      literal += src.split('Icons.arrow_back').length - 1;
    }

    expect(scan().length, literal,
        reason: 'the pattern matched a different number of back glyphs than a '
            'plain substring count found. That is how the first version of '
            'this guard shipped blind to `Icons.arrow_back_ios_new_rounded`: '
            'it matched 30 where the substring count would have said 41.');
  });

  test('BACK-G1 the detector can still see back controls at all', () {
    // An absent result must not read as "everything is named" — the H-D1
    // lesson, which this suite has been bitten by repeatedly.
    final all = scan();
    expect(all.length, greaterThanOrEqualTo(41),
        reason: 'lib has dozens of back controls; finding almost none means '
            'the detector is broken, not that the app changed');
    expect(all.where((h) => h.owner == 'NamedIconButton'), isNotEmpty,
        reason: 'NamedIconButton is in use for several of these — if the '
            'scanner cannot see one, its owner matching is broken');
  });

  test('BACK-G1 no back control ships without a name', () {
    final unnamed = scan().where((h) => !h.named).toList();
    final listed = unnamed
        .map((h) => '  ${h.owner.padRight(16)} ${h.file}:${h.line}')
        .join('\n');

    expect(
      unnamed,
      isEmpty,
      reason: 'A back control has no accessible name. A screen reader '
          'announces "button" and stops.\n$listed\n\n'
          'For an IconButton add `tooltip: \'Back\'`. For anything else use '
          '`NamedIconButton(label: \'Back\', …)`, which carries the name, the '
          'button role and the 44 dp target together.',
    );
  });
}
