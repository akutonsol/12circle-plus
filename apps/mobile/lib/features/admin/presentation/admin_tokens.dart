// GENERATED FILE — DO NOT EDIT BY HAND.
//
// Source of truth: `docs/design/brand/tokens/admin.tokens.css` at commit `931218b`, the approved
// 12Circle+ Admin design authority. That commit lives on
// `design/12circle-plus-admin-dashboard` and is NOT an ancestor of this branch, so
// the values below are pinned to it rather than to a working-tree path.
//
// Regenerate with:  node supabase/scripts/gen-admin-tokens.mjs
// CI verifies with: node supabase/scripts/gen-admin-tokens.mjs --check
//
// 126 tokens. Every doc comment quotes the exact source declaration, so a
// value can be traced to the design without leaving the file.
//
// THIS IS TIER 3. The Helix rule is that components consume semantic tokens and never
// raw hex, which is precisely what the existing admin screen's `const _brand =
// Color(0xFFA855F7)` violates. New Admin UI reads from here.
//
// NOT EVERY TOKEN BECOMES A FLUTTER VALUE. A `clamp()` gutter, an `em` tracking and a
// CSS font stack have no Flutter equivalent; they are exposed as the literal source
// string under [AdminTokensRaw] rather than converted into a guess.
library;

import 'package:flutter/painting.dart';

/// Colors from the published `--adm-color-*` set.
abstract final class AdminColors {
  /// `--adm-color-bg-canvas: #0a0a0b`
  static const colorBgCanvas = Color(0xFF0A0A0B);
  /// `--adm-color-bg-surface: #121215`
  static const colorBgSurface = Color(0xFF121215);
  /// `--adm-color-bg-raised: #16161a`
  static const colorBgRaised = Color(0xFF16161A);
  /// `--adm-color-bg-hover: #1b1b20`
  static const colorBgHover = Color(0xFF1B1B20);
  /// `--adm-color-bg-inset: #232326`
  static const colorBgInset = Color(0xFF232326);
  /// `--adm-color-text-primary: #f4f3f6`
  static const colorTextPrimary = Color(0xFFF4F3F6);
  /// `--adm-color-text-secondary: #d0ccd6`
  static const colorTextSecondary = Color(0xFFD0CCD6);
  /// `--adm-color-text-muted: #9b96a3`
  static const colorTextMuted = Color(0xFF9B96A3);
  /// `--adm-color-text-subtle: #8b8595`
  static const colorTextSubtle = Color(0xFF8B8595);
  /// `--adm-color-text-disabled: #6f6a78`
  static const colorTextDisabled = Color(0xFF6F6A78);
  /// `--adm-color-text-on-warning: #0a0a0b`
  static const colorTextOnWarning = Color(0xFF0A0A0B);
  /// `--adm-color-brand-violet: #7c3aed`
  static const colorBrandViolet = Color(0xFF7C3AED);
  /// `--adm-color-brand-accent: #a78bfa`
  static const colorBrandAccent = Color(0xFFA78BFA);
  /// `--adm-color-brand-accent-hover: #c4b1fc`
  static const colorBrandAccentHover = Color(0xFFC4B1FC);
  /// `--adm-color-brand-tint: rgba(124,58,237,0.18)`
  static const colorBrandTint = Color(0x2E7C3AED);
  /// `--adm-color-brand-tint-strong: rgba(124,58,237,0.22)`
  static const colorBrandTintStrong = Color(0x387C3AED);
  /// `--adm-color-brand-border: rgba(124,58,237,0.5)`
  static const colorBrandBorder = Color(0x807C3AED);
  /// `--adm-color-brand-focus: #a78bfa`
  static const colorBrandFocus = Color(0xFFA78BFA);
  /// `--adm-color-status-success: #2fbf87`
  static const colorStatusSuccess = Color(0xFF2FBF87);
  /// `--adm-color-status-success-text: #5fd6a4`
  static const colorStatusSuccessText = Color(0xFF5FD6A4);
  /// `--adm-color-status-success-tint: rgba(47,191,135,0.14)`
  static const colorStatusSuccessTint = Color(0x242FBF87);
  /// `--adm-color-status-warning: #e0a030`
  static const colorStatusWarning = Color(0xFFE0A030);
  /// `--adm-color-status-warning-text: #f0c060`
  static const colorStatusWarningText = Color(0xFFF0C060);
  /// `--adm-color-status-warning-tint: rgba(224,160,48,0.14)`
  static const colorStatusWarningTint = Color(0x24E0A030);
  /// `--adm-color-status-warning-border: rgba(224,160,48,0.4)`
  static const colorStatusWarningBorder = Color(0x66E0A030);
  /// `--adm-color-status-danger: #e8556d`
  static const colorStatusDanger = Color(0xFFE8556D);
  /// `--adm-color-status-danger-text: #f07a8c`
  static const colorStatusDangerText = Color(0xFFF07A8C);
  /// `--adm-color-status-danger-tint: rgba(232,85,109,0.14)`
  static const colorStatusDangerTint = Color(0x24E8556D);
  /// `--adm-color-status-danger-border: rgba(232,85,109,0.45)`
  static const colorStatusDangerBorder = Color(0x73E8556D);
  /// `--adm-color-status-info: #7cb8f0`
  static const colorStatusInfo = Color(0xFF7CB8F0);
  /// `--adm-color-line-hairline: rgba(255,255,255,0.045)`
  static const colorLineHairline = Color(0x0BFFFFFF);
  /// `--adm-color-line-default: rgba(255,255,255,0.08)`
  static const colorLineDefault = Color(0x14FFFFFF);
  /// `--adm-color-line-strong: rgba(255,255,255,0.14)`
  static const colorLineStrong = Color(0x24FFFFFF);
}

