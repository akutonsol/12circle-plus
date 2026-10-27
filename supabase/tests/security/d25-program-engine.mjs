// D25 · the coach programme engine (migration 186), live — through the same
// public RPC the app's "Generate week 1" step calls (materialize_program_week).
//
// GATED ON THE DECLARED MIGRATION STATE (migration-state.mjs). Until 186 is
// applied to QA every assertion is SKIPPED (never a pass) and the engine is NOT
// called: the pre-186 engine writes empty training days and reports success, so
// calling it would plant exactly the defect this suite exists to forbid.
//
// The intelligence substrate (registry EB-4) decides WHICH half is asserted once
// 186 is applied, and the other half is recorded as SKIPPED, by name:
//   * substrate EMPTY     -> generation must REFUSE (ENGINE_NO_SELECTION) and
//                            write nothing; "complete prescription" is SKIPPED.
//   * substrate POPULATED -> generation must produce one complete, canonical day
//                            per session; the empty-refusal case is SKIPPED.
// Asserted either way (they do not depend on the substrate): a coach-edited week
// is never silently overwritten, a malformed prescription is refused and writes
// nothing, and another coach cannot generate for this programme.
//
// Locally verified twin: supabase/tests/local/engine_materialize_replay.sql
// (28/28 with 186). This suite has NOT yet executed its strict half against QA.
//
// MIGRATION 188 (pending) changes what "populated" means: the engine selects only
// exercises certified for Program Builder WITH human-approved intelligence (187),
// within each session's focus. Once 188 is declared applied, the branch is chosen
// by asking build_workout — a STABLE function that writes nothing — whether every
// session of the plan has an eligible exercise, not by counting rows (draft rows
// would otherwise demand a success the engine must refuse). Its fail-closed module
// check is asserted only then, and SKIPPED before.

import { IDENT, signIn, rest, rpc, svc, check, skip, section, summary, beginSuite, countExact }
  from './lib.mjs';
import { migrationApplied } from './migration-state.mjs';

const MARK = 'QA-D25';
const ONE = (b) => (Array.isArray(b) ? b[0] : b) || {};
const uidOf = async (key) =>
  ONE((await svc(`user_profiles?email=eq.${encodeURIComponent(IDENT[key].email)}&select=id`)).body).id;
const DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const CTX = { goal: 'hypertrophy', experience: 'intermediate', size: 5 }; // what Program Builder sends
const errText = (r) => String(r.body?.message ?? r.body ?? '');

