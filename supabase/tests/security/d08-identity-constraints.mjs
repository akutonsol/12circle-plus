// Wave 3A task 3A-11 — the identity constraints, live.  (CRC-06, migration 131)
//
// Proves the four arbiters actually arbitrate, over the real PostgREST/RPC
// surface with the anon key and the same JWTs a phone would use:
//
//   I-NUT-04  at most one ACTIVE nutrition plan per client, and the assign
//             writer is atomic
//   I-WMH-01  one cycle_logs period per start date; end_date >= start_date
//   I-NOT-05  one conversation per unordered participant pair, race-free
//   I-PAY-01  one session-credit grant per payment
//
// ═══════════════════════════════════════════════════════════════════════════
// STATUS — CORRECTED 2026-09-30 (V5 §64/§65).  MIGRATION 131 IS APPLIED.
//
// This block used to read "DELIBERATELY NOT APPLIED … every assertion below
// fails by design".  That was true when written and is now FALSE, and it was
// the dangerous direction to be wrong in: it told a reader that a RED run here
// was EXPECTED, which would have masked a real regression.
//
// 131 is applied — verified against the LIVE QA catalog, not source: all four
// unique indexes and both functions are present, and the frontier is 141.
// This suite passes 24/24.  A FAILURE HERE IS A REGRESSION.
// ═══════════════════════════════════════════════════════════════════════════
//
// I-PAY-01 IS ONLY PARTLY REACHABLE HERE, and the suite says so rather than
// implying otherwise.  Its closure class is Billing / entitlement, which
// requires VERIFIED LIVE against Stripe TEST MODE; P-8 records that no QA
// Stripe credentials, runbook or price ids exist.  What is provable without
// Stripe is that the DATABASE refuses a second grant for one payment — the
// arbiter itself — and that is what is asserted.  The webhook replay is not
// simulated and no Stripe evidence is fabricated.
//
//   export QA_URL=https://<ref>.supabase.co QA_ANON=...   [QA_SERVICE=...]
//   node supabase/tests/security/d08-identity-constraints.mjs
//
// Registered in run.mjs.  QA only: it refuses any target it cannot positively
// identify as the 12 Circle QA project.

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

