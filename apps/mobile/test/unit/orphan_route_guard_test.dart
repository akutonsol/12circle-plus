import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/orphan_route_sweep.dart'
    show registeredRoutes, navigatedRoutes, externallyEntered;

/// ROUTE-G1 — a registered route with no way in must not multiply.
///
/// ── WHY ────────────────────────────────────────────────────────────────────
/// Three orphaned routes were found in one cycle, each by hand, each by asking
/// what a declared FIT interaction opens:
///
///   `/activity`   FIT-001's nav         → Home's week-progress panel
///   `/meal-plan`  FIT-003's header      → the `Meal plan` icon control
///   `/goals`      FIT-029's "You" list  → the `Goals` row
///
/// Each was a registered screen nobody could open. The coverage metric cannot
/// see this — it reads labels, and a missing control has none to read — so the
/// only reason those three surfaced is that the design happened to declare a
/// control for each. **Nothing would have found a fourth.**
///
/// ── AND WHAT THE SWEEP THEN FOUND ──────────────────────────────────────────
/// Six anchors whose route has no caller, two of them LOCKED:
///
///   * **FIT-006 "Welcome"** measured **2/2 and is unreachable.** The design
///     package documents this itself — FIT-010's annotation reads *"the shipped
///     implementation is a different screen entirely, and it orphans locked
///     Welcome"* — so it is **OD-31**, not a defect to fix here;
///   * **FIT-019 "Log a meal"**: `/log-meal` builds a 23-line screen whose
///     `initState` immediately `context.go('/meals-dashboard')`. A redirect
///     stub with no caller — and the literal instance of the "route resolved
///     to a redirect stub" defect the original coverage ledger named.
///
/// This is a **shrinking allowlist**, checked in both directions. An unlisted
/// orphan fails as new; a listed one that gains a door also fails, so a fix
/// cannot leave a stale excuse behind.
void main() {
  /// Measured 2026-09-23. Each is a registered route nothing navigates to.
  const known = <String, String>{
    '/coach': 'a duplicate alias of /train — both build TrainHubScreen',
    '/coach-business': 'CoachBusinessScreen, no entry point',
    '/food-search': 'gated screen, no entry point',
    '/log-meal': 'a redirect stub to /meals-dashboard (FIT-019, locked)',
    '/nutrition-overview': 'NutritionScreen, no entry point',
    '/onboarding': 'FIT-006 Welcome — locked, and OD-31',
    '/pods': 'PodsScreen — FIT-071..074, all non-locked',
  };

  late List<String> routes;
  late Set<String> navigated;

  setUpAll(() {
    final router = File('lib/core/router/app_router.dart');
    expect(router.existsSync(), isTrue);
    routes = registeredRoutes(router.readAsStringSync());
    navigated = navigatedRoutes(Directory('lib'));
  });

  List<String> orphans() => routes
      .where((r) => !navigated.contains(r))
      .where((r) => !externallyEntered.containsKey(r))
      .where((r) => !navigated.any((n) => n.startsWith('$r/')))
      .toList();

  test('ROUTE-G1 the detector can see the router', () {
    // An absent result must not read as "nothing is orphaned" — the H-D1
    // lesson, which this suite has now been bitten by four times.
    expect(routes.length, greaterThan(50),
        reason: 'almost no routes parsed — the detector is broken');
    expect(navigated, isNotEmpty);
    // And it must recognise the ways in that are not literal calls.
    expect(navigated, contains('/events'),
        reason: '/events is reached through a data-driven `_Module(route: …)` '
            'list; a literal-call scan reports it orphaned when it is not');
    expect(navigated, contains('/home'));
  });

  test('ROUTE-G1 no NEW route is registered without a way in', () {
    final found = orphans();
    expect(
      found.toSet().difference(known.keys.toSet()),
      isEmpty,
      reason: 'A route was registered that nothing navigates to. A screen '
          'nobody can open is dead product, and the coverage metric cannot '
          'see it — it reads labels, and a missing control has none.\n'
          'Give it a door, or do not register it.',
    );
  });

  test('ROUTE-G1 a route that gained a door leaves the list', () {
    final found = orphans().toSet();
    expect(
      known.keys.toSet().difference(found),
      isEmpty,
      reason: 'a recorded orphan is now reachable — delete it from `known` in '
          'the same change rather than leaving a stale excuse behind',
    );
  });

  test('ROUTE-G1 externally-entered routes are named, not inferred', () {
    // "No caller in lib" and "entered from elsewhere" are different facts, and
    // guessing which is which is how a real orphan gets excused.
    for (final r in externallyEntered.keys) {
      expect(routes, contains(r),
          reason: '$r is excused as externally entered but is not registered');
      expect(externallyEntered[r], isNotEmpty,
          reason: '$r is excused without a reason');
    }
  });

  test('ROUTE-G1 /log-meal is still only a redirect stub', () {
    // If it becomes a real screen, it needs a door and this entry is wrong.
    final stub =
        File('lib/features/nutrition/presentation/log_meal_screen.dart');
    expect(stub.existsSync(), isTrue);
    final src = stub.readAsStringSync();
    expect(src, contains("context.go('/meals-dashboard')"));
    expect(src.split('\n').length, lessThan(40),
        reason: 'this grew into something real — it needs an entry point, not '
            'an allowlist entry');
  });
}
