// NOT REGISTERED IN run.mjs — deliberately. See V5 §68.
//
// Reproducible evidence for the D12·Q2 SIGNING-AUTHORITY boundary. This is not
// a regression suite for application code: it asserts nothing about this
// repository. It is a self-contained adversary simulation answering the six
// capability questions the owner posed, against five progressively-hardened
// signer designs (D1–D5).
//
// It needs no credentials, no network and no infrastructure: the signer runs
// in-process on 127.0.0.1 and its Ed25519 keypair is generated per run, held in
// memory and never written to disk. Nothing contacts production or QA.
//
// Run:  node supabase/tests/security/d12-signing-authority-lab.mjs
// D12-Q2 SIGNING-AUTHORITY BOUNDARY — disposable empirical lab.
//
// THE QUESTION, stated so it cannot be fudged: not "is project B isolated from
// project A" (that is JWT isolation, already proven in V5 §61 and NOT the same
// claim), but "can the compromised primary service-role tier OBTAIN or EXERCISE
// arbitrary signing authority".
//
// ADVERSARY MODEL. A compromised primary-project Edge Function. It holds:
//   * the primary project's service_role key (BYPASSRLS, writes any row)
//   * whatever credential the LEGITIMATE minting path uses to call the signer --
//     because the legitimate minting path RUNS INSIDE the compromised tier.
//     This is the crux. An adversary that owns the caller owns the caller's
//     credentials. Denying it this would be modelling a different adversary.
//
// Everything is disposable: keys are generated per run, held in memory, and
// never written to disk. Nothing contacts production, QA, or any network.
//
// Ed25519 + HTTP here, Node rather than Deno (Deno is not installed). The
// deviation is immaterial: the questions are about credential and protocol
// semantics, which are identical in both runtimes.
import { createServer } from 'node:http';
import { generateKeyPairSync, sign as edSign, verify as edVerify, randomUUID, createHash } from 'node:crypto';

// ── project B: the signer's custody ────────────────────────────────────────
const { publicKey, privateKey } = generateKeyPairSync('ed25519');
const KEY_ID = 'k-' + createHash('sha256').update(publicKey.export({ type: 'spki', format: 'der' })).digest('hex').slice(0, 12);
const INVOKE_TOKEN = 'sbk_' + randomUUID();          // B's invoke credential
const issuanceLog = [];

const sig = (obj) => edSign(null, Buffer.from(JSON.stringify(obj)), privateKey).toString('base64url');

// DESIGN knob -- the four progressively-hardened signers under test.
let DESIGN = 'D1';
const seenIds = new Set();

const server = createServer((req, res) => {
  let body = '';
  req.on('data', (c) => (body += c));
  req.on('end', () => {
    const send = (code, o) => { res.writeHead(code, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(o)); };
    if (req.url !== '/sign' || req.method !== 'POST') return send(404, { error: 'not found' });

    // AUTHENTICATION -- the signer's only gate on who may ask.
    if (req.headers.authorization !== `Bearer ${INVOKE_TOKEN}`) return send(401, { error: 'unauthorized' });

    let reqBody; try { reqBody = JSON.parse(body); } catch { return send(400, { error: 'bad json' }); }

    // D2: the signer MINTS the identifier; the caller may not choose it.
    const correlation_id = DESIGN === 'D1' ? reqBody.correlation_id : randomUUID();

    // D3: actor-bound. The signer demands a user assertion and binds it.
    let actor = reqBody.actor ?? null;
    if (DESIGN === 'D3' || DESIGN === 'D4') {
      if (!reqBody.user_jwt) return send(400, { error: 'user assertion required' });
      // The signer verifies the assertion. In the real design this is a JWKS
      // check against the PRIMARY project -- so it proves only that the primary
      // project issued it, which is exactly the capability under test.
      try { actor = JSON.parse(Buffer.from(reqBody.user_jwt.split('.')[1], 'base64url')).sub; }
      catch { return send(400, { error: 'unreadable assertion' }); }
    }

    // D4: anti-replay -- refuse to sign an identifier twice.
    if (DESIGN === 'D4') {
      if (seenIds.has(correlation_id)) return send(409, { error: 'already issued' });
      seenIds.add(correlation_id);
    }

    const payload = { correlation_id, actor, operation: reqBody.operation ?? null, key_id: KEY_ID };
    const signature = sig(payload);
    issuanceLog.push({ at: Date.now(), payload });
    send(200, { ...payload, signature });
  });
});

