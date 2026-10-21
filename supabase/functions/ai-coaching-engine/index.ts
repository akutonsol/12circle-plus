// AI Coaching Engine — the coaching-intelligence layer (not a chatbot).
// Assembles the user's full context (profile, goals, adherence, recovery,
// memory) and produces structured coaching output via Claude:
//   type = daily_insight | weekly_review | goal_prediction
// then persists to ai_insights / ai_reviews / ai_goal_predictions.
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

// deno-lint-ignore no-explicit-any
type Db = any;
// F-J-04: every call used to order by `created_at`. Five of the ten context
// tables do not have that column, so PostgREST answered 42703 and the reader
// below turned it into `[]` — the AI was told "nothing happened" for the
// user's workouts, sets, habits, nutrition and score. The ordering key is now
// per-table and named at the call site. Truth read from the migrations, not
// assumed; note that `nutrition_logs` is created by **006** (no `created_at`)
// and 012's richer `CREATE TABLE IF NOT EXISTS` for the same name is a no-op,
// so 006's shape is the one that exists.
//
//   goals            created_at   (018)      cycle_logs        created_at (033)
//   daily_scores     created_at   (001)      workout_feedback  created_at (001)
//   ai_memories      created_at   (074)
//   user_scores      updated_at   (035)  — no created_at
//   workout_sessions started_at   (001)  — no created_at
//   nutrition_logs   logged_at    (006)  — no created_at
//   habit_logs       logged_at    (001)  — no created_at
//   workout_set_logs logged_at    (001)  — no created_at
//
// The `{ data } … ?? []` / `catch` degradation below is NOT changed here: that
// is ERR-2 / `EC-02` (rule S), whose fail-closed behaviour is blocked on Q-5.
const recent = async (db: Db, table: string, userCol: string, uid: string, n = 14, orderCol = 'created_at') => {
  try {
    const { data } = await db.from(table).select('*').eq(userCol, uid).order(orderCol, { ascending: false }).limit(n);
    return data ?? [];
  } catch { return []; }
};

