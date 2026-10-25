// Is a migration APPLIED to QA? — the one gate live suites use to decide whether
// an assertion about that migration is enforced or recorded as SKIPPED.
//
// It reads supabase/expected_applied.json, not the database, and that is
// deliberate rather than a shortcut:
//   * the manifest is the declared state, and the CI step `ENV-3 · declared vs
//     observed vs authored` (supabase/scripts/env3-live-check.mjs) fails the run
//     whenever the real QA ledger disagrees with it (L-1 missing, L-2 undeclared);
//   * probing behaviour instead would mean RUNNING the attack against a database
//     that may still be vulnerable — e.g. assigning a plan to someone else's
//     client to see whether it is refused — which writes to QA to answer a
//     question the ledger already answers.
// So "applied" here means: declared applied, and held equal to the ledger by ENV-3.
//
// A migration counts as applied only if ALL hold:
//   * its version is <= environments.qa.applied_through,
//   * it is not listed in `pending`,
//   * it is not listed in `excluded` (authored, at or below the frontier, but
//     deliberately NOT applied).
// Anything else — including a malformed manifest — is NOT applied: an assertion
// is never enforced on a guess.

import { readFileSync } from 'node:fs';

const MANIFEST = new URL('../../expected_applied.json', import.meta.url);

export function qaMigrationState(manifestText) {
  const text = manifestText ?? readFileSync(MANIFEST, 'utf8');
  const qa = JSON.parse(text)?.environments?.qa ?? {};
  return {
    appliedThrough: String(qa.applied_through ?? ''),
    pending: Object.keys(qa.pending ?? {}),
    excluded: Object.keys(qa.excluded ?? {}),
  };
}

export function migrationApplied(version, manifestText) {
  let s;
  try { s = qaMigrationState(manifestText); } catch { return false; }
  const v = String(version).padStart(3, '0');
  const through = s.appliedThrough.padStart(3, '0');
  if (!/^\d{3}$/.test(v) || !/^\d{3}$/.test(through)) return false;
  if (s.pending.includes(v) || s.excluded.includes(v)) return false;
  return v <= through;
}

// Self-test: `node supabase/tests/security/migration-state.mjs --self-test`
if (process.argv[1] && process.argv[1].endsWith('migration-state.mjs') && process.argv.includes('--self-test')) {
  const m = (through, pending = {}, excluded = {}) =>
    JSON.stringify({ environments: { qa: { applied_through: through, pending, excluded } } });
  const cases = [
    ['184 pending at frontier 181',          migrationApplied('184', m('181', { 184: {} })), false],
    ['184 applied at frontier 186',          migrationApplied('184', m('186')),               true],
    ['184 above the frontier, undeclared',   migrationApplied('184', m('183')),               false],
    ['183 excluded at frontier 186',         migrationApplied('183', m('186', {}, { 183: {} })), false],
    ['181 at frontier 181',                  migrationApplied('181', m('181')),               true],
    ['malformed manifest is NOT applied',    migrationApplied('184', '{not json'),            false],
    ['missing frontier is NOT applied',      migrationApplied('184', JSON.stringify({})),     false],
    ['current repo manifest: 186 pending',   migrationApplied('186'),                         false],
  ];
  let bad = 0;
  for (const [name, got, want] of cases) {
    const ok = got === want;
    if (!ok) bad++;
    console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${name} (got ${got}, want ${want})`);
  }
  console.log(bad ? `migration-state self-test: ${bad} FAILED` : `migration-state self-test: ${cases.length} passed`);
  process.exit(bad ? 1 : 0);
}
