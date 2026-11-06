// Live AI / intelligence decision-integrity harness (QA Workstream J).
//
// Runs against a REAL Supabase project over the same REST/RPC/Functions surface
// a phone uses, with the same anon key and real JWTs. A static assertion can
// tell you an edge function selects a column; only a live call can tell you the
// column exists, that the function is deployed, and that the guard composes.
//
// SAFETY
//   * Refuses to run against the production project ref.
//   * READ-ONLY by default. Anything that writes is gated behind
//     AI_ALLOW_WRITES=1 and is listed in the report's QA-mutations section.
//   * Reuses the p1-* fixtures created by supabase/tests/security. No service
//     key is required.
//
// Usage:
//   export QA_URL=https://<ref>.supabase.co QA_ANON=<anon key>
//   node supabase/tests/ai/run.mjs

export const URL_ = process.env.QA_URL;
export const ANON = process.env.QA_ANON;
export const ALLOW_WRITES = process.env.AI_ALLOW_WRITES === '1';

const PROD_REF = 'nxdbooufqzkpslkcogxc';

if (!URL_ || !ANON) {
  console.error('QA_URL and QA_ANON must be set. See supabase/tests/ai/README.md');
  process.exit(2);
}
if (URL_.includes(PROD_REF)) {
  console.error(`REFUSING TO RUN: ${PROD_REF} is the production project.`);
  process.exit(2);
}

// The same fixtures supabase/tests/security/setup-identities.mjs creates.
export const IDENT = {
  victim:   { email: 'p1-victim@qa.12circle.test',   pw: 'P1-Probe-Victim-2026!'   },
  attacker: { email: 'p1-attacker@qa.12circle.test', pw: 'P1-Probe-Attacker-2026!' },
  coach:    { email: 'p1-coach@qa.12circle.test',    pw: 'P1-Probe-Coach-2026!'    },
  admin:    { email: 'p1-admin@qa.12circle.test',    pw: 'P1-Probe-Admin-2026!'    },
  // Created by setup-identities.mjs alongside the other four. Carries role
  // content_manager, which PD-A05 option (a) deliberately excludes from
  // decision-trace reads (F-J-12).
  contentmgr: { email: 'p1-content-manager@qa.12circle.test', pw: 'P1-Probe-ContentMgr-2026!' },
};

async function parse(res) {
  const t = await res.text();
  let body; try { body = t ? JSON.parse(t) : null; } catch { body = t; }
  return { status: res.status, ok: res.ok, body, headers: res.headers };
}

