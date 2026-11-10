// Phase 1D — SECURITY DEFINER RPC execution security.
//
// Before migration 116, 98 of 100 public functions were executable by `anon` and
// 73 SECURITY DEFINER functions had no pinned search_path. The subject-scoped
// intelligence functions trusted a caller-supplied UUID outright, so any caller
// could read a stranger's engine picture and write provenance against them.
//
// This suite asserts the posture, the per-function guards, and — just as
// important — that the deterministic engine and every real app call still work.
import { rest, rpc, svc, signIn, check, section, summary, n, loadIds } from './lib.mjs';
import { engineWrapperClass, KNOWN_OPEN } from './migration-durability-guard.mjs';

const ids = await loadIds();
const REL = 'coach_client_relationships';
const now = () => new Date().toISOString();

const attacker = await signIn('attacker');
const coach    = await signIn('coach');
const victim   = await signIn('victim');
const admin    = await signIn('admin');

const clearRel = () => svc(`${REL}?client_id=eq.${ids.victim}`, { method: 'DELETE' });
const linkCoach = () => svc(REL, { method: 'POST', body: { coach_id: ids.coach,
  client_id: ids.victim, status: 'active', initiated_by: 'client', activated_at: now() } });
await clearRel();

// A denial is 401/403, or the PostgREST "function not found" 404 you get when
// the caller has no EXECUTE and therefore cannot see the function at all.
const denied = (r) => r.status === 401 || r.status === 403 || r.status === 404;

// ═══ 1. posture ════════════════════════════════════════════════════════════
section('1. Schema-wide function posture');
{
  // Sampled through the API surface rather than the catalog: this is what an
  // attacker can actually reach.
  const probes = ['insert_notification', 'ai_adjust_nutrition', 'mie_upsert_node',
                  'rebuild_movement_graph', 'generate_workout', 'predict_client',
                  'marketplace_coaches', 'admin_recent_users'];
  for (const fn of probes) {
    const r = await rpc('anon', fn, {});
    check(`anon cannot execute ${fn}()`, denied(r), `status=${r.status}`);
  }
}

// ═══ 2. internal / engine-only functions ═══════════════════════════════════
section('2. Engine-only functions are unreachable by a signed-in client');
{
  const cases = [
    ['insert_notification', { p_recipient_id: ids.victim, p_type: 'phish',
      p_title: 'Your account needs attention', p_body: 'tap here', p_data: {} }],
    ['ai_adjust_nutrition', { p_uid: ids.victim }],
    ['ai_detect_patterns',  { p_uid: ids.victim }],
    ['ai_cron_generate',    { p_type: 'daily_insight' }],
    ['ai_cron_accountability', {}],
    ['mie_upsert_node', { p_type: 'muscle', p_name: 'P1-FORGED', p_ref: null }],
    ['mie_upsert_edge', { p_from: ids.victim, p_to: ids.victim, p_rel: 'x',
                          p_conf: 100, p_reason: 'p1', p_source: 'p1' }],
    ['recalc_coach_rating', { p_coach_id: ids.coach }],
    ['seed_exercise', { p: {}, p_coach_id: ids.coach }],
    ['snapshot_exercise_content', { p_id: ids.victim, p_source: 'p1',
                                    p_confidence: 1, p_actor: ids.attacker }],
    ['predict_client_engine', { p_subject: ids.victim, p_program: null }],
    ['evaluate_week_engine',  { p_program_id: ids.victim, p_week: 1 }],
  ];
  for (const [fn, args] of cases) {
    const r = await rpc(attacker, fn, args);
    check(`authenticated client cannot execute ${fn}()`, denied(r), `status=${r.status}`);
  }

  const notifs = await svc(`notifications?recipient_id=eq.${ids.victim}&type=eq.phish&select=id`);
  check('no forged notification landed', n(notifs.body) === 0, `rows=${n(notifs.body)}`);
}

