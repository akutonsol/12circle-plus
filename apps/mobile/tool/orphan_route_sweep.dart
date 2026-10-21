// Which registered routes have no way in?
//
// ── WHY THIS EXISTS ─────────────────────────────────────────────────────────
// Three orphaned routes were found in one cycle, each by hand, each by asking
// what a declared FIT interaction opens:
//
//   /activity    FIT-001's nav       → Home's week-progress panel
//   /meal-plan   FIT-003's header    → the `Meal plan` icon control
//   /goals       FIT-029's "You" list → the `Goals` row
//
// A route the router knows about and nothing opens is dead product. The
// coverage metric cannot see it — it reads labels, and a missing control has
// none to read — so the only reason these surfaced is that the design happened
// to declare a control for each. Nothing would have found a fourth.
//
// ── WHAT COUNTS AS A WAY IN ─────────────────────────────────────────────────
//   * `context.go('/x')`, `push`, `replace`, `pushReplacement`;
//   * `route: '/x'` in a data structure — `directory_screen.dart` navigates
//     through a list of `_Module(route: …)`, which a literal-call scan misses
//     and which made `/events` look orphaned when it is not;
//   * a redirect target returned from the router's own `redirect:`;
//   * `initialLocation`.
//
// ── AND WHAT IS ENTERED FROM OUTSIDE THE APP ────────────────────────────────
// Some routes are reached by a deep link or an external redirect and will
// never have a caller in `lib`. They are named here rather than inferred,
// because "no caller" and "entered from elsewhere" are different facts.
//
// Usage:  dart tool/orphan_route_sweep.dart
// Run from apps/mobile. Reports; the gate is
// `test/unit/orphan_route_guard_test.dart`.

import 'dart:io';

/// Reached from outside `lib`, with the reason.
const externallyEntered = <String, String>{
  '/splash': "the router's own initialLocation",
  '/login': 'the unauthenticated redirect target',
  '/reset-password': 'a deep link from a password-reset email',
  '/payment-success': 'a Stripe redirect URL',
  '/payment-cancel': 'a Stripe redirect URL',
};

List<String> registeredRoutes(String router) =>
    RegExp(r"path:\s*'(/[^']*)'")
        .allMatches(router)
        .map((m) => m.group(1)!)
        .toSet()
        .toList()
      ..sort();

Set<String> navigatedRoutes(Directory lib) {
  final out = <String>{};
  for (final f in lib
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))) {
    // Comments quote routes constantly in this codebase; a detector that reads
    // its own prose has been a defect here four times.
    final src = f
        .readAsStringSync()
        .split('\n')
        .map((l) {
          final i = l.indexOf('//');
          return i < 0 ? l : l.substring(0, i);
        })
        .join('\n');

    for (final m in RegExp(
            r"(?:go|push|replace|pushReplacement)\s*\(\s*'(/[^']*)'")
        .allMatches(src)) {
      out.add(m.group(1)!.split('?').first);
    }
    // Data-driven navigation: `_Module(route: '/events', …)`.
    for (final m in RegExp(r"route:\s*'(/[^']*)'").allMatches(src)) {
      out.add(m.group(1)!.split('?').first);
    }
    // The router's own redirects and entry point.
    for (final m in RegExp(r"(?:return|initialLocation:)\s*'(/[^']*)'")
        .allMatches(src)) {
      out.add(m.group(1)!);
    }
  }
  return out;
}

/// Re-exported so `fit_backlog.dart` can mark an anchor whose route has no
/// way in. A screen nobody can open is not implemented, whatever its labels
/// say.
void main() {
  final routerFile = File('lib/core/router/app_router.dart');
  if (!routerFile.existsSync()) {
    stderr.writeln('run from apps/mobile');
    exit(2);
  }

  final routes = registeredRoutes(routerFile.readAsStringSync());
  final nav = navigatedRoutes(Directory('lib'));

  final orphans = routes
      .where((r) => !nav.contains(r))
      .where((r) => !externallyEntered.containsKey(r))
      // A parent whose children are navigated is reachable.
      .where((r) => !nav.any((n) => n.startsWith('$r/')))
      .toList();

  for (final r in orphans) {
    stdout.writeln('  ORPHAN  $r');
  }
  stdout.writeln('\nregistered ${routes.length} · '
      'navigated ${routes.length - orphans.length - externallyEntered.length} · '
      'externally entered ${externallyEntered.length} · '
      'ORPHANED ${orphans.length}');
}
