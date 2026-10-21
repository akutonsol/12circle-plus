// Phase 3A-10 — the chat-media storage contract, live.  (DEC-3A-10, migration 130)
//
// Pins the Option C contract exactly as the storage.objects policies express it:
//
//     chat-media/messages/<conversation_id>/<uploader_uid>/<file>
//
//   read    any participant of the conversation
//   upload  a participant, into their OWN uid segment
//   delete  the uploader only
//   update  NO policy — chat media is immutable
//   and a malformed path is DENIED, never an error (no uuid cast of a segment)
//
// Runs over the real Storage REST surface with the anon key and the same JWTs a
// phone would use, because a static reading of pg_policies cannot tell you how
// the storage-api, the policies and the helper function compose.
//
// SELF-CONTAINED ON PURPOSE. lib.mjs refuses to load without QA_SERVICE, and this
// suite needs no service role: every fixture it creates is created and removed
// as the fixture identities themselves, except the conversation row, which the
// schema gives users no DELETE policy for. That one row is removed by service
// role when QA_SERVICE is present (CI), and otherwise its id is printed for the
// operator to remove and verify — never left silently.
//
//   export QA_URL=https://<ref>.supabase.co QA_ANON=...   [QA_SERVICE=...]
//   node supabase/tests/security/d07-chat-media-storage.mjs
//
// Also registered in run.mjs. QA only: it refuses any target it cannot
// positively identify as the 12 Circle QA project.

const URL_ = process.env.QA_URL;
const ANON = process.env.QA_ANON;
const SERVICE = process.env.QA_SERVICE || null;
// The 12 Circle QA project — the only remote project this suite may touch.
// Matches supabase/config.toml's project_id and dart_defines/qa.json.
//
// Refusal is by ALLOWLIST, not by blocklist. This suite used to hold its own
// copy of the production ref and refuse that one string, which is a weaker
// claim in two ways: "is not production" is not "is QA", so a third project
// sailed through; and a second copy of the production ref is a second chance
// to drift — the exact argument apps/mobile/tool/qa_target.dart makes for
// keeping one shared constant, and the reason ENV-5 flagged this file.
const QA_REF = 'eyqtldjqpgpljlqvpowh';
const BUCKET = 'chat-media';

if (!URL_ || !ANON) {
  console.error('QA_URL and QA_ANON must be set (QA_SERVICE is optional for this suite).');
  process.exit(2);
}
if (!URL_.includes(QA_REF)) {
  console.error(`REFUSING TO RUN: "${URL_}" is not the 12 Circle QA project (${QA_REF}).`);
  console.error('This suite writes. A target is QA because its ref says so —');
  console.error('never because a variable or a filename is called "qa".');
  process.exit(2);
}

// Same fixture identities as lib.mjs IDENT — duplicated rather than imported
// for the reason in the header. Keep in step with lib.mjs.
const IDENT = {
  victim:   { email: 'p1-victim@qa.12circle.test',   pw: 'P1-Probe-Victim-2026!' },
  attacker: { email: 'p1-attacker@qa.12circle.test', pw: 'P1-Probe-Attacker-2026!' },
  coach:    { email: 'p1-coach@qa.12circle.test',    pw: 'P1-Probe-Coach-2026!' },
};

// Reporting: reuse lib.mjs's shared `results` when it is loadable so run.mjs
// counts this suite like the others; fall back to local equivalents otherwise.
let lib = null;
if (SERVICE) { try { lib = await import('./lib.mjs'); } catch { lib = null; } }
const localResults = [];
const check = lib ? lib.check : (name, pass, detail) => {
  localResults.push({ name, pass, detail });
  console.log(`  ${pass ? 'PASS' : 'FAIL'}  ${name}${detail ? `  — ${detail}` : ''}`);
  return pass;
};
const section = lib ? lib.section : (t) => console.log(`\n── ${t} ${'─'.repeat(Math.max(2, 68 - t.length))}`);
const summary = lib ? lib.summary : (label) => {
  const f = localResults.filter(r => !r.pass);
  console.log(`\n${'='.repeat(74)}\n${label}: ${localResults.length - f.length}/${localResults.length} passed`);
  if (f.length) { console.log('FAILURES:'); f.forEach(r => console.log(`  x ${r.name} — ${r.detail || ''}`)); }
  return f.length;
};

