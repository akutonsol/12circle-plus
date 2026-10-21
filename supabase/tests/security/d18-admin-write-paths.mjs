// D18 · THE TWO GOVERNED EDIT PATHS, and the gate divergence beside them.
//
// WHY THIS SUITE EXISTS. `admin_update_event` (165) and `admin_update_user_name` (161)
// had been applied for several migrations with NO caller: the Ecosystem page showed only
// an aggregate, and the People row had no action. V5 §188 wired both, so each now needs
// the rung the QA_CLOSURE_STANDARD demands of an authorization change — live evidence,
// not a status code.
//
// WHY EVERY RESULT IS READ BACK FROM THE ROW. A PostgREST RPC that RAISEs returns 4xx,
// but one that silently does nothing returns 204 — and so does one that worked. The
// status cannot distinguish "refused", "no-op" and "saved", so every assertion here is
// BEFORE → ATTEMPT → AFTER → ASSERT against the stored row.
//
// THE ASSERTION THAT MATTERS MOST IS NOT ABOUT MY CODE. §188 found that
// `admin_set_user_role` (115:363) gates on the legacy `is_admin()` — a
// `user_profiles.role = 'admin'` test — and NOT on the capability matrix that gates every
// other Admin surface. That was read off the source, and source-reading is how three
// earlier claims in this programme turned out to be wrong. Section 3 proves it live: a
// role holding `Users·update` can rename a user and CANNOT change a role. If that pair
// ever stops holding, the finding is stale and the owner question it raises has moved.
import { IDENT, signIn, svc, rpc, check, checkNoWrite,
         section, summary, beginSuite, n } from './lib.mjs';

const ONE = (b) => (Array.isArray(b) ? b[0] : b) || {};

async function uidOf(key) {
  const r = await svc(`user_profiles?email=eq.${encodeURIComponent(IDENT[key].email)}&select=id`);
  return ONE(r.body).id;
}
async function assign(uid, role) {
  await svc(`admin_role_assignments?user_id=eq.${uid}`, { method: 'DELETE' });
  await svc('admin_role_assignments', { method: 'POST', body: { user_id: uid, admin_role: role } });
}
const unassign = async (uid) =>
  svc(`admin_role_assignments?user_id=eq.${uid}`, { method: 'DELETE' });

// EVERY CALL SUPPLIES ALL THREE ARGUMENTS, and that is a contract fact rather than a
// convention: 161 declares `p_user_id, p_first_name, p_last_name` with NO DEFAULTs, so a
// caller that omits one does not get a validation error — PostgREST cannot resolve the
// signature at all and answers 404, which reads like "no such function" rather than
// "you forgot a field". The first draft of this suite omitted `p_last_name` and scored
// four spurious failures that looked like a broken gate. The Dart caller
// (`AdminMetricsService.updateUserName`) already passes all three, nulls included; this
// helper makes the test call it the way the app does.
const rename = (who, userId, { first = null, last = null } = {}) =>
  rpc(who, 'admin_update_user_name',
    { p_user_id: userId, p_first_name: first, p_last_name: last });

const readEvent = async (id) => ONE((await svc(
  `events?id=eq.${id}&select=title,location,description,event_date,max_capacity,status,price,is_free`)).body);
const readName = async (id) => ONE((await svc(
  `user_profiles?id=eq.${id}&select=first_name,last_name,role`)).body);

beginSuite();

