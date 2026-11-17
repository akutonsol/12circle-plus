// P0-SEC-1 / EDGE-2 — send-checkin-reminder refuses every caller but the service role.
//
//   node --test supabase/tests/functions/checkin_reminder_caller.test.mjs
//
// Fake requests and fake keys only: no network, no environment, no real secret.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

import {
  authorizeServiceCaller,
  refusalResponse,
} from '../../functions/send-checkin-reminder/service_caller.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const INDEX = resolve(here, '../../functions/send-checkin-reminder/index.ts');

// Fake JWT-shaped values. None is a real key.
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
const fakeJwt = (claims) => `${b64({ alg: 'HS256', typ: 'JWT' })}.${b64(claims)}.fakesignature`;
const SERVICE_KEY = fakeJwt({ iss: 'supabase', role: 'service_role', ref: 'fake' });
const ANON_KEY = fakeJwt({ iss: 'supabase', role: 'anon', ref: 'fake' });
const USER_JWT = fakeJwt({ sub: '00000000-0000-0000-0000-000000000001', role: 'authenticated', aud: 'authenticated' });
const PUBLISHABLE_KEY = 'sb_publishable_fakefakefakefakefake';

const req = (authorization) =>
  new Request('http://localhost/functions/v1/send-checkin-reminder', {
    method: 'POST',
    headers: authorization === undefined ? {} : { Authorization: authorization },
    body: '{}',
  });

test('refuses a request with no Authorization header (401)', async () => {
  const r = await authorizeServiceCaller(req(undefined), SERVICE_KEY);
  assert.deepEqual(r, { ok: false, status: 401, error: 'Unauthorized' });
});

test('refuses a non-Bearer or empty Authorization header (401)', async () => {
  for (const h of ['', 'Bearer', 'Bearer ', `Basic ${SERVICE_KEY}`, SERVICE_KEY, `Bearer ${SERVICE_KEY} extra`]) {
    const r = await authorizeServiceCaller(req(h), SERVICE_KEY);
    assert.equal(r.ok, false, `header form must be refused: ${JSON.stringify(h.slice(0, 12))}`);
    assert.equal(r.status, 401);
  }
});

test("refuses a signed-in user's JWT (403)", async () => {
  const r = await authorizeServiceCaller(req(`Bearer ${USER_JWT}`), SERVICE_KEY);
  assert.deepEqual(r, { ok: false, status: 403, error: 'Forbidden' });
});

test('refuses the legacy JWT-format anon key (403)', async () => {
  const r = await authorizeServiceCaller(req(`Bearer ${ANON_KEY}`), SERVICE_KEY);
  assert.deepEqual(r, { ok: false, status: 403, error: 'Forbidden' });
});

test('refuses a publishable key (403)', async () => {
  const r = await authorizeServiceCaller(req(`Bearer ${PUBLISHABLE_KEY}`), SERVICE_KEY);
  assert.equal(r.ok, false);
  assert.equal(r.status, 403);
});

test('refuses a wrong bearer, incl. a prefix, a suffix and a one-byte change of the key (403)', async () => {
  const flipped = SERVICE_KEY.slice(0, -1) + (SERVICE_KEY.endsWith('A') ? 'B' : 'A');
  for (const t of ['not-the-key', SERVICE_KEY.slice(0, -1), `${SERVICE_KEY}x`, flipped]) {
    const r = await authorizeServiceCaller(req(`Bearer ${t}`), SERVICE_KEY);
    assert.equal(r.ok, false);
    assert.equal(r.status, 403);
  }
});

test('refuses everything, even an empty bearer, when the server key is not configured (500)', async () => {
  for (const key of ['', undefined, null]) {
    for (const h of [undefined, 'Bearer ', `Bearer ${SERVICE_KEY}`]) {
      const r = await authorizeServiceCaller(req(h), key);
      assert.deepEqual(r, { ok: false, status: 500, error: 'Server not configured' });
    }
  }
});

test('accepts the exact service-role key (positive control)', async () => {
  assert.deepEqual(await authorizeServiceCaller(req(`Bearer ${SERVICE_KEY}`), SERVICE_KEY), { ok: true });
  // Scheme is case-insensitive, as pg_net / HTTP clients may vary it.
  assert.deepEqual(await authorizeServiceCaller(req(`bearer ${SERVICE_KEY}`), SERVICE_KEY), { ok: true });
});

test('refusal response carries the status and never echoes either token', async () => {
  const r = await authorizeServiceCaller(req(`Bearer ${USER_JWT}`), SERVICE_KEY);
  const res = refusalResponse(r);
  assert.equal(res.status, 403);
  const body = await res.text();
  assert.ok(!body.includes(USER_JWT) && !body.includes(SERVICE_KEY), 'body must not contain a token');
  assert.deepEqual(JSON.parse(body), { error: 'Forbidden' });
});

