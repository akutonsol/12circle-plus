import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// NAV-G1 — the client bottom bar is FIT-001's five, and there is only one of
/// it.
///
/// ── WHAT THE PACKAGE DECLARES ──────────────────────────────────────────────
/// Eleven frames carry a bottom nav. **Ten of them declare the same client
/// set**, and the eleventh is FIT-001, which prepends `Directory` — its top
/// bar control, not a tab, as its own sub-title says ("Activity folded in ·
/// Directory moved to the top bar").
///
///     Home · Workouts · Nutrition · Check-In · Connect
///
/// The twelfth set is the coach bar — `Clients · Adherence · Programs ·
/// Check-ins` — which `app_shell.dart` already implements.
///
/// ── WHAT SHIPPED, AND HOW THE PACKAGE RESOLVES IT ──────────────────────────
/// `Home · Train · [FAB] · Activity · Check-In`. Every difference is settled
/// by the package rather than by preference:
///
///   * the FAB — FIT-001: *"Directory, chat and notifications sit in the top
///     bar; the animated FAB is gone."*
///   * Activity — "folded in"; its content is already on Home.
///   * `Train` → `Workouts` — FIT-014, verbatim: *"the destination is always
///     `/train`, always labelled Workouts. `coachingModeProvider` changes what
///     renders here ... not where the tab goes."*
///
/// ── AND WHY A GUARD ────────────────────────────────────────────────────────
/// This nav has drifted **three** ways in one codebase: the live bar, a dead
/// `AppBottomNav` in `app_scaffold.dart` drawing `Overview · Appts · Track ·
/// Messages`, and a dead `home_org.dart` drawing `Home · Workouts · Nutrition
/// · Community · Profile`. Two were unreachable, which is the only reason a
/// client never saw the bar change under them.
/// Source with `//` comments removed.
///
/// Every assertion below goes through this. The guards in this programme have
/// now read their own prose as evidence **four** times — `tool/fit_coverage.dart`,
/// the MSG-003 guard, the Connect copy guard, and this file's own first run,
/// where the header comment naming `navIndex` and `AppBottomNav` made the
/// "only one bottom nav" assertion fail against a codebase that had exactly
/// one. Repeating the fix inline is how the fourth happened; it is a function
/// now.
String stripComments(String src) => src
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i < 0 ? l : l.substring(0, i);
    })
    .join('\n');

