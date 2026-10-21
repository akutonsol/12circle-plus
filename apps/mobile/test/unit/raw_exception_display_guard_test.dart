import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ERR-G2 — no raw exception may be interpolated into user-facing copy.
///
/// A PostgREST/Postgres error is not opaque. It carries table and column
/// names, constraint text, and on a unique violation the **conflicting
/// value**. `SEC-PHI-2` closed the two PHI screens and said so explicitly in
/// its own header:
///
/// > *"It does not claim the app never leaks an exception: five other sites
/// > still do (recorded, all on non-PHI coach screens)."*
///
/// A sweep found the real number was **38**, across 26 files, including
/// `womens_health_screen.dart` and the admin console — whose error card both
/// parsed the exception for its "not an admin" branch *and* printed the raw
/// text for every other error, to exactly the non-admin audience that branch
/// exists for.
///
/// All 38 are closed. This guard is what stops the count climbing back, and
/// it replaces a prose disclaimer with an enforced number.
///
/// ── WHAT COUNTS, AND WHAT DELIBERATELY DOES NOT ────────────────────────────
/// Only a **bare** interpolation inside a string literal counts: `$e`, `${e}`,
/// `$error`, `$err`, `$ex`. `${e.key}`, `${ex.name}` and `${e['score']}` are
/// loop and map variables that merely share a name — an early version of this
/// sweep counted them and reported 59 sites for 38 real ones.
///
/// Three uses are legitimate and are listed, not silently skipped:
///   * the observability sink, whose job is to format the exception;
///   * parsing (`'$e'.contains('42501')`) with no display;
///   * stringifying a list element that happens to be called `e`.
void main() {
  /// Bare exception interpolation that is NOT a user-facing display.
  ///
  /// Keyed by file, but each entry lists the exact CODE FRAGMENTS that are
  /// exempt — not the file. A file-granular allowlist gave every line in a
  /// listed file a blanket pass, and mutation testing caught it: planting
  /// `'Upload failed: $e'` in `progress_screen.dart` SURVIVED, because that
  /// file was listed for an unrelated storage path. Two of the five listed
  /// files are PHI-adjacent, so a blanket pass was the wrong shape.
  ///
  /// This list may shrink, never grow.
  const permitted = <String, List<String>>{
    'lib/core/observability/app_failure.dart': [
      // The error sink itself — formatting the exception is its purpose.
      r"StringBuffer('AppFailure($origin): $error')",
    ],
    'lib/features/admin/presentation/admin_dashboard_screen.dart': [
      // PARSES for the 42501 "not an admin" branch; displays nothing.
      r"'$e'.toLowerCase().contains('not authorized')",
      r"'$e'.contains('42501')",
    ],
    'lib/features/dashboard/presentation/client_detail_screen.dart': [
      // Stringifies list elements, not an exception.
      r"'$e'.trim()",
    ],
    'lib/features/onboarding/domain/intake_data.dart': [
      r"(e) => '$e'",
    ],
    // The `progress_screen.dart` exemption was REMOVED here, not forgotten.
    // Cloud (QAX-COR-07, 7e1507e) extracted the baseline-photo replace logic
    // into its own file, so the fragment no longer exists in the screen and
    // the screen is now clean. ERR-G2's stale-exemption test caught that
    // during the local↔cloud reconciliation — which is exactly what it is
    // for: an exemption that grants a pass to nothing hides the fact that a
    // file has become clean. The exemption follows the code.
    //
    // `e` is a file extension from `baselinePhotoExtensions`.
    'lib/features/progress/data/baseline_photo_replace.dart': [
      r"'$uid/$side.$e'",
    ],
    // `e` is a symptom string from a List, not an exception — the same class
    // as the intake_data entry.
    'lib/features/womens_health/presentation/womens_health_screen.dart': [
      r"(e) => '$e'",
    ],
  };

  late List<String> offenders;
  late int scanned;

  setUpAll(() {
    // Bare only: not followed by a property access, index, or more word
    // characters. `${e.key}` and `${e['x']}` are not exceptions.
    final bare = RegExp(r"""\$\{?(e|err|error|ex)\}?(?![\w.\[?])""");
    offenders = [];
    scanned = 0;

    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      scanned++;
      final exemptFragments = permitted[f.path] ?? const <String>[];

      var n = 0;
      for (final line in f.readAsStringSync().split('\n')) {
        n++;
        final code = line.contains('//') ? line.substring(0, line.indexOf('//')) : line;
        // Only THIS line's listed shapes are exempt, not the whole file.
        if (exemptFragments.any(code.contains)) continue;
        for (final m in bare.allMatches(code)) {
          // Inside a string literal? An odd number of quotes precedes it.
          final before = code.substring(0, m.start);
          final inSingle = "'".allMatches(before).length.isOdd;
          final inDouble = '"'.allMatches(before).length.isOdd;
          if (!inSingle && !inDouble) continue;
          offenders.add('${f.path}:$n\n        ${line.trim()}');
          break;
        }
      }
    }
  });

  test('ERR-G2 the sweep actually read the app', () {
    // An empty sweep must not read as "no leaks" — the H-D1 lesson.
    expect(scanned, greaterThan(200),
        reason: 'the file walk found almost nothing; every assertion below '
            'would be vacuous');
  });

  test('ERR-G2 no raw exception is shown to a user', () {
    expect(
      offenders,
      isEmpty,
      reason: 'A raw exception is being interpolated into user-facing copy '
          'again:\n  ${offenders.join('\n  ')}\n\n'
          'A PostgREST error carries table and column names, constraint text, '
          'and on a unique violation the conflicting VALUE. Say what failed '
          'in the repository\'s own words — "Could not load X." / '
          '"Failed to save. Try again." — and let the observability sink keep '
          'the detail.\n\n'
          'If this site genuinely parses rather than displays, add it to '
          '`permitted` WITH a reason.',
    );
  });

  test('ERR-G2 every exemption still exists and still applies', () {
    // A shrinking allowlist that keeps stale entries protects nothing — and a
    // fragment that no longer appears is an exemption granted to nothing,
    // which quietly widens the next one that IS matched.
    for (final entry in permitted.entries) {
      final f = File(entry.key);
      expect(f.existsSync(), isTrue,
          reason: '${entry.key} is gone; drop its exemptions in the same '
              'change');
      final src = f.readAsStringSync();
      for (final fragment in entry.value) {
        expect(src.contains(fragment), isTrue,
            reason: 'Exemption no longer present in ${entry.key}:\n'
                '    $fragment\n'
                'If the line was removed or rewritten, delete the exemption '
                'too. Leaving it here grants a pass to nothing and hides the '
                'fact that the file may now be clean.');
      }
    }
  });

  test('ERR-G2 the detector can still see a leak when there is one', () {
    // Without this, `offenders` being empty could mean the regex has rotted
    // rather than that the app is clean — the RG3 vacuous-pass lesson.
    final bare = RegExp(r"""\$\{?(e|err|error|ex)\}?(?![\w.\[?])""");
    expect(bare.hasMatch(r"Text('Could not load. $e')"), isTrue,
        reason: 'the detector no longer matches the exact shape it exists to '
            'catch');
    expect(bare.hasMatch(r"Text('${e.key} items')"), isFalse,
        reason: 'the detector matches loop variables again — it reported 59 '
            'sites for 38 real ones when it did');
  });
}
