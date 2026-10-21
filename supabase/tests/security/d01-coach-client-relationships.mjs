// D-01 (P0) — coach_client_relationships is the AUTHORIZATION ROOT.
//
// Before migration 113 the table had no RLS. Any caller holding the published
// anon key could POST {coach_id: self, client_id: victim, status: 'active'} and
// is_active_coach_of(victim) flipped false -> true, which through migrations 100
// and 102 handed over the victim's entire health record and PII profile.
//
// This suite asserts the SECURE state, so it fails loudly if 113 is ever rolled
// back, or if a future policy re-opens any leg of the chain.
import { rest, rpc, svc, mutate, blocked, landed, signIn,
         check, section, summary, n, loadIds } from './lib.mjs';

const T = 'coach_client_relationships';
const COLS = 'id,coach_id,client_id,status,initiated_by,client_source';
const ids = await loadIds();

const reset = async () => {
  await svc(`${T}?client_id=eq.${ids.victim}`,  { method: 'DELETE' });
  await svc(`${T}?client_id=eq.${ids.attacker}`, { method: 'DELETE' });
  await svc(`${T}?coach_id=eq.${ids.attacker}`,  { method: 'DELETE' });
};
await reset();

const attacker = await signIn('attacker');
const coach    = await signIn('coach');
const victim   = await signIn('victim');
const now      = () => new Date().toISOString();

// ═══ 1. anonymous ══════════════════════════════════════════════════════════
section('1. Anonymous access to the authorization table');
{
  const r = await rest('anon', `${T}?select=${COLS}`);
  check('anon cannot SELECT relationships', r.status >= 400 || n(r.body) === 0,
        `status=${r.status} rows=${n(r.body)}`);

  const i = await mutate('anon', T, 'POST',
    { coach_id: ids.attacker, client_id: ids.victim, status: 'active' });
  check('anon cannot INSERT a relationship', blocked(i), `status=${i.status}`);

  const u = await mutate('anon', `${T}?status=eq.active`, 'PATCH', { status: 'cancelled' });
  check('anon cannot UPDATE a relationship', blocked(u), `status=${u.status} affected=${u.affected}`);

  const d = await mutate('anon', `${T}?status=not.is.null`, 'DELETE');
  check('anon cannot DELETE a relationship', blocked(d), `status=${d.status} affected=${d.affected}`);
}

// ═══ 2. baseline ═══════════════════════════════════════════════════════════
section('2. Baseline — unrelated authenticated user, no relationship');
const HEALTH = ['weight_logs', 'body_measurements'];
for (const t of HEALTH) {
  const r = await rest(attacker, `${t}?user_id=eq.${ids.victim}&select=id`);
  check(`baseline: attacker reads 0 ${t}`, n(r.body) === 0, `rows=${n(r.body)} status=${r.status}`);
}

// ═══ 3. the attack ═════════════════════════════════════════════════════════
section('3. The D-01 attack — forge a relationship over an unconsenting client');
{
  const forge = await mutate(attacker, T, 'POST',
    { coach_id: ids.attacker, client_id: ids.victim, status: 'active',
      initiated_by: 'coach', activated_at: now() });
  check('attacker cannot forge an active relationship', blocked(forge),
        `status=${forge.status} ${JSON.stringify(forge.body || '').slice(0, 120)}`);
}

// ═══ 4. downstream authorization ═══════════════════════════════════════════
section('4. Downstream authorization must be unchanged');
{
  const iac = await rpc(attacker, 'is_active_coach_of', { target_user: ids.victim });
  check('is_active_coach_of(victim) stays false for the attacker',
        iac.body === false, `status=${iac.status} body=${JSON.stringify(iac.body)}`);

  for (const t of HEALTH) {
    const r = await rest(attacker, `${t}?user_id=eq.${ids.victim}&select=id`);
    check(`attacker still reads 0 ${t}`, n(r.body) === 0, `rows=${n(r.body)}`);
  }
  const p = await rest(attacker, `user_profiles?id=eq.${ids.victim}&select=email,phone,medical_conditions`);
  check('attacker cannot read the victim PII profile', n(p.body) === 0, `rows=${n(p.body)}`);
}

