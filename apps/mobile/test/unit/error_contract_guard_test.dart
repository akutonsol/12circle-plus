// EC-* — Workstream B error-contract guards.
//
// These are STATIC guards in the same shape as `phase1_security_boundary_test`:
// they parse the committed source, so a regression fails `flutter test` without
// needing a database, credentials, or a running app.
//
// They assert only what is already true of the tree today. Nothing here changes
// product behaviour, and nothing here asserts a fix that has not been made —
// the open findings are recorded in
// `docs/QA_WORKSTREAM_B_ERROR_CONTRACT_REPORT.md`, and two of these guards are
// deliberately written as *shrinking allowlists* so that closing a finding is a
// one-line deletion here rather than a test rewrite.
//
// What is guarded:
//   EC-G1  the Phase 2 propagating call sites cannot silently revert to a
//          swallow (WRK-07 / RC-C regression lock)
//   EC-G2  no NEW phantom table: every table the Flutter client reads or writes
//          has a CREATE in supabase/, except the two known-missing ones
//   EC-G3  the two in-tree reference implementations of "a zero-row PostgREST
//          write is a refusal, not a success" keep their verification
//   EC-G4  the nutrition Edge Function keeps the outcome distinctions that make
//          layer (misconfigured != unauthorized; empty AI answer != success)
//   EC-G5  a ratchet: the repo-wide count of error-to-empty-value sites does
//          not grow past the recorded Workstream B baseline

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

Directory _repoRoot() {
  var dir = _mobileRoot();
  while (!Directory('${dir.path}/supabase/migrations').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('Could not locate supabase/migrations');
    }
    dir = parent;
  }
  return dir;
}

String _read(String relativeToRepoRoot) =>
    File('${_repoRoot().path}/$relativeToRepoRoot').readAsStringSync();

Iterable<File> _filesUnder(String relativeDir, String extension) sync* {
  final dir = Directory('${_repoRoot().path}/$relativeDir');
  if (!dir.existsSync()) return;
  for (final e in dir.listSync(recursive: true)) {
    if (e is! File) continue;
    final p = e.path;
    if (p.contains('/node_modules/') || p.contains('/build/')) continue;
    if (!p.endsWith(extension)) continue;
    yield e;
  }
}

/// The source with `//` line comments removed, so a guard that asserts the
/// *absence* of a construct is not defeated by prose describing it — several of
/// these call sites carry a comment quoting the `catch (_) { return []; }` they
/// replaced.
String _withoutLineComments(String source) => source
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i < 0 ? l : l.substring(0, i);
    })
    .join('\n');

/// The first [lines] lines of the named Dart declaration, starting at its
/// signature. Deliberately crude — it only has to be good enough to prove a
/// `catch` is or is not present inside one method.
String _sliceFrom(String source, String anchor, {int lines = 40}) {
  final i = source.indexOf(anchor);
  if (i < 0) {
    throw StateError('anchor not found in source: $anchor');
  }
  return source.substring(i).split('\n').take(lines).join('\n');
}

bool _hasCatch(String dart) =>
    RegExp(r'\bcatch\s*[({]').hasMatch(_withoutLineComments(dart));

