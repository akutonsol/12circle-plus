import 'package:circle_fitness/features/payments/presentation/manage_subscription_screen.dart';
import 'package:flutter_test/flutter_test.dart';

// "Renews" printed the UTC date of `current_period_end`, a day late for a member
// west of UTC whose period ends in their evening. Run with TZ=America/New_York
// to see the old code fail (under UTC the two dates agree).

void main() {
  test("the renewal date is the member's own day", () {
    final now = DateTime.now();
    final evening = DateTime(now.year, now.month, now.day, 21, 30);
    expect(renewsLabel(evening.toUtc().toIso8601String()),
        'Renews ${now.month}/${now.day}/${now.year}');
  });

  test('no period end is just "Active"', () => expect(renewsLabel(null), 'Active'));
}