// ═══ 5. visibility + invite_token ══════════════════════════════════════════
section('5. Row visibility and invite_token');
{
  await svc(T, { method: 'POST', body: { coach_id: ids.coach, client_id: ids.victim,
    status: 'active', initiated_by: 'client', activated_at: now(),
    invite_token: 'P1-SECRET-INVITE-TOKEN' } });

  const other = await rest(attacker, `${T}?select=${COLS}&client_id=eq.${ids.victim}`);
  check('unrelated user cannot see a third party relationship', n(other.body) === 0, `rows=${n(other.body)}`);

  // invite_token is a bearer credential with no reader in the codebase. It is
  // withheld at the COLUMN-GRANT layer, so even a party cannot project it and no
  // future policy widening can hand it out.
  const tokA = await rest(attacker, `${T}?select=invite_token`);
  check('invite_token is not projectable by an authenticated user', tokA.status >= 400,
        `status=${tokA.status}`);
  const tokV = await rest(victim, `${T}?select=invite_token`);
  check('invite_token is not projectable even by a party', tokV.status >= 400, `status=${tokV.status}`);
  const tokAnon = await rest('anon', `${T}?select=invite_token`);
  check('invite_token is not projectable by anon', tokAnon.status >= 400, `status=${tokAnon.status}`);
  const star = await rest(victim, `${T}?select=*`);
  check('select=* is denied (it would expand to the withheld columns)', star.status >= 400,
        `status=${star.status}`);

  const mine = await rest(victim, `${T}?select=${COLS}&client_id=eq.${ids.victim}`);
  check('client CAN read their own relationship', n(mine.body) === 1, `rows=${n(mine.body)}`);
  const roster = await rest(coach, `${T}?select=${COLS}&coach_id=eq.${ids.coach}`);
  check('coach CAN read their own roster', n(roster.body) >= 1, `rows=${n(roster.body)}`);
}

// ═══ 6. tampering with a third-party relationship ══════════════════════════
section('6. Tampering with a relationship the caller is not party to');
{
  const cancel = await mutate(attacker, `${T}?client_id=eq.${ids.victim}&coach_id=eq.${ids.coach}`,
    'PATCH', { status: 'cancelled' });
  check('attacker cannot cancel a third-party relationship', blocked(cancel),
        `status=${cancel.status} affected=${cancel.affected}`);

  const del = await mutate(attacker, `${T}?client_id=eq.${ids.victim}`, 'DELETE');
  check('attacker cannot delete a third-party relationship', blocked(del),
        `status=${del.status} affected=${del.affected}`);

  const still = await svc(`${T}?client_id=eq.${ids.victim}&coach_id=eq.${ids.coach}&select=status`);
  check('the real relationship survived', still.body?.[0]?.status === 'active', JSON.stringify(still.body));

  // The row-repointing attack: take a row you legitimately own as the CLIENT and
  // rewrite it so you are the COACH of somebody else. A WITH CHECK clause cannot
  // see OLD, so this is caught by trg_relationship_integrity.
  await svc(T, { method: 'POST', body: { coach_id: ids.coach, client_id: ids.attacker,
    status: 'active', initiated_by: 'client' } });
  const repoint = await mutate(attacker, `${T}?client_id=eq.${ids.attacker}`, 'PATCH',
    { coach_id: ids.attacker, client_id: ids.victim });
  check('attacker cannot repoint their own row at a third party', blocked(repoint),
        `status=${repoint.status} affected=${repoint.affected}`);
}

// ═══ 7. coach-side escalation ══════════════════════════════════════════════
section('7. Coach-side escalation');
{
  await reset();

  const active = await mutate(coach, T, 'POST',
    { coach_id: ids.coach, client_id: ids.victim, status: 'active', initiated_by: 'coach' });
  check('coach cannot create an ACTIVE relationship over a client', blocked(active),
        `status=${active.status}`);

  const pend = await mutate(coach, T, 'POST',
    { coach_id: ids.coach, client_id: ids.victim, status: 'pending', initiated_by: 'coach' });
  check('coach CAN open a pending invite', landed(pend), `status=${pend.status}`);
  const invite = await svc(`${T}?client_id=eq.${ids.victim}&select=id`);
  const inviteId = invite.body?.[0]?.id;

  const selfApprove = await mutate(coach, `${T}?id=eq.${inviteId}`, 'PATCH', { status: 'active' });
  check('coach cannot self-approve their own invite', blocked(selfApprove),
        `status=${selfApprove.status} affected=${selfApprove.affected}`);

  const rewrite = await mutate(coach, `${T}?id=eq.${inviteId}`, 'PATCH',
    { initiated_by: 'client', status: 'active' });
  check('coach cannot rewrite initiated_by to self-approve', blocked(rewrite),
        `status=${rewrite.status} affected=${rewrite.affected}`);

  const noAccess = await rest(coach, `weight_logs?user_id=eq.${ids.victim}&select=id`);
  check('a pending invite grants the coach no data access', n(noAccess.body) === 0, `rows=${n(noAccess.body)}`);

  const accept = await mutate(victim, `${T}?id=eq.${inviteId}`, 'PATCH',
    { status: 'active', activated_at: now() });
  check('client CAN accept a coach invite', landed(accept),
        `status=${accept.status} affected=${accept.affected}`);

  await reset();
  const nonCoach = await mutate(victim, T, 'POST',
    { client_id: ids.victim, coach_id: ids.attacker, status: 'active', initiated_by: 'client' });
  check('client cannot enroll with a non-coach account', blocked(nonCoach), `status=${nonCoach.status}`);

  const selfCoach = await mutate(coach, T, 'POST',
    { client_id: ids.coach, coach_id: ids.coach, status: 'active', initiated_by: 'client' });
  check('nobody can be their own coach', blocked(selfCoach), `status=${selfCoach.status}`);

  // client_source drives the marketplace commission rate — server-set only.
  const seeded = await svc(T, { method: 'POST', body: { coach_id: ids.coach, client_id: ids.victim,
    status: 'active', initiated_by: 'client', client_source: 'marketplace' } });
  const relId = seeded.body?.[0]?.id;
  const cs = await mutate(victim, `${T}?id=eq.${relId}`, 'PATCH', { client_source: 'coach_invited' });
  check('client cannot rewrite client_source (commission)', blocked(cs),
        `status=${cs.status} affected=${cs.affected}`);
}