async function run() {
  const victim   = await signIn('victim');
  const vUid     = await uidOf('victim');
  const subject  = await uidOf('attacker');   // the user being renamed, never the actor
  const FIXTURE  = 'QA-D18 fixture event';
  let eventId;
  // Captured before anything is written, so the cleanup restores what was THERE rather
  // than a plausible-looking guess. A fixture teardown that invents a value is a quiet
  // data edit dressed up as hygiene.
  const original = await readName(subject);

  try {
    // ── arrange ───────────────────────────────────────────────────────────
    await svc(`events?title=eq.${encodeURIComponent(FIXTURE)}`, { method: 'DELETE' });
    const made = await svc('events', { method: 'POST', body: {
      title: FIXTURE, description: 'original description', location: 'Original location',
      event_date: '2027-03-01T10:00:00Z', max_capacity: 50, price: 25, is_free: false,
      status: 'upcoming' } });
    eventId = ONE(made.body).id;
    check('arranged: a fixture event with a recorded price, capacity and location',
      Boolean(eventId), `event=${eventId}`);

    const before0 = await readEvent(eventId);

    // ── 1 · admin_update_event ────────────────────────────────────────────
    section('events · admin_update_event is gated, and gated on `update` specifically');

    // `content_editor` holds Events·CREATE and Events·UPDATE both, so it cannot
    // distinguish the two verbs. `support` holds Users·update and NO Events verb, which
    // is the role that proves the Events gate is doing the work.
    await assign(vUid, 'support');
    const deniedEdit = await rpc(victim, 'admin_update_event',
      { p_event_id: eventId, p_title: 'SEIZED BY AN UNAUTHORIZED ROLE' });
    const afterDenied = await readEvent(eventId);
    check('a role WITHOUT Events·update cannot edit an event — proved by re-reading the ' +
          'stored title, not by the RPC status',
      afterDenied.title === FIXTURE,
      `status=${deniedEdit.status} title=${JSON.stringify(afterDenied.title)}`);
    checkNoWrite('…and nothing else on the row moved either', {
      before: before0.location, after: afterDenied.location, status: deniedEdit.status });

    await assign(vUid, 'content_editor');
    const okEdit = await rpc(victim, 'admin_update_event',
      { p_event_id: eventId, p_title: 'QA-D18 renamed event' });
    const afterEdit = await readEvent(eventId);
    check('a role WITH Events·update edits it, and the stored title actually CHANGED',
      okEdit.status < 300 && afterEdit.title === 'QA-D18 renamed event',
      `status=${okEdit.status} title=${JSON.stringify(afterEdit.title)}`);

    // THE CLAIM THE EDIT FORM RELIES ON. The form sends null for every field the operator
    // did not touch. If a null argument blanked its column, that design would quietly
    // erase three fields on every save — so this is the assertion the UI stands on.
    check('an OMITTED field is left alone — a null argument cannot blank a column, ' +
          'which is what lets the form send only what changed',
      afterEdit.location === before0.location &&
      afterEdit.description === before0.description &&
      afterEdit.max_capacity === before0.max_capacity,
      `location=${JSON.stringify(afterEdit.location)} ` +
      `description kept=${afterEdit.description === before0.description} ` +
      `capacity=${afterEdit.max_capacity}`);

    // AND THE MONETARY FIELDS STAY OUT OF REACH. 165 has no price/is_free parameter, so
    // the only way to prove an Admin cannot re-price an event is to try.
    const priceTry = await rpc(victim, 'admin_update_event',
      { p_event_id: eventId, p_price: 0, p_is_free: true });
    const afterPrice = await readEvent(eventId);
    check('an Admin cannot re-price or free an event through this path — the function ' +
          'has no such parameter and the stored price is unmoved',
      Number(afterPrice.price) === Number(before0.price) &&
      afterPrice.is_free === before0.is_free,
      `status=${priceTry.status} price=${afterPrice.price} is_free=${afterPrice.is_free}`);

    const negCap = await rpc(victim, 'admin_update_event',
      { p_event_id: eventId, p_max_capacity: -1 });
    const afterNeg = await readEvent(eventId);
    check('a negative capacity is REFUSED and the stored capacity is unchanged',
      negCap.status >= 400 && afterNeg.max_capacity === before0.max_capacity,
      `status=${negCap.status} capacity=${afterNeg.max_capacity}`);

    const noSuch = await rpc(victim, 'admin_update_event',
      { p_event_id: '00000000-0000-0000-0000-000000000000', p_title: 'ghost' });
    check('editing an event that does not exist is REFUSED, not silently accepted',
      noSuch.status >= 400, `status=${noSuch.status}`);

    // ── 2 · admin_update_user_name ────────────────────────────────────────
    section('people · admin_update_user_name is gated, and records columns not values');

    const nameBefore = await readName(subject);
    check('arranged: the subject has a readable name to change',
      Boolean(nameBefore.first_name) || Boolean(nameBefore.last_name),
      `first=${Boolean(nameBefore.first_name)} last=${Boolean(nameBefore.last_name)}`);

    // content_editor holds NO Users verb, so it is the denial case here — the mirror of
    // section 1, where support was the one without Events.
    const deniedName = await rename(victim, subject, { first: 'Seized' });
    const afterDeniedName = await readName(subject);
    check('a role WITHOUT Users·update cannot rename a user — proved by re-reading ' +
          'first_name',
      afterDeniedName.first_name === nameBefore.first_name,
      `status=${deniedName.status} first_name unchanged=${afterDeniedName.first_name === nameBefore.first_name}`);

    await assign(vUid, 'support');          // holds Users·update
    const auditBefore = await svc(
      "audit_events?action=eq.user_profiles.name.set&select=id&order=occurred_at.desc&limit=1");
    const okName = await rename(victim, subject, { first: 'QA-D18' });
    const afterName = await readName(subject);
    check('a role WITH Users·update renames the user, and the stored first_name CHANGED',
      okName.status < 300 && afterName.first_name === 'QA-D18',
      `status=${okName.status} first_name=${JSON.stringify(afterName.first_name)}`);
    check('…and the untouched last_name is left alone, not blanked',
      afterName.last_name === nameBefore.last_name,
      `last_name kept=${afterName.last_name === nameBefore.last_name}`);

    const blank = await rename(victim, subject, { first: '   ', last: '  ' });
    const afterBlank = await readName(subject);
    check('a whitespace-only name is REFUSED — a trimmed blank is not a name',
      blank.status >= 400 && afterBlank.first_name === 'QA-D18',
      `status=${blank.status} first_name=${JSON.stringify(afterBlank.first_name)}`);

    // The signature fact, asserted rather than merely worked around — a caller that
    // omits an argument gets an UNRESOLVABLE SIGNATURE, not a field-level complaint.
    const omitted = await rpc(victim, 'admin_update_user_name',
      { p_user_id: subject, p_first_name: 'QA-D18-omit' });
    const afterOmitted = await readName(subject);
    check('omitting p_last_name is an unresolvable signature, not a partial update — 161 ' +
          'declares no DEFAULTs, so every caller must send all three',
      omitted.status === 404 && afterOmitted.first_name === 'QA-D18',
      `status=${omitted.status} first_name=${JSON.stringify(afterOmitted.first_name)}`);

    const long = await rename(victim, subject, { first: 'x'.repeat(101) });
    const afterLong = await readName(subject);
    check('a name over 100 characters is REFUSED and nothing was stored',
      long.status >= 400 && afterLong.first_name === 'QA-D18',
      `status=${long.status} first_name len=${(afterLong.first_name || '').length}`);

    // THE AUDIT ROW NAMES THE COLUMN AND NOT THE VALUE. 161 passes p_delta => NULL on
    // purpose: the values identify the pseudonymous subject of its own audit row, so a
    // delta would undo the pseudonymisation the row exists to provide.
    const audit = await svc('audit_events?action=eq.user_profiles.name.set' +
      '&select=id,changed_columns,delta,subject_pseudonym&order=occurred_at.desc&limit=1');
    const row = ONE(audit.body);
    const isNew = row.id && row.id !== ONE(auditBefore.body).id;
    check('the rename emitted a NEW audit row', Boolean(isNew),
      `id=${row.id} was=${ONE(auditBefore.body).id}`);
    check('…which records the CHANGED COLUMN and carries no delta — the values would ' +
          're-identify the pseudonymous subject of this very row',
      Array.isArray(row.changed_columns) &&
      row.changed_columns.includes('first_name') &&
      (row.delta === null || row.delta === undefined),
      `changed_columns=${JSON.stringify(row.changed_columns)} delta=${JSON.stringify(row.delta)}`);
    check('…and no stored audit value contains the name that was written',
      JSON.stringify(row).includes('QA-D18') === false,
      `row mentions the written value=${JSON.stringify(row).includes('QA-D18')}`);

    // ── 3 · the gate divergence, proved rather than read off the source ────
    section('the `admin_set_user_role` gate is NOT the capability matrix');

    // The caller here holds Users·update and has just proved it by renaming someone.
    const beforeRole = (await readName(subject)).role;
    const roleTry = await rpc(victim, 'admin_set_user_role',
      { target_user: subject, new_role: 'admin' });
    const afterRole = (await readName(subject)).role;
    // OWNER DECISION Q8 RULED ON THIS, and the assertion's standing changed with it. It
    // began as evidence for an open question — can "Change role" be wired? — and is now the
    // ratchet for the answer: "Keep Change Role restricted/unbuilt. Do NOT widen
    // admin_set_user_role to Users·Update holders. Users·Update does not implicitly
    // confer authorization-management authority. Preserve the existing 403 behavior."
    // So this failing no longer means the finding is stale; it means a ruled authorization
    // boundary moved.
    check('OWNER Q8 · the SAME role that may rename a user may NOT change a role — ' +
          'Users·update does not confer authorization-management authority, and this ' +
          '403 is the behaviour the owner ruled is to be preserved',
      roleTry.status >= 400 && afterRole === beforeRole,
      `status=${roleTry.status} role=${afterRole} (was ${beforeRole})`);
    check('…and the refusal left no partial escalation behind — the subject is not admin',
      afterRole !== 'admin', `role=${afterRole}`);

    // ── 4 · neither path is reachable unauthenticated ──────────────────────
    section('no governed edit path is reachable without a session');
    for (const [fn, args] of [
      ['admin_update_event', { p_event_id: eventId, p_title: 'anon' }],
      ['admin_update_user_name',
        { p_user_id: subject, p_first_name: 'anon', p_last_name: null }],
    ]) {
      // `'anon'` and not `null`: hdrs() maps 'anon' to the anon key, while null would
      // send `Bearer null` — a MALFORMED TOKEN test, which proves something weaker.
      const r = await rpc('anon', fn, args);
      check(`${fn} refuses an anonymous caller`, r.status >= 400, `status=${r.status}`);
    }
    const stillNamed = await readName(subject);
    const stillTitled = await readEvent(eventId);
    check('…and the anonymous attempts changed nothing',
      stillNamed.first_name === 'QA-D18' && stillTitled.title === 'QA-D18 renamed event',
      `first_name=${JSON.stringify(stillNamed.first_name)} title=${JSON.stringify(stillTitled.title)}`);
  } finally {
    // Restore the subject's name, drop the fixture event, drop the role assignment.
    if (original.first_name !== undefined) {
      await svc(`user_profiles?id=eq.${subject}`, { method: 'PATCH',
        body: { first_name: original.first_name, last_name: original.last_name } });
    }
    await svc(`events?title=like.QA-D18*`, { method: 'DELETE' });
    await unassign(vUid);
  }
  return summary('D18 · governed admin edit paths');
}

export default await run();
