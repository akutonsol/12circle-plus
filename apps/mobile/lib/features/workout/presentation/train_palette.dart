import 'package:flutter/material.dart';

/// FIT-014's palette, in **one** place.
///
/// ── WHY THIS FILE EXISTS ───────────────────────────────────────────────────
/// `train_hub_screen.dart` held these as a private `class _C`. Extracting
/// `WeekRowTile` out of that screen would have meant copying them, making a
/// **21st** per-screen private palette — the exact drift `H-D1` in
/// `test/unit/presentation_drift_guard_test.dart` exists to stop, and the one
/// it would not have caught (see the note on that guard: its regex detected
/// only 5 of the 20 files it listed).
///
/// So the two files share one declaration instead. This is not the semantic
/// migration — components consuming `context.helix` rather than raw hex is
/// **D-2**, an open owner decision, and nothing here pre-empts it. It only
/// stops one screen's palette becoming two.
class TrainColors {
  static const bg                   = Color(0xFF0E0E0F);
  static const surfaceContainerHigh = Color(0xFF2A2A2B);
  static const glassCard            = Color(0x72201F20);
  static const primary              = Color(0xFFDDB7FF);
  static const primaryContainer     = Color(0xFFB76DFF);
  static const inversePrimary       = Color(0xFF842BD2);
  static const onSurface            = Color(0xFFE5E2E3);
  static const onSurfaceVar         = Color(0xFFCDC3D0);
  static const outline              = Color(0xFF968E99);
  static const tertiary             = Color(0xFF6FFBBE);
  static const amber                = Color(0xFFFFD580);
}

/// `mic` — 11px, w500, 0.14em tracking, uppercased by the caller.
const trainMicStyle = TextStyle(
  color: TrainColors.outline,
  fontSize: 11,
  fontWeight: FontWeight.w500,
  letterSpacing: 1.54, // 0.14em at 11px
);
