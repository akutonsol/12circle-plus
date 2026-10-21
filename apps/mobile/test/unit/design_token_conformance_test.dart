import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:circle_fitness/core/helix/helix_primitives.dart';
import 'package:circle_fitness/core/theme/twelve_circle_theme.dart';

/// D-T1 — the shipped theme must equal the authoritative design tokens.
///
/// Source of every expected value below: the design handoff package's
/// `manifest.json` `tokens` array (the design board's *rendered* CSS, which the
/// package declares as its source of truth), cross-checked against
/// `docs/12CIRCLE-FITNESS-PHASE-2-DESIGN-SYSTEM.md`. The intake that validated
/// the package is `docs/DESIGN_INTAKE_REPORT.md`.
///
/// The expected values are written out as literals rather than read from the
/// package, deliberately: the package lives OUTSIDE this repository, so a test
/// that parsed it would fail on any machine that does not happen to have it.
/// Pinning literals means this test states the contract on its own.
///
/// Before this landed, the shipped theme disagreed with the design on the
/// accent, all four surfaces, the border alpha, all three text colours, all
/// three status colours, all three radii, both motion values and all three font
/// families — see `docs/DESIGN_INTAKE_REPORT.md` §10.3.
void main() {
  // Building the full ThemeData resolves the display family through
  // GoogleFonts, which needs the services binding and would otherwise try to
  // fetch the font over the network. A test must not depend on the network.
  // Disabling runtime fetching keeps the *weights and metrics* under test —
  // which is all this file asserts — without needing the font binary.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const s = TwelveCircleTheme.semantics;

  group('D-T1 colour tokens', () {
    test('neutral ground', () {
      expect(s.background, const Color(0xFF0A0A0B), reason: '--bg');
      expect(s.surface, const Color(0xFF121215), reason: '--surf');
      expect(s.surfaceHigh, const Color(0xFF1B1B20), reason: '--surf-hi');
      expect(s.surfaceSunken, const Color(0xFF070708), reason: '--sunken');
    });

    test('two hairline strengths, not one', () {
      expect(s.border, const Color(0x14FFFFFF), reason: '--line, white 8%');
      expect(s.borderSubtle, const Color(0x0BFFFFFF), reason: '--line-2, white 4.5%');
      expect(s.borderSubtleOr, isNot(s.border),
          reason: 'A theme that distinguishes them must not collapse them.');
    });

    test('text colours — and white is NOT text primary', () {
      expect(s.textPrimary, const Color(0xFFF4F3F6), reason: '--ink');
      expect(s.textSecondary, const Color(0xFF9B96A3), reason: '--grey');
      expect(s.textTertiary, const Color(0xFF8B8595), reason: '--dim');

      // The design reserves pure white for metric readouts. Binding textPrimary
      // to white is what made every body string shout.
      expect(s.textPrimary, isNot(const Color(0xFFFFFFFF)),
          reason: 'White is reserved for metric readouts only.');

      // --dim exists at this exact value for a contrast reason: the design
      // rejected #6A6572 at 3.31:1. Anything darker fails for the same reason.
      expect(s.textTertiary, isNot(const Color(0xFF6A6572)));
      expect(s.textTertiary, isNot(const Color(0xFF5B646F)),
          reason: 'The previously shipped value, darker than the rejected one.');
    });

    test('accent, and a separate accent for text', () {
      expect(s.accent, const Color(0xFF7C3AED), reason: '--violet');
      expect(s.accentMuted, const Color(0x337C3AED), reason: '--violet-mut');
      expect(s.accentOnDark, const Color(0xFFA78BFA), reason: '--violet-txt');
      // Accent-as-text must differ from accent: #7C3AED on #0A0A0B is ~3.4:1,
      // below AA for body copy.
      expect(s.accentTextColor, isNot(s.accent));
    });

    test('status colours', () {
      expect(s.success, const Color(0xFF2FBF87), reason: '--green');
      expect(s.warning, const Color(0xFFE0A030), reason: '--amber');
      expect(s.danger, const Color(0xFFE8556D), reason: '--red');
    });
  });

  group('D-T2 shape', () {
    test('cards 16, controls flat 12', () {
      expect(s.radiusCard, HelixRadius.lg, reason: 'card radius 16');
      expect(s.radiusButton, HelixRadius.md, reason: 'button radius 12, flat');
      expect(s.radiusField, HelixRadius.md, reason: 'field radius 12');
    });

    test('the CTA is not a pill', () {
      // buttonShape returns StadiumBorder above radius 100. The design says
      // "12 flat — explicitly not pill, no gradient, no glow".
      expect(s.radiusButton, lessThan(100));
      expect(s.buttonShape, isA<RoundedRectangleBorder>());
      expect(s.buttonShape, isNot(isA<StadiumBorder>()));
    });
  });

  group('D-T3 motion', () {
    test('emphasised and brief', () {
      expect(s.easeBrand, HelixMotion.emphasized);
      expect(s.durationBrand, HelixMotion.d200);
      expect(s.durationBrand.inMilliseconds, 200);
    });

    test('the springy curve is not the brand curve', () {
      expect(s.easeBrand, isNot(HelixMotion.spring));
    });
  });

  group('D-T4 type', () {
    test('one family throughout', () {
      expect(s.fontDisplay, 'Schibsted Grotesk');
      expect(s.fontBody, 'Schibsted Grotesk');
      expect(s.fontNumeric, 'Schibsted Grotesk');
    });

    test('hierarchy from size and space — nothing above 500', () {
      // "Nothing above 500... Never 700/800."
      expect(s.displayWeight.value, lessThanOrEqualTo(HelixTypeScale.medium.value),
          reason: 'displayWeight must not exceed w500.');
      expect(s.displayWeight, isNot(HelixTypeScale.bold));
      expect(s.displayWeight, isNot(HelixTypeScale.heavy));
      expect(s.displayTracking, -0.6);
    });

    test('the theme builder takes its display weight from the theme', () {
      // Asserted against the builder's SOURCE rather than against a built
      // ThemeData. Building the theme resolves the family through GoogleFonts,
      // which is not bundled as an asset and is fetched at runtime, so
      // constructing it in a test requires the network. A test must not.
      //
      // The regression this pins is concrete: the builder previously hardcoded
      // `HelixTypeScale.heavy` / `.bold` for the five display styles, so a
      // theme could not lower them.
      final src = File('lib/core/helix/helix_theme_builder.dart').readAsStringSync();

      expect(src, contains('w ?? s.displayWeight'),
          reason: 'disp() must fall back to the theme\'s displayWeight.');
      expect(src, contains('letterSpacing: s.displayTracking'),
          reason: 'disp() must take tracking from the theme, not a literal.');

      final displayStyles = RegExp(
        r'(displayLarge|displayMedium|displaySmall|headlineLarge|headlineMedium)\s*:\s*disp\(([^)]*)\)',
      );
      final matches = displayStyles.allMatches(src).toList();
      expect(matches.length, 5, reason: 'All five display styles must use disp().');
      for (final m in matches) {
        final args = m.group(2)!;
        expect(args, isNot(contains('heavy')),
            reason: '${m.group(1)} must not pin w800.');
        expect(args, isNot(contains('bold')),
            reason: '${m.group(1)} must not pin w700.');
      }
    });

    test('the weight ramp reaches below w400', () {
      // Required so a light/editorial brand is expressible at all. NOTE: the
      // weight existing here does not mean the family ships it — see OD-6 in
      // docs/DESIGN_INTAKE_REPORT.md.
      expect(HelixTypeScale.light, FontWeight.w300);
      expect(HelixTypeScale.extraLight, FontWeight.w200);
    });
  });

  group('D-T5 spacing scale is unchanged, and was already correct', () {
    test('4-based, with the gutter and section intervals the design uses', () {
      expect(HelixSpace.x5, 20, reason: 'screen gutter');
      expect(HelixSpace.x8, 32, reason: 'section interval');
      expect(HelixSpace.x12, 48, reason: 'new screen part');
    });
  });
}
