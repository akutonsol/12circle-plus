import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// FIT-003 · the Nutrition header's declared controls.
///
/// The board draws three things in this header that source can be held to:
///
///     <button class="ph ph-scan"        aria-label="Scan a meal">
///     <button class="ph ph-list-checks" aria-label="Meal plan">
///
/// plus a back control, which shipped as an **unnamed 30 px chevron** — an
/// A-G8 site on a primary destination.
///
/// `Meal plan` matters beyond the label: `/meal-plan` is a **registered route
/// that nothing in the app navigated to**. It was orphaned, the same shape
/// `/activity` was in before FIT-001's nav work, and this control is its door.
String _strip(String src) => src
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i < 0 ? l : l.substring(0, i);
    })
    .join('\n');

void main() {
  final screen = _strip(
      File('lib/features/nutrition/presentation/meals_dashboard_screen.dart')
          .readAsStringSync());

  test('the detector is looking at the header', () {
    expect(screen, contains('class _Header'),
        reason: 'the header moved — every assertion below would pass vacuously');
  });

  test('both declared icon controls exist, and are named', () {
    for (final label in const ['Scan a meal', 'Meal plan']) {
      expect(screen, contains("label: '$label'"),
          reason: 'FIT-003 declares `$label` as an icon-only header control');
    }
  });

  test('the back control is no longer an unnamed chevron', () {
    expect(screen, contains("label: 'Back'"));
    expect(
      RegExp(r'GestureDetector\(\s*onTap: \(\) => context\.canPop\(\)')
          .hasMatch(screen),
      isFalse,
      reason: 'a bare GestureDetector around a chevron reports no name — A-G8',
    );
  });

  test('Meal plan opens the route that had no door', () {
    expect(screen, contains("context.go('/meal-plan')"));
    final router =
        File('lib/core/router/app_router.dart').readAsStringSync();
    expect(router, contains("path: '/meal-plan'"),
        reason: 'never invent a destination — the route must be registered');
  });

  test('Scan a meal opens the sheet already on its scan input', () {
    expect(screen, contains("_showAddSheet(context, mode: 'ai_scan')"),
        reason: 'the header control is the short way to the same place; '
            'opening on the default tab would make it a duplicate of '
            '`Log a meal`');
    expect(screen, contains('initialMode'));
  });

  test('/meal-plan is reachable from somewhere', () {
    final entries = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      if (RegExp(r"(go|push)\('/meal-plan'\)").hasMatch(f.readAsStringSync())) {
        entries.add(f.path);
      }
    }
    expect(entries, isNotEmpty,
        reason: '/meal-plan is registered but nothing navigates to it — a '
            'route with no door');
  });
}
