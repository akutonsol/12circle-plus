// N-07 — assessment access is coach-of-record only, and every read is logged.
//
// ── WHY ─────────────────────────────────────────────────────────────────────
// Intake writes 32 columns onto `user_profiles`, including parq_answers,
// risk_level, risk_score, medical_conditions, has_injuries, injury_locations,
// injury_description and food_allergies. Migration 102's SELECT policy grants
// the WHOLE ROW to:
//
//     id = auth.uid()
//     OR public.is_active_coach_of(id)
//     OR public.is_team_lead_of(id)     -- a team ROSTER
//     OR public.hosts_event_for(id)     -- an attendee LIST
//
// 102's own header shows the last two were added so a head coach could see a
// roster and a vendor an attendee list — that is, for NAMES. They carry the
// medical columns with them regardless. N-07's copy, "Only you and Amara can
// see this", is therefore false on the base-table path.
//
// get_client_assessment() is the narrow path: active coach ONLY, and it writes
// an audit row before it returns. This suite asserts that, and asserts the
// base-table exposure separately so the residual finding stays visible rather
// than being masked by the new RPC.
//
// ── STATUS — CORRECTED 2026-09-30 (V5 §65).  THE MIGRATION IS APPLIED. ──────
// This block used to read "authored and NOT applied … this suite fails by
// design".  `docs/proposed/N07_assessment_access.sql` was numbered, landed and
// applied as migration **140**, with **141** correcting `sleep_hours` to `text`
// (140 declared it `numeric`, which raised 42804 on every call).  The suite is
// registered in run.mjs under owner decision OD-56 = A and passes **18/18**.
//
// A FAILURE HERE IS A REGRESSION, not the pre-fix reading.
import { URL_, rest, rpc, svc, mutate, blocked, signIn,
         check, section, summary, n, loadIds } from './lib.mjs';

// POSITIVE allowlist, matching d07/d08/d10/d11. `lib.mjs` only BLOCKS the
// production ref, and "is not production" is not "is QA" — a third project
// would sail straight through.
//
// This suite needs the guard more than any other in the directory, because its
// arrange step issues service_role DELETEs against `coach_client_relationships`
// and `assessment_access_log` filtered only by client_id. Pointed at the wrong
// project that is destructive, not merely wrong.
const QA_REF = 'eyqtldjqpgpljlqvpowh';
if (!URL_.includes(QA_REF)) {
  console.error(`REFUSING TO RUN: "${URL_}" is not the 12 Circle QA project (${QA_REF}).`);
  process.exit(2);
}

// ── BEFORE THIS SUITE MAY BE REGISTERED IN run.mjs ──────────────────────────
// Two things must be true, and neither is today:
//
//   1. N-07's migration must be numbered, applied and its objects present.
//      `get_client_assessment()` and `assessment_access_log` do NOT exist —
//      zero references in supabase/migrations, zero in the live QA catalog —
//      so all seven RPC assertions below would fail on a missing function
//      rather than on a boundary. N-07 is blocked on owner decision OD-30
//      ("coach access to PAR-Q"), so there is no date for this.
//
//   2. The arrange step must stop mutating SHARED fixture state. `reset()`
//      DELETEs every coach_client_relationships row for the victim — the same
//      fixture d01 asserts on. That is the cross-suite contamination class that
//      made a d11 assertion vacuous in V5 §33.4, and it must be fixed before
//      this suite runs alongside the others, not after.
//
// Until both hold, this file is committed but NOT registered: it is preserved
// evidence, not part of the green suite. Registering it today would add no
// coverage of anything that exists and would make CI permanently red.
// ─────────────────────────────────────────────────────────────────────────────

const REL  = 'coach_client_relationships';
const LOG  = 'assessment_access_log';
const MED  = 'parq_answers,risk_level,risk_score,medical_conditions,has_injuries,' +
             'injury_locations,injury_description,food_allergies';
const ids  = await loadIds();

