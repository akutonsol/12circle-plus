// V5 P1 — the three security boundaries migrations 135 and 136 establish, live.
//
// Written because NO existing suite probed any of these surfaces. Verified before
// authoring: zero matches for `progress-photos`, `score_events` or
// `event_registrations` across every other supabase/tests/security/*.mjs. The
// static guards assert migration TEXT; only a request proves the policies, the
// column grants and PostgREST compose into an actual boundary.
//
//   QAX-SEC-09  an event host no longer reaches the whole user_profiles row,
//               and gets exactly five non-PHI columns through
//               event_attendee_profiles instead          (migration 135)
//   SEC-PHI-10  score_events requires an ACTIVE relationship (migration 136)
//   SEC-PHI-9   progress-photos requires an ACTIVE relationship (migration 136)
//
// ═══════════════════════════════════════════════════════════════════════════
// EVIDENCE SCOPE — READ THIS BEFORE CITING THIS SUITE
//
// This suite proves POST-FIX behaviour. It does NOT supply the "and the same
// probe demonstrably failed before the fix" half of QA_CLOSURE_STANDARD §5.2,
// because migrations 135/136 were already applied to QA before it was written,
// so the pre-fix state no longer exists there to probe. The pre-fix evidence
// that DOES exist is catalog-level, captured before application and recorded in
// docs/V5_PROGRAMME_DEFINITION.md §23.2.
//
// Obtaining the request-level pre-fix half would require temporarily reverting
// the policies on QA — i.e. deliberately reintroducing a PHI exposure on a
// shared environment. That is an authorization decision, not a test detail, and
// it is NOT taken here.
// ═══════════════════════════════════════════════════════════════════════════
//
//   node supabase/tests/security/d10-p1-profile-and-status-boundaries.mjs

import {
  URL_, ANON, SERVICE, IDENT, signIn, rest, svc, mutate,
  check, section, beginSuite, summary, blocked, n, loadIds,
} from './lib.mjs';

// POSITIVE allowlist, matching d07/d08. lib.mjs only BLOCKS the production ref,
// and "is not production" is not "is QA" — a third project would sail through.
// This is the most write-heavy suite in the directory (service_role inserts and
// deletes, a storage upload, and a PATCH that attempts first_name='PWNED' on a
// real profile row), so it takes the stronger guard.
const QA_REF = 'eyqtldjqpgpljlqvpowh';
if (!URL_.includes(QA_REF)) {
  console.error(`REFUSING TO RUN: "${URL_}" is not the 12 Circle QA project (${QA_REF}).`);
  process.exit(2);
}

// apikey: ANON, not SERVICE — this must be the request a phone makes, and the
// service-role key has no business on the wire here. Matches lib.mjs hdrs() and d07.
const H = (jwt) => ({ apikey: ANON, Authorization: `Bearer ${jwt}` });
const parse = async (r) => {
  const t = await r.text();
  let body; try { body = t ? JSON.parse(t) : null; } catch { body = t; }
  return { status: r.status, ok: r.ok, body };
};

const PHOTO_BUCKET = 'progress-photos';
const MARK = 'd10-probe';

beginSuite();
const ids = await loadIds();
const coachJwt    = await signIn('coach');
const attackerJwt = await signIn('attacker');

const COACH = ids.coach, VICTIM = ids.victim, HOST = ids.attacker;

// ── fixtures, arranged with service_role only ────────────────────────────────
// The whole suite is differential — only `status` changes between the positive
// and negative cases — so an INSERT that silently failed would leave NO row, the
// coach would be denied, and the negative assertion would pass while proving
// nothing about the status predicate. So the row is PROVED, not assumed.
async function setRelationship(status) {
  await svc(`coach_client_relationships?coach_id=eq.${COACH}&client_id=eq.${VICTIM}`, { method: 'DELETE' });
  if (status === null) return true;
  const ins = await svc('coach_client_relationships', {
    method: 'POST',
    body: { coach_id: COACH, client_id: VICTIM, status, initiated_by: 'coach' },
  });
  const back = await svc(`coach_client_relationships?coach_id=eq.${COACH}&client_id=eq.${VICTIM}&select=status`);
  const ok = ins.status < 300 && Array.isArray(back.body) && back.body[0]?.status === status;
  check(`fixture: the relationship is actually at status '${status}'`, ok,
    `insert=${ins.status} readback=${Array.isArray(back.body) ? back.body[0]?.status : 'none'}`);
  return ok;
}

async function cleanup() {
  await svc(`score_events?user_id=eq.${VICTIM}&dedup_key=eq.${MARK}`, { method: 'DELETE' });
  await svc(`event_registrations?user_id=eq.${VICTIM}`, { method: 'DELETE' });
  await svc(`events?vendor_id=eq.${HOST}&title=eq.${MARK}`, { method: 'DELETE' });
  await setRelationship(null);
}

await cleanup();

// ═════════════════════════════════════════════════════════════════════════════
section('SEC-PHI-10 — score_events requires an ACTIVE relationship');

