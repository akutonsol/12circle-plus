// NOT REGISTERED IN run.mjs — deliberately. See V5 §71.
//
// Reproducible evidence for the DETECTION claim in D12·Q5 Option A. Option A
// keeps "the external issuance log as a detection mechanism"; §68 proved
// prevention is unavailable. This measures what that log actually detects,
// against four attack shapes, before anything is built on it.
//
// No credentials, no network, no infrastructure. Ed25519 generated per run.
//
// Run:  node supabase/tests/security/d12-detection-lab.mjs
// D12-Q5 Option A — DOES THE ISSUANCE LOG ACTUALLY DETECT?
//
// Option A accepts the external-signing design for what it provides and keeps
// "the external issuance log as a detection mechanism". §68 proved prevention is
// unavailable. Nothing has tested the DETECTION claim, so it is tested here
// before anything is built on it.
//
// Project B's issuance log is outside the adversary's reach: it records every
// signature B issues. Trust reconciles recorded rows against that log.
// Disposable, in-process, no network, no credentials.
import { generateKeyPairSync, sign as edSign, verify as edVerify, randomUUID } from 'node:crypto';

const { publicKey, privateKey } = generateKeyPairSync('ed25519');
const KEY_ID = 'k-lab';
const issuanceLog = [];                   // lives in project B. Adversary cannot edit.
const audit = [], observability = [];     // live in project A. Adversary CAN write both.

const sign = (p) => edSign(null, Buffer.from(JSON.stringify(p)), privateKey).toString('base64url');
const verify = (p, s) => { try { return edVerify(null, Buffer.from(JSON.stringify(p)), publicKey, Buffer.from(s,'base64url')); } catch { return false; } };

// The signer. Mints the id itself (design D2+), logs every issuance.
function signerIssue(requestedBy) {
  const payload = { correlation_id: randomUUID(), key_id: KEY_ID };
  const signature = sign(payload);
  issuanceLog.push({ at: Date.now(), correlation_id: payload.correlation_id, requestedBy });
  return { ...payload, signature };
}
const write = (pop, row) => (pop === 'audit' ? audit : observability).push(row);

// ── legitimate traffic ─────────────────────────────────────────────────────
for (let i = 0; i < 200; i++) {
  const t = signerIssue('app');
  write('audit',         { subject: `user-${i}`, op: 'read_assessment', ...t });
  write('observability', { subject: `user-${i}`, op: 'read_assessment', ...t });
}
const baselineIssuance = issuanceLog.length;

// ── the four attack shapes ─────────────────────────────────────────────────
const attacks = {};

// A1 — unsigned fabrication: no signature at all.
{
  const id = randomUUID();
  write('audit',         { subject: 'victim-X', op: 'forged', correlation_id: id, key_id: KEY_ID, signature: 'AAAA' });
  write('observability', { subject: 'victim-Y', op: 'forged', correlation_id: id, key_id: KEY_ID, signature: 'AAAA' });
  attacks.A1 = { label: 'unsigned / invalid signature', ids: [id] };
}
// A2 — reuse ONE issued triple across inconsistent subjects (the §68 C-6 attack).
{
  const t = signerIssue('adversary');
  write('audit',         { subject: 'victim-X', op: 'forged', ...t });
  write('observability', { subject: 'victim-Y', op: 'forged', ...t });
  attacks.A2 = { label: 'one valid triple, two INCONSISTENT subjects', ids: [t.correlation_id] };
}
// A3 — the patient adversary: a FRESH triple per fabricated correlation, and it
// fabricates a self-consistent pair, exactly as the app would have written it.
{
  const ids = [];
  for (let i = 0; i < 3; i++) {
    const t = signerIssue('adversary');
    write('audit',         { subject: `victim-${i}`, op: 'read_assessment', ...t });
    write('observability', { subject: `victim-${i}`, op: 'read_assessment', ...t });
    ids.push(t.correlation_id);
  }
  attacks.A3 = { label: 'fresh triple per fabrication, self-consistent rows', ids };
}
// A4 — mass fabrication.
{
  const ids = [];
  for (let i = 0; i < 500; i++) {
    const t = signerIssue('adversary');
    write('audit',         { subject: `bulk-${i}`, op: 'read_assessment', ...t });
    write('observability', { subject: `bulk-${i}`, op: 'read_assessment', ...t });
    ids.push(t.correlation_id);
  }
  attacks.A4 = { label: 'mass fabrication (500 correlations)', ids };
}

// ── the detection controls Trust can actually run ──────────────────────────
const issued = new Set(issuanceLog.map(e => e.correlation_id));

// DET-1  signature verification (this is PREVENTION, not detection)
const detBadSig = new Set([...audit, ...observability]
  .filter(r => !verify({ correlation_id: r.correlation_id, key_id: r.key_id }, r.signature))
  .map(r => r.correlation_id));

// DET-2  a row whose id was never issued by B
const detNeverIssued = new Set([...audit, ...observability]
  .filter(r => !issued.has(r.correlation_id)).map(r => r.correlation_id));

// DET-3  one id binding INCONSISTENT subjects across populations
const detInconsistent = new Set();
for (const a of audit) for (const o of observability)
  if (a.correlation_id === o.correlation_id && a.subject !== o.subject) detInconsistent.add(a.correlation_id);

// DET-4  volume anomaly against the legitimate baseline
const volumeSpike = issuanceLog.length > baselineIssuance * 1.5;

const detects = (ids) => ids.some(id => detBadSig.has(id) || detNeverIssued.has(id) || detInconsistent.has(id));

console.log('\nD12-Q5 OPTION A — WHAT THE ISSUANCE LOG ACTUALLY DETECTS\n');
console.log(`  baseline: ${baselineIssuance} legitimate issuances; total now ${issuanceLog.length}\n`);
for (const [k, a] of Object.entries(attacks)) {
  const d = detects(a.ids);
  console.log(`  ${d ? 'DETECTED    ' : 'NOT DETECTED'}  ${k}  ${a.label}`);
  if (!d) console.log(`                  every row verifies, every id was genuinely issued,`);
  if (!d) console.log(`                  and audit/observability agree with each other.`);
}
console.log(`\n  DET-4 volume anomaly vs baseline: ${volumeSpike ? 'FLAGGED' : 'not flagged'} (${issuanceLog.length} vs ${baselineIssuance})`);
console.log(`  -> A4 is caught ONLY by volume, i.e. by the adversary being greedy, not by the mechanism.`);
console.log(`  -> A3 is the honest limit: a patient adversary at normal rates is INVISIBLE to reconciliation.\n`);
