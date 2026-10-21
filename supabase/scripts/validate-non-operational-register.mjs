#!/usr/bin/env node
// Validates ADMIN-NON-OPERATIONAL-CAPABILITIES.json against the approved matrix.
//
// POSITIVE ASSERTION IS THE POINT. V5 §139.3: three times in this programme a
// checker found nothing and reported success — a BSD-sed regex that returned no
// columns and printed "clean" for a table holding OAuth tokens (§129.3), an RLS
// scan whose single-space pattern missed every ENABLE statement, and a deny
// assertion over an empty table that could not tell refusal from absence (§135.2).
// So every lookup here states what it EXPECTS TO FIND and fails loudly when it is
// not there. Nothing is inferred from a zero result.
//
//   node supabase/scripts/validate-non-operational-register.mjs
import { readFileSync } from 'node:fs';

const DIR = 'docs/design/admin-dashboard';
const REGISTER = `${DIR}/ADMIN-NON-OPERATIONAL-CAPABILITIES.json`;
const MATRIX = `${DIR}/ADMIN-CAPABILITY-MATRIX.json`;

const problems = [];
const fail = (m) => problems.push(m);

function load(path, label) {
  let raw;
  try { raw = readFileSync(path, 'utf8'); }
  catch { throw new Error(`${label} is MISSING at ${path} — this validator asserts it exists`); }
  if (!raw.trim()) throw new Error(`${label} at ${path} is EMPTY`);
  try { return JSON.parse(raw); }
  catch (e) { throw new Error(`${label} at ${path} is not valid JSON: ${e.message}`); }
}

const reg = load(REGISTER, 'the non-operational register');
const mat = load(MATRIX, 'the approved capability matrix');

// ── the register's own shape ────────────────────────────────────────────────
for (const key of ['version', 'authority', 'non_operational', 'undecided']) {
  if (!(key in reg)) fail(`register is missing the required key "${key}"`);
}
if (!Array.isArray(reg.non_operational) || reg.non_operational.length === 0) {
  fail('register.non_operational must be a NON-EMPTY array — an empty register would ' +
       'validate vacuously, which is the failure mode this file exists to prevent');
}
if (reg.matrix_is_unchanged !== true) {
  fail('register must assert matrix_is_unchanged: true — it records a fact about ' +
       'operations, never a change to authorization');
}

// ── the matrix, indexed, with existence asserted ───────────────────────────
if (!Array.isArray(mat.areas) || mat.areas.length === 0) {
  fail('matrix.areas is missing or empty — expected the 17 approved areas');
}
const byArea = new Map((mat.areas || []).map((a) => [a.area, a]));
if (byArea.size !== 17) fail(`expected 17 areas in the matrix, found ${byArea.size}`);

// ── every entry must agree with the matrix, exactly ────────────────────────
const seen = new Set();
for (const [i, e] of (reg.non_operational || []).entries()) {
  const at = `non_operational[${i}]`;
  for (const key of ['area', 'verb', 'granted_to', 'invariant', 'reason',
                     'why_not_an_implementation_defect', 'what_would_change_this']) {
    if (!e[key] || (Array.isArray(e[key]) && e[key].length === 0)) {
      fail(`${at} is missing a non-empty "${key}"`);
    }
  }
  const cell = `${e.area} / ${e.verb}`;
  if (seen.has(cell)) fail(`${at} duplicates ${cell}`);
  seen.add(cell);

  const area = byArea.get(e.area);
  if (!area) { fail(`${at} names area "${e.area}", which is NOT in the approved matrix`); continue; }
  const verb = (area.verbs || []).find((v) => v.verb === e.verb);
  if (!verb) { fail(`${at} names verb "${e.verb}" on "${e.area}", which the matrix does not define`); continue; }

  // The register may only describe a capability the matrix actually GRANTS. A
  // non-operational entry for a cell nobody holds would be noise, and one whose
  // holders disagree with the matrix would misreport the authorization.
  const holders = Object.entries(verb.grants).filter(([, g]) => g === true).map(([r]) => r).sort();
  if (holders.length === 0) {
    fail(`${at} registers ${cell} as non-operational, but the matrix grants it to NO ONE — ` +
         'there is no capability to describe');
  }
  const declared = [...e.granted_to].sort();
  if (JSON.stringify(declared) !== JSON.stringify(holders)) {
    fail(`${at} says ${cell} is granted to [${declared}] but the matrix grants it to ` +
         `[${holders}] — the register has drifted from the approved matrix`);
  }
}

// ── a cell cannot be both ruled and undecided ──────────────────────────────
const und = reg.undecided || {};
if (Object.keys(und).filter((k) => k !== '_').length === 0) {
  fail('register.undecided is empty — it must name what is NOT settled, or the file ' +
       'reads as a complete account of the inert grants and it is not');
}
for (const [id, group] of Object.entries(und)) {
  if (id === '_') continue;
  for (const a of group.areas || []) {
    for (const v of group.verbs || []) {
      if (seen.has(`${a} / ${v}`)) {
        fail(`${a} / ${v} is listed BOTH as non-operational and as undecided under ${id}`);
      }
      if (!byArea.has(a)) fail(`undecided.${id} names area "${a}", not in the approved matrix`);
    }
  }
}

if (problems.length) {
  console.error('\n  FAIL — non-operational register:');
  for (const p of problems) console.error(`    · ${p}`);
  console.error('');
  process.exit(1);
}
console.log(`  OK — register: ${reg.non_operational.length} ruled non-operational ` +
            `(${[...seen].join(', ')}), each agreeing with the approved matrix; ` +
            `${Object.keys(und).filter((k) => k !== '_').length} groups declared undecided.`);
