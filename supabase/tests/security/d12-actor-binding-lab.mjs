// NOT REGISTERED IN run.mjs — deliberately. See V5 §68.
//
// Reproducible evidence that signer design D3 (actor-binding) does not survive a
// service_role adversary. Demonstrates that an adversary holding ONLY the
// service_role key — no password, no user session — obtains a genuine,
// JWKS-verifiable access token for a subject it does not own, by two
// independent paths.
//
// REQUIRES A DISPOSABLE LOCAL STACK. It must never be pointed at QA or
// production: it creates users and overwrites a password.
//
//   supabase init && supabase start
//   set -a; eval "$(supabase status -o env | grep -E '^(API_URL|ANON_KEY|SERVICE_ROLE_KEY)=')"; set +a
//   node supabase/tests/security/d12-actor-binding-lab.mjs
//   supabase stop --no-backup
const URL_ = process.env.API_URL, SVC = process.env.SERVICE_ROLE_KEY, ANON = process.env.ANON_KEY;
const H = { apikey: SVC, Authorization: `Bearer ${SVC}`, 'Content-Type': 'application/json' };
const AH = { apikey: ANON, 'Content-Type': 'application/json' };
const claims = (t) => t ? JSON.parse(Buffer.from(t.split('.')[1], 'base64url')) : {};

const email = `victim-${Date.now()}@lab.invalid`;
const origPw = crypto.randomUUID() + '!Aa1';
const victim = await (await fetch(`${URL_}/auth/v1/admin/users`, {
  method: 'POST', headers: H,
  body: JSON.stringify({ email, password: origPw, email_confirm: true }) })).json();
console.log(`\nfixture: victim sub=${victim.id}\n`);

console.log('── PATH 1: magiclink generate_link -> verify ───────────────────────────');
const link = await (await fetch(`${URL_}/auth/v1/admin/generate_link`, {
  method: 'POST', headers: H, body: JSON.stringify({ type: 'magiclink', email }) })).json();
console.log(`  generate_link: hashed_token issued = ${!!link.hashed_token}`);
for (const [label, init] of [
  ['POST verify {token, type, email}', { method: 'POST', headers: AH, body: JSON.stringify({ type: 'magiclink', token: link.hashed_token, email }) }],
  ['POST verify {token_hash, type}',   { method: 'POST', headers: AH, body: JSON.stringify({ type: 'magiclink', token_hash: link.hashed_token }) }],
]) {
  const r = await fetch(`${URL_}/auth/v1/verify`, init);
  const b = await r.json().catch(() => ({}));
  console.log(`  ${label} -> HTTP ${r.status}  ${b.access_token ? 'ACCESS TOKEN ISSUED' : JSON.stringify(b).slice(0,120)}`);
  if (b.access_token) console.log(`      sub=${claims(b.access_token).sub} matches victim: ${claims(b.access_token).sub === victim.id}`);
}

console.log('\n── PATH 2: admin password overwrite -> ordinary sign-in ────────────────');
const newPw = 'Adversary-Chosen-' + crypto.randomUUID().slice(0,8) + '!Aa1';
const upd = await fetch(`${URL_}/auth/v1/admin/users/${victim.id}`, {
  method: 'PUT', headers: H, body: JSON.stringify({ password: newPw }) });
console.log(`  PUT /admin/users/{id} {password} -> HTTP ${upd.status}`);
const tok = await fetch(`${URL_}/auth/v1/token?grant_type=password`, {
  method: 'POST', headers: AH, body: JSON.stringify({ email, password: newPw }) });
const tb = await tok.json().catch(() => ({}));
const c = claims(tb.access_token);
console.log(`  POST /token?grant_type=password -> HTTP ${tok.status}`);
console.log(`  access_token issued: ${!!tb.access_token}`);
console.log(`  sub=${c.sub}  matches victim: ${c.sub === victim.id}  role=${c.role}  iss=${c.iss}`);
console.log(`\n  VERDICT PATH 2: an adversary holding ONLY service_role obtained a genuine,`);
console.log(`  JWKS-verifiable user access token for a subject it does not own: ${c.sub === victim.id}`);
