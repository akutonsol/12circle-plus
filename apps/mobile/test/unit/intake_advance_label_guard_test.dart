import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A-G9 — the intake flow advances with one word.
///
/// ── THE DEFECT ─────────────────────────────────────────────────────────────
/// `intake_flow_screen.dart` is 5,841 lines and ~24 steps. Eleven of them
/// labelled the advance control **`Continue`** and five labelled it **`Next`**
/// — the same action, the same `onContinue` callback, two different words. A
/// client walking the flow was told to `Continue`, then `Next`, then
/// `Continue` again.
///
/// FIT-008 settles it: the board's step archetype draws **`Continue`**, and it
/// is already the majority word in the file, so this is not new vocabulary.
///
/// ── WHY A GUARD AND NOT JUST A FIX ─────────────────────────────────────────
/// The file is long enough that a sixteenth step added later would pick
/// whichever word its author happened to copy, and nothing would notice. This
/// is cheap to hold.
void main() {
  final file =
      File('lib/features/onboarding/presentation/intake_flow_screen.dart');
  late String source;

  setUpAll(() {
    expect(file.existsSync(), isTrue);
    source = file.readAsStringSync();
  });

  test('the detector can see the labels it is counting', () {
    // An absent result must not read as "no drift" — the H-D1 lesson. If the
    // button helper is renamed and this finds nothing, that is a broken
    // detector, not a clean flow.
    expect(RegExp(r"label: '").allMatches(source).length, greaterThan(10),
        reason: 'no labelled controls found at all — the detector is broken');
  });

  test('every advance control says Continue, and none says Next', () {
    final next = RegExp(r"label: 'Next'").allMatches(source).length;
    expect(
      next,
      0,
      reason: 'A step labels its advance control `Next` while $next others '
          'and the FIT-008 board say `Continue`. One flow, one word.',
    );
    expect(RegExp(r"label: 'Continue'").allMatches(source).length,
        greaterThanOrEqualTo(16),
        reason: 'the advance controls have gone somewhere else — re-check '
            'before relaxing this');
  });

  test('the word is the board\'s, not one invented here', () {
    // FIT-008 declares `Continue` and `Skip this`. `Continue` is also already
    // the majority word in this file, which is why unifying on it changes no
    // client-facing vocabulary — it only stops the flow contradicting itself.
    expect(source, contains("label: 'Continue'"));
  });
}