// Arrange: coach is coach-of-record for victim; attacker is a client with no
// relationship to victim at all.
// Scoped to the two coach/client PAIRS this suite owns.
//
// This previously deleted EVERY coach_client_relationships row for the victim:
//
//     await svc(`${REL}?client_id=eq.${ids.victim}`, { method: 'DELETE' });
//
// `coach_client_relationships` is the authorization root, and `d01` asserts on
// the same fixture. A blanket delete there is the cross-suite contamination
// class that made a `d11` assertion vacuous in V5 §33.4 and broke `FG-2a` in CI
// twice — a suite must own its fixtures or leave them alone, never both.
//
// `assessment_access_log` IS wholly owned by this suite: migration 140 creates
// it, only `get_client_assessment()` writes it, and no other suite reads it — so
// clearing the victim's rows there is scoped by construction.
const reset = async () => {
  for (const coach of [ids.coach, ids.attacker]) {
    await svc(`${REL}?client_id=eq.${ids.victim}&coach_id=eq.${coach}`,
              { method: 'DELETE' });
  }
  await svc(`${LOG}?client_id=eq.${ids.victim}`, { method: 'DELETE' });
};
await reset();
// NOTE: `svc()` stringifies `body` itself (lib.mjs:156). Passing an
// already-stringified string double-encodes it, PostgREST rejects the write, and
// because this call's result was discarded the arrange silently did nothing --
// leaving no relationship, so section 1's coach was 403'd and every audit
// assertion failed downstream. The result is now checked.
{
  const mk = await svc(REL, { method: 'POST',
    body: { coach_id: ids.coach, client_id: ids.victim,
            status: 'active', initiated_by: 'coach' } });
  if (mk.status >= 300) {
    throw new Error(`arrange failed: could not make the coach coach-of-record — ${mk.status} ${JSON.stringify(mk.body)}`);
  }
}

// These MUST be captured. `lib.mjs`'s `hdrs()` treats `who` as 'anon' | 'service'
// | <a JWT> — anything else is sent verbatim as `Authorization: Bearer <who>`.
// This file previously called signIn() and DISCARDED the tokens, then passed the
// literal strings 'coach'/'attacker'/'victim'/'admin', so every request became
// `Bearer coach` and QA answered 401 to all eighteen assertions. Seven "passed"
// on that 401 — a blanket auth rejection scored as a boundary decision. The bug
// survived because the suite was authored and never executed (N07_IMPLEMENTATION_
// STATUS.md §5: "None of these has been executed").
const coachJwt    = await signIn('coach');
const attackerJwt = await signIn('attacker');
const victimJwt   = await signIn('victim');
const adminJwt    = await signIn('admin');

// ═══ 1. the assigned coach ═════════════════════════════════════════════════
section('1. Assigned coach can read the assessment (QA-1)');
{
  const r = await rpc(coachJwt, 'get_client_assessment', { p_client: ids.victim });
  check('assigned coach receives the assessment', r.status < 300 && n(r.body) === 1,
        `status=${r.status} rows=${n(r.body)}`);
  const row = Array.isArray(r.body) ? r.body[0] : r.body;
  check('assessment carries the safety-critical fields',
        !!row && 'parq_answers' in row && 'injury_description' in row && 'risk_level' in row,
        row ? Object.keys(row).length + ' cols' : 'no row');
}

// ═══ 2. an unassigned coach ════════════════════════════════════════════════
section('2. Unassigned callers are refused (QA-2)');
{
  const a = await rpc(attackerJwt, 'get_client_assessment', { p_client: ids.victim });
  check('client with no relationship is refused', a.status >= 400, `status=${a.status}`);

  const an = await rpc('anon', 'get_client_assessment', { p_client: ids.victim });
  check('anon is refused', an.status >= 400, `status=${an.status}`);

  // Ending the relationship must revoke access immediately.
  await svc(`${REL}?client_id=eq.${ids.victim}`, { method: 'PATCH',
            body: { status: 'ended' } });
  const after = await rpc(coachJwt, 'get_client_assessment', { p_client: ids.victim });
  check('a coach whose relationship ended is refused', after.status >= 400, `status=${after.status}`);
  await svc(`${REL}?client_id=eq.${ids.victim}`, { method: 'PATCH',
            body: { status: 'active' } });
}

// ═══ 3. the client's own access is unchanged ═══════════════════════════════
section("3. The client still reads their own record (QA-3)");
{
  const own = await rest(victimJwt, `user_profiles?id=eq.${ids.victim}&select=${MED}`);
  check('client reads their own assessment fields', own.status < 300 && n(own.body) === 1,
        `status=${own.status} rows=${n(own.body)}`);
}

// ═══ 4. honest emptiness ═══════════════════════════════════════════════════
section('4. Missing assessment data is reported honestly (QA-4)');
{
  const r = await rpc(coachJwt, 'get_client_assessment', { p_client: ids.victim });
  const row = Array.isArray(r.body) ? r.body[0] : r.body;
  check('has_assessment is present and boolean',
        !!row && typeof row.has_assessment === 'boolean', `value=${row && row.has_assessment}`);

  // A client the coach is assigned to but who has no profile row at all must
  // yield zero rows — "no assessment on file", never an empty-looking one.
  const ghost = '00000000-0000-0000-0000-0000000000ff';
  await svc(REL, { method: 'POST',
    body: { coach_id: ids.coach, client_id: ghost, status: 'active', initiated_by: 'coach' } });
  const g = await rpc(coachJwt, 'get_client_assessment', { p_client: ghost });
  check('absent profile returns no row rather than a blank assessment',
        g.status >= 400 || n(g.body) === 0, `status=${g.status} rows=${n(g.body)}`);
  await svc(`${REL}?client_id=eq.${ghost}`, { method: 'DELETE' });
}

