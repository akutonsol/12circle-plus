/// FIT-062 · `/notifications`.
///
/// ── THE BOARD ──────────────────────────────────────────────────────────────
///
///     Notifications                              Mark all read
///     Today
///       Nadia replied to your check-in           Unread · 09:12
///       Your week has changed …                  Unread · 08:40
///     Earlier this week
///       Check-in due tomorrow                    Sunday
///       Hip thrust at 70 kg is a new best        Saturday
///
/// and, when it is clear:
///
///     Nothing new
///     Coach replies, plan changes and check-in reminders land here.
///
/// ── THE ACCESSIBILITY MANDATE IS THE DESIGN'S, NOT AN ADDITION ─────────────
/// > *"Unread carries **a dot** and **the word "Unread"** and **full-strength
/// > ink** — three signals, since a violet dot alone fails for a colour-blind
/// > member."*
///
/// The screen shipped with **one** of the three. That is not a nicety the
/// board mentions in passing; it states the reason, and the reason is a member
/// who cannot see the dot.
///
/// ── AND ONE DEFECT THE BOARD SETTLES BY DRAWING A BUTTON ───────────────────
/// `notifications_screen.dart` ran `Future.delayed(2s) → markAllRead()` in
/// `initState`. Everything became read two seconds after the screen appeared,
/// whether the client read anything or not. That:
///
///   * makes `Mark all read` — which the board draws as a **control** —
///     pointless, because it has already happened;
///   * destroys the state the three signals exist to convey;
///   * writes on the client's behalf without being asked.
///
/// The board draws marking-read as something the client does. So it is.
library;

/// Which dated group a notification belongs to.
enum NotificationGroup {
  today('Today'),
  earlierThisWeek('Earlier this week'),
  older('Earlier');

  const NotificationGroup(this.label);

  /// The board's heading. `Earlier` covers everything past the week — the
  /// board draws only two groups because its sample spans five days, and a
  /// notification from last month has to go somewhere that is not a lie.
  final String label;
}

/// The group a notification belongs to, by the day it arrived.
///
/// "This week" means the **last seven days**, not the calendar week: a
/// Monday-morning member would otherwise see Sunday's coach reply filed under
/// `Earlier`, which is true of the calendar and wrong about their week.
NotificationGroup groupFor(DateTime createdAt, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final d = DateTime(createdAt.year, createdAt.month, createdAt.day);
  final days = today.difference(d).inDays;
  if (days <= 0) return NotificationGroup.today;
  if (days < 7) return NotificationGroup.earlierThisWeek;
  return NotificationGroup.older;
}

/// The three signals an unread notification carries.
///
/// Returned together so a caller cannot ship one and forget the other two —
/// which is exactly what happened.
class UnreadSignals {
  /// The violet dot.
  final bool dot;

  /// The literal word, for a member who cannot distinguish the dot.
  final bool word;

  /// Full-strength ink rather than the dimmed treatment read items carry.
  final bool fullStrengthInk;

  const UnreadSignals({
    required this.dot,
    required this.word,
    required this.fullStrengthInk,
  });

  /// The board's word, used as the label itself.
  static const label = 'Unread';

  bool get all => dot && word && fullStrengthInk;
}

UnreadSignals unreadSignals({required bool read}) => UnreadSignals(
      dot: !read,
      word: !read,
      fullStrengthInk: !read,
    );

/// `Unread · 09:12`, or the day it arrived once it has been read.
///
/// The board writes both forms — unread rows carry the word and a time,
/// read rows carry a weekday. Times are 24-hour, as every time in this package
/// is.
String notificationMeta({
  required bool read,
  required DateTime createdAt,
  DateTime? now,
}) {
  final l = createdAt.toLocal();
  final time = '${l.hour.toString().padLeft(2, '0')}:'
      '${l.minute.toString().padLeft(2, '0')}';
  if (!read) return '${UnreadSignals.label} · $time';

  final group = groupFor(createdAt, now: now);
  if (group == NotificationGroup.today) return time;
  const days = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
    'Sunday',
  ];
  if (group == NotificationGroup.earlierThisWeek) return days[l.weekday - 1];
  return '${l.day}/${l.month}';
}

/// The board's own words for a clear list.
///
/// The shipped copy — "All caught up!" / "No more notifications for now." —
/// says the list is empty twice and never says what would appear in it. The
/// board's names the five categories the app actually sends.
const emptyNotificationsTitle = 'Nothing new';
const emptyNotificationsBody =
    'Coach replies, plan changes and check-in reminders land here.';

/// The board's control.
const markAllReadLabel = 'Mark all read';
