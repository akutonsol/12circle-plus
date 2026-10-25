// D24 · OD-14 / QAX-SEC-03 — the coach write arm of six policies requires an
// ACTIVE coach-client relationship (migration 185), live.
//
// GATED ON THE DECLARED MIGRATION STATE (migration-state.mjs). While 185 is not
// applied to QA every assertion here is recorded as SKIPPED — never as a pass —
// and NO request is made: against the pre-185 policies the "refused" writes
// would SUCCEED, i.e. this suite would be planting rows about the victim to learn
// something the ledger already says. The change that applies 185 and moves the
// frontier makes it strict in the same diff, because the gate reads the manifest
// and ENV-3 holds the manifest equal to the real ledger.
//
// Locally verified twin: supabase/tests/local/od_qax2_od14_replay.sql (47/47 on a
// replay with 185). This suite has NOT yet executed its strict half against QA.
//
// What it asserts once 185 is applied, per table:
//   * an UNRELATED user cannot write a row naming the victim (row count, not status);
//   * a PENDING "coach" cannot; a CANCELLED one cannot;
//   * the ACTIVE coach can (positive control — proves the statement is valid);
//   * a row the cancelled coach authored earlier stays readable to them and
//     cannot be changed (preserved, not mutated).
// Fixtures are marked and removed; the run purges by marker first.

import { IDENT, signIn, mutate, rest, svc, check, skip, section, summary, beginSuite, countExact }
  from './lib.mjs';
import { migrationApplied } from './migration-state.mjs';
import { verifyRelationship, failDependents } from './fixture-state.mjs';

const MARK = 'QA-D24';
const ONE = (b) => (Array.isArray(b) ? b[0] : b) || {};
const uidOf = async (key) =>
  ONE((await svc(`user_profiles?email=eq.${encodeURIComponent(IDENT[key].email)}&select=id`)).body).id;

// One statement shape per table, parameterised by the acting coach_id. The same
// shape must LAND for the active coach, or a refusal proves nothing.
const TABLES = [
  ['client_habits',               (c, v) => ({ client_id: v, coach_id: c, name: MARK })],
  ['action_items',                (c, v) => ({ client_id: v, coach_id: c, title: MARK })],
  ['coaching_calls',              (c, v) => ({ coach_id: c, client_id: v, scheduled_at: new Date().toISOString() })],
  ['coach_video_responses',       (c, v) => ({ coach_id: c, client_id: v })],
  ['client_nutrition_plans',      (c, v) => ({ client_id: v, coach_id: c, calories_target: 1234, is_active: false, notes: MARK })],
  ['workout_program_assignments', (c, v, prog) => ({ program_id: prog, client_id: v, coach_id: c })],
];

