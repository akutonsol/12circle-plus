// P0-SEC-1 / EDGE-2 — who may invoke send-checkin-reminder.
//
// The ONLY trusted caller is the scheduled job described in index.ts's header:
// pg_cron -> net.http_post with `Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>`.
//
// `verify_jwt = true` in config.toml is NOT enough: the gateway accepts any
// validly signed project JWT, i.e. every signed-in user's access token and the
// legacy JWT-format anon key. This module therefore requires the bearer to be
// byte-for-byte the service-role key the function itself is configured with.
//
// Plain JS (no Deno APIs) so it runs under Deno in the function and under
// `node --test` in CI. Uses only Web Crypto + TextEncoder, global in both.
//
// Nothing here logs, echoes or returns any part of either token.

const BEARER = /^Bearer[ \t]+([^\s]+)[ \t]*$/i;

async function sha256(text) {
  const bytes = new TextEncoder().encode(text);
  return new Uint8Array(await crypto.subtle.digest('SHA-256', bytes));
}

// Constant-time equality. Both sides are hashed first so the comparison always
// runs over 32 bytes and the token length does not shape the timing.
async function tokensEqual(a, b) {
  const [ha, hb] = await Promise.all([sha256(a), sha256(b)]);
  let diff = 0;
  for (let i = 0; i < ha.length; i++) diff |= ha[i] ^ hb[i];
  return diff === 0;
}

/**
 * Decide whether `req` comes from the service role.
 *
 * @param {Request} req
 * @param {string} serviceRoleKey  the function's SUPABASE_SERVICE_ROLE_KEY
 * @returns {Promise<{ ok: true } | { ok: false, status: 401 | 403 | 500, error: string }>}
 */
export async function authorizeServiceCaller(req, serviceRoleKey) {
  // Unconfigured server: refuse rather than compare against an empty string.
  if (typeof serviceRoleKey !== 'string' || serviceRoleKey.length === 0) {
    return { ok: false, status: 500, error: 'Server not configured' };
  }

  const header = req?.headers?.get?.('authorization') ?? '';
  const match = BEARER.exec(header);
  if (!match) {
    return { ok: false, status: 401, error: 'Unauthorized' };
  }

  if (!(await tokensEqual(match[1], serviceRoleKey))) {
    return { ok: false, status: 403, error: 'Forbidden' };
  }

  return { ok: true };
}

/** The refusal response index.ts returns. Generic body; no token detail. */
export function refusalResponse(result) {
  return new Response(JSON.stringify({ error: result.error }), {
    status: result.status,
    headers: { 'Content-Type': 'application/json' },
  });
}