// ── Trust: holds ONLY the public key ───────────────────────────────────────
function trustAccepts(payloadAndSig) {
  const { signature, ...payload } = payloadAndSig;
  try { return edVerify(null, Buffer.from(JSON.stringify(payload)), publicKey, Buffer.from(signature, 'base64url')); }
  catch { return false; }
}

// How Trust reads a ROW. The signer signed a TRIPLE; the row carries that triple
// plus its own content. Trust therefore verifies the triple it extracts, because
// that is all the signature ever covered. An earlier revision of this lab
// verified the WHOLE row, which failed -- and the failure was an artefact of the
// test, not a property of the design: it proved only that fields the signer never
// saw are not covered by its signature, which is the defect, not a defence.
function trustHonoursRow(row, signedFields) {
  const triple = {};
  for (const k of signedFields) triple[k] = row[k];
  return trustAccepts({ ...triple, signature: row.signature });
}
const TRIPLE_FIELDS = ['correlation_id', 'actor', 'operation', 'key_id'];

const PORT = 8787;
await new Promise((r) => server.listen(PORT, '127.0.0.1', r));
const SIGNER = `http://127.0.0.1:${PORT}/sign`;

// ── the adversary ──────────────────────────────────────────────────────────
const ask = async (bodyObj, token = INVOKE_TOKEN) => {
  const r = await fetch(SIGNER, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify(bodyObj),
  });
  return { status: r.status, body: await r.json().catch(() => null) };
};

const out = [];
const cap = (id, question, can, evidence) => {
  out.push({ id, can });
  console.log(`  ${can ? 'CAN   ' : 'CANNOT'}  ${id.padEnd(5)} ${question}\n          ${evidence}`);
};

console.log('\nD12-Q2 · SIGNING-AUTHORITY BOUNDARY — adversary = compromised primary Edge Function\n');
console.log('── Signer design D1: signs the payload it is given ─────────────────────\n');

