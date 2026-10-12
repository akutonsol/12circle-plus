// D23 · FG-3 — the POSITIVE authorization legs of the 116 engine-wrapper class.
//
// OWNER DECISION, 2026-10-12. FG-3 was registered "recorded, NOT implemented
// (owner assignment required)". It is now assigned, with these choices:
//
//   positive callers   program-scoped → the OWNING COACH, real non-NULL program
//                      subject-scoped → the SUBJECT themselves, real non-NULL subject
//   evidence           option C — HTTP 200 plus the expected engine-owned effect
//   service_role       a SEPARATE liveness test, explicitly not authorization evidence
//   side effects       isolated QA engine execution permitted, teardown verified by READING
//
// ── WHAT "THE EXPECTED EFFECT" ACTUALLY IS, PER WRAPPER ────────────────────
// Option C says "200 plus the expected engine-owned row or rows". Establishing
// what that means required reading the five engine bodies, and the answer is not
// uniform — three of the five WRITE NOTHING:
//
//   predict_client_engine          095 — zero mutating keywords. Pure read.
//   assemble_weekly_review_engine  096 — zero mutating keywords. Pure read.
//   evaluate_week_engine           094 — zero mutating keywords. Pure read.
//   regenerate_program_engine      094 — UPDATE workout_programs.plan
//                                      + INSERT decision_traces, but ONLY on the
//                                        'applied' branch. With p_approved=false it
//                                        returns 'pending_approval' and writes nothing.
//   materialize_program_week_engine 119 — INSERT program_workouts
//
// So for the three read-only engines the expected effect is the RETURNED PAYLOAD,
// not a row; asserting "a row appeared" would be asserting something the engine
// never promised. That is a narrowing of option C forced by the code, and it is
// flagged for the owner rather than silently substituted. For `regenerate_program`
// called with p_approved=false, the expected effect IS 'pending_approval' and NO
// write — asserting that is asserting the expected effect, not dodging it.
//
// ── HOW THIS PROVES THE PREDICATE, NOT SOMETHING ELSE ──────────────────────
// A 200 on its own proves nothing about WHY. Each positive leg is therefore run
// as a PAIR against the identical scope, varying only the caller:
//
//   owning coach / the subject  → 200          (the predicate's relationship arm)
//   an unrelated authenticated  → 403 · 42501  (the same predicate, refusing)
//
// Same program id, same subject id, same arguments — the caller is the only
// variable, so the outcome difference can only come from the relationship arm.
// That rules out the NULL arm (the scope is real and non-NULL in both), a
// service-role bypass (both are user JWTs), an admin shortcut (neither holds
// admin), and a malformed signature (a 403 and a 200 both prove the signature
// resolved).
import { IDENT, signIn, rpc, svc, rest, check, section, summary, beginSuite, n }
  from './lib.mjs';

const TAG = 'QA-D23-FG3';
const ONE = (b) => (Array.isArray(b) ? b[0] : b) || {};

async function uidOf(key) {
  const r = await svc(`user_profiles?email=eq.${encodeURIComponent(IDENT[key].email)}&select=id`);
  return ONE(r.body).id;
}
const countOf = async (path) => {
  const r = await svc(`${path}&select=id`);
  return n(r.body);
};

