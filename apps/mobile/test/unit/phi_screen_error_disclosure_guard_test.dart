import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// SEC-PHI-2 — a screen that renders PHI must not print the raw exception.
///
/// ── WHY THIS SCREEN ────────────────────────────────────────────────────────
/// `client_detail_screen.dart` is the coach's assessment surface. It carries
/// `TabController(length: 4)` with **`Tab(text: 'Assessment')`** and
/// **`Tab(text: 'PAR-Q')`**, wired into a live `TabBarView` as `_AssessmentTab`
/// and `_ParqHealthTab`, and it renders `parq_answers`, `medical_conditions`,
/// `injury_description`, `injury_locations`, `risk_level`, `risk_score` and
/// `risk_flags`.
///
/// It printed the raw exception into that screen:
///
/// ```dart
/// error: (e, _) => Center(child: Text('Error: $e', …)),
/// ```
///
/// A PostgREST/Postgres error is not opaque. It carries table and column
/// names, constraint text, and on a unique violation the **conflicting value**
/// — rendered on a page whose subject is somebody's medical history.
///
/// ── WHAT THIS GUARD IS NOT ─────────────────────────────────────────────────
/// It does **not** claim the app never leaks an exception: five other sites
/// still do (recorded, all on non-PHI coach screens). It pins the PHI screens,
/// which is where the disclosure matters most, and names the others so the
/// scope is explicit rather than implied.
void main() {
  /// Screens that render a client's intake/PAR-Q record.
  const phiScreens = <String>[
    'lib/features/dashboard/presentation/client_detail_screen.dart',
    'lib/features/coach/presentation/coach_copilot_screen.dart',
  ];

  test('SEC-PHI-2 the guard is looking at a real PHI surface', () {
    // An absent result must not read as "no leak" — the H-D1 lesson.
    final src = File(phiScreens.first).readAsStringSync();
    expect(src, contains("Tab(text: 'PAR-Q')"),
        reason: 'this file is pinned because it renders PAR-Q; if that has '
            'moved, re-point the guard in the same change');
    expect(src, contains('_AssessmentTab'));
    expect(src, contains('parq_answers'));
  });

  test('SEC-PHI-2 no PHI screen interpolates the raw exception', () {
    final offenders = <String>[];
    final raw = RegExp(r"""Text\(\s*'Error: \$e|Text\(\s*"Error: \$e|Text\(\s*'\$e'""");
    for (final path in phiScreens) {
      final f = File(path);
      expect(f.existsSync(), isTrue, reason: '$path has moved');
      for (final (i, line) in f.readAsLinesSync().indexed) {
        final code = line.split('//').first;
        if (raw.hasMatch(code)) offenders.add('$path:${i + 1}');
      }
    }
    expect(offenders, isEmpty,
        reason: 'A raw exception is being rendered on a screen that shows a '
            "client's medical record. Use the repository's "
            '`Could not load [noun]` pattern instead:\n  '
            '${offenders.join('\n  ')}');
  });

  test('SEC-PHI-2 the replacement uses the established pattern', () {
    final src =
        File(phiScreens.first).readAsStringSync();
    expect(src, contains("Could not load this client"));
    expect(src, contains("Could not load programs"));
  });
}
