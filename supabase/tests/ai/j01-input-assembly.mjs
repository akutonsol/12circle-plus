// J-01 — AI input assembly: does every column an AI feature reads exist?
//
// supabase-js does not throw when `.select()` names a column that is not there.
// PostgREST answers 42703, the client hands back `{ data: null }`, and the edge
// function's `?? {}` / `?? []` turns a hard schema error into "this member has
// no data". The model is then asked to coach a person it was told nothing
// about, and it does — fluently. That is the failure this suite exists to make
// visible.
//
// Each probe below is the EXACT column list an AI feature selects, taken from
// the committed edge-function source.
import { mark, signIn, columnExists, rest, section, characterize, invariant, summary } from './lib.mjs';

const _from = mark();

const jwt = await signIn('victim');

// ── ai-generate-workout — the whole client profile in one select ────────────
section('J-01A  ai-generate-workout · user_profiles');
{
  // supabase/functions/ai-generate-workout/index.ts:63
  const cols = ['fitness_goal', 'goal', 'equipment', 'experience_level',
                'training_location', 'has_injuries', 'injury_locations'];
  const missing = [];
  for (const c of cols) {
    const r = await columnExists(jwt, 'user_profiles', c);
    if (!r.ok) missing.push(c);
  }
  characterize('F-J-02  the profile select names columns that do not exist',
    missing.length > 0,
    missing.length
      ? `missing: ${missing.join(', ')} → the whole select 42703s, profile is null, ` +
        'and goal/equipment/experience/location/injuries all fall back to defaults'
      : 'every column now resolves — invert this to an invariant and delete the finding');

  // The remediation target, stated positively so the fix has something to aim at.
  const structural = ['fitness_goal', 'experience_level', 'training_location',
                      'has_injuries', 'injury_locations'];
  const gone = [];
  for (const c of structural) if (!(await columnExists(jwt, 'user_profiles', c)).ok) gone.push(c);
  invariant('the columns the generator genuinely needs are present in the schema',
    gone.length === 0, gone.length ? `absent: ${gone.join(', ')}` : 'fitness_goal, experience_level, training_location, has_injuries, injury_locations');
}

// ── ai-coaching-engine — profile + macro arithmetic ─────────────────────────
section('J-01B  ai-coaching-engine · user_profiles + nutrition_logs');
{
  // supabase/functions/ai-coaching-engine/index.ts:126
  const profileCols = ['first_name', 'role', 'goal', 'gender', 'date_of_birth',
                       'height_cm', 'weight_kg', 'experience_level', 'membership_tier'];
  const missing = [];
  for (const c of profileCols) if (!(await columnExists(jwt, 'user_profiles', c)).ok) missing.push(c);
  characterize('F-J-02  the coaching-engine profile select also names a missing column',
    missing.length > 0,
    missing.length ? `missing: ${missing.join(', ')} → context.profile is {} for every insight` : 'resolves');

  // index.ts:150 — today's consumed macros, subtracted from the plan target.
  const macroCols = ['calories', 'protein_g', 'carbs_g', 'fat_g'];
  const missingMacros = [];
  for (const c of macroCols) if (!(await columnExists(jwt, 'nutrition_logs', c)).ok) missingMacros.push(c);
  characterize('F-J-03  meal_suggestion reads macro columns nutrition_logs does not have',
    missingMacros.length > 0,
    missingMacros.length
      ? `missing: ${missingMacros.join(', ')} (the table has protein/carbs/fat) → ` +
        'today\'s intake sums to 0 and the member is told their whole day is still available'
      : 'resolves');

  const real = [];
  for (const c of ['protein', 'carbs', 'fat']) if ((await columnExists(jwt, 'nutrition_logs', c)).ok) real.push(c);
  invariant('the real macro columns exist under their own names',
    real.length === 3, `present: ${real.join(', ')}`);
}

// ── recent(): the shared history helper ─────────────────────────────────────
section('J-01C  ai-coaching-engine · recent() orders every table by created_at');
{
  // index.ts:27 — `.order('created_at', {ascending:false})` against nine tables.
  // A table without that column returns an error, `recent()` catches it, and the
  // model is handed [].
  const tables = ['goals', 'user_scores', 'daily_scores', 'workout_sessions',
                  'nutrition_logs', 'habit_logs', 'cycle_logs', 'workout_feedback',
                  'ai_memories', 'workout_set_logs'];
  const broken = [];
  for (const t of tables) {
    const r = await rest(jwt, `${t}?select=*&order=created_at.desc&limit=1`);
    if (r.status >= 300) broken.push(t);
  }
  characterize('F-J-04  recent() silently returns [] for tables with no created_at',
    broken.length > 0,
    broken.length
      ? `${broken.join(', ')} → those inputs are always empty, and the confidence ` +
        'score that is persisted alongside the advice is computed from them'
      : 'every table orders');

  // goals is keyed differently again — the filter, not the sort, is wrong there.
  const g = await columnExists(jwt, 'goals', 'user_id');
  characterize('F-J-04  goals is filtered on a user_id column it does not have',
    !g.ok, g.ok ? 'goals.user_id exists' : `${g.code}: goals has no user_id → goals is always []`);
}

export default summary('J-01 input assembly', _from);
