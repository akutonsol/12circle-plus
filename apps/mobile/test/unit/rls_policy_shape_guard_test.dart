import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// SEC-G1 — the F-21 policy shape must not spread.
///
/// ── THE DEFECT THIS PINS ───────────────────────────────────────────────────
/// `001_full_ecosystem.sql:351` reads:
///
///   CREATE POLICY "coaches manage programs" ON workout_programs
///     FOR ALL TO authenticated USING (coach_id = auth.uid());
///
/// The policy is *named* for coaches and never checks that the caller is one.
/// Anyone willing to write their own uid into `coach_id` satisfies it. Proven
/// empirically against QA: a client fixture created a programme naming itself
/// coach (201), self-assigned it (201), and **assigned it to another user**
/// (201 — cross-user write). All rows were deleted and cleanup verified.
/// See F-21 / F-21b in docs/QA_EVIDENCE.md.
///
/// `public.is_coach_profile(uuid)` already exists
/// (113_rls_coach_client_relationships.sql:58) and migration 113 applies
/// exactly that check to `coach_client_relationships`. It was never applied to
/// these tables.
///
/// ── WHY THIS IS A RATCHET AND NOT A FIX ────────────────────────────────────
/// Correcting the policies changes the authorization model, which the governing
/// instruction reserves as an owner decision (OD-14). This guard does not change
/// it. It holds the population at its measured size so a 16th cannot ship while
/// the decision is outstanding.
///
/// ── WHY IT READS THE MIGRATIONS AND NOT A MODEL OF THEM ────────────────────
/// `QA_CLOSURE_STANDARD` §4 records that 259 tests in this suite "define the
/// logic inside the test file and assert against the copy ... green whatever
/// the app does", and names `spec_security_guards_test.dart`'s simulated role
/// model as that shape. This guard parses the real `supabase/migrations/*.sql`
/// so it cannot pass while the database says otherwise.
/// The FOR ALL policies as they stand AFTER every later `ALTER POLICY` and
/// `DROP POLICY`, in migration order.
///
/// WHY THIS EXISTS (OD-14, migration 185). The two scans below used to read only
/// `CREATE POLICY ... FOR ALL`, which is correct for a tree that corrects policies
/// by drop-and-recreate and BLIND for one that corrects them with
/// `ALTER POLICY ... USING (...)`. Migration 185 does the latter, so a scan that
/// read only the CREATE statements would keep reporting the defect after it was
/// fixed — and, worse, would also keep reporting a policy that a later ALTER had
/// REPLACED with a different shape. The effective definition is what the database
/// enforces, so it is what these guards must read.
///
/// An ALTER that supplies `USING` replaces the whole body; one that supplies only
/// `WITH CHECK` is appended to what was there. A DROP, or a later CREATE of the
/// same name for a different command, removes the FOR ALL entry.
List<({String file, int line, String table, String name, String body})>
    effectiveAllPolicies() {
  final dir = Directory('../../supabase/migrations');
  if (!dir.existsSync()) return const [];

  String norm(String t) =>
      t.replaceFirst(RegExp(r'^public\.'), '').toLowerCase();

  final createAll = RegExp(
      r'CREATE POLICY\s+"([^"]+)"\s+ON\s+([\w.]+)\s+FOR\s+ALL(.*?);',
      dotAll: true,
      caseSensitive: false);
  final createOther = RegExp(
      r'CREATE POLICY\s+"([^"]+)"\s+ON\s+([\w.]+)\s+(?:AS\s+\w+\s+)?FOR\s+(?:SELECT|INSERT|UPDATE|DELETE)\b',
      caseSensitive: false);
  final alter = RegExp(r'ALTER POLICY\s+"([^"]+)"\s+ON\s+([\w.]+)(.*?);',
      dotAll: true, caseSensitive: false);
  final drop = RegExp(
      r'DROP POLICY\s+(?:IF EXISTS\s+)?"([^"]+)"\s+ON\s+([\w.]+)',
      caseSensitive: false);

  final live = <String,
      ({String file, int line, String table, String name, String body})>{};
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final f in files) {
    final src = f.readAsStringSync();
    final events = <({int at, String kind, RegExpMatch m})>[
      for (final m in createAll.allMatches(src))
        (at: m.start, kind: 'all', m: m),
      for (final m in createOther.allMatches(src))
        (at: m.start, kind: 'other', m: m),
      for (final m in alter.allMatches(src)) (at: m.start, kind: 'alter', m: m),
      for (final m in drop.allMatches(src)) (at: m.start, kind: 'drop', m: m),
    ]..sort((a, b) => a.at.compareTo(b.at));

    for (final e in events) {
      final key = '${norm(e.m.group(2)!)}|${e.m.group(1)}';
      switch (e.kind) {
        case 'all':
          live[key] = (
            file: f.uri.pathSegments.last,
            line: '\n'.allMatches(src.substring(0, e.at)).length + 1,
            table: e.m.group(2)!,
            name: e.m.group(1)!,
            body: e.m.group(3)!,
          );
        case 'alter':
          final old = live[key];
          if (old == null) break;
          final body = e.m.group(3)!;
          live[key] = (
            file: old.file,
            line: old.line,
            table: old.table,
            name: old.name,
            body: RegExp(r'\bUSING\b', caseSensitive: false).hasMatch(body)
                ? body
                : '${old.body} $body',
          );
        case 'other':
        case 'drop':
          live.remove(key);
      }
    }
  }
  return live.values.toList();
}

