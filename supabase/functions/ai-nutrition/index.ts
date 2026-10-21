// AI Nutrition Coach — the conversational endpoint.
//
// PD-A17 = A, resolved as A2 (V5 §46): this is the Edge equivalent of the
// NestJS route `POST /ai/nutrition/message`, which was the ONLY live surface
// that API served. Porting it here means the product needs no second hosting
// platform, and `apps/api` can be retired.
//
// The contract is preserved byte-for-byte where the client can observe it:
// the same request shape, the same validation limits, the same `{ text }`
// response, and the same deliberately-generic failure text. The Anthropic key
// stays server-side and is never echoed, exactly as `ai-nutrition.service.ts`
// guaranteed.
//
// Auth is `verify_jwt = true` in config.toml PLUS an explicit `getUser()` check
// here, the same belt-and-braces the other AI functions use: the Anthropic key
// is a paid credential and an unauthenticated caller must never spend it.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const ANTHROPIC_API_KEY = Deno.env.get('ANTHROPIC_API_KEY') ?? '';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
// PORTED, not chosen. `api-config.ts:38` defines
// DEFAULT_ANTHROPIC_MODEL = 'claude-sonnet-4-6' and the Nest service used it
// whenever ANTHROPIC_MODEL was unset, which it is on QA. Nine of the sibling
// Edge Functions use the same literal. An earlier revision of this file invented
// 'claude-sonnet-4-20250514' instead, and the live happy path returned 503
// because Anthropic rejected it — the negative paths all passed, so only an
// end-to-end call could surface it.
const ANTHROPIC_MODEL = Deno.env.get('ANTHROPIC_MODEL') ?? 'claude-sonnet-4-6';
const ANTHROPIC_MAX_TOKENS = Number(Deno.env.get('ANTHROPIC_MAX_TOKENS') ?? '1024');

// Ported verbatim from `nutrition-message.dto.ts`. Changing any of these is a
// contract change the Flutter client can observe.
const SUPPORTED_IMAGE_MEDIA_TYPES = ['image/jpeg', 'image/png', 'image/gif', 'image/webp'];
const MAX_IMAGE_BASE64_LENGTH = 7_000_000;
const MAX_MESSAGE_LENGTH = 8_000;
const MAX_HISTORY_TURNS = 40;
const MAX_HISTORY_CONTENT_LENGTH = 16_000;

// Ported verbatim from `ai-nutrition.service.ts`. The persona lives server-side
// so the prompt — and the key that pays for it — are not shipped in the client.
const NUTRITION_SYSTEM_PROMPT = `You are an expert AI Nutrition Coach for 12 Circle Fitness,
a premium fitness platform designed for women seeking sustainable body transformation.
Your role is to:
- Analyze meal photos and estimate calories and macros accurately
- Generate personalized meal plans
- Create detailed grocery lists
- Answer nutrition questions with science-backed advice
- Be encouraging, supportive and empowering
- Focus on sustainable, healthy eating habits
Keep responses concise, actionable and motivating.`;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

/**
 * Replaces Nest's `ValidationPipe({ whitelist: true, forbidNonWhitelisted: true })`.
 *
 * `forbidNonWhitelisted` is the half that is easy to drop by accident and the
 * half that matters: an unknown property must be REFUSED, not silently ignored,
 * so a client cannot smuggle a field a later version might start honouring.
 * Returns an error string, or null when the body is valid.
 */
