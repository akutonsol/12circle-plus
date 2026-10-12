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
const TAG2 = 'QA-D23-FG3-APPLIED';
const ONE = (b) => (Array.isArray(b) ? b[0] : b) || {};

async function uidOf(key) {
  const r = await svc(`user_profiles?email=eq.${encodeURIComponent(IDENT[key].email)}&select=id`);
  return ONE(r.body).id;
}
// PostgREST caps a plain select at 1000 rows. A count taken over a table larger
// than that page SATURATES, and a before/after delta built from two saturated
// reads is identical no matter what happened in between — an assertion that
// cannot fail. That defect shipped here once (§219.2) and was then found a
// second time, still live, in the pending_approval check.
//
// So counting refuses to return a number it cannot stand behind. Every count in
// this suite must be scoped tightly enough that saturation is impossible; if one
// ever is not, this throws by name instead of quietly returning 1000.
const PAGE_CAP = 1000;
const countOf = async (path) => {
  const r = await svc(`${path}&select=id`);
  const c = n(r.body);
  if (c >= PAGE_CAP) {
    throw new Error(
      `countOf("${path}") returned ${c}, at or above PostgREST's ${PAGE_CAP}-row page cap. `
      + `This count is SATURATED and any delta built from it is meaningless. Scope the query `
      + `(e.g. by the fixture's program_id) rather than widening the page.`);
  }
  return c;
};