// ═══ 8. legitimate flows ═══════════════════════════════════════════════════
section('8. Legitimate relationship flows still work');
{
  await reset();

  const req = await mutate(victim, T, 'POST', { client_id: ids.victim, coach_id: ids.coach,
    status: 'pending', initiated_by: 'client', request_message: 'P1 legit request', pending_at: now() });
  check('client can request a coach (pending)', landed(req), `status=${req.status}`);
  const rel = await svc(`${T}?client_id=eq.${ids.victim}&select=id`);
  const relId = rel.body?.[0]?.id;

  const pre = await rest(coach, `weight_logs?user_id=eq.${ids.victim}&select=id`);
  check('pending grants the coach no data access', n(pre.body) === 0, `rows=${n(pre.body)}`);

  const appr = await mutate(coach, `${T}?id=eq.${relId}`, 'PATCH',
    { status: 'active', activated_at: now() });
  check('coach can approve a pending request', landed(appr),
        `status=${appr.status} affected=${appr.affected}`);

  const post = await rest(coach, `weight_logs?user_id=eq.${ids.victim}&select=id`);
  check('active grants the coach client data access', n(post.body) >= 1, `rows=${n(post.body)}`);

  const profile = await rest(coach, `user_profiles?id=eq.${ids.victim}&select=id,email`);
  check('active coach can read the client profile (client_detail_screen)', n(profile.body) === 1,
        `rows=${n(profile.body)}`);

  const price = await mutate(coach, `${T}?id=eq.${relId}`, 'PATCH', { monthly_price: 149 });
  check('coach can set a per-client price', landed(price), `status=${price.status}`);

  const canc = await mutate(victim, `${T}?id=eq.${relId}`, 'PATCH',
    { status: 'cancelled', cancelled_by: 'client', cancel_reason: 'p1', cancelled_at: now() });
  check('client can cancel their own coaching relationship', landed(canc),
        `status=${canc.status} affected=${canc.affected}`);

  const revoked = await rest(coach, `weight_logs?user_id=eq.${ids.victim}&select=id`);
  check('cancelling revokes the coach data access', n(revoked.body) === 0, `rows=${n(revoked.body)}`);

  // Onboarding self-select: the client consents to share their own record, so
  // they may create the row already active. It is an upsert in the app.
  await reset();
  const onb = await mutate(victim, T, 'POST', { client_id: ids.victim, coach_id: ids.coach,
    status: 'active', initiated_by: 'client', activated_at: now() });
  check('onboarding: client can self-select an active coach', landed(onb), `status=${onb.status}`);

  const onbAgain = await mutate(victim, `${T}?client_id=eq.${ids.victim}&status=eq.active&coach_id=neq.${ids.coach}`,
    'PATCH', { status: 'cancelled', cancelled_by: 'client', cancelled_at: now() });
  check('onboarding: switching coach mid-intake is allowed', onbAgain.status < 300,
        `status=${onbAgain.status}`);

  // Marketplace capacity, which used to come from a cross-coach relationship read.
  const cap = await rpc(victim, 'coach_active_client_counts', { coach_ids: [ids.coach] });
  check('marketplace capacity counts are available to clients',
        cap.status < 300 && Array.isArray(cap.body) && cap.body[0]?.active_clients >= 1,
        `status=${cap.status} ${JSON.stringify(cap.body)}`);
  check('capacity RPC leaks no client identity',
        Array.isArray(cap.body) && cap.body.every(r => Object.keys(r).sort().join() === 'active_clients,coach_id'),
        JSON.stringify(cap.body?.[0] || {}));
}

await reset();
export default summary('D-01 coach_client_relationships');