void main() {
  final shell = File('lib/core/router/app_shell.dart');
  late String source;

  setUpAll(() {
    expect(shell.existsSync(), isTrue);
    source = shell.readAsStringSync();
  });

  /// `_NavItem(... label: 'X' ...)` labels, in source order, with comments
  /// stripped — this file's own comments quote the labels it replaced, and a
  /// detector that reads its own prose is a defect this programme has now hit
  /// three times.
  List<String> navLabelsIn(String src) {
    final stripped = stripComments(src);
    return RegExp(r"_NavItem\([^)]*?label:\s*'([^']+)'", dotAll: true)
        .allMatches(stripped)
        .map((m) => m.group(1)!)
        .toList();
  }

  test('NAV-G1 the detector can see the bar', () {
    // An absent result must not read as "the nav is correct".
    expect(navLabelsIn(source), isNotEmpty,
        reason: 'no _NavItem labels found at all — the detector is broken, '
            'or the bar has been rewritten in a shape this cannot read');
  });

  test('NAV-G1 the client bar is FIT-001\'s five, in order', () {
    final labels = navLabelsIn(source);
    // The coach bar is declared first in this file; the client bar follows.
    const client = ['Home', 'Workouts', 'Nutrition', 'Check-In', 'Connect'];
    expect(
      labels.sublist(labels.length - 5),
      client,
      reason: 'The package declares this set in ten of the eleven frames that '
          'carry a bottom nav. Found: $labels',
    );
  });

  test('NAV-G1 the coach bar is unchanged', () {
    final labels = navLabelsIn(source);
    expect(labels.take(4).toList(),
        ['Clients', 'Compliance', 'Programs', 'Check-ins'],
        reason: 'the coach bar is a separate declaration and this change does '
            'not touch it');
  });

  test('NAV-G1 the labels the package replaced do not come back', () {
    final labels = navLabelsIn(source);
    for (final gone in const ['Train', 'AI Train', 'Activity']) {
      expect(labels, isNot(contains(gone)),
          reason: '`$gone` is not one of FIT-001\'s destinations. `Train` is '
              'FIT-014\'s ruling ("always labelled Workouts"); `Activity` is '
              'folded into Home.');
    }
  });

  test('NAV-G1 the client bar carries no FAB', () {
    // FIT-001: "the animated FAB is gone." The coach bar keeps one, so this
    // asserts the count rather than the absence.
    final stripped = stripComments(source);
    expect(RegExp(r'_AnimatedFab\(onTap:').allMatches(stripped).length, 1,
        reason: 'exactly one FAB should remain, on the coach bar');
    expect(stripped, contains("_AnimatedFab(onTap: () => context.go('/coach-directory'))"),
        reason: 'and it is the coach one');
  });

  test('NAV-G1 every destination is a registered route', () {
    final router = File('lib/core/router/app_router.dart').readAsStringSync();
    final stripped = stripComments(source);
    final destinations = RegExp(r"context\.go\('([^']+)'\)")
        .allMatches(stripped)
        .map((m) => m.group(1)!)
        .toSet();
    expect(destinations, isNotEmpty);
    for (final route in destinations) {
      expect(router, contains("path: '$route'"),
          reason: '`$route` is not registered — go_router will land on an '
              'error page and nothing fails at compile time');
    }
  });

  test('NAV-G1 there is only ONE bottom nav in the codebase', () {
    // `app_scaffold.dart` held a dead `AppBottomNav` drawing a third
    // vocabulary; `home_org.dart` holds a dead fourth. Unreachable code that
    // contradicts the shipped architecture is how a fifth gets written.
    final scaffold = stripComments(
        File('lib/shared/widgets/app_scaffold.dart').readAsStringSync());
    expect(scaffold.contains('class AppBottomNav'), isFalse,
        reason: 'a second bottom nav, drawing Overview/Appts/Track/Messages');
    expect(scaffold.contains('navIndex'), isFalse,
        reason: 'a REQUIRED parameter nine screens passed and nothing read — '
            'the A-G1 defect shape');
  });

  test('NAV-G1 /activity did not lose its only entrance', () {
    // The tab that was removed was its sole door. "Folded in" does not mean
    // orphaned — OD-15's lesson.
    final entries = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final src = f.readAsStringSync();
      if (RegExp(r"(go|push)\('/activity'\)").hasMatch(src)) {
        entries.add(f.path);
      }
    }
    expect(entries, isNotEmpty,
        reason: '/activity is registered but nothing navigates to it — a '
            '1,089-line screen with no door');
    expect(entries.any((e) => e.contains('home_screen.dart')), isTrue,
        reason: 'FIT-001 folds Activity into Home, so Home is where it opens '
            'from');

    // A mention is not a door. The first version of this assertion looked for
    // the STRING `go('/activity')` anywhere in the file, and a mutation that
    // killed the gesture survived because the `Semantics` declaration still
    // carried one. The entry must be an announced control AND a real gesture —
    // the pair `excludeSemantics` makes necessary (F-20).
    final home = stripComments(
        File('lib/features/home/presentation/home_screen.dart')
            .readAsStringSync());
    final wired = RegExp(r"onTap: \(\) => context\.go\('/activity'\)")
        .allMatches(home)
        .length;
    expect(wired, greaterThanOrEqualTo(2),
        reason: 'the Activity entry must declare its action to assistive '
            'technology AND wire a gesture. Found $wired of the 2 an '
            '`excludeSemantics` control needs.');
    expect(home, contains("hint: 'Opens your activity'"),
        reason: 'and say what it does — the visible label is the panel title, '
            'so the action belongs in the hint (WCAG 2.5.3)');
  });
}