async function parse(res) {
  const t = await res.text();
  let body; try { body = t ? JSON.parse(t) : null; } catch { body = t; }
  return { status: res.status, body, text: t, headers: res.headers };
}

// Which layer produced a denial. storage-api relays Postgres' RLS message as
// JSON; Cloudflare's WAF answers with an HTML 403 before the request reaches
// storage-api at all. The two are NOT the same evidence and are never
// labelled as if they were.
function denialLayer(r) {
  if (/row-level security|AccessDenied|NoSuchKey|not_found/i.test(r.text || '')) return 'Storage-policy denial (RLS message present)';
  if (r.status === 403 && /<!DOCTYPE html|<html/i.test(r.text || '')) return 'WAF-layer denial; request did not reach Storage policy';
  return `denied by an unidentified layer (${r.status})`;
}
async function signIn(key) {
  const r = await fetch(`${URL_}/auth/v1/token?grant_type=password`, {
    method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: IDENT[key].email, password: IDENT[key].pw }),
  });
  const { status, body } = await parse(r);
  if (status >= 300) throw new Error(`signIn ${IDENT[key].email}: ${status} ${JSON.stringify(body)}`);
  return { jwt: body.access_token, uid: body.user.id };
}
const H = (jwt, extra = {}) => ({ apikey: ANON, Authorization: `Bearer ${jwt}`, ...extra });

// ── storage REST, exactly the calls supabase_flutter makes ──────────────────
const upload = (jwt, path, bodyText, upsert = false) =>
  fetch(`${URL_}/storage/v1/object/${BUCKET}/${path}`, {
    method: 'POST',
    headers: H(jwt, { 'Content-Type': 'text/plain', 'x-upsert': upsert ? 'true' : 'false' }),
    body: bodyText,
  }).then(parse);
const download = (jwt, path) =>
  fetch(`${URL_}/storage/v1/object/authenticated/${BUCKET}/${path}`, { headers: H(jwt) }).then(parse);
const sign = (jwt, path) =>
  fetch(`${URL_}/storage/v1/object/sign/${BUCKET}/${path}`, {
    method: 'POST', headers: H(jwt, { 'Content-Type': 'application/json' }),
    body: JSON.stringify({ expiresIn: 60 }),
  }).then(parse);
const remove = (jwt, path) =>
  fetch(`${URL_}/storage/v1/object/${BUCKET}/${path}`, { method: 'DELETE', headers: H(jwt) }).then(parse);
const list = (jwt, prefix) =>
  fetch(`${URL_}/storage/v1/object/list/${BUCKET}`, {
    method: 'POST', headers: H(jwt, { 'Content-Type': 'application/json' }),
    body: JSON.stringify({ prefix, limit: 100 }),
  }).then(parse);

// A denial is a 4xx. A 5xx, or any body mentioning a uuid-cast failure, is the
// exact defect migration 130 was rewritten to remove — it fails on its own.
const denied = (r) => r.status >= 400 && r.status < 500;
const uuidCastLeak = (r) => /invalid input syntax for type uuid|22P02/i.test(r.text || '');
const ok = (r) => r.status >= 200 && r.status < 300;

// Existence is proved by LIST, which is answered from the database, and never by
// a download: `/object/authenticated/` sits behind a CDN that can keep serving a
// deleted object for a short while, so a 200 there proves nothing about the row.
async function exists(jwt, path) {
  const i = path.lastIndexOf('/');
  const prefix = path.slice(0, i), file = path.slice(i + 1);
  const l = await list(jwt, prefix);
  return ok(l) && Array.isArray(l.body) && l.body.some(o => o.name === file);
}

// ═══ fixtures ══════════════════════════════════════════════════════════════
const A = await signIn('coach');     // uploader / participant_1
const B = await signIn('victim');    // recipient / participant_2
const C = await signIn('attacker');  // non-participant

