// Which cross-user reads target a table whose RLS would deny them?
//
// ── WHY THIS EXISTS ─────────────────────────────────────────────────────────
// An RLS-filtered SELECT is not an error. PostgREST answers `200` with `[]`,
// indistinguishable from "this user has none". So a read the database denies
// does not fail — it reports a confident, permanent, wrong zero. That was the
// `workout_logs` defect on three coach surfaces (QA_EVIDENCE §3ah, §3al), and
// nothing would have found the fourth instance.
//
// This sweeps every `.from('table')` read in `lib` that filters by somebody
// else's id, resolves the FINAL RLS state of that table across all migrations,
// and reports any whose policies contain no coach/relationship/role predicate.
//
// ── TWO THINGS IT GETS RIGHT THAT A GREP DOES NOT ──────────────────────────
//   * **dynamic SQL.** `074_ai_coaching_layer.sql` enables RLS on five tables
//     inside `do $$ foreach t in array[...] execute format(...)`. A
//     line-oriented scan misses it and reports five protected tables as
//     exposed — a false positive TWO separate workstreams have now made.
//   * **self-reads.** `.eq('user_id', uid)` is the caller reading their own
//     rows. Flagging those would bury the real findings in noise.
//
// ── AND WHAT IT CANNOT DO ──────────────────────────────────────────────────
//   * it reads migrations, not the live database — a policy applied out of
//     band is invisible to it;
//   * VIEWS have no RLS of their own and are reported as unprotected. Two are
//     deliberate bypasses and are covered by SEC-G4 instead;
//   * a read with no user filter at all (a reachability probe, a public
//     catalogue) is reported; judgement is still required.
//
// Usage:  dart tool/cross_user_read_sweep.dart
// Run from apps/mobile. Exits 0 always — this reports, it does not gate.
// The gates are SEC-G3 (test/unit/declared_denied_read_guard_test.dart) and
// SEC-G4 (test/unit/rls_bypassing_view_guard_test.dart).

import 'dart:io';

final _coachAware = RegExp(
    r'is_active_coach_of|is_coach_profile|is_team_lead_of|hosts_event_for|'
    r'is_admin|coach_id|EXISTS\s*\(|participant',
    caseSensitive: false);

void main() {
  final migrations = Directory('../../supabase/migrations');
  if (!migrations.existsSync()) {
    stderr.writeln('supabase/migrations not reachable from here.');
    exit(2);
  }

  final rlsOn = <String>{};
  final policies = <String, Map<String, String>>{};

  final files = migrations
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final f in files) {
    final src = f.readAsStringSync();

    for (final m in RegExp(
            r'alter\s+table\s+(?:if\s+exists\s+)?(?:only\s+)?(?:public\.)?"?(\w+)"?\s+enable\s+row\s+level\s+security',
            caseSensitive: false)
        .allMatches(src)) {
      rlsOn.add(m.group(1)!);
    }

    // The dynamic form a line-oriented scan misses.
    for (final m in RegExp(r"foreach\s+\w+\s+in\s+array\s*array\[([^\]]+)\]",
            caseSensitive: false)
        .allMatches(src)) {
      final block = src.substring(
          m.end, (m.end + 800).clamp(0, src.length));
      if (!block.toLowerCase().contains('enable row level security')) continue;
      final names = RegExp(r"'(\w+)'").allMatches(m.group(1)!);
      final using = RegExp(r'create policy "([^"]+)"[\s\S]*?using\s*\(([^)]*)\)',
              caseSensitive: false)
          .firstMatch(block);
      for (final n in names) {
        rlsOn.add(n.group(1)!);
        if (using != null) {
          policies.putIfAbsent(n.group(1)!, () => {})[using.group(1)!] =
              'USING (${using.group(2)})';
        }
      }
    }

    for (final m in RegExp(
            r'drop\s+policy\s+(?:if\s+exists\s+)?"([^"]+)"\s+on\s+(?:public\.)?"?(\w+)"?',
            caseSensitive: false)
        .allMatches(src)) {
      policies[m.group(2)!]?.remove(m.group(1));
    }
    for (final m in RegExp(
            r'create\s+policy\s+"([^"]+)"\s+on\s+(?:public\.)?"?(\w+)"?([\s\S]*?);',
            caseSensitive: false)
        .allMatches(src)) {
      policies.putIfAbsent(m.group(2)!, () => {})[m.group(1)!] =
          m.group(3)!.replaceAll(RegExp(r'\s+'), ' ');
    }
  }

  var flagged = 0, total = 0;
  final rows = <String>[];

  for (final f in Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))) {
    final src = f.readAsStringSync();
    for (final m in RegExp(r"\.from\('(\w+)'\)").allMatches(src)) {
      final table = m.group(1)!;
      final w = src.substring(m.start, (m.start + 340).clamp(0, src.length));
      if (RegExp(r'\.(insert|upsert|update|delete)\(').hasMatch(w)) continue;
      final selfRead =
          RegExp(r"\.eq\('(user_id|id)',\s*(uid|_uid|userId|currentUser)")
              .hasMatch(w);
      final otherRead = RegExp(
              r"\.inFilter\('(user_id|client_id|id)'|\.eq\('(user_id|client_id)',\s*(?!uid|_uid|userId)")
          .hasMatch(w);
      if (selfRead || !otherRead) continue;

      total++;
      final pol = policies[table] ?? const {};
      final aware = pol.values.any(_coachAware.hasMatch);
      final line = src.substring(0, m.start).split('\n').length;
      if (!aware) {
        flagged++;
        rows.add('  DENIED-OR-OPEN  $table  '
            '(rls ${rlsOn.contains(table) ? "on" : "OFF"}, '
            '${pol.length} policies)  ${f.path}:$line');
      }
    }
  }

  rows.sort();
  stdout.writeln(rows.isEmpty ? '  (nothing flagged)' : rows.join('\n'));
  stdout.writeln('\n$flagged flagged of $total cross-user reads.');
}
