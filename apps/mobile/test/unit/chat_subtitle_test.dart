import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/messaging/presentation/chat_screen.dart';

/// F-28 · the chat header claimed presence it never had.
///
/// ── THE DEFECT ─────────────────────────────────────────────────────────────
/// The subtitle was the **constant** `"Online now"`, beside a green presence
/// dot. Nothing in this repository tracks presence — no `is_online`, no
/// `last_seen`, no realtime channel for it — so **every conversation claimed
/// the other person was online, always**.
///
/// A client could message their coach at midnight believing they were there,
/// and a coach could believe the same of a client. It is a fabricated fact
/// about a third party, presented with a status indicator that exists
/// specifically to be trusted.
///
/// FIT-026's header reads "Nadia Rahman / **Your coach**" — the relationship,
/// which is real data on the conversation the caller already carries.
void main() {
  test('F-28 a coach is described by the relationship, not by presence', () {
    expect(chatSubtitle('coach'), 'Your coach');
  });

  test('F-28 a client is too', () {
    expect(chatSubtitle('client'), 'Your client');
  });

  test('F-28 an unknown role says NOTHING rather than guessing', () {
    // An empty line says nothing, and nothing is what the screen knows. The
    // defect being replaced was a screen that said something anyway.
    for (final r in <String?>[null, '', '   ', 'admin', 'vendor', 'unknown']) {
      expect(chatSubtitle(r), isNull, reason: 'role=$r');
    }
  });

  test('F-28 the role is matched case- and whitespace-insensitively', () {
    // PostgREST and the profile table have both been seen to vary.
    expect(chatSubtitle(' Coach '), 'Your coach');
    expect(chatSubtitle('CLIENT'), 'Your client');
  });

  test('F-28 no presence language survives anywhere in the subtitle', () {
    for (final r in <String?>['coach', 'client', null, 'admin']) {
      final s = chatSubtitle(r) ?? '';
      for (final word in ['Online', 'online', 'Active', 'Last seen']) {
        expect(s, isNot(contains(word)), reason: '$r produced "$s"');
      }
    }
  });

  test('F-28 the screen no longer renders a presence claim', () {
    // The rule above is tested; this is the WIRING. `ChatScreen` reads Supabase
    // in `_init`, so the header cannot be mounted in a widget test — without
    // this, restoring the constant is a mutation that survives.
    //
    // Comments are stripped: this file's siblings quote the defect, and a
    // guard that trips on its own explanation is the mistake already recorded
    // against the FIT coverage metric and the MSG-003 guard.
    final code = File('lib/features/messaging/presentation/chat_screen.dart')
        .readAsStringSync()
        .split('\n')
        .map((l) {
          final i = l.indexOf('//');
          return i == -1 ? l : l.substring(0, i);
        })
        .join('\n');

    expect(code.contains('Online now'), isFalse,
        reason: 'the hardcoded presence claim is back');
    expect(code, contains('chatSubtitle('),
        reason: 'the header must describe the relationship, not presence');
  });

  test('FIT-026 the header and composer carry the board\'s own labels', () {
    // Every one of these is an `aria-label` read verbatim off the board's
    // Conversation frame.
    final code = File('lib/features/messaging/presentation/chat_screen.dart')
        .readAsStringSync();
    for (final label in ["'Back'", "'Book a call'", "'Attach'", "'Message'", "'Send'"]) {
      expect(code, contains('label: $label'), reason: label);
    }
  });
}