// Column set read from the live QA catalog: category and action are both NOT NULL.
const se = await svc('score_events', {
  method: 'POST',
  body: { user_id: VICTIM, category: 'probe', action: MARK, points: 5, dedup_key: MARK },
});
check('fixture: a score event exists for the client', se.status < 300,
  `status=${se.status} ${se.status >= 300 ? JSON.stringify(se.body) : ''}`);

// 'cancelled' is the status the product actually writes on termination (025's
// cancelled_by/cancelled_at). 'ended' appears nowhere in the schema, so the
// earlier version never exercised a real terminal state.
for (const [status, shouldSee] of [['active', true], ['pending', false], ['cancelled', false]]) {
  await setRelationship(status);
  const r = await rest(coachJwt, `score_events?user_id=eq.${VICTIM}&dedup_key=eq.${MARK}&select=id`);
  // `status < 400` is load-bearing: n() returns 0 for an error body, so without
  // it a 500 raised from inside the RLS predicate — exactly the 22P02 regression
  // 136's fail-closed guard prevents — would score as a successful denial.
  const clean = r.status < 400;
  const saw = n(r.body) > 0;
  check(
    `relationship '${status}' → coach ${shouldSee ? 'READS' : 'is DENIED'} the client score event`,
    clean && saw === shouldSee,
    `status=${r.status} rows=${n(r.body)}`,
  );
}

// no relationship at all must fail closed, not error
await setRelationship(null);
const noRel = await rest(coachJwt, `score_events?user_id=eq.${VICTIM}&dedup_key=eq.${MARK}&select=id`);
check('no relationship at all → denied, and the request does NOT error',
  n(noRel.body) === 0 && noRel.status < 400, `status=${noRel.status} rows=${n(noRel.body)}`);

// ═════════════════════════════════════════════════════════════════════════════
section('QAX-SEC-09 — an event host loses the whole profile row');

const ev = await svc('events', {
  method: 'POST',
  body: { vendor_id: HOST, title: MARK, event_date: '2099-01-01' },
});
const eventId = Array.isArray(ev.body) ? ev.body[0]?.id : ev.body?.id;
check('fixture: the host owns an event', !!eventId, `status=${ev.status}`);

const reg = await svc('event_registrations', {
  method: 'POST',
  body: { event_id: eventId, user_id: VICTIM },
});
check('fixture: the client is registered for it', reg.status < 300, `status=${reg.status}`);

// THE BOUNDARY: the host must no longer read the base table.
const baseRow = await rest(attackerJwt, `user_profiles?id=eq.${VICTIM}&select=id`);
check('the event host can NO LONGER read the attendee user_profiles row',
  n(baseRow.body) === 0, `status=${baseRow.status} rows=${n(baseRow.body)}`);

// PHI specifically must be unreachable through the base table.
const phi = await rest(attackerJwt, `user_profiles?id=eq.${VICTIM}&select=parq_answers,weight_kg`);
check('PHI columns are unreachable through user_profiles for the host',
  n(phi.body) === 0 || phi.status >= 400, `status=${phi.status} rows=${n(phi.body)}`);

// The authorized path still works, and yields exactly the five columns.
const view = await rest(attackerJwt, `event_attendee_profiles?id=eq.${VICTIM}`);
check('the host DOES still read the attendee through event_attendee_profiles',
  n(view.body) === 1, `status=${view.status} rows=${n(view.body)}`);

if (n(view.body) === 1) {
  const cols = Object.keys(view.body[0]).sort();
  check('the view exposes exactly id, first_name, last_name, email, avatar_url',
    cols.join(',') === 'avatar_url,email,first_name,id,last_name', cols.join(','));
  for (const phiCol of ['parq_answers', 'weight_kg', 'goal_weight_kg', 'membership_tier',
                        'transformation_photo_urls', 'stripe_details_submitted']) {
    check(`the view carries no ${phiCol}`, !(phiCol in view.body[0]), 'absent');
  }
}

// Asking the view for a PHI column must fail, not silently succeed.
const viewPhi = await rest(attackerJwt, `event_attendee_profiles?id=eq.${VICTIM}&select=parq_answers`);
check('selecting a PHI column THROUGH the view is rejected', viewPhi.status >= 400,
  `status=${viewPhi.status}`);

// A stranger with no event relationship gets nothing.
const stranger = await rest(coachJwt, `event_attendee_profiles?id=eq.${VICTIM}`);
check('a user who hosts no event for the client reads nothing through the view',
  n(stranger.body) === 0, `status=${stranger.status} rows=${n(stranger.body)}`);

// The view is auto-updatable and runs security_invoker=off — writes must be refused.
const wr = await mutate(attackerJwt, `event_attendee_profiles?id=eq.${VICTIM}`, 'PATCH',
  { first_name: 'PWNED' });
// 403 specifically, not merely "an error": blocked() accepts any status >= 400,
// so a 405 or a 500 would pass and the grant hardening would go untested.
check('a write THROUGH the view is refused with 403 — the GRANT, not any error',
  wr.status === 403, `status=${wr.status} affected=${wr.affected}`);

const confirm = await svc(`user_profiles?id=eq.${VICTIM}&select=first_name`);
const stillOk = Array.isArray(confirm.body) && confirm.body[0]?.first_name !== 'PWNED';
check('and the underlying profile was NOT modified', stillOk, 'first_name intact');

