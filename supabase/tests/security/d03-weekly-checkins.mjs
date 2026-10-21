// D-03 (P0) — weekly_checkins carries free-text health data and had no RLS.
//
// Before migration 114 an unauthenticated caller holding the published anon key
// could read, forge and delete anyone's check-ins. Because compliance scoring,
// the coach at-risk roster and ai_adjust_nutrition's weight-trend calculation all
// read this table, a forged row steers a real nutrition prescription — so the
// write path is asserted as hard as the read path.
import { rest, svc, mutate, blocked, landed, signIn,
         check, section, summary, n, loadIds } from './lib.mjs';

const T = 'weekly_checkins';
const ids = await loadIds();
const REL = 'coach_client_relationships';
const now = () => new Date().toISOString();

const clearRel = () => svc(`${REL}?client_id=eq.${ids.victim}`, { method: 'DELETE' });
const linkCoach = () => svc(REL, { method: 'POST', body: { coach_id: ids.coach,
  client_id: ids.victim, status: 'active', initiated_by: 'client', activated_at: now() } });

await clearRel();
const attacker = await signIn('attacker');
const coach    = await signIn('coach');
const victim   = await signIn('victim');

// The fixture check-in seeded by setup-identities.mjs.
const seeded = await svc(`${T}?user_id=eq.${ids.victim}&week_number=eq.901&select=id`);
const checkinId = seeded.body?.[0]?.id;
if (!checkinId) throw new Error('fixture check-in missing — run setup-identities.mjs');

// ═══ 1. anonymous ══════════════════════════════════════════════════════════
section('1. Anonymous');
{
  const r = await rest('anon', `${T}?select=*`);
  check('anon cannot SELECT check-ins', r.status >= 400 || n(r.body) === 0,
        `status=${r.status} rows=${n(r.body)}`);

  const i = await mutate('anon', T, 'POST',
    { user_id: ids.victim, week_number: 999, week_start_date: '2026-01-05',
      status: 'submitted', notes: 'P1-ANON-FORGE' });
  check('anon cannot INSERT a check-in', blocked(i), `status=${i.status}`);

  const u = await mutate('anon', `${T}?id=eq.${checkinId}`, 'PATCH', { weight_kg: 1 });
  check('anon cannot UPDATE a check-in', blocked(u), `status=${u.status} affected=${u.affected}`);

  const d = await mutate('anon', `${T}?id=eq.${checkinId}`, 'DELETE');
  check('anon cannot DELETE a check-in', blocked(d), `status=${d.status} affected=${d.affected}`);

  const survived = await svc(`${T}?id=eq.${checkinId}&select=id,notes`);
  check('the fixture check-in survived every anon write', n(survived.body) === 1,
        JSON.stringify(survived.body));
}

// ═══ 2. unrelated authenticated user ═══════════════════════════════════════
section('2. Unrelated authenticated user');
{
  const r = await rest(attacker, `${T}?user_id=eq.${ids.victim}&select=*`);
  check('unrelated user cannot read another user check-in', n(r.body) === 0, `rows=${n(r.body)}`);

  const notes = await rest(attacker, `${T}?select=notes,feedback_message`);
  check('unrelated user reads no free-text health notes at all', n(notes.body) === 0,
        `rows=${n(notes.body)}`);

  const i = await mutate(attacker, T, 'POST',
    { user_id: ids.victim, week_number: 998, week_start_date: '2026-01-12', status: 'submitted' });
  check('unrelated user cannot create a check-in for someone else', blocked(i), `status=${i.status}`);

  const u = await mutate(attacker, `${T}?id=eq.${checkinId}`, 'PATCH', { compliance_percent: 3 });
  check('unrelated user cannot corrupt compliance data', blocked(u),
        `status=${u.status} affected=${u.affected}`);

  const d = await mutate(attacker, `${T}?id=eq.${checkinId}`, 'DELETE');
  check('unrelated user cannot delete a check-in', blocked(d),
        `status=${d.status} affected=${d.affected}`);
}

// ═══ 3. D-01 chain — a forged relationship must not open this table ════════
section('3. Cross-check: no relationship forgery route into check-in data');
{
  const forge = await mutate(attacker, REL, 'POST',
    { coach_id: ids.attacker, client_id: ids.victim, status: 'active', initiated_by: 'coach' });
  check('attacker still cannot forge the relationship', blocked(forge), `status=${forge.status}`);
  const r = await rest(attacker, `${T}?user_id=eq.${ids.victim}&select=id`);
  check('attacker still reads 0 check-ins', n(r.body) === 0, `rows=${n(r.body)}`);
}

