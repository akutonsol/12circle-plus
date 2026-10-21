// NOT REGISTERED IN run.mjs -- deliberately. See V5 §61.
//
// This is the reproducible evidence behind the D12-Q2 signer selection, not a
// regression suite for application code. It asserts a PLATFORM property (a
// foreign-signed JWT is rejected at signature verification), and the boundary it
// guards -- a second Supabase project acting as signer -- IS NOT BUILT. D12-Q5
// must be answered first (§61.5). Register it here only once project B exists;
// at that point this suite becomes the thing that tells us if the platform ever
// stops enforcing the isolation D12's custody argument rests on.
//
// Run:  QA_URL=... QA_ANON=... QA_SERVICE=... node supabase/tests/security/xproj-custody-boundary.mjs
// Requires Node >= 18 for global fetch.
//
// D12-Q2 architectural verification.
//
// CLAIM UNDER TEST (V-1): a second Supabase project is a real custody boundary,
// i.e. project A's `service_role` credential confers NOTHING in project B.
//
// Why this probe is equivalent to a two-project test: QA's service_role key is a
// legacy HS256 JWT whose claims are {iss, ref, role, iat, exp}. Project B
// authenticates it by verifying the HMAC against B's OWN jwt_secret. A token
// minted by project A is therefore, from B's side, a token with well-formed
// claims and a signature produced by a key B does not hold. That is exactly what
// this probe presents. A local two-stack test would have been WEAKER, not
// stronger: the Supabase CLI issues both stacks keys signed with the same
// well-known demo secret, so A's key would be accepted by B and the test would
// falsely confirm isolation.
//
// Reads only. No mutation. Never prints or derives any real credential.
import { createHmac, randomBytes } from 'node:crypto';

const URL_ = process.env.QA_URL;
const ANON = process.env.QA_ANON;
const SERVICE = process.env.QA_SERVICE;
if (!URL_ || !ANON || !SERVICE) { console.error('env missing'); process.exit(2); }

// Project ref is taken from the HOST, not from any key. It is not a secret --
// it is the public subdomain of every request this repo already makes.
const REF = new URL(URL_).host.split('.')[0];

const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
function mint(claims, secret) {
  const h = b64({ alg: 'HS256', typ: 'JWT' });
  const p = b64(claims);
  const s = createHmac('sha256', secret).update(`${h}.${p}`).digest('base64url');
  return `${h}.${p}.${s}`;
}

// The "other project's" secret. Random, generated here, never persisted. This
// stands in for project A's jwt_secret as seen from project B.
const FOREIGN_SECRET = randomBytes(64).toString('hex');

const now = Math.floor(Date.now() / 1000);
const claims = (role) => ({ iss: 'supabase', ref: REF, role, iat: now, exp: now + 3600 });

const results = [];
function record(id, desc, pass, detail) {
  results.push({ id, pass });
  console.log(`  ${pass ? 'PASS' : 'FAIL'}  ${id.padEnd(6)} ${desc}\n         -> ${detail}`);
}

// A table that exists and that service_role can read. Read-only, limit 1.
const PROBE = '/rest/v1/event_registrations?select=id&limit=1';

async function hit(token, apikey) {
  const r = await fetch(URL_ + PROBE, {
    headers: { apikey, Authorization: `Bearer ${token}` },
  });
  let body = '';
  try { body = (await r.text()).slice(0, 160); } catch {}
  return { status: r.status, body };
}

console.log('\nD12-Q2 / V-1  CROSS-PROJECT CREDENTIAL ISOLATION\n');

// --- ANTI-VACUITY CONTROL ------------------------------------------------
// If the endpoint refuses everything, every negative below is meaningless.
{
  const r = await hit(SERVICE, SERVICE);
  record('XP-0', 'CONTROL: the project\'s OWN service_role key is accepted here',
    r.status === 200,
    `HTTP ${r.status} (a non-200 would make every negative below vacuous)`);
}

// --- V-1 core ------------------------------------------------------------
{
  const t = mint(claims('service_role'), FOREIGN_SECRET);
  const r = await hit(t, t);
  record('XP-1', 'foreign-signed service_role token (correct ref+claims) is REJECTED',
    r.status === 401, `HTTP ${r.status} ${r.body}`);
}
{
  const t = mint(claims('anon'), FOREIGN_SECRET);
  const r = await hit(t, t);
  record('XP-2', 'foreign-signed anon token is REJECTED',
    r.status === 401, `HTTP ${r.status} ${r.body}`);
}
{
  // The strongest claim an attacker could assert.
  const t = mint(claims('supabase_admin'), FOREIGN_SECRET);
  const r = await hit(t, t);
  record('XP-3', 'foreign-signed supabase_admin token is REJECTED',
    r.status === 401, `HTTP ${r.status} ${r.body}`);
}
{
  // Signature stripped / alg=none style downgrade.
  const h = b64({ alg: 'none', typ: 'JWT' });
  const p = b64(claims('service_role'));
  const t = `${h}.${p}.`;
  const r = await hit(t, t);
  record('XP-4', 'alg=none service_role token is REJECTED',
    r.status === 401, `HTTP ${r.status} ${r.body}`);
}
{
  // Real anon key as apikey, foreign service_role as Authorization -- the
  // mix a confused-deputy attempt would produce.
  const t = mint(claims('service_role'), FOREIGN_SECRET);
  const r = await hit(t, ANON);
  record('XP-5', 'real anon apikey + foreign service_role bearer does NOT elevate',
    r.status === 401, `HTTP ${r.status} ${r.body}`);
}

const failed = results.filter((r) => !r.pass);
console.log(`\n  ${results.length - failed.length}/${results.length} assertions passed`);
if (failed.length) console.log(`  FAILED: ${failed.map((f) => f.id).join(', ')}`);
process.exit(failed.length ? 1 : 0);