void main() {
  /// Measured 2026-09-23 at 15. Lowered to 9 on 2026-10-21 when migration 185
  /// (OD-14) corrected six of them by `ALTER POLICY`; the scan now reads the
  /// EFFECTIVE policy, after every ALTER and DROP. Lower it again when more are
  /// corrected; never raise it. A rise means a new table shipped with a policy
  /// that claims a role it does not verify.
  const baseline = 9;

  /// Policies that name a privilege but only compare a caller-writable column
  /// to `auth.uid()`.
  List<({String file, int line, String table, String name, String cols})>
      scan() {
    final policies = effectiveAllPolicies();
    if (policies.isEmpty) return const [];

    // A real guard: a role helper, an explicit role comparison, or a subquery
    // that establishes a relationship.
    final guarded = RegExp(
      r'is_coach_profile|is_admin|is_active_coach_of|is_team_lead_of|'
      r'hosts_event_for|role\s*=|EXISTS\s*\(',
      caseSensitive: false,
    );
    final privileged =
        RegExp(r'coach|admin|head|team|vendor', caseSensitive: false);
    final uidCol = RegExp(r'(\w*?_?id)\s*=\s*\(?\s*(?:SELECT\s+)?auth\.uid\(\)',
        caseSensitive: false);

    final out =
        <({String file, int line, String table, String name, String cols})>[];
    for (final p in policies) {
      final name = p.name;
      final body = p.body;
      if (body.toUpperCase().contains('WITH CHECK')) continue;
      if (guarded.hasMatch(body)) continue;
      if (!privileged.hasMatch(name)) continue;
      final cols = uidCol
          .allMatches(body)
          .map((c) => c.group(1)!)
          .toSet()
          .toList()
        ..sort();
      if (cols.isEmpty) continue;
      out.add((
        file: p.file,
        line: p.line,
        table: p.table,
        name: name,
        cols: cols.join(',')
      ));
    }
    return out;
  }

  test('SEC-G1 privilege-asserting policies with no role check do not increase',
      () {
    final found = scan();
    if (found.isEmpty) {
      // The migrations directory is not reachable from this working directory.
      // Say so rather than passing silently — a guard that cannot see its
      // subject protects nothing.
      fail('Could not read supabase/migrations — SEC-G1 asserted nothing. '
          'Check the relative path before trusting this suite.');
    }

    final listing = found
        .map((p) => '  ${p.file}:${p.line} ${p.table} [${p.cols}] "${p.name}"')
        .join('\n');

    expect(
      found.length,
      lessThanOrEqualTo(baseline),
      reason: 'A policy claims a privileged role but only compares a '
          'caller-writable column to auth.uid(), so anyone can satisfy it by '
          'writing their own uid into that column. This is the F-21 shape, '
          'proven exploitable for cross-user writes.\n'
          'Found ${found.length} (baseline $baseline):\n$listing\n\n'
          'Add is_coach_profile(coach_id) and an explicit WITH CHECK — the '
          'pattern migration 113 already uses for coach_client_relationships.',
    );
  });

  test('SEC-G1 the two proven-exploitable policies are still recorded', () {
    final found = scan();
    final tables = found.map((p) => p.table).toSet();
    // If these disappear from the inventory the fix has landed — lower the
    // baseline in the same commit rather than leaving this stale.
    expect(
      tables.any((t) => t.contains('workout_programs')) ||
          tables.any((t) => t.contains('workout_program_assignments')),
      isTrue,
      reason:
          'F-21 is recorded as OPEN in docs/QA_EVIDENCE.md. If the policies '
          'have been corrected, close F-21 and lower the SEC-G1 baseline in the '
          'same change — do not leave the ledger and the guard disagreeing.',
    );
  });

  test('SEC-G1 the helper the fix needs already exists', () {
    final f = File(
        '../../supabase/migrations/113_rls_coach_client_relationships.sql');
    expect(f.existsSync(), isTrue);
    expect(f.readAsStringSync(), contains('is_coach_profile'),
        reason: 'The correction for F-21 needs no new database function — '
            'migration 113 already defines and uses this one.');
  });

  // ── SEC-G2 · the cross-user-write subset ──────────────────────────────────
  //
  // SEC-G1 counts fifteen policies of one shape. They are NOT equally
  // dangerous, and a single number lets the worse kind hide inside it.
  //
  // `USING (coach_id = auth.uid() OR client_id = auth.uid())` is satisfied by
  // EITHER disjunct, so a caller can write a row naming itself as coach and
  // **any other user** as client. That is the class that reaches a victim, and
  // it is the one that was proven: a client fixture assigned a programme it had
  // just forged to a different account (201).
  //
  // FIVE policies across FOUR tables carry it — `coaching_calls` has two
  // ("Coach and client can see calls" from 002, and "calls_participant_access"
  // added later), which is worth stating because it means a correction has to
  // find both. A sixth must not appear while OD-14 is outstanding, and under
  // SEC-G1 alone it could: displacing one of the single-party policies leaves
  // the total unchanged.
  group('SEC-G2 the cross-user-write shape', () {
    /// Measured 2026-09-23: 5 policies across 4 tables. Migration 185 (OD-14)
    /// corrected all five by `ALTER POLICY`, so the baseline is now ZERO and the
    /// scan reads the effective definition. Never raise.
    const baseline = 0;

    List<({String table, String policy})> twoParty() {
      final policies = effectiveAllPolicies();
      if (policies.isEmpty) return const [];

      // Two DIFFERENT caller-writable columns, either of which satisfies the
      // predicate on its own.
      final uidCol = RegExp(r'(\w+_id)\s*=\s*\(?\s*(?:SELECT\s+)?auth\.uid\(\)',
          caseSensitive: false);
      final uidColRev =
          RegExp(r'auth\.uid\(\)\s*=\s*(\w+_id)', caseSensitive: false);

      final out = <({String table, String policy})>[];
      for (final p in policies) {
        final body = p.body;
        if (body.toUpperCase().contains('WITH CHECK')) continue;
        if (!body.toUpperCase().contains(' OR ')) continue;
        // A disjunct that ALSO requires an active relationship is not satisfiable
        // by naming a victim: the relationship row must exist and be active.
        if (RegExp(r'is_active_coach_of', caseSensitive: false).hasMatch(body))
          continue;
        final cols = <String>{
          ...uidCol.allMatches(body).map((c) => c.group(1)!),
          ...uidColRev.allMatches(body).map((c) => c.group(1)!),
        };
        if (cols.length < 2) continue;
        out.add((table: p.table, policy: p.name));
      }
      return out;
    }

    test('does not spread beyond the five recorded policies', () {
      // The premise is that the scan CAN see policies, not that it found some:
      // at baseline zero an empty result is the passing result.
      expect(effectiveAllPolicies().length, greaterThan(50),
          reason: 'Could not read supabase/migrations — SEC-G2 asserted nothing.');
      final found = twoParty();
      final listing = found.map((p) => '  ${p.table} "${p.policy}"').join('\n');
      expect(
        found.length,
        lessThanOrEqualTo(baseline),
        reason: 'A policy lets a caller satisfy it by naming EITHER party, so '
            'it can write a row about another user. This is the shape proven '
            'exploitable for a cross-user write.\n'
            'Found ${found.length} (baseline $baseline):\n$listing\n\n'
            'See docs/F21_BLAST_RADIUS.md §2a.',
      );
    });

    test('the four tables are corrected, and the correction is what is enforced', () {
      // docs/F21_BLAST_RADIUS.md names these four tables as carrying the
      // cross-user-write shape. Migration 185 corrected them; this asserts the
      // POSITIVE: each one's effective FOR ALL policy now requires an active
      // relationship. Without it, "zero found" could also mean "the scan broke".
      final byTable = <String, List<String>>{};
      for (final p in effectiveAllPolicies()) {
        byTable.putIfAbsent(p.table.replaceFirst('public.', ''), () => []).add(p.body);
      }
      for (final t in const [
        'workout_program_assignments',
        'client_nutrition_plans',
        'client_habits',
        'coaching_calls',
      ]) {
        final bodies = byTable[t];
        expect(bodies, isNotNull, reason: '$t has no FOR ALL policy at all');
        for (final b in bodies!) {
          expect(b, contains('is_active_coach_of'),
              reason: '$t has a FOR ALL policy that no longer requires an active '
                  'relationship on the coach arm — OD-14 / migration 185 regressed.');
        }
      }
    });

    test('the scan is not vacuous: it still sees a two-party policy when one exists', () {
      // Mutation probe on the DETECTOR, not on the tree: feed the same regexes a
      // body that has the shape and confirm it would be counted.
      const body = ' USING (coach_id = auth.uid() OR client_id = auth.uid())';
      final uidCol = RegExp(r'(\w+_id)\s*=\s*\(?\s*(?:SELECT\s+)?auth\.uid\(\)',
          caseSensitive: false);
      expect(uidCol.allMatches(body).map((m) => m.group(1)).toSet().length, 2);
      expect(body.toUpperCase().contains(' OR '), isTrue);
      expect(body.contains('is_active_coach_of'), isFalse);
    });
  });
}