// ═════════════════════════════════════════════════════════════════════════════
section('SEC-PHI-9 — progress-photos requires an ACTIVE relationship');

const victimJwt = await signIn('victim');
const objPath = `${VICTIM}/${MARK}.txt`;

await fetch(`${URL_}/storage/v1/object/${PHOTO_BUCKET}/${objPath}`,
  { method: 'DELETE', headers: H(victimJwt) }).then(parse).catch(() => null);

const up = await fetch(`${URL_}/storage/v1/object/${PHOTO_BUCKET}/${objPath}`, {
  method: 'POST',
  headers: { ...H(victimJwt), 'Content-Type': 'text/plain' },
  body: 'probe',
}).then(parse);
check('fixture: the client owns an object in progress-photos', up.status < 300, `status=${up.status}`);

const listAs = async (jwt) => fetch(`${URL_}/storage/v1/object/list/${PHOTO_BUCKET}`, {
  method: 'POST',
  headers: { ...H(jwt), 'Content-Type': 'application/json' },
  body: JSON.stringify({ prefix: `${VICTIM}/`, limit: 100 }),
}).then(parse);

for (const [status, shouldSee] of [['active', true], ['pending', false], ['cancelled', false]]) {
  await setRelationship(status);
  const l = await listAs(coachJwt);
  const clean = l.status < 400;   // see the note in the score_events loop
  const saw = Array.isArray(l.body) && l.body.some(o => o.name?.includes(MARK));
  check(`relationship '${status}' → coach ${shouldSee ? 'LISTS' : 'is DENIED'} the client photo`,
    clean && saw === shouldSee, `status=${l.status} objects=${n(l.body)}`);
}

await setRelationship(null);
const lNone = await listAs(coachJwt);
const sawNone = Array.isArray(lNone.body) && lNone.body.some(o => o.name?.includes(MARK));
check('no relationship at all → denied, and the request does NOT error',
  !sawNone && lNone.status < 400, `status=${lNone.status}`);

// The owner must still reach their own photo — the fix must not break self-access.
const lOwn = await listAs(victimJwt);
const sawOwn = Array.isArray(lOwn.body) && lOwn.body.some(o => o.name?.includes(MARK));
check('the client still lists their OWN photo (self-access not broken)', sawOwn,
  `status=${lOwn.status}`);

// ═════════════════════════════════════════════════════════════════════════════
section("136's fail-closed guard — a non-uuid folder must DENY, never raise");

// This is the property migration 136 exists to protect and which nothing else
// tested: (storage.foldername(name))[1] is user-controlled text, so a bare
// ::uuid cast would raise 22P02 from INSIDE an RLS predicate — a query error,
// not a denial. service_role places the object (the owner policy would refuse a
// non-uuid folder), then the coach lists it: the policy must evaluate
// is_active_coach_of('not-a-uuid') and get false, cleanly.
const badPath = `not-a-uuid/${MARK}.txt`;
const upBad = await fetch(`${URL_}/storage/v1/object/${PHOTO_BUCKET}/${badPath}`, {
  method: 'POST',
  headers: { apikey: SERVICE, Authorization: `Bearer ${SERVICE}`, 'Content-Type': 'text/plain' },
  body: 'probe',
}).then(parse);
check('fixture: an object sits at a NON-uuid folder path', upBad.status < 300, `status=${upBad.status}`);

await setRelationship('active');   // an ACTIVE coach, so only the guard can deny
const badList = await fetch(`${URL_}/storage/v1/object/list/${PHOTO_BUCKET}`, {
  method: 'POST',
  headers: { ...H(coachJwt), 'Content-Type': 'application/json' },
  body: JSON.stringify({ prefix: 'not-a-uuid/', limit: 100 }),
}).then(parse);
const badSeen = Array.isArray(badList.body) && badList.body.some(o => o.name?.includes(MARK));
check('a non-uuid folder DENIES cleanly — no rows AND no error (not 22P02)',
  !badSeen && badList.status < 400, `status=${badList.status} objects=${n(badList.body)}`);

await fetch(`${URL_}/storage/v1/object/${PHOTO_BUCKET}/${badPath}`,
  { method: 'DELETE', headers: { apikey: SERVICE, Authorization: `Bearer ${SERVICE}` } })
  .then(parse).catch(() => null);

// ═════════════════════════════════════════════════════════════════════════════
section('cleanup');
await fetch(`${URL_}/storage/v1/object/${PHOTO_BUCKET}/${objPath}`,
  { method: 'DELETE', headers: H(victimJwt) }).then(parse).catch(() => null);
await cleanup();

const leftScore = await svc(`score_events?user_id=eq.${VICTIM}&dedup_key=eq.${MARK}&select=id`);
const leftEvent = await svc(`events?vendor_id=eq.${HOST}&title=eq.${MARK}&select=id`);
check('every fixture removed, proved by a read',
  n(leftScore.body) === 0 && n(leftEvent.body) === 0,
  `score=${n(leftScore.body)} events=${n(leftEvent.body)}`);

export default summary('P1 profile + status boundaries');
