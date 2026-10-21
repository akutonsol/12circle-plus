// Phase 1F — the standing posture guard.
//
// The three P0s of this phase all had the same shape: a table or a function
// shipped without the control, and nothing noticed. These assertions are the
// noticing. They are deliberately coarse and schema-wide, so a table or RPC
// added in six months either meets the posture or fails this suite.
import { rest, rpc, svc, mutate, blocked, signIn,
         check, section, summary, n, loadIds } from './lib.mjs';

const ids = await loadIds();
const attacker = await signIn('attacker');
const coach    = await signIn('coach');
const victim   = await signIn('victim');
const REL = 'coach_client_relationships';
await svc(`${REL}?client_id=eq.${ids.victim}`, { method: 'DELETE' });

// ═══ 1. the anon surface ═══════════════════════════════════════════════════
section('1. The anonymous surface is empty');
{
  // Every table the audit classified as sensitive, probed as the open internet.
  const tables = [
    'user_profiles', 'coach_client_relationships', 'weekly_checkins', 'workouts',
    'weight_logs', 'body_measurements', 'nutrition_logs', 'progress_photos',
    'coach_notes', 'messages', 'conversations', 'notifications', 'payments',
    'subscriptions', 'coach_availability', 'coaching_calls', 'class_bookings',
    'decision_traces', 'predictions', 'program_versions', 'communications',
    'movement_nodes', 'movement_edges', 'exercise_intelligence', 'weekly_feedback',
    'workout_programs', 'program_workouts', 'workout_sessions', 'daily_scores',
    'user_scores', 'ai_insights', 'ai_memories', 'ai_conversations',
  ];
  let readable = [], writable = [];
  for (const t of tables) {
    const r = await rest('anon', `${t}?select=*&limit=1`);
    if (r.status < 300 && n(r.body) > 0) readable.push(`${t}(${n(r.body)})`);
    const w = await mutate('anon', t, 'POST', { id: '00000000-0000-0000-0000-000000000000' });
    if (!blocked(w)) writable.push(`${t}(${w.status})`);
  }
  check('anon reads no row from any sensitive table', readable.length === 0, readable.join(', '));
  check('anon writes to no sensitive table', writable.length === 0, writable.join(', '));

  const views = ['public_profiles', 'conversation_participant_profiles',
                 'coach_client_workout_stats', 'exercises', 'exercise_certifications'];
  let vr = [];
  for (const v of views) {
    const r = await rest('anon', `${v}?select=*&limit=1`);
    if (r.status < 300 && n(r.body) > 0) vr.push(v);
  }
  check('anon reads no view', vr.length === 0, vr.join(', '));

  const root = await rest('anon', '');
  check('anon cannot read the PostgREST schema root', root.status >= 400, `status=${root.status}`);
}

// ═══ 2. F-01 coach stats view ══════════════════════════════════════════════
section('2. F-01 — coach_client_workout_stats is caller-scoped');
{
  const V = 'coach_client_workout_stats';
  const stranger = await rest(attacker, `${V}?select=coach_id,client_name,completion_rate_pct`);
  const foreign = (stranger.body || []).filter(r => r.coach_id !== ids.attacker
                                               && r.client_id !== ids.attacker);
  check('an unrelated member sees no other coach\'s roster', foreign.length === 0,
        `rows=${n(stranger.body)} foreign=${foreign.length} ${JSON.stringify((stranger.body||[])[0]||{})}`);

  await svc(REL, { method: 'POST', body: { coach_id: ids.coach, client_id: ids.victim,
    status: 'active', initiated_by: 'client', activated_at: new Date().toISOString() } });

  const own = await rest(coach, `${V}?select=coach_id,client_id&coach_id=eq.${ids.coach}`);
  check('the coach CAN see their own roster stats', n(own.body) >= 1, `rows=${n(own.body)}`);
  const leak = (own.body || []).filter(r => r.coach_id !== ids.coach);
  check('...and only their own', leak.length === 0, `foreign=${leak.length}`);

  const asClient = await rest(victim, `${V}?select=client_id`);
  check('the client can see their own row', n(asClient.body) >= 1, `rows=${n(asClient.body)}`);

  await svc(`${REL}?client_id=eq.${ids.victim}`, { method: 'DELETE' });
}