// ═══ 3. arbitrary subject UUID ═════════════════════════════════════════════
section('3. Subject-scoped RPCs reject an arbitrary subject');
{
  const traceBefore = await svc(`decision_traces?subject_id=eq.${ids.victim}&select=id`);

  const gen = await rpc(attacker, 'generate_workout',
    { p_context: { size: 3 }, p_subject: ids.victim });
  check('attacker cannot generate_workout for another subject', denied(gen) || gen.status >= 400,
        `status=${gen.status} ${JSON.stringify(gen.body || '').slice(0, 90)}`);

  const traceAfter = await svc(`decision_traces?subject_id=eq.${ids.victim}&select=id`);
  check('no decision trace was forged against the victim',
        n(traceAfter.body) === n(traceBefore.body),
        `before=${n(traceBefore.body)} after=${n(traceAfter.body)}`);

  const pred = await rpc(attacker, 'predict_client', { p_subject: ids.victim });
  check('attacker cannot predict_client on another subject', pred.status >= 400,
        `status=${pred.status} ${JSON.stringify(pred.body || '').slice(0, 90)}`);

  const rec = await rpc(attacker, 'record_prediction', { p_subject: ids.victim });
  check('attacker cannot record_prediction against another subject', rec.status >= 400,
        `status=${rec.status}`);

  const asm = await rpc(attacker, 'assemble_weekly_review',
    { p_subject: ids.victim, p_program: null, p_week: 1 });
  check('attacker cannot assemble_weekly_review for another subject', asm.status >= 400,
        `status=${asm.status}`);

  const cwr = await rpc(attacker, 'create_weekly_review',
    { p_subject: ids.victim, p_program: null, p_week: 1 });
  check('attacker cannot create_weekly_review against another subject', cwr.status >= 400,
        `status=${cwr.status}`);
  const comms = await svc(`communications?subject_id=eq.${ids.victim}&select=id`);
  check('no communication was drafted against the victim', n(comms.body) === 0,
        `rows=${n(comms.body)}`);

  const media = await rpc(attacker, 'resolve_exercise_media',
    { p_exercise_id: '00000000-0000-0000-0000-000000000000', p_viewer_id: ids.victim });
  check('attacker cannot resolve another user\'s coach media', media.status >= 400,
        `status=${media.status} ${JSON.stringify(media.body || '').slice(0, 90)}`);
}

// ═══ 4. own-subject and coach-authorized paths still work ══════════════════
section('4. Legitimate subject-scoped use');
{
  // `module` is required by migration 188 (ENGINE_UNKNOWN_MODULE otherwise); a
  // pre-188 build_workout ignores the key, so these calls hold on both sides.
  const own = await rpc(victim, 'generate_workout', { p_context: { size: 3, module: 'workout_builder' }, p_subject: ids.victim });
  check('a member can generate_workout for themselves', own.status < 300,
        `status=${own.status} ${JSON.stringify(own.body || '').slice(0, 80)}`);

  const implicit = await rpc(victim, 'generate_workout', { p_context: { size: 3, module: 'workout_builder' } });
  check('generate_workout with no subject defaults to the caller', implicit.status < 300,
        `status=${implicit.status}`);

  const trace = await svc(`decision_traces?subject_id=eq.${ids.victim}&select=created_by&limit=1`);
  check('the trace is attributed to the caller', trace.body?.[0]?.created_by === ids.victim,
        JSON.stringify(trace.body?.[0] || {}));

  const noCoach = await rpc(coach, 'predict_client', { p_subject: ids.victim });
  check('a coach with no relationship is refused', noCoach.status >= 400, `status=${noCoach.status}`);

  await linkCoach();
  const withCoach = await rpc(coach, 'predict_client', { p_subject: ids.victim });
  check('an ACTIVE coach can predict_client for their client', withCoach.status < 300,
        `status=${withCoach.status} ${JSON.stringify(withCoach.body || '').slice(0, 80)}`);

  const selfPred = await rpc(victim, 'predict_client', { p_subject: ids.victim });
  check('a member can predict_client on themselves', selfPred.status < 300, `status=${selfPred.status}`);

  const adminPred = await rpc(admin, 'predict_client', { p_subject: ids.victim });
  check('an admin can predict_client on anyone', adminPred.status < 300, `status=${adminPred.status}`);

  await clearRel();
  const revoked = await rpc(coach, 'predict_client', { p_subject: ids.victim });
  check('ending the relationship revokes RPC access too', revoked.status >= 400, `status=${revoked.status}`);
}

