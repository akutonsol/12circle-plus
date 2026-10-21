// Phase 1E — intelligence / engine substrate RLS.
//
// Two things are asserted here, and the second matters as much as the first:
//   * clients cannot READ the deterministic engine's substrate, or WRITE any of
//     its provenance (decision traces, predictions, program versions, audit rows)
//   * the engine and every legitimate app path still work
import { rest, rpc, svc, mutate, blocked, signIn, check, section, summary, n, loadIds, checkDenied } from './lib.mjs';

const ids = await loadIds();
const REL = 'coach_client_relationships';
const now = () => new Date().toISOString();

const attacker = await signIn('attacker');
const coach    = await signIn('coach');
const victim   = await signIn('victim');
const admin    = await signIn('admin');

const clearRel = () => svc(`${REL}?client_id=eq.${ids.victim}`, { method: 'DELETE' });
await clearRel();

// ═══ 1. anon ═══════════════════════════════════════════════════════════════
section('1. Anonymous reach into the substrate');
for (const t of ['ai_conversations', 'ai_insights', 'ai_memories', 'decision_traces',
                 'predictions', 'program_versions', 'movement_nodes', 'movement_edges',
                 'exercise_intelligence', 'weekly_feedback', 'communications',
                 'intelligence_attribute_reviews', 'workout_programs', 'program_workouts',
                 'user_scores']) {
  const r = await rest('anon', `${t}?select=*&limit=1`);
  check(`anon reads 0 ${t}`, r.status >= 400 || n(r.body) === 0, `status=${r.status} rows=${n(r.body)}`);
}

// ═══ 2. engine substrate is not client-readable ════════════════════════════
section('2. Engine substrate is not readable by an ordinary member');
{
  for (const t of ['movement_nodes', 'movement_edges', 'exercise_intelligence']) {
      // MEASURED AGAINST THE REAL POPULATION, not asserted bare. These three engine
      // tables are EMPTY on QA, so "member reads 0" passed without proving anything
      // -- the member saw nothing because there was nothing to see (V5 §147).
      // checkDenied labels that honestly instead of counting it as evidence, and
      // allowEmpty is set because the emptiness is the engine's current state, not
      // something this suite can seed without inventing graph rows.
      const all = await svc(`${t}?select=*&limit=1000`);
      const r = await rest(victim, `${t}?select=*&limit=5`);
      checkDenied(`member reads no ${t}`,
        { saw: n(r.body), population: n(all.body), allowEmpty: true, detail: `status=${r.status}` });
    }
    const nodes = await svc('movement_nodes?select=id&limit=1000');
    const staff = await rest(admin, 'movement_nodes?select=id&limit=5');
    check(`a content editor CAN read the movement graph${n(nodes.body) === 0 ? ' (graph is EMPTY — status only, not proof of visibility)' : ''}`,
      staff.status < 300 && (n(nodes.body) === 0 || n(staff.body) > 0),
      `status=${staff.status} staff_rows=${n(staff.body)} population=${n(nodes.body)}`);

  // ...and the client still gets what it actually needs, through the RPC.
  const graph = await rpc(victim, 'movement_graph',
    { p_exercise_id: '00000000-0000-0000-0000-000000000000' });
  check('movement_graph() still serves the client', graph.status < 300, `status=${graph.status}`);
  const rank = await rpc(victim, 'rank_exercises', { p_context: {}, p_limit: 3 });
  check('rank_exercises() still reads the substrate as definer', rank.status < 300, `status=${rank.status}`);
}