// ═══ 4. owner flows ════════════════════════════════════════════════════════
section('4. Owner flows');
{
  const own = await rest(victim, `${T}?select=*`);
  check('owner CAN read their own check-ins (bare select=*)', n(own.body) >= 1, `rows=${n(own.body)}`);

  const sub = await mutate(victim, T, 'POST', { user_id: ids.victim, week_number: 902,
    week_start_date: '2026-08-10', status: 'submitted', mood: 4, energy: 4,
    stress_level: 2, sleep_hours_avg: 7.5, notes: 'P1 own submission', overall_score: 8.1,
    submitted_at: now() });
  check('owner can submit their own check-in', landed(sub), `status=${sub.status}`);

  const resub = await mutate(victim, `${T}?id=eq.${checkinId}`, 'PATCH',
    { mood: 5, energy: 5, notes: 'P1 revised', status: 'submitted' });
  check('owner can revise their own answers', landed(resub),
        `status=${resub.status} affected=${resub.affected}`);

  const forgeReview = await mutate(victim, `${T}?id=eq.${checkinId}`, 'PATCH',
    { feedback_message: 'self-authored praise', coach_name: 'Fake Coach', reviewed_at: now() });
  check('owner cannot author their own coach feedback', blocked(forgeReview),
        `status=${forgeReview.status} affected=${forgeReview.affected}`);

  const forgeStatus = await mutate(victim, `${T}?id=eq.${checkinId}`, 'PATCH', { status: 'reviewed' });
  check('owner cannot mark their own check-in reviewed', blocked(forgeStatus),
        `status=${forgeStatus.status} affected=${forgeStatus.affected}`);

  const steal = await mutate(victim, `${T}?id=eq.${checkinId}`, 'PATCH', { user_id: ids.attacker });
  check('owner cannot reassign a check-in to another user', blocked(steal),
        `status=${steal.status} affected=${steal.affected}`);

  const other = await mutate(victim, T, 'POST',
    { user_id: ids.attacker, week_number: 997, week_start_date: '2026-01-19', status: 'submitted' });
  check('owner cannot create a check-in for another user', blocked(other), `status=${other.status}`);
}

// ═══ 5. coach flows ════════════════════════════════════════════════════════
section('5. Coach flows');
{
  const before = await rest(coach, `${T}?user_id=eq.${ids.victim}&select=id`);
  check('coach with NO relationship reads 0 check-ins', n(before.body) === 0, `rows=${n(before.body)}`);

  await linkCoach();

  const after = await rest(coach, `${T}?user_id=eq.${ids.victim}&select=*`);
  check('active coach CAN read their client check-ins', n(after.body) >= 1, `rows=${n(after.body)}`);

  // getSubmittedCheckinsForCoach() issues an unscoped status=submitted query; RLS
  // is what keeps it to this coach's own clients.
  const queue = await rest(coach, `${T}?status=eq.submitted&select=user_id`);
  const foreign = (queue.body || []).filter(r => r.user_id !== ids.victim);
  check('the coach review queue is scoped to this coach\'s clients by RLS',
        foreign.length === 0, `foreign rows=${foreign.length}`);

  const review = await mutate(coach, `${T}?id=eq.${checkinId}`, 'PATCH',
    { status: 'reviewed', feedback_message: 'P1 great week', feedback_recommendations: ['sleep'],
      coach_name: 'P1 coach', reviewed_at: now() });
  check('active coach can submit feedback', landed(review),
        `status=${review.status} affected=${review.affected}`);

  const tamper = await mutate(coach, `${T}?id=eq.${checkinId}`, 'PATCH', { weight_kg: 60, mood: 1 });
  check('coach cannot rewrite the client\'s own answers', blocked(tamper),
        `status=${tamper.status} affected=${tamper.affected}`);

  const fabricate = await mutate(coach, T, 'POST',
    { user_id: ids.victim, week_number: 996, week_start_date: '2026-01-26',
      status: 'submitted', compliance_percent: 100 });
  check('coach cannot fabricate a check-in for a client', blocked(fabricate), `status=${fabricate.status}`);

  const del = await mutate(coach, `${T}?id=eq.${checkinId}`, 'DELETE');
  check('coach cannot delete a client check-in', blocked(del),
        `status=${del.status} affected=${del.affected}`);

  await clearRel();
  const revoked = await rest(coach, `${T}?user_id=eq.${ids.victim}&select=id`);
  check('ending the relationship revokes check-in access', n(revoked.body) === 0, `rows=${n(revoked.body)}`);
}

// cleanup: keep the week-901 fixture, drop what this run added
await svc(`${T}?user_id=eq.${ids.victim}&week_number=eq.902`, { method: 'DELETE' });
await clearRel();
export default summary('D-03 weekly_checkins');
