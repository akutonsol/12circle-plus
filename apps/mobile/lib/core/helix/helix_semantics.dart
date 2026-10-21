// ═══════════════════════════════════════════════════════════════════════════
// HELIX · Tier 2 — SEMANTIC TOKENS  (the contract / swap boundary)
//
// The vocabulary components speak: surface, text-primary, accent, accent-fg,
// danger, radius-card, ease-brand, duration-brand, and the type-family trio.
// Components consume ONLY these — never raw hex, never a literal font/duration.
// That is the rule that makes the theme swappable.
//
// This file is brand-agnostic and promotable to helix-core. A theme (Tier 3)
// ASSIGNS these tokens; it lives in product code and is the only place raw brand
// values exist.
// ═══════════════════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'helix_primitives.dart';

@immutable
class HelixSemantics extends ThemeExtension<HelixSemantics> {
  // ── Color ──
  final Color background, surface, surfaceHigh, surfaceSunken, border;
  final Color textPrimary, textSecondary, textTertiary;
  final Color accent, accentFg, accentMuted;
  final Color success, warning, danger, dangerFg;

  /// A second, fainter hairline. The design system separates two divider
  /// strengths (`--line` 8% and `--line-2` 4.5%); one `border` could not carry
  /// both. Defaults to `border` so a theme that does not distinguish them
  /// behaves exactly as before.
  final Color? borderSubtle;

  /// Accent colour for *text* on a dark surface. The brand accent at full
  /// strength is ~3.4:1 on the background — below AA for body copy — so the
  /// design specifies a separate lighter accent for text. Defaults to `accent`.
  final Color? accentOnDark;

  // ── Shape (assigned from HelixRadius) ──
  final double radiusCard, radiusButton, radiusField;

  // ── Motion (assigned from HelixMotion) ──
  final Curve easeBrand;
  final Duration durationBrand;

  // ── Type families (the pairing — display / body / numeric) ──
  final String fontDisplay, fontBody, fontNumeric;

  /// Weight and tracking for display/metric type. These are a *brand*
  /// dimension, not a fixed one: a theme whose personality is "airy editorial"
  /// sets a light weight, one whose personality is "punchy athletic" sets a
  /// heavy one. They were previously hardcoded in `helixDisplay`, which made
  /// the choice unreachable from a theme.
  ///
  /// Defaults preserve the prior hardcoded behaviour exactly (`bold`, `-0.4`).
  final FontWeight displayWeight;
  final double displayTracking;

  const HelixSemantics({
    required this.background, required this.surface, required this.surfaceHigh,
    required this.surfaceSunken, required this.border,
    required this.textPrimary, required this.textSecondary, required this.textTertiary,
    required this.accent, required this.accentFg, required this.accentMuted,
    required this.success, required this.warning, required this.danger, required this.dangerFg,
    required this.radiusCard, required this.radiusButton, required this.radiusField,
    required this.easeBrand, required this.durationBrand,
    required this.fontDisplay, required this.fontBody, required this.fontNumeric,
    this.borderSubtle, this.accentOnDark,
    this.displayWeight = HelixTypeScale.bold, this.displayTracking = -0.4,
  });

  /// Resolved accessors — a theme that does not distinguish these gets the
  /// previous single-value behaviour, so no call site has to test for null.
  Color get borderSubtleOr => borderSubtle ?? border;
  Color get accentTextColor => accentOnDark ?? accent;

  // ── Component-facing helpers (read ONLY semantics) ─────────────────────────
  BoxDecoration cardDecoration({bool elevated = false, bool glow = false}) => BoxDecoration(
    color: surface,
    borderRadius: BorderRadius.circular(radiusCard),
    border: Border.all(color: border),
    boxShadow: [
      if (elevated) ...HelixElevation.md(const Color(0x59000000)),
      if (glow) ...HelixElevation.glow(accent),
    ],
  );

