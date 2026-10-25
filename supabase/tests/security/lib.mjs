import { execFileSync } from 'node:child_process';

// ⚠ CONCURRENCY GUARD — runs ONCE PER PROCESS, on import.
//
// It used to live in run.mjs, which protected the full regression and nothing else.
// V5 §161: two overlapping LOCAL runs of d15 on its own interleaved, one holding
// trust_lead while the other's "forbidden" loop called audit_open_incident — so an
// incident that must never exist was created, and audit_incidents cannot be deleted.
// Every suite imports this module, so the guard now covers every entry point.
//
//   ALLOW_CONCURRENT_QA_RUN=1   to override deliberately
function refuseIfCiRunning() {
  if (process.env.ALLOW_CONCURRENT_QA_RUN === '1') return;
  if (process.env.CI) return;                       // this IS the CI runner
  let branch, raw;
  try {
    branch = execFileSync('git', ['rev-parse', '--abbrev-ref', 'HEAD'],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
    raw = execFileSync('gh', ['run', 'list', '--branch', branch, '--limit', '10',
      '--json', 'status,databaseId,headSha'],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
  } catch {
    console.log('  (could not check for in-flight CI — proceeding)');
    return;
  }
  let live = [];
  try {
    live = JSON.parse(raw).filter((r) =>
      ['queued', 'in_progress', 'requested', 'waiting', 'pending'].includes(r.status));
  } catch { return; }
  if (!live.length) return;
  console.error(`\n  ✋ REFUSING TO RUN — CI is executing on "${branch}":`);
  for (const r of live) console.error(`     run ${r.databaseId}  ${String(r.headSha).slice(0, 7)}  ${r.status}`);
  console.error(`
  Both would arrange the SAME fixtures against the SAME QA project. V5 §95 produced
  four failures that read like an authorization hole and were not; §146 produced a
  J-04 failure in a suite the change never touched.

  Wait for it, or override deliberately:
      ALLOW_CONCURRENT_QA_RUN=1 node supabase/tests/security/run.mjs
`);
  process.exit(2);
}
refuseIfCiRunning();

// Live security regression harness.
//
// These suites run against a REAL Supabase project over the REST/RPC surface,
// with the same anon key and the same JWTs a phone would use. That is the point:
// a static SQL assertion cannot tell you whether PostgREST, the column grants,
// the policies and the triggers compose into an actual boundary. Every finding
// in the Phase 1 audit was reproduced here first and is now pinned here.
//
// SAFETY: the harness refuses to run against the production project. It only
// ever touches its own `p1-*@qa.12circle.test` fixtures.
//
// Usage:
//   export QA_URL=https://<ref>.supabase.co QA_ANON=... QA_SERVICE=...
//   node supabase/tests/security/run.mjs

export const URL_ = process.env.QA_URL;
export const ANON = process.env.QA_ANON;
export const SERVICE = process.env.QA_SERVICE;

const PROD_REF = 'nxdbooufqzkpslkcogxc';

if (!URL_ || !ANON || !SERVICE) {
  console.error('QA_URL, QA_ANON and QA_SERVICE must be set. See supabase/tests/security/README.md');
  process.exit(2);
}
if (URL_.includes(PROD_REF)) {
  console.error(`REFUSING TO RUN: ${PROD_REF} is the production project.`);
  process.exit(2);
}

// Fixture identities. Created on demand by setup-identities.mjs; all are
// flagged is_demo so they stay out of discovery surfaces.
export const IDENT = {
  victim:   { email: 'p1-victim@qa.12circle.test',   pw: 'P1-Probe-Victim-2026!',   role: 'client' },
  attacker: { email: 'p1-attacker@qa.12circle.test', pw: 'P1-Probe-Attacker-2026!', role: 'client' },
  coach:    { email: 'p1-coach@qa.12circle.test',    pw: 'P1-Probe-Coach-2026!',    role: 'coach'  },
  admin:    { email: 'p1-admin@qa.12circle.test',    pw: 'P1-Probe-Admin-2026!',    role: 'admin'  },
  // F-J-12 / PD-A05 option (a), 2026-08-27. `content_manager` is the one role
  // the ruling deliberately does NOT grant decision-trace access to, and it is
  // the arm that distinguishes option (a) from option (b). Without an identity
  // carrying it, that arm is unassertable in either direction.
  contentmgr: { email: 'p1-content-manager@qa.12circle.test', pw: 'P1-Probe-ContentMgr-2026!', role: 'content_manager' },
};

async function parse(res) {
  const t = await res.text();
  let body; try { body = t ? JSON.parse(t) : null; } catch { body = t; }
  return { status: res.status, ok: res.ok, body, headers: res.headers };
}

// ── auth ─────────────────────────────────────────────────────────────────────
export async function adminFindUser(email) {
  const r = await fetch(`${URL_}/auth/v1/admin/users?filter=${encodeURIComponent(email)}`,
    { headers: { apikey: SERVICE, Authorization: `Bearer ${SERVICE}` } });
  const { body } = await parse(r);
  return (body?.users || []).find(u => u.email === email) || null;
}

export async function ensureUser(key) {
  const { email, pw } = IDENT[key];
  let u = await adminFindUser(email);
  if (!u) {
    const r = await fetch(`${URL_}/auth/v1/admin/users`, {
      method: 'POST',
      headers: { apikey: SERVICE, Authorization: `Bearer ${SERVICE}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password: pw, email_confirm: true }),
    });
    const { status, body } = await parse(r);
    if (status >= 300) throw new Error(`create ${email}: ${status} ${JSON.stringify(body)}`);
    u = body;
  } else {
    await fetch(`${URL_}/auth/v1/admin/users/${u.id}`, {
      method: 'PUT',
      headers: { apikey: SERVICE, Authorization: `Bearer ${SERVICE}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ password: pw, email_confirm: true }),
    });
  }
  return u.id;
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
  if (status >= 300) throw new Error(`signIn ${email}: ${status} ${JSON.stringify(body)}`);
  tokenCache.set(key, body.access_token);
  return body.access_token;
}

// ── rest ─────────────────────────────────────────────────────────────────────
// who: 'anon' | 'service' | <jwt>
function hdrs(who, extra = {}) {
  const key = who === 'service' ? SERVICE : ANON;
  const bearer = who === 'anon' ? ANON : who === 'service' ? SERVICE : who;
  return { apikey: key, Authorization: `Bearer ${bearer}`, 'Content-Type': 'application/json', ...extra };
}

/** Plain read. `path` is everything after /rest/v1/, filters included. */
export async function rest(who, path, opts = {}) {
  const r = await fetch(`${URL_}/rest/v1/${path}`, {
    method: opts.method || 'GET',
    headers: hdrs(who, opts.headers),
    body: opts.body ? JSON.stringify(opts.body) : undefined,
  });
  return parse(r);
}

/**
 * Write exactly the way the Flutter client writes: `Prefer: return=minimal`,
 * i.e. no RETURNING clause.
 *
 * This matters. `return=representation` needs SELECT on every column, so on a
 * table that deliberately withholds a column (invite_token) it 403s for reasons
 * that have nothing to do with the policy under test — and would make an
 * unprotected table look protected. `count=exact` gives rows-affected through
 * the Content-Range header instead, with no column privilege required.
 *
 * Returns { status, affected } where affected is null when unavailable.
 */
export async function mutate(who, path, method, body) {
  const r = await fetch(`${URL_}/rest/v1/${path}`, {
    method,
    headers: hdrs(who, { Prefer: 'return=minimal,count=exact' }),
    body: body ? JSON.stringify(body) : undefined,
  });
  const p = await parse(r);
  const cr = r.headers.get('content-range');           // e.g. "*/3"
  const affected = cr && cr.includes('/') ? Number(cr.split('/')[1]) : null;
  return { status: p.status, body: p.body, affected: Number.isNaN(affected) ? null : affected };
}

/** A mutation is BLOCKED when it errors, or succeeds against zero rows. */
export const blocked = (m) => m.status >= 400 || m.affected === 0;
/** A mutation LANDED when it succeeded and touched at least one row. */
export const landed = (m) => m.status < 300 && (m.affected === null || m.affected > 0);

export async function rpc(who, fn, args = {}) {
  const r = await fetch(`${URL_}/rest/v1/rpc/${fn}`, {
    method: 'POST', headers: hdrs(who), body: JSON.stringify(args),
  });
  return parse(r);
}

/** Service-role helper — used only to arrange fixtures, never to assert. */
export async function svc(path, opts = {}) {
  const r = await fetch(`${URL_}/rest/v1/${path}`, {
    method: opts.method || 'GET',
    // `...opts.headers` LAST, AND THIS WAS A REAL BUG. This helper used to build its
    // headers and drop `opts.headers` on the floor, honouring only `opts.prefer`. Three
    // call sites passed `headers: { Prefer: … }` and were silently ignored: two in D16
    // asked for `count=exact` and never got it (harmless — they count by body length), and
    // one in D19 asked for `resolution=merge-duplicates` on a one-row table, so the upsert
    // became a primary-key conflict, the teardown appeared to succeed, and **QA's Guardian
    // was left disabled by a test**. A helper that accepts an option and ignores it is
    // worse than one that rejects it.
    headers: { apikey: SERVICE, Authorization: `Bearer ${SERVICE}`, 'Content-Type': 'application/json',
               Prefer: opts.prefer || 'return=representation', ...opts.headers },
    body: opts.body ? JSON.stringify(opts.body) : undefined,
  });
  return parse(r);
}

// ── reporting ────────────────────────────────────────────────────────────────
export const results = [];
let suiteStart = 0;

export function beginSuite() {
  suiteStart = results.length;
}

export function check(name, pass, detail) {
  results.push({ name, pass, detail });
  console.log(`  ${pass ? 'PASS' : 'FAIL'}  ${name}${detail ? `  — ${detail}` : ''}`);
  return pass;
}

/**
 * An assertion that was deliberately NOT made — recorded, never counted as a pass.
 *
 * Use it ONLY when the thing under test is known not to exist yet on QA (e.g. its
 * migration is declared pending — see migration-state.mjs), so asserting it would
 * fail on intent rather than on a defect, and running the probe would itself
 * write the defect into QA. Before this helper, gated checks were a console line
 * and the suite still printed "25/25 passed": the skipped scenarios were invisible
 * in the score. A skip is now part of the result set, is excluded from the pass
 * count, and is printed by `summary()` and by run.mjs on its own line.
 */
export function skip(name, reason) {
  results.push({ name, pass: null, skipped: true, detail: reason });
  console.log(`  SKIP  ${name}${reason ? `  — ${reason}` : ''}  (NOT a pass)`);
  return null;
}

/**
 * A DENIAL assertion that cannot pass for want of data.
 *
 * V5 §139.5. Four assertions in this programme passed for the wrong reason, and
 * three were the same shape: a deny check over a table with no rows.
 *   · §128.5  "a Viewer reads 0 row-level workout_logs" — workout_logs is empty.
 *   · §132.3  two Security categories asserted absent — neither had any rows, so a
 *             MISSPELLED category in the view would have satisfied the test.
 *   · §135.2  "a Viewer cannot read governance_policy" — the table is empty, and
 *             the assertion kept passing after the approved matrix INVERTED the
 *             posture it described. It was not merely unproven; it was wrong.
 *
 * `saw === 0` only means something when there was something to see. This FAILS on
 * an empty population rather than passing, so the absence of data is reported as a
 * gap in the evidence instead of being silently counted as proof.
 *
 *   checkDenied('a Viewer reads no other member', { saw: n(mine.body), population: n(all.body) })
 *
 * Use `allowEmpty` only where emptiness is itself the fact being recorded, and say
 * so in the name — the assertion then states plainly that it proves nothing.
 */
export function checkDenied(name, { saw, population, detail = '', allowEmpty = false }) {
  if (population === 0 && !allowEmpty) {
    return check(name, false,
      `NOT ASSERTABLE: the population is empty, so "saw ${saw}" distinguishes refusal ` +
      `from absence. Seed a row or mark allowEmpty.${detail ? ` ${detail}` : ''}`);
  }
  if (population === 0) {
    return check(`${name} (population empty — recorded, not proof)`, saw === 0,
      `saw=${saw} population=0${detail ? ` ${detail}` : ''}`);
  }
  return check(name, saw === 0, `saw=${saw} of ${population}${detail ? ` ${detail}` : ''}`);
}

/**
 * The other half: a GRANT assertion that cannot pass for want of data either.
 * §136.3 — an inert grant is invisible from both ends, because a test asserting
 * "the denied role sees nothing" passes while the granted role also sees nothing.
 * This is what turned AI Guardian from an assumption into a measurement.
 */
export function checkGranted(name, { saw, population, detail = '' }) {
  if (population === 0) {
    return check(name, false,
      `NOT ASSERTABLE: the population is empty, so "saw ${saw}" cannot show the grant ` +
      `works.${detail ? ` ${detail}` : ''}`);
  }
  return check(name, saw === population,
    `saw=${saw} of ${population}${detail ? ` ${detail}` : ''}`);
}

/**
 * A WRITE-REFUSAL assertion that reads the database, not the status line.
 *
 * V5 §155. A privilege sweep over twelve system-owned tables reported a write
 * privilege on every one of them, and ALL TWELVE were artifacts of the probe:
 *   · PostgREST answers 201 to an INSERT that RLS's WITH CHECK rejects — nothing
 *     is created, and the status says otherwise;
 *   · it answers 204 to a PATCH whose row set is empty, or whose body is empty,
 *     whether or not the privilege exists (§129.2 established this for UPDATE);
 *   · an empty `{}` body yields 201 with no row at all.
 *
 * So neither 2xx nor 4xx proves anything about a write on its own. `before` and
 * `after` row counts do. Use this wherever the question is "did this write land",
 * which is the only question that matters.
 */
export function checkNoWrite(name, { before, after, status, detail = '' }) {
  return check(name, after <= before,
    `rows ${before}->${after} (status ${status}${detail ? `, ${detail}` : ''}) — ` +
    'asserted by row count, because a PostgREST 201/204 does not mean a write landed');
}

export function section(t) {
  console.log(`\n── ${t} ${'─'.repeat(Math.max(2, 68 - t.length))}`);
}

export function summary(label) {
  const suiteResults = results.slice(suiteStart);
  // A SKIP is neither a pass nor a failure (see skip()). The headline counts only
  // assertions actually made, and the skips are named on their own.
  const skipped = suiteResults.filter(r => r.skipped);
  const asserted = suiteResults.filter(r => !r.skipped);
  const f = asserted.filter(r => !r.pass);

  console.log(
    `\n${'='.repeat(74)}\n${label}: ${asserted.length - f.length}/${asserted.length} passed` +
    (skipped.length ? `, ${skipped.length} SKIPPED (not passes)` : '')
  );
  if (skipped.length) {
    console.log('SKIPPED (not asserted — each is a gap in the evidence, not a pass):');
    skipped.forEach(r => console.log(`  - ${r.name} — ${r.detail || ''}`));
  }

  if (f.length) {
    console.log('FAILURES:');
    f.forEach(r => console.log(`  x ${r.name} — ${r.detail || ''}`));
  }

  return f.length;
}


/** PostgREST's default page size. A body of exactly this length may be a CAPPED page
 *  rather than a true count. */
export const PAGE_LIMIT = 1000;

/** Row count of a PostgREST body; an error object counts as zero rows read.
 *
 *  THIS IS DELIBERATELY A PURE LENGTH, and an earlier version of it was not.
 *  I made it raise a failed check on any body of exactly PAGE_LIMIT rows, which found
 *  the real P2 defect (§174.1) and then fired on four D15 sites that are NOT blind:
 *  they pass `limit=1000` on purpose and compare PRESENCE (`> 0`, `=== 0`), which a
 *  capped page does not affect. Saturation is fatal to a DELTA or an EQUALITY over a
 *  large population, and harmless to presence — so the check belongs where that
 *  distinction is known, which is [checkDelta], not here. A detector that cries wolf
 *  on correct code gets switched off. */
export const n = (b) => (Array.isArray(b) ? b.length : 0);

/** A before/after DELTA assertion that REFUSES to run on a saturated count.
 *
 *  This is where paging actually bites. P2 asserted `before + 1 === after` over
 *  `audit_events.admin_action`, counted by the length of one PostgREST page. The
 *  population crossed 1000 (1028 exact), both sides read 1000, and the assertion could
 *  no longer see the event appear — nor see one FAIL to appear, which is the property it
 *  existed to protect. The audit path was healthy the entire time.
 *
 *  So a delta built on a number that may be a capped page is reported as UNMEASURABLE
 *  rather than as a pass or a fail. Count with [countExact] and it cannot happen. */
export function checkDelta(name, { before, after, expected = 1, detail = '' }) {
  if (before === PAGE_LIMIT || after === PAGE_LIMIT) {
    return check(`${name} — UNMEASURABLE`, false,
      `before=${before} after=${after}: one side is exactly PAGE_LIMIT, so this is a ` +
      'capped page and the delta is invisible in both directions. Use countExact(). ' +
      detail);
  }
  return check(name, after === before + expected,
    `${before} -> ${after} (expected +${expected}) ${detail}`.trim());
}

/** The exact row count of a population, from `content-range`, independent of paging.
 *  Reads as service_role, so it is a MEASUREMENT and never an access assertion — use
 *  `rest()` for anything that must observe a caller's own visibility. */
export async function countExact(path) {
  const sep = path.includes('?') ? '&' : '?';
  const r = await fetch(`${URL_}/rest/v1/${path}${sep}select=id&limit=1`, {
    headers: { apikey: SERVICE, Authorization: `Bearer ${SERVICE}`,
               Prefer: 'count=exact' },
  });
  const range = r.headers.get('content-range') || '';
  const total = Number(range.split('/')[1]);
  if (!Number.isFinite(total)) {
    throw new Error(`countExact: no usable content-range for ${path} (got "${range}") ` +
      '— refusing to return a count that was not measured');
  }
  return total;
}

/**
 * `countExact`, but AS A SIGNED-IN CALLER rather than as service_role.
 *
 * WHY BOTH EXIST. `countExact` goes through `service_role`, which bypasses RLS — and for any
 * surface gated on `admin_can(...)` that gate is FALSE for service_role, so a service count of
 * `admin_user_directory` is 0 and a comparison against it is vacuous. D20 §6 and D21 §3 each
 * made that mistake once. This counts the population the CALLER can actually see.
 *
 * Same refusal as `countExact`: a missing content-range throws rather than returning a number
 * nobody measured.
 */
export async function countExactAs(who, path) {
  const sep = path.includes('?') ? '&' : '?';
  const r = await fetch(`${URL_}/rest/v1/${path}${sep}select=id&limit=1`, {
    headers: { apikey: ANON, Authorization: `Bearer ${who}`, Prefer: 'count=exact' },
  });
  const range = r.headers.get('content-range') || '';
  const total = Number(range.split('/')[1]);
  if (!Number.isFinite(total)) {
    throw new Error(`countExactAs: no usable content-range for ${path} (got "${range}") ` +
      '— refusing to return a count that was not measured');
  }
  return total;
}

export async function loadIds() {
  const { readFileSync } = await import('node:fs');
  const p = new URL('./ids.json', import.meta.url);
  try { return JSON.parse(readFileSync(p, 'utf8')); }
  catch { throw new Error('ids.json missing — run: node supabase/tests/security/setup-identities.mjs'); }
}
