// h01 — HARNESS · checkDelta measurability at PAGE_LIMIT
//
// OFFLINE. This file makes no request of any kind: it drives lib.mjs's checkDelta
// with numbers and reads back what it recorded. It runs first in run.mjs so a broken
// delta instrument is named before any suite leans on it.
//
// WHY IT EXISTS. checkDelta refused every value equal to PAGE_LIMIT, whether it was
// the length of one PostgREST page (which may be capped) or a countExact total
// (which never is). On 2026-11-13 P2 B3 failed "UNMEASURABLE before=1000 after=1000"
// on main 2f4cc2f, run 43466190325: `billing_entitlement` had grown +3 a run (988,
// 991, 994, 997, 1000) and landed on the cap. The rollover emitted nothing, exactly
// as ruled, and the same run read 1000 -> 1001 a step later — no capped page can.
//
// THE PROPERTY KEPT. A delta over counts NOT declared exact is still refused at the
// cap, in both directions. Only `exact: true` lifts it, and then a missed or a spurious
// event at exactly 1000 is still seen.
//
// Pre-fix: against the old lib.mjs (no `exact` option) the four "exact" cases below
// fail and the "not exact" ones pass.
import { results, check, section, summary, checkDelta, PAGE_LIMIT } from './lib.mjs';

/** One checkDelta call, recorded and printed nowhere: its verdict is the subject here,
 *  not an assertion of this suite. Returns what it would have recorded. */
function probe(args) {
  const log = console.log;
  console.log = () => {};
  try {
    checkDelta('probe', args);
    return results.pop();
  } finally {
    console.log = log;
  }
}

const refused = (r) => r.pass === false && r.name.endsWith('— UNMEASURABLE');
const measured = (r, pass) => r.pass === pass && !r.name.endsWith('— UNMEASURABLE');

// ─────────────────────────────────────────────────────────────────────────────
section('Counts not declared exact are still refused at the cap');

const L = PAGE_LIMIT;
check('PAGE_LIMIT is the PostgREST page size this guard assumes', L === 1000, `PAGE_LIMIT=${L}`);

let r = probe({ before: L, after: L, expected: 0 });
check('both sides at the cap, +0 expected → UNMEASURABLE, not a pass', refused(r), r.detail);

r = probe({ before: L - 1, after: L, expected: 1 });
check('after at the cap → UNMEASURABLE (it may be a capped page)', refused(r), r.detail);

r = probe({ before: L, after: L, expected: 0, exact: 'yes' });
check('only `exact: true` lifts the refusal — a truthy look-alike does not', refused(r), r.detail);

// ─────────────────────────────────────────────────────────────────────────────
section('Exact counts at the cap are measured');

r = probe({ before: L, after: L, expected: 0, exact: true });
check('exact 1000 -> 1000, +0 expected → measured and PASSES (the 2026-11-13 input)',
  measured(r, true), r.detail);

r = probe({ before: L, after: L + 1, expected: 1, exact: true });
check('exact 1000 -> 1001, +1 expected → measured and PASSES', measured(r, true), r.detail);

r = probe({ before: L, after: L, expected: 1, exact: true });
check('exact 1000 -> 1000, +1 expected → measured and FAILS: a MISSED event is seen',
  measured(r, false), r.detail);

r = probe({ before: L, after: L + 1, expected: 0, exact: true });
check('exact 1000 -> 1001, +0 expected → measured and FAILS: a SPURIOUS event is seen',
  measured(r, false), r.detail);

// ─────────────────────────────────────────────────────────────────────────────
section('Away from the cap nothing changed');

r = probe({ before: 997, after: 997, expected: 0 });
check('997 -> 997, +0 → passes with or without the flag', measured(r, true), r.detail);

r = probe({ before: 997, after: 998, expected: 0 });
check('997 -> 998, +0 → fails with or without the flag', measured(r, false), r.detail);

export default summary('H-01  checkDelta measurability (harness, offline)');