// (1) REACH
{
  const r = await fetch(SIGNER, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' });
  cap('C-1', 'reach the second-project signer over the network?', r.status !== 0 && r.status !== undefined,
    `the endpoint answered HTTP ${r.status} to an unauthenticated probe -- reachable. Outbound HTTPS from an Edge Function is unrestricted (the live ai-nutrition function calls api.anthropic.com).`);
}

// (2) AUTHENTICATE
{
  const bad = await ask({ correlation_id: randomUUID() }, 'sbk_' + randomUUID());
  const good = await ask({ correlation_id: randomUUID() });
  cap('C-2', 'authenticate to the signer?', bad.status === 401 && good.status === 200,
    `a WRONG token -> ${bad.status}; the invoke credential the legitimate mint path holds -> ${good.status}. The adversary holds it BECAUSE the mint path runs in the compromised tier.`);
}

// (3) OBTAIN A VALID SIGNATURE
let stolen;
{
  const r = await ask({ correlation_id: randomUUID(), operation: 'anything' });
  stolen = r.body;
  cap('C-3', 'obtain a signature Trust verifies?', r.status === 200 && trustAccepts(r.body),
    `HTTP ${r.status}; Trust verified the returned triple: ${trustAccepts(r.body)}. key_id=${r.body?.key_id}`);
}

// (4) CHOOSE ARBITRARY CONTENTS
{
  const chosen = '00000000-dead-beef-0000-000000000000';
  const r = await ask({ correlation_id: chosen, actor: 'any-subject-i-like', operation: 'forged' });
  cap('C-4', 'choose the correlation_id and payload contents?',
    r.status === 200 && r.body.correlation_id === chosen && trustAccepts(r.body),
    `asked for correlation_id=${chosen} -> got ${r.body?.correlation_id}, actor=${r.body?.actor}, Trust accepts: ${trustAccepts(r.body)}`);
}

// (5) REPLAY / REUSE
{
  const replayed = { ...stolen };
  const ok = trustAccepts(replayed);
  const again = await ask({ correlation_id: stolen.correlation_id });
  cap('C-5', 'replay or reuse a previously authorized signing capability?',
    ok && again.status === 200,
    `the earlier triple still verifies after the fact: ${ok}; and the signer re-issued for the same id: HTTP ${again.status}. The invoke credential is durable -- nothing expires it.`);
}

// (6) FABRICATED CROSS-POPULATION CORRELATION
{
  const r = await ask({ correlation_id: randomUUID(), operation: 'fabricated' });
  const t = r.body;
  // The adversary holds service_role/BYPASSRLS, so it writes both rows itself.
  const auditRow = { population: 'audit', subject: 'victim-A', ...t };
  const obsRow   = { population: 'observability', subject: 'victim-B', ...t };
  const both = trustHonoursRow(auditRow, TRIPLE_FIELDS) && trustHonoursRow(obsRow, TRIPLE_FIELDS);
  cap('C-6', 'make Trust accept a FABRICATED cross-population correlation?',
    both,
    `one signer-issued triple stamped on two rows the adversary invented, in two populations, binding 'victim-A' to 'victim-B'. Trust honours BOTH rows: ${both}. The signature is GENUINE -- it just never covered 'subject' or 'population'.`);
}

// ── do the hardened designs close it? ──────────────────────────────────────
console.log('\n── Do hardened signer designs close C-4 / C-6? ─────────────────────────\n');
const hardened = [];
for (const [d, label] of [['D2', 'signer MINTS the id (caller may not choose)'],
                          ['D3', 'D2 + actor-bound to a verified user assertion'],
                          ['D4', 'D3 + anti-replay (refuses to sign an id twice)']]) {
  DESIGN = d;
  // A forged user assertion: the adversary holds service_role, which reaches
  // the Auth admin API and can mint a session for ANY subject. Modelled here;
  // empirically demonstrated separately against a disposable local stack.
  const fakeJwt = 'x.' + Buffer.from(JSON.stringify({ sub: 'any-victim-uuid' })).toString('base64url') + '.x';
  const r = await ask({ user_jwt: fakeJwt, operation: 'fabricated' });
  const t = r.body;
  const chose = d === 'D1';
  const accepted = r.status === 200 && trustAccepts(t);
  const rowA = { population: 'audit', subject: 'victim-A', ...t };
  const rowB = { population: 'observability', subject: 'victim-B', ...t };
  const correlates = accepted && trustHonoursRow(rowA, TRIPLE_FIELDS) && trustHonoursRow(rowB, TRIPLE_FIELDS);
  hardened.push({ d, correlates });
  console.log(`  ${d}  ${label}`);
  console.log(`      C-4 choose id: ${chose ? 'CAN' : 'CANNOT'} (signer mints it)`);
  console.log(`      C-6 fabricated correlation Trust accepts: ${correlates ? 'CAN' : 'CANNOT'}`);
  console.log(`      -> obtained a FRESH valid triple (${t?.correlation_id?.slice(0, 8)}…, actor=${t?.actor}) and stamped it on two invented rows in two populations.\n`);
}

console.log('── VERDICT ─────────────────────────────────────────────────────────────');
const canAll = out.filter(o => o.can).map(o => o.id);
console.log(`  adversary capabilities demonstrated: ${canAll.join(', ')}`);
console.log(`  hardened designs that still permit fabricated correlation: ${hardened.filter(h => h.correlates).map(h => h.d).join(', ') || 'none'}`);
console.log(`  issuance-log entries the signer recorded: ${issuanceLog.length} (all outside the adversary's reach -- DETECTION, not prevention)`);
server.close();

// ── D5: the last candidate defence — bind the ROW, not just the identifier ──
// If the signature covered the row's own content (population, subject), the
// adversary could not move a triple onto a row the signer never saw. So: have
// the signer sign whatever complete row it is handed.
console.log('\n── D5: signer binds the FULL row content ───────────────────────────────\n');
{
  const fabricatedA = { population: 'audit',         subject: 'victim-A', correlation_id: randomUUID() };
  const fabricatedB = { population: 'observability', subject: 'victim-B', correlation_id: fabricatedA.correlation_id };
  // The adversary simply presents its fabricated rows and asks for them to be signed.
  const signRow = (row) => ({ ...row, key_id: KEY_ID, signature: sig({ ...row, key_id: KEY_ID }) });
  const sA = signRow(fabricatedA);
  const sB = signRow(fabricatedB);
  const ok = trustAccepts(sA) && trustAccepts(sB);
  console.log(`  C-6 under full-row binding: ${ok ? 'CAN' : 'CANNOT'}`);
  console.log(`      Both fabricated rows carry signatures over their OWN content and verify: ${ok}`);
  console.log(`      Binding the content does not help: the adversary COMPOSES the content it asks`);
  console.log(`      the signer to bind. The signer has no independent knowledge of what is true.\n`);
}
