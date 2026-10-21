// d11 — BIL-3 / K-04 · event_registrations integrity
//
// ═══════════════════════════════════════════════════════════════════════════
// THIS SUITE HAS A GENUINE PRE-FIX HALF, AND IT NEEDS NO ROLLBACK.
//
// Unlike QAX-SEC-09 (§24.3), the defect this probe attacks is LIVE ON QA right
// now and has never been remediated there. So QA_CLOSURE_STANDARD §5.2 — "a
// real request against QA reproduces the secure/correct behaviour, and the same
// probe demonstrably failed before the fix" — is satisfiable by running this
// file against QA BEFORE migration 138 is applied and again after. No policy is
// reverted and no exposure is manufactured to obtain evidence.
//
// Every assertion below states the SECURE expectation.  Before 138 this suite
// WAS expected to fail on the attack assertions, and that failure WAS the
// evidence: the real pre-fix run scored **2/8** and is recorded in V5 §32.4.
//
// CORRECTED 2026-09-30 (V5 §65) — past tense, deliberately.  138 and 139 are
// applied and this suite passes **9/9**.  A FAILURE HERE IS NOW A REGRESSION,
// not the pre-fix reading.
// ═══════════════════════════════════════════════════════════════════════════
//
//   node supabase/tests/security/d11-event-registration-integrity.mjs

import {
  URL_, ANON, IDENT, signIn, rest, svc, mutate,
  check, section, beginSuite, summary, blocked, landed, n, loadIds,
} from './lib.mjs';

// POSITIVE allowlist, matching d07/d08/d10. lib.mjs only BLOCKS production, and
// "is not production" is not "is QA". This suite writes fixtures through
// service_role and attempts real PATCHes, so it takes the stronger guard.
const QA_REF = 'eyqtldjqpgpljlqvpowh';
if (!URL_.includes(QA_REF)) {
  console.error(`REFUSING TO RUN: "${URL_}" is not the 12 Circle QA project (${QA_REF}).`);
  process.exit(2);
}

const MARK = 'd11-probe';
const ids = await loadIds();
beginSuite();

// ── fixtures, arranged through service_role ──────────────────────────────────
// The attacker is made a vendor and given two events. §25 link 4 (vendor is
// self-assignable at signup) is already recorded and is NOT re-proven here;
// this arranges the same end state deterministically.
const cleanup = [];
const svcJson = async (path, opts) => (await svc(path, opts)).body;

// Pre-clean. A run aborted mid-suite by the connectivity fault (§31) leaves
// fixtures behind, and a leftover registration makes the INSERT arm ambiguous:
// the write 409s on the duplicate while the read-back still finds a paid row,
// which reads as a failure for the wrong reason. Remove any prior d11 state
// before arranging new state.
//
// The filter is deliberately WIDER than this suite's own marker. d10 also
// arranges an attacker-owned event with the victim registered for it, and d10
// does not always clean it up. That leftover makes hosts_event_for(victim)
// legitimately TRUE, which makes the PII assertion below VACUOUS: the view
// correctly returns the victim, and the suite reports a failure that has
// nothing to do with the defect under test. Observed exactly that on QA after
// 138 was applied. Any `d<N>-probe` event owned by the attacker is fixture
// state by construction, so all of them go.
{
  const stale = await svcJson(`events?title=like.${encodeURIComponent('d1%-probe%')}&select=id`);
  for (const e of (Array.isArray(stale) ? stale : [])) {
    await svc(`event_registrations?event_id=eq.${e.id}`, { method: 'DELETE', prefer: 'return=minimal' });
    await svc(`events?id=eq.${e.id}`, { method: 'DELETE', prefer: 'return=minimal' });
  }
}

await svc(`user_profiles?id=eq.${ids.attacker}`, {
  method: 'PATCH', body: { role: 'vendor' },
});

