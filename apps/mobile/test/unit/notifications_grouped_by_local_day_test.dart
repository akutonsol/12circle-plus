import 'package:circle_fitness/features/notifications/domain/notification_groups.dart';
import 'package:flutter_test/flutter_test.dart';

// Notifications were grouped by the UTC day.
//
// `createdAt` comes from the row parsed as UTC, and `groupFor` read its
// year/month/day as they were. The time beside it (`notificationMeta`) is
// converted to local, so the two disagreed: in Sydney a 07:00 notification
// (21:00 UTC the day before) sat under "Earlier this week" next to "07:00"; in
// New York an evening one moved into the next day's "Today".
//
// HOW TO SEE IT FAIL: run with TZ=Australia/Sydney or TZ=America/New_York. Under
// UTC the two days agree and the old code passes.

void main() {
  test("a notification from this morning is Today, however it arrives", () {
    final now = DateTime.now();
    final morning = DateTime(now.year, now.month, now.day, 0, 30);
    if (now.isBefore(morning)) return; // the first half hour of the day
    expect(groupFor(morning.toUtc(), now: now), NotificationGroup.today,
        reason: 'THE defect: the UTC day of ${morning.toUtc()} was used '
            '(offset ${now.timeZoneOffset})');
  });

  test("last night's notification is not Today, however it arrives", () {
    final now = DateTime.now();
    final lastNight = DateTime(now.year, now.month, now.day).subtract(const Duration(minutes: 30));
    expect(groupFor(lastNight.toUtc(), now: now), NotificationGroup.earlierThisWeek);
  });

  test('a UTC instant and the same local instant always group alike', () {
    final now = DateTime.now();
    for (var h = 0; h < 48; h++) {
      final at = now.subtract(Duration(hours: h));
      expect(groupFor(at.toUtc(), now: now), groupFor(at, now: now), reason: '$h hours ago');
    }
  });
}
