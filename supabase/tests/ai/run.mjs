// Runs every live AI decision-integrity suite and exits non-zero if any
// assertion fails.
//
//   export QA_URL=... QA_ANON=...
//   node supabase/tests/ai/run.mjs
//
// Optional: AI_ALLOW_WRITES=1 enables the handful of checks that write to QA.
// They are listed in docs/QA_WORKSTREAM_J_AI_DECISION_INTEGRITY_REPORT.md §14.
import { results, ALLOW_WRITES } from './lib.mjs';

const SUITES = [
  ['J-01  AI input assembly',            './j01-input-assembly.mjs'],
  ['J-02  safety inputs',                './j02-safety-inputs.mjs'],
  ['J-03  deterministic engine boundary','./j03-engine-boundary.mjs'],
  ['J-04  provenance & subject scoping', './j04-provenance-authz.mjs'],
  ['J-05  AI-to-product path',           './j05-product-path.mjs'],
];

console.log(`AI decision-integrity suites — writes ${ALLOW_WRITES ? 'ENABLED' : 'disabled'}`);

let totalFailures = 0;
const summary = [];

for (const [label, path] of SUITES) {
  console.log(`\n${'█'.repeat(74)}\n██  ${label}\n${'█'.repeat(74)}`);
  const before = results.length;
  let failures;
  try {
    failures = (await import(path)).default ?? 0;
  } catch (err) {
    console.error(`  SUITE ERROR: ${err.message}`);
    failures = 1;
  }
  totalFailures += failures;
  summary.push({ label, ran: results.length - before, failures });
}

const chars = results.filter(r => r.kind === 'characterization');
const charsHeld = chars.filter(r => r.pass).length;

console.log(`\n${'█'.repeat(74)}\n██  WORKSTREAM J — AI DECISION INTEGRITY SUMMARY\n${'█'.repeat(74)}`);
for (const s of summary) {
  console.log(`  ${s.failures === 0 ? 'PASS' : 'FAIL'}  ${s.label.padEnd(38)} ${String(s.ran - s.failures).padStart(3)}/${String(s.ran).padEnd(3)}`);
}
const total = summary.reduce((a, s) => a + s.ran, 0);
console.log(`\n  ${total - totalFailures}/${total} assertions passed across ${SUITES.length} suites`);
console.log(`  ${charsHeld}/${chars.length} characterized defects still reproduce ` +
            '(a characterization that stops reproducing was either fixed — invert it — or drifted)');
process.exit(totalFailures ? 1 : 0);