// One conversation between A and B, created as A through PostgREST, exactly as
// MessagingService.getOrCreateConversationWith() does.
const convRes = await fetch(`${URL_}/rest/v1/conversations`, {
  method: 'POST',
  headers: H(A.jwt, { 'Content-Type': 'application/json', Prefer: 'return=representation' }),
  body: JSON.stringify({ participant_1: A.uid, participant_2: B.uid, last_message_at: new Date().toISOString() }),
}).then(parse);
if (!ok(convRes) || !Array.isArray(convRes.body) || !convRes.body[0]?.id) {
  console.error(`SUITE ERROR: could not create the fixture conversation: ${convRes.status} ${convRes.text}`);
  process.exit(1);
}
const CONV = convRes.body[0].id;
const stamp = Date.now();
const fileA = `probe-${stamp}.txt`;
const pathA = `messages/${CONV}/${A.uid}/${fileA}`;           // canonical, A's own segment
const created = new Set();                                       // every object this suite manages to create

console.log(`  fixture conversation ${CONV}  A=${A.uid}  B=${B.uid}  C=${C.uid}`);

try {
  // ═══ 1. upload ═══════════════════════════════════════════════════════════
  section('1. Upload — participant, into own uid segment only');
  {
    const r = await upload(A.jwt, pathA, 'A original');
    if (ok(r)) created.add(pathA);
    check('participant A uploads to messages/<conv>/<A>/<file>', ok(r), `${r.status}`);

    const impersonate = `messages/${CONV}/${A.uid}/impersonated-${stamp}.txt`;
    const r2 = await upload(B.jwt, impersonate, 'B pretending to be A');
    if (ok(r2)) created.add(impersonate);
    check('participant B cannot upload into A\'s uid segment', denied(r2) && !uuidCastLeak(r2), `${r2.status} ${r2.text}`);

    const outsider = `messages/${CONV}/${C.uid}/outsider-${stamp}.txt`;
    const r3 = await upload(C.jwt, outsider, 'C is not a participant');
    if (ok(r3)) created.add(outsider);
    check('non-participant C cannot upload to the conversation, even in own uid segment', denied(r3) && !uuidCastLeak(r3), `${r3.status} ${r3.text}`);

    const legacy = `messages/${A.uid}/legacy-${stamp}.txt`;      // the pre-130 two-segment shape
    const r4 = await upload(A.jwt, legacy, 'old path shape');
    if (ok(r4)) created.add(legacy);
    check('old two-segment path messages/<uid>/<file> is refused', denied(r4) && !uuidCastLeak(r4), `${r4.status} ${r4.text}`);

    const anonR = await fetch(`${URL_}/storage/v1/object/${BUCKET}/${pathA}-anon`, {
      method: 'POST', headers: { apikey: ANON, Authorization: `Bearer ${ANON}`, 'Content-Type': 'text/plain' }, body: 'anon',
    }).then(parse);
    if (ok(anonR)) created.add(`${pathA}-anon`);
    check('anonymous caller cannot upload', denied(anonR), `${anonR.status}`);
  }

  // ═══ 2. read ═════════════════════════════════════════════════════════════
  section('2. Read — any participant, nobody else');
  {
    const rA = await download(A.jwt, pathA);
    check('uploader A reads own object', ok(rA) && rA.text === 'A original', `${rA.status}`);
    const rB = await download(B.jwt, pathA);
    check('recipient B reads A\'s object (read is symmetric)', ok(rB) && rB.text === 'A original', `${rB.status}`);
    const rC = await download(C.jwt, pathA);
    check('non-participant C cannot read it', denied(rC) && !uuidCastLeak(rC), `${rC.status} ${rC.text}`);
    const rAnon = await fetch(`${URL_}/storage/v1/object/authenticated/${BUCKET}/${pathA}`, {
      headers: { apikey: ANON, Authorization: `Bearer ${ANON}` } }).then(parse);
    check('anonymous caller cannot read it', denied(rAnon), `${rAnon.status}`);
    const pub = await fetch(`${URL_}/storage/v1/object/public/${BUCKET}/${pathA}`).then(parse);
    check('the public URL form serves nothing (bucket is private)', denied(pub), `${pub.status}`);

    // The client's real read path is createSignedUrl(); prove it composes.
    const sB = await sign(B.jwt, pathA);
    check('recipient B can create a signed URL (the app\'s read path)', ok(sB) && typeof sB.body?.signedURL === 'string', `${sB.status}`);
    if (ok(sB)) {
      const viaSigned = await fetch(`${URL_}/storage/v1${sB.body.signedURL}`).then(parse);
      check('the signed URL serves the object without a JWT', ok(viaSigned) && viaSigned.text === 'A original', `${viaSigned.status}`);
    }
    const sC = await sign(C.jwt, pathA);
    check('non-participant C cannot create a signed URL', denied(sC) && !uuidCastLeak(sC), `${sC.status} ${sC.text}`);
  }

  // ═══ 3. immutability ═════════════════════════════════════════════════════
  section('3. Immutability — no UPDATE policy, no overwrite');
  {
    const ow = await upload(A.jwt, pathA, 'A overwritten', /* upsert */ true);
    const after = await download(A.jwt, pathA);
    check('uploader A cannot overwrite own object with x-upsert', denied(ow) && !uuidCastLeak(ow), `${ow.status} ${ow.text}`);
    check('object content is unchanged after the overwrite attempt', ok(after) && after.text === 'A original', `${after.status} "${after.text}"`);
    const owB = await upload(B.jwt, pathA, 'B overwrote', true);
    check('participant B cannot overwrite A\'s object', denied(owB) && !uuidCastLeak(owB), `${owB.status}`);
    const dup = await upload(A.jwt, pathA, 'A duplicate', false);
    check('a plain re-upload to an existing path is refused (no silent replace)', denied(dup), `${dup.status}`);
  }

  // ═══ 4. malformed paths ══════════════════════════════════════════════════
  section('4. Malformed paths — denied, never an error');
  {
    const cases = [
      [`messages/not-a-uuid/${A.uid}/bad-${stamp}.txt`,           'non-uuid conversation segment'],
      [`messages/${CONV}/not-a-uuid/bad-${stamp}.txt`,            'non-uuid uploader segment'],
      [`messages/${CONV}/${A.uid}/extra/bad-${stamp}.txt`,        'four folder segments (too deep)'],
      [`messages/${CONV}/bad-${stamp}.txt`,                       'two folder segments (too shallow)'],
      [`notmessages/${CONV}/${A.uid}/bad-${stamp}.txt`,           'wrong namespace segment'],
      [`bad-${stamp}.txt`,                                        'bare filename, no folders'],
      // A real uuid with trailing garbage: text comparison must not "almost" match.
      [`messages/${CONV}x/${A.uid}/bad-${stamp}.txt`,             'conversation uuid with trailing garbage'],
      [`messages/${CONV}/${A.uid}x/bad-${stamp}.txt`,             'uploader uid with trailing garbage'],
    ];
    for (const [p, why] of cases) {
      const r = await upload(A.jwt, p, 'x');
      if (ok(r)) created.add(p);
      check(`malformed upload denied cleanly: ${why}`, denied(r) && !uuidCastLeak(r), `${r.status} ${(r.text || '').slice(0, 80)}`);
      const d = await download(A.jwt, p);
      check(`malformed read denied cleanly: ${why}`, denied(d) && !uuidCastLeak(d), `${d.status}`);
    }

    // Category B — the hostile/WAF-layer case, kept as defence-in-depth and
    // labelled for exactly what it proves. Cloudflare's WAF answers this URL
    // with an HTML 403 before storage-api sees it, so a denial here is evidence
    // of the WAF layer, NOT of the Storage policy. The two uuid-with-garbage
    // cases above are the ones that prove the policy's text comparison. If the
    // WAF ever lets this through, the policy must still deny it, and the detail
    // string flips to say so.
    {
      const p = `messages/'; DROP TABLE x; --/${A.uid}/bad-${stamp}.txt`;
      const r = await upload(A.jwt, p, 'x');
      if (ok(r)) created.add(p);
      check('hostile conversation segment upload denied (WAF-layer case; does not prove policy evaluation)',
        denied(r) && !uuidCastLeak(r), `${r.status} — ${denialLayer(r)}`);
      const d = await download(A.jwt, p);
      check('hostile conversation segment read denied (WAF-layer case; does not prove policy evaluation)',
        denied(d) && !uuidCastLeak(d), `${d.status} — ${denialLayer(d)}`);
    }
    // The original defect: one bad object would have broken every LIST for
    // everyone. Listing the conversation prefix must still work after all of
    // the above were attempted.
    const l = await list(A.jwt, `messages/${CONV}`);
    check('listing the conversation prefix still works for a participant', ok(l), `${l.status}`);
  }

  // ═══ 5. delete ═══════════════════════════════════════════════════════════
  section('5. Delete — the uploader only');
  {
    const dB = await remove(B.jwt, pathA);
    check('participant B cannot delete A\'s object', await exists(A.jwt, pathA), `delete ${dB.status}; still listed for A`);
    const dC = await remove(C.jwt, pathA);
    check('non-participant C cannot delete it', await exists(A.jwt, pathA), `delete ${dC.status}; still listed for A`);
    const dA = await remove(A.jwt, pathA);
    check('uploader A deletes own object', ok(dA), `${dA.status}`);
    const gone = !(await exists(A.jwt, pathA));
    check('…and it is gone, proved by a database-backed list', gone);
    if (gone) created.delete(pathA);

    // DIAGNOSTIC ONLY — not an assertion. A GET on /object/authenticated/ is
    // served through the CDN and may keep answering 200 for a deleted object
    // until invalidation propagates; that is why existence is proved by LIST
    // above. The headers are logged so a stale 200 can be attributed to the
    // cache rather than left as an unexplained number. Nothing here depends
    // on Cloudflare-specific headers being present.
    const diag = await download(A.jwt, pathA);
    const h = (n) => diag.headers?.get(n) ?? '-';
    console.log(`  diag  post-delete GET → ${diag.status}  cf-cache-status=${h('cf-cache-status')}  age=${h('age')}  cache-control=${h('cache-control')}`);
  }
} finally {
  // ═══ cleanup — closure standard §7: enumerate, remove, prove by a read ═══
  section('cleanup');
  for (const p of [...created]) {
    // Try every identity; only the uploader is authorized, which is the point.
    for (const who of [A, B, C]) { const r = await remove(who.jwt, p); if (ok(r)) break; }
    const still = await exists(A.jwt, p);
    check(`residual object removed: ${p}`, !still);
    if (!still) created.delete(p);
  }
  const l = await list(A.jwt, `messages/${CONV}`);
  check('conversation prefix lists zero objects after cleanup', ok(l) && Array.isArray(l.body) && l.body.length === 0, `${l.status} ${JSON.stringify(l.body)}`);

  if (SERVICE) {
    const del = await fetch(`${URL_}/rest/v1/conversations?id=eq.${CONV}`, {
      method: 'DELETE', headers: { apikey: SERVICE, Authorization: `Bearer ${SERVICE}`, Prefer: 'return=minimal,count=exact' },
    });
    const back = await fetch(`${URL_}/rest/v1/conversations?id=eq.${CONV}&select=id`, { headers: H(A.jwt) }).then(parse);
    check('fixture conversation row removed (service role), proved by a read', del.status < 300 && ok(back) && Array.isArray(back.body) && back.body.length === 0, `delete ${del.status}; re-read ${JSON.stringify(back.body)}`);
  } else {
    console.log(`\n  NOTE: no QA_SERVICE — the fixture conversation row ${CONV} must be removed by the operator`);
    console.log(`        (users have no DELETE policy on conversations). Verify with a read afterwards.`);
    console.log(`  D07-FIXTURE-CONVERSATION ${CONV}`);
  }
}

export default summary('3A-10 chat-media storage contract');