// ═══ 5. deterministic engine still executes ════════════════════════════════
section('5. The deterministic engine is intact');
{
  const build = await rpc(victim, 'build_workout', { p_context: { size: 4, focus: 'push', module: 'workout_builder' } });
  check('build_workout still runs for a member', build.status < 300,
        `status=${build.status} ${JSON.stringify(build.body || '').slice(0, 70)}`);

  const rank = await rpc(victim, 'rank_exercises', { p_context: { focus: 'push' }, p_limit: 5 });
  check('rank_exercises still runs', rank.status < 300, `status=${rank.status}`);

  const warm = await rpc(victim, 'generate_warmup', { p_exercise_ids: [] });
  check('generate_warmup still runs', warm.status < 300, `status=${warm.status}`);

  const plan = await rpc(victim, 'client_plan', {});
  check('client_plan still runs', plan.status < 300, `status=${plan.status}`);

  const mk = await rpc(victim, 'marketplace_coaches', {});
  check('marketplace_coaches still runs', mk.status < 300 && Array.isArray(mk.body),
        `status=${mk.status} rows=${n(mk.body)}`);

  // service_role is the engine's own identity and must retain everything.
  for (const fn of ['ai_detect_patterns', 'insert_notification', 'mie_upsert_node',
                    'predict_client_engine']) {
    const r = await rpc('service', fn, fn === 'insert_notification'
      ? { p_recipient_id: ids.victim, p_type: 'p1_engine_probe', p_title: 'p1', p_body: 'p1', p_data: {} }
      : fn === 'mie_upsert_node' ? { p_type: 'muscle', p_name: 'P1-ENGINE-PROBE', p_ref: null }
      : fn === 'predict_client_engine' ? { p_subject: ids.victim, p_program: null }
      : { p_uid: ids.victim });
    check(`service_role can still execute ${fn}()`, r.status < 300, `status=${r.status}`);
  }
  await svc(`notifications?type=eq.p1_engine_probe`, { method: 'DELETE' });
  await svc(`movement_nodes?name=eq.P1-ENGINE-PROBE`, { method: 'DELETE' });
}

// ═══ 6. RLS still evaluates its predicates ═════════════════════════════════
section('6. RLS predicates survived the schema-wide revoke');
{
  // If EXECUTE on is_active_coach_of() had been revoked, every coach-read policy
  // would fail closed and the coach dashboard would silently show nothing.
  await linkCoach();
  const health = await rest(coach, `weight_logs?user_id=eq.${ids.victim}&select=id`);
  check('coach-read policies still evaluate (is_active_coach_of executable)',
        health.status < 300 && n(health.body) >= 1, `status=${health.status} rows=${n(health.body)}`);

  const prof = await rest(coach, `user_profiles?id=eq.${ids.victim}&select=id`);
  check('user_profiles coach-read policy still evaluates', n(prof.body) === 1, `rows=${n(prof.body)}`);

  const conv = await rest(victim, 'conversation_participant_profiles?select=id&limit=1');
  check('conversation_participant_profiles view still readable', conv.status < 300, `status=${conv.status}`);

  const ex = await rest(victim, 'exercises?select=id&limit=1');
  check('exercise_readable() policy still evaluates', ex.status < 300, `status=${ex.status}`);
  await clearRel();
}

