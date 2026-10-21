#!/usr/bin/env node
// ENV-3 · the STATIC half of the migration-state contract.
//
// ── What this checks, and what it deliberately does not ─────────────────────
//
// It reconciles two things that both live in the repository:
//
//   authored  the migration versions actually present in supabase/migrations/
//   declared  supabase/expected_applied.json -- what each environment is
//             supposed to have applied, what it deliberately has not, and why
//
// It never opens a network connection, needs no credential, and reads no
// database. The third term of the contract --
//
//   observed  supabase_migrations.schema_migrations, the real ledger
//
// -- is the LIVE half, and it is not implemented here. That half needs a QA
// database credential in CI (the same blocker as FG-1/FG-2) and is what finally
// moves ENV-3 from REMEDIATED to VERIFIED_CLOSED. Until then this guard proves
// only that the declaration is coherent with the tree -- which is a real
// property, and a precondition for the live comparison meaning anything.
//
// ── Why the original ENV-3 wording is not what this implements ──────────────
//
// ENV-3's Tests field said "a CI check that the ledger's max version equals the
// highest migration filename". That is a specification defect in three ways: a
// max cannot see a hole in the middle; it asserts authored == applied, which
// this programme violates ON PURPOSE (102 is withheld from production, 123 is
// committed-but-unapplied right now); and it is environment-blind, so it cannot
// be true for QA and production simultaneously during any staged rollout. Read
// literally it is red today by design -- ledger max 122, highest filename 123.
//
// RELEASE_GATES row 1.2 already states the correct, directional property:
// "every migration APPLIED to QA is recorded in schema_migrations". This guard
// is the static precondition for checking that, not a replacement for it.
//
// ── Ownership boundary ──────────────────────────────────────────────────────
//
// Migration NUMBERING -- filename shape, duplicate prefixes, contiguity -- is
// gate 0.9 and belongs to check-migration-hygiene.sh. This guard deliberately
// does not re-derive those rules; it assumes the authored set is well-formed
// and asks only whether the declaration covers it honestly. Two guards, two
// jobs, no duplicated logic to drift apart.
//
//   node supabase/scripts/check-migration-manifest.mjs
//   node supabase/scripts/check-migration-manifest.mjs --migrations-dir DIR --manifest FILE
//
// The two overrides exist so the guard can be tested against fixtures without
// touching a real migration. Exit 0 when the declaration is coherent, 1 when it
// is not. An authored-but-pending migration is REPORTED, never a failure.

import { readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
const argOf = (flag, fallback) => {
  const i = process.argv.indexOf(flag);
  return i !== -1 && process.argv[i + 1] ? resolve(process.argv[i + 1]) : fallback;
};
const MIGRATIONS_DIR = argOf('--migrations-dir', join(HERE, '..', 'migrations'));
const MANIFEST = argOf('--manifest', join(HERE, '..', 'expected_applied.json'));

const VERSION = /^\d{3}$/;
const failures = [];
const notes = [];
const fail = (rule, msg) => failures.push({ rule, msg });

// ── authored ────────────────────────────────────────────────────────────────
const authored = readdirSync(MIGRATIONS_DIR)
  .filter((f) => /^\d{3}_[a-z0-9_]+\.sql$/.test(f))
  .map((f) => f.slice(0, 3))
  .sort();
const authoredSet = new Set(authored);

// ── declared ────────────────────────────────────────────────────────────────
const raw = readFileSync(MANIFEST, 'utf8');
let manifest;
try {
  manifest = JSON.parse(raw);
} catch (err) {
  console.error(`FAIL — ${MANIFEST} is not valid JSON: ${err.message}`);
  process.exit(1);
}

// Rule 2, first half: JSON.parse keeps the LAST of a duplicated key silently, so
// a duplicate declaration would be invisible after parsing. Count the raw
// version-shaped keys and compare against what parsing produced.
const rawKeyCounts = new Map();
for (const m of raw.matchAll(/"(\d{3})"\s*:/g)) {
  rawKeyCounts.set(m[1], (rawKeyCounts.get(m[1]) || 0) + 1);
}

if (!manifest.environments || typeof manifest.environments !== 'object') {
  console.error('FAIL — manifest has no "environments" object.');
  process.exit(1);
}

const parsedKeyCounts = new Map();
const envNames = Object.keys(manifest.environments);

for (const env of envNames) {
  const e = manifest.environments[env] || {};
  const excluded = e.excluded && typeof e.excluded === 'object' ? e.excluded : {};
  const pending = e.pending && typeof e.pending === 'object' ? e.pending : {};
  const label = `[${env}]`;

  for (const v of [...Object.keys(excluded), ...Object.keys(pending)]) {
    parsedKeyCounts.set(v, (parsedKeyCounts.get(v) || 0) + 1);
  }

  // Rule 6 — the frontier must exist, be well-formed, and be a real migration.
  const frontier = e.applied_through;
  if (typeof frontier !== 'string' || !VERSION.test(frontier)) {
    fail(6, `${label} applied_through is missing or malformed: ${JSON.stringify(frontier)} (want a three-digit version string)`);
    continue;
  }
  if (!authoredSet.has(frontier)) {
    fail(6, `${label} applied_through ${frontier} is not an authored migration`);
    continue;
  }

  // Rules 1, 3, 5, 8 — every declared entry must be well-formed, authored, and
  // carry the metadata that makes the declaration reviewable.
  for (const [bucket, entries] of [['excluded', excluded], ['pending', pending]]) {
    for (const [v, meta] of Object.entries(entries)) {
      if (!VERSION.test(v)) {
        fail(3, `${label} ${bucket} key "${v}" is malformed (want a three-digit version string)`);
        continue;
      }
      if (!authoredSet.has(v)) {
        fail(bucket === 'pending' ? 5 : 1, `${label} ${bucket} names version ${v}, which has no migration file`);
        continue;
      }
      const reason = meta && typeof meta === 'object' ? meta.reason : null;
      const gate = meta && typeof meta === 'object' ? meta.gate : null;
      if (!reason || !String(reason).trim()) {
        fail(8, `${label} ${bucket} ${v} has no "reason" — an undocumented deviation is not a declaration`);
      }
      if (!gate || !String(gate).trim()) {
        fail(8, `${label} ${bucket} ${v} has no "gate" — say what releases it`);
      }
      // Position sanity: excluded is at-or-below the frontier, pending is above.
      if (bucket === 'excluded' && v > frontier) {
        fail(4, `${label} excluded ${v} is ABOVE the frontier ${frontier} — an unapplied version above the frontier is "pending", not "excluded"`);
      }
      if (bucket === 'pending' && v <= frontier) {
        fail(4, `${label} pending ${v} is at or below the frontier ${frontier} — the frontier already claims it as applied`);
      }
    }
  }

  // Rule 4 — a version cannot be in two states at once.
  for (const v of Object.keys(pending)) {
    if (Object.prototype.hasOwnProperty.call(excluded, v)) {
      fail(4, `${label} version ${v} is declared BOTH pending and excluded`);
    }
  }

  // Rule 7 — every authored version must be classified. Silence is not a state.
  const undeclared = authored.filter((v) =>
    v > frontier
    && !Object.prototype.hasOwnProperty.call(pending, v)
    && !Object.prototype.hasOwnProperty.call(excluded, v));
  for (const v of undeclared) {
    fail(7, `${label} authored migration ${v} is above the frontier ${frontier} and is declared nowhere — declare it pending (with a reason and a gate) or move the frontier`);
  }

  // The expected set, derived rather than restated: everything at or below the
  // frontier that is not deliberately excluded. This is what the LIVE half will
  // compare against schema_migrations.
  const expected = authored.filter((v) => v <= frontier && !Object.prototype.hasOwnProperty.call(excluded, v));
  notes.push({ env, frontier, expected, pending: Object.keys(pending).sort(), excluded: Object.keys(excluded).sort() });
}

// Rule 2, second half.
for (const [v, count] of rawKeyCounts) {
  const parsed = parsedKeyCounts.get(v) || 0;
  if (count > parsed) {
    fail(2, `version ${v} appears ${count} times as a declaration key but survives parsing ${parsed} time(s) — a duplicate key is silently discarded by JSON and must not be relied on`);
  }
}

// ── report ──────────────────────────────────────────────────────────────────
const line = '─'.repeat(74);
console.log(`\n  ENV-3 · migration-state declaration (STATIC half)`);
console.log(`  ${authored.length} authored migration(s): ${authored[0]}–${authored[authored.length - 1]}`);

for (const n of notes) {
  console.log(`\n${line}\n  environment: ${n.env}\n${line}`);
  console.log(`  frontier          ${n.frontier}  (expected applied: ${n.expected.length} version(s), ${n.expected[0]}–${n.expected[n.expected.length - 1]})`);
  console.log(`  excluded          ${n.excluded.length ? n.excluded.join(', ') : '(none)'}`);
  if (n.pending.length) {
    console.log(`  authored, PENDING ${n.pending.join(', ')}  — committed but deliberately not applied here.`);
    console.log(`                    Not a failure. These are NOT written into schema_migrations`);
    console.log(`                    to make a check pass; their rows appear only when they are`);
    console.log(`                    actually applied.`);
  } else {
    console.log(`  authored, PENDING (none) — the tree and this environment's frontier agree`);
  }
}

console.log(`\n${line}`);
if (failures.length) {
  console.log(`  FAIL — ${failures.length} problem(s) in the declaration:\n`);
  for (const f of failures) console.log(`   [rule ${f.rule}] ${f.msg}`);
  console.log(`\n  The declaration and the tree disagree. Fix the manifest, or author the`);
  console.log(`  migration -- never delete the declaration to make this green.`);
  console.log(`${line}\n`);
  process.exit(1);
}
console.log(`  OK — every authored migration is declared, and every declaration is`);
console.log(`  authored, well-formed and documented. This is the STATIC half only:`);
console.log(`  nothing here has looked at a real ledger.`);
console.log(`${line}\n`);
