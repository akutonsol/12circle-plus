// Regression test for d08's OD-QAX-2 fixture read-back — LOCAL, OFFLINE, NEVER QA.
//
//   node supabase/tests/local/d08_fixture_regression.mjs
//
// WHY. d08's gated block used to create its pending relationship and cancel it with
// fire-and-forget writes. A cancel that did not persist left the actor PENDING, and
// "a CANCELLED coach is refused" passed against the wrong state. d08 now reads each
// fixture back (fixture-state.mjs) and records the dependent refusal assertions as
// FAILED when the fixture is not in place. This test PROVES that, by running the
// REAL d08 against a local PostgREST-shaped mock that faithfully models migration
// 184's authorisation and can DELIBERATELY BREAK each fixture step:
//
//   none            everything persists            -> every OD-QAX-2 assertion PASSES
//   drop-cancel     the cancel PATCH is ignored    -> cancelled fixture + 2 dependents FAIL
//   drop-pending    the pending insert is dropped  -> pending fixture + dependent FAIL,
//                                                     and the cancel cannot persist either
//   stale-active-cb a stale ACTIVE C->B row exists -> unrelated fixture + 2 dependents FAIL
//
// It never opens a socket to anything but 127.0.0.1, strips every QA_* variable from
// the child's environment, and runs d08 from a temp COPY of the security directory
// whose manifest declares 184 applied (the strict half of the gate) — the repository
// manifest is read, never written.
//
// LIMITS, stated so this is not read as more than it is: it models d08's OD-QAX-2
// block only (the other d08 sections fail against the mock and are ignored), it is
// not evidence about QA, and the mock's authorisation is a model of 184, not 184.

import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';

const ROOT = new URL('../../../', import.meta.url).pathname;
const SEC = path.join(ROOT, 'supabase/tests/security');

// ── the mock ─────────────────────────────────────────────────────────────────
const UID = { 'p1-coach@qa.12circle.test': 'u-coach', 'p1-victim@qa.12circle.test': 'u-victim',
  'p1-attacker@qa.12circle.test': 'u-attacker' };

function startMock(fault) {
  const db = { coach_client_relationships: [], client_nutrition_plans: [] };
  if (fault === 'stale-active-cb')
    db.coach_client_relationships.push({ coach_id: 'u-attacker', client_id: 'u-victim', status: 'active' });
  let nid = 1;
  const matches = (row, q) => { for (const [k, v] of q) {
    if (['select', 'limit', 'order'].includes(k)) continue;
    if (v.startsWith('eq.')) { if (String(row[k]) !== v.slice(3)) return false; }
    else if (v.startsWith('in.(')) { if (!v.slice(4, -1).split(',').includes(String(row[k]))) return false; }
    else return false; } return true; };
  const activeRel = (c, cl) => db.coach_client_relationships
    .some((r) => r.coach_id === c && r.client_id === cl && r.status === 'active');

  const server = http.createServer(async (req, res) => {
    const url = new URL(req.url.replace(/^\/eyqtldjqpgpljlqvpowh/, ''), 'http://x');
    let body = ''; for await (const c of req) body += c;
    const json = body ? JSON.parse(body) : null;
    const auth = (req.headers.authorization || '').replace('Bearer ', '');
    const send = (code, data) => { res.writeHead(code, { 'content-type': 'application/json' });
      res.end(data === undefined ? '' : JSON.stringify(data)); };
    const service = auth === 'mock-service';
    const actor = auth.startsWith('jwt:') ? UID[auth.slice(4)] : null;

    if (url.pathname.startsWith('/auth/v1/token'))
      return send(200, { access_token: 'jwt:' + json.email, user: { id: UID[json.email] } });

    const rpc = url.pathname.match(/^\/rest\/v1\/rpc\/(\w+)/);
    if (rpc) {
      if (rpc[1] !== 'assign_nutrition_plan') return send(404, { message: 'not mocked' });
      if (!actor) return send(401, { code: '42501', message: 'not authenticated' });
      if (!activeRel(actor, json.p_client_id))                      // migration 184
        return send(400, { code: '42501', message: 'not authorized' });
      for (const r of db.client_nutrition_plans) if (r.client_id === json.p_client_id && r.is_active) r.is_active = false;
      const row = { id: 'plan' + nid++, client_id: json.p_client_id, coach_id: actor,
        calories_target: json.p_calories_target, is_active: true };
      db.client_nutrition_plans.push(row); return send(200, row.id);
    }

    const m = url.pathname.match(/^\/rest\/v1\/(\w+)/);
    if (!m || !db[m[1]]) return send(404, { message: 'not mocked' });
    const t = m[1]; const rows = db[t]; const q = [...url.searchParams.entries()];
    if (req.method === 'GET') {
      const vis = (r) => service || t === 'coach_client_relationships' || r.client_id === actor || r.coach_id === actor;
      return send(200, rows.filter((r) => matches(r, q) && vis(r)));
    }
    if (req.method === 'POST') {
      const row = { id: 'id' + nid++, ...json };
      if (t === 'coach_client_relationships') {
        if (rows.some((r) => r.coach_id === row.coach_id && r.client_id === row.client_id))
          return send(409, { code: '23505', message: 'duplicate key' });
        if (fault === 'drop-pending' && row.status === 'pending') return send(201);   // 201, no row
      }
      if (t === 'client_nutrition_plans' && row.is_active && rows.some((r) => r.client_id === row.client_id && r.is_active))
        return send(409, { code: '23505', message: 'duplicate key value violates unique constraint' });
      rows.push(row); return send(201);
    }
    if (req.method === 'PATCH') {
      for (const r of rows) if (matches(r, q) && service) {
        if (fault === 'drop-cancel' && json.status === 'cancelled') continue;          // 204, no change
        Object.assign(r, json);
      }
      return send(204);
    }
    if (req.method === 'DELETE') { db[t] = rows.filter((r) => !matches(r, q)); return send(204); }
    send(405, {});
  });
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve({ server, port: server.address().port })));
}

