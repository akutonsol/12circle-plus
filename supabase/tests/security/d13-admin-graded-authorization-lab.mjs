// D13 · GRADED ADMIN AUTHORIZATION — the matrix-INDEPENDENT half, live against QA.
//
// Covers migrations 153 (admin layer) and 154 (governance registry). V5 §113 is
// the specification, §113.3 the least-privilege proof, §118.3 the QA packet.
//
// WHY THIS SUITE IS UNREGISTERED. 153/154 are authored and declared PENDING on QA
// (supabase/expected_applied.json) because no owner authorization to apply them
// exists. Registering it in run.mjs would make CI fail on a migration that is
// deliberately unapplied — the opposite of evidence. It is registered the moment
// they are applied.
//
// WHY IT NEEDS NO CAPABILITY DATA. Every assertion below holds with
// admin_role_capabilities EMPTY. The 85-cell matrix is a separate blocker (V5
// §116) and gates only the grant-specific tests of §A6. These are the structural
// and separation properties, and they are exactly the ones a seeding mistake
// would break.
//
// It CLEANS UP after itself: unlike d12, these tables carry no append-only freeze,
// so the fixture assignment row is removed in a finally block.
import { URL_, SERVICE, IDENT, signIn, rpc, rest, mutate, svc, check, section, summary, beginSuite, n } from './lib.mjs';