function validate(body: unknown): string | null {
  if (typeof body !== 'object' || body === null || Array.isArray(body)) {
    return 'body must be an object';
  }
  const b = body as Record<string, unknown>;

  for (const key of Object.keys(b)) {
    if (!['message', 'history', 'image'].includes(key)) {
      return `property ${key} should not exist`;
    }
  }

  if (typeof b.message !== 'string' || b.message.length === 0) {
    return 'message must be a non-empty string';
  }
  if (b.message.length > MAX_MESSAGE_LENGTH) {
    return `message must be shorter than or equal to ${MAX_MESSAGE_LENGTH} characters`;
  }

  if (b.history !== undefined) {
    if (!Array.isArray(b.history)) return 'history must be an array';
    if (b.history.length > MAX_HISTORY_TURNS) {
      return `history must contain no more than ${MAX_HISTORY_TURNS} elements`;
    }
    for (const turn of b.history) {
      if (typeof turn !== 'object' || turn === null || Array.isArray(turn)) {
        return 'history entries must be objects';
      }
      const t = turn as Record<string, unknown>;
      for (const key of Object.keys(t)) {
        if (!['role', 'content'].includes(key)) {
          return `property ${key} should not exist`;
        }
      }
      if (t.role !== 'user' && t.role !== 'assistant') {
        return 'history role must be user or assistant';
      }
      if (typeof t.content !== 'string') return 'history content must be a string';
      if (t.content.length > MAX_HISTORY_CONTENT_LENGTH) {
        return `history content must be shorter than or equal to ${MAX_HISTORY_CONTENT_LENGTH} characters`;
      }
    }
  }

  if (b.image !== undefined) {
    if (typeof b.image !== 'object' || b.image === null || Array.isArray(b.image)) {
      return 'image must be an object';
    }
    const img = b.image as Record<string, unknown>;
    for (const key of Object.keys(img)) {
      if (!['mediaType', 'data'].includes(key)) {
        return `property ${key} should not exist`;
      }
    }
    if (typeof img.mediaType !== 'string' || !SUPPORTED_IMAGE_MEDIA_TYPES.includes(img.mediaType)) {
      return `image mediaType must be one of ${SUPPORTED_IMAGE_MEDIA_TYPES.join(', ')}`;
    }
    if (typeof img.data !== 'string' || img.data.length === 0) {
      return 'image data must be a non-empty string';
    }
    if (img.data.length > MAX_IMAGE_BASE64_LENGTH) {
      return `image data must be shorter than or equal to ${MAX_IMAGE_BASE64_LENGTH} characters`;
    }
  }

  return null;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  try {
    const authHeader = req.headers.get('Authorization') ?? '';
    const userDb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user } } = await userDb.auth.getUser();
    if (!user) return json({ error: 'Missing or invalid access token' }, 401);

    // ORDER MATTERS, and it is Nest's: guard -> ValidationPipe -> service. The
    // pipe ran before anything touched the Anthropic client, so a malformed body
    // was a 400 whether or not the server held a key. Checking configuration
    // first would turn every validation error into a 503 on an unconfigured
    // environment — which is what this function did until a QA probe showed
    // `unknown property` returning 503 instead of 400.
    let body: unknown;
    try {
      body = await req.json();
    } catch {
      return json({ error: 'body must be valid JSON' }, 400);
    }

    const invalid = validate(body);
    if (invalid) return json({ error: invalid }, 400);

    // Mirrors the Nest service's `isConfigured` check: a MISCONFIGURED server
    // must not be reported as a rejected credential.
    if (!ANTHROPIC_API_KEY) return json({ error: 'AI is not configured' }, 503);

    const dto = body as {
      message: string;
      history?: { role: 'user' | 'assistant'; content: string }[];
      image?: { mediaType: string; data: string };
    };

    // Image FIRST, then the text — the order `ai-nutrition.service.ts` used, and
    // the order Claude's vision guidance recommends.
    const userContent: unknown[] = [];
    if (dto.image) {
      userContent.push({
        type: 'image',
        source: { type: 'base64', media_type: dto.image.mediaType, data: dto.image.data },
      });
    }
    userContent.push({ type: 'text', text: dto.message });

    const messages = [
      ...(dto.history ?? []).map((turn) => ({ role: turn.role, content: turn.content })),
      { role: 'user', content: userContent },
    ];

    // RETRY IS PART OF THE CONTRACT BEING PRESERVED, not an embellishment.
    // `ai-nutrition.service.ts` used the Anthropic SDK and overrode neither
    // `maxRetries` nor `timeout`, so it inherited the SDK default of
    // **maxRetries = 2** (`@anthropic-ai/sdk/client.d.ts:207`). A bare fetch --
    // which is what the sibling functions use -- would have silently dropped
    // that, turning transient 429s and 5xxs into a user-visible 503 far more
    // often. Retried on the SDK's own retryable set (408/409/429/5xx and
    // connection errors), never on a 4xx the caller can fix.
    const ANTHROPIC_MAX_RETRIES = 2;
    const retryable = (status: number) =>
      status === 408 || status === 409 || status === 429 || status >= 500;

    const upstreamBody = JSON.stringify({
      model: ANTHROPIC_MODEL,
      max_tokens: ANTHROPIC_MAX_TOKENS,
      system: NUTRITION_SYSTEM_PROMPT,
      messages,
    });

    let upstream: Response | null = null;
    let lastError: unknown = null;
    for (let attempt = 0; attempt <= ANTHROPIC_MAX_RETRIES; attempt++) {
      if (attempt > 0) {
        // Exponential backoff, as the SDK does. Short: an Edge Function has a
        // wall-clock budget and the caller is a user waiting on a chat reply.
        await new Promise((r) => setTimeout(r, 500 * 2 ** (attempt - 1)));
      }
      try {
        upstream = await fetch('https://api.anthropic.com/v1/messages', {
          method: 'POST',
          headers: {
            'x-api-key': ANTHROPIC_API_KEY,
            'anthropic-version': '2023-06-01',
            'Content-Type': 'application/json',
          },
          body: upstreamBody,
        });
      } catch (e) {
        // A connection-level failure is retryable; the SDK treats it so.
        lastError = e;
        upstream = null;
        continue;
      }
      if (upstream.ok || !retryable(upstream.status)) break;
      console.warn(`Anthropic ${upstream.status}, attempt ${attempt + 1} of ${ANTHROPIC_MAX_RETRIES + 1}`);
    }

    if (!upstream) {
      console.error(
        `Anthropic unreachable after ${ANTHROPIC_MAX_RETRIES + 1} attempts: ` +
        (lastError instanceof Error ? lastError.name : 'unknown'),
      );
      return json({ error: 'AI is temporarily unavailable' }, 503);
    }

    if (!upstream.ok) {
      // Logged by status, NEVER returned. `toClientSafeError()`'s whole purpose
      // was that nothing about the credential or the upstream request can leak
      // through an error path.
      console.error(`Anthropic API error ${upstream.status}`);
      return json({ error: 'AI is temporarily unavailable' }, 503);
    }

    const payload = await upstream.json() as {
      content?: { type: string; text?: string }[];
      stop_reason?: string;
    };
    const text = (payload.content ?? [])
      .filter((block) => block.type === 'text')
      .map((block) => block.text ?? '')
      .join('')
      .trim();

    if (!text) {
      console.warn(`Claude returned no text (stop_reason=${payload.stop_reason})`);
      return json({ error: 'AI returned an empty response' }, 503);
    }

    return json({ text });
  } catch (e) {
    console.error('ai-nutrition error:', e instanceof Error ? e.name : 'unknown');
    return json({ error: 'AI is temporarily unavailable' }, 503);
  }
});