const mkEvent = async (title) => {
  const r = await svc('events', {
    method: 'POST',
    body: { title: `${MARK} ${title}`, event_date: '2026-12-01T10:00:00Z',
            vendor_id: ids.attacker, status: 'upcoming' },
  });
  const row = Array.isArray(r.body) ? r.body[0] : r.body;
  if (!row?.id) throw new Error(`fixture event failed: ${r.status} ${JSON.stringify(r.body)}`);
  cleanup.push(['events', row.id]);
  return row.id;
};

const eventA = await mkEvent('event A');
const eventB = await mkEvent('event B');

// A registration the attacker legitimately owns, on their own event.
const regRow = await svcJson('event_registrations', {
  method: 'POST',
  body: { event_id: eventA, user_id: ids.attacker, status: 'registered', paid: false },
});
const reg = Array.isArray(regRow) ? regRow[0] : regRow;
if (!reg?.id) throw new Error(`fixture registration failed: ${JSON.stringify(regRow)}`);
cleanup.push(['event_registrations', reg.id]);

const attackerJwt = await signIn('attacker');

/** Read a registration back through service_role — never trust the write's status. */
const readReg = async () => {
  const b = await svcJson(`event_registrations?id=eq.${reg.id}&select=user_id,event_id,paid,payment_id,qr_code,status,checked_in_at`);
  return Array.isArray(b) ? b[0] : b;
};

const before = await readReg();
check('fixture: the registration starts owned by the attacker themselves',
  before?.user_id === ids.attacker && before?.paid === false,
  `user_id=${before?.user_id === ids.attacker ? 'attacker' : before?.user_id} paid=${before?.paid}`);

// ── 1. the §25 PII path — reassigning whose registration it is ───────────────
section('1. A vendor cannot reassign a registration to another user');

// PRECONDITION. If the attacker can ALREADY read the victim through the view
// before attacking anything, they legitimately host an event the victim
// attends, and the PII assertion below proves nothing either way. Assert the
// clean precondition explicitly so this suite can never silently measure
// nothing — a vacuous test that reports PASS is worse than one that fails.
const baseline = await rest(attackerJwt,
  `event_attendee_profiles?id=eq.${ids.victim}&select=id`);
check('precondition: the attacker cannot already see the victim through the view',
  n(baseline.body) === 0,
  `status=${baseline.status} rows=${n(baseline.body)}${n(baseline.body) ? ' — FIXTURE CONTAMINATION, the PII assertion below is vacuous' : ''}`);

const rewrite = await mutate(attackerJwt, `event_registrations?id=eq.${reg.id}`,
  'PATCH', { user_id: ids.victim });
const afterRewrite = await readReg();

check('the vendor CANNOT rewrite user_id to the victim',
  afterRewrite?.user_id === ids.attacker,
  `status=${rewrite.status} user_id_now=${afterRewrite?.user_id === ids.victim ? 'VICTIM (LEAKED)' : 'attacker'}`);

// The consequence assertion. This is the one that matters: even if the write
// were somehow permitted, the view must not hand over the victim's PII.
const viewRead = await rest(attackerJwt,
  `event_attendee_profiles?id=eq.${ids.victim}&select=id,first_name,last_name,email`);
const leakedRow = Array.isArray(viewRead.body) ? viewRead.body[0] : null;

check('the victim\'s PII is NOT reachable through event_attendee_profiles',
  n(viewRead.body) === 0,
  `status=${viewRead.status} rows=${n(viewRead.body)}${leakedRow?.email ? ' EMAIL DISCLOSED' : ''}`);

// ── 2. K-04 as originally recorded — the billing self-grant ──────────────────
section('2. A client cannot decide that a registration was paid for');

// `paid` is tested ALONE, with no payment_id.
//
// An earlier revision of this probe sent { paid: true, payment_id: <random uuid> }
// and scored the resulting 409 as "blocked". That was a FALSE PASS:
// `event_registrations_payment_id_fkey` REFERENCES payments(id), so the random
// uuid was rejected by the FOREIGN KEY and the authorization control was never
// exercised at all. `paid` carries no constraint, so setting it alone tests the
// policy and nothing else.
const payAttempt = await mutate(attackerJwt, `event_registrations?id=eq.${reg.id}`,
  'PATCH', { paid: true });