// ── a temp COPY of the security suites whose manifest declares 184 APPLIED ───
function makeTree() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'd08-regress-'));
  const sec = path.join(dir, 'supabase/tests/security');
  fs.mkdirSync(sec, { recursive: true });
  for (const f of fs.readdirSync(SEC)) if (f.endsWith('.mjs')) fs.copyFileSync(path.join(SEC, f), path.join(sec, f));
  const m = JSON.parse(fs.readFileSync(path.join(ROOT, 'supabase/expected_applied.json'), 'utf8'));
  m.environments.qa.applied_through = '186'; m.environments.qa.pending = {}; m.environments.qa.excluded = {};
  fs.writeFileSync(path.join(dir, 'supabase/expected_applied.json'), JSON.stringify(m));
  return { dir, d08: path.join(sec, 'd08-identity-constraints.mjs') };
}

function runD08(tree, port) {
  const env = Object.fromEntries(Object.entries(process.env).filter(([k]) => !k.startsWith('QA_')));
  Object.assign(env, { CI: '1', QA_URL: `http://127.0.0.1:${port}/eyqtldjqpgpljlqvpowh`,
    QA_ANON: 'mock-anon', QA_SERVICE: 'mock-service' });
  return new Promise((resolve) => {
    const p = spawn(process.execPath, [tree.d08], { env });
    let out = ''; p.stdout.on('data', (d) => out += d); p.stderr.on('data', (d) => out += d);
    p.on('close', () => resolve(out));
  });
}

const parse = (out) => {
  const m = new Map();
  for (const line of out.split('\n')) {
    const x = line.match(/^\s*(PASS|FAIL)\s{2}(.*?)(?:\s{2}— (.*))?$/);
    if (x) m.set(x[2].trim(), { v: x[1], detail: x[3] || '' });
  }
  return m;
};

// ── expectations ─────────────────────────────────────────────────────────────
const N = {
  unrelFix: 'fixture: the unrelated user has NO relationship with the victim',
  unrel: 'an UNRELATED user is refused (42501)',
  unrelPlan: "…and the victim's active plan is untouched",
  pendFix: 'fixture: the PENDING-coach case — relationship is pending',
  pend: 'a PENDING coach is refused (42501) — an invite is not consent',
  cancFix: 'fixture: the CANCELLED-coach case — relationship is cancelled',
  canc: 'a CANCELLED coach is refused (42501)',
  cancPlan: "…and the victim's active plan is still untouched",
};
const ALL = Object.values(N);
const SCENARIOS = [
  { fault: 'none',            pass: ALL, fail: [] },
  { fault: 'drop-cancel',     pass: [N.unrelFix, N.unrel, N.unrelPlan, N.pendFix, N.pend],
                              fail: [N.cancFix, N.canc, N.cancPlan] },
  { fault: 'drop-pending',    pass: [N.unrelFix, N.unrel, N.unrelPlan],
                              fail: [N.pendFix, N.pend, N.cancFix, N.canc, N.cancPlan] },
  { fault: 'stale-active-cb', pass: [],
                              fail: [N.unrelFix, N.unrel, N.unrelPlan] },
];

let bad = 0;
const tree = makeTree();
try {
  for (const sc of SCENARIOS) {
    const { server, port } = await startMock(sc.fault);
    const r = parse(await runD08(tree, port));
    server.close();
    console.log(`\n── fault: ${sc.fault}`);
    for (const n of ALL) {
      const got = r.get(n);
      const want = sc.pass.includes(n) ? 'PASS' : sc.fail.includes(n) ? 'FAIL' : null;
      if (!want) continue;
      const ok = got?.v === want;
      if (!ok) bad++;
      console.log(`  ${ok ? 'ok  ' : 'BAD '} ${want} expected, ${got ? got.v : 'MISSING'} seen — ${n}`);
      // A dependent that FAILED must have said why, so a reader can tell "not run" from "ran and failed".
      if (ok && want === 'FAIL' && [N.unrel, N.unrelPlan, N.pend, N.canc, N.cancPlan].includes(n)
          && !/NOT ASSERTABLE/.test(got.detail)) { bad++; console.log(`  BAD  ${n}: failed but not marked NOT ASSERTABLE (${got.detail})`); }
    }
  }
} finally {
  fs.rmSync(tree.dir, { recursive: true, force: true });
}
console.log(bad ? `\nd08 fixture regression: ${bad} expectation(s) NOT met` : '\nd08 fixture regression: every expectation met');
process.exit(bad ? 1 : 0);
