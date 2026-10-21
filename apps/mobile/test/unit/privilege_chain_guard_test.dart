import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// CHAIN-G1 — a self-assertable table must not feed an authorization helper
/// that a PHI-bearing policy trusts.
///
/// ── THE COMPOSITION NOBODY GUARDED ─────────────────────────────────────────
/// Three facts were each recorded separately, and their product was not:
///
///   1. `002_ecosystem_additions.sql:146`
///        CREATE POLICY "Head coach manages team"
///          ON coach_team_members FOR ALL USING (coach_id = auth.uid());
///      `FOR ALL` with a USING clause and **no WITH CHECK**. Postgres reuses
///      USING as the INSERT check, so any authenticated user may insert a row
///      naming themselves `coach_id` and any victim `member_id`. This is
///      member 12 of the 15 policies already ratcheted as F-21 / OD-14 by
///      `rls_policy_shape_guard_test.dart` (SEC-G1).
///
///   2. `102_restrict_user_profiles.sql:50`
///        is_team_lead_of(target) = EXISTS(coach_team_members
///          WHERE coach_id = auth.uid() AND member_id = target)
///      No status or consent condition, unlike `is_active_coach_of`.
///
///   3. `102_restrict_user_profiles.sql:164`
///        the `user_profiles` SELECT policy trusts `is_team_lead_of(id)`.
///
/// Composed: **any authenticated user can read any user's `parq_answers`,
/// `medical_conditions`, weight and billing columns on demand.** The Cloud
/// workstream reached this live (QAX-SEC-08, P0, LR + MUT) and it retracts the
/// earlier H-06 conclusion that the `user_profiles` policy "is correct".
///
/// SEC-G1 counts the self-assertable POPULATION (15) and would stay green while
/// a new helper started trusting one of them. This guard pins the CHAIN.
///
/// ── WHAT THIS IS NOT ───────────────────────────────────────────────────────
/// Not a fix. Correcting either end is migration-governed and reserved:
/// the policy population is **OD-14**, and what a "team" means is **OD-QAX-9**.
/// `docs/proposed/SEC_PHI_1_roster_attendee_views.sql` carries the proposed
/// read-side narrowing and a correction recording that it is necessary but not
/// sufficient without the write-side consent fix.
void main() {
  final selfAssertable = RegExp(
      r'CREATE POLICY\s+"([^"]+)"\s+ON\s+([\w.]+)\s+FOR\s+ALL(.*?);',
      dotAll: true, caseSensitive: false);
  final roleCheck = RegExp(
      r'is_coach_profile|is_admin|is_active_coach_of|is_team_lead_of|'
      r'hosts_event_for|role\s*=|EXISTS\s*\(',
      caseSensitive: false);
  final privileged = RegExp(r'coach|admin|head|team|vendor', caseSensitive: false);
  final uidCol = RegExp(r'(\w*?_?id)\s*=\s*\(?\s*(?:SELECT\s+)?auth\.uid\(\)',
      caseSensitive: false);
  final phiTable = RegExp(
      r'user_profiles|weekly_checkins|parq|cycle_|weight_logs|'
      r'body_measurements|ai_memories|coach_notes',
      caseSensitive: false);

  /// Tables any authenticated caller can write themselves into.
  Set<String> assertableTables(Iterable<String> sources) {
    final out = <String>{};
    for (final s in sources) {
      for (final m in selfAssertable.allMatches(s)) {
        final body = m.group(3)!;
        // A WITH CHECK clause means the INSERT path is stated explicitly, so
        // the USING-as-WITH-CHECK reuse does not apply.
        if (body.toUpperCase().contains('WITH CHECK')) continue;
        if (!privileged.hasMatch(m.group(1)!)) continue;
        if (!uidCol.hasMatch(body)) continue;
        if (roleCheck.hasMatch(body)) continue;
        out.add(m.group(2)!.split('.').last);
      }
    }
    return out;
  }

  /// Helper functions whose body reads one of those tables.
  Map<String, Set<String>> helpers(Iterable<String> sources, Set<String> tables) {
    final fn = RegExp(
        r'CREATE\s+(?:OR REPLACE\s+)?FUNCTION\s+(?:public\.)?'
        r'(is_\w+|hosts_\w+|can_\w+|shares_\w+)\s*\((.*?)\)(.*?)\$\$(.*?)\$\$',
        dotAll: true, caseSensitive: false);
    final out = <String, Set<String>>{};
    for (final s in sources) {
      for (final m in fn.allMatches(s)) {
        final body = m.group(4)!;
        final hit = tables.where((t) => RegExp('\\b$t\\b').hasMatch(body)).toSet();
        if (hit.isNotEmpty) {
          out.putIfAbsent(m.group(1)!.toLowerCase(), () => <String>{}).addAll(hit);
        }
      }
    }
    return out;
  }

  /// Complete chains: self-assertable write -> helper -> PHI-table policy.
  List<String> chains(Map<String, String> sources) {
    final tables = assertableTables(sources.values);
    final hs = helpers(sources.values, tables);
    final pol = RegExp(r'CREATE POLICY\s+"([^"]+)"\s+ON\s+([\w.]+)(.*?);',
        dotAll: true, caseSensitive: false);
    final out = <String>[];
    sources.forEach((name, s) {
      for (final m in pol.allMatches(s)) {
        final table = m.group(2)!.split('.').last;
        if (!phiTable.hasMatch(table)) continue;
        for (final h in hs.keys) {
          if (RegExp('\\b$h\\s*\\(', caseSensitive: false).hasMatch(m.group(3)!)) {
            final line = s.substring(0, m.start).split('\n').length;
            out.add('$name:$line $table "${m.group(1)}" via $h() '
                '<- ${(hs[h]!.toList()..sort()).join(",")}');
          }
        }
      }
    });
    return out..sort();
  }

  Map<String, String> readMigrations() {
    final dir = Directory('../../supabase/migrations');
    expect(dir.existsSync(), isTrue,
        reason: 'migrations not found — repoint this guard rather than '
            'letting it assert nothing');
    return {
      for (final f in dir.listSync().whereType<File>())
        if (f.path.endsWith('.sql')) f.uri.pathSegments.last: f.readAsStringSync()
    };
  }

  test('CHAIN-G1 self-test: the detector finds a planted chain and clears a fix',
      () {
    // Non-vacuity, proven on fixtures rather than asserted. The "fixed" variant
    // is the same chain with a WITH CHECK on the write side.
    const broken = {
      'a.sql': '''
CREATE POLICY "Head coach manages team" ON planted_team FOR ALL USING (coach_id = auth.uid());
CREATE FUNCTION public.is_planted_lead(t uuid) RETURNS boolean AS \$\$
  SELECT EXISTS (SELECT 1 FROM planted_team WHERE coach_id = auth.uid() AND member_id = t);
\$\$;
CREATE POLICY "read" ON user_profiles FOR SELECT USING (public.is_planted_lead(id));
''',
    };
    expect(chains(broken), hasLength(1),
        reason: 'the detector cannot see a complete planted chain');

    final fixed = {
      'a.sql': broken['a.sql']!.replaceFirst(
          'FOR ALL USING (coach_id = auth.uid())',
          'FOR ALL USING (coach_id = auth.uid()) WITH CHECK (member_id = auth.uid())'),
    };
    expect(chains(fixed), isEmpty,
        reason: 'a WITH CHECK on the write side must clear the chain, or this '
            'guard can never be satisfied by the real fix');
  });

  test('CHAIN-G1 no NEW privilege-escalation chain into a PHI table', () {
    final sources = readMigrations();
    expect(sources.length, greaterThan(100),
        reason: 'almost no migrations parsed — the detector is broken');

    // Measured 2026-09-27. This may only SHRINK. Shrinking it is the last step
    // of closing QAX-SEC-08; a rise means a new helper began trusting a table
    // that any caller can write themselves into.
    const known = <String>[
      '102_restrict_user_profiles.sql:164 user_profiles '
          '"own profile or active coach reads profile" via is_team_lead_of() '
          '<- coach_team_members',
    ];

    final found = chains(sources);
    expect(found, known,
        reason: 'The set of self-assertable -> helper -> PHI chains changed.\n'
            'FOUND:\n  ${found.join("\n  ")}\n\n'
            'A NEW entry means any authenticated user can now reach PHI by '
            'writing their own uid into a table a policy trusts — the '
            'QAX-SEC-08 shape. A REMOVED entry means it was fixed: delete it '
            'from `known` in the same change.');
  });

  test('CHAIN-G1 the three composing facts are each still true', () {
    // If any single link is corrected the chain breaks, and this guard must say
    // WHICH one moved rather than only that the set changed.
    final sources = readMigrations();
    final team = sources['002_ecosystem_additions.sql'] ?? '';
    final restrict = sources['102_restrict_user_profiles.sql'] ?? '';

    expect(team, contains('ON coach_team_members FOR ALL USING (coach_id = auth.uid())'),
        reason: 'LINK 1 changed: the coach_team_members write policy. If a '
            'WITH CHECK was added, QAX-SEC-08 is closed — update `known`.');
    expect(restrict, contains('FROM public.coach_team_members t'),
        reason: 'LINK 2 changed: is_team_lead_of no longer reads '
            'coach_team_members');
    expect(restrict.contains('r.status'), isFalse,
        reason: 'LINK 2: is_team_lead_of gained a status check — good, but the '
            'chain analysis must be redone');
    expect(restrict, contains('OR public.is_team_lead_of(id)'),
        reason: 'LINK 3 changed: the user_profiles policy no longer trusts '
            'is_team_lead_of — QAX-SEC-08 read side is closed');
  });
}
