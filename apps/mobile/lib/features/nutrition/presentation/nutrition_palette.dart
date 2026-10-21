import 'package:flutter/material.dart';

/// FIT-003's palette, in **one** place.
///
/// `meals_dashboard_screen.dart` held these as top-level consts. Extracting
/// `MealRowTile` out of that 1,490-line screen would have meant copying them,
/// making a **78th** file that declares its own colours — the drift `H-D2` in
/// `test/unit/presentation_drift_guard_test.dart` exists to stop.
///
/// So the two files share one declaration. This is not the semantic migration
/// — components consuming `context.helix` rather than raw hex is **D-2**, an
/// open owner decision, and nothing here pre-empts it. It only stops one
/// screen's palette becoming two.
const nutBg    = Color(0xFF050510);
const nutCard  = Color(0xFF111120);
const nutBrand = Color(0xFFA855F7);
const nutWhite = Colors.white;
const nutGrey  = Color(0xFF888898);
const nutBlue  = Color(0xFF60A5FA);
