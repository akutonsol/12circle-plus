// ═══════════════════════════════════════════════════════════════════════════
// HELIX · Tier 1 — PRIMITIVE TOKENS  (brand-agnostic)
//
// The raw scales every product shares: spacing, radii, motion, type sizes,
// elevation. NO hex, NO font family, NO product decisions live here. This file
// is promotable verbatim into `helix-core` — nothing in it knows about 12 Circle.
//
// Themes pick FROM these primitives when they assign semantic tokens; components
// never read primitives directly (they read semantics).
// ═══════════════════════════════════════════════════════════════════════════
import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

/// 4-based spacing scale.
class HelixSpace {
  static const double x1 = 4, x2 = 8, x3 = 12, x4 = 16, x5 = 20,
      x6 = 24, x8 = 32, x10 = 40, x12 = 48, x16 = 64;
}

/// Corner radii scale.
class HelixRadius {
  static const double sm = 8, md = 12, lg = 16, xl = 20, xxl = 28, x3l = 36, pill = 999;
}

/// Motion primitives — durations + curves. Curves range from restrained to
/// springy; a theme's `easeBrand` picks the one that matches its personality.
class HelixMotion {
  static const Duration d120 = Duration(milliseconds: 120);
  static const Duration d200 = Duration(milliseconds: 200);
  static const Duration d300 = Duration(milliseconds: 300);
  static const Duration d450 = Duration(milliseconds: 450);
  static const Duration loop = Duration(milliseconds: 2600);

  static const Curve standard   = Curves.easeOutCubic;            // neutral
  static const Curve emphasized = Cubic(0.2, 0.0, 0.0, 1.0);      // decisive
  static const Curve spring     = Cubic(0.34, 1.56, 0.64, 1.0);   // springy overshoot
  static const Curve springSoft = Cubic(0.22, 1.20, 0.36, 1.0);  // gentler pop
}

/// Type SIZE + WEIGHT ramp (font family is a semantic decision, not a primitive).
class HelixTypeScale {
  static const double metricXl = 56, metricLg = 40, metricMd = 30; // big readouts
  static const double display = 32, h1 = 24, h2 = 20, title = 17;
  static const double body = 15, bodySm = 13, label = 12, caption = 11;

  // A brand whose display type is light/editorial needs weights below w400.
  // NOTE: a weight existing here does not mean the chosen family ships it —
  // Schibsted Grotesk via google_fonts 8.1.0 provides w400..w900 only, so
  // selecting `light` for that family currently renders as w400. See
  // docs/DESIGN_INTAKE_REPORT.md OD-6.
  static const FontWeight extraLight = FontWeight.w200;
  static const FontWeight light   = FontWeight.w300;
  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium  = FontWeight.w500;
  static const FontWeight semibold = FontWeight.w600;
  static const FontWeight bold    = FontWeight.w700;
  static const FontWeight heavy   = FontWeight.w800;
}

/// Elevation primitives — a shadow ramp parameterized by an ambient color so the
/// theme controls the tint. Agnostic to what that color is.
class HelixElevation {
  static List<BoxShadow> sm(Color c) =>
      [BoxShadow(color: c, blurRadius: 16, spreadRadius: -6, offset: const Offset(0, 6))];
  static List<BoxShadow> md(Color c) =>
      [BoxShadow(color: c, blurRadius: 28, spreadRadius: -8, offset: const Offset(0, 12))];
  static List<BoxShadow> lg(Color c) =>
      [BoxShadow(color: c, blurRadius: 44, spreadRadius: -10, offset: const Offset(0, 20))];

  /// A brand "glow" — colored bloom for celebratory/active accents.
  static List<BoxShadow> glow(Color c, {double opacity = 0.35}) =>
      [BoxShadow(color: c.withValues(alpha: opacity), blurRadius: 40, spreadRadius: -12, offset: const Offset(0, 10))];
}
