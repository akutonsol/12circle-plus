// AI per-session workout generator. Builds ONE personalized session grounded in
// the real exercise library, respecting the user's goal, equipment, injuries,
// dislikes, recovery, and the coach's focus + intensity adjustment for today.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const ANTHROPIC_API_KEY = Deno.env.get('ANTHROPIC_API_KEY') ?? '';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
const json = (d: unknown, s = 200) =>
  new Response(JSON.stringify(d), { status: s, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

const SYSTEM = `You are an elite strength coach generating ONE workout session for a client.

Rules:
- Select exercises ONLY from the provided LIBRARY list, by their EXACT name.
- Respect available equipment, AVOID anything contraindicated by their injuries, and
  avoid disliked exercises. Favour exercises they like.
- Honour today's FOCUS area and the INTENSITY adjustment: a negative intensity_delta
  means reduce volume/effort (fewer sets, leave reps in reserve — note it); positive
  means push harder.
- Pick 4-7 exercises, ordered big→small. Use supersets where sensible (same
  superset_group letter, e.g. "A"). Prescribe realistic sets/reps/rest/tempo.
- "sets" and "reps" MUST be whole numbers. Never a range ("8-12"), never a
  string, never text. If you would write a range, pick the single number you
  actually mean.
- Do NOT prescribe a load. Weight is the deterministic engine's decision, not
  yours.

Respond with ONLY JSON — no prose, no fences:
{
  "title": "session name (e.g. 'Lower Body — Recovery Focus')",
  "estimated_minutes": number,
  "exercises": [
    { "name": "Exact Library Name", "sets": number, "reps": number,
      "rest_seconds": number, "tempo": "e.g. 3-1-1", "superset_group": "A or null",
      "notes": "short cue, optional" }
  ]
}`;

// deno-lint-ignore no-explicit-any
type Db = any;

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const authHeader = req.headers.get('Authorization') ?? '';
    if (!ANTHROPIC_API_KEY) return json({ error: 'AI not configured' }, 500);
    const userDb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, { global: { headers: { Authorization: authHeader } } });
    const { data: { user } } = await userDb.auth.getUser();
    if (!user) return json({ error: 'Unauthorized' }, 401);
    const { duration_minutes } = await req.json().catch(() => ({})) as { duration_minutes?: number };

    const db = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
    const uid = user.id;

    const [{ data: profile }, { data: aiProfile }, { data: todayInsight }, memRes, libRes, fbRes] = await Promise.all([
      // DAT-2 / I-INT-02. `user_profiles` has neither `goal` nor `equipment`
      // (000 baseline + every ADD COLUMN since; the authoritative goal column is
      // `fitness_goal`, 000, and 001's `user_profiles` block is a shadow
      // `CREATE TABLE IF NOT EXISTS` that never executes). PostgREST resolves
      // the whole select before reading, so ONE phantom column 400'd the entire
      // request and `{ data: null }` came back without throwing — taking
      // `experience_level`, `training_location`, `has_injuries` and
      // `injury_locations` (013) down with it, whoever the member actually was.
      db.from('user_profiles').select('fitness_goal, experience_level, training_location, has_injuries, injury_locations').eq('id', uid).maybeSingle(),
      db.from('ai_profiles').select('goals, preferences').eq('user_id', uid).maybeSingle(),
      db.from('ai_insights').select('data').eq('user_id', uid).eq('type', 'daily_insight').order('for_date', { ascending: false }).limit(1).maybeSingle(),
      db.from('ai_memories').select('kind, content').eq('user_id', uid),
      db.from('custom_exercises').select('name, muscle_group, equipment, difficulty, exercise_type, contraindications')
        .eq('visibility', 'global').eq('submission_status', 'approved').limit(220),
      db.from('workout_feedback').select('energy_level, difficulty').eq('user_id', uid).order('created_at', { ascending: false }).limit(1),
    ]);

    const mem = (memRes.data ?? []) as Db[];
    const memory = {
      likes: mem.filter((m) => m.kind === 'like').map((m) => m.content),
      dislikes: mem.filter((m) => m.kind === 'dislike').map((m) => m.content),
      injuries: mem.filter((m) => m.kind === 'injury').map((m) => m.content),
    };
    const focus = (todayInsight?.data?.focus as string) ?? (aiProfile?.goals?.secondary_goal as string) ?? null;
    const intensityDelta = (todayInsight?.data?.intensity_delta as number) ?? 0;

    const library = ((libRes.data ?? []) as Db[]).map((e) =>
      `${e.name} [${e.muscle_group ?? '?'} | ${e.equipment ?? 'bodyweight'} | ${e.difficulty ?? 'int'}${
        (e.contraindications?.length ? ' | avoid: ' + e.contraindications.join(',') : '')}]`).join('\n');

    const ctx = {
      goal: profile?.fitness_goal ?? 'general',
      experience: profile?.experience_level ?? 'intermediate',
      // The user's available equipment is declared on `ai_profiles.preferences`
      // (074_ai_coaching_layer.sql:13 — "{favorite_exercises,
      // disliked_exercises, available_equipment, training_days}"), which this
      // handler already fetches in the same Promise.all. Read it there rather
      // than from a `user_profiles.equipment` column that has never existed.
      // The `?? 'Bodyweight'` default is UNCHANGED: whether a missing input may
      // be defaulted at all is ERR-2 / rule S, blocked on Q-5.
      equipment: (aiProfile?.preferences?.available_equipment as string | undefined) ?? 'Bodyweight',
      location: profile?.training_location ?? 'gym',
      duration_minutes: duration_minutes ?? 45,
      focus, intensity_delta: intensityDelta,
      recovery: fbRes.data?.[0] ?? {},
      memory,
    };

    const res = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: { 'x-api-key': ANTHROPIC_API_KEY, 'anthropic-version': '2023-06-01', 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: 'claude-sonnet-4-6', max_tokens: 1200, system: SYSTEM,
        messages: [{ role: 'user', content: `CLIENT:\n${JSON.stringify(ctx, null, 1)}\n\nLIBRARY (pick by exact name):\n${library}` }],
      }),
    });
    if (!res.ok) { console.error('Anthropic', res.status, await res.text()); return json({ error: 'AI request failed' }, 502); }
    const aiData = await res.json() as { content?: Array<{ text: string }> };
    let text = (aiData.content?.[0]?.text ?? '{}').trim().replace(/^```(?:json)?/i, '').replace(/```$/, '').trim();
    const a = text.indexOf('{'), b = text.lastIndexOf('}');
    if (a >= 0 && b > a) text = text.slice(a, b + 1);
    let out: Record<string, unknown>;
    try { out = JSON.parse(text); } catch { return json({ error: 'Could not read AI result', raw: text }, 502); }

    // ── Canonical contract (docs/WORKOUT_DOMAIN_CONTRACT.md §3) ──────────────
    //
    // The model's output is untrusted text, so it is validated here rather than
    // passed through. Previously `e.reps ?? 10` preserved whatever the model
    // emitted — a string, a range — and the client's codec then failed on the
    // whole workout. A model that cannot produce whole numbers is a failure to
    // report, not a workout to half-build.
    //
    // Load is deliberately absent: AI explains, the engine decides. `weight_kg`
    // is written as null, which the client renders as no prescribed load.
    const whole = (v: unknown): number | null => {
      if (typeof v === 'number' && Number.isInteger(v)) return v;
      if (typeof v === 'string' && /^\d+$/.test(v.trim())) return parseInt(v.trim(), 10);
      return null;
    };
    const rejected: string[] = [];
    const exercises = ((out.exercises as Db[]) ?? []).flatMap((e, i) => {
      const name = typeof e.name === 'string' ? e.name.trim() : '';
      const sets = whole(e.sets);
      const reps = whole(e.reps);
      if (!name || sets === null || sets < 1 || reps === null || reps < 0) {
        rejected.push(`#${i} ${name || '(unnamed)'}: sets=${JSON.stringify(e.sets)} reps=${JSON.stringify(e.reps)}`);
        return [];
      }
      const group = e.superset_group && e.superset_group !== 'null' ? e.superset_group : null;
      return [{
        exercise_instance_id: `ai-${crypto.randomUUID()}`,
        name, position: i, sets, reps,
        weight_kg: null,
        rest_seconds: whole(e.rest_seconds),
        rpe: null,
        tempo: typeof e.tempo === 'string' && e.tempo.trim() ? e.tempo.trim() : null,
        duration_seconds: null,
        notes: typeof e.notes === 'string' && e.notes.trim() ? e.notes.trim() : null,
        superset_group: group,
        is_superset: !!group,
      }];
    });

    if (exercises.length === 0) {
      console.error('ai-generate-workout: no exercise satisfied the contract', rejected);
      return json({ error: 'The generated workout was not usable', rejected }, 502);
    }
    if (rejected.length) console.warn('ai-generate-workout: dropped out-of-contract exercises', rejected);

    return json({
      workout: {
        title: out.title ?? 'AI Workout',
        estimated_minutes: whole(out.estimated_minutes) ?? ctx.duration_minutes,
        contract_version: 2,
        exercises,
      },
    });
  } catch (e) {
    console.error('ai-generate-workout error:', e);
    return json({ error: String(e) }, 500);
  }
});
