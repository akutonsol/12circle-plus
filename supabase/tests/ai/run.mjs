// Runs every live AI decision-integrity suite and exits non-zero if any
// assertion fails.
//
//   export QA_URL=... QA_ANON=...
//   node supabase/tests/ai/run.mjs
//
// Optional: AI_ALLOW_WRITES=1 enables the handful of checks that write to QA.
// They are listed in docs/QA_WORKSTREAM_J_AI_DECISION_INTEGRITY_REPORT.md §14.
import { results, ALLOW_WRITES, suiteVerdict } from './lib.mjs';

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
  // Deliberately not-asserted checks (lib.mjs skip()). Never passes, never failures.
  const skipped = results.slice(before).filter(r => r.skipped).length;
  summary.push({ label, ran: results.length - before, skipped, failures });
}

const chars = results.filter(r => r.kind === 'characterization');   // skips carry kind 'skip'
const charsHeld = chars.filter(r => r.pass).length;

console.log(`\n${'█'.repeat(74)}\n██  WORKSTREAM J — AI DECISION INTEGRITY SUMMARY\n${'█'.repeat(74)}`);
for (const s of summary) {
  const asserted = s.ran - s.skipped;
  console.log(`  ${suiteVerdict(s).padEnd(4)}  ${s.label.padEnd(38)} ` +
    (asserted === 0 && s.skipped > 0
      ? `  0 asserted, ${s.skipped} SKIPPED — NOT A PASS`
      : `${String(asserted - s.failures).padStart(3)}/${String(asserted).padEnd(3)}` +
        (s.skipped ? ` (+${s.skipped} SKIPPED)` : '')));
}
const total = summary.reduce((a, s) => a + s.ran - s.skipped, 0);
const totalSkipped = summary.reduce((a, s) => a + s.skipped, 0);
console.log(`\n  ${total - totalFailures}/${total} assertions passed across ${SUITES.length} suites`);
if (totalSkipped) {
  console.log(`  ${totalSkipped} assertion(s) SKIPPED — not passes. Each pins empty-substrate behaviour ` +
    'that cannot be exercised while exercise_intelligence is populated; see each suite above.');
}
console.log(`  ${charsHeld}/${chars.length} characterized defects still reproduce ` +
            '(a characterization that stops reproducing was either fixed — invert it — or drifted)');
process.exit(totalFailures ? 1 : 0);