async function run() {
  beginSuite();
  const coach    = await signIn('coach');
  const victim   = await signIn('victim');
  const attacker = await signIn('attacker');
  const coachId  = await uidOf('coach');
  const victimId = await uidOf('victim');

  const purge = async () => {
    for (const tag of [TAG, TAG2]) {
      const progs = await svc(`workout_programs?name=eq.${tag}&select=id`);
      for (const p of (Array.isArray(progs.body) ? progs.body : [])) {
        await svc(`program_workouts?program_id=eq.${p.id}`, { method: 'DELETE' });
        await svc(`program_versions?program_id=eq.${p.id}`, { method: 'DELETE' });
        // weekly_feedback is NOT deleted explicitly: 094 declares
        // `program_id ... references workout_programs(id) ON DELETE CASCADE`.
        // §5 asserts the cascade actually fired rather than trusting the DDL.
        await svc(`workout_programs?id=eq.${p.id}`, { method: 'DELETE' });
      }
    }
    await svc(`decision_traces?engine_version=eq.${TAG}`, { method: 'DELETE' });
  };

  // materialize_program_week's engine calls generate_workout, which INSERTs into
  // decision_traces, and regenerate_program's applied branch inserts one more.
  // decision_traces is a provenance table other suites read, so teardown removes
  // only ids this run created — never a blanket wipe, and never a predicate sweep.
  let progId;
  let prog2;
  let appliedTraceId;          // regenerate_program's applied branch returns this
  let materializeTraceIds = []; // materialize_program_week returns one per session

  // Every trace this run causes, identified by an id the ENGINE REPORTED.
  // Neither engine is asked to be trusted about whether it wrote — §5 looks each
  // id up afterwards — but both are trusted to say WHICH row they wrote, which is
  // the only handle that survives decision_traces being larger than PostgREST's
  // 1000-row page.
  const createdTraceIds = () => [appliedTraceId, ...materializeTraceIds].filter(Boolean);
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
    // The CONTRACT, not merely "an object". 094's own returns are either
    // `{action:'NO_FEEDBACK'}` or the full
    // `{week, action, volume_delta, rules_triggered, escalate, needs_approval,
    //   coaching_mode, affected_weeks}`. Asserting `typeof === 'object'` would
    // pass for `{}` or for an error body, which is the same vacuity this
    // programme keeps finding.
    const EV_ACTIONS = ['NO_FEEDBACK', 'CONTINUE', 'REPLACE_EXERCISES',
      'INSERT_DELOAD', 'REDUCE_VOLUME', 'REDUCE_COMPLEXITY', 'INCREASE_VOLUME'];
    check('evaluate_week() returns its declared contract — a known `action`, and '
        + 'the full shape whenever feedback exists',
      EV_ACTIONS.includes(ev.body?.action)
        && (ev.body.action === 'NO_FEEDBACK'
            || ['week', 'volume_delta', 'rules_triggered', 'needs_approval']
                 .every((k) => k in ev.body)),
      `action=${ev.body?.action} keys=${Object.keys(ev.body || {}).join(',')}`);

    // materialize: this engine DOES write program_workouts. Scoped delta.
    const beforeRows = await countOf(`program_workouts?program_id=eq.${progId}`);
    const mz = await rpc(coach, 'materialize_program_week',
      { p_program_id: progId, p_week: 1, p_context: {} });
    materializeTraceIds = (mz.body?.sessions ?? [])
      .map((x) => x?.trace_id).filter(Boolean);
    const afterRows = await countOf(`program_workouts?program_id=eq.${progId}`);
    check('materialize_program_week() ADMITS the owning coach (200)',
      mz.status === 200, `status=${mz.status} ${JSON.stringify(mz.body || '').slice(0, 70)}`);
    check(`materialize_program_week() produced its engine-owned rows — `
        + `program_workouts for THIS program ${beforeRows} → ${afterRows}`,
      afterRows > beforeRows,
      `scoped to program_id=${progId}, so an unrelated concurrent insert cannot satisfy it`);

    // regenerate with p_approved=false: the expected effect is NO write.
    // Scoped to THIS program via the trace's own context, not to the subject.
    // `subject_id=eq.<victim>` matches >1000 rows and saturates, which is how the
    // first version of this check could not have detected a write at all.
    const tracesQ = `decision_traces?context->>program_id=eq.${progId}`;
    const tracesBefore = await countOf(tracesQ);
    const rg = await rpc(coach, 'regenerate_program',
      { p_program_id: progId, p_week: 1, p_approved: false });
    const tracesAfter = await countOf(tracesQ);
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

    // ── §2b · regenerate_program's THREE branches, including `applied` ──────
    //
    // The branch under test above is `p_approved=false`. 094 has three, and only
    // one of them writes, so testing one branch and calling the wrapper covered
    // would be the same mistake as asserting `typeof === 'object'`:
    //
    //   action in ('CONTINUE','NO_FEEDBACK')          → 'no_change',       no write
    //   needs_approval AND NOT p_approved             → 'pending_approval', no write
    //   otherwise                                     → 'applied',   THREE writes
    //
    // The write branch is reached deterministically from evaluate_week's own
    // rule table: `recovery > 85 AND completion_pct > 90` → INCREASE_VOLUME with
    // volume_delta +0.05. `p_approved=true` bypasses the approval arm regardless
    // of the subject's coaching_mode, so the fixture does not depend on it.
    //
    // The plan needs a week AFTER p_week or nothing changes: 094 locks
    // `wknum <= p_week` and only rewrites later weeks. Hence weeks 1 and 2.
    section('§2b · regenerate_program — all three branches, and the writes');

    const plan2 = { duration_weeks: 2, weeks: [
      { week: 1, split: ['push'], volume_multiplier: 1.0, is_deload: false },
      { week: 2, split: ['pull'], volume_multiplier: 1.0, is_deload: false },
    ] };
    const made2 = await svc('workout_programs', { method: 'POST',
      body: { coach_id: coachId, name: TAG2, goal: 'strength', plan: plan2 } });
    prog2 = ONE(made2.body).id;
    check('applied-branch fixture program created', made2.status < 300 && !!prog2,
      `status=${made2.status}`);

    // weekly_feedback's columns were read from 094's DDL, not assumed:
    // (program_id NOT NULL → workout_programs ON DELETE CASCADE, subject_id,
    //  week NOT NULL, completion_pct, recovery, sleep, stress, energy,
    //  pain jsonb default '[]', unique(program_id, week)).
    const fb = await svc('weekly_feedback', { method: 'POST', body: {
      program_id: prog2, subject_id: victimId, week: 1,
      recovery: 90, completion_pct: 95, energy: 90, pain: [] } });
    check('weekly_feedback fixture created — the input evaluate_week reads',
      fb.status < 300, `status=${fb.status} ${JSON.stringify(fb.body || '').slice(0, 90)}`);

    const evForApplied = await rpc(coach, 'evaluate_week',
      { p_program_id: prog2, p_week: 1 });
    check('evaluate_week() on that fixture yields INCREASE_VOLUME — the branch is '
        + 'reached by the engine\'s own rule, not forced',
      evForApplied.body?.action === 'INCREASE_VOLUME',
      `action=${evForApplied.body?.action} delta=${evForApplied.body?.volume_delta}`);

    // BEFORE. Scoped to this fixture so concurrent activity cannot satisfy it.
    const versionsBefore = await countOf(`program_versions?program_id=eq.${prog2}`);
    const planBefore = ONE((await svc(
      `workout_programs?id=eq.${prog2}&select=plan`)).body).plan;
    check('BEFORE: week 2 sits at volume_multiplier 1.0',
      planBefore?.weeks?.[1]?.volume_multiplier === 1.0,
      `week2=${JSON.stringify(planBefore?.weeks?.[1] ?? null)}`);

    const applied = await rpc(coach, 'regenerate_program',
      { p_program_id: prog2, p_week: 1, p_approved: true });
    check('regenerate_program() ADMITS the owning coach on the write branch (200)',
      applied.status === 200, `status=${applied.status}`);
    check('…and returns `applied` with its declared contract '
        + '{status, evaluation, diff, version, trace_id}',
      applied.body?.status === 'applied'
        && ['evaluation', 'diff', 'version', 'trace_id'].every((k) => k in (applied.body || {})),
      `status=${applied.body?.status} keys=${Object.keys(applied.body || {}).join(',')}`);

    appliedTraceId = applied.body?.trace_id;

    // EFFECT 1 · the scoped plan update, asserted by VALUE not by "something changed".
    const planAfter = ONE((await svc(
      `workout_programs?id=eq.${prog2}&select=plan`)).body).plan;
    check('EFFECT 1 — workout_programs.plan week 2 rewritten 1.0 → 1.05 and marked '
        + 'regenerated; week 1 LOCKED because 094 locks `wknum <= p_week`',
      planAfter?.weeks?.[1]?.volume_multiplier === 1.05
        && planAfter?.weeks?.[1]?.regenerated === true
        && planAfter?.weeks?.[0]?.volume_multiplier === 1.0
        && !('regenerated' in (planAfter?.weeks?.[0] ?? {})),
      `week1=${JSON.stringify(planAfter?.weeks?.[0] ?? null)} `
      + `week2=${JSON.stringify(planAfter?.weeks?.[1] ?? null)}`);

    check('…and the returned diff names exactly that change',
      Array.isArray(applied.body?.diff) && applied.body.diff.length === 1
        && applied.body.diff[0].week === 2
        && applied.body.diff[0].before?.volume_multiplier === 1.0
        && applied.body.diff[0].after?.volume_multiplier === 1.05,
      `diff=${JSON.stringify(applied.body?.diff ?? null).slice(0, 110)}`);

    // EFFECT 2 · decision_traces, identified by the id the engine returned.
    // NOT a count delta over `subject_id`. That query is SATURATED: PostgREST
    // caps a plain select at 1000 rows, this subject already has ≥1000 traces,
    // and both sides of the subtraction read exactly 1000 — so the assertion
    // could never fail no matter what the engine did. Observed, then fixed.
    //
    // The id the engine RETURNED is the precise handle, and it carries more
    // information than a delta ever could: that this exact row exists, and that
    // its context names this program.
    const traceRow = await svc(`decision_traces?id=eq.${appliedTraceId}&select=id,context`);
    check('EFFECT 2 — the decision_traces row the engine reported exists, and its '
        + 'context names THIS program (asserted by id, not by a capped count)',
      !!appliedTraceId && n(traceRow.body) === 1
        && ONE(traceRow.body).context?.program_id === prog2
        && ONE(traceRow.body).context?.type === 'regeneration',
      `trace_id=${appliedTraceId} context=`
      + `${JSON.stringify(ONE(traceRow.body).context ?? null).slice(0, 90)}`);

    // The same SCOPED query the pending_approval check uses, now run where a write
    // definitely happened. This is what proves that check is capable of failing:
    // if `context->>program_id` scoping did not actually find traces, it would
    // read 0 here, and the "no write" assertion elsewhere would be passing for
    // the wrong reason — vacuous in a way no amount of green would reveal.
    const scopedTraces = await countOf(`decision_traces?context->>program_id=eq.${prog2}`);
    check('the SCOPED trace query finds the applied branch\'s write — so the same '
        + 'query returning 0 on the pending_approval branch means "no write", '
        + 'not "the query cannot see writes"',
      scopedTraces === 1, `scoped traces for this program=${scopedTraces}`);

    // EFFECT 3 · program_versions, via snapshot_program_version. Source-confirmed:
    // the applied branch calls it, and 116 shows it INSERTs program_versions.
    const versionsAfter = await countOf(`program_versions?program_id=eq.${prog2}`);
    check('EFFECT 3 — snapshot_program_version wrote a program_versions row for '
        + 'THIS program (scoped, so a concurrent insert cannot satisfy it)',
      versionsAfter === versionsBefore + 1,
      `program_versions ${versionsBefore} → ${versionsAfter}`);

    // The pair, on the write branch too.
    const strangerApplied = await rpc(attacker, 'regenerate_program',
      { p_program_id: prog2, p_week: 1, p_approved: true });
    check('regenerate_program() REFUSES a stranger on the SAME program even on the '
        + 'write branch — and the plan is unchanged by the attempt',
      strangerApplied.status === 403 && strangerApplied.body?.code === '42501',
      `status=${strangerApplied.status} code=${strangerApplied.body?.code ?? '-'}`);
    const planAfterStranger = ONE((await svc(
      `workout_programs?id=eq.${prog2}&select=plan`)).body).plan;
    check('…the refused call wrote NOTHING — denial with no side effect',
      planAfterStranger?.weeks?.[1]?.volume_multiplier === 1.05
        && await countOf(`program_versions?program_id=eq.${prog2}`) === versionsAfter,
      'plan and program_versions identical to the authorized call\'s result');

    // ── §3 · SUBJECT-SCOPED · the subject themselves ─────────────────────────
    section('§3 · subject-scoped: the subject is admitted, a stranger is not');
    for (const [fn, args] of [
      ['predict_client', { p_subject: victimId, p_program: null }],
      ['assemble_weekly_review', { p_subject: victimId, p_program: null, p_week: 1 }],
    ]) {
      const ok = await rpc(victim, fn, args);
      check(`${fn}() ADMITS the subject themselves (200)`, ok.status === 200,
        `status=${ok.status} ${JSON.stringify(ok.body || '').slice(0, 70)}`);
      // Declared contracts, read from 095 and 096:
      //   predict_client         {status:'no_data', program_id} | {status:'ok', program_id,
      //                           engine_version, weeks_completed, duration_weeks, goal, …}
      //   assemble_weekly_review {status:'no_feedback', week}    | {status:'ok', type:'weekly_review',
      //                           client_name, week, week_summary, completion, recovery, …}
      const expected = fn === 'predict_client'
        ? { states: ['no_data', 'ok'], always: ['status', 'program_id'] }
        : { states: ['no_feedback', 'ok'], always: ['status', 'week'] };
      check(`${fn}() returns its declared contract — a known status and its `
          + `invariant keys, not merely "an object"`,
        expected.states.includes(ok.body?.status)
          && expected.always.every((k) => k in (ok.body || {})),
        `status=${ok.body?.status} keys=${Object.keys(ok.body || {}).join(',')}`);
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
    // The applied branch's trace is removed by the id the ENGINE returned —
    // the most precise handle available, and better than a predicate sweep over
    // a provenance table other suites count.
    for (const id of createdTraceIds()) {
      await svc(`decision_traces?id=eq.${id}`, { method: 'DELETE' });
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
  if (prog2) {
    const leftVersions = await countOf(`program_versions?program_id=eq.${prog2}`);
    check('no program_versions row survives for the applied-branch fixture',
      leftVersions === 0, `rows=${leftVersions}`);
    // The DDL says ON DELETE CASCADE. That is a claim about the schema; this is
    // the observation. If the cascade were ever dropped, teardown would silently
    // start leaving feedback rows behind and nothing else would notice.
    const leftFeedback = await countOf(`weekly_feedback?program_id=eq.${prog2}`);
    check('weekly_feedback was removed by the FK CASCADE — observed, not inferred '
        + 'from 094 declaring `ON DELETE CASCADE`',
      leftFeedback === 0, `rows=${leftFeedback}`);
  }
  const leftProgs2 = await svc(`workout_programs?name=eq.${TAG2}&select=id`);
  check('no applied-branch program survives', n(leftProgs2.body) === 0,
    `rows=${n(leftProgs2.body)}`);

  // Also NOT an id-set diff over the subject: `traceIdsBefore` was built from the
  // same 1000-row-capped window, so a trace created outside it would be invisible
  // and this check would pass while leaving the row behind. Each trace this run
  // created is looked up by its OWN id instead.
  const created = createdTraceIds();
  let strays = 0;
  for (const id of created) {
    const r = await svc(`decision_traces?id=eq.${id}&select=id`);
    if (n(r.body) !== 0) strays++;
  }
  check('no decision_traces row created by this run survives — each looked up by '
      + 'its own id, because a capped id-set diff could not see one',
    strays === 0, `${strays} stray of ${created.length} engine-reported trace(s)`);

  return summary('D23 · FG-3 positive authorization legs');
}

export default await run();