async function run() {
  beginSuite();

  if (!migrationApplied('186')) {
    section('programme engine — migration 186 is NOT applied to QA');
    const why = 'migration 186 is declared PENDING for QA (supabase/expected_applied.json); ' +
      'the engine is not called, because the pre-186 engine writes empty days';
    for (const name of [
      'generation produces one complete day per session, or refuses with ENGINE_NO_SELECTION',
      'every generated exercise is a canonical prescription with no invented load',
      'a second generation of the same week is refused (ENGINE_WEEK_EXISTS)',
      'a coach-edited week is never silently overwritten',
      'a malformed prescription is refused and writes nothing',
      'a signed-in non-owner cannot generate for this programme (42501)',
      '188: build_workout without a module is refused (ENGINE_UNKNOWN_MODULE)',
    ]) skip(name, why);
    skip('a genuine SECOND COACH cannot generate for this programme',
      'not testable: QA has no second coach fixture (only the p1-coach owner and p1-attacker, a client)');
    return summary('D25 programme engine (186)');
  }

  const coach = await signIn('coach');
  const attacker = await signIn('attacker');
  const coachUid = await uidOf('coach');
  const runStart = new Date().toISOString();

  const purge = async () => {
    const progs = await svc(`workout_programs?name=like.${MARK}*&select=id`);
    for (const p of (Array.isArray(progs.body) ? progs.body : [])) {
      await svc(`program_workouts?program_id=eq.${p.id}`, { method: 'DELETE' });
      await svc(`program_versions?program_id=eq.${p.id}`, { method: 'DELETE' });
      await svc(`workout_programs?id=eq.${p.id}`, { method: 'DELETE' });
    }
  };

  try {
    await purge();
    const plan = await rpc(coach, 'plan_program', { p_strategy: {
      program_type: 'Hypertrophy', duration_weeks: 4, frequency: 3, primary_focus: 'Full Body',
      progression_model: 'linear', deload_strategy: 'every_4th' } });
    check('fixture: the planner returns a plan with weeks', Array.isArray(plan.body?.weeks), `${plan.status}`);
    const mk = async (suffix) => ONE((await svc('workout_programs', { method: 'POST', body: {
      coach_id: coachUid, name: `${MARK}-${suffix}`, plan: plan.body, strategy: {}, engine_generated: true } })).body).id;
    const progA = await mk('A');
    const progB = await mk('B');
    // Week 1 by its explicit `week` value, never by array position: the planner
    // does not promise ordering, and a deload or reordered plan would otherwise
    // compare the wrong week's split.
    const week1 = (Array.isArray(plan.body?.weeks) ? plan.body.weeks : []).find((w) => Number(w?.week) === 1);
    check('fixture: the plan contains an explicit week 1 with sessions',
      !!week1 && Array.isArray(week1.split) && week1.split.length > 0,
      `week1=${week1 ? `split ${JSON.stringify(week1.split)}` : 'absent'}`);
    const split = week1?.split || [];
    const days = (p, w) => countExact(`program_workouts?program_id=eq.${p}&week_number=eq.${w}`);

    // The substrate decides which half is asserted. exercise_intelligence is
    // keyed by exercise_id (no id column), so count it directly.
    let substrate;
    if (migrationApplied('188')) {
      let ready = split.length > 0;
      const status = [];
      for (const focus of split) {
        const b = await rpc(coach, 'build_workout', { p_context: { ...CTX, module: 'program_generator', focus } });
        status.push(`${focus}:${b.status < 300 ? b.body?.selection_status : b.status}`);
        ready = ready && b.status < 300 && b.body?.selection_status === 'ok';
      }
      substrate = ready ? 1 : 0;
      check('the eligible substrate is measurable (188: certified + approved, per session focus)',
        status.length === split.length && split.length > 0, status.join(' '));
    } else {
      const sub = await fetch(`${process.env.QA_URL}/rest/v1/exercise_intelligence?select=exercise_id&limit=1`,
        { headers: { apikey: process.env.QA_SERVICE, Authorization: `Bearer ${process.env.QA_SERVICE}`, Prefer: 'count=exact' } });
      substrate = Number((sub.headers.get('content-range') || '').split('/')[1]);
      check('the intelligence substrate is measurable', Number.isFinite(substrate), `rows=${substrate}`);
    }

    section(`generation (substrate rows: ${substrate})`);
    const gen = await rpc(coach, 'materialize_program_week', { p_program_id: progA, p_week: 1, p_context: CTX });
    if (substrate === 0) {
      check('EMPTY substrate: generation is REFUSED with ENGINE_NO_SELECTION',
        gen.status >= 400 && errText(gen).includes('ENGINE_NO_SELECTION'), `${gen.status} ${errText(gen).slice(0, 90)}`);
      check('…and NO training day was written', (await days(progA, 1)) === 0);
      skip('every generated exercise is a canonical prescription with no invented load',
        'EB-4: the intelligence substrate is empty on QA, so nothing can be generated to inspect');
      skip('a second generation of the same week is refused (ENGINE_WEEK_EXISTS)',
        'EB-4: needs a generated week first');
    } else {
      const sessions = gen.body?.sessions;
      check('POPULATED substrate: generation succeeds with one day per session in the split',
        gen.status < 300 && Array.isArray(sessions) && sessions.length === split.length && split.length > 0,
        `${gen.status} sessions=${Array.isArray(sessions) ? sessions.length : '?'} split=${split.length}`);
      const rows = await svc(`program_workouts?program_id=eq.${progA}&week_number=eq.1&select=day_of_week,exercises&order=sort_order`);
      const list = Array.isArray(rows.body) ? rows.body : [];
      const ex = list.flatMap((d) => d.exercises || []);
      check('every generated exercise is a canonical prescription with no invented load',
        list.length === split.length && list.every((d) => (d.exercises || []).length > 0) && ex.length > 0 &&
        ex.every((e) => Number.isInteger(e.sets) && e.sets >= 1 && Number.isInteger(e.reps)
          && Object.hasOwn(e, 'weight_kg') && e.weight_kg === null && e.exercise_instance_id && e.name) &&
        list.every((d) => DAYS.includes(d.day_of_week)),
        `${list.length} days, ${ex.length} exercises`);
      const again = await rpc(coach, 'materialize_program_week', { p_program_id: progA, p_week: 1, p_context: CTX });
      check('a second generation of the same week is refused (ENGINE_WEEK_EXISTS)',
        again.status >= 400 && errText(again).includes('ENGINE_WEEK_EXISTS') && (await days(progA, 1)) === split.length,
        `${again.status} ${errText(again).slice(0, 80)}`);
      skip('EMPTY substrate: generation is REFUSED with ENGINE_NO_SELECTION',
        'the substrate is populated on QA, so the empty case cannot be exercised live');
    }

    section('asserted regardless of the substrate');
    // A coach-edited week: a hand-built day, then a generation request without replace.
    // Arranged as service_role: it is a FIXTURE (a coach's hand-built day), not the thing under test.
    await svc('program_workouts', { method: 'POST', prefer: 'return=minimal', body: {
      program_id: progB, week_number: 1, day_of_week: 'Monday', title: `${MARK} coach day`,
      exercises: [{ exercise_instance_id: 'd25-coach-1', name: 'Bench Press', sets: 4, reps: 6, weight_kg: 80, rest_seconds: 120 }],
      sort_order: 0 } });
    const before = JSON.stringify((await svc(`program_workouts?program_id=eq.${progB}&select=title,exercises`)).body);
    const over = await rpc(coach, 'materialize_program_week', { p_program_id: progB, p_week: 1, p_context: CTX });
    const after = JSON.stringify((await svc(`program_workouts?program_id=eq.${progB}&select=title,exercises`)).body);
    check('a coach-edited week is never silently overwritten',
      over.status >= 400 && errText(over).includes('ENGINE_WEEK_EXISTS') && before === after && before.includes('coach day'),
      `${over.status} ${errText(over).slice(0, 70)} unchanged=${before === after}`);

    const bad = await rpc(coach, 'materialize_program_week',
      { p_program_id: progA, p_week: 3, p_context: { ...CTX, reps: '8-12' } });
    check('a malformed prescription is refused and writes nothing',
      bad.status >= 400 && errText(bad).includes('ENGINE_BAD_PRESCRIPTION') && (await days(progA, 3)) === 0,
      `${bad.status} ${errText(bad).slice(0, 80)}`);

    // p1-attacker is a CLIENT-role identity: this proves a signed-in user who does
    // not own the programme is refused. It does NOT prove the second-coach case —
    // there is no second-coach fixture — and is named accordingly.
    const foreign = await rpc(attacker, 'materialize_program_week', { p_program_id: progA, p_week: 2, p_context: CTX });
    check('a signed-in non-owner cannot generate for this programme (42501)',
      foreign.status >= 400 && (foreign.body?.code === '42501' || /not authorized/i.test(errText(foreign)))
        && (await days(progA, 2)) === 0,
      `${foreign.status} ${foreign.body?.code ?? ''}`);
    skip('a genuine SECOND COACH cannot generate for this programme',
      'not testable: QA has no second coach fixture (only the p1-coach owner and p1-attacker, a client)');

    if (migrationApplied('188')) {
      const noModule = await rpc(coach, 'build_workout', { p_context: { goal: 'hypertrophy', size: 3 } });
      check('188: build_workout without a module is refused (ENGINE_UNKNOWN_MODULE)',
        noModule.status >= 400 && errText(noModule).includes('ENGINE_UNKNOWN_MODULE'),
        `${noModule.status} ${errText(noModule).slice(0, 80)}`);
    } else {
      skip('188: build_workout without a module is refused (ENGINE_UNKNOWN_MODULE)',
        'migration 188 is not declared applied for QA (supabase/expected_applied.json)');
    }
  } finally {
    await purge();
    // generate_workout records a decision trace per session it builds.
    await svc(`decision_traces?created_by=eq.${coachUid}&created_at=gte.${encodeURIComponent(runStart)}`, { method: 'DELETE' });
  }
  return summary('D25 programme engine (186)');
}

export default await run();
