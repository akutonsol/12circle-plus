import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ROUTE-P · every registered route must keep existing.
///
/// ── THE GAP THIS CLOSES, MEASURED ──────────────────────────────────────────
/// Before this file, the only numeric bound on the route table anywhere in the
/// 1,547-test suite was `expect(routes.length, greaterThan(50))` in
/// `orphan_route_guard_test.dart:69`. With 97 routes registered, **46 of them
/// could be deleted and every test would still pass.** Only two routes —
/// `/events` and `/home` — were individually asserted to exist anywhere.
///
/// The sibling guards cover the other direction and a different concern:
///   * `orphan_route_guard_test`   — no NEW route without a way in;
///   * `release_route_gate_test`   — debug-only routes are excluded in release;
///   * `client_nav_contract_guard_test`, `duplicate_screen_class_guard_test`.
/// None of them fails when an existing route DISAPPEARS, which is the one
/// direction that silently removes product surface.
///
/// ── WHY THE LIST IS WRITTEN OUT ────────────────────────────────────────────
/// Deriving the expected set from the file under test makes the assertion
/// self-referential: deleting a route would delete its own assertion and the
/// suite would stay green. That exact defect was measured in a sibling guard in
/// this repository — 51 assertions passed before a protected entry was removed,
/// 50 passed after, green both times. So the routes are listed here, and the
/// comparison runs in BOTH directions: a deletion fails, and an addition fails
/// until it is recorded here in the same diff.
///
/// ── PROVENANCE ─────────────────────────────────────────────────────────────
/// `docs/FINAL_SCREEN_INVENTORY.json` records `routes: 91` and
/// `routes_release_build: 89` at baseline `0aa844a`. Verified against code:
/// `0aa844a` declares exactly **91** routes, and HEAD declares **97**. **No
/// route present at the baseline has been lost**; the six additions are the
/// Admin Control Center surfaces (`/admin-ecosystem`, `/admin-metrics`,
/// `/admin-operations`, `/admin-people`, `/admin-settings`, `/admin-trust`).
/// 97 − 2 debug-only = **95** release routes, against 89 at the baseline.
///
/// This guard asserts the posture the code already has, so it starts green by
/// describing reality rather than by demanding a change. The separate claim of
/// "174 approved screens" is **not** used here: the repository records it as
/// uncorroborated under `CONF-01`
/// (`V5_IMPACT_ANALYSIS_2026-09-27.md:392` — *"174 approved screens not
/// corroborated | 91 routes / 148 surfaces"*), and a guard must not encode a
/// number the repository itself disputes.
void main() {
  final router = File('lib/core/router/app_router.dart');

  /// Every `path: '...'` declared in the router, de-duplicated.
  Set<String> declaredRoutes() {
    final src = router.readAsStringSync();
    return RegExp(r"path:\s*'([^']+)'")
        .allMatches(src)
        .map((m) => m.group(1)!)
        .toSet();
  }

  /// The routes registered at the time of writing. Changing the route table is
  /// allowed; changing it WITHOUT updating this list is not.
  const expectedRoutes = <String>{
    '/action-items',
    '/active-workout',
    '/activity',
    '/admin-dashboard',
    '/admin-ecosystem',
    '/admin-exercise-review',
    '/admin-metrics',
    '/admin-operations',
    '/admin-people',
    '/admin-settings',
    '/admin-trust',
    '/ai-coach',
    '/ai-nutrition',
    '/appointments',
    '/book-call',
    '/booking-handoff',
    '/challenge-detail',
    '/challenges',
    '/chat',
    '/checkin-detail',
    '/checkin-form',
    '/checkins',
    '/class-detail',
    '/classes',
    '/coach',
    '/coach-business',
    '/coach-checkin-review',
    '/coach-classes',
    '/coach-client-workouts',
    '/coach-copilot',
    '/coach-dashboard',
    '/coach-directory',
    '/coach-marketplace',
    '/coach-packages',
    '/coach-payments',
    '/coach-plan',
    '/community',
    '/compliance',
    '/content-center',
    '/content-review',
    '/continuous-coaching',
    '/create-exercise',
    '/daily-checkin',
    '/directory',
    '/events',
    '/exercise-database',
    '/exercise-detail',
    '/exercise-library',
    '/food-search',
    '/forgot-password',
    '/goals',
    '/grocery-list',
    '/habits',
    '/help-center',
    '/home',
    '/insights',
    '/intake',
    '/integrations',
    '/knowledge-review',
    '/log-meal',
    '/login',
    '/meal-plan',
    '/meals-dashboard',
    '/messages',
    '/mie-debugger',
    '/notification-preferences',
    '/notifications',
    '/nutrition',
    '/nutrition-overview',
    '/observability',
    '/onboarding',
    '/payment-cancel',
    '/payment-success',
    '/personal-info',
    '/pods',
    '/privacy-policy',
    '/profile',
    '/program-builder',
    '/program-designer',
    '/progress',
    '/qa-center',
    '/reset-password',
    '/score',
    '/settings',
    '/signup',
    '/splash',
    '/strength-progression',
    '/subscription',
    '/terms-of-service',
    '/train',
    '/upgrade',
    '/vendor-portal',
    '/weekly-review',
    '/womens-health',
    '/workout-detail',
    '/workout-history',
    '/workouts',
  };

  /// Excluded from a release build. Asserted by `release_route_gate_test`;
  /// repeated here only so the release-count arithmetic below is explicit.
  const debugOnlyRoutes = <String>{'/mie-debugger', '/qa-center'};

  group('ROUTE-P · registered routes are preserved', () {
    test('the router is readable and the detector is not vacuous', () {
      // Without this, every assertion below could pass by finding nothing.
      expect(router.existsSync(), isTrue,
          reason: 'router not found at ${router.path} — this guard is blind');
      expect(declaredRoutes().length, greaterThan(80),
          reason: 'only ${declaredRoutes().length} routes parsed; the regex has '
              'stopped matching the router and every assertion below is inert');
    });

    test('no registered route has been removed', () {
      final missing = expectedRoutes.difference(declaredRoutes()).toList()..sort();
      expect(missing, isEmpty,
          reason: 'these routes were registered and are now gone: '
              '${missing.join(', ')}.\n'
              'Removing a route removes a product surface. If the removal is '
              'intended, delete it from expectedRoutes in THIS file in the same '
              'change, so the loss is visible in review rather than silent.');
    });

    test('no route was added without being recorded here', () {
      final added = declaredRoutes().difference(expectedRoutes).toList()..sort();
      expect(added, isEmpty,
          reason: 'these routes are registered but not listed in this guard: '
              '${added.join(', ')}.\n'
              'Add them to expectedRoutes so the preserved set stays complete — '
              'otherwise a route added today can be deleted tomorrow unnoticed.');
    });

    test('the release-build route count is explicit', () {
      final release = declaredRoutes().difference(debugOnlyRoutes);
      expect(release.length, declaredRoutes().length - debugOnlyRoutes.length,
          reason: 'a debug-only path is no longer registered, so the release '
              'count no longer follows from the arithmetic this asserts');
      expect(release, isNot(contains('/qa-center')));
      expect(release, isNot(contains('/mie-debugger')));
    });

    test('every baseline route from 0aa844a is still present', () {
      // The canonical inventory's 91 are a SUBSET of expectedRoutes by
      // construction (97 = 91 baseline + 6 Admin). Asserting the subset
      // relation keeps the provenance claim in the doc comment honest.
      final declared = declaredRoutes();
      const baselineAdditions = <String>{
        '/admin-ecosystem', '/admin-metrics', '/admin-operations',
        '/admin-people', '/admin-settings', '/admin-trust',
      };
      final baseline = expectedRoutes.difference(baselineAdditions);
      expect(baseline.length, 91,
          reason: 'the baseline set should be 91 routes, as '
              'FINAL_SCREEN_INVENTORY.json records at 0aa844a; got '
              '${baseline.length}');
      expect(declared.containsAll(baseline), isTrue,
          reason: 'a route from the 0aa844a baseline is missing: '
              '${baseline.difference(declared).join(', ')}');
    });
  });
}
