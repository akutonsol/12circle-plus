// AI-J-001 … AI-J-016 — QA Workstream J: AI / intelligence decision integrity.
//
// STATIC guards. They parse the committed SQL, the committed edge-function
// TypeScript and the committed Dart, so a regression fails `flutter test`
// before anything reaches a database and without needing QA credentials.
//
// They are the second half of a pair, the same way phase1_security_boundary_test
// pairs with supabase/tests/security. The live half is supabase/tests/ai/, which
// answers "does this actually behave that way against a real project?" — that is
// where the column-existence, guard-composition and deployment findings are
// proven. What is asserted HERE is narrower and complementary: that the
// committed source cannot express the defect again.
//
// Two kinds of test, both green today, and the difference is stated in each
// name:
//
//   [invariant]       a property the system holds and must keep holding.
//   [characterizes]   a defect this workstream found, pinned exactly as the
//                     source reads today, with its finding ID. It goes red the
//                     moment the source changes — which is the point: whoever
//                     remediates F-J-nn inverts the test in the same commit.
//                     Nothing here is skipped and nothing is marked as an
//                     expected failure; a red test nobody can act on protects
//                     nothing.
//
// Findings guarded — see docs/QA_WORKSTREAM_J_AI_DECISION_INTEGRITY_REPORT.md
//   F-J-01  migration 119 replaced a 116 authorization wrapper and dropped it
//   F-J-07  build_workout's deload rule appended an untyped literal to a text[] —
//           REMEDIATED by migration 127, with evaluate_week and predict_client
//   F-J-17  derive_parq_risk did the same in the PAR-Q classifier trigger —
//           REMEDIATED by migration 126; the guard is now an invariant
//   F-J-10  the AI generator names the engine as load authority, never calls it
//   F-J-18  ai-coach ignores the target_client_id its own client sends
//   F-J-19  the client parses a JSON risk verdict with Uri.splitQueryString
//   F-J-20  no Anthropic call checks stop_reason, so a refusal is persisted
//   F-J-21  no Anthropic call carries a timeout or an abort signal
//   F-J-22  the engine plans from unreviewed, AI-authored intelligence
//   F-J-23  the only automated substrate builder writes no injury data at all
//   F-J-24  the service-mode check compares against a possibly-empty key
//   F-J-25  model identifiers are per-file literals and are never persisted
//   F-J-16  the coaching-engine client swallows every failure into null
//   F-J-26  the nutrition coach is given no subject context of any kind
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

String _stripSqlComments(String sql) => sql
    .split('\n')
    .map((line) {
      final i = line.indexOf('--');
      return i == -1 ? line : line.substring(0, i);
    })
    .join('\n');

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

String _migration(int n) {
  final dir = Directory('${_repoRoot().path}/supabase/migrations');
  for (final f in dir.listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    if (!name.endsWith('.sql')) continue;
    if (int.tryParse(name.split('_').first) == n) {
      return _flat(_stripSqlComments(f.readAsStringSync()));
    }
  }
  throw StateError('migration $n should exist');
}

/// The body of `CREATE OR REPLACE FUNCTION public.<name>(` in a migration, up to
/// the closing `$$;`. Flattened, comments stripped.
String _fnBody(int migration, String name) {
  final sql = _migration(migration);
  final start = sql.toUpperCase().indexOf(
      'CREATE OR REPLACE FUNCTION PUBLIC.${name.toUpperCase()}(');
  if (start < 0) {
    final legacy = sql.toUpperCase().indexOf(
        'CREATE OR REPLACE FUNCTION ${name.toUpperCase()}(');
    if (legacy < 0) throw StateError('$name not declared in migration $migration');
    return _fnFrom(sql, legacy);
  }
  return _fnFrom(sql, start);
}

/// The highest-numbered migration that declares
/// `CREATE OR REPLACE FUNCTION public.<name>(`. A forward-only correction
/// redeclares a function in a NEW migration — an applied migration is never
/// edited — so a guard on the LIVE definition must read the last declaration,
/// not the first.
int _lastMigrationDeclaring(String name) {
  final dir = Directory('${_repoRoot().path}/supabase/migrations');
  final needle = 'CREATE OR REPLACE FUNCTION PUBLIC.${name.toUpperCase()}(';
  var last = -1;
  for (final f in dir.listSync().whereType<File>()) {
    final fname = f.uri.pathSegments.last;
    if (!fname.endsWith('.sql')) continue;
    final n = int.tryParse(fname.split('_').first);
    if (n == null || n <= last) continue;
    final sql = _flat(_stripSqlComments(f.readAsStringSync())).toUpperCase();
    if (sql.contains(needle)) last = n;
  }
  if (last < 0) throw StateError('$name is declared in no migration');
  return last;
}

String _fnFrom(String sql, int start) {
  final end = sql.indexOf(r'$$;', start);
  return end < 0 ? sql.substring(start) : sql.substring(start, end + 3);
}

/// A deployed edge function's source, verbatim.
String _edgeFn(String name) {
  final f = File('${_repoRoot().path}/supabase/functions/$name/index.ts');
  if (!f.existsSync()) throw StateError('supabase/functions/$name/index.ts should exist');
  return f.readAsStringSync();
}

String _lib(String relative) {
  final f = File('${_mobileRoot().path}/lib/$relative');
  if (!f.existsSync()) throw StateError('lib/$relative should exist');
  return f.readAsStringSync();
}

