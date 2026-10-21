#!/usr/bin/env node
// Migration ↔ wave-plan coverage, reconciled from tracked sources only.
//
// WHY THIS EXISTS. A prior reconciliation reported "51 migrations beyond the
// plan" by matching the pre-assignment table with a narrow regex and reading
// absence from that table as absence from the plan. The plan's own final row
// says otherwise:
//
//     | **132+** | 4+ | Assigned at wave entry, never before |
//
// So migrations at or above the floor are OUTSIDE the pre-assignment scope by
// the plan's explicit rule, not missing from it. This tool encodes that
// convention so the distinction cannot be re-lost, and reports anything that
// genuinely does not fit.
//
// WHAT IT DELIBERATELY DOES NOT DO. It never infers status from a migration's
// number or from a file existing. Applied/verified status is not derivable from
// tracked files — `expected_applied.json` declares intent, not outcome — so it
// is reported as NOT ESTABLISHED HERE rather than guessed.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const MIG_DIR = path.join(ROOT, 'supabase', 'migrations');
const PLAN = path.join(ROOT, 'docs', 'MASTER_REMEDIATION_WAVES.md');
const MANIFEST = path.join(ROOT, 'supabase', 'expected_applied.json');

const json = process.argv.includes('--json');
// `--check` compares the committed artifact against a fresh derivation. Without
// it the artifact is a snapshot that goes quietly stale — which is precisely
// the failure mode this programme keeps finding in documents.
const checkArtifact = process.argv.includes('--check');
const ARTIFACT = path.join(ROOT, '.skills-agent', 'migration-coverage.json');

// ── migrations actually present ───────────────────────────────────────────
const files = fs.readdirSync(MIG_DIR).filter((f) => /^\d+_.*\.sql$/.test(f)).sort();
const present = new Map();
for (const f of files) present.set(parseInt(f.match(/^(\d+)/)[1], 10), f);
const numbers = [...present.keys()].sort((a, b) => a - b);

// ── the plan's pre-assignment table and its floor ─────────────────────────
const plan = fs.readFileSync(PLAN, 'utf8');
const planRows = new Map();
for (const m of plan.matchAll(/^\|\s*\*{0,2}(\d{1,3})\*{0,2}\s*\|\s*\*{0,2}([0-9A-C+]+)\*{0,2}\s*\|/gm)) {
  planRows.set(parseInt(m[1], 10), m[2]);
}
const floorMatch = /^\|\s*\*{0,2}(\d{1,3})\+\*{0,2}\s*\|/m.exec(plan);
const floor = floorMatch ? parseInt(floorMatch[1], 10) : null;
// The plan's table has a LOWER bound as well as a floor: its first assigned row
// is 123, because the remediation programme starts there. Everything below is
// pre-existing history, NOT an unexplained gap — treating it as one made the
// first run of this tool report 123 false problems.
const planLow = planRows.size ? Math.min(...planRows.keys()) : null;

// ── manifest declarations ─────────────────────────────────────────────────
// The manifest does NOT enumerate migrations. It declares, per environment, an
// `applied_through` frontier plus `pending` and `excluded`. My first version of
// this tool invented a per-file key format, found none of it, and reported all
// 182 migrations as undeclared — a parser error presented as a finding.
const manifest = JSON.parse(fs.readFileSync(MANIFEST, 'utf8'));
const qa = manifest.environments?.qa ?? {};
// Coerced: the manifest stores applied_through as a STRING ("181"). A prior
// version tested Number.isInteger on it, got false, and reported every one of
// the 182 migrations as undeclared — a type error presented as a finding.
const appliedThrough = Number.parseInt(String(qa.applied_through ?? ''), 10);
const excluded = new Set((qa.excluded ?? []).map((x) => parseInt(String(x), 10)));
const pending = new Set(Object.keys(qa.pending ?? {}).map((x) => parseInt(x, 10)));
const isDeclared = (n) =>
  excluded.has(n) || pending.has(n)
  || (Number.isInteger(appliedThrough) && n <= appliedThrough);