// ═══ 3. F-02 workouts ══════════════════════════════════════════════════════
section('3. F-02 — the legacy workouts catalog');
{
  // THIS SECTION USED TO PROVE LESS THAN IT LOOKED. `workouts` is EMPTY on QA and
  // the delete attempt was UNFILTERED, so it passed on status 400 — PostgREST
  // REFUSING AN UNFILTERED DELETE, which says nothing about whether the member
  // holds the privilege. Being wrong here means a member can empty the exercise
  // catalogue. A marked row is seeded and a FILTERED delete is attempted against
  // it, so the assertion now rests on the row surviving (V5 §146).
  const PROBE = 'P1-SWEEP-PROBE catalog row';
  await svc(`workouts?title=eq.${encodeURIComponent(PROBE)}`, { method: 'DELETE' });
  const seeded = await svc('workouts', { method: 'POST', body: { title: PROBE, category: 'probe' } });
  check('seeded a catalog row, so the delete assertion below is not vacuous',
    seeded.status < 300, `status=${seeded.status}`);
  const probeId = n(seeded.body) ? seeded.body[0].id : null;

  const read = await rest(victim, 'workouts?select=id&limit=1');
  check('a member can read the catalog', read.status < 300, `status=${read.status}`);

  const w = await mutate(victim, 'workouts', 'POST', { title: 'P1-FORGED', category: 'x' });
  check('a member cannot write the catalog', blocked(w), `status=${w.status}`);

  const d = await mutate(victim, `workouts?id=eq.${probeId}`, 'DELETE');
  const survived = await svc(`workouts?title=eq.${encodeURIComponent(PROBE)}&select=id`);
  check('a member cannot delete a catalog row — and the seeded row SURVIVED',
    blocked(d) && n(survived.body) === 1,
    `status=${d.status} seeded_row_remaining=${n(survived.body)}`);

  const u = await mutate(victim, `workouts?id=eq.${probeId}`, 'PATCH', { title: 'P1-TAMPERED' });
  const title = await svc(`workouts?select=title&id=eq.${probeId}`);
  check('a member cannot rewrite a catalog row either',
    n(title.body) === 1 && title.body[0].title === PROBE,
    `status=${u.status} title=${n(title.body) ? title.body[0].title : 'GONE'}`);

  const left = await svc('workouts?title=eq.P1-FORGED&select=id');
  check('nothing was written', n(left.body) === 0, `rows=${n(left.body)}`);
  await svc(`workouts?title=eq.${encodeURIComponent(PROBE)}`, { method: 'DELETE' });
}

// ═══ 4. F-03 notification injection ════════════════════════════════════════
section('4. F-03 — notifications cannot be sent to a stranger');
{
  const phish = await mutate(attacker, 'notifications', 'POST',
    { recipient_id: ids.victim, type: 'security', title: 'Verify your account',
      body: 'tap this link', read: false });
  check('a stranger cannot push a notification', blocked(phish), `status=${phish.status}`);
  const got = await svc(`notifications?recipient_id=eq.${ids.victim}&type=eq.security&select=id`);
  check('nothing landed in the victim\'s feed', n(got.body) === 0, `rows=${n(got.body)}`);

  const self = await mutate(victim, 'notifications', 'POST',
    { recipient_id: ids.victim, type: 'p1_self', title: 'p1', body: 'p1', read: false });
  check('a member can notify themselves', self.status < 300, `status=${self.status}`);

  // The real flow: a client requests a coach, then notifies them.
  await svc(REL, { method: 'POST', body: { coach_id: ids.coach, client_id: ids.victim,
    status: 'pending', initiated_by: 'client' } });
  const legit = await mutate(victim, 'notifications', 'POST',
    { recipient_id: ids.coach, type: 'coach_request', title: 'New Coaching Request',
      body: 'A new client is requesting you as their coach.', read: false });
  check('requestCoach() can still notify the coach', legit.status < 300, `status=${legit.status}`);

  const back = await mutate(coach, 'notifications', 'POST',
    { recipient_id: ids.victim, type: 'request_approved', title: 'Approved',
      body: 'Your coach accepted.', read: false });
  check('approveRequest() can still notify the client', back.status < 300, `status=${back.status}`);

  // The DB trigger path (insert_notification, SECURITY DEFINER) is unaffected.
  const viaTrigger = await rpc('service', 'insert_notification',
    { p_recipient_id: ids.victim, p_type: 'p1_trigger', p_title: 'p1', p_body: 'p1', p_data: {} });
  check('the trigger path still writes notifications', viaTrigger.status < 300, `status=${viaTrigger.status}`);

  await svc(`notifications?type=in.(p1_self,coach_request,request_approved,p1_trigger)`,
    { method: 'DELETE' });
  await svc(`${REL}?client_id=eq.${ids.victim}`, { method: 'DELETE' });
}

