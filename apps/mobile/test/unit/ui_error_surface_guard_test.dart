// EC-G6 … EC-G8 — the presentation half of the error contract (Workstream N).
//
// Workstream B's ratchet (`error_contract_guard_test.dart` EC-G5) counts
// `catch`-to-empty-value sites in the SERVICE and PROVIDER layers. It cannot
// see the presentation layer, because Riverpod's swallow is not a `catch`: it
// is `error: (_, __) => const SizedBox.shrink()` inside `AsyncValue.when`, or
// `.valueOrNull`, which collapses an error into `null` with no syntax the
// EC-G5 regex matches.
//
// That blind spot is load-bearing. Phase 2 made `activeSessionProvider`
// propagate, and its source comment states the intent verbatim:
//
//     "A failed lookup returned as `null` is indistinguishable from 'there is
//      nothing to resume', and hiding the Resume affordance from a client who
//      is mid-workout is the exact failure the restoration work exists to
//      prevent. Surfaces here become an error state with a retry."
//
// Both surfaces that read it do the opposite. EC-G1 passes anyway, because it
// only asserts that `workout_provider.dart` contains no `catch`. WRK-07 is
// therefore fixed at the provider and still live at the screen.
//
// These guards assert only what is TRUE of the tree today. The two ratchets are
// SHRINKING allowlists in the shape Workstream B established: closing a finding
// is a one-line edit here, and a NEW silent error branch fails immediately.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ── Locating the tree ────────────────────────────────────────────────────────

Directory _mobileRoot() {
  var dir = Directory.current;
  while (!File('${dir.path}/pubspec.yaml').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('Could not locate the Flutter package root');
    }
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

String _relative(File f) => f.path.split('/apps/mobile/').last;

/// Source with `//` line comments removed, so a guard asserting the absence of
/// a construct is not defeated by prose describing it.
String _withoutLineComments(String source) => source
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i < 0 ? l : l.substring(0, i);
    })
    .join('\n');

/// A widget expression that renders nothing at all.
final _silentWidget = RegExp(
    r'const\s+SizedBox(\.shrink)?\(\)|SizedBox(\.shrink)?\(\)|const\s+Container\(\)|Container\(\)');

/// `error: (…) =>` handlers whose body renders nothing, i.e. a failure that the
/// client is never told about. Handlers spanning more than two lines are not
/// matched — deliberately: this is a ratchet, not an inventory, and a
/// multi-line handler is nearly always a real error card.
List<({String file, int line, String text})> _silentErrorBranches() {
  final hits = <({String file, int line, String text})>[];
  for (final f in _dartFilesUnder('lib')) {
    final lines = _withoutLineComments(f.readAsStringSync()).split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (!RegExp(r'error:\s*\(').hasMatch(lines[i])) continue;
      final window = (i + 1 < lines.length) ? '${lines[i]} ${lines[i + 1]}' : lines[i];
      final upToArrow = window.indexOf('=>');
      if (upToArrow < 0) continue;
      final body = window.substring(upToArrow + 2);
      // Only the first expression after the arrow counts.
      final firstExpr = body.split(RegExp(r',\s*(data|loading):')).first;
      if (_silentWidget.hasMatch(firstExpr)) {
        hits.add((file: _relative(f), line: i + 1, text: lines[i].trim()));
      }
    }
  }
  return hits;
}

/// `.valueOrNull` reads — an AsyncValue error becomes `null`, which every
/// caller then renders as the domain's empty state.
List<({String file, int line})> _valueOrNullReads() {
  final hits = <({String file, int line})>[];
  for (final f in _dartFilesUnder('lib')) {
    final lines = _withoutLineComments(f.readAsStringSync()).split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].contains('valueOrNull')) hits.add((file: _relative(f), line: i + 1));
    }
  }
  return hits;
}

