// UIX-2 (text half) — the app must not claim a deletion path it does not have.
//
// App Store Guideline 5.1.1(v) makes in-app account deletion mandatory for any
// app that supports account creation. 12 Circle has no such affordance: the
// Settings "Account" section holds Subscription, Connected Apps, units, heart
// rate zones and notification preferences, and nothing else.
//
// It nonetheless told users, in two places, to use one:
//   help_center_screen.dart   "Go to Profile → Settings → Account → Delete Account"
//   privacy_policy_screen.dart "You may delete your account from Profile → Settings → Account"
// and a third that the original guard's narrow phrasing missed (QAX, 2026-09-25):
//   terms_of_service_screen.dart "You may delete your account at any time from '
//                                 'Profile → Settings → Account." (split literal)
//
// The feature itself is Wave 7 and is blocked behind I-USR-01(a) — 53 of 143
// foreign keys restrict deletes, so deletion is blocked at the schema level
// before it is blocked at the UI level. This guard covers only the half that
// needed no decision: the false statement should not outlive Wave 1, and must
// not come back before the feature does.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Directory _mobileRoot() {
  var dir = Directory.current;
  while (!File('${dir.path}/pubspec.yaml').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) fail('Could not locate the Flutter package root');
    dir = parent;
  }
  return dir;
}

Iterable<File> _dartFilesUnder(String relative) sync* {
  final dir = Directory('${_mobileRoot().path}/$relative');
  if (!dir.existsSync()) return;
  for (final e in dir.listSync(recursive: true)) {
    if (e is File && e.path.endsWith('.dart')) yield e;
  }
}

void main() {
  group('UIX-2 no screen claims an in-app account-deletion path', () {
    /// Phrasings that assert a navigable route to deletion. Deliberately
    /// narrow: the app is free to *discuss* deletion — it must not give
    /// directions to a screen that is not there.
    final claims = <RegExp, String>{
      RegExp(r'Settings\s*→\s*Account\s*→\s*Delete', caseSensitive: false):
          'directs the user to a Delete Account screen',
      RegExp(r'delete your account from Profile', caseSensitive: false):
          'states deletion is reachable from Profile',
      // QAX: the Terms said "delete your account at any time from Profile →
      // Settings → Account", which the narrow phrase above never matched.
      RegExp(r'delete your account[^.]{0,40}\b(from|in|via)\s+(Profile|Settings)',
          caseSensitive: false):
          'states deletion is reachable from Profile/Settings',
      RegExp(r'(Go to|Navigate to|Tap)[^.]{0,60}Delete Account',
          caseSensitive: false):
          'gives navigation directions to a Delete Account affordance',
    };

    test('no file under lib/ gives directions to a deletion screen', () {
      final offenders = <String>[];
      for (final f in _dartFilesUnder('lib')) {
        // Join adjacent string literals ('…' '…', across lines) so a claim
        // split over two literals cannot slip past the patterns (QAX finding:
        // the Terms claim was split exactly like that).
        final src = f.readAsStringSync().replaceAll(RegExp(r"'\s*\n?\s*'"), '');
        claims.forEach((re, why) {
          if (re.hasMatch(src)) {
            offenders.add('${f.path.split('/apps/mobile/').last} — $why');
          }
        });
      }
      expect(offenders, isEmpty,
          reason: 'the app claims an in-app deletion path.\n'
              'If the feature has shipped, delete this test and close UIX-2. '
              'If it has not, the statement is false and must go:\n'
              '${offenders.join('\n')}');
    });

    test('both corrected screens still tell the user how deletion works', () {
      // The inverse failure is just as bad: silently removing the sentence
      // would leave a user with no route at all and still fail 5.1.1(v)
      // guidance about being told what to do.
      const screens = [
        'lib/features/settings/presentation/help_center_screen.dart',
        'lib/features/settings/presentation/privacy_policy_screen.dart',
        'lib/features/settings/presentation/terms_of_service_screen.dart',
      ];
      for (final relative in screens) {
        final src = File('${_mobileRoot().path}/$relative').readAsStringSync();
        expect(src.toLowerCase(), contains('delet'),
            reason: '$relative no longer mentions deletion at all');
        expect(RegExp(r'(support|privacy)@12circle\.app').hasMatch(src), isTrue,
            reason: '$relative must name the channel that actually works');
      }
    });

    test('the Settings Account section really has no delete affordance', () {
      // Pins the premise. When a Delete Account row is added, this fails and
      // whoever added it is sent here to close UIX-2 properly.
      final src = File('${_mobileRoot().path}/'
              'lib/features/settings/presentation/settings_screen.dart')
          .readAsStringSync();
      expect(src.contains('Delete Account'), isFalse,
          reason: 'Settings now has a Delete Account row — the in-app feature '
              'may have shipped. Re-check the help-centre and privacy-policy '
              'wording and close UIX-2 rather than leaving this guard.');
    });
  });
}