void main() {
  // ── EC-G1 · the Phase 2 propagation must not silently revert ───────────────
  //
  // RC-C's original shape was `catch (_) { return []; }` in the four workout
  // providers and in the two service reads that feed restoration. Phase 2
  // removed those. A later "make the crash go away" edit would put them back
  // and look like a bug fix, so the absence is pinned here with the reason.
  group('EC-G1 workout error propagation is locked open', () {
    late final String provider =
        _read('apps/mobile/lib/features/workout/domain/workout_provider.dart');
    late final String service =
        _read('apps/mobile/lib/features/workout/data/workout_service.dart');
    late final String coachPrograms =
        _read('apps/mobile/lib/features/coach/data/coach_program_service.dart');

    test('workout_provider.dart contains no catch at all', () {
      // Every provider in this file either propagates or has no failure mode.
      // A single `catch` here is the RC-C regression, whatever it returns.
      expect(_hasCatch(provider), isFalse,
          reason: 'workout_provider must not catch — a swallowed read makes '
              '"failed to load" indistinguishable from "you have no program" '
              '(WRK-07). Render an error state with a retry instead.');
    });

    test('assignedWorkoutsProvider still lets a decode failure through', () {
      final body = _sliceFrom(provider, 'final assignedWorkoutsProvider');
      expect(body, contains('programWorkoutToWorkout'));
      expect(body.contains('return [];') && body.contains('catch'), isFalse,
          reason: 'an empty list must mean exactly "no assigned program"');
    });

    test('generateAiWorkout raises on a non-200 generator response', () {
      final body = _sliceFrom(provider, 'Future<Workout?> generateAiWorkout');
      expect(body, contains('res.status != 200'));
      expect(body, contains('throw'),
          reason: '"the generator could not be reached" and "the generator '
              'declined" are different answers');
    });

    test('getSessionCompletedSets lets read errors propagate', () {
      final body = _sliceFrom(
          service, 'Future<Map<String, List<Map<String, dynamic>>>> '
              'getSessionCompletedSets');
      expect(_hasCatch(body), isFalse,
          reason: 'an empty map for a failed read shows recorded work as '
              'outstanding and invites the client to redo logged sets');
    });

    test('saveSetLog refuses an identity-less row rather than guessing', () {
      final body = _sliceFrom(service, 'Future<void> saveSetLog', lines: 70);
      expect(body, contains('throw ArgumentError.value'));
      expect(_hasCatch(body), isFalse,
          reason: 'a swallowed save is a lost set');
    });

    test('materializeWeek does not swallow the engine raise', () {
      final body = _sliceFrom(
          coachPrograms, 'Future<Map<String, dynamic>?> materializeWeek',
          lines: 7);
      expect(_hasCatch(body), isFalse,
          reason: 'migration 119 makes an empty selection RAISE; swallowing it '
              'here restores the silent "sessions_created: 4 with zero '
              'exercises" materialization');
    });
  });

  // ── EC-G2 · no new phantom tables ─────────────────────────────────────────
  //
  // `checkins` and `coach_tips` are referenced by the client and created by no
  // migration. Every call to them 404s (PGRST205) and every caller swallows it,
  // so the features report success-shaped failure forever. Recorded here as a
  // shrinking allowlist: closing CON-01 means deleting an entry, and a NEW
  // phantom table fails immediately instead of shipping as a dead feature.
  group('EC-G2 every table the client uses has a backing migration', () {
    // Known-missing, tracked as CON-01 (`checkins`) and its twin (`coach_tips`).
    // Remove an entry when the table is created or its caller is retired.
    const knownMissing = {'checkins', 'coach_tips'};

    test('no phantom table outside the recorded allowlist', () {
      final referenced = <String, Set<String>>{};
      for (final f in _filesUnder('apps/mobile/lib', '.dart')) {
        final src = f.readAsStringSync();
        for (final m in RegExp(r"\.from\(\s*'([a-z0-9_]+)'\s*\)").allMatches(src)) {
          // `client.storage.from('bucket')` names a storage bucket, not a
          // table, and the receiver is often on the previous line.
          final before = src
              .substring(0, m.start)
              .replaceAll(RegExp(r'\s+'), '');
          if (before.endsWith('.storage')) continue;
          referenced
              .putIfAbsent(m.group(1)!, () => <String>{})
              .add(f.path.split('/apps/mobile/lib/').last);
        }
      }

      final sql = StringBuffer();
      for (final f in _filesUnder('supabase', '.sql')) {
        sql.writeln(f.readAsStringSync().toLowerCase());
      }
      final defined = RegExp(
        r'create\s+(?:or\s+replace\s+)?(?:table|view|materialized\s+view)\s+'
        r'(?:if\s+not\s+exists\s+)?(?:public\.)?"?([a-z0-9_]+)',
      ).allMatches(sql.toString()).map((m) => m.group(1)!).toSet();

      final missing = referenced.keys
          .where((t) => !defined.contains(t))
          .toSet();

      expect(missing.difference(knownMissing), isEmpty,
          reason: 'these tables are read or written by the client and created '
              'by no migration. Every call 404s with PGRST205 and the callers '
              'swallow it, so the feature silently never works. Create the '
              'table or retire the caller — do not add it to the allowlist.');

      // Keep the allowlist honest in the other direction too: an entry that is
      // no longer missing must be deleted, or the list rots into a permanent
      // excuse.
      expect(knownMissing.difference(missing), isEmpty,
          reason: 'a known-missing table now exists — delete it from '
              'knownMissing so the guard tightens.');
    });
  });

  // ── EC-G3 · a zero-row PostgREST write is a refusal, not a success ─────────
  //
  // PostgREST answers an RLS-filtered UPDATE/DELETE with 200 and zero rows —
  // no error is raised, so `await db.update(...); return true;` reports a write
  // that never happened. Two call sites in this tree already do it correctly.
  // They are the pattern the contract generalises, so they are pinned.
  group('EC-G3 the write-verification reference implementations hold', () {
    test('setMode detects a 0-row update, rolls back, and rethrows', () {
      final src = _read(
          'apps/mobile/lib/features/coaching_mode/domain/coaching_mode_provider.dart');
      final body = _sliceFrom(src, 'Future<void> setMode', lines: 22);
      expect(body, contains(".select('id')"),
          reason: 'without .select() an RLS-dropped update looks like success');
      expect(body, contains('isEmpty'));
      expect(body, contains('throw StateError'));
      expect(body, contains('state = prev'),
          reason: 'an optimistic update must roll back when the write did not '
              'land, or the UI keeps asserting something untrue');
      expect(body, contains('rethrow'));
    });

    test('updateExercise turns a 0-row update into a stated refusal', () {
      final src = _read(
          'apps/mobile/lib/features/exercise_database/data/custom_exercise_service.dart');
      final body =
          _sliceFrom(src, 'Future<bool> updateExercise(String id', lines: 12);
      expect(body, contains(".select('id')"));
      expect(body, contains('isEmpty'));
      expect(body, contains('return false'),
          reason: 'a refused write must be reported as refused, never as true');
    });
  });

  // ── EC-G4 · the nutrition endpoint keeps the outcome distinctions ─────────
  //
  // This group used to read apps/api, whose NestJS layer was "the only place in
  // the repo that already implements the contract in full". That layer was
  // retired when PD-A17 = A resolved as A2 (V5 §46-§55) and the route became a
  // Supabase Edge Function. **The reference moved; it was not lost.** Each
  // distinction below is the same one, asserted against the implementation that
  // now serves the traffic:
  //
  //   * a misconfigured server is not a rejected credential  — 503, not 401
  //   * an empty upstream answer is not a successful answer  — 503, not ""
  //   * upstream detail is logged rather than returned       — generic body
  group('EC-G4 the nutrition endpoint keeps its failure taxonomy', () {
    test('a misconfigured server is 503, not a rejected credential', () {
      final src = _read('supabase/functions/ai-nutrition/index.ts');
      // Absent key -> 503. Absent/!invalid token -> 401. The two are distinct.
      expect(src, contains("json({ error: 'AI is not configured' }, 503)"));
      expect(src, contains("json({ error: 'Missing or invalid access token' }, 401)"));
      // The comment states the rule; keeping it is part of keeping the rule.
      expect(src, contains('must not be reported as a rejected credential'));
    });

    test('an empty AI answer is refused, not returned as success', () {
      final src = _read('supabase/functions/ai-nutrition/index.ts');
      expect(src, contains("json({ error: 'AI returned an empty response' }, 503)"),
          reason: 'returning "" as a successful reply is the RC-C shape: a '
              'failure rendered as a valid empty domain value');
      expect(src, contains("json({ error: 'AI is temporarily unavailable' }, 503)"),
          reason: 'upstream detail is logged, not returned');
      // And the detail must never travel: the upstream status is logged only.
      expect(src, contains('console.error(`Anthropic API error'));
    });

    test('validation precedes the configuration check', () {
      // The ordering a live QA probe caught (§47.3): checking the key first turns
      // every malformed body into a 503 on an unconfigured environment. Nest ran
      // guard -> ValidationPipe -> service, and that order is part of the taxonomy.
      final src = _read('supabase/functions/ai-nutrition/index.ts');
      final validateAt = src.indexOf('const invalid = validate(body)');
      final configAt = src.indexOf("if (!ANTHROPIC_API_KEY) return json");
      expect(validateAt, greaterThan(-1));
      expect(configAt, greaterThan(validateAt));
    });
  });

  // ── EC-G5 · the ratchet ───────────────────────────────────────────────────
  //
  // 234 sites convert a caught failure into a valid empty domain value or
  // discard it outright, measured 2026-08-24 across apps/mobile/lib,
  // apps/api/src, supabase/functions and apps/mobile/tool. That number is the
  // Workstream B baseline. It may fall. It may not rise: a new swallow is a new
  // instance of the root cause, and this guard is what stops the inventory
  // drifting back up between remediation phases.
  group('EC-G5 error-to-empty-value sites do not increase', () {
    // 234 → 232 (QA exhaustion Run 2, 2026-09-25): remediation removed two
    // sites, and a ratchet that is not tightened leaves exactly that much room
    // for new swallows to pass unseen — mutation-proven: a planted swallow
    // passed at 234. Re-measured with this file's own regexes.
    const baseline = 232;

    test('the swallow inventory is at or below the recorded baseline', () {
      final catchRe = RegExp(
          r'(\}\s*(on\s+[\w<>.]+\s*)?catch\s*[({]|\}\s*on\s+[\w<>.]+\s*\{|(?<![.\w])catch\s*\{)');
      final emptyReturnRe = RegExp(
          '^\\s*return\\s*(\\[\\]|null|false|0|\\{\\}|\'\'|""'
          '|<[^>]*>\\[\\]|<[^>]*>\\{\\})\\s*;');
      final closeOnlyRe = RegExp(r'^\s*\}\s*$');
      final anyReturnRe = RegExp(r'^\s*(return|throw|rethrow)');

      var count = 0;
      final targets = <(String, String)>[
        ('apps/mobile/lib', '.dart'),
        ('apps/mobile/tool', '.dart'),
        // apps/api/src was removed with the NestJS retirement (V5 §55). The
        // ratchet is allowed to FALL — it may not rise.
        ('supabase/functions', '.ts'),
      ];
      for (final (dir, ext) in targets) {
        for (final f in _filesUnder(dir, ext)) {
          if (f.path.endsWith('.spec.ts')) continue;
          final lines = f.readAsStringSync().split('\n');
          for (var i = 0; i < lines.length; i++) {
            if (!catchRe.hasMatch(lines[i])) continue;
            for (var j = i + 1; j < i + 7 && j < lines.length; j++) {
              if (emptyReturnRe.hasMatch(lines[j])) {
                count++;
                break;
              }
              if (j - i <= 2 && closeOnlyRe.hasMatch(lines[j])) {
                count++; // an empty catch body: the failure is discarded
                break;
              }
              if (anyReturnRe.hasMatch(lines[j])) break;
            }
          }
        }
      }

      expect(count, lessThanOrEqualTo(baseline),
          reason: 'a new catch-to-empty-value site was added. RC-C is that a '
              'real failure becomes a valid empty domain value, so "no data" '
              'and "could not load" become the same answer. Propagate, or — if '
              'the swallow is genuinely one of the sanctioned exceptions in '
              'docs/QA_WORKSTREAM_B_ERROR_CONTRACT_REPORT.md §5 — record why '
              'in a comment and lower this baseline elsewhere first.');
    });

    // EC-G5b (QA exhaustion Run 2). The line-scan above inspects only the
    // lines AFTER a `catch`, so the most common swallow shape — the whole body
    // on one line, `catch (_) {}` or `catch (_) { return []; }` — was counted
    // only when an unrelated `}` happened to follow: 20 of 103 such sites were
    // invisible to it. This ratchet counts the one-line shape directly (102 in
    // code; one further match lived only in a comment and is excluded).
    test('one-line swallows (catch body on the catch line) do not increase', () {
      const oneLineBaseline = 102; // measured 2026-09-25, comments stripped
      final oneLine = RegExp(
          r"catch[ \t]*\([^)\n]*\)[ \t]*\{[ \t]*(\}|return[ \t]*(\[\]|null|false|0|\{\}|''|<[^>]*>\[\])[ \t]*;[ \t]*\})");
      var count = 0;
      for (final (dir, ext) in [
        ('apps/mobile/lib', '.dart'),
        ('apps/mobile/tool', '.dart'),
        // apps/api/src removed with the NestJS retirement (V5 §55).
        ('supabase/functions', '.ts'),
      ]) {
        for (final f in _filesUnder(dir, ext)) {
          if (f.path.endsWith('.spec.ts')) continue;
          // Comments stripped: a quoted swallow in a comment is not a swallow.
          // (Truncating at `//` can also cut a line after a URL literal; a
          // catch after a URL on the same line is not a shape this tree has.)
          count += oneLine.allMatches(_withoutLineComments(f.readAsStringSync())).length;
        }
      }
      expect(count, lessThanOrEqualTo(oneLineBaseline),
          reason: 'a new one-line catch-to-empty/discard site was added');
    });
  });
}