// ═══ 3. provenance and audit rows are not client-writable ══════════════════
section('3. Provenance / audit tables reject every client write');
{
  const cases = [
    ['decision_traces',   { subject_id: ids.attacker, created_by: ids.attacker,
                            engine_version: 'FORGED', context: {}, result: {} }],
    ['predictions',       { subject_id: ids.attacker, prediction: {}, confidence: 99,
                            engine_version: 'FORGED' }],
    ['program_versions',  { program_id: ids.attacker, version: 999, reason: 'FORGED' }],
    ['movement_nodes',    { type: 'muscle', name: 'P1-FORGED' }],
    ['movement_edges',    { from_node: ids.attacker, to_node: ids.attacker, rel: 'x' }],
    ['exercise_intelligence', { exercise_id: ids.attacker, confidence: 100 }],
    ['intelligence_attribute_reviews', { exercise_id: ids.attacker, attribute: 'x', status: 'approved' }],
    ['communications',    { subject_id: ids.attacker, type: 'weekly_review', status: 'sent' }],
  ];
  for (const [t, row] of cases) {
    const ins = await mutate(attacker, t, 'POST', row);
    check(`client cannot INSERT into ${t}`, blocked(ins), `status=${ins.status}`);
    const upd = await mutate(attacker, `${t}?select=id`, 'PATCH', { });
    const del = await mutate(attacker, t, 'DELETE');
    check(`client cannot DELETE from ${t}`, blocked(del), `status=${del.status} affected=${del.affected}`);
  }

  // An admin is a moderator, not an engine: even they do not hand-write traces.
  const adminForge = await mutate(admin, 'decision_traces', 'POST',
    { subject_id: ids.attacker, created_by: ids.admin, engine_version: 'FORGED',
      context: {}, result: {} });
  check('not even an admin can hand-write a decision trace', blocked(adminForge),
        `status=${adminForge.status}`);
}

// ═══ 4. own AI data still works, other people's does not ═══════════════════
section('4. Per-member AI data');
{
  const mine = await mutate(victim, 'ai_insights', 'POST',
    { user_id: ids.victim, type: 'p1_probe', title: 'p1', body: 'p1' });
  check('a member can write their own ai_insights row', mine.status < 300, `status=${mine.status}`);

  const theirs = await mutate(attacker, 'ai_insights', 'POST',
    { user_id: ids.victim, type: 'p1_forged', title: 'forged', body: 'forged' });
  check('a member cannot write ai_insights for someone else', blocked(theirs), `status=${theirs.status}`);

  const read = await rest(attacker, `ai_insights?user_id=eq.${ids.victim}&select=id`);
  check('a member cannot read someone else\'s ai_insights', n(read.body) === 0, `rows=${n(read.body)}`);

  const conv = await rest('anon', 'ai_conversations?select=*&limit=1');
  check('ai_conversations is closed to anon (policy is TO authenticated now)',
        conv.status >= 400 || n(conv.body) === 0, `status=${conv.status}`);

  await svc(`ai_insights?type=in.(p1_probe,p1_forged)`, { method: 'DELETE' });
}