/// Pixel dimensions — spacing, radii, sizes, type sizes. All `double`, because
/// every Flutter dimension is.
abstract final class AdminDims {
  /// `--adm-type-overline-size: 11px`
  static const typeOverlineSize = 11.0;
  /// `--adm-type-caption-size: 12px`
  static const typeCaptionSize = 12.0;
  /// `--adm-type-small-size: 13.5px`
  static const typeSmallSize = 13.5;
  /// `--adm-type-body-size: 14px`
  static const typeBodySize = 14.0;
  /// `--adm-type-nav-size: 14.5px`
  static const typeNavSize = 14.5;
  /// `--adm-type-lead-size: 16px`
  static const typeLeadSize = 16.0;
  /// `--adm-type-card-title-size: 17px`
  static const typeCardTitleSize = 17.0;
  /// `--adm-type-card-title-tracking: -0.3px`
  static const typeCardTitleTracking = -0.3;
  /// `--adm-type-section-title-size: 20px`
  static const typeSectionTitleSize = 20.0;
  /// `--adm-type-section-title-tracking: -0.6px`
  static const typeSectionTitleTracking = -0.6;
  /// `--adm-type-page-title-size: 28px`
  static const typePageTitleSize = 28.0;
  /// `--adm-type-page-title-tracking: -0.8px`
  static const typePageTitleTracking = -0.8;
  /// `--adm-type-display-size: 48px`
  static const typeDisplaySize = 48.0;
  /// `--adm-type-display-tracking: -1px`
  static const typeDisplayTracking = -1.0;
  /// `--adm-space-1: 2px`
  static const space1 = 2.0;
  /// `--adm-space-2: 4px`
  static const space2 = 4.0;
  /// `--adm-space-3: 6px`
  static const space3 = 6.0;
  /// `--adm-space-4: 8px`
  static const space4 = 8.0;
  /// `--adm-space-5: 10px`
  static const space5 = 10.0;
  /// `--adm-space-6: 12px`
  static const space6 = 12.0;
  /// `--adm-space-7: 14px`
  static const space7 = 14.0;
  /// `--adm-space-8: 16px`
  static const space8 = 16.0;
  /// `--adm-space-10: 20px`
  static const space10 = 20.0;
  /// `--adm-space-12: 24px`
  static const space12 = 24.0;
  /// `--adm-space-16: 32px`
  static const space16 = 32.0;
  /// `--adm-space-20: 40px`
  static const space20 = 40.0;
  /// `--adm-radius-xs: 4px`
  static const radiusXs = 4.0;
  /// `--adm-radius-sm: 6px`
  static const radiusSm = 6.0;
  /// `--adm-radius-md: 10px`
  static const radiusMd = 10.0;
  /// `--adm-radius-lg: 12px`
  static const radiusLg = 12.0;
  /// `--adm-radius-xl: 16px`
  static const radiusXl = 16.0;
  /// `--adm-radius-2xl: 20px`
  static const radius2xl = 20.0;
  /// `--adm-radius-pill: 999px`
  static const radiusPill = 999.0;
  /// `--adm-size-control: 44px`
  static const sizeControl = 44.0;
  /// `--adm-size-control-compact: 40px`
  static const sizeControlCompact = 40.0;
  /// `--adm-size-row-list: 52px`
  static const sizeRowList = 52.0;
  /// `--adm-size-row-rich: 64px`
  static const sizeRowRich = 64.0;
  /// `--adm-size-env-strip: 34px`
  static const sizeEnvStrip = 34.0;
  /// `--adm-size-icon-sm: 15px`
  static const sizeIconSm = 15.0;
  /// `--adm-size-icon-md: 17px`
  static const sizeIconMd = 17.0;
  /// `--adm-size-icon-lg: 18px`
  static const sizeIconLg = 18.0;
  /// `--adm-breakpoint-xl: 1440px`
  static const breakpointXl = 1440.0;
  /// `--adm-breakpoint-lg: 1200px`
  static const breakpointLg = 1200.0;
  /// `--adm-breakpoint-md: 900px`
  static const breakpointMd = 900.0;
  /// `--adm-breakpoint-sm: 768px`
  static const breakpointSm = 768.0;
  /// `--adm-breakpoint-container-narrow: 560px`
  static const breakpointContainerNarrow = 560.0;
}