// ═══ 5. F-04 / F-05 ════════════════════════════════════════════════════════
section('5. F-04 / F-05 — availability and bookings');
{
  const anonAvail = await rest('anon', 'coach_availability?select=id,is_booked&limit=5');
  check('anon cannot read coach availability', anonAvail.status >= 400 || n(anonAvail.body) === 0,
        `status=${anonAvail.status} rows=${n(anonAvail.body)}`);
  const memberAvail = await rest(victim, 'coach_availability?select=id&limit=5');
  check('a signed-in member still can (booking screen)', memberAvail.status < 300,
        `status=${memberAvail.status}`);

  const bookings = await rest(attacker, 'class_bookings?select=user_id,class_id');
  const foreign = (bookings.body || []).filter(r => r.user_id !== ids.attacker);
  check('a member sees no one else\'s class bookings', foreign.length === 0,
        `rows=${n(bookings.body)} foreign=${foreign.length}`);
}

// ═══ 6. F-07 defence in depth ══════════════════════════════════════════════
section('6. F-07 — a table shipped without RLS is still not anon-reachable');
{
  // The grant layer is what has to hold if the policy layer is forgotten again.
  await svc('/rpc/query', { method: 'POST' }).catch(() => {});
  const probe = await rest('anon', 'user_profiles?select=id&limit=1');
  check('anon has no table grant to fall back on', probe.status >= 400,
        `status=${probe.status} (401/403 = grant refused, not merely no rows)`);
}

// ═══ 7. legitimate app surfaces ════════════════════════════════════════════
section('7. Ordinary member and coach surfaces still work');
{
  const surfaces = [
    ['own profile',        () => rest(victim, `user_profiles?id=eq.${ids.victim}&select=id,first_name`)],
    ['public profiles',    () => rest(victim, 'public_profiles?select=id,first_name&limit=3')],
    ['community feed',     () => rest(victim, 'community_posts?select=id&limit=3')],
    ['challenges',         () => rest(victim, 'challenges?select=id&limit=3')],
    ['classes',            () => rest(victim, 'classes?select=id&limit=3')],
    ['exercise library',   () => rest(victim, 'exercises?select=id&limit=3')],
    ['foods',              () => rest(victim, 'foods?select=id&limit=3')],
    ['own weight logs',    () => rest(victim, `weight_logs?user_id=eq.${ids.victim}&select=id`)],
    ['own notifications',  () => rest(victim, `notifications?recipient_id=eq.${ids.victim}&select=id`)],
    ['own scores',         () => rest(victim, `user_scores?user_id=eq.${ids.victim}&select=user_id`)],
    ['badges',             () => rest(victim, 'badges?select=id&limit=3')],
    ['coach packages',     () => rest(victim, 'coach_packages?select=id&limit=3')],
  ];
  for (const [name, fn] of surfaces) {
    const r = await fn();
    check(`${name} still reads`, r.status < 300, `status=${r.status}`);
  }
}

export default summary('Phase 1F sweep posture');