// ═══ 7. admin / content-editor gating ══════════════════════════════════════
section('7. Admin and content-editor RPCs');
{
  for (const [fn, args] of [['admin_recent_users', { p_limit: 5 }],
                            ['admin_platform_stats', {}],
                            ['intelligence_review_queue', { p_limit: 5 }]]) {
    const bad = await rpc(attacker, fn, args);
    const leaked = bad.status < 300 && (Array.isArray(bad.body) ? bad.body.length > 0
                                        : bad.body && Object.keys(bad.body).length > 0);
    check(`a client cannot use ${fn}()`, !leaked, `status=${bad.status}`);
  }
  const ok = await rpc(admin, 'admin_recent_users', { p_limit: 5 });
  check('an admin still can', ok.status < 300 && n(ok.body) > 0, `status=${ok.status} rows=${n(ok.body)}`);
}

// ═══ 8. The 116 engine-wrapper CLASS ═══════════════════════════════════════
//
// I-MIG-03 / W2-2B. Sections 3 and 4 above assert individual wrappers, and that
// is exactly how F-J-01 survived: migration 116 published FIVE thin wrappers in
// front of `<name>_engine` implementations, this suite named two of them, and
// migration 119 stripped one of the three nobody was asserting. An assertion
// that pins instances cannot notice the class growing a hole.
//
// So the class is read from the migration source at run time — never
// hand-copied here — and every member must be exercised or explicitly exempted.
// If 116's set grows, the completeness assertion below fails until someone
// extends this coverage deliberately.
section('8. Every 116 engine wrapper refuses an unauthorized caller (class)');
{
  // 116's five, read from the migration source. Migration 117 applied the same
  // wrapper-over-engine shape to eight content-editor functions; none is
  // stripped and covering them is a follow-up, deliberately outside W2-2B.
  const CLASS = engineWrapperClass({ establishedIn: '116' });
  const members = [...CLASS.keys()].sort();

  // A stand-in uuid: not a program, so `can_act_on_program()` is false and a
  // guarded function refuses before the engine is reached. The same convention
  // section 2 already uses for the *_engine probes.
  // Which predicate each member guards on, verified against 116's source:
  // `can_act_for(p_subject)` for the two subject-scoped members,
  // `can_act_on_program(p_program_id)` for the other three. FG-3's own wording
  // ("the owning coach → 200 … for each of the five wrappers") does not hold for
  // the subject-scoped pair, which have no program and no owning coach — that
  // split is one of the six questions in V5_FG3_DECISION_REQUEST.md and is NOT
  // decided here. What IS asserted below is only which refusal each one emits.
  const SUBJECT_SCOPED = new Set(['predict_client', 'assemble_weekly_review']);

  const NOT_A_PROGRAM = ids.victim;
  const ARGS = {
    predict_client:           { p_subject: ids.victim, p_program: null },
    assemble_weekly_review:   { p_subject: ids.victim, p_program: null, p_week: 1 },
    evaluate_week:            { p_program_id: NOT_A_PROGRAM, p_week: 1 },
    regenerate_program:       { p_program_id: NOT_A_PROGRAM, p_week: 1, p_approved: false },
    materialize_program_week: { p_program_id: NOT_A_PROGRAM, p_week: 1, p_context: {} },
  };

  // Members whose guard is KNOWN STRIPPED are not probed. Calling
  // materialize_program_week today would not test an authorization boundary —
  // there is not one — it would EXERCISE the open hole and write to QA through
  // the engine. Closure standard §5.2: where a security-sensitive probe cannot
  // be made safe, the probe is not run and the limitation is recorded. It
  // becomes an enforced assertion in 2A, once migration 124 restores the guard
  // and refusal is the expected outcome.
  const exempt = new Map(KNOWN_OPEN
    .filter((k) => k.property === 'auth-wrapper')
    .map((k) => [k.fn, k]));

  check('the 116 engine-wrapper class still has five members',
        members.length === 5, `${members.length}: ${members.join(', ')}`);
  check('every class member has an authorization probe defined here',
        members.every((fn) => ARGS[fn]),
        members.filter((fn) => !ARGS[fn]).join(', ') || 'all covered');

  for (const fn of members) {
    if (exempt.has(fn)) {
      const k = exempt.get(fn);
      console.log(`  SKIP  ${fn}() — NOT PROBED. ${k.finding}: the wrapper was stripped by `
        + `migration ${k.strippedBy} and is not restored, so this call would exercise the `
        + `open hole rather than test a boundary. Closes: ${k.closedBy}.`);
      continue;
    }
    const r = await rpc(attacker, fn, ARGS[fn]);
    // NOT `status >= 400`. That was the previous assertion, and it accepted ANY
    // error as a refusal: a malformed argument, a wrong signature, a type error
    // or a 500 would all have read as "the guard held". This is the mirror of
    // the gap FG-3 records — FG-3 says an OVER-refusing wrapper is
    // indistinguishable from a correct one; a bare `>= 400` makes a BROKEN
    // wrapper indistinguishable from a guarding one.
    //
    // The expected refusal is defined in 116's own source:
    //   RAISE EXCEPTION 'not authorized for this …' USING ERRCODE = '42501'
    // and PostgREST surfaces it as 403 + code 42501. Observed as exactly that
    // for all five members before this assertion was written.
    //
    // The MESSAGE is asserted too, because it names which predicate refused:
    // `can_act_for` says "subject", `can_act_on_program` says "program". A
    // member that silently swapped predicates would still 403 — and would still
    // be wrong, because the two guard different things. This is the only part
    // of the probe that can tell them apart.
    const wantsSubject = SUBJECT_SCOPED.has(fn);
    const scope = wantsSubject ? 'subject' : 'program';
    const msg = String(r.body?.message ?? '');
    check(`${fn}() refuses an unauthorized caller with the AUTHORIZATION error, `
          + `not merely an error`,
          r.status === 403 && r.body?.code === '42501',
          `status=${r.status} code=${r.body?.code ?? '-'} ${JSON.stringify(r.body || '').slice(0, 60)}`);
    check(`${fn}() refuses via its own predicate — "${scope}"`,
          msg.includes(`not authorized for this ${scope}`),
          `message=${JSON.stringify(msg).slice(0, 80)} (expected the ${scope} arm, `
          + `because ${fn} guards on ${wantsSubject ? 'can_act_for' : 'can_act_on_program'})`);
  }

  // ── the UNAUTHENTICATED leg, for the whole class ────────────────────────
  //
  // §1 above probes anon against a SAMPLE of the API surface, and `predict_client`
  // is the only class member in it. SEC-R1's Tests field asks for the five to be
  // asserted "as a class, not individually", so the sample is extended to the
  // class here.
  //
  // This is a DIFFERENT LAYER from the refusal above, and asserting the layer is
  // the point. An anonymous caller is stopped by the GRANT — PostgREST returns
  // 401 `42501` "permission denied for function …" and the body never runs. An
  // authenticated non-owner reaches the body and is stopped by the PREDICATE —
  // 403 `42501` "not authorized for this …". Two independent defences, and a
  // probe that accepted either for both would not notice if one disappeared.
  for (const fn of members) {
    const r = await rpc('anon', fn, ARGS[fn]);
    const msg = String(r.body?.message ?? '');
    check(`${fn}() is refused to anon at the GRANT layer, before the body runs`,
          r.status === 401 && msg.includes('permission denied for function'),
          `status=${r.status} code=${r.body?.code ?? '-'} message=${JSON.stringify(msg).slice(0, 70)}`);
  }

  // The engine implementations behind the class stay unreachable to a client
  // whatever the wrapper does — the second, independent leg of 116's design,
  // and the one that still holds for the stripped member.
  for (const fn of members) {
    const r = await rpc(attacker, `${fn}_engine`, ARGS[fn]);
    check(`${fn}_engine() is unreachable by a client`, denied(r), `status=${r.status}`);
  }
}

await clearRel();
export default summary('Phase 1D RPC execution security');