async function run() {
  beginSuite();

  // ── 0 · are the migrations applied at all? ────────────────────────────────
  // Stated first so a run against an un-migrated QA reports WHY it asserted
  // nothing, rather than failing 20 times for one reason (V5 §28.9's lesson).
  const probe = await svc('admin_role_capabilities?select=admin_role&limit=1');
  if (probe.status === 404 || (probe.body && /does not exist|schema cache/i.test(JSON.stringify(probe.body)))) {
    check('migrations 153/154 are applied to QA', false,
      'admin_role_capabilities not reachable — 153 is PENDING, nothing below was asserted');
    return summary('D13 admin graded authorization');
  }
  check('migrations 153/154 are applied to QA', true, 'capability table reachable');

  const victim = await signIn('victim');   // role='client' — never role='admin'
  let arranged = false;

  try {
    // ── 1 · deny-by-default, now against the SEEDED grid ────────────────────
    // UPDATED V5 §125. This section asserted an EMPTY grid, which was correct
    // until migration 155 seeded the owner-approved matrix. Two things had to
    // change, and the second is the one that matters:
    //   · the row count is now the approved 116, not 0;
    //   · the deny probes used DISPLAY casing ('View'), which matches no row
    //     because 153's CHECK stores lowercase verbs. Left as they were, they
    //     would have kept passing for the wrong reason — vacuously — once the
    //     grid was populated. They now use lowercase and a cell the matrix
    //     genuinely denies to a Viewer.
    // The exhaustive per-cell verification lives in D14, which reads its
    // expectations from the approved matrix file itself.
    section('deny-by-default against the seeded matrix');
    const caps = await svc('admin_role_capabilities?select=admin_role');
    check('capability grid holds the approved 116 rows',
      Array.isArray(caps.body) && caps.body.length === 116,
      `rows=${Array.isArray(caps.body) ? caps.body.length : '?'}`);

    // At this point the caller holds NO Admin-layer assignment, so a populated
    // grid must still give them nothing — the grid grants to ROLES, never to
    // everyone. This runs before the fixture role is arranged, deliberately.
    for (const [area, verb] of [['Security', 'view'], ['Audit logs', 'update'], ['Users', 'create']]) {
      const r = await rpc(victim, 'admin_can', { p_area: area, p_verb: verb });
      check(`admin_can('${area}','${verb}') is false for an UNASSIGNED caller`,
        r.body === false, `got ${JSON.stringify(r.body)}`);
    }

    // ── 2 · the Admin layer does NOT confer legacy admin — §113.3 proof ──────
    section('an Admin-layer member is not a legacy admin');
    const me = await svc(`user_profiles?select=id&email=eq.${encodeURIComponent(IDENT.victim.email)}`);
    const uid = Array.isArray(me.body) && me.body[0] ? me.body[0].id : null;
    check('fixture identity resolved', !!uid, uid ? 'ok' : 'could not resolve victim id');

    if (uid) {
      // svc() JSON-stringifies opts.body itself — pass an OBJECT, never a string,
      // or the body is double-encoded and the row lands unusable while PostgREST
      // still answers 201. That exact mistake made is_admin_member() read false
      // on this suite's first live run.
      // DELETE FIRST. admin_role_assignments has user_id as its PRIMARY KEY, so a
      // bare INSERT returns 409 if ANY row for this fixture survives from an
      // earlier run -- and this arrange used to be a bare INSERT.
      //
      // V5 §137: that is not hypothetical. Pushing over an in-flight CI run
      // cancelled it mid-suite; a cancelled process never runs a `finally`, so the
      // assignment row survived, and the NEXT run's arrange returned 409. Because
      // the cleanup below was guarded by `if (arranged)`, a failed arrange left the
      // row in place -- so the failure perpetuated itself and every subsequent run
      // would have failed for a reason that had nothing to do with the code under
      // test. A suite must survive the abrupt death of the one before it.
      await svc(`admin_role_assignments?user_id=eq.${uid}`, { method: 'DELETE' });
      const ins = await svc('admin_role_assignments', {
        method: 'POST', body: { user_id: uid, admin_role: 'viewer' },
      });
      arranged = ins.status < 300;
      check('arranged: victim holds the Viewer Admin role', arranged, `status=${ins.status}`);

      if (arranged) {
        const isMember = await rpc(victim, 'is_admin_member');
        check('is_admin_member() is TRUE for the assigned user', isMember.body === true, `got ${JSON.stringify(isMember.body)}`);

        // THE assertion. A Viewer must not satisfy is_admin(), or they inherit
        // all 14 inline RLS clauses that name 'admin' (V5 §107.3).
        const isAdmin = await rpc(victim, 'is_admin');
        check('is_admin() is FALSE for a Viewer — no legacy admin inherited',
          isAdmin.body === false, `got ${JSON.stringify(isAdmin.body)}`);

        const isTrust = await rpc(victim, 'is_trust_operator');
        check('is_trust_operator() is FALSE — Trust separation holds', isTrust.body === false, `got ${JSON.stringify(isTrust.body)}`);

        const isEras = await rpc(victim, 'is_erasure_executor');
        check('is_erasure_executor() is FALSE — erasure separation holds', isEras.body === false, `got ${JSON.stringify(isEras.body)}`);

        // The predicate must DISCRIMINATE, not merely always deny: with the role
        // assigned, a grant the approved matrix gives a Viewer must now be true,
        // while one it withholds stays false. Without this pair, an always-false
        // admin_can() would satisfy every other assertion in this suite.
        const yes = await rpc(victim, 'admin_can', { p_area: 'Security', p_verb: 'view' });
        check("admin_can('Security','view') is TRUE for an assigned Viewer", yes.body === true, `got ${JSON.stringify(yes.body)}`);
        const no = await rpc(victim, 'admin_can', { p_area: 'Security', p_verb: 'manage' });
        check("admin_can('Security','manage') is FALSE for an assigned Viewer", no.body === false, `got ${JSON.stringify(no.body)}`);

        // ── 3 · the layer cannot escalate itself ────────────────────────────
        section('self-escalation is refused');
        const selfGrant = await mutate(victim, 'admin_role_capabilities', 'POST',
          { admin_role: 'viewer', area: 'Security', verb: 'manage' });
        check('a Viewer cannot grant themselves a capability',
          selfGrant.status >= 400 || selfGrant.affected === 0, `status=${selfGrant.status}`);

        const selfAssign = await mutate(victim, 'admin_role_assignments', 'POST',
          { user_id: uid, admin_role: 'trust_lead' });
        check('a Viewer cannot promote their own Admin role',
          selfAssign.status >= 400 || selfAssign.affected === 0, `status=${selfAssign.status}`);

        // ── 4 · A12 — the layer opens no identity path ──────────────────────
        section('A12 · no new re-identification path');
        const map = await rest(victim, 'audit_identity_map?select=*').catch(() => ({ status: 403 }));
        check('a Viewer cannot read audit_identity_map',
          !map || map.status >= 400 || (Array.isArray(map.body) && map.body.length === 0),
          `status=${map && map.status}`);

        // ── 5 · governance registry — CORRECTED BY MIGRATION 163 ────────────
        // This asserted "a Viewer cannot read governance_policy", which was true
        // when 154 shipped and is NO LONGER the approved posture. The matrix grants
        // AI Guardian/View to viewer, and 154's read arm was is_admin() OR
        // is_trust_operator() -- neither of which an Admin-layer principal
        // satisfies -- so the owner-approved grant was INERT. 163 adds the
        // admin_can('AI Guardian','view') arm that makes it effective (V5 §135).
        //
        // It was ALSO passing vacuously: governance_policy is empty on QA, so the
        // old assertion could not distinguish "RLS denied the read" from "there was
        // nothing to read". The discriminating test now lives in D15, which seeds a
        // row for the duration and asserts three roles CAN read it and two CANNOT.
        //
        // What remains assertable here, and is the property this suite owns: the
        // Admin layer may READ the governance record and may not AUTHOR it. 154's
        // writes stay on is_admin() and 163 added no write arm.
        section('governance registry (154/163)');
        const gpWrite = await mutate(victim, 'governance_policy', 'POST',
          { code: 'D13-FORBIDDEN', name: 'x', category: 'safety', status: 'draft' });
        check('a Viewer cannot AUTHOR a governance policy — the registry is not writable by the Admin layer',
          gpWrite.status >= 400 || gpWrite.affected === 0, `status=${gpWrite.status}`);
        const gpLanded = await svc('governance_policy?select=id&code=eq.D13-FORBIDDEN');
        check('…and no row landed', n(gpLanded.body) === 0, `rows=${n(gpLanded.body)}`);
      }
    }

    // ── 6 · anon reaches nothing ────────────────────────────────────────────
    section('anon posture');
    for (const t of ['admin_role_assignments', 'admin_role_capabilities', 'governance_policy']) {
      const a = await fetch(`${URL_}/rest/v1/${t}?select=*`, { headers: { apikey: process.env.QA_ANON } });
      check(`anon cannot read ${t}`, a.status >= 400 || (await a.json().catch(() => [])).length === 0,
        `status=${a.status}`);
    }
  } finally {
    // UNCONDITIONAL. This used to run only `if (arranged)`, which meant a FAILED
    // arrange left its row behind -- the exact condition that makes the failure
    // self-perpetuating (V5 §137). Deleting a row that is not there is free.
    const me = await svc(`user_profiles?select=id&email=eq.${encodeURIComponent(IDENT.victim.email)}`);
    const uid = Array.isArray(me.body) && me.body[0] ? me.body[0].id : null;
    if (uid) await svc(`admin_role_assignments?user_id=eq.${uid}`, { method: 'DELETE' });
  }

  return summary('D13 admin graded authorization');
}

// run.mjs imports each suite for its side effects and reads the DEFAULT EXPORT as
// that suite's failure count, so a suite must execute on import. Keeping run() as
// a function and awaiting it here preserves the early-return guard at the top
// while still matching that contract.
export default await run();
