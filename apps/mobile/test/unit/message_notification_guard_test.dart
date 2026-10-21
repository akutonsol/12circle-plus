import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// MSG-003 — a message notifies its recipient exactly once.
///
/// ── WHY THIS IS A STATIC GUARD AND NOT A LIVE ASSERTION ────────────────────
/// "Exactly once" has two halves and they need two different sessions:
///
///   * **not twice** — no Dart-side insert alongside the DB trigger. Checkable
///     here, from the source, in the fast suite.
///   * **not zero** — the trigger actually fired. Only the RECIPIENT can see
///     their own notification: `notifications` carries
///     `recipients read own notifications … USING (recipient_id = auth.uid())`
///     (migrations 003 and 004).
///
/// `integration_test/service_logic_test.dart` used to assert the second half
/// **from the sender's session**, counting the recipient's rows. That query
/// returns 0 before and 0 after, for any sender, forever — so the assertion
/// was unsatisfiable, and the only way it could ever have gone green is if
/// `notifications` leaked rows across users. **A test whose passing condition
/// is a privacy defect is not a weaker test, it is a wrong one.** Recorded as
/// F-25; that file now asserts only what its session can observe.
///
/// This guard holds the half that can be held honestly, and pins the two
/// pieces the defect would move.
void main() {
  test('MSG-003 the Dart side does not insert a message notification', () {
    // The duplicate this was written for: `sendMessage` inserting into
    // `notifications` as well as the trigger, giving the recipient two.
    final src =
        File('lib/features/messaging/data/messaging_service.dart').readAsStringSync();
    final send = src.substring(src.indexOf('Future<bool> sendMessage('));
    final body = send.substring(0, send.indexOf('\n  Future<') == -1
        ? send.length
        : send.indexOf('\n  Future<'));

    expect(body.contains("from('notifications')"), isFalse,
        reason: 'sendMessage must leave the recipient notification to '
            'trg_notify_on_message. A Dart-side insert beside it is how the '
            'recipient ends up with two.');
  });

  test('MSG-003 the trigger that DOES notify is still installed', () {
    // The other half of "exactly once": something has to create it. If this
    // disappears the guard above is satisfied by a product that notifies
    // nobody, which is the failure mode the live test was reaching for.
    final dir = Directory('../../supabase/migrations');
    if (!dir.existsSync()) {
      fail('Could not read supabase/migrations — this guard asserted nothing.');
    }
    final sql = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sql'))
        .map((f) => f.readAsStringSync())
        .join('\n');

    expect(sql, contains('trg_notify_on_message'),
        reason: 'the function that notifies the recipient is gone');
    expect(
        RegExp(r'CREATE TRIGGER\s+notify_on_message\s+AFTER INSERT ON messages',
                caseSensitive: false)
            .hasMatch(sql),
        isTrue,
        reason: 'the function exists but nothing fires it on an insert');
  });

  test('MSG-003 the live test no longer asserts across the RLS boundary', () {
    // F-25 itself, pinned: if someone reinstates the cross-user count, this
    // fails rather than the suite going quietly red on the device and being
    // read as a product defect.
    //
    // **Comments are stripped first, and the first version of this guard did
    // not do that.** It failed on the very file it was protecting, because
    // that file's header *explains* the defect and quotes the expression. The
    // FIT coverage metric had the identical fault on the same day — counting
    // a design label because a comment quoted it. Writing down what went
    // wrong should not register as the thing going wrong.
    final live = _withoutComments(
        File('integration_test/service_logic_test.dart').readAsStringSync());
    expect(live.contains("_notifCount(coachId"), isFalse,
        reason: 'counting the RECIPIENT\'s notifications from the SENDER\'s '
            'session is unsatisfiable under `recipients read own '
            'notifications`. See F-25 in docs/QA_EVIDENCE.md — the recipient '
            'half needs the recipient\'s session, not a looser policy.');
  });

}

/// Drops `//` line comments. Enough for this guard: the expressions it looks
/// for are single-line calls, and block comments are not used in the file it
/// reads.
String _withoutComments(String src) => src
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i == -1 ? l : l.substring(0, i);
    })
    .join('\n');