/// Unitless numbers — line heights, font weights, z-indices, opacities. These keep
/// the source literal's own type: a line height of `1.3` is a double, a font
/// weight of `500` is an int, because that is what each one is.
abstract final class AdminNums {
  /// `--adm-font-weight-regular: 400`
  static const fontWeightRegular = 400;
  /// `--adm-font-weight-medium: 500`
  static const fontWeightMedium = 500;
  /// `--adm-font-weight-semibold: 600`
  static const fontWeightSemibold = 600;
  /// `--adm-type-overline-line: 1.3`
  static const typeOverlineLine = 1.3;
  /// `--adm-type-overline-weight: 500`
  static const typeOverlineWeight = 500;
  /// `--adm-type-caption-line: 1.4`
  static const typeCaptionLine = 1.4;
  /// `--adm-type-caption-weight: 400`
  static const typeCaptionWeight = 400;
  /// `--adm-type-caption-tracking: 0`
  static const typeCaptionTracking = 0;
  /// `--adm-type-small-line: 1.45`
  static const typeSmallLine = 1.45;
  /// `--adm-type-small-weight: 400`
  static const typeSmallWeight = 400;
  /// `--adm-type-small-tracking: 0`
  static const typeSmallTracking = 0;
  /// `--adm-type-body-line: 1.5`
  static const typeBodyLine = 1.5;
  /// `--adm-type-body-weight: 400`
  static const typeBodyWeight = 400;
  /// `--adm-type-body-tracking: 0`
  static const typeBodyTracking = 0;
  /// `--adm-type-nav-line: 1.3`
  static const typeNavLine = 1.3;
  /// `--adm-type-nav-weight: 400`
  static const typeNavWeight = 400;
  /// `--adm-type-nav-tracking: 0`
  static const typeNavTracking = 0;
  /// `--adm-type-lead-line: 1.5`
  static const typeLeadLine = 1.5;
  /// `--adm-type-lead-weight: 400`
  static const typeLeadWeight = 400;
  /// `--adm-type-lead-tracking: 0`
  static const typeLeadTracking = 0;
  /// `--adm-type-card-title-line: 1.3`
  static const typeCardTitleLine = 1.3;
  /// `--adm-type-card-title-weight: 500`
  static const typeCardTitleWeight = 500;
  /// `--adm-type-section-title-line: 1.25`
  static const typeSectionTitleLine = 1.25;
  /// `--adm-type-section-title-weight: 500`
  static const typeSectionTitleWeight = 500;
  /// `--adm-type-page-title-line: 1.1`
  static const typePageTitleLine = 1.1;
  /// `--adm-type-page-title-weight: 500`
  static const typePageTitleWeight = 500;
  /// `--adm-type-display-line: 1`
  static const typeDisplayLine = 1;
  /// `--adm-type-display-weight: 500`
  static const typeDisplayWeight = 500;
  /// `--adm-space-0: 0`
  static const space0 = 0;
  /// `--adm-z-header: 10`
  static const zHeader = 10;
  /// `--adm-z-menu: 20`
  static const zMenu = 20;
  /// `--adm-z-dialog: 50`
  static const zDialog = 50;
  /// `--adm-z-toast: 60`
  static const zToast = 60;
}