const afterPay = await readReg();

check('the vendor CANNOT self-grant paid = true',
  afterPay?.paid === false,
  `status=${payAttempt.status} paid_now=${afterPay?.paid}`);

// INSERT arm: a member registering must not be able to create a paid row.
//
// This runs against its OWN event, not eventA. Assertion 1 above attempts to
// rewrite the fixture registration's user_id to the victim; where that attempt
// SUCCEEDS (i.e. pre-fix), eventA already holds a victim-owned row, so this
// INSERT collides on (event_id, user_id) and 409s while the read-back finds the
// rewritten row instead of the inserted one. That is contamination between
// assertions, not a result — the arm gets a clean event so it measures only the
// control it names.
const eventC = await mkEvent('event C');
const selfJwt = await signIn('victim');
const insAttempt = await mutate(selfJwt, 'event_registrations', 'POST',
  { event_id: eventC, user_id: ids.victim, status: 'registered', paid: true });
const insRow = await svcJson(`event_registrations?event_id=eq.${eventC}&user_id=eq.${ids.victim}&select=id,paid,payment_id`);
const created = Array.isArray(insRow) ? insRow[0] : null;
if (created?.id) cleanup.push(['event_registrations', created.id]);

check('a member INSERTing their own registration cannot set paid = true',
  !created || created.paid === false,
  created ? `status=${insAttempt.status} paid=${created.paid} payment_id=${created.payment_id}`
          : `status=${insAttempt.status} (insert refused outright)`);

// ── 3. the bearer credential and the event binding ───────────────────────────
section('3. The ticket credential and the event binding are frozen');

const qrAttempt = await mutate(attackerJwt, `event_registrations?id=eq.${reg.id}`,
  'PATCH', { qr_code: 'FORGED-TICKET-CODE' });
const afterQr = await readReg();
check('the vendor CANNOT rewrite qr_code (a bearer credential)',
  afterQr?.qr_code !== 'FORGED-TICKET-CODE',
  `status=${qrAttempt.status} qr_changed=${afterQr?.qr_code === 'FORGED-TICKET-CODE'}`);

const moveAttempt = await mutate(attackerJwt, `event_registrations?id=eq.${reg.id}`,
  'PATCH', { event_id: eventB });
const afterMove = await readReg();
check('the vendor CANNOT move the registration to another event',
  afterMove?.event_id === eventA,
  `status=${moveAttempt.status} event_now=${afterMove?.event_id === eventB ? 'EVENT B (moved)' : 'event A'}`);

// ── 4. REGRESSION — the legitimate operation must still work ─────────────────
// vendor_service.dart:90-93 sends exactly { checked_in_at, status }. If 138
// broke this, the fix would be worse than the defect. This assertion must pass
// BOTH before and after the migration.
section('4. REGRESSION — the vendor can still perform a real check-in');

const checkIn = await mutate(attackerJwt, `event_registrations?id=eq.${reg.id}`,
  'PATCH', { checked_in_at: '2026-12-01T10:05:00Z', status: 'attended' });
const afterCheckIn = await readReg();

check('the vendor CAN still check a registration in (status + checked_in_at)',
  landed(checkIn) && afterCheckIn?.status === 'attended' && afterCheckIn?.checked_in_at !== null,
  `status=${checkIn.status} affected=${checkIn.affected} status_now=${afterCheckIn?.status}`);

// ── cleanup ──────────────────────────────────────────────────────────────────
for (const [table, id] of cleanup.reverse()) {
  await svc(`${table}?id=eq.${id}`, { method: 'DELETE', prefer: 'return=minimal' });
}
await svc(`user_profiles?id=eq.${ids.attacker}`, {
  method: 'PATCH', body: { role: IDENT.attacker.role },
});

export default summary('K-04  event_registration integrity');
