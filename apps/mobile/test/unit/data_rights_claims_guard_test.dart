import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// RIGHTS-G1 — the app must not promise a data-subject control it does not have.
///
/// ── WHAT WAS FOUND ─────────────────────────────────────────────────────────
/// Three shipped screens describe how a user exercises access, portability and
/// deletion. **Two of the three are accurate.** `privacy_policy_screen.dart`
/// and `help_center_screen.dart` both say plainly:
///
/// > *"Deleting your account from inside the app is not available yet."*
///
/// Two individual statements are not:
///
///   1. `terms_of_service_screen.dart` §9 — *"You may delete your account at
///      any time from Profile → Settings → Account."*
///   2. `privacy_policy_screen.dart` §5 Access — *"You may request a full
///      export of your data at any time from Profile → Settings → Account."*
///
/// **Profile → Settings → Account contains exactly three rows** — Profile,
/// Subscription, Connected Apps. There is no deletion control and no export
/// control; the app contains **zero** export controls anywhere.
///
/// ── WHY A BASELINE AND NOT A FAILURE ───────────────────────────────────────
/// The remediation is either to build the controls or to correct user-facing
/// legal copy. **Neither is a QA decision** — that is an owner call, so this
/// pins the current state rather than asserting the fixed one. The count may
/// fall; it may not rise. When a control is built or a sentence corrected,
/// lower the baseline in the same change.
void main() {
  const settings = 'lib/features/settings/presentation/settings_screen.dart';
  const terms = 'lib/features/settings/presentation/terms_of_service_screen.dart';
  const privacy = 'lib/features/settings/presentation/privacy_policy_screen.dart';

  String read(String p) => File(p).readAsStringSync();

  test('RIGHTS-G1 the guard is reading the real screens', () {
    // An absent result must not read as "no false claims" — the H-D1 lesson.
    expect(read(terms), contains('Termination'));
    expect(read(privacy), contains('Your Rights'));
    expect(read(settings), contains("_SectionLabel(label: 'Account')"));
  });

  test('RIGHTS-G1 no in-app export control exists — the premise still holds', () {
    // If one is ever built, the claims below stop being false and the
    // baseline must drop.
    var exportControls = 0;
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.contains('privacy_policy'))) {
      final src = f.readAsStringSync();
      // Dart named arguments are `title: '...'` — a COLON, not a paren. The
      // first version of this matched `title(` and therefore matched nothing
      // ever, so the count was 0 regardless of the codebase. Mutation RG3
      // caught it.
      if (RegExp(r"""(title|label)\s*:\s*(const\s+)?'[^']*Export[^']*'""")
              .hasMatch(src) ||
          RegExp(r"""Text\(\s*(const\s+)?'[^']*Export (My )?Data[^']*'""")
              .hasMatch(src)) {
        exportControls++;
      }
    }
    expect(exportControls, 0,
        reason: 'an export control now exists — update the privacy policy '
            'claim and lower this guard in the same change');
  });

  test('RIGHTS-G1 claims naming an in-app path do not increase', () {
    // The two known-inaccurate sentences, matched on the path they name.
    const baseline = 2;
    final offenders = <String>[];

    // Matched on the PATH, not the phrasing. A regex over wordings ("export
    // of your data") missed a promise worded differently ("export your data")
    // — mutation RG1 walked through it twice. The load-bearing element is the
    // destination: any sentence pointing a user at this path is promising a
    // control that is not there.
    const path_ = 'Profile → Settings → Account';
    for (final file in [terms, privacy]) {
      final src = read(file);
      expect(src, isNotEmpty);
      var from = 0;
      while (true) {
        final i = src.indexOf(path_, from);
        if (i < 0) break;
        offenders.add('$file:${'\n'.allMatches(src.substring(0, i)).length + 1}');
        from = i + path_.length;
      }
    }

    expect(
      offenders.length,
      lessThanOrEqualTo(baseline),
      reason: 'A screen now promises a data-subject control at '
          '`Profile → Settings → Account`, which holds only Profile, '
          'Subscription and Connected Apps. Build the control or correct the '
          'sentence — do not add another promise.\n  '
          '${offenders.join('\n  ')}',
    );
  });

  test('RIGHTS-G1 the accurate disclaimers are still present', () {
    // Two screens say in-app deletion is unavailable. If those sentences are
    // removed while the Terms claim stays, the app would be uniformly wrong
    // instead of merely inconsistent.
    expect(read(privacy),
        contains('Deleting your account from inside the app is not available yet'));
    expect(read('lib/features/settings/presentation/help_center_screen.dart'),
        contains('Deleting your account from inside the app is not available yet'));
  });
}