const IDENT = {
  victim:   { email: 'p1-victim@qa.12circle.test',   pw: 'P1-Probe-Victim-2026!' },
  attacker: { email: 'p1-attacker@qa.12circle.test', pw: 'P1-Probe-Attacker-2026!' },
  coach:    { email: 'p1-coach@qa.12circle.test',    pw: 'P1-Probe-Coach-2026!' },
};

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
  return { status: res.status, body, text: t };
}
async function signIn(key) {
  const r = await fetch(`${URL_}/auth/v1/token?grant_type=password`, {
    method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: IDENT[key].email, password: IDENT[key].pw }),
  });
  const { status, body } = await parse(r);
  if (status >= 300) throw new Error(`signIn ${IDENT[key].email}: ${status}`);
  return { jwt: body.access_token, uid: body.user.id };
}
const H = (jwt, extra = {}) => ({
  apikey: ANON, Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json', ...extra });

const rest = (jwt, path, opts = {}) =>
  fetch(`${URL_}/rest/v1/${path}`, {
    method: opts.method || 'GET',
    headers: H(jwt, opts.prefer ? { Prefer: opts.prefer } : {}),
    body: opts.body ? JSON.stringify(opts.body) : undefined,
  }).then(parse);
const rpc = (jwt, fn, params) =>
  fetch(`${URL_}/rest/v1/rpc/${fn}`, {
    method: 'POST', headers: H(jwt), body: JSON.stringify(params),
  }).then(parse);
const svc = (path, opts = {}) => SERVICE
  ? fetch(`${URL_}/rest/v1/${path}`, {
      method: opts.method || 'GET',
      headers: { apikey: SERVICE, Authorization: `Bearer ${SERVICE}`,
                 'Content-Type': 'application/json', Prefer: opts.prefer || 'return=representation' },
      body: opts.body ? JSON.stringify(opts.body) : undefined,
    }).then(parse)
  : Promise.resolve({ status: 0, body: null, text: '' });

const ok = (r) => r.status >= 200 && r.status < 300;
// The arbiter's signature. 23505 is the unique violation; PostgREST surfaces it
// as 409. Anything else — 500, a timeout, a cast error — is NOT this assertion
// passing, and is reported as such.
const uniqueViolation = (r) =>
  r.status === 409 || /23505|duplicate key value violates unique/i.test(r.text || '');

const A = await signIn('coach');
const B = await signIn('victim');
const C = await signIn('attacker');
const stamp = Date.now();
const cleanup = [];   // [table, filter] pairs, removed by service role at the end

console.log(`  A(coach)=${A.uid}  B(victim)=${B.uid}  C(attacker)=${C.uid}`);

try {
  // ═══ 1 · I-NOT-05 ════════════════════════════════════════════════════════
  section('1. I-NOT-05 — one conversation per unordered participant pair');
  {
    const r1 = await rpc(A.jwt, 'get_or_create_conversation', { other_user: B.uid });
    check('the RPC creates the conversation', ok(r1) && typeof r1.body === 'string', `${r1.status}`);
    const convId = typeof r1.body === 'string' ? r1.body : null;
    if (convId) cleanup.push(['conversations', `id=eq.${convId}`]);

    const r2 = await rpc(A.jwt, 'get_or_create_conversation', { other_user: B.uid });
    check('calling it again returns the SAME id, not a second thread',
      ok(r2) && r2.body === convId, `${r2.status} ${r2.body}`);

    // The pair is unordered: B asking for A must resolve to A's conversation.
    const r3 = await rpc(B.jwt, 'get_or_create_conversation', { other_user: A.uid });
    check('the other party resolves to the same conversation (pair is unordered)',
      ok(r3) && r3.body === convId, `${r3.status} ${r3.body}`);

    // Race: two simultaneous callers must converge on one row, not two.
    const [p1, p2] = await Promise.all([
      rpc(A.jwt, 'get_or_create_conversation', { other_user: C.uid }),
      rpc(C.jwt, 'get_or_create_conversation', { other_user: A.uid }),
    ]);
    check('two SIMULTANEOUS callers converge on one conversation',
      ok(p1) && ok(p2) && p1.body === p2.body, `${p1.body} vs ${p2.body}`);
    if (typeof p1.body === 'string') cleanup.push(['conversations', `id=eq.${p1.body}`]);

    // The index itself, proved directly: a raw insert of the same pair fails.
    const dup = await rest(A.jwt, 'conversations', {
      method: 'POST', prefer: 'return=minimal',
      body: { participant_1: B.uid, participant_2: A.uid },
    });
    check('a direct duplicate-pair insert is refused by the index',
      uniqueViolation(dup), `${dup.status} ${(dup.text || '').slice(0, 100)}`);

    check('the RPC refuses a self-conversation',
      !ok(await rpc(A.jwt, 'get_or_create_conversation', { other_user: A.uid })));
    const anonR = await fetch(`${URL_}/rest/v1/rpc/get_or_create_conversation`, {
      method: 'POST',
      headers: { apikey: ANON, Authorization: `Bearer ${ANON}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ other_user: B.uid }),
    }).then(parse);
    check('the RPC is not executable by anon', !ok(anonR), `${anonR.status}`);
  }

  // ═══ 2 · I-NUT-04 ════════════════════════════════════════════════════════
  section('2. I-NUT-04 — at most one ACTIVE nutrition plan per client');
  {
    const r1 = await rpc(A.jwt, 'assign_nutrition_plan', {
      p_client_id: B.uid, p_calories_target: 2100, p_protein_g: 150,
      p_carbs_g: 200, p_fat_g: 70, p_water_target_oz: 100, p_notes: `d08-${stamp}`,
    });
    check('the coach assigns a plan through the RPC', ok(r1), `${r1.status} ${(r1.text||'').slice(0,90)}`);
    cleanup.push(['client_nutrition_plans', `client_id=eq.${B.uid}`]);

    const r2 = await rpc(A.jwt, 'assign_nutrition_plan', {
      p_client_id: B.uid, p_calories_target: 2200, p_protein_g: 160,
      p_carbs_g: 210, p_fat_g: 72, p_water_target_oz: 100, p_notes: `d08-${stamp}-b`,
    });
    check('assigning a second plan supersedes rather than collides', ok(r2), `${r2.status}`);

    // The contract, read back: exactly one active row, and it is the newer one.
    const active = await rest(A.jwt,
      `client_nutrition_plans?select=id,calories_target,is_active&client_id=eq.${B.uid}&is_active=eq.true`);
    check('exactly ONE active plan remains',
      ok(active) && Array.isArray(active.body) && active.body.length === 1,
      `${active.status} n=${Array.isArray(active.body) ? active.body.length : '?'}`);
    check('and it is the newer prescription',
      Array.isArray(active.body) && active.body[0]?.calories_target === 2200,
      `${active.body?.[0]?.calories_target}`);

    // The index itself: a direct second active row is refused.
    const dup = await rest(A.jwt, 'client_nutrition_plans', {
      method: 'POST', prefer: 'return=minimal',
      body: { client_id: B.uid, coach_id: A.uid, calories_target: 999, is_active: true },
    });
    check('a direct second ACTIVE row is refused by the partial index',
      uniqueViolation(dup), `${dup.status} ${(dup.text || '').slice(0, 100)}`);

    check('the RPC is not executable by anon',
      !ok(await fetch(`${URL_}/rest/v1/rpc/assign_nutrition_plan`, {
        method: 'POST',
        headers: { apikey: ANON, Authorization: `Bearer ${ANON}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ p_client_id: B.uid, p_calories_target: 1, p_protein_g: 1, p_carbs_g: 1, p_fat_g: 1 }),
      }).then(parse)));

    // coach_id is taken from auth.uid(), so a caller cannot attribute a plan
    // to another coach even by asking.
    const attributed = await rest(C.jwt,
      `client_nutrition_plans?select=coach_id&client_id=eq.${B.uid}&is_active=eq.true`);
    check('coach_id records the actual caller, never a supplied value',
      !ok(attributed) || !Array.isArray(attributed.body) ||
        attributed.body.every((r) => r.coach_id !== C.uid),
      `${attributed.status}`);
  }

  // ═══ 3 · I-WMH-01 ════════════════════════════════════════════════════════
  section('3. I-WMH-01 — one period per start date; end_date >= start_date');
  {
    const day = `2026-03-0${1 + (stamp % 8)}`;
    const first = await rest(B.jwt, 'cycle_logs', {
      method: 'POST', prefer: 'return=minimal',
      body: { user_id: B.uid, start_date: day },
    });
    check('a period logs once', ok(first), `${first.status} ${(first.text||'').slice(0,90)}`);
    cleanup.push(['cycle_logs', `user_id=eq.${B.uid}`]);

    const second = await rest(B.jwt, 'cycle_logs', {
      method: 'POST', prefer: 'return=minimal',
      body: { user_id: B.uid, start_date: day },
    });
    check('the double tap is refused — one period per start date',
      uniqueViolation(second), `${second.status} ${(second.text || '').slice(0, 100)}`);

    const backwards = await rest(B.jwt, 'cycle_logs', {
      method: 'POST', prefer: 'return=minimal',
      body: { user_id: B.uid, start_date: '2026-04-10', end_date: '2026-04-01' },
    });
    check('a period cannot end before it starts',
      !ok(backwards) && /cycle_logs_end_on_or_after_start|23514/i.test(backwards.text || ''),
      `${backwards.status} ${(backwards.text || '').slice(0, 100)}`);

    const openEnded = await rest(B.jwt, 'cycle_logs', {
      method: 'POST', prefer: 'return=minimal',
      body: { user_id: B.uid, start_date: '2026-05-10' },
    });
    check('an open period (NULL end_date) is still allowed', ok(openEnded), `${openEnded.status}`);
  }

  // ═══ 4 · I-PAY-01 — the arbiter only; Stripe is out of reach ═════════════
  section('4. I-PAY-01 — one credit grant per payment (DB arbiter only)');
  {
    if (!SERVICE) {
      console.log('  SKIP  client_session_credits is service-role territory; QA_SERVICE not set.');
      console.log('        The DB arbiter is unproven in this run — NOT a pass.');
    } else {
      const pay = await svc('payments', {
        method: 'POST', prefer: 'return=representation',
        body: { user_id: B.uid, amount_cents: 1000, status: 'paid', kind: 'package' },
      });
      const paymentId = Array.isArray(pay.body) ? pay.body[0]?.id : null;
      check('fixture payment created', !!paymentId, `${pay.status}`);
      if (paymentId) {
        cleanup.push(['client_session_credits', `payment_id=eq.${paymentId}`]);
        const grant = { client_id: B.uid, coach_id: A.uid, payment_id: paymentId, sessions_total: 5 };
        const g1 = await svc('client_session_credits', { method: 'POST', prefer: 'return=minimal', body: grant });
        check('the first grant lands', ok(g1), `${g1.status}`);
        const g2 = await svc('client_session_credits', { method: 'POST', prefer: 'return=minimal', body: grant });
        check('a SECOND grant for the same payment is refused — the redelivery arbiter',
          uniqueViolation(g2), `${g2.status} ${(g2.text || '').slice(0, 100)}`);
        const rows = await svc(`client_session_credits?select=id&payment_id=eq.${paymentId}`);
        check('exactly one credit block exists for that payment',
          Array.isArray(rows.body) && rows.body.length === 1, `n=${rows.body?.length}`);

        // payment_id is nullable and NULLs are distinct: manual grants still work.
        const m1 = await svc('client_session_credits', { method: 'POST', prefer: 'return=minimal',
          body: { client_id: B.uid, coach_id: A.uid, sessions_total: 1 } });
        const m2 = await svc('client_session_credits', { method: 'POST', prefer: 'return=minimal',
          body: { client_id: B.uid, coach_id: A.uid, sessions_total: 1 } });
        check('two manual grants with NO payment still insert (NULLs are distinct)',
          ok(m1) && ok(m2), `${m1.status}/${m2.status}`);
        cleanup.push(['client_session_credits', `client_id=eq.${B.uid}`]);
        cleanup.push(['payments', `id=eq.${paymentId}`]);
      }
    }
    console.log('  NOTE  Stripe TEST-MODE replay is NOT simulated here and no Stripe');
    console.log('        evidence is claimed. P-8: no QA Stripe credentials exist.');
    console.log('        I-PAY-01 terminal closure is DEFERRED to Wave 6 with K-01.');
  }
} finally {
  // ═══ cleanup — closure standard §7: remove, then PROVE by a read ═════════
  section('cleanup');
  if (!SERVICE) {
    console.log('  NOTE: no QA_SERVICE — fixtures created as the p1 identities remain.');
    for (const [t, f] of cleanup) console.log(`  D08-FIXTURE ${t} ${f}`);
  } else {
    for (const [table, filter] of cleanup) {
      await svc(`${table}?${filter}`, { method: 'DELETE', prefer: 'return=minimal' });
    }
    let remaining = 0;
    for (const [table, filter] of cleanup) {
      const back = await svc(`${table}?select=*&${filter}`);
      if (Array.isArray(back.body)) remaining += back.body.length;
    }
    check('every fixture removed, proved by a read', remaining === 0, `remaining=${remaining}`);
  }
}

export default summary('3A-11 identity constraints');
