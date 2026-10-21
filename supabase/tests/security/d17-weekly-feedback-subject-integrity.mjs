// D17 · ENG-02 — `weekly_feedback.subject_id`, and the write path that deriving it
// would otherwise have opened. Live against QA, migration 175.
//
// WHY THE FREEZE IS TESTED AS HARD AS THE DERIVATION. Migration 117 split 094's
// `FOR ALL` policy to take DELETE away from the subject, but left the subject arm on
// UPDATE. That arm has been DEAD CODE ever since, for one reason: `subject_id` was
// never written, so no subject could match it. Deriving the subject WAKES it, over a
// row containing `coach_note` — the coach's written assessment of that person. So the
// derivation and the freeze ship together, and this suite proves both. A green
// "subject_id is now populated" without the freeze assertions would be a remediation
// that opened a hole and reported success.
//
// WHY EVERY DENIAL IS CHECKED BY RE-READING THE ROW. PostgREST answers 204 to a PATCH
// whether or not RLS or a BEFORE trigger silently discarded the change — and a column
// freeze NEVER errors, it just preserves OLD. So a status code here proves nothing at
// all, and every freeze assertion below compares the value before and after.
import { IDENT, signIn, rest, mutate, rpc, svc, check, section, summary, beginSuite, n }
  from './lib.mjs';

const ONE = (b) => (Array.isArray(b) ? b[0] : b) || {};

async function uidOf(key) {
  const r = await svc(`user_profiles?email=eq.${encodeURIComponent(IDENT[key].email)}&select=id`);
  return ONE(r.body).id;
}

const MARK = 'QA-D17';

