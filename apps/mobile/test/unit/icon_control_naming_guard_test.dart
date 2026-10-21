import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A-G8 — the unnamed icon-only control population must not grow.
///
/// ── THE DEFECT ─────────────────────────────────────────────────────────────
/// A tappable whose entire content is an `Icon` — a back arrow, a close cross,
/// a pencil, a bell — reports to the accessibility tree with **no name**. A
/// screen reader announces nothing at all. This was measured on-device twice:
/// the password toggle (19.8 × 20.2 dp, unlabelled) and the three top-bar
/// controls (38 × 38, unlabelled). Both are now fixed with the design's own
/// wording.
///
/// A repository-wide scan found **56 more across 36 files**.
///
/// ── WHY A RATCHET AND NOT A FIX ────────────────────────────────────────────
/// Naming a control is product copy. The authoritative package supplies the
/// vocabulary for the controls it draws — "Back", "More", "Directory",
/// "Messages", "Notifications", "History", "Exercise library", "Show password"
/// — and those have been applied. It does not supply names for every icon in
/// screens it does not draw, and inventing 56 strings would be exactly the
/// fabrication the brief forbids. Recorded as F-22 / OD-8 instead.
///
/// ── WHICH ONES COULD BE NAMED WITHOUT INVENTING ANYTHING ───────────────────
/// The package declares short control labels, and three of them cover a large
/// share of this population: **"Back" (138 declarations), "Close" (4) and
/// "Refresh" (8)**. A back arrow named "Back" and a close cross named "Close"
/// use the design's own words, so those are not product copy and were named:
/// `/progress` ×2, `/directory`, `/daily-checkin`, `/nutrition`,
/// `/chat`, `/messages` ×2, plus the intake flow's three.
///
/// What was deliberately NOT named, although it would have moved the number:
///
///   * `coach_checkin_review_screen.dart` — a cross that REMOVES a
///     recommendation. "Close" would be wrong, and the package declares only
///     "Remove <thing>", never a bare "Remove".
///   * `exercise_database_screen.dart` — a cross that CLEARS a search field.
///     Same reason.
///   * `coach_notes_sheet.dart` — a cross wired to `onDelete`. The package
///     declares no delete label at all.
///
/// Naming those three "Close" would have been faster, wrong, and invisible in
/// a count.
///
/// So this guard holds the line where it sits. It fails on the next one, which
/// is the only thing that can be asserted honestly today.
///
/// ── KNOWN FALSE POSITIVES, LEFT IN ON PURPOSE ──────────────────────────────
/// The scan reads 420 characters FORWARD from each tappable, so a `Semantics`
/// wrapper that sits OUTSIDE the `GestureDetector` is invisible to it. FIT-002
/// named `set_tracker_row.dart`'s completion check exactly that way — the
/// control now announces "Log set" and is asserted to, in
/// `test/widget/set_tracker_row_test.dart` — and this scan still counts it.
///
/// The window is not widened backwards to make the number fall. A backward
/// window would also swallow an unrelated `Semantics` sitting above a genuinely
/// unnamed control, and a ratchet that under-counts is worse than one that
/// over-counts: the first hides a regression, the second only overstates the
/// work left. The baseline is held at the number this scan produces.
///
/// What is NOT acceptable is leaving the discrepancy unquantified. The sites
/// verified named-but-counted are listed and asserted below, so the real figure
/// is auditable rather than a caveat in prose. The clearest case is
/// `auth_design.dart`'s password toggle: **this file already asserts it is
/// named** — it was measured on-device at 19.8 × 20.2 dp and fixed — and the
/// scan counts it anyway.
///
/// ── WHY IT DOES NOT COPY EC-G5'S MISTAKE ───────────────────────────────────
/// `QA_CLOSURE_STANDARD` §4 records that EC-G5 "counts `catch` blocks" while
/// the defect it targets has no `catch` in it, so ~150 sites are invisible to
/// it. This guard matches on the *shape that actually reports unlabelled* — a
/// tappable whose subtree has an Icon and no Text, tooltip or Semantics —
/// rather than on a keyword that happens to appear nearby.
void main() {
  /// The population as measured on 2026-09-23. Lower this number when sites are
  /// fixed; never raise it. A rise means a new unreachable control shipped.
  ///
  ///   56 — after FIT-001 named the three top-bar controls
  ///   55 — after FIT-002 named the Workout Zone's close control "End session"
  ///        and extracted it to `ZoneAction`. Note that FIT-002 also ADDED a
  ///        control ("Pause session"); the count fell by one rather than
  ///        staying level because the new one is named, which is the whole
  ///        point of the ratchet.
  ///   53 — after F-9 replaced the intake flow's three unlabelled back controls
  ///        (40/36/36 dp, no name) with one named `IntakeBackButton`. Two of
  ///        the three were visible to this scan.
  ///   47 — after nine more were named from the package's OWN vocabulary. See
  ///        the note below on why those nine and not the other forty-four.
  ///   46 — after FIT-003's "Log a meal" and "Scan a meal".
  ///
  /// **This number OVERSTATES the defect, and by a known amount.** See the
  /// verified-false-positive test below.
  const baseline = 46;

  List<({String file, int count})> scan() {
    final files = <File>[
      ...Directory('lib/features')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart') && f.path.contains('/presentation/')),
      ...Directory('lib/core/widgets')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')),
    ];

    final tappable = RegExp(r'(GestureDetector|InkWell|InkResponse)\(');
    final out = <({String file, int count})>[];

    for (final f in files) {
      final src = f.readAsStringSync();
      var n = 0;
      for (final m in tappable.allMatches(src)) {
        final end = (m.start + 420).clamp(0, src.length);
        final w = src.substring(m.start, end);
        if (!w.contains('onTap')) continue;
        final hasIcon = RegExp(r'\bIcon\(|Icons\.').hasMatch(w);
        final hasText = RegExp(r'\bText\(|child: Text|label:').hasMatch(w);
        final hasName = RegExp(r'Semantics\(|tooltip:|semanticLabel').hasMatch(w);
        if (hasIcon && !hasText && !hasName) n++;
      }
      if (n > 0) out.add((file: f.path, count: n));
    }
    return out;
  }

  test('A-G8 unnamed icon-only controls are at or below the recorded baseline', () {
    final found = scan();
    final total = found.fold<int>(0, (a, b) => a + b.count);

    final worst = (found.toList()..sort((a, b) => b.count.compareTo(a.count)))
        .take(8)
        .map((e) => '  ${e.count.toString().padLeft(3)}  ${e.file}')
        .join('\n');

    expect(
      total,
      lessThanOrEqualTo(baseline),
      reason:
          'A new icon-only control shipped with no accessible name — a screen '
          'reader announces nothing for it.\n'
          'Found $total across ${found.length} files (baseline $baseline).\n'
          'Heaviest files:\n$worst\n\n'
          'Name it with the authoritative design\'s wording if the package '
          'draws the screen. If it does not, the name is product copy: record '
          'it under OD-8 rather than inventing one.',
    );
  });

  // ── DETECTOR FLOOR ────────────────────────────────────────────────────
  // `total <= baseline` is satisfied both when nothing was added and when
  // `scan()` stopped seeing anything. Those are opposite facts, and the
  // assertion above cannot tell them apart — H-D1 passed for weeks on exactly
  // that ambiguity, its detector seeing 5 of the 20 files it named.
  //
  // The test below asserts that NAMED controls keep their names; it reads
  // source strings directly, so it would stay green while `scan()` went
  // blind. This is the part that proves the scanner still works.
  test('A-G8 the scanner still finds the controls it is counting', () {
    final found = scan();
    expect(found, isNotEmpty,
        reason: 'the scanner found nothing at all — an absent result here '
            'proves nothing about drift');

    final byFile = {for (final e in found) e.file: e.count};
    // Measured concentrations. When one is fixed, delete it here and lower
    // the baseline in the same change — the discipline SEC-G1/G2 already use.
    for (final path in const [
      'lib/features/exercise_database/presentation/exercise_content_center_screen.dart',
      'lib/features/nutrition/presentation/meals_dashboard_screen.dart',
      'lib/features/workout/presentation/active_workout_screen.dart',
    ]) {
      expect(byFile[path], isNotNull,
          reason: '$path is a recorded site for this shape. The scanner no '
              'longer sees it, so the count above means nothing.');
    }

    // And the detector must still discriminate: a NAMED icon control must not
    // be counted. `NamedIconButton` is the shared fix, and it wraps its
    // gesture in a `Semantics`.
    expect(byFile['lib/core/widgets/named_icon_button.dart'], isNull,
        reason: 'the scanner counts a control that IS named — it would '
            'over-report and the baseline would be meaningless');
  });

  test('A-G8 the controls already fixed stay fixed', () {
    // The nine named from the package's own vocabulary. If one loses its name
    // the count alone would not say which.
    const named = <String, String>{
      'lib/features/progress/presentation/progress_screen.dart': "label: 'Close'",
      'lib/features/dashboard/presentation/directory_screen.dart': "label: 'Close'",
      'lib/features/nutrition/presentation/nutrition_screen.dart': "label: 'Close'",
      'lib/features/checkins/presentation/daily_checkin_screen.dart': "label: 'Back'",
      'lib/features/messaging/presentation/chat_screen.dart': "label: 'Back'",
      'lib/features/messaging/presentation/messaging_screen.dart': "label: 'Refresh'",
    };
    named.forEach((path, needle) {
      expect(File(path).readAsStringSync(), contains(needle),
          reason: '$path lost the accessible name it was given from the '
              "design's own vocabulary");
    });

    // And the three that were left unnamed ON PURPOSE stay that way rather
    // than acquiring a plausible-sounding wrong one.
    final review = File(
            'lib/features/checkins/presentation/coach_checkin_review_screen.dart')
        .readAsStringSync();
    expect(review.contains("label: 'Close'"), isFalse,
        reason: 'that cross removes a recommendation; "Close" would be wrong. '
            'It stays unnamed under OD-8 until the owner supplies a word.');

    // F-9's three intake back controls, replaced by one named widget.
    final intake = File('lib/features/onboarding/presentation/intake_flow_screen.dart')
        .readAsStringSync();
    expect(intake.contains('IntakeBackButton'), isTrue);
    expect(RegExp(r'Icons\.arrow_back(_ios_new)?|Icons\.chevron_left')
        .allMatches(intake).isNotEmpty, isTrue,
        reason: 'the icons still ship — it is the naming that changed');
    expect(File('lib/features/onboarding/presentation/widgets/intake_back_button.dart')
        .readAsStringSync(), contains("label: 'Back'"));

    // FIT-002's two, extracted so they could be asserted at all.
    final zone = File('lib/features/workout/presentation/widgets/zone_action.dart');
    expect(zone.existsSync(), isTrue);
    final screen = File('lib/features/workout/presentation/active_workout_screen.dart')
        .readAsStringSync();
    for (final label in ["label: 'End session'", "'Pause session'"]) {
      expect(screen, contains(label),
          reason: 'FIT-002 names this control; it was an unlabelled 36 dp '
              'cross before.');
    }

    // These three were measured unlabelled on-device and named from FIT-001.
    final nav = File('lib/core/widgets/app_top_nav.dart').readAsStringSync();
    for (final label in ['Directory', 'Messages', 'Notifications']) {
      expect(nav, contains("label: '$label'"),
          reason: '$label was named from FIT-001 after being measured '
              'unlabelled on emulator-5554.');
    }
    // And the password toggle, measured at 19.8 x 20.2 dp with no name.
    final auth = File('lib/features/auth/presentation/widgets/auth_design.dart')
        .readAsStringSync();
    expect(auth, contains("'Show password'"));
    expect(auth, contains("'Hide password'"));
  });

  test('A-G8 the scan\'s verified false positives, quantified', () {
    // Each of these carries a `Semantics` wrapper OUTSIDE its tappable, which
    // the forward-only scan cannot see. They were read and confirmed named.
    // Listing them keeps the real figure auditable instead of leaving the
    // over-count as a sentence in a doc comment.
    const namedButCounted = <String, String>{
      'lib/features/auth/presentation/widgets/auth_design.dart':
          "label: _obscure ? 'Show password' : 'Hide password'",
      'lib/features/workout/presentation/workout_detail_screen.dart':
          "label: 'Back'",
      'lib/features/nutrition/presentation/nutrition_screen.dart':
          "label: 'Close'",
      'lib/features/dashboard/presentation/directory_screen.dart':
          "label: 'Close'",
      'lib/features/nutrition/presentation/meals_dashboard_screen.dart':
          "label: 'Log a meal'",
      'lib/features/ai_nutrition/presentation/ai_nutrition_screen.dart':
          "label: 'Scan a meal'",
    };

    namedButCounted.forEach((path, needle) {
      expect(File(path).readAsStringSync(), contains(needle),
          reason: '$path is listed as a verified false positive of this scan. '
              'If the name is gone, it is a real finding again — remove it '
              'from this list rather than from the count.');
    });

    final raw = scan().fold<int>(0, (a, b) => a + b.count);
    final adjusted = raw - namedButCounted.length;
    printOnFailure('raw=$raw  verified false positives=${namedButCounted.length}  '
        'adjusted=$adjusted');
    expect(adjusted, lessThan(raw));
    expect(adjusted, greaterThanOrEqualTo(0));
  });
}