const SYSTEM: Record<string, string> = {
  daily_insight: `You are an elite personal fitness coach giving today's brief to a client.
Use their profile, goals, adherence, recovery, and coaching memory. Be specific and
actionable — adjust today's training intensity based on recovery (sleep, stress,
soreness), reference their goal, and respect injuries/dislikes from memory.
Respond with ONLY JSON: {
  "title": "short headline (max 8 words)",
  "body": "2-3 sentence coaching insight, second person, supportive but direct",
  "focus": "today's focus area (e.g. lower_body, recovery, cardio)",
  "intensity_delta": number,   // % adjustment to planned intensity, -30..+10, 0 if normal
  "nutrition_note": "one actionable nutrition cue for today",
  "recovery_note": "one recovery cue for today"
}`,
  weekly_review: `You are an elite fitness coach writing a client's weekly review.
Summarize the week from their adherence + metrics, celebrate wins, name one thing to
improve, and connect it to their goal. Respond with ONLY JSON: {
  "summary": "3-4 sentence review, encouraging and honest",
  "metrics": { "workouts_completed": number, "workouts_planned": number, "habit_adherence": number, "weight_change": number },
  "next_week_focus": "one clear focus for next week"
}`,
  goal_prediction: `You are a fitness goal-prediction engine. From the client's goal,
current weight, target weight, and recent rate of change, estimate their pace and a
realistic projected goal date. Be honest if pace is off-track. Respond with ONLY JSON: {
  "current_weight": number, "target_weight": number,
  "current_pace": number,        // signed units/week toward goal
  "projected_date": "YYYY-MM-DD",
  "confidence": number,          // 0-100
  "summary": "2 sentence plain-language projection"
}`,
  accountability: `You are an accountability coach. Using the client's behavioral
patterns (best/missed workout day, usual training time, streaks) and recent activity,
write ONE short, specific, contextual nudge — never generic. Reference the actual
pattern (e.g. their streak, their usual day/time). Respond with ONLY JSON: {
  "title": "short hook (max 6 words)",
  "body": "1-2 sentence contextual message in the client's coaching style"
}`,
  risk_assessment: `You are a fitness risk-analysis engine. From adherence, recovery,
soreness, consistency trend, and history, estimate risks. Respond with ONLY JSON: {
  "plateau_risk": number,   // 0-100
  "churn_risk": number,     // 0-100 (likelihood they stop using the app)
  "injury_risk": number,    // 0-100
  "summary": "2 sentence explanation of the biggest risk and how to mitigate it"
}`,
  meal_suggestion: `You are a nutrition coach. Suggest meals that help the client hit
their REMAINING macros for today, respecting allergies/dislikes/preferences from memory.
Keep portions realistic. Respond with ONLY JSON: {
  "meals": [
    { "name": "meal name", "calories": number, "protein_g": number, "carbs_g": number,
      "fat_g": number, "note": "why it fits their remaining macros" }
  ]
}
Give 3 options. If remaining calories are near zero, suggest light/high-protein snacks.`,
  progress_insight: `You are a fitness analytics engine. From the client's recent
workout set logs, weight trend, and adherence, surface the single most motivating,
data-grounded insight (e.g. strength up on a lift, consistency streak, weight trend).
Be specific with numbers when present. Respond with ONLY JSON: {
  "title": "headline with the key number (max 9 words)",
  "body": "1-2 sentence insight that explains why it matters"
}`,
};

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const authHeader = req.headers.get('Authorization') ?? '';
    if (!ANTHROPIC_API_KEY) return json({ error: 'AI not configured' }, 500);

    const { type = 'daily_insight', user_id: bodyUid } = await req.json() as { type?: string; user_id?: string };
    if (!SYSTEM[type]) return json({ error: 'Unknown type' }, 400);

    // Service-role (cron/batch) mode: trust the user_id in the body. Otherwise
    // resolve the user from their JWT.
    const isService = authHeader === `Bearer ${SUPABASE_SERVICE_KEY}`;
    let uid: string;
    if (isService && bodyUid) {
      uid = bodyUid;
    } else {
      const userDb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, { global: { headers: { Authorization: authHeader } } });
      const { data: { user } } = await userDb.auth.getUser();
      if (!user) return json({ error: 'Unauthorized' }, 401);
      uid = user.id;
    }

    const db = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

    // Refresh behavioral patterns first so memory + ai_profile are current.
    await db.rpc('ai_detect_patterns', { p_uid: uid }).then(() => {}, () => {});
    // Weekly cadence: auto-adjust nutrition macros from the weight trend.
    if (type === 'weekly_review') {
      await db.rpc('ai_adjust_nutrition', { p_uid: uid }).then(() => {}, () => {});
    }

    // ── Assemble context ──
    const [{ data: profile }, { data: aiProfile }] = await Promise.all([
      db.from('user_profiles').select('first_name, role, fitness_goal, gender, date_of_birth, height_cm, weight_kg, experience_level, membership_tier').eq('id', uid).maybeSingle(),
      db.from('ai_profiles').select('*').eq('user_id', uid).maybeSingle(),
    ]);
    const [goals, scores, dailyScores, workouts, nutrition, habits, cycles, feedback, memories] = await Promise.all([
      recent(db, 'goals', 'user_id', uid, 5),
      recent(db, 'user_scores', 'user_id', uid, 1, 'updated_at'),
      recent(db, 'daily_scores', 'user_id', uid, 7),
      recent(db, 'workout_sessions', 'user_id', uid, 14, 'started_at'),
      recent(db, 'nutrition_logs', 'user_id', uid, 21, 'logged_at'),
      recent(db, 'habit_logs', 'user_id', uid, 14, 'logged_at'),
      recent(db, 'cycle_logs', 'user_id', uid, 5),
      recent(db, 'workout_feedback', 'user_id', uid, 7),
      recent(db, 'ai_memories', 'user_id', uid, 50),
    ]);
    const setLogs = (type === 'progress_insight')
      ? await recent(db, 'workout_set_logs', 'user_id', uid, 60, 'logged_at') : [];

    // For meal suggestions: active plan targets + today's logged macros → remaining.
    let nutritionTargets: Record<string, number> | null = null;
    if (type === 'meal_suggestion') {
      const { data: plan } = await db.from('client_nutrition_plans')
        .select('calories_target, protein_g, carbs_g, fat_g')
        .eq('client_id', uid).eq('is_active', true).order('created_at', { ascending: false }).maybeSingle();
      const start = new Date(); start.setHours(0, 0, 0, 0);
      const { data: todays } = await db.from('nutrition_logs')
        .select('calories, protein, carbs, fat').eq('user_id', uid).gte('logged_at', start.toISOString());
      const sum = (k: string) => ((todays ?? []) as Db[]).reduce((a, r) => a + (Number(r[k]) || 0), 0);
      if (plan) {
        nutritionTargets = {
          remaining_calories: Math.max(0, Math.round((plan.calories_target ?? 0) - sum('calories'))),
          // The plan's targets really are `*_g` (client_nutrition_plans, 001);
          // the logged macros are not (nutrition_logs, 006). Mixing the two is
          // I-NUT-01: `sum()` read a column that does not exist, returned 0 for
          // every meal, and the remaining macros equalled the whole day's target
          // no matter how much the client had already eaten. The response keys
          // are prompt-facing and unchanged.
          remaining_protein_g: Math.max(0, Math.round((plan.protein_g ?? 0) - sum('protein'))),
          remaining_carbs_g: Math.max(0, Math.round((plan.carbs_g ?? 0) - sum('carbs'))),
          remaining_fat_g: Math.max(0, Math.round((plan.fat_g ?? 0) - sum('fat'))),
        };
      }
    }

    const context = {
      profile: profile ?? {},
      ai_profile: aiProfile ?? {},
      goals,
      score: scores?.[0] ?? {},
      daily_scores: dailyScores,
      recent_workouts: workouts.map((w: Db) => ({ date: w.started_at, completed: w.completed ?? w.status, title: w.title })),
      recent_nutrition_days: nutrition.length,
      recent_habit_logs: habits.length,
      recovery: feedback?.[0] ?? cycles?.[0] ?? {},
      recent_set_logs: setLogs.map((s: Db) => ({ exercise: s.exercise_name, weight_kg: s.weight_kg, reps: s.reps, date: s.logged_at })),
      remaining_macros_today: nutritionTargets,
      memory: {
        likes: memories.filter((m: Db) => m.kind === 'like').map((m: Db) => m.content),
        dislikes: memories.filter((m: Db) => m.kind === 'dislike').map((m: Db) => m.content),
        injuries: memories.filter((m: Db) => m.kind === 'injury').map((m: Db) => m.content),
        notes: memories.filter((m: Db) => ['note', 'constraint', 'preference'].includes(m.kind)).map((m: Db) => m.content),
      },
      today: new Date().toISOString().slice(0, 10),
    };

    // ── Confidence: how much data backs a recommendation (0-99) ──
    const conf = (() => {
      let s = 15; const why: string[] = [];
      const wk = workouts.length;
      if (wk >= 8) { s += 28; why.push(`${wk} recent workouts`); }
      else if (wk >= 3) { s += 16; why.push(`${wk} recent workouts`); }
      else if (wk >= 1) { s += 7; }
      if (dailyScores.length >= 5) { s += 14; why.push('consistent daily activity'); }
      if (goals.length > 0 || aiProfile?.goals) { s += 10; why.push('goal set'); }
      const mem = context.memory.likes.length + context.memory.dislikes.length + context.memory.injuries.length;
      if (mem >= 3) { s += 16; why.push('rich coaching memory'); }
      else if (mem >= 1) { s += 8; }
      if (nutrition.length >= 7) { s += 9; why.push('nutrition logged'); }
      if (profile?.weight_kg) { s += 5; }
      return { score: Math.min(s, 99), reasons: why };
    })();

    // ── Coach personality (delivery style) ──
    const persona = (aiProfile?.coach_persona ?? {}) as Record<string, string>;
    const pName = persona.name || 'Nova';
    const pStyle = persona.style || 'motivational';
    const pTone = persona.tone || 'supportive';
    const personaDirective =
      `You are "${pName}". Deliver in a ${pStyle} style with a ${pTone} tone — the substance ` +
      `of the advice never changes, only the delivery.`;
    const confidenceDirective =
      `Coaching confidence in this user's data: ${conf.score}% (${conf.reasons.join(', ') || 'limited data'}). ` +
      `If confidence is below 50, be cautious — soften strong changes and suggest confirming details first.`;

    // ── Ask Claude ──
    const res = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: { 'x-api-key': ANTHROPIC_API_KEY, 'anthropic-version': '2023-06-01', 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: 'claude-sonnet-4-6',
        max_tokens: 900,
        system: `${personaDirective}\n\n${SYSTEM[type]}`,
        messages: [{ role: 'user', content: `${confidenceDirective}\n\nClient context:\n${JSON.stringify(context, null, 1)}` }],
      }),
    });
    if (!res.ok) { console.error('Anthropic', res.status, await res.text()); return json({ error: 'AI request failed' }, 502); }
    const aiData = await res.json() as { content?: Array<{ text: string }> };
    let text = (aiData.content?.[0]?.text ?? '{}').trim().replace(/^```(?:json)?/i, '').replace(/```$/, '').trim();
    const a = text.indexOf('{'), b = text.lastIndexOf('}');
    if (a >= 0 && b > a) text = text.slice(a, b + 1);
    let out: Record<string, unknown>;
    try { out = JSON.parse(text); } catch { return json({ error: 'Could not read AI result', raw: text }, 502); }

    // ── Persist ──
    if (type === 'daily_insight') {
      const today = context.today;
      await db.from('ai_insights').delete().eq('user_id', uid).eq('type', 'daily_insight').eq('for_date', today);
      await db.from('ai_insights').insert({
        user_id: uid, type: 'daily_insight', for_date: today,
        title: out.title ?? 'Today’s Coaching', body: out.body ?? '',
        data: { focus: out.focus, intensity_delta: out.intensity_delta, nutrition_note: out.nutrition_note,
                recovery_note: out.recovery_note, confidence: conf.score, confidence_reasons: conf.reasons },
      });
    } else if (type === 'weekly_review') {
      const end = new Date(); const start = new Date(Date.now() - 6 * 864e5);
      await db.from('ai_reviews').insert({
        user_id: uid, period_start: start.toISOString().slice(0, 10), period_end: end.toISOString().slice(0, 10),
        summary: out.summary ?? '', metrics: { ...(out.metrics as object ?? {}), next_week_focus: out.next_week_focus },
      });
      await db.from('ai_profiles').upsert({ user_id: uid, last_review_at: new Date().toISOString() });
    } else if (type === 'goal_prediction') {
      await db.from('ai_goal_predictions').insert({
        user_id: uid,
        current_weight: out.current_weight, target_weight: out.target_weight,
        current_pace: out.current_pace, projected_date: out.projected_date,
        confidence: out.confidence, summary: out.summary ?? '',
      });
    } else if (type === 'accountability') {
      const today = context.today;
      await db.from('ai_insights').delete().eq('user_id', uid).eq('type', 'accountability').eq('for_date', today);
      await db.from('ai_insights').insert({
        user_id: uid, type: 'accountability', for_date: today,
        title: out.title ?? 'Stay on track', body: out.body ?? '', data: { confidence: conf.score },
      });
      // Also surface as a notification.
      try {
        await db.from('notifications').insert({
          recipient_id: uid, type: 'ai_accountability',
          title: out.title ?? 'Your coach', body: out.body ?? '', data: {}, read: false,
        });
      } catch (_e) { /* notifications table optional */ }
    } else if (type === 'risk_assessment') {
      await db.from('ai_insights').insert({
        user_id: uid, type: 'risk', title: 'Risk assessment', body: out.summary ?? '',
        data: { plateau_risk: out.plateau_risk, churn_risk: out.churn_risk, injury_risk: out.injury_risk, confidence: conf.score },
      });
    } else if (type === 'progress_insight') {
      await db.from('ai_insights').insert({
        user_id: uid, type: 'progress', title: out.title ?? 'Progress', body: out.body ?? '',
        data: { confidence: conf.score },
      });
    } else if (type === 'meal_suggestion') {
      const today = context.today;
      await db.from('ai_insights').delete().eq('user_id', uid).eq('type', 'meal_suggestion').eq('for_date', today);
      await db.from('ai_insights').insert({
        user_id: uid, type: 'meal_suggestion', for_date: today,
        title: 'Meal ideas', body: '', data: { meals: out.meals ?? [], remaining: nutritionTargets },
      });
    }

    return json({ result: out, type, confidence: conf.score, confidence_reasons: conf.reasons,
                  persona: { name: pName, style: pStyle, tone: pTone } });
  } catch (e) {
    console.error('ai-coaching-engine error:', e);
    return json({ error: String(e) }, 500);
  }
});
