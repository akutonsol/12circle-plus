import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static guards over the presentation layer, in the shape the rest of this
/// suite already uses: they read committed source and assert a property of it.
///
/// These are DRIFT guards, not conformance guards. The distinction matters and
/// is stated here so a later reader does not mistake one for the other.
///
/// `docs/MOBILE_QA_SWEEP_2026-09-22.md` §4 measured the presentation layer
/// against the contract at `lib/core/helix/helix_semantics.dart:5-7`
/// ("Components consume ONLY these — never raw hex") and found it honoured
/// nowhere: 0 of 158 presentation files read `context.helix`, against 3,009
/// non-semantic colour references and 20 files declaring their own private
/// palette. Closing that gap is a design decision with an owner, not a QA
/// repair, and nothing here attempts it.
///
/// What these guards do instead is hold the line where it currently sits, so
/// the gap cannot quietly widen while that decision is outstanding. A guard
/// that fails today would have to be either weakened or allowlisted into
/// meaninglessness; a guard that pins today's count does real work.
void main() {
  final presentationFiles = Directory('lib/features')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => f.path.contains('/presentation/'))
      .toList();

  group('A-G1 a declared tooltip must actually reach the widget tree', () {
    /// The defect this pins was real and shipped: `_IconBtn` in
    /// `train_hub_screen.dart` declared `final String tooltip` as a REQUIRED
    /// parameter and its build returned a bare GestureDetector, so the string
    /// reached neither a Tooltip nor the semantics tree. Two call sites passed
    /// 'History' and 'Exercise Library' believing they labelled the control.
    /// They did not, and a screen reader announced nothing.
    ///
    /// A required parameter that is never read is unambiguously a defect
    /// rather than a design choice, which is why this one was repaired and the
    /// broader labelling question was not.
    test('no widget class declares a tooltip field it never reads', () {
      final offenders = <String>[];

      for (final file in presentationFiles) {
        final whole = file.readAsStringSync();
        // Per CLASS, not per file (QA exhaustion Run 2): with a file-level
        // check, an unused tooltip field hid behind ANY other widget in the
        // same file that consumed one (mutation-proven in train_hub_screen).
        final starts = RegExp(r'^class\s+\w+', multiLine: true)
            .allMatches(whole)
            .map((m) => m.start)
            .toList();
        for (var c = 0; c < starts.length; c++) {
          final source = whole.substring(
              starts[c], c + 1 < starts.length ? starts[c + 1] : whole.length);
          if (!RegExp(r'final\s+String\??\s+tooltip\s*;').hasMatch(source)) {
            continue;
          }
          // Declared. It must then be CONSUMED — as a Tooltip message, or passed
          // into another widget's tooltip/semantics slot.
          //
          // `required this.tooltip` in the constructor is NOT consumption, and
          // an earlier draft of this guard counted it as such. The mutation test
          // that reverts _IconBtn to its bare-GestureDetector form caught the
          // false negative: the specific assertion below failed while this scan
          // stayed green. Constructor initialisers are therefore stripped before
          // the check.
          final body = source.replaceAll(RegExp(r'this\.tooltip'), '');
          final consumed = RegExp(
            r'message\s*:\s*tooltip|tooltip\s*:\s*tooltip|'
            r'semanticLabel\s*:\s*tooltip|Tooltip\s*\(\s*message',
          ).hasMatch(body);
          if (!consumed) {
            offenders.add(
                '${file.path} :: ${RegExp(r'class\s+(\w+)').firstMatch(source)!.group(1)}');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'These files declare a `tooltip` field and never use it. The value '
            'is accepted and discarded, so the control is unlabelled and the '
            'caller is misled:\n  ${offenders.join('\n  ')}',
      );
    });

    test('_IconBtn specifically carries its tooltip into the tree', () {
      final source = File(
        'lib/features/workout/presentation/train_hub_screen.dart',
      ).readAsStringSync();

      expect(
        source,
        contains(RegExp(r'Tooltip\(\s*message:\s*tooltip', dotAll: true)),
        reason: '_IconBtn must pass its required `tooltip` to a Tooltip, which '
            'also supplies the semantics label. A bare GestureDetector '
            'silently drops it.',
      );
    });
  });

  group('A-G2 no auth screen may show a user a raw error object', () {
    /// Confirmed at runtime on Android (emulator-5554, API 35): signing in with
    /// a wrong password put this on screen, in a SnackBar, for the user:
    ///
    ///   AuthApiException(message: Invalid login credentials, statusCode: 400,
    ///   code: invalid_credentials)
    ///
    /// That is `AuthException.toString()`. All four auth screens did the same
    /// thing — the entire unauthenticated surface. The repair reads the
    /// provider's own `message` field via `authErrorText` and sends the raw
    /// object to `reportError` instead.
    ///
    /// This guard is deliberately scoped to `features/auth/presentation`. The
    /// same shape exists elsewhere in the tree and is NOT repaired here; that
    /// is recorded in docs/MOBILE_QA_SWEEP_2026-09-22.md §23, not silently
    /// pinned by a guard that would have to be weakened to pass.
    final authFiles = Directory('lib/features/auth/presentation')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    test('no auth screen stringifies a caught error into UI text', () {
      final offenders = <String>[];

      // `Text(e.toString())`, `_showError(e.toString())`,
      // `_snack(error.toString())`, `Text('$e')` — the shapes actually found.
      final raw = RegExp(
        r"\b(?:e|err|error)\!?\.toString\(\)|"
        r"Text\(\s*'\$\{?(?:e|err|error)\}?'\s*\)",
      );

      for (final file in authFiles) {
        for (final line in file.readAsLinesSync()) {
          final code = line.split('//').first;
          if (raw.hasMatch(code)) {
            offenders.add('${file.path}: ${line.trim()}');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'An auth screen puts a caught error object into user-facing text. '
            'Use `authErrorText(e)` for the user and `reportError(...)` for the '
            'operator:\n  ${offenders.join('\n  ')}',
      );
    });

    test('authErrorText exists and reads the provider message field', () {
      final src = File('lib/core/errors/auth_error_text.dart');
      expect(src.existsSync(), isTrue,
          reason: 'lib/core/errors/auth_error_text.dart is the seam the auth '
              'screens depend on.');
      final text = src.readAsStringSync();
      expect(text, contains('is AuthException'));
      expect(text, contains('error.message'),
          reason: 'It must return the provider-supplied human-readable '
              'message, not a string this repository invented.');
    });
  });

  group('A-G4 no screen may present invented data as the user\'s own', () {
    /// `chat_screen.dart` displayed four hardcoded messages as the member's
    /// real coach conversation whenever the thread was empty or could not be
    /// created — including one attributed to the member themselves ("A bit sore
    /// but in a good way!..."). The screen already had the correct empty state;
    /// the fabricated fallback was the only thing hiding it.
    ///
    /// This guard is narrow on purpose. It pins the specific fabrication that
    /// shipped, rather than trying to define "fake data" in general — a broad
    /// rule would have to be weakened the first time a legitimate placeholder
    /// appeared, and a guard that gets weakened protects nothing.
    test('no presentation file calls getSampleMessages()', () {
      final offenders = <String>[];
      for (final file in presentationFiles) {
        for (final (i, line) in file.readAsLinesSync().indexed) {
          final code = line.split('//').first; // comments may name it
          if (code.contains('getSampleMessages')) {
            offenders.add('${file.path}:${i + 1}');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'A screen is substituting invented messages for real data:\n  '
            '${offenders.join('\n  ')}',
      );
    });

    test('the chat screen distinguishes failure from emptiness', () {
      final src = File(
        'lib/features/messaging/presentation/chat_screen.dart',
      ).readAsStringSync();

      expect(src, contains('_loadFailed'),
          reason: 'A thread that could not be reached is not an empty thread. '
              'Collapsing the two is the error-to-empty defect recorded as '
              'F-15 in docs/QA_EVIDENCE.md.');
      expect(src, contains("Start the conversation!"),
          reason: 'The genuine empty state must remain reachable.');
    });
  });

  group('A-G5 a failed load must not be rendered as a real figure', () {
    /// `train_hub_screen.dart` rendered `error: (_, __) => '0'` for STREAK,
    /// THIS WEEK and TOTAL. A member whose stats failed to load was told their
    /// streak was zero — a specific, wrong, and discouraging claim about their
    /// own training, produced by the app failing to ask.
    ///
    /// The same widget's DONE RATE tile already used `'—'` for that case, so
    /// the repair reused the file's own placeholder rather than inventing copy.
    ///
    /// Deliberately narrow: this guards the numeric-stat shape only. The wider
    /// error→empty collapse across eight screens (F-15) needs product copy that
    /// the design package does not supply, and is an owner decision — a guard
    /// that tried to cover it would have to be weakened to pass.
    test('no AsyncValue error branch returns a bare numeral', () {
      final offenders = <String>[];
      // `error: (_, __) => '0'` / `=> '0%'` / `=> 0` — a figure invented from a
      // failure. Whitespace-tolerant.
      final fabricated = RegExp(
        r"""error\s*:\s*\([^)]*\)\s*=>\s*'?-?\d+%?'?\s*[,)]""",
      );
      for (final file in presentationFiles) {
        for (final (i, line) in file.readAsLinesSync().indexed) {
          final code = line.split('//').first;
          if (fabricated.hasMatch(code)) offenders.add('${file.path}:${i + 1}');
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'A failed request is being displayed as a real measurement. '
            "Use the screen's own no-figure placeholder instead:\n  "
            '${offenders.join('\n  ')}',
      );
    });

    test('train_hub keeps its four stat tiles on the placeholder', () {
      final src = File(
        'lib/features/workout/presentation/train_hub_screen.dart',
      ).readAsStringSync();
      expect(
        RegExp(r"error: \(_, __\) => '—'").allMatches(src).length,
        4,
        reason: 'STREAK, THIS WEEK, TOTAL and DONE RATE must all show "—" when '
            'their load fails.',
      );
    });
  });

  group('A-G6 the train hub keeps "no plan" distinct from "could not load"', () {
    /// FIT-014 (coach-guided content) and FIT-015 ("the empty state that
    /// matters most") are two states of one route, /train. The hub implemented
    /// neither: it never read `assignedWorkoutsProvider`, so a member with a
    /// plan was not shown it and a member without one saw a hub of zeros with
    /// no explanation.
    ///
    /// The property pinned here is the one QA_CLOSURE_STANDARD §4 singles out:
    /// "`[]` from a failed read and `[]` from 'this member has none' are the
    /// same value at review time and different values in production."
    /// `.valueOrNull ?? []` erases that difference; `.when` preserves it.
    final src = File(
      'lib/features/workout/presentation/train_hub_screen.dart',
    ).readAsStringSync();

    test('the plan surface reads the assigned-plan provider at all', () {
      expect(src, contains('assignedWorkoutsProvider'),
          reason: 'The hub cannot render FIT-014 or FIT-015 without it.');
    });

    test('it branches on .when, not on a collapsed valueOrNull', () {
      final plan = src.substring(src.indexOf('class _PlanSurface'));
      expect(plan, contains('assigned.when('),
          reason: 'loading / error / data must stay three outcomes.');
      expect(plan, contains('loading:'));
      expect(plan, contains('error:'));
      expect(plan, isNot(contains('valueOrNull ?? []')),
          reason: 'That collapses a failed read into "no plan" — the exact '
              'error-to-empty defect recorded as F-15.');
    });

    test('a failed load and an empty plan render different widgets', () {
      expect(src, contains('_PlanUnavailable'));
      expect(src, contains('_NoPlanYet'));
      final plan = src.substring(src.indexOf('class _PlanSurface'));
      // Assert the PROPERTY, not the spelling: the error arm must route to the
      // unavailable widget and must not route to the no-plan one. An earlier
      // draft of this guard pinned `=> const _PlanUnavailable` and broke the
      // moment the widget legitimately gained a retry callback — a guard that
      // fails on a correct change is noise, not protection.
      final errorArm = RegExp(r'error:\s*\([^)]*\)\s*=>\s*(?:const\s+)?(\w+)')
          .firstMatch(plan)
          ?.group(1);
      expect(errorArm, '_PlanUnavailable',
          reason: 'A plan that could not be loaded is not an absent plan.');
      expect(errorArm, isNot('_NoPlanYet'));
    });
  });

  group('A-G7 the top-bar icon controls are named and reachable', () {
    /// These are icon-only: a compass, a speech bubble, a bell. Without an
    /// accessible name the tree reports them unlabelled and a screen reader
    /// announces nothing at all — the same defect measured on the password
    /// toggle. They were also 38x38, below the 44dp floor the design's `tap`
    /// component sets.
    ///
    /// FIT-001 supplies all three names, so none was invented.
    final src = File('lib/core/widgets/app_top_nav.dart').readAsStringSync();

    test('every top-bar icon button declares a label', () {
      final buttons = RegExp(r'_NavIconButton\((.*?)\)\s*,', dotAll: true)
          .allMatches(src)
          .map((m) => m.group(1)!)
          .toList();
      expect(buttons.length, greaterThanOrEqualTo(3),
          reason: 'FIT-001 places Directory, Messages and Notifications here.');
      for (final b in buttons) {
        expect(b, contains('label:'),
            reason: 'An icon-only control without a name is unusable by a '
                'screen reader:\n$b');
      }
    });

    test('Directory is present — FIT-001 moves it to the top bar', () {
      expect(src, contains("label: 'Directory'"));
      expect(src, contains("context.go('/directory')"),
          reason: '/directory is the sole entry to /events; relocating rather '
              'than deleting it is what makes the five-tab nav possible.');
    });

    test('the hit area clears the 44dp floor', () {
      expect(src, contains('minWidth: 44, minHeight: 44'),
          reason: 'The chip may stay 38px, but the TARGET must be 44.');
    });
  });

  group('A-G3 the app ships under its product name, on both platforms', () {
    /// Found at runtime: the first thing Android showed a new user was
    /// "Allow circle_fitness to send you notifications?" — the Flutter project
    /// directory name, in a system dialog. On Android `android:label` is also
    /// the launcher name, the app-drawer name and the Settings entry.
    ///
    /// The platforms had drifted apart too: iOS declared "Circle Fitness"
    /// while Android declared "circle_fitness", and neither was the product's
    /// name. Owner decision 2026-09-22: **12Circle Fitness**, both platforms.
    const expected = '12Circle Fitness';

    test('android:label is the product name', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      final m =
          RegExp(r'android:label="([^"]*)"').firstMatch(manifest);
      expect(m, isNotNull, reason: '<application> must declare android:label.');
      expect(
        m!.group(1),
        expected,
        reason: 'android:label is the launcher, Settings and permission-dialog '
            'name. It must never be the project directory name.',
      );
    });

    test('iOS CFBundleDisplayName matches, so the platforms cannot drift', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      final m = RegExp(
        r'<key>CFBundleDisplayName</key>\s*<string>([^<]*)</string>',
      ).firstMatch(plist);
      expect(m, isNotNull);
      expect(
        m!.group(1),
        expected,
        reason: 'iOS shipped "Circle Fitness" while Android shipped '
            '"circle_fitness". One product, one name.',
      );
    });
  });

  group('H-D1 the private-palette population must not grow', () {
    /// Three palettes ship concurrently — the Helix brand tier, a legacy
    /// `AppColors`, and a per-screen private palette in each file below. That
    /// is the measured state, and resolving it is D-2's owner decision.
    ///
    /// This guard does not judge the 20. It fails only on the 21st, so the
    /// decision can be taken deliberately rather than overtaken by drift.
    ///
    /// If a file is legitimately removed from this list — because it adopted
    /// the semantic tokens — delete its entry. The count is a ceiling, not a
    /// quota, and the test says so by asserting a subset rather than equality.
    const known = <String>{
      'insights_screen.dart',
      'settings_screen.dart',
      'home_screen.dart',
      'progress_screen.dart',
      'notifications_screen.dart',
      'events_screen.dart',
      'activity_screen.dart',
      'auth_design.dart',
      'dashboard_screen.dart',
      'directory_screen.dart',
      'profile_screen.dart',
      'checkin_screen.dart',
      'exercise_database_screen.dart',
      'exercise_detail_screen.dart',
      'create_exercise_screen.dart',
      'workout_list_screen.dart',
      'workout_history_screen.dart',
      'exercise_library_screen.dart',
      'workout_detail_screen.dart',

      // NOT an addition — a relocation. `train_hub_screen.dart` used to
      // declare this palette privately; extracting `WeekRowTile` would have
      // meant copying it into a second file, so the declaration moved to
      // `train_palette.dart` and the screen aliases it (`typedef _C =
      // TrainColors`). One declaration, two consumers, population unchanged.
      // The test below holds the screen to that.
      'train_palette.dart',

      // Found the moment the regex above was repaired: it was never detected
      // by the broken one, so it is pre-existing drift rather than a new
      // arrival. Listed rather than quietly deleted, and rather than migrated
      // — rewriting another feature's screen is D-2's decision, not a QA
      // repair.
      'ai_coach_screen.dart',
    };

    test('no NEW file declares a private colour palette class', () {
      // A private palette is a private class whose body is (almost) entirely
      // colour constants — the `class _C {}` / `class _S {}` / `class
      // AuthColors {}` shape the sweep found.
      // ── THIS REGEX WAS REPAIRED, AND THE REPAIR IS THE FINDING ──────────
      // The original required `static const Color <name>` or a member whose
      // name began with `c`. **None of the listed palettes are written that
      // way.** They are `static const bg = Color(0xFF0E0E0F)` — no type
      // annotation — so the guard detected only **5 of the 20 files it
      // names**, and had been passing because it could not see the other 15,
      // not because nothing had grown.
      //
      // A guard that cannot observe what it asserts is the defect class this
      // programme has recorded twice already (F-25's two live assertions, one
      // of them green forever). Repairing it immediately surfaced one file
      // that had drifted in undetected — see `known` below.
      final palette = RegExp(
        r'class\s+(_?[A-Z]\w*)\s*\{[^}]*static\s+const\s+(?:Color\s+\w+|\w+)\s*=\s*Color\(0x',
        dotAll: true,
      );

      // ── ONE SANCTIONED EXCEPTION, AND IT IS NOT "KNOWN DEBT" ─────────────
      // `admin_tokens.dart` is the Admin Tier-3 token layer: the very thing this
      // guard's invariant wants presentation files to read FROM. It is not added
      // to `known`, because `known` means "debt that may only shrink", and this
      // file must not shrink — it must stay byte-identical to the approved design
      // authority.
      //
      // The exemption is CONDITIONAL, so nobody can hand-write a palette and name
      // it admin_tokens.dart to escape the rule: the file must carry the generated
      // header AND name the design commit it was derived from, and CI separately
      // re-derives it with `gen-admin-tokens.mjs --check`. If either marker is
      // missing, the exemption does not apply and the file is reported.
      bool isGeneratedTokenLayer(String name, String source) =>
          name == 'admin_tokens.dart' &&
          source.contains('GENERATED FILE — DO NOT EDIT BY HAND') &&
          source.contains('admin.tokens.css') &&
          source.contains('931218b');

      final found = <String>{};
      for (final file in presentationFiles) {
        final source = file.readAsStringSync();
        if (!palette.hasMatch(source)) continue;
        if (!source.contains(RegExp(r'Color\(0x[0-9a-fA-F]{8}\)'))) continue;
        final name = file.path.split('/').last;
        if (isGeneratedTokenLayer(name, source)) continue;
        found.add(name);
      }

      final added = found.difference(known);
      expect(
        added,
        isEmpty,
        reason:
            'New private colour palette(s) introduced. The presentation layer '
            'already carries ${known.length} of these plus a legacy AppColors, '
            'against a semantic contract that says components consume only '
            'semantic tokens (see docs/MOBILE_QA_SWEEP_2026-09-22.md §4). '
            'Adding another widens a gap that is already an open owner '
            'decision:\n  ${added.join('\n  ')}',
      );
    });

    test('the detector still sees every palette it is supposed to be counting',
        () {
      // `added = found - known` is empty both when nothing drifted in and when
      // the detector has gone blind. Those are opposite facts and the
      // assertion above cannot tell them apart — which is how the original
      // regex passed for as long as it did while seeing 5 of 20.
      //
      // So `known` is a FLOOR for detection as well as a ceiling for
      // additions: every file listed must still be found. Narrow the regex and
      // this fails immediately.
      final palette = RegExp(
        r'class\s+(_?[A-Z]\w*)\s*\{[^}]*static\s+const\s+(?:Color\s+\w+|\w+)\s*=\s*Color\(0x',
        dotAll: true,
      );
      // ── ONE SANCTIONED EXCEPTION, AND IT IS NOT "KNOWN DEBT" ─────────────
      // `admin_tokens.dart` is the Admin Tier-3 token layer: the very thing this
      // guard's invariant wants presentation files to read FROM. It is not added
      // to `known`, because `known` means "debt that may only shrink", and this
      // file must not shrink — it must stay byte-identical to the approved design
      // authority.
      //
      // The exemption is CONDITIONAL, so nobody can hand-write a palette and name
      // it admin_tokens.dart to escape the rule: the file must carry the generated
      // header AND name the design commit it was derived from, and CI separately
      // re-derives it with `gen-admin-tokens.mjs --check`. If either marker is
      // missing, the exemption does not apply and the file is reported.
      bool isGeneratedTokenLayer(String name, String source) =>
          name == 'admin_tokens.dart' &&
          source.contains('GENERATED FILE — DO NOT EDIT BY HAND') &&
          source.contains('admin.tokens.css') &&
          source.contains('931218b');

      final found = <String>{};
      for (final file in presentationFiles) {
        final source = file.readAsStringSync();
        if (!palette.hasMatch(source)) continue;
        if (!source.contains(RegExp(r'Color\(0x[0-9a-fA-F]{8}\)'))) continue;
        final name = file.path.split('/').last;
        if (isGeneratedTokenLayer(name, source)) continue;
        found.add(name);
      }

      expect(
        known.difference(found),
        isEmpty,
        reason: 'the detector no longer sees palette(s) it is meant to count, '
            'so an absent result proves nothing about drift',
      );
    });

    // ── H-D2 · THE OTHER HALF OF THE POPULATION ────────────────────────
    // H-D1 counts palette *classes* — `class _C { static const bg = … }`.
    // That is not how most of this codebase declares a palette, and it is not
    // how anything this programme added declares one: `exercise_brief_sheet`,
    // `pill_tab`, `nutrition_load_failed`, `intake_complete_page`,
    // `checkin_detail_screen` and `needs_you_today` all use **top-level**
    // `const _ink = Color(0xFF…)`.
    //
    // Measured 2026-09-23: **21** files declare a palette class, **77**
    // declare top-level colour consts. So "the population is 21" was never
    // true of the thing D-2 is about, and the shape this programme kept
    // reaching for was the one nothing counted.
    //
    // Listing 77 files would be a large mechanical change against an open
    // owner decision, so this is a bare count with a detector floor: it may
    // fall, it may not rise.
    test('H-D2 the top-level colour-const population must not grow', () {
      final topLevel = RegExp(r'^const\s+_?\w+\s*=\s*Color\(0x',
          multiLine: true);
      final found = <String>[];
      for (final file in presentationFiles) {
        if (topLevel.hasMatch(file.readAsStringSync())) {
          found.add(file.path.split('/').last);
        }
      }

      // Detector floor — an absent result must not read as "nothing drifted".
      expect(found, isNotEmpty,
          reason: 'the scanner found no top-level palette at all, which is '
              'false of this codebase — the detector is broken');
      for (final path in const [
        'coach_dashboard_screen.dart',
        'active_workout_screen.dart',
        'chat_screen.dart',
      ]) {
        expect(found, contains(path),
            reason: '$path is a recorded site; the detector no longer sees it');
      }

      const baseline = 77;
      found.sort();
      printOnFailure(found.join('\n  '));
      expect(found.length, lessThanOrEqualTo(baseline),
          reason: 'another presentation file declares its own colours as '
              'top-level consts. This is the same gap H-D1 names — components '
              'consuming raw hex instead of semantic tokens (D-2) — in the '
              'shape H-D1 does not count. Found ${found.length} '
              '(baseline $baseline).');
    });

    test('train_hub_screen.dart did not keep a copy of the palette it moved',
        () {
      // Without this, `train_palette.dart` replacing `train_hub_screen.dart`
      // in the list above would be indistinguishable from a 21st palette
      // arriving while the screen kept its own — the population would have
      // grown and the ceiling would still read 20.
      final source = File(
              'lib/features/workout/presentation/train_hub_screen.dart')
          .readAsStringSync();
      expect(source, contains('typedef _C = TrainColors;'));
      expect(
        RegExp(r'class\s+_C\s*\{').hasMatch(source),
        isFalse,
        reason: 'the screen must consume the shared palette, not re-declare it',
      );
    });
  });
}