  OutlinedBorder get buttonShape => radiusButton >= 100
      ? const StadiumBorder()
      : RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusButton));

  // ── Gradients (agnostic shapes, brand-assigned colors) ──
  LinearGradient get heroGradient => LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [surfaceSunken, background]);
  LinearGradient get accentSweep => LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [accent, accent.withValues(alpha: 0.55)]);
  RadialGradient accentGlow([double opacity = 0.18]) => RadialGradient(
      colors: [accent.withValues(alpha: opacity), accent.withValues(alpha: 0)]);
  LinearGradient get featureGradient => LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [accentMuted, surfaceHigh]);

  @override
  HelixSemantics copyWith({
    Color? background, Color? surface, Color? surfaceHigh, Color? surfaceSunken, Color? border,
    Color? textPrimary, Color? textSecondary, Color? textTertiary,
    Color? accent, Color? accentFg, Color? accentMuted,
    Color? success, Color? warning, Color? danger, Color? dangerFg,
    double? radiusCard, double? radiusButton, double? radiusField,
    Curve? easeBrand, Duration? durationBrand,
    String? fontDisplay, String? fontBody, String? fontNumeric,
    Color? borderSubtle, Color? accentOnDark,
    FontWeight? displayWeight, double? displayTracking,
  }) => HelixSemantics(
    background: background ?? this.background, surface: surface ?? this.surface,
    surfaceHigh: surfaceHigh ?? this.surfaceHigh, surfaceSunken: surfaceSunken ?? this.surfaceSunken,
    border: border ?? this.border,
    textPrimary: textPrimary ?? this.textPrimary, textSecondary: textSecondary ?? this.textSecondary,
    textTertiary: textTertiary ?? this.textTertiary,
    accent: accent ?? this.accent, accentFg: accentFg ?? this.accentFg, accentMuted: accentMuted ?? this.accentMuted,
    success: success ?? this.success, warning: warning ?? this.warning,
    danger: danger ?? this.danger, dangerFg: dangerFg ?? this.dangerFg,
    radiusCard: radiusCard ?? this.radiusCard, radiusButton: radiusButton ?? this.radiusButton,
    radiusField: radiusField ?? this.radiusField,
    easeBrand: easeBrand ?? this.easeBrand, durationBrand: durationBrand ?? this.durationBrand,
    fontDisplay: fontDisplay ?? this.fontDisplay, fontBody: fontBody ?? this.fontBody,
    fontNumeric: fontNumeric ?? this.fontNumeric,
    borderSubtle: borderSubtle ?? this.borderSubtle,
    accentOnDark: accentOnDark ?? this.accentOnDark,
    displayWeight: displayWeight ?? this.displayWeight,
    displayTracking: displayTracking ?? this.displayTracking,
  );

  @override
  HelixSemantics lerp(ThemeExtension<HelixSemantics>? other, double t) {
    if (other is! HelixSemantics) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return HelixSemantics(
      background: c(background, other.background), surface: c(surface, other.surface),
      surfaceHigh: c(surfaceHigh, other.surfaceHigh), surfaceSunken: c(surfaceSunken, other.surfaceSunken),
      border: c(border, other.border),
      textPrimary: c(textPrimary, other.textPrimary), textSecondary: c(textSecondary, other.textSecondary),
      textTertiary: c(textTertiary, other.textTertiary),
      accent: c(accent, other.accent), accentFg: c(accentFg, other.accentFg), accentMuted: c(accentMuted, other.accentMuted),
      success: c(success, other.success), warning: c(warning, other.warning),
      danger: c(danger, other.danger), dangerFg: c(dangerFg, other.dangerFg),
      radiusCard: lerpDouble(radiusCard, other.radiusCard, t), radiusButton: lerpDouble(radiusButton, other.radiusButton, t),
      radiusField: lerpDouble(radiusField, other.radiusField, t),
      easeBrand: t < 0.5 ? easeBrand : other.easeBrand,
      durationBrand: t < 0.5 ? durationBrand : other.durationBrand,
      fontDisplay: t < 0.5 ? fontDisplay : other.fontDisplay,
      fontBody: t < 0.5 ? fontBody : other.fontBody,
      fontNumeric: t < 0.5 ? fontNumeric : other.fontNumeric,
      // Both sides may be null; Color.lerp handles that, and two nulls stay null
      // so the resolved accessors keep falling back.
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t),
      accentOnDark: Color.lerp(accentOnDark, other.accentOnDark, t),
      displayWeight: FontWeight.lerp(displayWeight, other.displayWeight, t) ?? displayWeight,
      displayTracking: lerpDouble(displayTracking, other.displayTracking, t),
    );
  }

  static double lerpDouble(double a, double b, double t) => a + (b - a) * t;
}

/// Ergonomic access + type helpers that consume ONLY semantics.
extension HelixContext on BuildContext {
  HelixSemantics get helix => Theme.of(this).extension<HelixSemantics>()!;

  /// Display / emphatic headings — brand display family.
  ///
  /// Weight and tracking now default to the *theme's* values rather than to
  /// literals, so a brand that wants light editorial display type can express
  /// that. Passing them explicitly still overrides, as before.
  TextStyle helixDisplay(double size, {FontWeight? weight, Color? color, double? spacing}) =>
      GoogleFonts.getFont(helix.fontDisplay, fontSize: size,
          fontWeight: weight ?? helix.displayWeight,
          color: color ?? helix.textPrimary,
          letterSpacing: spacing ?? helix.displayTracking, height: 1.06);

  /// Body / UI text — brand body family.
  TextStyle helixBody(double size, {FontWeight weight = HelixTypeScale.regular, Color? color, double spacing = 0}) =>
      GoogleFonts.getFont(helix.fontBody, fontSize: size, fontWeight: weight,
          color: color ?? helix.textPrimary, letterSpacing: spacing);

  /// Metric readouts / timers / streaks — brand numeric family.
  ///
  /// [tabular] selects fixed-advance figures. Use it — the default — wherever a
  /// value changes in place or sits in a column, so digits do not jitter. Turn
  /// it OFF for hero totals, thousands separators and currency: in a tabular
  /// face every glyph takes a digit's advance, so at display sizes a comma is
  /// given the width of a numeral and `1,640` reads as `1 , 640`.
  TextStyle helixNumeric(double size, {FontWeight? weight, Color? color, double? spacing, bool tabular = true}) =>
      GoogleFonts.getFont(helix.fontNumeric, fontSize: size,
          fontWeight: weight ?? helix.displayWeight,
          color: color ?? helix.textPrimary,
          letterSpacing: spacing ?? helix.displayTracking, height: 1.0,
          fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null);
}