async function run() {
  beginSuite();
  const coach = await signIn('coach');
  const victim = await signIn('victim');
  const coachUid = await uidOf('coach');
  const victimUid = await uidOf('victim');
  const attackerUid = await uidOf('attacker');

  // Purge by marker FIRST, so a crashed earlier run cannot make a correct assertion
  // fail forever — the §161 defect, not repeated.
  const purge = async () => {
    const progs = await svc(`workout_programs?name=like.${MARK}*&select=id`);
    for (const p of (Array.isArray(progs.body) ? progs.body : [])) {
      await svc(`weekly_feedback?program_id=eq.${p.id}`, { method: 'DELETE' });
      await svc(`workout_program_assignments?program_id=eq.${p.id}`, { method: 'DELETE' });
      await svc(`workout_programs?id=eq.${p.id}`, { method: 'DELETE' });
    }
  };

  const mkProgram = async (suffix) => {
    const r = await svc('workout_programs', { method: 'POST',
      headers: { Prefer: 'return=representation' },
      body: { name: `${MARK}-${suffix}`, coach_id: coachUid, duration_weeks: 4 } });
    return ONE(r.body).id;
  };
  const assign = (programId, clientId) => svc('workout_program_assignments',
    { method: 'POST', body: { program_id: programId, client_id: clientId,
      coach_id: coachUid, status: 'active' } });

  try {
    await purge();

    // ── 1 · the derivation, where it is unambiguous ────────────────────────
    section('ENG-02 · subject_id is derived from the single active assignment');
    const pOne = await mkProgram('one');
    check('arranged: a program with exactly ONE active assignment',
      pOne && (await assign(pOne, victimUid)).status < 300, `program=${pOne}`);

    const ins = await mutate(coach, 'weekly_feedback', 'POST',
      { program_id: pOne, week: 1, completion_pct: 80, coach_note: 'coach wrote this' });
    const rowOne = ONE((await svc(
      `weekly_feedback?program_id=eq.${pOne}&select=id,subject_id,coach_note`)).body);
    check('the coach can record a week, and subject_id is DERIVED — not left NULL as ' +
          'ENG-02 recorded, and not supplied by the client',
      ins.status < 300 && rowOne.subject_id === victimUid,
      `insert=${ins.status} subject_id=${rowOne.subject_id} expected=${victimUid}`);

    // ── 2 · the REFUSAL, proved rather than assumed ────────────────────────
    section('the derivation declines to guess where the model is ambiguous');
    const pTwo = await mkProgram('two');
    await assign(pTwo, victimUid);
    await assign(pTwo, attackerUid);
    const insTwo = await mutate(coach, 'weekly_feedback', 'POST',
      { program_id: pTwo, week: 1, completion_pct: 50 });
    const rowTwo = ONE((await svc(
      `weekly_feedback?program_id=eq.${pTwo}&select=subject_id`)).body);
    check('a program with TWO active assignments leaves subject_id NULL — whose body a ' +
          'coaching decision was made about is not something to guess',
      insTwo.status < 300 && rowTwo.subject_id === null,
      `insert=${insTwo.status} subject_id=${JSON.stringify(rowTwo.subject_id)}`);

    const pZero = await mkProgram('zero');
    const insZero = await mutate(coach, 'weekly_feedback', 'POST',
      { program_id: pZero, week: 1, completion_pct: 50 });
    const rowZero = ONE((await svc(
      `weekly_feedback?program_id=eq.${pZero}&select=subject_id`)).body);
    check('a program with NO active assignment leaves subject_id NULL',
      insZero.status < 300 && rowZero.subject_id === null,
      `insert=${insZero.status} subject_id=${JSON.stringify(rowZero.subject_id)}`);

    // ── 3 · what ENG-02 was for · the subject can see their own record ─────
    section('ENG-02 · the subject can now read the record of their own week');
    const asSubject = await rest(victim, `weekly_feedback?program_id=eq.${pOne}&select=id,subject_id`);
    const svcCount = await svc(`weekly_feedback?program_id=eq.${pOne}&select=id`);
    check('the SUBJECT reads their own feedback row — the same count the service role ' +
          'sees, so this is a real crossing and not an empty 200',
      asSubject.status < 300 && n(asSubject.body) === n(svcCount.body) && n(svcCount.body) === 1,
      `subject=${n(asSubject.body)} service=${n(svcCount.body)}`);
    const otherSees = await rest(victim, `weekly_feedback?program_id=eq.${pTwo}&select=id`);
    check('a NULL-subject row is still invisible to that same member, so the read is ' +
          'scoped by subject_id and not merely open',
      n(otherSees.body) === 0, `rows=${n(otherSees.body)}`);

    // ── 4 · THE HOLE THAT 175 CLOSES ──────────────────────────────────────
    section('the subject CANNOT overwrite the note their coach wrote about them');
    const before = ONE((await svc(
      `weekly_feedback?program_id=eq.${pOne}&select=coach_note`)).body).coach_note;
    const attempt = await mutate(victim,
      `weekly_feedback?program_id=eq.${pOne}`, 'PATCH', { coach_note: 'TAMPERED' });
    const after = ONE((await svc(
      `weekly_feedback?program_id=eq.${pOne}&select=coach_note`)).body).coach_note;
    check('coach_note survives a subject PATCH — asserted by RE-READING the row, ' +
          'because a column freeze never errors and PostgREST answers 204 either way',
      before === 'coach wrote this' && after === before,
      `status=${attempt.status} before=${JSON.stringify(before)} after=${JSON.stringify(after)}`);

    // The subject's own note must still work, or the freeze has broken the feature.
    const ownNote = await mutate(victim,
      `weekly_feedback?program_id=eq.${pOne}`, 'PATCH', { client_note: 'felt strong' });
    const noteBack = ONE((await svc(
      `weekly_feedback?program_id=eq.${pOne}&select=client_note`)).body).client_note;
    check('the subject CAN still write their own client_note — the freeze is scoped to ' +
          "the coach's column, not a blanket read-only",
      ownNote.status < 300 && noteBack === 'felt strong',
      `status=${ownNote.status} client_note=${JSON.stringify(noteBack)}`);

    const coachEdit = await mutate(coach,
      `weekly_feedback?program_id=eq.${pOne}`, 'PATCH', { coach_note: 'revised by coach' });
    const coachBack = ONE((await svc(
      `weekly_feedback?program_id=eq.${pOne}&select=coach_note`)).body).coach_note;
    check('the COACH can still revise their own note, so the freeze discriminates by ' +
          'actor rather than forbidding the column outright',
      coachEdit.status < 300 && coachBack === 'revised by coach',
      `status=${coachEdit.status} coach_note=${JSON.stringify(coachBack)}`);

    // ── 5 · identity is frozen ────────────────────────────────────────────
    section('identity columns are frozen on UPDATE');
    const reassign = await mutate(victim,
      `weekly_feedback?program_id=eq.${pOne}`, 'PATCH', { subject_id: attackerUid });
    const stillMine = ONE((await svc(
      `weekly_feedback?program_id=eq.${pOne}&select=subject_id`)).body).subject_id;
    check('a subject cannot reassign the row to someone else',
      stillMine === victimUid, `status=${reassign.status} subject_id=${stillMine}`);

    const moveProgram = await mutate(coach,
      `weekly_feedback?program_id=eq.${pOne}`, 'PATCH', { program_id: pZero, week: 99 });
    const identity = ONE((await svc(
      `weekly_feedback?subject_id=eq.${victimUid}&select=program_id,week`)).body);
    check('program_id and week are frozen even for the coach — which program and which ' +
          'week a record describes is not an editable field',
      identity.program_id === pOne && identity.week === 1,
      `status=${moveProgram.status} program_id=${identity.program_id} week=${identity.week}`);

    // ── 5b · THE POINT OF ENG-02, PROVED END TO END ───────────────────────
    // A populated column is not a working system. ENG-02's central claim is that
    // `needs_approval` NEVER FIRES for coach-guided clients, because `evaluate_week`
    // reads `coaching_mode` through `fb.subject_id` and that was always NULL. So the
    // two cases are run side by side: a derived subject and an undecidable one, over
    // the same RPC. If the derivation did nothing useful, both would answer the same.
    section('ENG-02 · the approval matrix fires again (evaluate_week, 127:161)');
    const priorMode = ONE((await svc(
      `user_profiles?id=eq.${victimUid}&select=coaching_mode`)).body).coaching_mode;
    await svc(`user_profiles?id=eq.${victimUid}`,
      { method: 'PATCH', body: { coaching_mode: 'coach_guided' } });
    // THE FIXTURE MUST ISOLATE THE MODE, AND MY FIRST ONE DID NOT. I first reported
    // `pain`, which is the top-priority branch — and `needs_approval` is
    // `(coach_guided and action <> CONTINUE) OR (rules && INJURY_ADAPTATION)`
    // (`127:188`), because "injury needs approval in every mode". So an injury
    // approves whatever the coaching mode is, and the undecidable program ALSO
    // returned needs_approval = true. The code was right and fail-safe; the fixture
    // chose the one branch where the mode cannot be the variable, and the contrast
    // assertion below is what caught it.
    //
    // Low adherence instead: recovery 70 skips the injury, fatigue and recovery
    // branches, and completion_pct 50 lands on ADHERENCE_SUPPORT — a non-CONTINUE
    // action that is NOT an injury. Now the coaching mode is the only difference
    // between the two programs.
    const adherence = { pain: [], recovery: 70, energy: 80, completion_pct: 50 };
    await svc(`weekly_feedback?program_id=eq.${pOne}`, { method: 'PATCH', body: adherence });
    await svc(`weekly_feedback?program_id=eq.${pTwo}`, { method: 'PATCH', body: adherence });

    const evalOne = await rpc(coach, 'evaluate_week',
      { p_program_id: pOne, p_week: 1 });
    const evalTwo = await rpc(coach, 'evaluate_week',
      { p_program_id: pTwo, p_week: 1 });
    const bodyOne = evalOne.body || {};
    const bodyTwo = evalTwo.body || {};
    check('with subject_id derived, evaluate_week RESOLVES the coaching mode — the ' +
          'read that ENG-02 recorded as permanently NULL',
      bodyOne.coaching_mode === 'coach_guided',
      `coaching_mode=${JSON.stringify(bodyOne.coaching_mode)} action=${JSON.stringify(bodyOne.action)}`);
    check('…and needs_approval FIRES for a coach-guided client on a non-CONTINUE ' +
          'action, so the approval matrix is no longer silently disabled',
      bodyOne.needs_approval === true && bodyOne.action !== 'CONTINUE',
      `needs_approval=${JSON.stringify(bodyOne.needs_approval)} action=${JSON.stringify(bodyOne.action)}`);
    // ── 177 · THE CONTRAST, AND THE APPROVAL MATRIX FAILING CLOSED ────────
    // The undecidable program reports coaching_mode "unknown", which is the degenerate
    // answer ENG-02 described — and it now requires APPROVAL rather than returning the
    // NULL that every consumer read as "apply it".
    //
    // §171.5 recorded that NULL as an owner question. It was not one: auto-apply is
    // licensed for self_guided and ai_guided and nothing else (`decision-log.md:18`),
    // and a client whose mode is unknown MAY be coach-guided — so applying a
    // consequential change without sign-off risks exactly the bypass
    // `product-bible.md:111` forbids. Migration 177 fixes it, fails closed, and makes
    // the field a total boolean.
    check('METRIC-ENG · the UNDECIDABLE program still reports coaching_mode "unknown", ' +
          'so the contrast above is evidence rather than coincidence',
      bodyTwo.coaching_mode === 'unknown',
      `coaching_mode=${JSON.stringify(bodyTwo.coaching_mode)}`);
    check('177 · an unestablished coaching mode now REQUIRES approval for a ' +
          'consequential action — it no longer returns NULL, which every consumer read ' +
          'as "apply it without sign-off"',
      bodyTwo.needs_approval === true,
      `needs_approval=${JSON.stringify(bodyTwo.needs_approval)} ` +
      `action=${JSON.stringify(bodyTwo.action)}`);
    check('177 · needs_approval is a TOTAL boolean — never null, whatever the mode',
      typeof bodyOne.needs_approval === 'boolean' &&
      typeof bodyTwo.needs_approval === 'boolean',
      `derived=${JSON.stringify(bodyOne.needs_approval)} ` +
      `undecidable=${JSON.stringify(bodyTwo.needs_approval)}`);

    // AUTO-APPLY MUST STILL WORK FOR THE TWO MODES IT IS LICENSED FOR, or 177 has
    // traded a bypass for a flood of needless approvals.
    for (const mode of ['self_guided', 'ai_guided']) {
      await svc(`user_profiles?id=eq.${victimUid}`,
        { method: 'PATCH', body: { coaching_mode: mode } });
      const ev = await rpc(coach, 'evaluate_week', { p_program_id: pOne, p_week: 1 });
      check(`177 · a ${mode} client still AUTO-APPLIES a minor change — the licence ` +
            'decision-log.md:18 grants is intact',
        (ev.body || {}).needs_approval === false,
        `needs_approval=${JSON.stringify((ev.body || {}).needs_approval)} ` +
        `mode=${JSON.stringify((ev.body || {}).coaching_mode)}`);
    }
    // And the injury arm still approves in EVERY mode, which is the rule my first
    // fixture tripped over (§171.4).
    await svc(`user_profiles?id=eq.${victimUid}`,
      { method: 'PATCH', body: { coaching_mode: 'self_guided' } });
    await svc(`weekly_feedback?program_id=eq.${pOne}`,
      { method: 'PATCH', body: { pain: ['knee'] } });
    const evInjury = await rpc(coach, 'evaluate_week', { p_program_id: pOne, p_week: 1 });
    check('177 · an INJURY still requires approval even for a self_guided client — ' +
          '"injury needs approval in every mode" survived the change',
      (evInjury.body || {}).needs_approval === true,
      `needs_approval=${JSON.stringify((evInjury.body || {}).needs_approval)}`);

    await svc(`user_profiles?id=eq.${victimUid}`,
      { method: 'PATCH', body: { coaching_mode: priorMode ?? null } });

    // ── 5c · B1 RESOLVED BY EVIDENCE, AND NOW A MONITORED INVARIANT ───────
    // V5 §171.3 recorded "which subject owns a multi-assignment program's feedback" as
    // an architecture question. The evidence answers it, and it is not a choice:
    //
    //   * `generate_client_plan` (`121:221`) inserts a FRESH program and then EXACTLY
    //     ONE assignment for the calling member, so a generated plan is 1:1 with its
    //     client by construction — and generated plans are what this screen operates on;
    //   * `weekly_feedback` is `unique (program_id, week)`. A template assigned to N
    //     clients cannot have one feedback row per week for all of them, whichever
    //     subject were chosen. The ambiguous state is INCOHERENT for this table, not a
    //     model to pick between.
    //
    // So 175's refusal is right, and the useful artifact is not an owner question but an
    // invariant that makes the incoherent state visible if it ever occurs. Every row
    // must either carry a subject, or belong to a program that genuinely has ≠1 active
    // assignments — in which case the NULL is explained rather than a defect.
    section('B1 · every feedback row has a subject, or an explained absence');
    const allFb = (await svc('weekly_feedback?select=program_id,subject_id')).body || [];
    const assigns = (await svc(
      'workout_program_assignments?status=eq.active&select=program_id,client_id')).body || [];
    const activeCount = {};
    for (const a of assigns) activeCount[a.program_id] = (activeCount[a.program_id] || 0) + 1;
    const unexplained = allFb.filter((f) =>
      f.subject_id === null && activeCount[f.program_id] === 1);
    check('no feedback row has an UNEXPLAINED null subject — a null is only ever ' +
          'accompanied by a program with zero or several active assignments',
      unexplained.length === 0,
      `rows=${allFb.length} unexplained=${unexplained.length} ` +
      `(ambiguous programs are expected to carry nulls)`);
    // NON-VACUITY. This suite arranged both an explained null and a derived subject, so
    // the population is not empty and the assertion is not passing over nothing.
    check('…and the invariant was checked against a NON-EMPTY population containing ' +
          'both a derived subject and an explained null',
      allFb.length >= 2 &&
      allFb.some((f) => f.subject_id !== null) &&
      allFb.some((f) => f.subject_id === null),
      `rows=${allFb.length} derived=${allFb.filter((f) => f.subject_id !== null).length} ` +
      `null=${allFb.filter((f) => f.subject_id === null).length}`);

    // ── 6 · the service path is untouched ─────────────────────────────────
    section('the internal path still writes freely');
    const svcPatch = await svc(`weekly_feedback?program_id=eq.${pOne}`,
      { method: 'PATCH', body: { coach_note: 'service wrote this' } });
    const svcBack = ONE((await svc(
      `weekly_feedback?program_id=eq.${pOne}&select=coach_note`)).body).coach_note;
    check('service_role is passed through, as 138:101 established for the sibling ' +
          'trigger — erasure and provenance decisions stay there',
      svcPatch.status < 300 && svcBack === 'service wrote this',
      `status=${svcPatch.status} coach_note=${JSON.stringify(svcBack)}`);
  } finally {
    await purge();
  }
  return summary('D17 · weekly_feedback subject integrity');
}

export default await run();