// Removes // and /* */ comments so a commented-out check cannot satisfy the
// wiring test. String and template literals are copied verbatim, so a `//`
// inside a URL is not mistaken for a comment. (index.ts has no regex literals.)
// Each comment becomes one space, so tokens either side of it stay separate.
function stripComments(src) {
  let out = '';
  let i = 0;
  while (i < src.length) {
    const c = src[i];
    const n = src[i + 1];
    if (c === '/' && n === '/') {
      while (i < src.length && src[i] !== '\n') i++;
      out += ' ';
    } else if (c === '/' && n === '*') {
      const end = src.indexOf('*/', i + 2);
      assert.ok(end >= 0, 'unterminated /* comment in index.ts');
      i = end + 2;
      out += ' ';
    } else if (c === "'" || c === '"' || c === '`') {
      let j = i + 1;
      while (j < src.length && src[j] !== c) j += src[j] === '\\' ? 2 : 1;
      out += src.slice(i, j + 1);
      i = j + 1;
    } else {
      out += c;
      i++;
    }
  }
  return out;
}

// Brace depth at `pos`, ignoring braces inside string/template literals.
function braceDepthAt(code, pos) {
  let depth = 0;
  for (let i = 0; i < pos; i++) {
    const c = code[i];
    if (c === "'" || c === '"' || c === '`') {
      let j = i + 1;
      while (j < code.length && code[j] !== c) j += code[j] === '\\' ? 2 : 1;
      i = j;
    } else if (c === '{') depth++;
    else if (c === '}') depth--;
  }
  return depth;
}

test('wiring: index.ts checks the caller and returns on refusal before any client, read, write or email', () => {
  const src = stripComments(readFileSync(INDEX, 'utf8'));

  // The handler must be one top-level serve(async (req) => { ... }), and its
  // first two statements must be exactly the check and the early return —
  // nothing before them, and not nested in any block (if (false) { … }, etc.).
  const serveRe = /\bserve\s*\(\s*async\s*\(\s*req\s*\)\s*=>\s*\{/g;
  const serves = [...src.matchAll(serveRe)];
  assert.equal(serves.length, 1, 'index.ts must have exactly one serve(async (req) => { … }) handler');
  const serveAt = serves[0].index;
  assert.equal(braceDepthAt(src, serveAt), 0, 'serve(...) must be called at top level, not inside a block');
  const body = src.slice(serveAt + serves[0][0].length);
  const firstTwo =
    /^\s*const\s+caller\s*=\s*await\s+authorizeServiceCaller\s*\(\s*req\s*,\s*SUPABASE_SERVICE_KEY\s*\)\s*;\s*if\s*\(\s*!\s*caller\.ok\s*\)\s*return\s+refusalResponse\s*\(\s*caller\s*\)\s*;/;
  assert.match(
    body,
    firstTwo,
    'the first two statements of the serve handler must be exactly ' +
      '`const caller = await authorizeServiceCaller(req, SUPABASE_SERVICE_KEY);` and ' +
      '`if (!caller.ok) return refusalResponse(caller);`',
  );

  assert.match(
    src,
    /import\s*\{[^}]*\bauthorizeServiceCaller\b[^}]*\}\s*from\s*['"]\.\/service_caller\.mjs['"]/,
    'index.ts must import authorizeServiceCaller from ./service_caller.mjs',
  );

  const call = src.search(/await\s+authorizeServiceCaller\s*\(\s*req\s*,\s*SUPABASE_SERVICE_KEY\s*\)/);
  assert.ok(call >= 0, 'index.ts must call authorizeServiceCaller(req, SUPABASE_SERVICE_KEY)');

  assert.ok(serveAt < call, 'the check must run inside the request handler');

  // The refusal must actually stop the handler, right after the check.
  const guard = /const\s+caller\s*=\s*await\s+authorizeServiceCaller\s*\(\s*req\s*,\s*SUPABASE_SERVICE_KEY\s*\)\s*;\s*if\s*\(\s*!\s*caller\.ok\s*\)\s*return\s+refusalResponse\s*\(\s*caller\s*\)\s*;/;
  assert.match(src, guard, 'index.ts must `if (!caller.ok) return refusalResponse(caller);` immediately after the check');

  const firstDbFrom = src.indexOf('db.from(');
  const firstDbCall = src.search(/\bdb\s*\.\s*from\s*\(/);
  assert.ok(firstDbFrom >= 0 && firstDbCall >= 0, 'expected the function to read via db.from(');
  assert.ok(call < firstDbFrom && call < firstDbCall, 'caller check must precede the first db.from(');

  for (const sink of ['createClient(', 'fetch(', ".insert("]) {
    const at = src.indexOf(sink);
    if (at >= 0) assert.ok(call < at, `caller check must precede the first ${sink}`);
  }
});
