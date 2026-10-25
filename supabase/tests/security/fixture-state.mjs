// Read-back verification of a coach_client_relationships FIXTURE, before any
// assertion that depends on it is allowed to run.
//
// Why (D24 review, D1): a refusal assertion — "a PENDING coach cannot write …" —
// is only evidence if the relationship really IS pending at that moment. The
// fixture writes were fire-and-forget, so a failed insert (e.g. a 409 on the
// unique coach/client pair) or a PATCH that did not persist left the actor in a
// different state, and the "pending" and "cancelled" refusals silently degraded
// into the "unrelated user" refusal — and still passed.
//
// This reads the PERSISTED row through the caller-supplied service-role reader
// and records a check. It passes only when there is EXACTLY ONE row for the pair
// and its status is the expected one. Anything else — no row, two rows, the wrong
// status, an error body — fails, and returns false so the caller can mark every
// dependent assertion as failed instead of running it.
//
// No side effects on import (unlike lib.mjs), so it can be self-tested offline:
//   node supabase/tests/security/fixture-state.mjs --self-test

export async function verifyRelationship({ read, check, coachUid, clientUid, expected, label }) {
  const r = await read(
    `coach_client_relationships?coach_id=eq.${coachUid}&client_id=eq.${clientUid}&select=status`);
  const rows = Array.isArray(r?.body) ? r.body : null;
  const ok = !!rows && rows.length === 1 && rows[0]?.status === expected;
  const seen = rows ? (rows.map((x) => x?.status).join(',') || 'no row') : `unreadable (status ${r?.status})`;
  check(`fixture: ${label} — relationship is ${expected}`, ok, `persisted: ${seen}`);
  return ok;
}

/** Records every dependent assertion as FAILED because its fixture was not in place. */
export function failDependents(check, names, why) {
  for (const n of names) check(n, false, `NOT ASSERTABLE — ${why}; not run, so it cannot pass against the wrong state`);
}

// ── self-test ────────────────────────────────────────────────────────────────
if (process.argv[1] && process.argv[1].endsWith('fixture-state.mjs') && process.argv.includes('--self-test')) {
  const cases = [
    ['persisted as expected',                  { status: 200, body: [{ status: 'pending' }] },    'pending', true],
    ['creation failed — no row',               { status: 200, body: [] },                         'pending', false],
    ['PATCH did not persist — still pending',  { status: 200, body: [{ status: 'pending' }] },    'cancelled', false],
    ['wrong state — active instead of pending',{ status: 200, body: [{ status: 'active' }] },     'pending', false],
    ['two rows for the pair',                  { status: 200, body: [{ status: 'pending' }, { status: 'pending' }] }, 'pending', false],
    ['read error (e.g. 401/409 body)',         { status: 409, body: { code: '23505', message: 'duplicate key' } }, 'pending', false],
  ];
  let bad = 0;
  for (const [name, resp, expected, want] of cases) {
    const recorded = [];
    const got = await verifyRelationship({
      read: async () => resp, check: (n, pass, d) => { recorded.push({ n, pass, d }); return pass; },
      coachUid: 'c', clientUid: 'v', expected, label: name });
    const ok = got === want && recorded.length === 1 && recorded[0].pass === want;
    if (!ok) bad++;
    console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${name}: verify=${got} (want ${want}) — ${recorded[0]?.d}`);
  }
  // A failed fixture must turn its dependents into FAILURES, never skips or passes.
  const dep = [];
  failDependents((n, pass) => { dep.push(pass); return pass; }, ['a', 'b', 'c'], 'pending fixture missing');
  const depOk = dep.length === 3 && dep.every((p) => p === false);
  if (!depOk) bad++;
  console.log(`  ${depOk ? 'PASS' : 'FAIL'}  a failed fixture records each dependent assertion as FAILED (${dep.join(',')})`);
  console.log(bad ? `fixture-state self-test: ${bad} FAILED` : `fixture-state self-test: ${cases.length + 1} passed`);
  process.exit(bad ? 1 : 0);
}
