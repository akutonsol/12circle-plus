import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// FIT-062 · the three unread signals, and the write nobody asked for.
///
/// The board's mandate is stated with its reason: *"Unread carries a dot AND
/// the word 'Unread' AND full-strength ink — three signals, since a violet dot
/// alone fails for a colour-blind member."* The screen shipped with the dot,
/// which is the one the board names as insufficient on its own.
///
/// `notifications_screen.dart` reads a provider that reaches Supabase, so the
/// card is asserted against committed source. `test/unit/notification_groups_test.dart`
/// proves every string and rule it composes.
String _strip(String src) => src
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i < 0 ? l : l.substring(0, i);
    })
    .join('\n');

void main() {
  final screen = _strip(
      File('lib/features/notifications/presentation/notifications_screen.dart')
          .readAsStringSync());

  test('the detector is looking at the card', () {
    expect(screen, contains('_NotificationCard'),
        reason: 'the card moved — the assertions below would pass vacuously');
  });

  test('all three unread signals are wired, not one', () {
    expect(screen, contains('unreadSignals(read: n.read)'),
        reason: 'the three are computed together so one cannot ship alone');
    expect(screen, contains('signals.dot'), reason: 'the dot');
    expect(screen, contains('signals.word'), reason: 'the WORD — the signal a '
        'colour-blind member relies on, and the one that was missing');
    expect(screen, contains('signals.fullStrengthInk'), reason: 'the ink');
  });

  // The board draws `Mark all read` as a CONTROL. The screen marked everything
  // read two seconds after it opened, whether the client read anything or not
  // — which made the control pointless, destroyed the state the three signals
  // convey, and wrote on the client's behalf unasked.
  test('nothing marks the list read on open', () {
    expect(screen.contains('Future.delayed'), isFalse,
        reason: 'the 2-second auto-mark is back');
    expect(
      RegExp(r'initState\(\)[\s\S]{0,400}?markAllRead').hasMatch(screen),
      isFalse,
      reason: 'marking read is the client\'s action — the board draws a button',
    );
    // And the control itself is still there.
    expect(screen, contains('markAllReadLabel'));
  });

  test('the grouping and empty copy come from the shared rules', () {
    expect(screen, contains('groupFor(n.createdAt).label'));
    expect(screen, contains('emptyNotificationsTitle'));
    expect(screen, contains('emptyNotificationsBody'));
    // The scheme this replaces produced Yesterday / 3 days ago / Sep 17 in
    // one list.
    expect(screen.contains("'Yesterday'"), isFalse);
    expect(screen.contains('days ago'), isFalse);
  });

  // FIT-062 declares Back as a named control; it shipped as an unnamed 38 px
  // circle, two pixels under the 44 dp floor as well.
  test('the back control is named', () {
    expect(screen, contains("label: 'Back'"));
    expect(
      RegExp(r'GestureDetector\(\s*onTap: \(\) => context\.canPop\(\)')
          .hasMatch(screen),
      isFalse,
      reason: 'a bare GestureDetector around an icon reports no name — A-G8',
    );
  });

  test('the meta line is composed, not hand-built', () {
    expect(screen, contains('notificationMeta(read: n.read'));
    expect(screen.contains('_timeAgo'), isFalse,
        reason: 'the old relative-time helper is gone');
  });
}