// ═══ 5. no alternate route ═════════════════════════════════════════════════
section('5. No leak through an alternate route (QA-7)');
{
  const direct = await rest(attackerJwt, `user_profiles?id=eq.${ids.victim}&select=${MED}`);
  check('unassigned client cannot read medical columns directly',
        direct.status >= 400 || n(direct.body) === 0,
        `status=${direct.status} rows=${n(direct.body)}`);

  const anon = await rest('anon', `user_profiles?id=eq.${ids.victim}&select=${MED}`);
  check('anon cannot read medical columns directly',
        anon.status >= 400 || n(anon.body) === 0, `status=${anon.status} rows=${n(anon.body)}`);

  // The view used for names must not carry clinical columns.
  const pv = await rest(attackerJwt, `public_profiles?id=eq.${ids.victim}&select=*`);
  const leaked = Array.isArray(pv.body) && pv.body[0]
    ? Object.keys(pv.body[0]).filter(k => MED.split(',').includes(k)) : [];
  check('public_profiles projects no clinical column', leaked.length === 0, leaked.join(',') || 'none');
}

// ═══ 6. the audit row ══════════════════════════════════════════════════════
section('6. Access is actually logged, and the log is honest (QA-8)');
{
  await svc(`${LOG}?client_id=eq.${ids.victim}`, { method: 'DELETE' });
  await rpc(coachJwt, 'get_client_assessment', { p_client: ids.victim });

  const rows = await svc(`${LOG}?client_id=eq.${ids.victim}&select=coach_id,client_id,event,accessed_at`);
  const row  = Array.isArray(rows.body) ? rows.body[0] : null;
  check('an audit row was persisted', n(rows.body) === 1, `rows=${n(rows.body)}`);
  check('the audit row names the coach, the client and the event',
        !!row && row.coach_id === ids.coach && row.client_id === ids.victim
              && row.event === 'assessment_view' && !!row.accessed_at,
        row ? JSON.stringify(row) : 'none');

  // The subject can inspect who opened their record — this is what makes the
  // on-screen privacy claim verifiable rather than merely asserted.
  const mine = await rest(victimJwt, `${LOG}?select=coach_id,event,accessed_at`);
  check('the client can read their own access log', mine.status < 300 && n(mine.body) >= 1,
        `status=${mine.status} rows=${n(mine.body)}`);

  const other = await rest(attackerJwt, `${LOG}?client_id=eq.${ids.victim}&select=coach_id`);
  check('a third party cannot read the log', other.status >= 400 || n(other.body) === 0,
        `status=${other.status} rows=${n(other.body)}`);

  // An audit trail a caller can edit or erase is not an audit trail.
  const upd = await mutate(coachJwt, `${LOG}?client_id=eq.${ids.victim}`, 'PATCH',
                           { event: 'assessment_view' });
  check('nobody can UPDATE an audit row', blocked(upd), `status=${upd.status} affected=${upd.affected}`);
  const del = await mutate(coachJwt, `${LOG}?client_id=eq.${ids.victim}`, 'DELETE');
  check('nobody can DELETE an audit row', blocked(del), `status=${del.status} affected=${del.affected}`);
}

// ═══ 7. the residual base-table exposure ═══════════════════════════════════
section('7. The base-table path — was a residual finding, now CLOSED');
{
  // This was written as a KNOWN-FAILING assertion: when d09 was authored, migration
  // 102's SELECT policy still carried `is_team_lead_of(id)` and `hosts_event_for(id)`,
  // so a team lead received the whole row including the clinical columns. The comment
  // here used to read "EXPECTED TO FAIL until the owner rules on the base-table
  // policy".
  //
  // That ruling was made and implemented while this file sat unregistered:
  // migration 132 removed the team-lead arm and 135 removed the event-host arm
  // (V5 §21.2, §43.3). The live QA policy is now
  // `USING ((id = auth.uid()) OR is_active_coach_of(id))`, and this assertion
  // PASSES — first observed 2026-09-29 at 18/18.
  //
  // It is kept, not deleted: it is now a ratchet. If either arm is ever added back,
  // this is the assertion that fails.
  const lead = await rest(adminJwt, `user_profiles?id=eq.${ids.victim}&select=${MED}`);
  check('S-N07-a  a team lead cannot read a member\'s medical columns',
        lead.status >= 400 || n(lead.body) === 0,
        `status=${lead.status} rows=${n(lead.body)} — migrations 132/135 removed the team-lead and event-host arms`);
}

await reset();
export default summary('N-07 assessment access');
