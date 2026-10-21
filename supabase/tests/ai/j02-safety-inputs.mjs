// J-02 — Safety inputs: the constraints exist, and nothing consumes them.
//
// The platform computes an authoritative PAR-Q risk classification server-side
// (migration 115) and stores structured food allergies (migration 013). Both
// are real, populated, and correct. Neither reaches any decision surface: not
// the deterministic engine's context, not a single AI prompt.
//
// A safety input that exists but is never read is worse than one that is
// missing, because the schema makes the system look governed.
import { mark, signIn, rest, columnExists, rpc, section, characterize, invariant, summary,
         URL_, ANON } from './lib.mjs';

const _from = mark();

const victim = await signIn('victim');
const admin  = await signIn('admin');

section('J-02A  the safety substrate is present and server-owned');
{
  for (const c of ['risk_level', 'risk_flags', 'risk_score', 'parq_answers',
                   'medical_conditions', 'food_allergies']) {
    const r = await columnExists(victim, 'user_profiles', c);
    invariant(`user_profiles.${c} exists`, r.ok, r.ok ? '' : `${r.code}`);
  }

  // The classifier itself — pure, and the copy the server trusts.
  const high = await rpc(victim, 'derive_parq_risk', {
    p_parq: { '1': true }, p_medical_conditions: '', p_has_injuries: false, p_injury_locations: '',
  });
  const row = Array.isArray(high.body) ? high.body[0] : high.body;
  invariant('derive_parq_risk classifies a declared heart condition as high risk',
    row?.risk_level === 'high', `risk_level=${row?.risk_level} flags=${row?.risk_flags}`);

  // The authoritative classifier returns the narrative safety flags as
  // typed text[] values. F-J-17 previously exposed an untyped-array-literal
  // failure for pregnancy, postpartum, and active_injuries; migration 126
  // remediated that defect without changing the flag vocabulary or order.
  for (const [label, args, expected] of [
    ['pregnancy',
      { p_parq: {}, p_medical_conditions: 'Pregnancy', p_has_injuries: false, p_injury_locations: '' },
      'pregnancy'],
    ['postpartum',
      { p_parq: {}, p_medical_conditions: 'Postpartum', p_has_injuries: false, p_injury_locations: '' },
      'postpartum'],
    ['active_injuries',
      { p_parq: {}, p_medical_conditions: '', p_has_injuries: true, p_injury_locations: 'left knee' },
      'active_injuries'],
  ]) {
    const r = await rpc(victim, 'derive_parq_risk', args);
    const row = Array.isArray(r.body) ? r.body[0] : r.body;
    const flags = row?.risk_flags ?? '';
    characterize(`F-J-17  derive_parq_risk raises the ${label} flag`,
      r.status < 400 && flags.split(',').includes(expected),
      `HTTP ${r.status} flags=${flags} level=${row?.risk_level ?? ''}`);
  }
}

section('J-02A2  and the classifier is a BEFORE trigger, so the member can declare');
{
  // apply_parq_risk() runs BEFORE INSERT OR UPDATE on user_profiles and calls
  // derive_parq_risk. The F-J-17 remediation makes this write path operational.
  // The probe is self-restoring so the fixture is returned to its prior state.
  const me = (await rest(victim, 'user_profiles?select=id,has_injuries,injury_locations&limit=1')).body?.[0];
  invariant('the member can read their own profile', !!me?.id, me?.id ?? 'none');

  if (me?.id) {
    const before = { has_injuries: me.has_injuries ?? false, injury_locations: me.injury_locations ?? '' };
    const w = await fetch(`${URL_}/rest/v1/user_profiles?id=eq.${me.id}`, {
      method: 'PATCH',
      headers: { apikey: ANON, Authorization: `Bearer ${victim}`, 'Content-Type': 'application/json',
                 Prefer: 'return=minimal,count=exact' },
      body: JSON.stringify({ has_injuries: true, injury_locations: 'left knee' }),
    });
    const wb = await w.json().catch(() => null);
    characterize('F-J-17  a member can save an injury declaration',
      w.status < 300,
      `PATCH → HTTP ${w.status} ${wb?.code ?? ''} "${wb?.message ?? ''}" — injury declaration write path is operational. ` +
      'Onboarding intake (intake_data.toProfileMap) writes exactly these columns.');

    if (w.status < 300) {
      // Only reachable once remediated; put the fixture back the way it was.
      await fetch(`${URL_}/rest/v1/user_profiles?id=eq.${me.id}`, {
        method: 'PATCH',
        headers: { apikey: ANON, Authorization: `Bearer ${victim}`, 'Content-Type': 'application/json',
                   Prefer: 'return=minimal' },
        body: JSON.stringify(before),
      });
    }
  }
}

section('J-02B  the deterministic engine has no PAR-Q dimension at all');
{
  // score_exercise's documented context keys (087): goal, equipment, recovery,
  // experience, injuries, recent_patterns. There is no risk_level, no
  // risk_flags, no pregnancy/postpartum, no medical clearance. Passing them
  // changes nothing, which is the point — they are not inputs.
  const ex = await rest(victim, 'custom_exercises?select=id&limit=1');
  const id = ex.body?.[0]?.id;
  invariant('a library exercise is readable to score', !!id, id ?? 'none');

  if (id) {
    const bare = await rpc(victim, 'score_exercise', { p_exercise_id: id, p_context: { goal: 'strength' } });
    const flagged = await rpc(victim, 'score_exercise', {
      p_exercise_id: id,
      p_context: { goal: 'strength', risk_level: 'high',
                   risk_flags: 'heart_condition,doctor_advised_no_exercise,pregnancy' },
    });
    characterize('F-J-05  a high-risk PAR-Q classification does not change any score',
      JSON.stringify(bare.body) === JSON.stringify(flagged.body),
      'score_exercise ignores risk_level / risk_flags entirely — the engine cannot ' +
      'express "this member has been advised against unsupervised exercise"');
  }
}

section('J-02C  the injury rule can only fire on data nothing populates');
{
  // score_exercise penalises an injury via exercise_intelligence.contraindications
  // and .joint_stress. rebuild_exercise_intelligence() — the only automated way
  // to populate the table — writes neither column. Until an AI or a human fills
  // them, injury_compatibility is 100 for every exercise and INJURY_PREVENTION
  // is unreachable.
  // intelligence_stats is content-editor gated (migration 116 class E).
  const stats = await rpc(admin, 'intelligence_stats');
  const profiled = stats.body?.profiled;
  characterize('F-J-06  the intelligence substrate is unpopulated on this project',
    stats.status >= 300 || profiled === 0,
    stats.status >= 300
      ? `intelligence_stats is admin-gated here (${stats.status}) — run as admin for the count`
      : `profiled=${profiled} of ${stats.body?.total_exercises} exercises, engine_ready=${stats.body?.engine_ready}`);
}

export default summary('J-02 safety inputs', _from);