/// Every .dart file under lib/, for "is this actually called anywhere" checks.
Iterable<File> _libFiles() sync* {
  final root = Directory('${_mobileRoot().path}/lib');
  for (final e in root.listSync(recursive: true)) {
    if (e is File && e.path.endsWith('.dart')) yield e;
  }
}

/// Every AI edge function that talks to Anthropic.
const _anthropicFunctions = <String>[
  // Added when the NestJS nutrition route became an Edge Function (PD-A17 = A
  // resolved as A2, V5 §46-§55). It is an Anthropic caller, so every
  // characterization in this file that sweeps the set must now include it.
  'ai-nutrition',
  'ai-coach',
  'ai-coaching-engine',
  'ai-generate-workout',
  'analyze-food-image',
  'explain-decision',
  'generate-communication',
  'enrich-exercise-intelligence',
];

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // AI-J-001 — the authorization wrapper migration 119 overwrote
  // ══════════════════════════════════════════════════════════════════════════
  group('AI-J-001 subject/program-scoped engine functions keep their guard', () {
    test('[invariant] every guarded engine function 116 wrapped still checks', () {
      // 116 §4 renamed five long engine bodies to <name>_engine and kept the
      // public name as a thin authorized wrapper. Its own comment predicted the
      // failure mode: "If a future migration replaces one of these by its PUBLIC
      // name it will replace the WRAPPER and silently drop the guard."
      final m116 = _migration(116);
      for (final pair in const [
        ['predict_client', 'can_act_for'],
        ['assemble_weekly_review', 'can_act_for'],
        ['evaluate_week', 'can_act_on_program'],
        ['regenerate_program', 'can_act_on_program'],
        ['materialize_program_week', 'can_act_on_program'],
      ]) {
        expect(m116, contains('public.${pair[0]}_engine'),
            reason: '116 should have renamed ${pair[0]} to ${pair[0]}_engine');
        expect(_fnBody(116, pair[0]), contains('public.${pair[1]}('),
            reason: '116\'s ${pair[0]} wrapper should call ${pair[1]}');
      }
    });

    test('[invariant] the LAST declaration of every 116-guarded function still guards',
        () {
      // QA exhaustion Run 2: the invariant above reads 116's text only, so a
      // later migration redeclaring predict_client WITHOUT can_act_for passed
      // this group (mutation-proven) — the exact 116 -> 119 shape. The end-state
      // check below existed for materialize_program_week alone; this applies it
      // to all five.
      final dir = Directory('${_repoRoot().path}/supabase/migrations');
      for (final pair in const [
        ['predict_client', 'can_act_for'],
        ['assemble_weekly_review', 'can_act_for'],
        ['evaluate_week', 'can_act_on_program'],
        ['regenerate_program', 'can_act_on_program'],
        ['materialize_program_week', 'can_act_on_program'],
      ]) {
        var lastDeclaring = -1, lastGuarded = -1;
        for (final f in dir.listSync().whereType<File>()) {
          final name = f.uri.pathSegments.last;
          final n = int.tryParse(name.split('_').first);
          if (n == null || !name.endsWith('.sql')) continue;
          final sql = _flat(_stripSqlComments(f.readAsStringSync()));
          if (!sql.toUpperCase().contains('FUNCTION PUBLIC.${pair[0].toUpperCase()}(')) continue;
          if (n > lastDeclaring) lastDeclaring = n;
          if (sql.contains('${pair[1]}(') && n > lastGuarded) lastGuarded = n;
        }
        expect(lastDeclaring, greaterThanOrEqualTo(116), reason: pair[0]);
        expect(lastGuarded, equals(lastDeclaring),
            reason: 'the last migration to declare ${pair[0]} is $lastDeclaring and '
                'the last to guard it with ${pair[1]} is $lastGuarded');
      }
    });

    test('[characterizes F-J-01] 119 redeclared materialize_program_week without it', () {
      // Live-proven: an unrelated authenticated client reaches the engine body
      // against another coach's program (supabase/tests/ai/j04). With a real
      // week number that call DELETEs and rewrites that week's program_workouts.
      //
      // REMEDIATION: add `IF NOT public.can_act_on_program(p_program_id) THEN
      // RAISE EXCEPTION ... ERRCODE '42501'; END IF;` as the first statement of
      // 119's body (or restore the wrapper/_engine split), then invert this to
      // an invariant.
      final body = _fnBody(119, 'materialize_program_week');
      expect(body, isNot(contains('can_act_on_program')),
          reason: 'F-J-01 is fixed — invert this test and delete the finding');

      // The two properties 122 DID restore, so the fix is scoped to the guard.
      expect(_migration(122), contains('ALTER FUNCTION %s SET search_path = public, pg_temp'),
          reason: '122 re-pins the search_path 119 dropped');
    });

    test('[characterizes F-J-01] no later migration restores the guard either', () {
      // The invariant is about the end state of the chain, not one file.
      final dir = Directory('${_repoRoot().path}/supabase/migrations');
      var lastDeclaringGuard = -1;
      var lastDeclaring = -1;
      for (final f in dir.listSync().whereType<File>()) {
        final name = f.uri.pathSegments.last;
        final n = int.tryParse(name.split('_').first);
        if (n == null || !name.endsWith('.sql')) continue;
        final sql = _flat(_stripSqlComments(f.readAsStringSync()));
        if (!sql.toUpperCase().contains('FUNCTION PUBLIC.MATERIALIZE_PROGRAM_WEEK(')) continue;
        if (n > lastDeclaring) lastDeclaring = n;
        if (sql.contains('can_act_on_program') && n > lastDeclaringGuard) {
          lastDeclaringGuard = n;
        }
      }
      expect(lastDeclaring, greaterThanOrEqualTo(119));
      expect(lastDeclaringGuard, equals(lastDeclaring),
          reason: 'the last migration to declare materialize_program_week is $lastDeclaring '
              'and the last to guard it is $lastDeclaringGuard — F-J-01 requires the '
              'final declaration to retain its authorization guard');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // AI-J-002 — the untyped array append, as a CLASS, all on safety paths
  // ══════════════════════════════════════════════════════════════════════════
  group('AI-J-002 text[] rule accumulators', () {
    // `v text[] := '{}'` then `v := v || 'LABEL'` is ambiguous: Postgres
    // resolves anyarray||anyarray and then fails to read 'LABEL' as an array
    // literal (22P02). Appending a DECLARED text variable is unambiguous and
    // works — which is why the fault hides: in both functions the loop-driven
    // appends are fine and only the hand-written literals throw.
    // An append of a BARE literal: `v := v || 'LABEL'` with no ::text cast.
    // The negative lookahead is what makes this mean "untyped" — without it the
    // corrected form matches too, and the guard can never go green.
    final literalAppend =
        RegExp(r"""(\w+)\s*:=\s*\1\s*\|\|\s*'[A-Za-z_]+'(?!\s*::\s*text)""");

    test('[invariant] every rule accumulator appends typed text — the whole class', () {
      // F-J-07 (registry SEC-R3), REMEDIATED by migration 127, together with the
      // two further instances F-J-07's own remediation note required a sweep for.
      //
      // Eleven sites across three functions had the bare-literal shape:
      //   build_workout          089:55   RECOVERY_REDUCTION
      //   evaluate_week          094:52,55,60,65
      //   predict_client         095:125,127,128,129,130,131
      //
      // 116 renamed evaluate_week and predict_client to *_engine and published
      // authorization wrappers under the public names, so the LIVE definitions
      // of the defective bodies are the engines. This reads the last migration
      // declaring each — an applied migration is never edited, so a forward-only
      // correction is the last declaration.
      const accumulators = {
        'build_workout': 127,
        'evaluate_week_engine': 127,
        'predict_client_engine': 127,
        'derive_parq_risk': 126,          // F-J-17, closed earlier
      };
      accumulators.forEach((fn, expected) {
        final last = _lastMigrationDeclaring(fn);
        expect(last, greaterThanOrEqualTo(expected),
            reason: '$fn is last declared in $last; the untyped append is only '
                'corrected from migration $expected onward');
        final body = _fnBody(last, fn);
        expect(literalAppend.hasMatch(body), isFalse,
            reason: 'a bare-literal append survives in the live declaration of '
                '$fn — text[] || unknown resolves to anyarray||anyarray and '
                'throws 22P02 the moment that branch is taken');
        expect(body.toLowerCase(), contains('set search_path = public, pg_temp'),
            reason: 'CREATE OR REPLACE drops proconfig unless restated '
                '(I-MIG-03 / CRC-07); 118 and 122 pinned every function in public');
      });
    });

    test('[invariant] no migration after 126 reintroduces the bare-literal append', () {
      // Forward-looking half: the class must not come back in NEW work. The
      // historical originals (089, 094, 095, 115) are applied and immutable, so
      // they are excluded by number, not by exception — their live definitions
      // are already asserted clean above.
      //
      // SUPERSEDED DECLARATIONS ARE EXCLUDED ON THE SAME GROUND, V5 §134.3. The
      // sentence above is the rule this test actually encodes: an applied
      // migration MAY carry the pattern provided its LIVE definition is clean. The
      // number cutoff expressed that because, when this was written, every such
      // case was historical. It is not a second, stricter rule — and read as one it
      // forces a choice between two repository rules, since
      // check-migration-hygiene.sh forbids editing an applied migration in place
      // (Wave 0: in-place edits made "replay from empty" and "what production
      // actually ran" diverge) and this file's own comment above states the same:
      // "an applied migration is never edited, so a forward-only correction is the
      // last declaration."
      //
      // 161 shipped `v_changed := v_changed || 'first_name'` in
      // admin_update_user_name and EVERY call failed 22P02 — including the only
      // authorized one. 162 corrects it forward. This test caught it, and it still
      // would: detection is unchanged for any function whose LIVE declaration
      // carries the pattern, which is what the first test in this group asserts
      // function by function. Had 162 not been written, the live declaration would
      // be 161's and both tests would fail.
      //
      // A superseded offender is PRINTED rather than passed over in silence, so a
      // correction sitting in a different file stays visible.
      final dir = Directory('${_repoRoot().path}/supabase/migrations');
      final offenders = <String>[];
      final superseded = <String>[];
      for (final f in dir.listSync().whereType<File>()) {
        final name = f.uri.pathSegments.last;
        if (!name.endsWith('.sql')) continue;
        final n = int.tryParse(name.split('_').first);
        if (n == null || n <= 126) continue;
        final sql = _flat(_stripSqlComments(f.readAsStringSync()));
        if (!literalAppend.hasMatch(sql)) continue;
        // Which functions does this migration declare, and is this still the last
        // word on any of them? If a later migration redeclares every one of them,
        // nothing this file says is live.
        final declared = RegExp(
                r'CREATE\s+OR\s+REPLACE\s+FUNCTION\s+(?:public\.)?([a-z_][a-z0-9_]*)',
                caseSensitive: false)
            .allMatches(sql)
            .map((m) => m.group(1)!)
            .toSet();
        final stillLive = declared.isEmpty ||
            declared.any((fn) => _lastMigrationDeclaring(fn) <= n);
        if (stillLive) {
          offenders.add(name);
        } else {
          superseded.add('$name (live definition is later)');
        }
      }
      for (final s in superseded) {
        // ignore: avoid_print
        print('AI-J-002 note: bare-literal append survives in $s — superseded, '
            'and the live declaration is asserted clean above');
      }
      expect(offenders, isEmpty,
          reason: 'these migrations append a bare literal to an accumulator and it '
              'is still the LIVE definition: ${offenders.join(', ')} — cast it to ::text');
    });

    test('[invariant] build_workout keeps the RECOVERY_REDUCTION threshold contract', () {
      // The correction must not have moved the threshold or the volume factor.
      final body = _fnBody(_lastMigrationDeclaring('build_workout'), 'build_workout');
      expect(body, contains("v_recovery < 60 then rules := rules || 'RECOVERY_REDUCTION'::text"));
      expect(body, contains('case when v_recovery < 60 then 0.8 else 1.0 end'));
      expect(body, contains('rules := rules || rule'),
          reason: 'the rejection rules append a declared text variable and always worked');
    });

    test('[invariant] 127 corrects the ENGINES, never 116\'s authorization wrappers', () {
      // Redeclaring the PUBLIC names with the engine bodies would delete 116's
      // can_act_for / can_act_on_program wrappers — the exact F-J-01 / SEC-R1
      // regression 119 caused and 124 had to repair.
      final m127 = _migration(127);
      for (final engine in const ['evaluate_week_engine', 'predict_client_engine']) {
        expect(m127.toUpperCase(),
            contains('CREATE OR REPLACE FUNCTION PUBLIC.${engine.toUpperCase()}('));
      }
      for (final wrapper in const ['evaluate_week', 'predict_client']) {
        expect(m127.toUpperCase(),
            isNot(contains('CREATE OR REPLACE FUNCTION PUBLIC.${wrapper.toUpperCase()}(')),
            reason: '127 must not redeclare the public $wrapper — that is the wrapper');
        expect(_lastMigrationDeclaring(wrapper), equals(116),
            reason: '$wrapper\'s authorization wrapper must still be 116\'s');
      }
    });

    test('[invariant] derive_parq_risk appends its narrative flags as typed text', () {
      // F-J-17, REMEDIATED by migration 126.
      //
      // Before it: a member could not save has_injuries + injury_locations, or a
      // Pregnancy / Postpartum medical condition — apply_parq_risk() is a BEFORE
      // trigger on user_profiles, so the 22P02 throw rejected the whole write.
      //
      // This reads the LAST migration that declares the function, not 115.
      // Migration 115 is applied and must never be edited; the correction is a
      // forward-only redeclaration, so the live definition is the last one.
      final last = _lastMigrationDeclaring('derive_parq_risk');
      expect(last, greaterThanOrEqualTo(126),
          reason: 'no migration after 115 redeclares derive_parq_risk, so the '
              'untyped append is still the live definition and F-J-17 is open');

      final body = _fnBody(last, 'derive_parq_risk');
      for (final flag in const ['pregnancy', 'postpartum', 'active_injuries']) {
        expect(body, contains("v_flags || '$flag'::text"),
            reason: '$flag must append as anyarray||anyelement');
        expect(RegExp("v_flags \\|\\| '$flag'(?!::text)").hasMatch(body), isFalse,
            reason: 'an untyped $flag append survives in the live declaration — '
                "text[] || unknown resolves to anyarray||anyarray and throws 22P02");
      }
      expect(body, contains('v_flags := v_flags || v_labels[i]'),
          reason: 'the numbered PAR-Q flags append an array element and work');

      // The correction must not quietly change anything else.
      expect(body, contains("array_to_string(v_flags, ',')"),
          reason: 'risk_flags stays the comma-joined TEXT contract of migration 013');
      expect(body, contains('IMMUTABLE'));
      expect(body, contains('SET search_path = public, pg_temp'),
          reason: 'CREATE OR REPLACE drops proconfig unless it is restated '
              '(I-MIG-03 / CRC-07)');
    });

    test('[invariant] the derived risk fields stay server-owned on every write', () {
      // The classifier is the only writer of risk_score / risk_level /
      // risk_flags: apply_parq_risk() overwrites NEW.* unconditionally, on
      // INSERT and UPDATE, for every caller including service_role. A
      // client-supplied classification is therefore discarded, not trusted.
      final apply = _fnBody(115, 'apply_parq_risk');
      for (final f in const ['risk_score', 'risk_level', 'risk_flags']) {
        expect(apply, contains('NEW.$f :='),
            reason: '$f must be recomputed in the write path, not accepted');
      }
      expect(_lastMigrationDeclaring('apply_parq_risk'), equals(115),
          reason: 'the trigger body is unchanged by the F-J-17 correction');
    });

    test('[invariant] the trigger that runs the classifier is still BEFORE and server-owned', () {
      // Not a nit: the reason F-J-17 blocks a write rather than just losing a
      // flag is that the classification is computed in the write path. That
      // design is correct (Phase 0 Q-4) and must survive the fix.
      final m115 = _migration(115);
      expect(m115, contains('BEFORE INSERT OR UPDATE'));
      expect(m115, contains('EXECUTE FUNCTION public.apply_parq_risk()'));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // AI-J-003 — the deterministic-engine boundary, as the source states it
  // ══════════════════════════════════════════════════════════════════════════
  group('AI-J-003 engine authority', () {
    test('[invariant] the AI generator refuses to prescribe load', () {
      final src = _edgeFn('ai-generate-workout');
      expect(src, contains('Do NOT prescribe a load'));
      expect(src, contains('weight_kg: null'));
      // The output contract is validated rather than passed through: a model
      // that cannot produce whole numbers is a failure to report.
      expect(src, contains('Number.isInteger'));
      expect(src, contains('The generated workout was not usable'));
    });

    test('[characterizes F-J-10] …and then never asks the engine that owns it', () {
      // The prompt names the deterministic engine as the load authority. No
      // engine RPC is invoked before or after the model call, so weight_kg is
      // null for every AI-generated session, permanently — not "the engine
      // decided no load", but "nothing decided".
      //
      // REMEDIATION is a product decision (D-3 in the report): either the engine
      // prescribes load and this function calls it, or the prompt stops naming
      // an authority that is not consulted.
      final src = _edgeFn('ai-generate-workout');
      for (final rpcName in const ['generate_workout', 'build_workout', 'score_exercise', 'rank_exercises']) {
        expect(src, isNot(contains(rpcName)),
            reason: 'F-J-10 is fixed — the generator now consults $rpcName; invert this test');
      }
    });

    test('[characterizes F-J-10] an AI-generated session records no provenance', () {
      // No decision_traces row, no ai_insights row, no model identifier, no
      // input snapshot. The workout is returned straight to the client and can
      // be started. Nothing downstream can tell it was AI-authored.
      final src = _edgeFn('ai-generate-workout');
      expect(src, isNot(contains('decision_traces')),
          reason: 'F-J-10 is fixed — invert this test');
      expect(RegExp(r'\.insert\(').hasMatch(src), isFalse,
          reason: 'the generator writes nothing at all');
    });

    test('[characterizes F-J-22] the engine plans from unreviewed AI-authored intelligence', () {
      // enrich-exercise-intelligence writes contraindications and joint_stress —
      // the two columns the injury rule reads — at status 'ai_generated', which
      // 090 defines as pending human review. build_workout joins
      // exercise_intelligence with no status predicate, so a draft or an
      // unreviewed model output is planned from as though certified.
      //
      // REMEDIATION is a policy decision (D-1): which statuses are engine-
      // eligible. Then add the predicate here and to rank_exercises.
      expect(_edgeFn('enrich-exercise-intelligence'), contains("status: 'ai_generated'"));
      final body = _fnBody(89, 'build_workout');
      expect(body, contains('join exercise_intelligence ei on ei.exercise_id = e.id'));
      expect(body, isNot(contains('ei.status')),
          reason: 'F-J-22 is fixed — build_workout now filters on review status; invert this test');
    });

    test('[characterizes F-J-23] the only automated substrate builder writes no injury data', () {
      // score_exercise penalises an injury from exercise_intelligence
      // .contraindications and .joint_stress. rebuild_exercise_intelligence —
      // the sole non-AI way to populate the table — inserts neither. Until a
      // model or a human fills them, injury_compatibility is 100 for every
      // exercise and INJURY_PREVENTION can never fire.
      final body = _fnBody(87, 'rebuild_exercise_intelligence');
      expect(body, contains('insert into exercise_intelligence'));
      expect(body, isNot(contains('contraindications')),
          reason: 'F-J-23 is fixed — invert this test');
      expect(body, isNot(contains('joint_stress')),
          reason: 'F-J-23 is fixed — invert this test');
      // The consumer, for contrast.
      expect(_fnBody(87, 'score_exercise'), contains('ei.contraindications'));
      expect(_fnBody(87, 'score_exercise'), contains('ei.joint_stress'));
    });

    test('[characterizes F-J-09] the rejection gates compare possibly-NULL scores', () {
      // `em := (rec.bd->>'equipment_match')::int` is NULL whenever
      // score_exercise took an early return, and `IF NULL = 0` / `IF NULL < 40`
      // are both false, so control falls through to accepted. The safety gates
      // are null-permissive: absence of evidence reads as absence of risk.
      //
      // REMEDIATION: reject on `em IS NULL OR em = 0` / `ic IS NULL OR ic < 40`.
      final body = _fnBody(89, 'build_workout');
      expect(body, contains('if em = 0 then'));
      expect(body, contains('elsif ic < 40 then'));
      expect(body, isNot(contains('em is null')),
          reason: 'F-J-09 is fixed — invert this test');
      expect(body, isNot(contains('ic is null')),
          reason: 'F-J-09 is fixed — invert this test');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // AI-J-004 — safety inputs that exist and are never read
  // ══════════════════════════════════════════════════════════════════════════
  group('AI-J-004 safety inputs reach the decision surfaces', () {
    test('[invariant] the safety substrate is declared', () {
      expect(_migration(13), contains('food_allergies'));
      expect(_migration(13), contains('parq_answers'));
      expect(_migration(115), contains('derive_parq_risk'));
    });

    test('[characterizes F-J-05] no AI feature reads the PAR-Q classification', () {
      // risk_level / risk_flags are the server's authoritative answer to "is
      // this member cleared to train unsupervised, and are they pregnant,
      // postpartum or injured?". Nothing consults them.
      for (final name in _anthropicFunctions) {
        expect(_edgeFn(name), isNot(contains('risk_flags')),
            reason: 'F-J-05 is fixed in $name — invert this test');
      }
      // 'risk_level' does appear once, but as a key the MODEL is asked to
      // invent in ai-coach's risk_detection mode — the opposite of reading the
      // server's classification. The distinction is the finding: the product
      // asks a language model to guess a risk level it already knows.
      expect(_edgeFn('ai-coach'),
          contains('Output JSON: { "risk_level": "low/medium/high"'));
      expect(_edgeFn('ai-coach'), isNot(contains('profile.risk_level')));
      expect(_fnBody(87, 'score_exercise').contains('risk_level'), isFalse,
          reason: 'the deterministic engine has no PAR-Q dimension either');
    });

    test('[characterizes F-J-05] no nutrition surface reads the structured allergies', () {
      // user_profiles.food_allergies is captured at intake and never read. The
      // coaching engine's meal prompt says "respecting allergies … from memory",
      // i.e. from ai_memories free text, whose own extractor has no allergy kind.
      expect(_edgeFn('ai-coaching-engine'), isNot(contains('food_allergies')),
          reason: 'F-J-05 is fixed — invert this test');
      expect(_edgeFn('analyze-food-image'), isNot(contains('food_allergies')));
      expect(_edgeFn('ai-nutrition'), isNot(contains('food_allergies')));
      expect(_edgeFn('ai-coach'), contains('"kind":"like|dislike|injury|constraint|preference"'),
          reason: 'the memory extractor has no allergy kind to put one in');
    });

    test('[characterizes F-J-26] the nutrition coach is given no subject context at all', () {
      // The nutrition route is the security-correct one — the Anthropic key is
      // server-held and the caller's Supabase session is verified. But the body
      // carries only message/history/image: it never looks up who the caller is,
      // so meal plans and grocery lists are produced with no plan, no targets,
      // no goal, and no allergies.
      //
      // Repointed from apps/api to the Edge Function when the route moved
      // (V5 §46-§55). The defect is UNCHANGED by that move, which is why this
      // characterization survives it rather than being deleted.
      final svc = _edgeFn('ai-nutrition');
      expect(svc, contains('NUTRITION_SYSTEM_PROMPT'));
      for (final field in const ['user_profiles', 'client_nutrition_plans', 'sub', 'userId']) {
        expect(svc, isNot(contains(field)),
            reason: 'F-J-26 is fixed — the service now loads $field; invert this test');
      }
      // The guard that IS in place, and must stay. On the Edge side that is the
      // explicit getUser() check, backed by verify_jwt = true in config.toml.
      expect(svc, contains('userDb.auth.getUser()'));
      expect(svc, contains("json({ error: 'Missing or invalid access token' }, 401)"));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // AI-J-005 — subject identity through the caller chain
  // ══════════════════════════════════════════════════════════════════════════
  group('AI-J-005 the AI answers about the person it was asked about', () {
    test('[characterizes F-J-18] ai-coach ignores the target_client_id it is sent', () {
      // AICoachService.analyzeCheckins(clientId) and .detectRisks(clientId) post
      // target_client_id. The function never reads it: every query is
      // .eq(..., user.id). A coach asking for a client's check-in analysis or
      // risk assessment is served an analysis of THEMSELVES, labelled as the
      // client's.
      //
      // REMEDIATION: resolve the subject through can_act_for/is_active_coach_of
      // in the function, or remove the parameter and the two coach-facing calls.
      final client = _lib('features/ai_coach/data/ai_coach_service.dart');
      expect(client, contains("'target_client_id': clientId"));
      expect(_edgeFn('ai-coach'), isNot(contains('target_client_id')),
          reason: 'F-J-18 is fixed — invert this test');
      expect(_edgeFn('ai-coach'), contains('const { message, mode } = body'),
          reason: 'the destructure is where the subject is dropped');
    });

    test('[invariant] the two mis-subjected methods have no call site', () {
      // This is what keeps F-J-18 latent rather than live: nothing in the app
      // calls analyzeCheckins or detectRisks today, so no coach is currently
      // being shown their own data labelled as a client's. Wiring either into a
      // coach screen turns a latent defect into a live one, so the wiring is
      // what this test guards — fix the subject resolution first.
      for (final method in const ['analyzeCheckins', 'detectRisks']) {
        final callers = <String>[];
        for (final f in _libFiles()) {
          if (f.path.endsWith('ai_coach_service.dart')) continue;
          if (f.readAsStringSync().contains('$method(')) callers.add(f.path);
        }
        expect(callers, isEmpty,
            reason: '$method is now called from ${callers.join(', ')} — F-J-18 and F-J-19 '
                'are live from that screen. Resolve the subject in ai-coach and parse the '
                'verdict with jsonDecode before shipping it.');
      }
    });

    test('[characterizes F-J-19] the risk verdict is parsed as a URL query string', () {
      // The prompt asks for JSON. detectRisks feeds it to Uri.splitQueryString,
      // which splits on & and =, so a well-formed verdict never yields
      // risk_level / flags / recommendation.
      //
      // REMEDIATION: jsonDecode, and keep the catch that degrades to 'unknown'.
      final client = _lib('features/ai_coach/data/ai_coach_service.dart');
      expect(client, contains('Uri.splitQueryString(jsonStr)'),
          reason: 'F-J-19 is fixed — invert this test');
      expect(client, isNot(contains('jsonDecode')));
    });

    test('[invariant] the coaching engine derives its subject from the JWT by default', () {
      final src = _edgeFn('ai-coaching-engine');
      expect(src, contains('await userDb.auth.getUser()'));
      expect(src, contains("return json({ error: 'Unauthorized' }, 401)"));
    });

    test('[characterizes F-J-24] …but its service-mode check compares to a possibly-empty key', () {
      // `SUPABASE_SERVICE_ROLE_KEY ?? ''` and then
      // `authHeader === \`Bearer ${SUPABASE_SERVICE_KEY}\``. If the secret is
      // ever absent, `Authorization: Bearer ` matches and the caller names any
      // subject they like in the body. The platform injects that secret today,
      // so this is defence in depth, not a live hole — but the comparison should
      // not be the only thing standing between an unset variable and arbitrary
      // subject targeting.
      //
      // REMEDIATION: `SUPABASE_SERVICE_KEY.length > 0 && authHeader === ...`.
      final src = _edgeFn('ai-coaching-engine');
      expect(src, contains('const isService = authHeader === `Bearer \${SUPABASE_SERVICE_KEY}`'),
          reason: 'F-J-24 is fixed — invert this test');
      expect(src, contains("Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''"));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // AI-J-006 — model failure modes
  // ══════════════════════════════════════════════════════════════════════════
  group('AI-J-006 model failure is handled, not assumed away', () {
    test('[invariant] every AI function authenticates its caller', () {
      for (final name in _anthropicFunctions) {
        expect(_edgeFn(name), contains('auth.getUser()'),
            reason: '\$name must authenticate its caller');
      }
    });

    test('[characterizes F-J-28] ai-coach alone has no key guard, and echoes upstream errors', () {
      // Six of the seven refuse to run when ANTHROPIC_API_KEY is absent.
      // ai-coach instead calls Anthropic with an empty key, gets a 401, and
      // returns HTTP 500 with the upstream response body in `detail` — an
      // internal failure shape handed to the client. It also logs whether the
      // key is present on every request.
      //
      // REMEDIATION: the same `if (!ANTHROPIC_API_KEY) return json({ error:
      // 'AI not configured' }, 500)` guard the other six use, and drop `detail`.
      // Matched on the PROPERTY rather than one exact string. ai-nutrition says
      // "AI is not configured" because that wording is ported verbatim from the
      // NestJS service it replaced (§47), and the guard is what matters here, not
      // the phrasing.
      for (final name in _anthropicFunctions.where((n) => n != 'ai-coach')) {
        final src = _edgeFn(name);
        expect(src.contains("'AI not configured'") || src.contains("'AI is not configured'"),
            isTrue,
            reason: '\$name must fail closed when the key is absent');
      }
      final src = _edgeFn('ai-coach');
      expect(src, isNot(contains("'AI not configured'")),
          reason: 'F-J-28 is fixed — invert this test');
      expect(src, contains("json({ error: 'AI service error', detail: errText }, 500)"));
    });

    test('[invariant] unparseable model output is a 502, not a silent default', () {
      for (final name in const ['ai-coaching-engine', 'ai-generate-workout',
                                'analyze-food-image', 'generate-communication']) {
        final src = _edgeFn(name);
        expect(src.contains('Could not read AI result') || src.contains('Could not parse result'),
            isTrue, reason: '$name must surface a parse failure');
      }
    });

    test('[characterizes F-J-20] a refusal is not detected and is persisted as coaching', () {
      // The Messages API answers HTTP 200 with stop_reason 'refusal' and no
      // usable content. Every function here reads content[0].text with a '{}'
      // fallback, so the parse succeeds, `out` is {}, and ai-coaching-engine
      // writes an ai_insights row titled "Today's Coaching" with an empty body —
      // and stamps a confidence score on it. That is a fabricated artifact
      // produced by a declined request.
      //
      // REMEDIATION: check stop_reason before reading content; treat 'refusal'
      // and 'max_tokens' as distinct, reportable outcomes; never persist on either.
      // ai-nutrition is EXCLUDED because it already does the remediation this
      // characterization asks for, and that is worth recording rather than
      // hiding: it reads stop_reason, and on empty content it returns 503
      // "AI returned an empty response" instead of persisting anything. It is the
      // counter-example proving the defect is fixable, and the shape the other
      // six should adopt. Ported from the NestJS service (§47), which behaved the
      // same way.
      for (final name in _anthropicFunctions.where((n) => n != 'ai-nutrition')) {
        expect(_edgeFn(name), isNot(contains('stop_reason')),
            reason: 'F-J-20 is fixed in $name — invert this test');
      }
      final nutrition = _edgeFn('ai-nutrition');
      expect(nutrition, contains('stop_reason'));
      expect(nutrition, contains("json({ error: 'AI returned an empty response' }, 503)"),
          reason: 'it refuses an empty answer rather than persisting one');
      final engine = _edgeFn('ai-coaching-engine');
      expect(engine, contains("(aiData.content?.[0]?.text ?? '{}')"));
      expect(engine, contains("title: out.title ?? 'Today’s Coaching', body: out.body ?? ''"),
          reason: 'the empty-output path writes a row rather than failing');
    });

    test('[characterizes F-J-21] no Anthropic call is bounded by a timeout', () {
      // Deno's fetch has no default timeout. A slow or hung upstream holds the
      // request until the platform's own wall clock kills it, and the caller
      // sees a generic failure with no signal that it was a timeout.
      //
      // REMEDIATION: AbortSignal.timeout(n) on every call, and a distinct
      // 504-shaped response.
      for (final name in _anthropicFunctions) {
        final src = _edgeFn(name);
        expect(src.contains('AbortSignal') || src.contains('AbortController'), isFalse,
            reason: 'F-J-21 is fixed in $name — invert this test');
      }
      // F-J-21 got slightly WORSE, and that is recorded rather than glossed.
      // The NestJS route inherited the Anthropic SDK's 10-minute default, which
      // was a bound even if a generous one. Retiring apps/api removed it: every
      // Anthropic call in this repo is now an unbounded Deno fetch. The retry
      // count WAS preserved in the move (§48.2); the timeout never existed to
      // preserve.
      expect(_edgeFn('ai-nutrition'), contains('ANTHROPIC_MAX_RETRIES = 2'),
          reason: 'retry parity with the SDK default was preserved; the timeout '
              'bound was not, because the SDK supplied it and the SDK is gone');
    });

    test('[characterizes F-J-16] the coaching-engine client cannot report a failure', () {
      // generate() returns null for a 500, a 404, a network error and "the model
      // had nothing to say" alike. The home briefing renders all four as "no
      // insight yet", which is also what a brand-new member sees. Contrast
      // generateAiWorkout, which throws — that is the contract the rest of the
      // AI surface should adopt.
      final svc = _lib('features/ai_coach/data/ai_coach_service.dart');
      expect(svc, contains('} catch (_) { return null; }'),
          reason: 'F-J-16 is fixed — invert this test');
      expect(_lib('features/workout/domain/workout_provider.dart'),
          contains("throw StateError('Workout generator failed"),
          reason: 'the workout generator already distinguishes unreachable from declined');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // AI-J-007 — the communication layers stay communication layers
  // ══════════════════════════════════════════════════════════════════════════
  group('AI-J-007 the LLM explains, it does not decide', () {
    test('[invariant] explain-decision may use only the recorded trace', () {
      final src = _edgeFn('explain-decision');
      expect(src, contains('HARD RULES'));
      expect(src, contains('Do NOT introduce exercises, muscles, reasons, or numbers not present'));
      expect(src, contains('Do not contradict the trace'));
      // It reads the trace under the CALLER's RLS, not service role, so it can
      // only narrate what the caller may already see.
      expect(src, contains('userDb.from(\'decision_traces\')'));
      expect(src, contains("if (!body.trace_id) return json({ error: 'Provide trace_id' }, 400)"));
    });

    test('[invariant] generate-communication may use only the deterministic brief', () {
      final src = _edgeFn('generate-communication');
      expect(src, contains('presentation layer, not an analyst'));
      expect(src, contains('Never introduce numbers, reasons, exercises,'));
      expect(src, contains('Do not contradict the brief'));
      expect(src, contains("userDb.from('communications')"));
      // The coach edits before sending: the model fills the draft text and
      // never touches status, so nothing it writes can reach a client unread.
      expect(src, contains("client_text: out.client_text ?? ''"));
      expect(RegExp(r"\.update\(\{[^}]*status").hasMatch(src), isFalse,
          reason: 'the model may fill the draft text and nothing else');
    });

    test('[invariant] explain-decision records what explained the trace', () {
      // The one place in the whole AI surface where a model identifier is
      // persisted alongside its output. It is the pattern the rest should follow.
      final src = _edgeFn('explain-decision');
      expect(src, contains('explain_model: MODEL'));
      expect(src, contains('explained_at: new Date().toISOString()'));
    });

    test('[characterizes F-J-25] every other model identifier is a literal that is never recorded', () {
      // Nine call sites, four files, three different model strings, no central
      // pin and — outside explain-decision — nothing persisted. An insight, a
      // macro estimate or a generated workout cannot be attributed to the model
      // that produced it, so a model change is not auditable after the fact.
      //
      // REMEDIATION: one shared constant per surface, and write the model id
      // into the row alongside the output.
      final ids = <String>{};
      for (final name in _anthropicFunctions) {
        for (final m in RegExp(r"model: '([^']+)'").allMatches(_edgeFn(name))) {
          ids.add(m.group(1)!);
        }
      }
      expect(ids.length, greaterThan(1),
          reason: 'F-J-25 is fixed — model ids are centralised; invert this test. Found: $ids');

      // ai-nutrition carries the one good shape: a single named constant with an
      // env override, so its model id is NOT one of the scattered literals above.
      // That pin moved here from apps/api/src/config/api-config.ts when the route
      // did (§46-§55).
      expect(_edgeFn('ai-nutrition'), contains("Deno.env.get('ANTHROPIC_MODEL')"));
      expect(_edgeFn('ai-nutrition'), contains('model: ANTHROPIC_MODEL'),
          reason: 'a variable, not a literal — this is the shape F-J-25 asks for');

      // Nothing but explain-decision writes a model id next to its output.
      for (final name in const ['ai-coach', 'ai-coaching-engine', 'ai-generate-workout',
                                'analyze-food-image']) {
        final src = _edgeFn(name);
        expect(src.contains('explain_model') || src.contains('evidence_source'), isFalse,
            reason: 'F-J-25 is fixed in $name — invert this test');
      }
      // enrich-exercise-intelligence is the counter-example that proves it is
      // cheap: it stamps evidence_source + ai_version on every row it writes.
      expect(_edgeFn('enrich-exercise-intelligence'), contains('evidence_source:'));
      expect(_edgeFn('enrich-exercise-intelligence'), contains('ai_version: AI_VERSION'));
    });
  });
}
