import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// SEC-G11 — PD-A05 option (a) must not be silently widened.
///
/// ── WHY THIS EXISTS ────────────────────────────────────────────────────────
/// `F-J-12` is `VERIFIED_CLOSED`: migration 128 narrowed `decision_traces`
/// SELECT to the owner-ruled option (a) — subject OR creator OR the subject's
/// ACTIVE coach OR admin, and nothing else. The registry records a **retained
/// limitation** against that closure, and migration 128 repeats it in its own
/// header:
///
///   "The I-MIG-03 migration-durability guard tracks FUNCTION properties only
///    … RLS policies are outside its coverage, so nothing in this repository
///    would notice if a later migration replaced this policy with a weaker one
///    — the exact mechanism that produced F-J-01."
///
/// This file is that missing notice. It is a TEST-level guard in the shape of
/// `SEC-G1`, which already pins the `F-21` policy family; it deliberately does
/// NOT touch Gate 0.14, because 128 and registry §7.11 both record whether the
/// GATE should cover policies as an open governance question. Pinning a shape
/// the owner already ruled is not deciding that question.
///
/// ── WHAT IT CANNOT DO ──────────────────────────────────────────────────────
/// This reads committed migration source. It proves what the tree declares, not
/// what the database holds — the live half is `d05-intelligence-substrate.mjs`
/// §9 and `j04-provenance-authz.mjs`. A guard that read only the live catalog
/// would pass against a tree that had already lost the policy, and one that
/// reads only the tree cannot see a hand-edited database. Both halves exist on
/// purpose.
void main() {
  final dir = Directory('../../supabase/migrations');

  /// Every migration, numbered, ordered.
  List<({int number, String name, String body})> corpus() {
    final out = <({int number, String name, String body})>[];
    for (final f in dir.listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      final m = RegExp(r'^(\d+)_').firstMatch(name);
      if (m == null || !name.endsWith('.sql')) continue;
      out.add((
        number: int.parse(m.group(1)!),
        name: name,
        body: f.readAsStringSync(),
      ));
    }
    out.sort((a, b) => a.number.compareTo(b.number));
    return out;
  }

  /// SQL with comments removed. Every "must not contain X" assertion below runs
  /// against THIS, never the raw file: 128's header names `content_manager`,
  /// `coach` and `option (b)` repeatedly while granting none of them, so a word
  /// search on the raw text would fail on the prose that explains the exclusion.
  /// That mistake has recurred in this programme often enough to be a rule.
  String stripComments(String sql) => sql
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
      .replaceAll(RegExp(r'--[^\n]*'), '');

  /// The statement that creates the SELECT policy, comments already gone.
  String? selectPolicyOf(String code) => RegExp(
        r'CREATE\s+POLICY[^;]*ON\s+(?:public\.)?decision_traces[^;]*FOR\s+SELECT[^;]*;',
        caseSensitive: false,
        dotAll: true,
      ).firstMatch(code)?.group(0);

  bool touchesPolicy(String code) => RegExp(
        r'(?:CREATE|DROP)\s+POLICY[^;]*ON\s+(?:public\.)?decision_traces\b',
        caseSensitive: false,
        dotAll: true,
      ).hasMatch(code);

  late List<({int number, String name, String body})> all;
  late List<({int number, String name, String body})> definers;
  late String authoritativeCode;

  setUp(() {
    all = corpus();
    definers = all.where((m) => touchesPolicy(stripComments(m.body))).toList();
    authoritativeCode = stripComments(definers.last.body);
  });

  group('SEC-G11 · the detector is not vacuous', () {
    test('the migration corpus is actually found and non-trivial', () {
      expect(dir.existsSync(), isTrue,
          reason: 'migrations directory not found — every assertion below '
              'would pass by reading nothing');
      expect(all.length, greaterThan(150));
    });

    test('comment stripping removes the prose but NOT the policy COMMENT, and '
        'the grant assertions are scoped accordingly', () {
      final raw = all.firstWhere((m) => m.number == 128).body;
      final stripped = stripComments(raw);
      int count(String h, String n) => h.split(n).length - 1;

      expect(count(raw, 'content_manager'), greaterThan(1),
          reason: "128's header explains the exclusion by name, repeatedly");
      // Stripping `--` lines removes the prose. It CANNOT remove the word from
      // `COMMENT ON POLICY … IS '…content_manager is deliberately NOT
      // granted…'`, because that is a string literal, not a comment. Blanket
      // stripping of literals would be wrong — `role IN ('coach')` is a literal
      // that matters — so the grant assertions below are scoped to the CREATE
      // POLICY statement instead, and this test states that relationship rather
      // than pretending stripping is enough.
      expect(count(stripped, 'content_manager'), lessThan(count(raw, 'content_manager')),
          reason: 'stripping must remove at least the header occurrences');
      expect(count(stripped, 'content_manager'), 1,
          reason: 'exactly one survives: the policy COMMENT string literal');
      expect(selectPolicyOf(stripped)!.contains('content_manager'), isFalse,
          reason: 'and the GRANT itself — the only place it would take '
              'effect — does not mention it');
    });

    test('the policy matcher finds a real statement', () {
      expect(selectPolicyOf(authoritativeCode), isNotNull);
      expect(selectPolicyOf(authoritativeCode)!.toLowerCase(),
          contains('decision_traces'));
    });
  });

  group('SEC-G11 · the frontier of policy definers is tracked', () {
    // The D-3 pattern, authorized as Option A: record WHICH migrations define
    // this policy, and fail when that set changes. A new definer is not assumed
    // hostile — it is simply unreviewed, and the guard's own coverage has to
    // move with it deliberately.
    //
    // All three, in order: 089 created the defective role-class policy, 125
    // closed the actual `coach` hole but kept `content_manager` (option (b)),
    // and 128 narrowed it to the ruled option (a). 125 is NOT edited out —
    // editing an applied migration is ENV-2 / CRC-13, the defect this
    // programme is remediating — so it stays in the corpus and 128 supersedes
    // it by being later.
    const expectedDefiners = <String>[
      '089_mie_decision_intelligence.sql',
      '125_scope_decision_trace_reads.sql',
      '128_scope_decision_trace_reads_option_a.sql',
    ];

    test('exactly the recorded migrations touch decision_traces policies', () {
      expect(definers.map((m) => m.name).toList(), expectedDefiners,
          reason: 'A migration began or stopped defining a decision_traces '
              'policy. If the new one is authorized, extend this guard to '
              'assert ITS shape and add it here — do not just widen the list. '
              'PD-A05 option (a) is an owner ruling; narrowing or widening it '
              'needs a new one.');
    });

    test('the highest-numbered definer is the authoritative one, and it is 128',
        () {
      expect(definers.last.number, 128);
    });
  });

  group('SEC-G11 · option (a), arm by arm', () {
    test('the four authorized arms are all present', () {
      final policy = selectPolicyOf(authoritativeCode)!;
      expect(policy, contains('subject_id'));
      expect(policy, contains('created_by'),
          reason: 'M-1 retained the creator arm: auditability must survive the '
              'relationship ending');
      expect(policy.toLowerCase(), contains('is_active_coach_of'));
      expect(policy.toLowerCase(), contains('is_admin'));
    });

    test('the active-coach arm is scoped to the SUBJECT, not bare', () {
      final policy = selectPolicyOf(authoritativeCode)!;
      expect(
          RegExp(r'is_active_coach_of\s*\(\s*subject_id\s*\)',
                  caseSensitive: false)
              .hasMatch(policy),
          isTrue,
          reason: 'an unscoped is_active_coach_of() would readmit F-J-12 by a '
              'different route');
    });

    test('the admin arm uses the pinned SECURITY DEFINER, not an inline EXISTS',
        () {
      final policy = selectPolicyOf(authoritativeCode)!;
      expect(RegExp(r'public\.is_admin\s*\(\s*\)', caseSensitive: false)
          .hasMatch(policy), isTrue);
      expect(policy.toLowerCase(), isNot(contains('user_profiles')),
          reason: "125's inline EXISTS was replaced on purpose — is_admin() is "
              'the predicate every other admin gate uses, with search_path '
              'pinned');
    });

    test('content_manager is NOT granted', () {
      // Scoped to the CREATE POLICY statement: that is where a grant takes
      // effect. The surrounding COMMENT names content_manager precisely to
      // record that it is excluded, so asserting on the whole file would fail
      // on the documentation of the exclusion.
      expect(selectPolicyOf(authoritativeCode)!.toLowerCase(),
          isNot(contains('content_manager')),
          reason: 'option (b) retained content_manager; the owner ruled '
              'option (a), which does not');
    });

    test('and no migration GRANTs decision_traces to a role class', () {
      // A policy is not the only way to widen a read. A table-level GRANT to a
      // role would bypass the question entirely.
      final offenders = <String>[];
      for (final m in all) {
        final code = stripComments(m.body);
        for (final match in RegExp(
          r'GRANT\s+[^;]*\bON\s+(?:TABLE\s+)?(?:public\.)?decision_traces\b[^;]*TO\s+([^;]*);',
          caseSensitive: false,
          dotAll: true,
        ).allMatches(code)) {
          final to = match.group(1)!.toLowerCase();
          if (to.contains('content_manager') || RegExp(r'\bcoach\b').hasMatch(to)) {
            offenders.add('${m.name}: GRANT … TO ${match.group(1)!.trim()}');
          }
        }
      }
      expect(offenders, isEmpty);
    });

    test('the bare coach role is never sufficient — F-J-12 itself', () {
      final policy = selectPolicyOf(authoritativeCode)!.toLowerCase();
      expect(
          RegExp(r"role\s*(?:=|in)\s*\(?\s*'?(?:coach|admin)").hasMatch(policy),
          isFalse,
          reason: "089's role-class arm is the defect. Read access is granted "
              'by RELATIONSHIP, not by role class.');
    });

    test('the policy targets authenticated', () {
      expect(selectPolicyOf(authoritativeCode)!.toLowerCase(),
          contains('to authenticated'));
    });
  });

  group('SEC-G11 · the write-deny posture holds across the whole tree', () {
    test('no migration ever creates a write policy on decision_traces', () {
      // Under RLS, "no policy" means deny. The table has a SELECT policy and no
      // write policy, so provenance cannot be hand-written — not even by an
      // admin. This scans EVERY migration, because the risk is a later one.
      final offenders = <String>[];
      for (final m in all) {
        final code = stripComments(m.body);
        final matches = RegExp(
          r'CREATE\s+POLICY[^;]*ON\s+(?:public\.)?decision_traces[^;]*?FOR\s+(ALL|INSERT|UPDATE|DELETE)',
          caseSensitive: false,
          dotAll: true,
        ).allMatches(code);
        for (final match in matches) {
          offenders.add('${m.name}: FOR ${match.group(1)!.toUpperCase()}');
        }
      }
      expect(offenders, isEmpty,
          reason: 'decision_traces must carry NO write policy. 128 says it '
              '"creates NO write policy and must never be extended to". '
              'Writes are SECURITY DEFINER engine functions; erasure is '
              'service_role, which bypasses RLS.');
    });

    test('migration 128 declares exactly ONE policy on decision_traces', () {
      // Pinned to 128 BY NUMBER, not to `definers.last`. The first version read
      // the latter, and the negative control exposed why that was weak: under a
      // widening, `definers.last` IS the widening migration, which declared one
      // policy of its own and so passed trivially. The assertion is about 128,
      // so it names 128.
      final code = stripComments(
          all.firstWhere((m) => m.number == 128).body);
      final created = RegExp(
        r'CREATE\s+POLICY[^;]*ON\s+(?:public\.)?decision_traces',
        caseSensitive: false,
        dotAll: true,
      ).allMatches(code).length;
      expect(created, 1);
    });
  });
}
