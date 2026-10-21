import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// DEAD-G1 — two files must not declare the same screen class, and the live
/// one must stay the one the router builds.
///
/// ── THE HAZARD, PRECISELY ──────────────────────────────────────────────────
/// `home_org.dart` and `home_screen.dart` **both declare `class HomeScreen`**.
/// `app_router.dart` builds `const HomeScreen()` for `/home` and resolves it
/// by a **single import line**.
///
/// Dart will not let both be imported at once — that is an ambiguous-import
/// error — so the danger is not accidental double-import. It is a one-line
/// **swap**: change `import '…/home_screen.dart'` to `home_org.dart` and
/// `/home` silently renders a different screen. Nothing fails. The analyzer is
/// happy. The tests are happy.
///
/// `docs/MISSING_SCREEN_REGISTER.md` records that this duplication already
/// "caused the FIT-001 mis-mapping" once — the coverage ledger measured the
/// dead file and reported the live screen's coverage from it.
///
/// ── WHAT WAS MEASURED, RATHER THAN ASSUMED ─────────────────────────────────
/// Exactly **two** public classes are declared in more than one file:
///
///   `HomeScreen`       home_org.dart (dead) · home_screen.dart (**routed**)
///   `DashboardScreen`  dash_org.dart · dashboard_screen.dart (**both dead** —
///                      the router builds `AdminDashboardScreen`,
///                      `CoachDashboardScreen` and `MealsDashboardScreen`, and
///                      no route builds a bare `DashboardScreen`)
///
/// ── WHY A GUARD AND NOT A DELETION ─────────────────────────────────────────
/// Deleting a screen file is destructive and is **OD-32**. This changes
/// nothing; it stops a third from appearing and pins which of the two the
/// router builds. The register's own observation is the argument: across 202
/// mobile commits **no screen file has ever been deleted** — the failure mode
/// is pure accretion.
void main() {
  late Map<String, List<String>> declarations;
  late String router;

  setUpAll(() {
    router = File('lib/core/router/app_router.dart').readAsStringSync();
    declarations = <String, List<String>>{};
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      for (final m
          in RegExp(r'^class\s+([A-Z]\w+)', multiLine: true)
              .allMatches(f.readAsStringSync())) {
        declarations.putIfAbsent(m.group(1)!, () => []).add(f.path);
      }
    }
  });

  test('DEAD-G1 the detector can see the codebase', () {
    // An absent result must not read as "no duplicates" — the H-D1 lesson.
    expect(declarations.length, greaterThan(200),
        reason: 'almost no classes parsed — the detector is broken');
    expect(declarations, contains('HomeScreen'));
  });

  // The FILES, not just the names. A first version pinned the two duplicated
  // class NAMES, and a mutation adding a THIRD file declaring `HomeScreen`
  // survived it — `HomeScreen` was already on the list, so a third copy was
  // not a new name. Accretion is exactly what this guards, so it pins the
  // exact file set for each.
  test('DEAD-G1 no NEW duplicate, and no new copy of an existing one', () {
    const known = <String, List<String>>{
      'HomeScreen': [
        'lib/features/home/presentation/home_org.dart',
        'lib/features/home/presentation/home_screen.dart',
      ],
      'DashboardScreen': [
        'lib/features/dashboard/presentation/dash_org.dart',
        'lib/features/dashboard/presentation/dashboard_screen.dart',
      ],
      // RECON-1 — created by the local↔cloud integration, not by either side
      // alone, which is why neither workstream's CI could see it:
      //
      //   widgets/log_weight_sheet.dart  declares LogWeightSheet in the common
      //                                  base, Local AND Cloud. **Dead** —
      //                                  nothing imports it.
      //   progress_screen.dart           Cloud (QAX-COR-06, fa593a7) made its
      //                                  private sheet PUBLIC so a widget test
      //                                  could drive it, the same testability
      //                                  motive as AddMealSheet. **Live** —
      //                                  built at progress_screen.dart:306.
      //
      // Cloud could not have caught it: DEAD-G1 is a Local-only guard. Listed
      // rather than deleted, per this file's own OD-32 rationale above. The
      // file set is pinned, so a THIRD copy still fails.
      'LogWeightSheet': [
        'lib/features/progress/presentation/progress_screen.dart',
        'lib/features/progress/presentation/widgets/log_weight_sheet.dart',
      ],
    };

    final dupes = <String, List<String>>{
      for (final e in declarations.entries)
        if (e.value.length > 1) e.key: (e.value.toList()..sort()),
    };

    expect(
      dupes.keys.toSet().difference(known.keys.toSet()),
      isEmpty,
      reason: 'Two files now declare the same class. Whichever the router '
          'imports is the one that ships, and swapping that single line '
          'changes the app with nothing failing.',
    );
    expect(
      known.keys.toSet().difference(dupes.keys.toSet()),
      isEmpty,
      reason: 'a recorded duplicate is gone — delete it from `known` in the '
          'same change rather than leaving a stale excuse behind',
    );

    known.forEach((cls, files) {
      expect(dupes[cls], files,
          reason: '`$cls` is declared in a different set of files than '
              'recorded. A THIRD copy is the accretion this exists to catch.');
    });
  });

  // The one-line swap. `/home` is the app's front door and the two candidates
  // are a live screen and a dead one.
  test('DEAD-G1 /home resolves HomeScreen from the LIVE file', () {
    expect(router, contains("import '../../features/home/presentation/home_screen.dart'"),
        reason: 'the router must import the live Home');
    expect(router.contains('home_org.dart'), isFalse,
        reason: 'home_org.dart is the dead duplicate — importing it would '
            'silently change what /home renders');
    expect(router, contains('const HomeScreen()'),
        reason: 'and /home must still build it');
  });

  test('DEAD-G1 neither bare DashboardScreen becomes routed', () {
    // Both are dead. The router builds AdminDashboardScreen,
    // CoachDashboardScreen and MealsDashboardScreen — all distinct classes.
    // A bare `DashboardScreen()` appearing here means one of the two dead
    // files just became live, which is a decision, not a refactor.
    expect(
      RegExp(r'=>\s*const\s+DashboardScreen\s*\(').hasMatch(router),
      isFalse,
      reason: 'a route now builds a bare DashboardScreen — say which of the '
          'two files it is and why, rather than letting the import decide',
    );
  });

  test('DEAD-G1 the dead Home duplicate stays out of the live tree', () {
    // Nothing may import it. If something does, the duplicate stops being
    // inert and the class collision becomes reachable.
    // Comments stripped. This assertion failed on first run against a COMMENT
    // in `app_scaffold.dart` that names `home_org.dart` while explaining why
    // the dead nav was removed — the **fifth** time a detector in this
    // programme has read its own prose as evidence, after
    // `tool/fit_coverage.dart`, the MSG-003 guard, the Connect copy guard and
    // NAV-G1. Every one was an inline fix; this is why the strippers exist.
    String strip(String src) => src
        .split('\n')
        .map((l) {
          final i = l.indexOf('//');
          return i < 0 ? l : l.substring(0, i);
        })
        .join('\n');

    final importers = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.endsWith('home_org.dart'))) {
      if (strip(f.readAsStringSync()).contains('home_org.dart')) {
        importers.add(f.path);
      }
    }
    expect(importers, isEmpty,
        reason: 'home_org.dart is imported by ${importers.join(', ')} — it is '
            'recorded as dead (OD-32) and must stay unreferenced until that '
            'decision is taken');
  });
}