// ═══ 5. programming visibility ═════════════════════════════════════════════
section('5. Coach programming is not world-readable');
{
  const prog = await svc('workout_programs', { method: 'POST',
    body: { coach_id: ids.coach, name: 'P1 Program', goal: 'strength' } });
  const progId = prog.body?.[0]?.id;
  check('fixture program created', !!progId, `status=${prog.status}`);

  const day = await svc('program_workouts', { method: 'POST',
    body: { program_id: progId, week_number: 1, day_of_week: 1, title: 'P1 Day' } });
  check('fixture program_workouts row created', day.status < 300,
        `status=${day.status} ${JSON.stringify(day.body || '').slice(0, 120)}`);

  const stranger = await rest(attacker, `workout_programs?id=eq.${progId}&select=id,name`);
  check('an unrelated member cannot read a coach\'s program', n(stranger.body) === 0,
        `rows=${n(stranger.body)}`);
  const strangerDays = await rest(attacker, `program_workouts?program_id=eq.${progId}&select=id`);
  check('an unrelated member cannot read its program_workouts', n(strangerDays.body) === 0,
        `rows=${n(strangerDays.body)}`);

  const owner = await rest(coach, `workout_programs?id=eq.${progId}&select=id`);
  check('the owning coach CAN read their program', n(owner.body) === 1, `rows=${n(owner.body)}`);
  const ownerDays = await rest(coach, `program_workouts?program_id=eq.${progId}&select=id`);
  check('the owning coach CAN read its program_workouts', n(ownerDays.body) >= 1,
        `rows=${n(ownerDays.body)}`);

  await svc('workout_program_assignments', { method: 'POST',
    body: { program_id: progId, client_id: ids.victim, coach_id: ids.coach, status: 'active' } });
  const assigned = await rest(victim, `workout_programs?id=eq.${progId}&select=id`);
  check('the ASSIGNED client CAN read their program', n(assigned.body) === 1, `rows=${n(assigned.body)}`);
  const assignedDays = await rest(victim, `program_workouts?program_id=eq.${progId}&select=id`);
  check('the ASSIGNED client CAN read its program_workouts', n(assignedDays.body) >= 1,
        `rows=${n(assignedDays.body)}`);

  const embed = await rest(victim,
    `workout_program_assignments?client_id=eq.${ids.victim}&select=id,workout_programs(name,goal)`);
  check('the embedded assignment->program read still works', n(embed.body) >= 1 &&
        embed.body?.[0]?.workout_programs?.name === 'P1 Program', JSON.stringify(embed.body?.[0] || {}));

  const steal = await mutate(attacker, `workout_programs?id=eq.${progId}`, 'PATCH', { name: 'PWNED' });
  check('an unrelated member cannot edit a coach\'s program', blocked(steal),
        `status=${steal.status} affected=${steal.affected}`);

  await svc(`workout_program_assignments?program_id=eq.${progId}`, { method: 'DELETE' });
  await svc(`program_workouts?program_id=eq.${progId}`, { method: 'DELETE' });
  await svc(`workout_programs?id=eq.${progId}`, { method: 'DELETE' });
}

// ═══ 6. weekly_feedback: engine input ══════════════════════════════════════
section('6. weekly_feedback is engine input');
{
  const prog = await svc('workout_programs', { method: 'POST',
    body: { coach_id: ids.coach, name: 'P1 Feedback Program', goal: 'strength' } });
  const progId = prog.body?.[0]?.id;
  const fb = await svc('weekly_feedback', { method: 'POST',
    body: { program_id: progId, subject_id: ids.victim, week: 1,
            completion_pct: 80, recovery: 3 } });
  check('fixture weekly_feedback row created', fb.status < 300,
        `status=${fb.status} ${JSON.stringify(fb.body || '').slice(0, 120)}`);
  const fbId = fb.body?.[0]?.id;

  const own = await rest(victim, `weekly_feedback?id=eq.${fbId}&select=id`);
  check('the subject can read their own feedback', n(own.body) === 1, `rows=${n(own.body)}`);

  const other = await rest(attacker, `weekly_feedback?id=eq.${fbId}&select=id`);
  check('an unrelated member cannot read it', n(other.body) === 0, `rows=${n(other.body)}`);

  const upd = await mutate(victim, `weekly_feedback?id=eq.${fbId}`, 'PATCH', { completion_pct: 90 });
  check('the subject can revise their own feedback', upd.status < 300, `status=${upd.status}`);

  const del = await mutate(victim, `weekly_feedback?id=eq.${fbId}`, 'DELETE');
  check('the subject cannot DELETE engine input', blocked(del),
        `status=${del.status} affected=${del.affected}`);

  const survived = await svc(`weekly_feedback?id=eq.${fbId}&select=id`);
  check('the feedback row survived', n(survived.body) === 1, `rows=${n(survived.body)}`);
  await svc(`weekly_feedback?id=eq.${fbId}`, { method: 'DELETE' });
  await svc(`workout_programs?id=eq.${progId}`, { method: 'DELETE' });
}

