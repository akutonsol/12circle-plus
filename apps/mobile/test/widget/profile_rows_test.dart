import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// FIT-029 · the two rows its "You" list declares that were not on the screen.
///
/// `Goals` matters beyond the label: `/goals` is a **registered route that
/// nothing in the app navigated to** — the third orphan this cycle has found
/// by asking what a declared control opens, after `/activity` (FIT-001) and
/// `/meal-plan` (FIT-003). This row is its door.
String _strip(String src) => src
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i < 0 ? l : l.substring(0, i);
    })
    .join('\n');

void main() {
  final screen = _strip(
      File('lib/features/profile/presentation/profile_screen.dart')
          .readAsStringSync());
  final router = File('lib/core/router/app_router.dart').readAsStringSync();

  test('the detector is looking at the profile rows', () {
    expect(screen, contains('_ProfileRow'),
        reason: 'the row widget moved — the assertions below would pass '
            'vacuously');
    expect(screen, contains("label: 'Personal information'"),
        reason: 'the You list moved');
  });

  test('both declared rows exist', () {
    for (final label in const ['Goals', 'Connected apps']) {
      expect(screen, contains("label: '$label'"),
          reason: "FIT-029's You list declares `$label`");
    }
  });

  test('each opens a registered route', () {
    for (final route in const ['/goals', '/integrations']) {
      expect(screen, contains("context.push('$route')"));
      expect(router, contains("path: '$route'"),
          reason: 'never invent a destination — $route must be registered');
    }
  });

  test('/goals is reachable from somewhere', () {
    final entries = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      if (RegExp(r"(go|push)\('/goals'\)").hasMatch(f.readAsStringSync())) {
        entries.add(f.path);
      }
    }
    expect(entries, isNotEmpty,
        reason: '/goals is registered but nothing navigates to it — a route '
            'with no door');
  });

  test('the count is live, not a literal', () {
    expect(screen, contains('connectedAppsCountProvider'));
    expect(screen, contains('connectedAppsBadge'),
        reason: 'the three no-badge cases live there, including the failed '
            'read that must not render as 0');
    expect(RegExp(r"label: 'Connected apps'[\s\S]{0,300}?Text\('\d+'")
        .hasMatch(screen), isFalse,
        reason: 'a hardcoded count would match the board and mean nothing');
  });
}
