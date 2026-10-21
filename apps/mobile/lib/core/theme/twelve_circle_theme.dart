// ═══════════════════════════════════════════════════════════════════════════
// 12 CIRCLE THEME · Tier 3 — the brand bundle  (PRODUCT-SPECIFIC)
//
// The ONLY place raw brand values live. It ASSIGNS the Helix semantic contract
// from 12 Circle's primitives + choices, then hands off to the brand-agnostic
// HelixThemeBuilder. Swap this file → different product; Helix is untouched.
//
// Personality (athletic consumer-wellness — WHOOP / Strava / Nike / Levels /
// Apple Fitness+ — NOT enterprise or medical):
//   • Color   — restrained neutral ground; violet is a line and a mark, never
//               a flood. White is reserved for metric readouts.
//   • Type    — Schibsted Grotesk throughout. Hierarchy from size and space,
//               not weight.
//   • Motion  — emphasised and brief (200ms). Nothing loops.
//   • Density — 16px cards, flat 12px controls, 20px screen gutter
//   • Voice   — motivational, athletic
//
// ── SOURCE OF THESE VALUES ─────────────────────────────────────────────────
// Every value below is taken from the authoritative design handoff, not chosen
// here: manifest.json `tokens` (the board's rendered CSS) cross-checked against
// docs/12CIRCLE-FITNESS-PHASE-2-DESIGN-SYSTEM.md. Intake and the full
// design-vs-repo conflict table are in docs/DESIGN_INTAKE_REPORT.md.
// IMPLEMENT-THIS.md §4: "Tokens go into Helix Tier 1-3 as written there.
// No parallel theme."
//
// The previous values are kept in comments where they were replaced, because
// they were a deliberate brand expression and the diff should show what moved.
// ═══════════════════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';
import '../helix/helix_primitives.dart';
import '../helix/helix_semantics.dart';
import '../helix/helix_theme_builder.dart';

/// 12 Circle brand primitives — product hex. Nothing outside this file should
/// reference these directly; components read semantic tokens (context.helix.*).
class _Brand {
  // Neutral ground.                                    design token → was
  static const bg            = Color(0xFF0A0A0B); // --bg       ← 0xFF0A0C10
  static const surface       = Color(0xFF121215); // --surf     ← 0xFF14171D
  static const surfaceHigh   = Color(0xFF1B1B20); // --surf-hi  ← 0xFF1D222B
  static const surfaceSunken = Color(0xFF070708); // --sunken   ← 0xFF07090C

  // Two hairline strengths. The design separates them; one value cannot serve
  // both a card edge and an in-card divider.
  static const border       = Color(0x14FFFFFF); // --line   white 8% ← ~12%
  static const borderSubtle = Color(0x0BFFFFFF); // --line-2 white 4.5%

  static const white = Color(0xFFFFFFFF);         // --white: METRIC READOUTS ONLY
  static const ink   = Color(0xFFF4F3F6);         // --ink    ← was pure white
  static const grey  = Color(0xFF9B96A3);         // --grey   ← 0xFF9AA3AF
  // --dim. Raised for contrast: the design rejected #6A6572 at 3.31:1; this
  // clears AA at 11px (worst case 4.81:1 on surfaceHigh). The value replaced
  // here, #5B646F, was DARKER than the one the design rejected.
  static const dim   = Color(0xFF8B8595);

  static const violet      = Color(0xFF7C3AED); // --violet     ← 0xFF7C5CFF
  static const violetText  = Color(0xFFA78BFA); // --violet-txt: accent TEXT.
  // Full-strength violet on the background is ~3.4:1 — below AA for body copy.
  static const violetMuted = Color(0x337C3AED); // --violet-mut ← 0x337C5CFF

  static const green = Color(0xFF2FBF87);        // --green ← 0xFF2FE0A6
  static const amber = Color(0xFFE0A030);        // --amber ← 0xFFFFB020
  static const red   = Color(0xFFE8556D);        // --red   ← 0xFFFF4D6A
}

class TwelveCircleTheme {
  static const String voice = 'motivational · athletic · in-your-corner';

  /// The semantic assignment — 12 Circle's answer to the Helix contract.
  static const HelixSemantics semantics = HelixSemantics(
    background: _Brand.bg, surface: _Brand.surface, surfaceHigh: _Brand.surfaceHigh,
    surfaceSunken: _Brand.surfaceSunken, border: _Brand.border,
    borderSubtle: _Brand.borderSubtle,
    // textPrimary is --ink, not pure white: white is reserved for metrics.
    textPrimary: _Brand.ink, textSecondary: _Brand.grey, textTertiary: _Brand.dim,
    accent: _Brand.violet, accentFg: _Brand.white, accentMuted: _Brand.violetMuted,
    accentOnDark: _Brand.violetText,
    success: _Brand.green, warning: _Brand.amber, danger: _Brand.red, dangerFg: _Brand.white,
    // Density/radius — cards 16, controls flat 12. Explicitly NOT pill:
    // "no gradient, no glow" (PHASE-2-DESIGN-SYSTEM §shape).
    //                                   was: xxl(28) / pill(999) / lg(16)
    radiusCard: HelixRadius.lg, radiusButton: HelixRadius.md, radiusField: HelixRadius.md,
    // Motion — emphasised and brief. Nothing loops.  was: spring / 300ms
    easeBrand: HelixMotion.emphasized, durationBrand: HelixMotion.d200,
    // Type — one family throughout.  was: Outfit / Inter / Rajdhani
    fontDisplay: 'Schibsted Grotesk', fontBody: 'Schibsted Grotesk',
    fontNumeric: 'Schibsted Grotesk',
    // "Hierarchy comes from size and space, not weight. Nothing above 500."
    // The design DOC specifies w300, but Schibsted Grotesk ships no w300 via
    // google_fonts 8.1.0, and manifest.json — the board's rendered CSS, which
    // is the package's declared source of truth — records w400 for d1/h1.
    // w400 is used here and OD-6 records the open question.
    displayWeight: HelixTypeScale.regular, displayTracking: -0.6,
  );

  static ThemeData get theme => HelixThemeBuilder.dark(semantics);
}
