// ═══════════════════════════════════════════════════════════════════════════
// HELIX · ThemeData composer  (brand-agnostic)
//
// Turns a HelixSemantics assignment into a Material ThemeData. It reads ONLY
// semantic tokens + primitives — no hex, no literal font family, no product
// value. Swap the semantics and every Material surface re-skins. Promotable to
// helix-core alongside the token files.
// ═══════════════════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'helix_primitives.dart';
import 'helix_semantics.dart';

class HelixThemeBuilder {
  static ThemeData dark(HelixSemantics s) {
    // Body font drives the base text theme; display font drives headings; the
    // numeric font is applied by components via context.helixNumeric().
    final baseText = GoogleFonts.getTextTheme(s.fontBody,
        ThemeData(brightness: Brightness.dark).textTheme);
    // Display weight and tracking come from the theme, not from literals — a
    // brand whose hierarchy is built from size and space rather than weight
    // could not previously express that, because these were hardcoded.
    TextStyle disp(double size, [FontWeight? w]) => GoogleFonts.getFont(
        s.fontDisplay, fontSize: size, fontWeight: w ?? s.displayWeight,
        color: s.textPrimary, letterSpacing: s.displayTracking, height: 1.06);
    TextStyle body(double size, FontWeight w, Color c) => GoogleFonts.getFont(
        s.fontBody, fontSize: size, fontWeight: w, color: c);

    final textTheme = baseText.copyWith(
      displayLarge:  disp(HelixTypeScale.metricLg),
      displayMedium: disp(HelixTypeScale.display),
      displaySmall:  disp(HelixTypeScale.h1),
      headlineLarge: disp(HelixTypeScale.h1),
      headlineMedium: disp(HelixTypeScale.h2),
      headlineSmall: body(HelixTypeScale.title, HelixTypeScale.semibold, s.textPrimary),
      titleLarge:  body(HelixTypeScale.title, HelixTypeScale.semibold, s.textPrimary),
      titleMedium: body(HelixTypeScale.body, HelixTypeScale.semibold, s.textPrimary),
      titleSmall:  body(HelixTypeScale.bodySm, HelixTypeScale.semibold, s.textSecondary),
      bodyLarge:  body(HelixTypeScale.body, HelixTypeScale.regular, s.textPrimary),
      bodyMedium: body(HelixTypeScale.bodySm, HelixTypeScale.regular, s.textSecondary),
      bodySmall:  body(HelixTypeScale.label, HelixTypeScale.regular, s.textTertiary),
      labelLarge: body(HelixTypeScale.bodySm, HelixTypeScale.semibold, s.textPrimary),
    );

    final cta = ElevatedButton.styleFrom(
      backgroundColor: s.accent, foregroundColor: s.accentFg,
      disabledBackgroundColor: s.surfaceHigh, disabledForegroundColor: s.textTertiary,
      minimumSize: const Size(double.infinity, 54),
      elevation: 0, shadowColor: Colors.transparent,
      shape: s.buttonShape,
      // CTA label: medium, no extra tracking. A button label is not a place to
      // reintroduce weight the type system has removed.
      textStyle: GoogleFonts.getFont(s.fontBody, fontSize: HelixTypeScale.body, fontWeight: HelixTypeScale.medium, letterSpacing: 0),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: s.background,
      canvasColor: s.background,
      extensions: [s],
      colorScheme: ColorScheme.dark(
        primary: s.accent, onPrimary: s.accentFg,
        secondary: s.success, onSecondary: s.accentFg,
        surface: s.surface, onSurface: s.textPrimary,
        error: s.danger, onError: s.dangerFg,
      ),
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: s.background, surfaceTintColor: Colors.transparent, elevation: 0, centerTitle: true,
        iconTheme: IconThemeData(color: s.textPrimary),
        titleTextStyle: GoogleFonts.getFont(s.fontBody, fontSize: HelixTypeScale.title, fontWeight: HelixTypeScale.bold, color: s.textPrimary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(style: cta),
      filledButtonTheme: FilledButtonThemeData(style: cta),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(
        foregroundColor: s.accent,
        textStyle: GoogleFonts.getFont(s.fontBody, fontSize: HelixTypeScale.bodySm, fontWeight: HelixTypeScale.semibold))),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
        foregroundColor: s.textPrimary, side: BorderSide(color: s.border),
        minimumSize: const Size(0, 54), shape: s.buttonShape,
        textStyle: GoogleFonts.getFont(s.fontBody, fontSize: HelixTypeScale.body, fontWeight: HelixTypeScale.semibold))),
      cardTheme: CardThemeData(
        color: s.surface, surfaceTintColor: Colors.transparent, elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(s.radiusCard), side: BorderSide(color: s.border)),
        shadowColor: const Color(0x59000000)),
      dividerTheme: DividerThemeData(color: s.border, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: s.surfaceHigh,
        hintStyle: GoogleFonts.getFont(s.fontBody, fontSize: HelixTypeScale.body, color: s.textTertiary),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(s.radiusField), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(s.radiusField), borderSide: BorderSide(color: s.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(s.radiusField), borderSide: BorderSide(color: s.accent, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: HelixSpace.x4, vertical: HelixSpace.x4)),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(s.surfaceHigh),
        thickness: WidgetStateProperty.all(5), radius: const Radius.circular(3)),
    );
  }
}