async function run() {
  beginSuite();

  if (!migrationApplied('185')) {
    section('OD-14 coach write arms — migration 185 is NOT applied to QA');
    const why = 'migration 185 is declared PENDING for QA (supabase/expected_applied.json); ' +
      'strict once the frontier passes 185';
    for (const [t] of TABLES) {
      for (const who of ['an unrelated user', 'a PENDING coach', 'a CANCELLED coach'])
        skip(`${who} cannot write ${t} rows naming the victim`, why);
      skip(`the ACTIVE coach still writes ${t} (positive control)`, why);
    }
    skip('a cancelled coach still reads, but cannot change, a row they authored', why);
    return summary('D24 coach write arms (185)');
  }

  const coach = await signIn('coach');
  const attacker = await signIn('attacker');
  const coachUid = await uidOf('coach');
  const victimUid = await uidOf('victim');
  const attackerUid = await uidOf('attacker');
  const REL = 'coach_client_relationships';

  const purge = async () => {
    for (const [t] of TABLES) {
      await svc(`${t}?client_id=eq.${victimUid}&coach_id=in.(${coachUid},${attackerUid})`, { method: 'DELETE' });
    }
    await svc(`workout_programs?name=eq.${MARK}`, { method: 'DELETE' });
    await svc(`${REL}?client_id=eq.${victimUid}&coach_id=in.(${coachUid},${attackerUid})`, { method: 'DELETE' });
  };

  try {
    await purge();
    // Every relationship fixture is READ BACK before anything depends on it
    // (fixture-state.mjs). A fixture in the wrong state fails, and the
    // assertions that depend on it are recorded as FAILED, not run.
    const rel = (coachId, expected, label) => verifyRelationship({
      read: svc, check, coachUid: coachId, clientUid: victimUid, expected, label });

    // The active relationship the positive control needs, and a programme the
    // assignment statement can point at.
    await svc(REL, { method: 'POST', prefer: 'return=minimal',
      body: { coach_id: coachUid, client_id: victimUid, status: 'active',
              initiated_by: 'client', activated_at: new Date().toISOString() } });
    const activeOk = await rel(coachUid, 'active', 'the coach is ACTIVE with the victim');
    const prog = ONE((await svc('workout_programs', { method: 'POST',
      body: { coach_id: coachUid, name: MARK } })).body).id;
    check('fixture: a programme exists for the assignment statement', !!prog, `${prog}`);

    const attempt = async (label, who, actorUid, fixtureOk = true, fixtureWhy = '') => {
      if (!fixtureOk) {
        failDependents(check, TABLES.map(([t]) => `${label} cannot write ${t} rows naming the victim`), fixtureWhy);
        return;
      }
      for (const [t, row] of TABLES) {
        const scope = `${t}?client_id=eq.${victimUid}&coach_id=eq.${actorUid}`;
        const before = await countExact(scope);
        const m = await mutate(who, t, 'POST', row(actorUid, victimUid, prog));
        const after = await countExact(scope);
        check(`${label} cannot write ${t} rows naming the victim`, after === before,
          `rows ${before}->${after} (status ${m.status}) — asserted by row count`);
      }
    };

    section('refusals');
    // "Unrelated" means NO relationship row at all — verified, not assumed.
    const none = await svc(`${REL}?coach_id=eq.${attackerUid}&client_id=eq.${victimUid}&select=status`);
    const unrelatedOk = Array.isArray(none.body) && none.body.length === 0;
    check('fixture: the unrelated user has NO relationship with the victim', unrelatedOk,
      `persisted: ${Array.isArray(none.body) ? (none.body.map((x) => x.status).join(',') || 'no row') : `unreadable (status ${none.status})`}`);
    await attempt('an unrelated user', attacker, attackerUid, unrelatedOk,
      'the unrelated-user fixture is not in place (a relationship row exists)');

    await svc(REL, { method: 'POST', prefer: 'return=minimal',
      body: { coach_id: attackerUid, client_id: victimUid, status: 'pending', initiated_by: 'coach' } });
    const pendingOk = await rel(attackerUid, 'pending', 'the PENDING-coach case');
    await attempt('a PENDING coach', attacker, attackerUid, pendingOk,
      'the PENDING relationship fixture did not persist as pending');

    await svc(`${REL}?coach_id=eq.${attackerUid}&client_id=eq.${victimUid}`, { method: 'PATCH',
      prefer: 'return=minimal',
      body: { status: 'cancelled', cancelled_by: 'client', cancelled_at: new Date().toISOString() } });
    const cancelledOk = await rel(attackerUid, 'cancelled', 'the CANCELLED-coach case');
    await attempt('a CANCELLED coach', attacker, attackerUid, cancelledOk,
      'the relationship did not persist as cancelled');

    section('positive control — the ACTIVE coach still writes');
    if (!activeOk) {
      failDependents(check, TABLES.map(([t]) => `the ACTIVE coach still writes ${t} (positive control)`),
        'the ACTIVE relationship fixture did not persist as active');
    } else for (const [t, row] of TABLES) {
      const scope = `${t}?client_id=eq.${victimUid}&coach_id=eq.${coachUid}`;
      const before = await countExact(scope);
      const m = await mutate(coach, t, 'POST', row(coachUid, victimUid, prog));
      const after = await countExact(scope);
      check(`the ACTIVE coach still writes ${t} (positive control)`, after === before + 1,
        `rows ${before}->${after} (status ${m.status})`);
    }

    section('existing rows are preserved, not mutated');
    // The coach authors a habit while active, then the relationship is cancelled.
    const habit = ONE((await svc('client_habits', { method: 'POST',
      body: { client_id: victimUid, coach_id: coachUid, name: `${MARK}-legacy` } })).body).id;
    await svc(`${REL}?coach_id=eq.${coachUid}&client_id=eq.${victimUid}`, { method: 'PATCH',
      prefer: 'return=minimal',
      body: { status: 'cancelled', cancelled_by: 'client', cancelled_at: new Date().toISOString() } });
    const coachCancelledOk = await rel(coachUid, 'cancelled', 'the authoring coach is now CANCELLED');
    if (!coachCancelledOk || !habit) {
      failDependents(check, ['a cancelled coach still reads, but cannot change, a row they authored'],
        !habit ? 'the authored-row fixture was not created' : 'the authoring coach did not persist as cancelled');
      return summary('D24 coach write arms (185)');
    }
    const read = await rest(coach, `client_habits?id=eq.${habit}&select=id,name`);
    const upd = await mutate(coach, `client_habits?id=eq.${habit}`, 'PATCH', { name: `${MARK}-tampered` });
    const back = ONE((await svc(`client_habits?id=eq.${habit}&select=name`)).body).name;
    check('a cancelled coach still reads, but cannot change, a row they authored',
      Array.isArray(read.body) && read.body.length === 1 && back === `${MARK}-legacy`,
      `read=${Array.isArray(read.body) ? read.body.length : read.status} patch=${upd.status}/${upd.affected} name=${back}`);
  } finally {
    await purge();
  }
  return summary('D24 coach write arms (185)');
}

export default await run();
