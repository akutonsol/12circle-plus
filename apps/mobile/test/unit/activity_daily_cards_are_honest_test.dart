import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/dashboard/domain/dashboard_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Activity's daily cards showed figures that were not this member's.
//
//   * Steps: `stepsProvider` was the constant 6240, shown as the member's own
//     steps with a 62% bar. Nothing in the app counts steps.
//   * Water: `waterIntakeProvider` did not watch the signed-in user, so on a
//     shared device the next account started with the previous one's glasses.

User _user(String id) => User(
    id: id, appMetadata: const {}, userMetadata: const {}, aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z');

final _who = StateProvider<User?>((ref) => _user('member-a'));

void main() {
  test('steps are unknown, not 6240', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(stepsProvider), isNull, reason: 'THE defect: a constant 6240 for everyone');
  });

  test("the next account does not start with the previous one's water", () {
    final c = ProviderContainer(overrides: [
      currentUserProvider.overrideWith((ref) => ref.watch(_who)),
    ]);
    addTearDown(c.dispose);
    c.listen(waterIntakeProvider, (_, __) {});
    c.read(waterIntakeProvider.notifier).state = 5;
    expect(c.read(waterIntakeProvider), 5);

    c.read(_who.notifier).state = _user('member-b'); // A signs out, B signs in
    expect(c.read(waterIntakeProvider), 0,
        reason: "THE defect: B saw A's 5 glasses");
  });
}
