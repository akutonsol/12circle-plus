import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// BACK-G2 — a screen the design draws a `Back` control on must have one.
///
/// ── WHAT WAS MEASURED ──────────────────────────────────────────────────────
/// `BACK-G1` ratchets whether a back control that EXISTS carries a name. It
/// says nothing about a screen that has no back control at all, and five did:
///
///   `/goals` · `/score` · `/womens-health` · `/challenges` · `/action-items`
///
/// The design package declares every one of them `hasBottomNav: false` — a
/// full-height page with a `Back` control. The router puts all five inside the
/// `ShellRoute`, so they get the bottom bar instead, and none of them had any
/// back affordance whatsoever.
///
/// ── WHY THIS IS NOT "NOBODY IS STRANDED, SO IT IS FINE" ────────────────────
/// The bottom bar is a way out, so this is not the `/pods` class of defect.
/// But all five are reached with `context.go` from `/directory` or `/home`,
/// and a bottom bar only ever returns the user to a **tab root** — never to
/// the screen they came from. `context.go` also replaces rather than pushes,
/// so `canPop()` is usually false here and the system back gesture does not
/// retrace the path either.
///
/// ── WHAT THIS GUARD DOES NOT CLAIM ─────────────────────────────────────────
/// It reads source. It proves the control is CONSTRUCTED, not that it is
/// reachable, sized or announced — `named_icon_button_test.dart` covers what
/// `backLeading` builds, and `BACK-G1` covers naming across the app. The three
/// together are still weaker than one device run, which is why F-6/F-6b exist.
void main() {
  /// Screens the design declares a `Back` control on and which had none.
  /// Adding to this list is how a newly-fixed screen gets pinned; removing
  /// from it needs a reason in the same change.
  const mustHaveBack = <String, String>{
    'lib/features/goals/presentation/goals_screen.dart': 'FIT-059',
    'lib/features/scoring/presentation/score_screen.dart': 'FIT-060',
    'lib/features/womens_health/presentation/womens_health_screen.dart':
        'FIT-063',
    'lib/features/challenges/presentation/challenges_screen.dart': 'FIT-075',
    'lib/features/action_items/presentation/action_center_screen.dart':
        'FIT-100',
  };

  String strip(String src) => src
      .split('\n')
      .map((l) {
        final i = l.indexOf('//');
        return i < 0 ? l : l.substring(0, i);
      })
      .join('\n');

  test('BACK-G2 the files are where the guard thinks they are', () {
    // A renamed file must fail loudly rather than silently passing on an
    // empty check — the H-D1 lesson.
    for (final path in mustHaveBack.keys) {
      expect(File(path).existsSync(), isTrue,
          reason: '$path has moved; update this guard in the same change '
              'rather than letting it check nothing');
    }
  });

  test('BACK-G2 each of them constructs a back control', () {
    final missing = <String>[];
    mustHaveBack.forEach((path, anchor) {
      final src = strip(File(path).readAsStringSync());
      if (!src.contains('backLeading(')) missing.add('$anchor  $path');
    });

    expect(missing, isEmpty,
        reason: 'These screens are declared `hasBottomNav: false` by the '
            'design and drawn with a `Back` control. Reached with '
            '`context.go`, a bottom bar returns the user to a tab root and '
            'never to where they came from.\n${missing.join('\n')}');
  });

  test('BACK-G2 the shared control pops before it falls back', () {
    // `context.go` replaces rather than pushes, so a bare `pop()` would do
    // nothing on exactly these screens; and a bare `go()` would throw away a
    // real history when there is one.
    final src = strip(
        File('lib/core/widgets/back_leading.dart').readAsStringSync());

    expect(src, contains('canPop()'));
    expect(src, contains('context.pop()'));
    expect(src, contains('context.go(fallback)'));
    expect(src, contains("label: 'Back'"),
        reason: 'and it must carry the name, or BACK-G1 has been routed '
            'around rather than satisfied');
  });
}
