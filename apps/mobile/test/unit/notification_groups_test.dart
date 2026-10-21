import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/features/notifications/domain/notification_groups.dart';

/// FIT-062 · the notification list's rules.
///
/// The board's accessibility mandate is stated, not implied: *"Unread carries
/// a dot AND the word 'Unread' AND full-strength ink — three signals, since a
/// violet dot alone fails for a colour-blind member."* The screen shipped with
/// one of the three.

final _now = DateTime(2026, 9, 23, 14, 0); // a Wednesday

void main() {
  group('grouping', () {
    test('today is Today', () {
      expect(groupFor(DateTime(2026, 9, 23, 9, 12), now: _now),
          NotificationGroup.today);
      expect(NotificationGroup.today.label, 'Today');
    });

    // "This week" is the last SEVEN DAYS, not the calendar week. A Monday
    // member would otherwise see Sunday's coach reply filed under `Earlier`,
    // which is true of the calendar and wrong about their week.
    test('the last seven days are Earlier this week', () {
      for (final d in const [1, 3, 6]) {
        expect(
          groupFor(_now.subtract(Duration(days: d)), now: _now),
          NotificationGroup.earlierThisWeek,
          reason: '$d days ago',
        );
      }
      expect(NotificationGroup.earlierThisWeek.label, 'Earlier this week');
    });

    test('a week or more back is Earlier', () {
      expect(groupFor(_now.subtract(const Duration(days: 7)), now: _now),
          NotificationGroup.older);
      expect(groupFor(_now.subtract(const Duration(days: 40)), now: _now),
          NotificationGroup.older);
      // The board draws two groups because its sample spans five days. A
      // notification from last month has to go somewhere that is not a lie.
      expect(NotificationGroup.older.label, 'Earlier');
    });

    test('a future timestamp is not filed in the past', () {
      expect(groupFor(_now.add(const Duration(days: 1)), now: _now),
          NotificationGroup.today);
    });
  });

  group('the three unread signals', () {
    // THE test. Shipping one of three is what happened.
    test('an unread notification carries all three', () {
      final s = unreadSignals(read: false);
      expect(s.dot, isTrue);
      expect(s.word, isTrue, reason: 'the word is the one a dot cannot replace');
      expect(s.fullStrengthInk, isTrue);
      expect(s.all, isTrue);
    });

    test('a read notification carries none', () {
      final s = unreadSignals(read: true);
      expect(s.dot, isFalse);
      expect(s.word, isFalse);
      expect(s.fullStrengthInk, isFalse);
      expect(s.all, isFalse);
    });

    test('the word is the board\'s', () {
      expect(UnreadSignals.label, 'Unread');
    });
  });

  group('the meta line', () {
    test('unread reads as the board writes it', () {
      expect(
        notificationMeta(
            read: false, createdAt: DateTime(2026, 9, 23, 9, 12), now: _now),
        'Unread · 09:12',
      );
      expect(
        notificationMeta(
            read: false, createdAt: DateTime(2026, 9, 23, 8, 40), now: _now),
        'Unread · 08:40',
      );
    });

    test('a read one from today shows its time', () {
      expect(
        notificationMeta(
            read: true, createdAt: DateTime(2026, 9, 23, 9, 12), now: _now),
        '09:12',
      );
    });

    test('a read one from this week shows its weekday', () {
      // Sunday 2026-09-20 is three days before Wednesday the 23rd.
      expect(
        notificationMeta(
            read: true, createdAt: DateTime(2026, 9, 20, 10, 0), now: _now),
        'Sunday',
      );
      expect(
        notificationMeta(
            read: true, createdAt: DateTime(2026, 9, 19, 10, 0), now: _now),
        'Saturday',
      );
    });

    test('an older one shows a date rather than a weekday', () {
      // "Monday" for something five weeks old tells the client nothing.
      expect(
        notificationMeta(
            read: true, createdAt: DateTime(2026, 8, 17, 10, 0), now: _now),
        '17/8',
      );
    });

    test('an unread one always carries the word, whatever its age', () {
      expect(
        notificationMeta(
            read: false, createdAt: DateTime(2026, 8, 17, 7, 5), now: _now),
        'Unread · 07:05',
      );
    });
  });

  group('the empty state', () {
    // The shipped copy says the list is empty twice and never says what would
    // appear in it.
    test('names what lands there', () {
      expect(emptyNotificationsTitle, 'Nothing new');
      expect(emptyNotificationsBody,
          'Coach replies, plan changes and check-in reminders land here.');
      expect(emptyNotificationsBody, contains('Coach replies'));
      expect(emptyNotificationsBody, contains('check-in reminders'));
    });

    test('does not say it twice', () {
      expect(emptyNotificationsTitle, isNot('All caught up!'));
      expect(emptyNotificationsBody, isNot(contains('No more notifications')));
    });
  });

  test('the control is the board\'s', () {
    expect(markAllReadLabel, 'Mark all read');
  });
}
