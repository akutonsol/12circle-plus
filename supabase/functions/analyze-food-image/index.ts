// AI food analysis (Cal-AI style) for the nutrition module's calorie tracker.
// Accepts a food photo (base64) OR a text description and returns estimated
// calories + macros as structured JSON, using Claude vision. Auth required.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { checkPlan } from '../plan_gate.mjs';

const ANTHROPIC_API_KEY = Deno.env.get('ANTHROPIC_API_KEY') ?? '';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') ?? '';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), {
    status, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

const SYSTEM = `You are a precise nutrition estimation engine for a calorie-tracking app.
Given a photo of a meal (and/or a text description), identify the dish and every
visible component, and estimate realistic portion sizes for a single serving as shown.
Respond with ONLY a JSON object — no prose, no markdown fences — in EXACTLY this shape:
{
  "name": "short dish name",
  "calories": number,        // total kcal
  "protein_g": number,
  "carbs_g": number,
  "fat_g": number,
  "confidence": number,      // 0-100, your confidence in the estimate
  "items": [                 // per-component breakdown
    { "name": "string", "calories": number, "protein_g": number, "carbs_g": number, "fat_g": number }
  ]
}
Round grams to whole numbers and calories to the nearest 5. If you cannot identify
any food, return calories 0 and confidence 0.`;

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const authHeader = req.headers.get('Authorization') ?? '';
    const userDb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user } } = await userDb.auth.getUser();
    if (!user) return json({ error: 'Unauthorized' }, 401);

    // Server side of the app's PaywallGate: the tier the app requires at this
    // function's entry points (plan_gate.mjs).
    const gate = await checkPlan(userDb, user.id, 'self_guided');
    if (!gate.ok) return json(gate.body, gate.status);
    if (!ANTHROPIC_API_KEY) return json({ error: 'AI not configured' }, 500);

    const { imageBase64, mediaType, description } = await req.json() as {
      imageBase64?: string; mediaType?: string; description?: string;
    };
    if (!imageBase64 && !description) {
      return json({ error: 'Provide an image or a description' }, 400);
    }

    // deno-lint-ignore no-explicit-any
    const content: any[] = [];
    if (imageBase64) {
      content.push({
        type: 'image',
        source: { type: 'base64', media_type: mediaType || 'image/jpeg', data: imageBase64 },
      });
    }
    content.push({
      type: 'text',
      text: description
        ? `Estimate the nutrition for: ${description}`
        : 'Estimate the nutrition for the food in this photo.',
    });

    const res = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'x-api-key': ANTHROPIC_API_KEY,
        'anthropic-version': '2023-06-01',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        // Sonnet for stronger food recognition / portion estimation accuracy.
        model: 'claude-sonnet-4-6',
        max_tokens: 700,
        system: SYSTEM,
        messages: [{ role: 'user', content }],
      }),
    });

    if (!res.ok) {
      const err = await res.text();
      console.error('Anthropic error:', res.status, err);
      return json({ error: 'AI request failed' }, 502);
    }

    const data = await res.json() as { content?: Array<{ text: string }> };
    let text = data.content?.[0]?.text ?? '{}';
    // Strip any stray markdown fences and isolate the JSON object.
    text = text.trim().replace(/^```(?:json)?/i, '').replace(/```$/, '').trim();
    const start = text.indexOf('{');
    const end = text.lastIndexOf('}');
    if (start >= 0 && end > start) text = text.slice(start, end + 1);

    let parsed: Record<string, unknown>;
    try {
      parsed = JSON.parse(text);
    } catch {
      return json({ error: 'Could not read AI result', raw: text }, 502);
    }
    return json({ result: parsed });
  } catch (e) {
    console.error('analyze-food-image error:', e);
    return json({ error: String(e) }, 500);
  }
});