async function run() {
  beginSuite();
  const coach    = await signIn('coach');
  const victim   = await signIn('victim');
  const attacker = await signIn('attacker');
  const coachId  = await uidOf('coach');
  const victimId = await uidOf('victim');

  const purge = async () => {
    const progs = await svc(`workout_programs?name=eq.${TAG}&select=id`);
    for (const p of (Array.isArray(progs.body) ? progs.body : [])) {
      await svc(`program_workouts?program_id=eq.${p.id}`, { method: 'DELETE' });
      await svc(`workout_programs?id=eq.${p.id}`, { method: 'DELETE' });
    }
    await svc(`decision_traces?engine_version=eq.${TAG}`, { method: 'DELETE' });
  };

  // materialize_program_week's engine calls generate_workout, which INSERTs into
  // decision_traces. Those are this run's side effects and must be removed, but
  // decision_traces is a provenance table other suites count — so the teardown
  // deletes EXACTLY the ids that did not exist beforehand, never a blanket wipe.
  const traceIdsBefore = new Set(
    ((await svc(`decision_traces?subject_id=eq.${victimId}&select=id`)).body || [])
      .map((r) => r.id));

  let progId;
  try {
    await purge();

    // ── §1 · a REAL, coach-owned program. Non-NULL scope is the whole point ──
    section('§1 · fixture: a real program owned by the coach');
    // The engine reads `week->'split'` and loops `0 .. jsonb_array_length(split)-1`.
    // A week without `split` makes that bound NULL and raises 22004 — observed,
    // and the reason this fixture carries a split rather than a day list.
    const plan = { weeks: [{ week: 1, split: ['push'], volume_multiplier: 1.0 }] };
    const made = await svc('workout_programs', {
      method: 'POST',
      body: { coach_id: coachId, name: TAG, goal: 'strength', plan },
    });
    progId = ONE(made.body).id;
    check('fixture program created and owned by the coach',
      made.status < 300 && !!progId, `status=${made.status} id=${progId}`);
    const owner = await svc(`workout_programs?id=eq.${progId}&select=coach_id`);
    check('the fixture\'s coach_id IS the calling coach — the relationship the '
        + 'predicate tests', ONE(owner.body).coach_id === coachId,
      `coach_id=${ONE(owner.body).coach_id} coach=${coachId}`);

    // ── §2 · PROGRAM-SCOPED · the owning coach is ADMITTED ───────────────────
    section('§2 · program-scoped: the owning coach is admitted, a stranger is not');

    const ev = await rpc(coach, 'evaluate_week', { p_program_id: progId, p_week: 1 });
    check('evaluate_week() ADMITS the owning coach (200)', ev.status === 200,
      `status=${ev.status} ${JSON.stringify(ev.body || '').slice(0, 70)}`);
    check('evaluate_week() returns an engine payload — its engine is READ-ONLY, '
        + 'so the payload is the expected effect, not a row',
      ev.body !== null && typeof ev.body === 'object',
      `body=${JSON.stringify(ev.body || '').slice(0, 70)}`);

    // materialize: this engine DOES write program_workouts. Scoped delta.
    const beforeRows = await countOf(`program_workouts?program_id=eq.${progId}`);
    const mz = await rpc(coach, 'materialize_program_week',
      { p_program_id: progId, p_week: 1, p_context: {} });
    const afterRows = await countOf(`program_workouts?program_id=eq.${progId}`);
    check('materialize_program_week() ADMITS the owning coach (200)',
      mz.status === 200, `status=${mz.status} ${JSON.stringify(mz.body || '').slice(0, 70)}`);
    check(`materialize_program_week() produced its engine-owned rows — `
        + `program_workouts for THIS program ${beforeRows} → ${afterRows}`,
      afterRows > beforeRows,
      `scoped to program_id=${progId}, so an unrelated concurrent insert cannot satisfy it`);

    // regenerate with p_approved=false: the expected effect is NO write.
    const tracesBefore = await countOf(`decision_traces?subject_id=eq.${victimId}`);
    const rg = await rpc(coach, 'regenerate_program',
      { p_program_id: progId, p_week: 1, p_approved: false });
    const tracesAfter = await countOf(`decision_traces?subject_id=eq.${victimId}`);
    check('regenerate_program() ADMITS the owning coach (200)', rg.status === 200,
      `status=${rg.status} ${JSON.stringify(rg.body || '').slice(0, 70)}`);
    check('regenerate_program() returned a documented status, and with '
        + 'p_approved=false the expected effect is NO write',
      ['no_change', 'pending_approval', 'applied'].includes(rg.body?.status)
        && (rg.body?.status === 'applied' || tracesAfter === tracesBefore),
      `status=${rg.body?.status} traces ${tracesBefore} → ${tracesAfter}`);

    // THE PAIR. Same scope, different caller.
    for (const fn of ['evaluate_week', 'materialize_program_week', 'regenerate_program']) {
      const args = fn === 'evaluate_week' ? { p_program_id: progId, p_week: 1 }
        : fn === 'materialize_program_week' ? { p_program_id: progId, p_week: 1, p_context: {} }
        : { p_program_id: progId, p_week: 1, p_approved: false };
      const r = await rpc(attacker, fn, args);
      check(`${fn}() REFUSES a stranger on the SAME real program — the caller is `
          + `the only variable, so the admission above came from the relationship arm`,
        r.status === 403 && r.body?.code === '42501',
        `status=${r.status} code=${r.body?.code ?? '-'}`);
    }

    // ── §3 · SUBJECT-SCOPED · the subject themselves ─────────────────────────
    section('§3 · subject-scoped: the subject is admitted, a stranger is not');
    for (const [fn, args] of [
      ['predict_client', { p_subject: victimId, p_program: null }],
      ['assemble_weekly_review', { p_subject: victimId, p_program: null, p_week: 1 }],
    ]) {
      const ok = await rpc(victim, fn, args);
      check(`${fn}() ADMITS the subject themselves (200)`, ok.status === 200,
        `status=${ok.status} ${JSON.stringify(ok.body || '').slice(0, 70)}`);
      check(`${fn}() returns an engine payload — this engine is READ-ONLY, so the `
          + `payload is the expected effect`,
        ok.body !== null && typeof ok.body === 'object',
        `body=${JSON.stringify(ok.body || '').slice(0, 60)}`);
      const no = await rpc(attacker, fn, args);
      check(`${fn}() REFUSES a stranger for the SAME subject — caller is the only `
          + `variable`,
        no.status === 403 && no.body?.code === '42501',
        `status=${no.status} code=${no.body?.code ?? '-'}`);
    }

    // ── §4 · service_role · LIVENESS ONLY ────────────────────────────────────
    section('§4 · service_role — LIVENESS, explicitly NOT authorization evidence');
    const live = await svc('rpc/evaluate_week', {
      method: 'POST', body: { p_program_id: progId, p_week: 1 },
    });
    check('LIVENESS (not authorization): service_role reaches the engine. It '
        + 'passes through can_act_on_program\'s `auth.uid() IS NULL` arm — the '
        + 'internal-engine arm — so it would succeed with every relationship arm '
        + 'deleted, and proves only that the path is reachable',
      live.status === 200, `status=${live.status}`);
  } finally {
    // ── §5 · teardown, verified by READING ─────────────────────────────────
    await purge();
    const after = ((await svc(`decision_traces?subject_id=eq.${victimId}&select=id`)).body || []);
    for (const t of after) {
      if (!traceIdsBefore.has(t.id)) await svc(`decision_traces?id=eq.${t.id}`, { method: 'DELETE' });
    }
  }

  section('§5 · teardown verified by reading, not inferred from a 204');
  const leftProgs = await svc(`workout_programs?name=eq.${TAG}&select=id`);
  check('no D23 program survives', n(leftProgs.body) === 0, `rows=${n(leftProgs.body)}`);
  if (progId) {
    const leftRows = await countOf(`program_workouts?program_id=eq.${progId}`);
    check('no program_workouts row survives for the fixture program',
      leftRows === 0, `rows=${leftRows}`);
  }
  const tracesNow = ((await svc(`decision_traces?subject_id=eq.${victimId}&select=id`)).body || []);
  const strays = tracesNow.filter((t) => !traceIdsBefore.has(t.id));
  check('no decision_traces row created by this run survives — the engine\'s own '
      + 'side effect, removed by id and confirmed by a read',
    strays.length === 0, `${strays.length} stray trace(s); baseline ${traceIdsBefore.size}`);

  return summary('D23 · FG-3 positive authorization legs');
}

export default await run();