const rows = [];
const problems = [];
for (const n of numbers) {
  const inPlan = planRows.has(n);
  const belowPlan = planLow != null && n < planLow;
  const aboveFloor = floor != null && n >= floor;
  let coverage;
  if (inPlan) coverage = `PRE-ASSIGNED to wave ${planRows.get(n)}`;
  else if (aboveFloor) coverage = `OUTSIDE pre-assignment by rule (>= ${floor}+, "assigned at wave entry")`;
  else if (belowPlan) coverage = `PRE-PROGRAMME history (< ${planLow}, before the plan's first assigned row)`;
  else coverage = 'UNEXPLAINED — inside the plan range yet not pre-assigned';
  if (coverage.startsWith('UNEXPLAINED')) {
    problems.push(`migration ${String(n).padStart(3, '0')} (${present.get(n)}) is below the `
      + `plan floor ${floor} yet has no pre-assignment row`);
  }
  rows.push({
    migration: String(n).padStart(3, '0'),
    file: `supabase/migrations/${present.get(n)}`,
    inManifest: isDeclared(n),
    planCoverage: coverage,
    appliedStatus: 'NOT ESTABLISHED HERE — expected_applied.json declares intent, not outcome',
  });
}

// contiguity, which Gate 0.9 requires and renumbering is forbidden to fix
const gaps = [];
for (let i = numbers[0]; i <= numbers[numbers.length - 1]; i++) {
  if (!present.has(i)) gaps.push(i);
}
if (gaps.length) problems.push(`non-contiguous authored sequence; missing: ${gaps.join(', ')}`);

const undeclared = numbers.filter((n) => !isDeclared(n));
if (undeclared.length) {
  problems.push(`authored but not declared in expected_applied.json: `
    + undeclared.map((n) => String(n).padStart(3, '0')).join(', '));
}

const summary = {
  authored: numbers.length,
  range: `${String(numbers[0]).padStart(3, '0')}–${String(numbers[numbers.length - 1]).padStart(3, '0')}`,
  planAssignedRange: planLow != null ? `${planLow}-${floor - 1}` : null,
  planFloor: floor,
  qaRef: qa.ref ?? null,
  appliedThrough: appliedThrough ?? null,
  preProgramme: rows.filter((r) => r.planCoverage.startsWith('PRE-PROGRAMME')).length,
  preAssigned: rows.filter((r) => r.planCoverage.startsWith('PRE-ASSIGNED')).length,
  outsideByRule: rows.filter((r) => r.planCoverage.startsWith('OUTSIDE')).length,
  unexplained: rows.filter((r) => r.planCoverage.startsWith('UNEXPLAINED')).length,
  contiguous: gaps.length === 0,
  allDeclared: undeclared.length === 0,
};

const payload = { summary, problems, rows };

if (checkArtifact) {
  let committed = null;
  try { committed = JSON.parse(fs.readFileSync(ARTIFACT, 'utf8')); }
  catch (e) {
    console.error(`FAIL — the committed artifact is missing or unreadable: ${ARTIFACT}`);
    process.exit(1);
  }
  const a = JSON.stringify(committed);
  const b = JSON.stringify(payload);
  if (a !== b) {
    console.error('FAIL — .skills-agent/migration-coverage.json is STALE. It no longer '
      + 'matches what the tracked tree derives. Regenerate it:\n'
      + '  node scripts/check-migration-wave-coverage.mjs --json > .skills-agent/migration-coverage.json');
    console.error(`  committed: ${JSON.stringify(committed.summary)}`);
    console.error(`  derived  : ${JSON.stringify(summary)}`);
    process.exit(1);
  }
  console.log(`PASS — the committed migration-coverage artifact matches the tracked tree `
    + `(${rows.length} migrations, ${problems.length} problems).`);
  process.exit(problems.length ? 1 : 0);
}

if (json) {
  console.log(JSON.stringify(payload, null, 2));
} else {
  console.log('Migration ↔ wave-plan coverage');
  console.log(`  authored        ${summary.authored} (${summary.range})`);
  console.log(`  plan assigns    ${summary.planAssignedRange} explicitly`);
  console.log(`  plan floor      ${summary.planFloor}+ — "assigned at wave entry, never before"`);
  console.log(`  manifest        qa ref=${summary.qaRef} applied_through=${summary.appliedThrough}`);
  console.log(`  pre-programme   ${summary.preProgramme}`);
  console.log(`  pre-assigned    ${summary.preAssigned}`);
  console.log(`  outside by rule ${summary.outsideByRule}`);
  console.log(`  unexplained     ${summary.unexplained}`);
  console.log(`  contiguous      ${summary.contiguous}`);
  console.log(`  all declared    ${summary.allDeclared}`);
  console.log('  applied status  NOT ESTABLISHED HERE for any migration — not derivable from tracked files');
}

if (problems.length) {
  console.error(`\nFAIL — ${problems.length} problem(s):`);
  for (const p of problems) console.error(`  · ${p}`);
  process.exit(1);
}
if (!json) console.log('\nPASS — every authored migration is accounted for by the plan\'s own convention.');