const tokenCache = new Map();
export async function signIn(key) {
  if (tokenCache.has(key)) return tokenCache.get(key);
  const { email, pw } = IDENT[key];
  const r = await fetch(`${URL_}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: ANON, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: pw }),
  });
  const { status, body } = await parse(r);
  if (status >= 300) {
    throw new Error(`signIn ${email}: ${status} — run supabase/tests/security/setup-identities.mjs first`);
  }
  tokenCache.set(key, body.access_token);
  return body.access_token;
}

function hdrs(jwt, extra = {}) {
  return { apikey: ANON, Authorization: `Bearer ${jwt ?? ANON}`, 'Content-Type': 'application/json', ...extra };
}

/** Plain read. `path` is everything after /rest/v1/, filters included. */
export async function rest(jwt, path, extra = {}) {
  return parse(await fetch(`${URL_}/rest/v1/${path}`, { headers: hdrs(jwt, extra) }));
}

export async function rpc(jwt, fn, args = {}) {
  return parse(await fetch(`${URL_}/rest/v1/rpc/${fn}`, {
    method: 'POST', headers: hdrs(jwt), body: JSON.stringify(args),
  }));
}

/** Invoke an edge function exactly as supabase_flutter does. */
export async function fn(jwt, name, body = {}) {
  return parse(await fetch(`${URL_}/functions/v1/${name}`, {
    method: 'POST', headers: hdrs(jwt), body: JSON.stringify(body),
  }));
}

/**
 * Does `table.column` exist and is it selectable by this caller?
 *
 * PostgREST answers 42703 for a column that is not there, which is exactly the
 * failure an edge function's `.select('a, b, c')` hits — and which supabase-js
 * turns into `{ data: null }` rather than a throw. That silent null is the
 * whole reason this probe exists.
 */
export async function columnExists(jwt, table, column) {
  const r = await rest(jwt, `${table}?select=${column}&limit=1`);
  if (r.status < 300) return { ok: true };
  const code = r.body?.code;
  return { ok: false, code, message: r.body?.message };
}

// ── reporting ────────────────────────────────────────────────────────────────
//
// Two kinds of assertion, and the difference matters:
//
//   invariant       — a property the system MUST hold. A failure is a
//                     regression and fails the run.
//   characterization— a defect this workstream FOUND and pinned as it actually
//                     behaves today, with its finding ID. It passes while the
//                     defect is present. When it starts failing, the behaviour
//                     changed: either it was remediated (invert the assertion
//                     and promote it to an invariant) or it drifted further.
//                     Either way it must be looked at, so a broken
//                     characterization also fails the run.
//
// Nothing here is ever marked "expected to fail". A red test nobody can act on
// is noise; a characterization that flips is a signal.
export const results = [];
export function check(name, pass, detail, kind = 'invariant') {
  results.push({ name, pass, detail, kind });
  const tag = kind === 'characterization' ? 'CHAR' : 'INV ';
  console.log(`  ${pass ? 'PASS' : 'FAIL'} ${tag}  ${name}${detail ? `  — ${detail}` : ''}`);
  return pass;
}
export const invariant = (name, pass, detail) => check(name, pass, detail, 'invariant');
export const characterize = (name, pass, detail) => check(name, pass, detail, 'characterization');

/**
 * A check that was deliberately NOT asserted. Same semantics as
 * supabase/tests/security/lib.mjs skip(): it is neither a pass nor a failure,
 * it is counted and listed separately, and it never adds to "N/N passed".
 * A skip is a gap in the evidence, so it always says why.
 */
export function skip(name, reason) {
  results.push({ name, pass: null, skipped: true, detail: reason, kind: 'skip' });
  console.log(`  SKIP        ${name}${reason ? `  — ${reason}` : ''}  (NOT a pass)`);
}

/**
 * A suite's verdict. A suite that asserted nothing but recorded skips is SKIP,
 * never PASS: "0 of 0 passed" is not evidence.
 */
export function suiteVerdict({ ran, skipped = 0, failures }) {
  if (failures > 0) return 'FAIL';
  if (ran - skipped === 0 && skipped > 0) return 'SKIP';
  return 'PASS';
}

// ── the intelligence substrate (exercise_intelligence) ──────────────────────
//
// A few checks pin behaviour that only exists while exercise_intelligence is
// EMPTY. They are asserted when the table is known to be empty, skipped when it
// is known to be populated, and FAILED when the state cannot be established —
// a probe that fails is never read as "empty".

/** Total rows from a `Prefer: count=exact` response's content-range, or null. */
export function contentRangeTotal(res) {
  const m = /\/(\d+)$/.exec(res?.headers?.get?.('content-range') ?? '');
  return m ? Number(m[1]) : null;
}

/**
 * Pure: classify a probe. `isEditor` must be exactly `true` — the table is
 * content-editor-only (migration 117), so anyone else sees 0 rows whatever it
 * holds, and that 0 must not be taken for an empty table.
 */
export function substrateFrom(isEditor, res) {
  if (isEditor !== true) return { state: 'unknown', detail: 'the probing account is not a content editor (117 hides the table)' };
  if (!res || res.status >= 300) return { state: 'unknown', detail: `HTTP ${res?.status ?? 'none'}` };
  const n = contentRangeTotal(res);
  if (n === null || !Number.isInteger(n) || n < 0) return { state: 'unknown', detail: 'no row count in the response' };
  return { state: n === 0 ? 'empty' : 'populated', detail: `${n} rows` };
}

/** Network: probe the substrate as `jwt` (use the admin fixture). Counts only. */
export async function intelligenceSubstrate(jwt) {
  try {
    const editor = await rpc(jwt, 'is_content_editor');
    const res = await rest(jwt, 'exercise_intelligence?select=exercise_id&limit=0', { Prefer: 'count=exact' });
    return substrateFrom(editor.status < 300 ? editor.body : null, res);
  } catch (e) {
    return { state: 'unknown', detail: `probe error: ${e.message}` };
  }
}

/**
 * Run `assert` — an assertion that pins EMPTY-substrate behaviour — only when the
 * substrate is known to be empty. Populated: skip it, with the reason. Unknown:
 * record a failure. `assert` runs exactly as it did before this gate existed.
 */
export function whenSubstrateEmpty(substrate, name, assert) {
  if (substrate?.state === 'empty') return assert();
  if (substrate?.state === 'populated') {
    return skip(name, `exercise_intelligence is populated (${substrate.detail}); this pins ` +
      'empty-substrate behaviour, which cannot be exercised now');
  }
  return check(`${name} — substrate state`, false,
    `could not establish whether exercise_intelligence is empty (${substrate?.detail ?? 'no probe'}); ` +
    'refusing to treat an unknown state as empty', 'invariant');
}

export function section(t) { console.log(`\n── ${t} ${'─'.repeat(Math.max(2, 68 - t.length))}`); }

/** Index into `results` at the moment a suite starts, so its summary is its own. */
export const mark = () => results.length;

export function summary(label, from = 0) {
  const mine = results.slice(from);
  const skipped = mine.filter(r => r.skipped);
  const asserted = mine.filter(r => !r.skipped);
  const f = asserted.filter(r => !r.pass);
  console.log(`\n${'='.repeat(74)}\n${label}: ${asserted.length - f.length}/${asserted.length} passed` +
    (skipped.length ? `, ${skipped.length} SKIPPED (not passes)` : ''));
  if (f.length) { console.log('FAILURES:'); f.forEach(r => console.log(`  x ${r.name} — ${r.detail || ''}`)); }
  if (skipped.length) {
    console.log('SKIPPED (not asserted — each is a gap in the evidence, not a pass):');
    skipped.forEach(r => console.log(`  - ${r.name} — ${r.detail || ''}`));
  }
  return f.length;
}
