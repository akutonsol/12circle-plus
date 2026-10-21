import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'named_icon_button.dart';

/// A back control for a screen that the design draws one on.
///
/// ── WHY THESE SCREENS HAD NONE ─────────────────────────────────────────────
/// `/goals`, `/score`, `/womens-health`, `/challenges` and `/action-items` are
/// declared `hasBottomNav: false` by the design package — full-height pages,
/// each with a `Back` control. The router puts all five inside the
/// `ShellRoute`, so they get the bottom bar instead and **none of them has any
/// back affordance at all**.
///
/// Nobody is stranded: the bottom bar is a way out. But every one of them is
/// reached with `context.go` from `/directory` or `/home`, and a bottom bar
/// only returns you to a **tab root** — never to the screen you came from. The
/// design's `Back` is what closes that gap.
///
/// ── WHY IT IS NOT JUST `context.pop()` ─────────────────────────────────────
/// `context.go` replaces the location rather than pushing, so `canPop()` is
/// often false on exactly these screens and a bare `pop()` would do nothing at
/// all. The codebase's existing idiom — `canPop() ? pop() : go(somewhere)` —
/// is the one used here, with the fallback naming a route the user actually
/// came from rather than a guess.
Widget backLeading(BuildContext context, {String fallback = '/directory'}) =>
    NamedIconButton(
      label: 'Back',
      onTap: () =>
          context.canPop() ? context.pop() : context.go(fallback),
      child: const Icon(Icons.arrow_back_ios_new, size: 20),
    );