void main() {
  // ── EC-G6 · the Resume surfaces, named ────────────────────────────────────
  //
  // Not a ratchet. These two are the specific, reproduced instance of WRK-07
  // surviving its own fix, so they are pinned by name with the finding attached.
  group('EC-G6 the Resume affordance still hides itself on a failed lookup', () {
    late final String provider = File(
            '${_mobileRoot().path}/lib/features/workout/domain/workout_provider.dart')
        .readAsStringSync();
    late final String trainHub = File(
            '${_mobileRoot().path}/lib/features/workout/presentation/train_hub_screen.dart')
        .readAsStringSync();
    late final String banner = File(
            '${_mobileRoot().path}/lib/features/workout/presentation/resume_workout_banner.dart')
        .readAsStringSync();

    test('the provider still propagates — the Phase 2 half of the fix holds', () {
      expect(provider, contains('final activeSessionProvider'));
      expect(provider, contains('Errors propagate.'));
      expect(RegExp(r'\bcatch\s*[({]').hasMatch(_withoutLineComments(provider)),
          isFalse);
    });

    test('DEFECT: Train hub renders the failure as "nothing to resume"', () {
      final body = _withoutLineComments(trainHub);
      expect(body, contains('activeSession.when('));
      // The error arm and the "no session" arm produce the identical widget, so
      // a client mid-workout whose lookup fails is shown the same screen as a
      // client with no workout in progress.
      expect(
          RegExp(r'activeSession\.when\([\s\S]{0,200}?error:\s*\(_,\s*__\)\s*=>\s*const SizedBox\.shrink\(\)')
              .hasMatch(body),
          isTrue,
          reason: 'if this now fails because the arm renders an error state '
              'with a retry, delete this test — the finding is closed');
    });

    test('DEFECT: the shared Resume banner collapses the error with '
        '.valueOrNull', () {
      final body = _withoutLineComments(banner);
      expect(body, contains('ref.watch(activeSessionProvider).valueOrNull'));
      expect(body, contains('if (session == null) return const SizedBox.shrink()'),
          reason: 'null-from-error and null-from-no-session take the same '
              'branch, so the provider comment\'s promise — "surfaces here '
              'become an error state with a retry" — is unfulfilled on every '
              'surface that mounts this banner');
    });

    test('the one surface that DOES honour the contract keeps honouring it', () {
      // workout_list_screen is the reference implementation: an error card that
      // names the failure and offers `ref.invalidate` as the retry. It is what
      // the other two should look like.
      final list = File(
              '${_mobileRoot().path}/lib/features/workout/presentation/workout_list_screen.dart')
          .readAsStringSync();
      expect(list, contains('_AssignedErrorCard'));
      expect(list, contains('Your program could not be loaded'));
      expect(list, contains('onRetry: () => ref.invalidate(assignedWorkoutsProvider)'));
      expect(list, contains('Try again'));
    });

    test('active_workout_screen keeps its restoration error state', () {
      // The restoration provider is the pattern the master reconciliation
      // singled out as correct — loading / null / error kept distinct.
      final screen = File(
              '${_mobileRoot().path}/lib/features/workout/presentation/active_workout_screen.dart')
          .readAsStringSync();
      expect(screen, contains('ref.watch(activeWorkoutRestorationProvider)'));
      expect(screen,
          contains('onRetry: () => ref.invalidate(activeWorkoutRestorationProvider)'));
    });
  });

  // ── EC-G7 · the silent-error-branch ratchet ───────────────────────────────
  group('EC-G7 silent error branches do not increase', () {
    // Measured 2026-08-24 across apps/mobile/lib by this file's own scanner.
    // It may fall. It may not rise.
    const baseline = 16;

    test('the inventory is at or below the recorded baseline', () {
      final hits = _silentErrorBranches();
      printOnFailure(hits.map((h) => '  ${h.file}:${h.line}  ${h.text}').join('\n'));
      expect(hits.length, lessThanOrEqualTo(baseline),
          reason: 'a new `error: (…) => SizedBox` branch was added. This is '
              'RC-C in the presentation layer: the failure and the empty state '
              'render identically, so the client is told "you have none" when '
              'the truth is "we could not find out". Render an error with a '
              'retry — workout_list_screen._AssignedErrorCard is the pattern.');
    });

    test('the workout surfaces carrying the finding are still the recorded ones',
        () {
      // Named so that fixing one is visible here rather than absorbed by the
      // count, and so a NEW workout surface with a silent error arm is caught
      // even if another was fixed in the same change.
      const recorded = {
        'lib/features/workout/presentation/train_hub_screen.dart',
        'lib/features/workout/presentation/coach_client_workout_screen.dart',
      };
      final workoutHits = _silentErrorBranches()
          .where((h) => h.file.startsWith('lib/features/workout/'))
          .map((h) => h.file)
          .toSet();
      expect(workoutHits.difference(recorded), isEmpty,
          reason: 'a workout surface newly swallows a load failure');
      expect(recorded.difference(workoutHits), isEmpty,
          reason: 'a recorded surface no longer swallows — delete it from '
              '`recorded` so the guard tightens');
    });
  });

  // ── EC-G8 · the .valueOrNull ratchet ──────────────────────────────────────
  group('EC-G8 error-to-null reads do not increase', () {
    // Measured 2026-08-24 across apps/mobile/lib. `.valueOrNull` is legitimate
    // where the provider genuinely cannot fail (a synchronous seed, a local
    // notifier) and is RC-C wherever the provider does I/O. The count is a
    // ratchet precisely because the two are indistinguishable at a call site —
    // which is the argument for a typed error state, not a bigger allowlist.
    const baseline = 134;

    test('the inventory is at or below the recorded baseline', () {
      final hits = _valueOrNullReads();
      printOnFailure(hits.map((h) => '  ${h.file}:${h.line}').join('\n'));
      expect(hits.length, lessThanOrEqualTo(baseline),
          reason: 'a new `.valueOrNull` read was added. On a provider that does '
              'I/O this converts "could not load" into the domain\'s empty '
              'value at the read site, below any error arm the widget declares. '
              'Use `.when(error: …)` and state the failure.');
    });

    // ── DETECTOR FLOOR ─────────────────────────────────────────────────
    // `hits.length <= baseline` is satisfied both when nothing was added and
    // when `_valueOrNullReads()` stopped seeing anything. Those are opposite
    // facts. H-D1 passed for weeks on exactly that ambiguity — its detector
    // saw 5 of the 20 files it named — so every ratchet in this suite now has
    // to prove it can still see.
    //
    // The companion test below uses its own inline scan, so it cannot catch
    // the shared detector going blind. This can.
    test('EC-G8 the detector still finds the reads it is counting', () {
      final hits = _valueOrNullReads();
      expect(hits, isNotEmpty,
          reason: 'the scanner found nothing at all — an absent result here '
              'proves nothing about drift');

      final byFile = <String, int>{};
      for (final h in hits) {
        byFile[h.file] = (byFile[h.file] ?? 0) + 1;
      }
      // Files measured as carrying the heaviest concentration. If a fix lands
      // in one, delete it here and lower the baseline in the same change —
      // the same discipline SEC-G1/G2 use.
      for (final path in const [
        'lib/features/home/presentation/home_screen.dart',
        'lib/features/dashboard/presentation/coach_dashboard_screen.dart',
        'lib/features/nutrition/presentation/meals_dashboard_screen.dart',
      ]) {
        expect(byFile[path], isNotNull,
            reason: '$path is a recorded `.valueOrNull` site. The detector no '
                'longer sees it, so the count above means nothing.');
      }
    });

    test('no NEW workout provider read collapses an error to null', () {
      // The workout domain is the one where the failure mode is reproduced and
      // costed, so it gets a named list rather than a bare count.
      const recorded = {
        'lib/features/workout/presentation/resume_workout_banner.dart',
      };
      final workoutSessionReads = <String>{};
      for (final f in _dartFilesUnder('lib/features/workout')) {
        final lines = _withoutLineComments(f.readAsStringSync()).split('\n');
        for (final l in lines) {
          if (l.contains('activeSessionProvider') && l.contains('valueOrNull')) {
            workoutSessionReads.add(_relative(f));
          }
        }
      }
      expect(workoutSessionReads.difference(recorded), isEmpty,
          reason: 'another surface now hides a failed active-session lookup');
      expect(recorded.difference(workoutSessionReads), isEmpty,
          reason: 'the banner no longer collapses the error — delete it from '
              '`recorded`');
    });
  });
}