// ═══ 7. user_scores ════════════════════════════════════════════════════════
section('7. user_scores');
{
  const others = await rest(attacker, `user_scores?user_id=eq.${ids.victim}&select=user_id`);
  check('a member cannot read another member\'s score row', n(others.body) === 0, `rows=${n(others.body)}`);
  const own = await rest(victim, `user_scores?user_id=eq.${ids.victim}&select=user_id`);
  check('a member can read their own score row', own.status < 300, `status=${own.status}`);
  const lb = await rpc(victim, 'leaderboard_global', { p_limit: 5 });
  check('the global leaderboard RPC still works', lb.status < 300, `status=${lb.status}`);
}

// ═══ 8. moderation dashboards ══════════════════════════════════════════════
section('8. Moderation dashboards are content-editor only');
for (const [fn, args] of [['intelligence_review_queue', { p_limit: 5 }],
                          ['intelligence_stats', {}],
                          ['decision_analytics', {}],
                          ['movement_graph_stats', {}],
                          ['exercise_content_stats', {}],
                          ['certification_summary', {}]]) {
  const bad = await rpc(victim, fn, args);
  check(`a member cannot call ${fn}()`, bad.status >= 400, `status=${bad.status}`);
  const ok = await rpc(admin, fn, args);
  check(`an admin can call ${fn}()`, ok.status < 300, `status=${ok.status}`);
}

// ═══ 9. decision_traces read scope — PD-A05 option (a) ═════════════════════
//
// F-J-12. Migration 089's SELECT policy admitted every account whose role was
// coach / content_manager / admin, with no relationship or program check — a
// self-registered coach read every member's traces. 125 removed the coach arm;
// **128 removes content_manager**, leaving exactly the policy the product owner
// authorized on 2026-08-27:
//
//     subject  OR  created_by  OR  the subject's ACTIVE coach  OR  admin
//
// The negative arms (unrelated coach, unrelated client, content_manager) and the
// subject arm are read-only and are proved in
// supabase/tests/ai/j04-provenance-authz.mjs §J-04A. The two POSITIVE arms below
// have to arrange a relationship and author a trace, so they need the service
// key and live here — the home Workstream J's own remediation field named.
section('9. decision_traces read scope — PD-A05 option (a)');
{
  const linkCoach = () => svc(REL, { method: 'POST', body: { coach_id: ids.coach,
    client_id: ids.victim, status: 'active', initiated_by: 'client', activated_at: now() } });

  await clearRel();
  await linkCoach();

  // The active-coach arm, positively. Every negative assertion in J-04A would
  // pass just as well against a policy that refused everyone — that would be a
  // different defect, not a fix, and this is the probe that can tell them apart.
  const asCoach = await rest(coach,
    `decision_traces?select=id,subject_id,created_by&subject_id=eq.${ids.victim}`);
  const coachRows = Array.isArray(asCoach.body) ? asCoach.body : [];
  check('an ACTIVE coach CAN read their own client\'s decision traces',
        asCoach.status < 300 && coachRows.length > 0,
        `status=${asCoach.status} rows=${coachRows.length}`);

  // The created_by arm (M-1). The owner ruled it retained because a coach must
  // not lose the audit record of a decision they themselves made once the
  // relationship ends — auditability is the reason traces exist. Author one as
  // the coach while the relationship is active, END the relationship, and read
  // it back: the only arm that can still be granting access is created_by.
  const authoredGen = await rpc(coach, 'generate_workout',
    { p_context: { size: 2 }, p_subject: ids.victim });
  await clearRel();
  const mine = await rest(coach,
    `decision_traces?select=id,subject_id,created_by&created_by=eq.${ids.coach}`);
  const mineRows = Array.isArray(mine.body) ? mine.body : [];
  check('the CREATOR still reads the trace they authored after the relationship ends',
        authoredGen.status < 300 && mine.status < 300 && mineRows.length > 0
          && mineRows.every(r => r.created_by === ids.coach),
        `generate=${authoredGen.status} read=${mine.status} rows=${mineRows.length} ` +
        `(subject is ${mineRows[0]?.subject_id === ids.coach ? 'the coach' : 'the client'}, ` +
        'so the subject arm cannot be what is granting this read)');
}

await clearRel();
export default summary('Phase 1E intelligence substrate');