/// Values with no Flutter equivalent, carried verbatim so nothing is reinterpreted.
abstract final class AdminTokensRaw {
  /// `--adm-font-family: "Schibsted Grotesk", system-ui, sans-serif`
  static const fontFamily = "\"Schibsted Grotesk\", system-ui, sans-serif";
  /// `--adm-font-mono: ui-monospace, SFMono-Regular, Menlo, monospace`
  static const fontMono = "ui-monospace, SFMono-Regular, Menlo, monospace";
  /// `--adm-type-overline-tracking: 0.12em`
  static const typeOverlineTracking = "0.12em";
  /// `--adm-type-overline-case: uppercase`
  static const typeOverlineCase = "uppercase";
  /// `--adm-space-gutter: clamp(16px, 2.6vw, 36px)`
  static const spaceGutter = "clamp(16px, 2.6vw, 36px)";
  /// `--adm-shadow-menu: inset 0 0 0 1px rgba(255,255,255,0.1), 0 20px 50px rgba(0,0,0,0.6)`
  static const shadowMenu = "inset 0 0 0 1px rgba(255,255,255,0.1), 0 20px 50px rgba(0,0,0,0.6)";
  /// `--adm-shadow-edge: inset 0 0 0 1px rgba(255,255,255,0.08)`
  static const shadowEdge = "inset 0 0 0 1px rgba(255,255,255,0.08)";
  /// `--adm-shadow-divider: inset 0 -1px 0 rgba(255,255,255,0.045)`
  static const shadowDivider = "inset 0 -1px 0 rgba(255,255,255,0.045)";
  /// `--adm-shadow-header: inset 0 -1px 0 rgba(255,255,255,0.07)`
  static const shadowHeader = "inset 0 -1px 0 rgba(255,255,255,0.07)";
  /// `--adm-motion-fast: 120ms`
  static const motionFast = "120ms";
  /// `--adm-motion-base: 180ms`
  static const motionBase = "180ms";
  /// `--adm-motion-slow: 240ms`
  static const motionSlow = "240ms";
  /// `--adm-motion-ease: cubic-bezier(0.2, 0, 0, 1)`
  static const motionEase = "cubic-bezier(0.2, 0, 0, 1)";
  /// `--adm-motion-skeleton: 1.4s linear infinite`
  static const motionSkeleton = "1.4s linear infinite";
}
