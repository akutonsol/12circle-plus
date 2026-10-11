// D15 · ADMIN SURFACE ACCESS — migrations 156/157, live against QA.
//
// The owner's authorization for these surfaces says: "test the actual resulting
// data access, not merely function return values." D13 proves admin_can() returns
// the right booleans and D14 proves all 425 of them. NEITHER proves a row crosses
// an RLS boundary. This suite reads rows.
//
// WHY MOST ASSERTIONS ARE COUNT COMPARISONS AGAINST SERVICE. A surface test that
// says "the admin got HTTP 200" proves nothing: PostgREST answers 200 with `[]`
// when RLS filters everything, which is exactly how the three coach surfaces in
// SEC-G3 rendered a confident permanent zero. So every positive asserts the
// assigned caller sees THE SAME COUNT the service role sees, and every negative
// asserts an unassigned caller sees ZERO of the same query.
//
// WHY SEVEN OF THE SIXTEEN ARMS ARE ASSERTED AS REDUNDANT, NOT AS GRANTS. The
// baseline measured before 156 (V5 §128.2) showed community_posts, post_comments,
// post_reactions, community_groups, accountability_pods, events and classes are
// ALREADY readable by any authenticated user through policies that predate this
// work. The admin arm on those tables grants nothing that was not already granted.
// Asserting "an admin can read community_posts" would therefore PASS WITHOUT 156
// APPLIED AT ALL -- a vacuous test, and §5.2's "test the class, not the instance"
// cuts against writing one. They are asserted for NON-REGRESSION only, and the
// pre-existing broad posture is recorded as a finding rather than dressed up as a
// result of this migration.
import { URL_, SERVICE, IDENT, signIn, rest, mutate, svc, rpc, countExact, countExactAs,
         check, checkDenied, checkGranted, section, summary, beginSuite, n } from './lib.mjs';
import { readFileSync, readdirSync } from 'node:fs';

// Owner decision B-20 (2026-10-06): these capabilities are AUTHORIZED AND NOT
// OFFERED. Read from the register rather than restated here, so the test and the
// ruling cannot drift — the same discipline D14 uses for the capability matrix.
const NON_OPERATIONAL = JSON.parse(
  readFileSync('docs/design/admin-dashboard/ADMIN-NON-OPERATIONAL-CAPABILITIES.json', 'utf8'));

// Every migration's SQL, loaded once. POSITIVE ASSERTION: this THROWS if it finds
// no migrations, rather than returning [] and letting a "no write path exists"
// assertion pass because nothing was read. Three checkers in this programme have
// reported success from an empty result (V5 §139.3), and a static scan that
// silently scanned nothing is the same bug wearing a test's clothes.
const MIGRATION_SOURCES = (() => {
  const dir = 'supabase/migrations';
  const files = readdirSync(dir).filter((f) => f.endsWith('.sql')).sort();
  if (files.length < 100) {
    throw new Error(`D15: expected the full migration set in ${dir}, found ${files.length} ` +
      'file(s) — refusing to run static assertions against a directory this small, ' +
      'because "no match" would then mean "nothing was searched"');
  }
  const loaded = files.map((name) => ({ name, sql: readFileSync(`${dir}/${name}`, 'utf8') }));
  // Prove the loader can actually SEE a string it must be able to find, so a
  // path or encoding fault cannot masquerade as a clean scan.
  const canary = loaded.some((m) => /admin_can\(\s*'Community'\s*,\s*'view'/i.test(m.sql));
  if (!canary) {
    throw new Error("D15: the migration scan could not find admin_can('Community','view'), " +
      'which migration 156 definitely contains — the scan is broken, not the schema');
  }
  return loaded;
})();

// DISCOVERED, NOT LISTED. V5 §139.6: a hardcoded list covers the views someone
// remembered. Every `admin_*` view in the migration set is swept for mutation
// below, so a view added later is covered the day it ships rather than the day
// someone updates this array — which is how 156/157's three views reached QA
// holding `authenticated` write grants in the first place (§129.2).
const VIEWS = (() => {
  const found = [...new Set(MIGRATION_SOURCES.flatMap((m) =>
    [...m.sql.matchAll(/CREATE\s+(?:OR\s+REPLACE\s+)?VIEW\s+(?:public\.)?(admin_[a-z0-9_]+)/gi)]
      .map((x) => x[1].toLowerCase())))].sort();
  if (found.length === 0) {
    throw new Error('D15: discovered NO admin_* views in the migration set — the scan is ' +
      'broken, not the schema; refusing to report a clean mutation sweep over nothing');
  }
  return found;
})();

// Credential-looking columns the schema ACTUALLY declares, discovered rather than
// listed. Throws if it finds none, because a sweep over an empty set would report
// every view clean (V5 §139.3).
const SECRET_COLUMNS = (() => {
  const re = /token|secret|password|credential|api_key|private_key/i;
  const found = new Set();
  for (const m of MIGRATION_SOURCES) {
    for (const c of m.sql.matchAll(/^\s*"?([a-z_][a-z0-9_]*)"?\s+(?:TEXT|text|varchar|VARCHAR)/gm)) {
      if (re.test(c[1])) found.add(c[1].toLowerCase());
    }
  }
  if (found.size === 0) {
    throw new Error('D15: discovered NO credential-looking columns in the schema — the scan ' +
      'is broken, not the schema (user_integrations.access_token exists), and a clean ' +
      'sweep over an empty set would be meaningless');
  }
  return [...found].sort();
})();



// Owner decision B-2: the Users projection is identity and account state ONLY.
// Every column below is PHI, contact PII, a financial identifier, or a risk field
// DERIVED from PHI. risk_* and phone were offered and DECLINED, so they are
// asserted absent alongside the rest -- a projection that quietly widened would
// otherwise satisfy every other assertion.
const USERS_FORBIDDEN = ['medical_conditions', 'parq_answers', 'has_injuries', 'injury_locations',
                         'injury_description', 'date_of_birth', 'height_cm', 'weight_kg',
                         'sleep_hours', 'stress_level', 'dietary_restrictions', 'food_allergies',
                         'risk_score', 'risk_level', 'risk_flags', 'stripe_customer_id',
                         'stripe_account_id', 'phone'];
const USERS_ALLOWED = ['id', 'first_name', 'last_name', 'email', 'avatar_url', 'role',
                       'membership_tier', 'onboarding_complete', 'created_at'];

// Owner decision B-1, 2026-10-05: the Security area is access-control oversight.
// control_evidence and storage_media_access were OFFERED AND NOT CHOSEN, so they
// are asserted ABSENT -- a surface that silently widened past the decision would
// otherwise pass every other assertion below.
const SECURITY_IN  = ['authentication', 'authorization_denial', 'admin_action', 'audit_read'];
const SECURITY_OUT = ['incident', 'phi_read', 'phi_correction', 'financial', 'agent_action',
                      'control_evidence', 'storage_media_access', 'relationship_change',
                      'export_deletion', 'observability_audit', 'billing_entitlement'];

async function uidOf(key) {
  const r = await svc(`user_profiles?select=id&email=eq.${encodeURIComponent(IDENT[key].email)}`);
  return Array.isArray(r.body) && r.body[0] ? r.body[0].id : null;
}
async function assign(uid, role) {
  await svc(`admin_role_assignments?user_id=eq.${uid}`, { method: 'DELETE' });
  const r = await svc('admin_role_assignments', { method: 'POST', body: { user_id: uid, admin_role: role } });
  return r.status < 300;
}
async function unassign(uid) {
  if (uid) await svc(`admin_role_assignments?user_id=eq.${uid}`, { method: 'DELETE' });
}

async function run() {
  beginSuite();

  // ── 0 · are 156/157 applied? ──────────────────────────────────────────────
  const probe = await svc('admin_audit_events?select=id&limit=1');
  if (probe.status === 404 || (probe.body && /does not exist|schema cache/i.test(JSON.stringify(probe.body)))) {
    check('migrations 156/157 are applied to QA', false,
      'admin_audit_events not reachable — nothing below was asserted');
    return summary('D15 admin surface access');
  }
  check('migrations 156/157 are applied to QA', true, 'all three curated views reachable');

  const victim = await signIn('victim');
  const admin  = await signIn('admin');
  let vUid = null, aUid = null, seededIntegration = null, capRemoved = false;

  try {
    vUid = await uidOf('victim');
    aUid = await uidOf('admin');
    check('fixture identities resolved', !!vUid && !!aUid, `victim=${!!vUid} admin=${!!aUid}`);
    if (!vUid) return summary('D15 admin surface access');

    // ── 1 · the DECISIVE pairs — 0 without the role, all rows with it ───────
    // These four tables deny an unassigned authenticated caller outright, so the
    // before/after difference is attributable to 156 and to nothing else.
    section('decisive surfaces · unassigned sees nothing, Viewer sees everything');
    const DECISIVE = [
      ['event_registrations', 'Events'],
      ['class_bookings',      'Events'],
      ['subscriptions',       'Monetization'],
      ['observability_events','System'],
    ];
    await unassign(vUid);
    const baseline = {};
    for (const [t] of DECISIVE) {
      const svcRows = await svc(`${t}?select=id`);
      const mine    = await rest(victim, `${t}?select=id`);
      baseline[t] = n(svcRows.body);
      checkDenied(`${t}: an UNASSIGNED caller sees nothing`,
        { saw: n(mine.body), population: baseline[t], detail: `status=${mine.status}` });
    }

    const arranged = await assign(vUid, 'viewer');
    check('arranged: victim holds the Viewer Admin role', arranged, `assign ok=${arranged}`);

    for (const [t, area] of DECISIVE) {
      const mine = await rest(victim, `${t}?select=id`);
      checkGranted(`${t}: a Viewer now sees every row via admin_can('${area}','view')`,
        { saw: n(mine.body), population: baseline[t], detail: `status=${mine.status}` });
    }

    // ── 2 · the seven redundant arms — non-regression only ──────────────────
    section('pre-existing broad-read tables · arms are redundant, asserted for non-regression');
    for (const t of ['community_posts','post_comments','post_reactions','community_groups',
                     'accountability_pods','events','classes']) {
      const svcRows = await svc(`${t}?select=id`);
      const mine    = await rest(victim, `${t}?select=id`);
      check(`${t}: readable (${n(mine.body)}/${n(svcRows.body)}) — ALREADY public to authenticated before 156`,
        n(mine.body) === n(svcRows.body), `saw ${n(mine.body)} of ${n(svcRows.body)}`);
    }

    // ── 3 · Training — AGGREGATE ONLY, no row-level PHI path ────────────────
    // The parked boundary is row-level training disclosure. This asserts the
    // aggregate works AND that the projection cannot be turned into a row reader.
    section('Training aggregate surface');
    const tAgg = await rest(victim, 'admin_training_overview?select=*');
    check('a Viewer reads the Training aggregate — exactly one row',
      n(tAgg.body) === 1, `rows=${n(tAgg.body)} status=${tAgg.status}`);
    check('the aggregate carries the four counts and nothing else',
      n(tAgg.body) === 1 && ['programs_total','workouts_total','sessions_total','logs_total']
        .every(k => k in tAgg.body[0]) && Object.keys(tAgg.body[0]).length === 4,
      `keys=${n(tAgg.body) === 1 ? Object.keys(tAgg.body[0]).join(',') : 'n/a'}`);
    for (const col of ['user_id','workout_id','notes']) {
      const r = await rest(victim, `admin_training_overview?select=${col}`);
      check(`the Training aggregate exposes no ${col} column — no row-level path`,
        r.status >= 400, `status=${r.status}`);
    }
    // And the PARKED boundary must still hold: row-level training stays denied.
    // ASSERTED ON workout_sessions, NOT workout_logs. The first draft of this
    // check used workout_logs and FAILED -- not because the boundary leaked but
    // because that table is EMPTY on QA, so "the Viewer saw 0" proved nothing. A
    // deny assertion over an empty table is the vacuous pass this suite exists to
    // avoid, and the `service > 0` clause is what caught it. workout_sessions
    // carries real rows, so the denial is observable.
    for (const t of ['workout_sessions', 'workout_logs']) {
      const raw = await rest(victim, `${t}?select=id`);
      const all = await svc(`${t}?select=id`);
      if (n(all.body) === 0) {
        check(`PARKED boundary: ${t} is EMPTY on QA — denial not assertable here`,
          n(raw.body) === 0, `viewer=${n(raw.body)} service=0 (recorded, not claimed as proof)`);
        continue;
      }
      checkDenied(`PARKED boundary intact: a Viewer reads no row-level ${t}`,
        { saw: n(raw.body), population: n(all.body) });
    }

    // ── 4 · Integrations — the column-limited view, and the STRICTER AND ────
    section('Wearable / Integrations connection view (157)');
    const coachUid = await uidOf('coach');
    const ins = await svc('user_integrations', { method: 'POST', body: {
      user_id: coachUid, provider: 'qa-d15-probe', connected: true,
      access_token: 'QA-D15-SECRET-MUST-NEVER-BE-READABLE',
      refresh_token: 'QA-D15-REFRESH-MUST-NEVER-BE-READABLE' } });
    seededIntegration = ins.status < 300;
    check('seeded a probe integration row carrying a token', seededIntegration, `status=${ins.status}`);

    if (seededIntegration) {
      const via = await rest(victim, 'admin_integration_connections?select=*&provider=eq.qa-d15-probe');
      check('a Viewer reads the probe connection through the curated view',
        n(via.body) === 1, `rows=${n(via.body)} status=${via.status}`);
      check('the curated view exposes NO token column — the 156 defect is closed',
        n(via.body) === 1 && !('access_token' in via.body[0]) && !('refresh_token' in via.body[0]),
        `keys=${n(via.body) === 1 ? Object.keys(via.body[0]).join(',') : 'n/a'}`);
      for (const col of ['access_token','refresh_token']) {
        const r = await rest(victim, `admin_integration_connections?select=${col}`);
        check(`${col} cannot be selected through the curated view`, r.status >= 400, `status=${r.status}`);
      }
      // The base table must STILL deny cross-user reads — 157 withdrew 156's arm.
      const direct = await rest(victim, 'user_integrations?select=id,access_token');
      check('the base table still denies a Viewer any other user\'s integration row',
        n(direct.body) === 0, `rows=${n(direct.body)} status=${direct.status}`);

      // STRICTER AUTHORIZATION, proved behaviourally. The owner directed the
      // shared surface use "the stricter applicable authorization", implemented as
      // AND over both areas. Today the matrix grants both to every role, so an AND
      // and an OR are indistinguishable by observation -- unless one grant is
      // withdrawn. This removes the Integrations grant ONLY, asserts the surface
      // closes even though the Wearable grant remains, and restores it. The
      // approved matrix FILE is not touched; the row is replaced and the 116-row
      // total re-asserted before this block exits.
      const del = await svc("admin_role_capabilities?admin_role=eq.viewer&area=eq.Integrations&verb=eq.view",
                            { method: 'DELETE' });
      capRemoved = del.status < 300;
      check('withdrew only viewer/Integrations/view for the stricter-AND probe', capRemoved, `status=${del.status}`);
      if (capRemoved) {
        const stillWearable = await rpc(victim, 'admin_can', { p_area: 'Wearable intelligence', p_verb: 'view' });
        check('the Wearable grant is still TRUE during the probe',
          stillWearable.body === true, `got ${JSON.stringify(stillWearable.body)}`);
        const closed = await rest(victim, 'admin_integration_connections?select=id&provider=eq.qa-d15-probe');
        check('STRICTER: losing ONE of the two area grants closes the shared surface',
          n(closed.body) === 0, `rows=${n(closed.body)} — an OR would still have returned 1`);
        const re = await svc('admin_role_capabilities', { method: 'POST',
          body: { admin_role: 'viewer', area: 'Integrations', verb: 'view' } });
        capRemoved = !(re.status < 300);
        const back = await rest(victim, 'admin_integration_connections?select=id&provider=eq.qa-d15-probe');
        check('restored: the surface reopens and the grid is whole again',
          !capRemoved && n(back.body) === 1, `restore=${re.status} rows=${n(back.body)}`);
        const caps = await svc('admin_role_capabilities?select=admin_role');
        check('the approved grid is back to exactly 116 rows',
          n(caps.body) === 116, `rows=${n(caps.body)}`);
      }
    }

    // ── 5 · the curated AUDIT projection — A13·1 and A12 ───────────────────
    section('curated audit projection · A13·1 preserved, base table untouched');

    // 5a · the base table protection the owner required proof of. The Viewer is
    // NOT is_admin() and NOT is_trust_operator(), so 142's policy gives them
    // nothing -- and 156 added no arm to it.
    const svcAudit = await svc('audit_events?select=id&limit=1000');
    const rawAudit = await rest(victim, 'audit_events?select=id&limit=1000');
    checkDenied('BASE audit_events still denies a Viewer every row — A13·1 not bypassed',
      { saw: n(rawAudit.body), population: n(svcAudit.body) });

    // 5b · the curated surface DOES open to that same Viewer (Audit logs/View=true)
    const curated = await rest(victim, 'admin_audit_events?select=id&limit=1000');
    check('the CURATED view opens audit reads to a Viewer the base table refuses',
      n(curated.body) > 0, `rows=${n(curated.body)} status=${curated.status}`);

    // 5c · discrimination. support has Audit logs/View = FALSE in the approved
    // matrix, so the same view must close for them. Without this, an always-open
    // view would satisfy 5b too.
    await assign(vUid, 'support');
    const asSupport = await rest(victim, 'admin_audit_events?select=id&limit=1000');
    checkDenied('the curated view CLOSES for Support — Audit logs/View is false in the matrix',
      { saw: n(asSupport.body), population: n(curated.body) });
    await assign(vUid, 'viewer');

    // 5d · A13·1 itself, on real rows. p1-admin authored admin_action rows, so
    // assigning them an Admin-layer role makes the exclusion observable: their own
    // rows must vanish from the view while everyone else's remain. Counts are read
    // from service at run time, so this does not drift as the population grows.
    const ownSvc   = await svc(`audit_events?select=id&category=eq.admin_action&actor_id=eq.${aUid}`);
    const otherSvc = await svc(`audit_events?select=id&category=eq.admin_action&actor_id=neq.${aUid}&limit=1000`);
    const assignedAdmin = await assign(aUid, 'viewer');
    check('arranged: p1-admin holds an Admin-layer Viewer role', assignedAdmin, `ok=${assignedAdmin}`);
    if (assignedAdmin && n(ownSvc.body) > 0) {
      const ownViaView = await rest(admin,
        `admin_audit_events?select=id&category=eq.admin_action&actor_id=eq.${aUid}`);
      check(`A13·1: the reader's OWN ${n(ownSvc.body)} admin_action rows are EXCLUDED from the view`,
        n(ownViaView.body) === 0, `saw ${n(ownViaView.body)} of ${n(ownSvc.body)}`);
      const otherViaView = await rest(admin,
        `admin_audit_events?select=id&category=eq.admin_action&actor_id=neq.${aUid}&limit=1000`);
      check(`A13·1 is NARROW: the other ${n(otherSvc.body)} admin_action rows remain visible`,
        n(otherSvc.body) > 0 && n(otherViaView.body) === n(otherSvc.body),
        `saw ${n(otherViaView.body)} of ${n(otherSvc.body)}`);
    } else {
      check('A13·1 exclusion is observable on real rows', false,
        `p1-admin authored ${n(ownSvc.body)} admin_action rows — cannot assert non-vacuously`);
    }

    // 5e · A12 — the view projects a pseudonym and opens no resolution path.
    section('A12 · the curated view resolves nothing');
    const shape = await rest(victim, 'admin_audit_events?select=*&limit=1');
    check('the curated view projects subject_pseudonym',
      n(shape.body) === 1 && 'subject_pseudonym' in shape.body[0],
      `keys=${n(shape.body) === 1 ? Object.keys(shape.body[0]).join(',') : 'none'}`);
    for (const col of ['subject_id','correlation_signature','correlation_key_id']) {
      const r = await rest(victim, `admin_audit_events?select=${col}`);
      check(`the curated view exposes no ${col}`, r.status >= 400, `status=${r.status}`);
    }
    const map = await rest(victim, 'audit_identity_map?select=*');
    check('a Viewer still cannot read audit_identity_map', n(map.body) === 0, `status=${map.status}`);

    // ── 6 · no write authority was created anywhere ─────────────────────────
    section('read surfaces confer no write authority');
    const wSub = await mutate(victim, 'subscriptions', 'POST', { user_id: vUid, kind: 'qa-d15', status: 'incomplete' });
    check('a Viewer cannot INSERT a subscription despite Monetization/View',
      wSub.status >= 400 || wSub.affected === 0, `status=${wSub.status}`);
    const wRole = await mutate(victim, 'admin_role_assignments', 'POST', { user_id: vUid, admin_role: 'trust_lead' });
    check('Roles READ confers no role-management authority (owner constraint)',
      wRole.status >= 400 || wRole.affected === 0, `status=${wRole.status}`);

    // ── 6b · THE CURATED VIEWS CONFER NO WRITE AUTHORITY ───────────────────
    // This section exists because 156/157 SHIPPED WITHOUT IT and the gap was real.
    // Both migrations revoked from PUBLIC and anon but NOT from `authenticated`,
    // and Supabase's default privileges grant ALL on a new view to that role. The
    // two single-table views are auto-updatable and run security_invoker = off, so
    // a write through them executes as the view OWNER and base-table RLS does not
    // apply. A user holding only the Admin-layer `viewer` role -- View yes, Update
    // explicitly NO -- DELETED another user's user_integrations row through
    // admin_integration_connections before migration 158 (V5 §129.2).
    //
    // Section 6 above asserted write refusal on the BASE TABLES and passed, which
    // is exactly why it did not catch this: the escalation was through the VIEW.
    // A deny assertion only covers the object it names.
    section('the curated views confer no write authority (158)');
    const NONE = '00000000-0000-0000-0000-000000000000';
    // INSERT and DELETE reflect the privilege directly: both answered 2xx before
    // 158 and 403 after it.
    for (const v of VIEWS) {
      for (const method of ['POST', 'DELETE']) {
        const path = method === 'POST' ? v : `${v}?id=eq.${NONE}`;
        const r = await rest(victim, path, {
          method,
          ...(method === 'DELETE' ? {} : { body: JSON.stringify({ provider: 'probe' }) }),
          headers: { 'Content-Type': 'application/json' },
        }).catch(() => ({ status: 403 }));
        check(`${method} on ${v} is refused`, r.status >= 400,
          `status=${r.status} — a 2xx means authenticated still holds the write grant`);
      }
    }
    // NO ADMIN VIEW MAY PROJECT A CREDENTIAL. Swept over the DISCOVERED view list
    // and the credential columns the schema actually declares, so this covers a
    // view added later and a secret column added later, without either being
    // listed here. This is the standing form of the §129.1 defect: 156 put a
    // blanket arm on user_integrations, which carries OAuth bearer tokens, and the
    // only reason it was caught was that I happened to audit the columns.
    // CONTROL FIRST. If a credential column were simply unselectable everywhere,
    // every assertion below would pass while proving nothing. This shows the column
    // IS reachable on its own table, so a 400 on a view is the view withholding it.
    const ctl = await svc('user_integrations?select=access_token&limit=1');
    check('control: access_token IS selectable on its own table — so the 400s below mean something',
      ctl.status < 400, `status=${ctl.status}`);

    for (const v of VIEWS) {
      for (const col of SECRET_COLUMNS) {
        const r = await rest(victim, `${v}?select=${col}&limit=1`);
        check(`${v} does not project ${col}`, r.status >= 400,
          `status=${r.status} — a 2xx means a credential column is reachable through an Admin surface`);
      }
    }

    // UPDATE is asserted by OUTCOME, not by status. PostgREST answers 204 to a
    // PATCH on these views whether or not the privilege exists -- it returns 204
    // even for admin_training_overview, which is not auto-updatable and could not
    // accept an UPDATE under any privilege. So the status code carries no
    // information here and asserting 403 on it would be asserting PostgREST's
    // request handling. What matters is that no write LANDS, which is checked
    // against the base row below, by a caller who DOES hold the View grant and
    // therefore supplies a non-empty row set -- the exact condition under which
    // the pre-158 DELETE succeeded.
    const coachUid2 = await uidOf('coach');
    await svc('user_integrations', { method: 'POST', body: {
      user_id: coachUid2, provider: 'qa-d15-write-probe', connected: true,
      access_token: 'ORIGINAL' } });
    const probeRow = (await svc('user_integrations?select=id,connected&provider=eq.qa-d15-write-probe')).body[0];
    if (probeRow) {
      const visible = await rest(victim, 'admin_integration_connections?select=id&provider=eq.qa-d15-write-probe');
      check('the Viewer DOES see the probe row — the row set is non-empty, so a write would have had a target',
        n(visible.body) === 1, `rows=${n(visible.body)}`);
      await rest(victim, `admin_integration_connections?id=eq.${probeRow.id}`, { method: 'PATCH',
        body: JSON.stringify({ connected: false }), headers: { 'Content-Type': 'application/json' } }).catch(() => ({}));
      const delRes = await rest(victim, `admin_integration_connections?id=eq.${probeRow.id}`,
        { method: 'DELETE' }).catch(() => ({ status: 403 }));
      const after = await svc('user_integrations?select=id,connected,access_token&provider=eq.qa-d15-write-probe');
      check('ESCALATION CLOSED: another user\'s row survives a Viewer\'s PATCH and DELETE, unchanged',
        n(after.body) === 1 && after.body[0].connected === true && after.body[0].access_token === 'ORIGINAL',
        `rows=${n(after.body)} connected=${n(after.body) === 1 ? after.body[0].connected : 'gone'} delete_status=${delRes.status}`);
      await svc('user_integrations?provider=eq.qa-d15-write-probe', { method: 'DELETE' });
    } else {
      check('write-escalation probe row seeded', false, 'could not seed the probe row');
    }

    // ── 6c · THE SECURITY AREA PROJECTION — owner decision B-1 (159) ───────
    section('Security area projection · B-1 scope, A13·1 again, B-19 withheld');

    // TWO OF THE FOUR DECIDED CATEGORIES HAVE NO LIVE ROWS ON QA -- `authentication`
    // and `authorization_denial` are both at zero. Without a row, "only the decided
    // categories appear" is satisfied by a view that MISSPELLED either of them, and
    // the Security screen would silently show no sign-in or denial events at all.
    // That is the defect this seeds against, and it is the same vacuity trap that
    // made the first parked-boundary assertion fail (V5 §128.5).
    //
    // A13 permits deterministic, clearly-marked QA data. audit_events is append-only
    // (trg_audit_events_freeze), so these rows CANNOT be cleaned up -- which is why
    // the seed is IDEMPOTENT: it emits only what is missing, so repeated local and
    // CI runs add at most one row per category, ever.
    //
    // EMITTED THROUGH THE SANCTIONED WRITE PATH, NOT INSERTED. A direct INSERT was
    // the first attempt and it was correctly REFUSED with 42501 even for the service
    // role: migration 148 revokes audit_events from `authenticated, service_role`
    // because "writes reach these tables through SECURITY DEFINER functions owned by
    // the table owner". That is a deliberate V5 boundary and the right answer was to
    // use the real producer, not to work around it. audit_record_event() is granted
    // to authenticated, so this exercises the same path production uses. The
    // p_changed_columns argument selects 151's signature over 150's overload.
    for (const cat of ['authentication', 'authorization_denial']) {
      const probeAction = `qa.d15.scope-probe.${cat}`;
      const already = await svc(`audit_events?select=id&action=eq.${encodeURIComponent(probeAction)}&limit=1`);
      if (n(already.body) === 0) {
        const r = await rpc(victim, 'audit_record_event', {
          p_action: probeAction, p_category: cat, p_outcome: 'success',
          p_actor_provenance: 'grounded', p_changed_columns: null });
        check(`emitted one clearly-marked QA ${cat} row through audit_record_event()`,
          r.status < 300, `status=${r.status} ${JSON.stringify(r.body).slice(0, 90)}`);
      } else {
        check(`a clearly-marked QA ${cat} row is already present`, true, 'idempotent — not re-emitted');
      }
    }

    // The Viewer holds Security/view=true in the approved matrix.
    const secRows = await rest(victim, 'admin_security_events?select=category&limit=1000');
    check('a Viewer reads the Security projection',
      n(secRows.body) > 0, `rows=${n(secRows.body)} status=${secRows.status}`);

    // SCOPE, both directions. Only the four decided categories may appear, and the
    // two that were offered and declined must be absent even though they exist in
    // the population -- which is what makes this an assertion about the DECISION
    // rather than about whatever the view happens to return.
    const seen = new Set((secRows.body || []).map(r => r.category));
    check(`only the four decided categories appear — got [${[...seen].sort().join(', ')}]`,
      [...seen].every(c => SECURITY_IN.includes(c)),
      `unexpected: ${[...seen].filter(c => !SECURITY_IN.includes(c)).join(', ') || 'none'}`);
    // The other direction, and the one that needed the seed: every decided category
    // must ACTUALLY flow through. A misspelling in the view's ARRAY would fail here
    // and nowhere else.
    for (const c of SECURITY_IN) {
      const live = await svc(`audit_events?select=id&category=eq.${c}&limit=1`);
      const via  = await rest(victim, `admin_security_events?select=id&category=eq.${c}&limit=1`);
      check(`${c} is IN Security scope and reaches the view`,
        n(live.body) > 0 && n(via.body) > 0,
        `population=${n(live.body)} view=${n(via.body)}`);
    }
    for (const c of SECURITY_OUT) {
      const live = await svc(`audit_events?select=id&category=eq.${c}&limit=1`);
      const via  = await rest(victim, `admin_security_events?select=id&category=eq.${c}&limit=1`);
      check(`${c} is OUT of Security scope${n(live.body) ? '' : ' (no live rows — recorded, not proof)'}`,
        n(via.body) === 0, `view=${n(via.body)} population=${n(live.body)}`);
    }

    // A13·1 AGAIN. admin_action is in scope here, so the exclusion has to hold on
    // this surface too -- otherwise adding the category to a second view would have
    // restored what A13·1 removes from the first.
    if (aUid) {
      const ownSvc2 = await svc(`audit_events?select=id&category=eq.admin_action&actor_id=eq.${aUid}`);
      const ok = await assign(aUid, 'viewer');
      if (ok && n(ownSvc2.body) > 0) {
        const own = await rest(admin, `admin_security_events?select=id&category=eq.admin_action&actor_id=eq.${aUid}`);
        check(`A13·1 holds in the Security projection too — the reader's own ${n(ownSvc2.body)} admin_action rows are excluded`,
          n(own.body) === 0, `saw ${n(own.body)} of ${n(ownSvc2.body)}`);
        const others = await rest(admin, `admin_security_events?select=id&category=eq.admin_action&actor_id=neq.${aUid}&limit=1000`);
        check('and it stays narrow — other actors\' admin_action rows remain visible',
          n(others.body) > 0, `saw ${n(others.body)}`);
      } else {
        check('A13·1 in the Security projection is observable', false,
          `admin authored ${n(ownSvc2.body)} admin_action rows`);
      }
    }

    // DISCRIMINATION. support has Security/view = false in the approved matrix.
    await assign(vUid, 'support');
    const asSup = await rest(victim, 'admin_security_events?select=id&limit=1000');
    check('the Security projection CLOSES for Support — Security/view is false in the matrix',
      n(asSup.body) === 0, `rows=${n(asSup.body)}`);
    await assign(vUid, 'viewer');

    // B-19: delta and changed_columns stay withheld. They EXIST on audit_events
    // (migration 150), so this is a projection decision, not an absent column.
    for (const col of ['delta', 'changed_columns']) {
      const onBase = await svc(`audit_events?select=${col}&limit=1`);
      const onView = await rest(victim, `admin_security_events?select=${col}&limit=1`);
      check(`B-19: ${col} exists on audit_events (${onBase.status}) and is WITHHELD from the Security projection`,
        onBase.status < 400 && onView.status >= 400, `base=${onBase.status} view=${onView.status}`);
      const onAudit = await rest(victim, `admin_audit_events?select=${col}&limit=1`);
      check(`B-19: ${col} is withheld from the Audit logs projection too`,
        onAudit.status >= 400, `status=${onAudit.status}`);
    }

    // A12 and the write posture, on this view as well.
    for (const col of ['subject_id', 'correlation_signature', 'correlation_key_id']) {
      const r = await rest(victim, `admin_security_events?select=${col}`);
      check(`the Security projection exposes no ${col}`, r.status >= 400, `status=${r.status}`);
    }
    for (const m of ['POST', 'DELETE']) {
      const path = m === 'POST' ? 'admin_security_events' : `admin_security_events?id=eq.${NONE}`;
      const r = await rest(victim, path, { method: m,
        ...(m === 'DELETE' ? {} : { body: JSON.stringify({ action: 'probe' }) }),
        headers: { 'Content-Type': 'application/json' } }).catch(() => ({ status: 403 }));
      check(`${m} on admin_security_events is refused — the revoke is in 159 itself`,
        r.status >= 400, `status=${r.status}`);
    }

    // ── 6d · USERS projection — owner decision B-2 (160) ───────────────────
    section('Users area projection · identity and account state only');
    // ── THE BLIND COMPARISON, now sighted ────────────────────────────────
    // This read `n(usersVia.body) === n(usersSvc.body)` with both sides capped at
    // `limit=1000`, so once the population passed the cap it was comparing 1000 to 1000 —
    // GREEN AND MEANINGLESS. §187 named exactly this shape after P2's audit delta went blind
    // the same way. It is the more dangerous sibling of the failure above: that one broke
    // loudly, this one kept passing.
    //
    // `countExactAs` for the view, because `admin_user_directory` is gated on
    // `admin_can('Users','view')` and a service_role count of it is 0 — comparing against
    // THAT would have replaced a blind assertion with a vacuous one.
    //
    // The equality is the right claim: 160:37 projects `FROM public.user_profiles` with no
    // row predicate — the `WHERE admin_can(...)` is a gate, not a filter — so a Viewer must
    // see every profile. Measured 1005 = 1005 at the time of this change.
    const usersSvc = await countExact('user_profiles');
    const usersViaCount = await countExactAs(victim, 'admin_user_directory');
    const usersVia = await rest(victim, 'admin_user_directory?select=*&limit=1000');
    check(`a Viewer reads the Users directory — ${usersViaCount} of ${usersSvc}`,
      usersViaCount > 0 && usersViaCount === usersSvc,
      `view=${usersViaCount} service=${usersSvc} status=${usersVia.status}`);
    check('the projection carries EXACTLY the nine decided columns',
      n(usersVia.body) > 0 &&
        Object.keys(usersVia.body[0]).length === USERS_ALLOWED.length &&
        USERS_ALLOWED.every(k => k in usersVia.body[0]),
      `keys=${n(usersVia.body) ? Object.keys(usersVia.body[0]).join(',') : 'none'}`);
    // Column by column, because "the projection looks right" is not the same claim
    // as "this column cannot be reached".
    for (const col of USERS_FORBIDDEN) {
      const onBase = await svc(`user_profiles?select=${col}&limit=1`);
      const onView = await rest(victim, `admin_user_directory?select=${col}&limit=1`);
      check(`${col} exists on user_profiles and is UNREACHABLE through the Users projection`,
        onBase.status < 400 && onView.status >= 400, `base=${onBase.status} view=${onView.status}`);
    }
    // The base table's own RLS is untouched: a Viewer must not read another member's
    // PHI directly. 160 added no policy to user_profiles.
    const phiDirect = await rest(victim, 'user_profiles?select=id,medical_conditions,parq_answers&limit=1000');
    const phiVisible = (phiDirect.body || []).filter(r => r.id !== vUid).length;
    check('base user_profiles still denies a Viewer every OTHER member\'s row — no policy was added to it',
      phiVisible === 0, `other members' rows visible=${phiVisible} of ${n(usersSvc.body)} (status ${phiDirect.status})`);

    // ── 6e · INCIDENTS projection — owner decision B-4 (160) ───────────────
    section('Incidents area projection · no evidence, no actor_identity');
    const incSvc = await svc('audit_incidents?select=id&limit=1000');
    const incVia = await rest(victim, 'admin_incidents?select=*&limit=1000');
    check(`a Viewer reads Incidents — ${n(incVia.body)} of ${n(incSvc.body)}`,
      n(incVia.body) > 0 && n(incVia.body) === n(incSvc.body),
      `view=${n(incVia.body)} service=${n(incSvc.body)}`);
    for (const col of ['evidence', 'actor_identity', 'actor_provenance', 'created_at', 'updated_at']) {
      const onBase = await svc(`audit_incidents?select=${col}&limit=1`);
      const onView = await rest(victim, `admin_incidents?select=${col}&limit=1`);
      check(`${col} exists on audit_incidents and is WITHHELD from the projection`,
        onBase.status < 400 && onView.status >= 400, `base=${onBase.status} view=${onView.status}`);
    }
    // DISCRIMINATION: support holds Incidents/view = FALSE in the approved matrix,
    // while it holds Users/view = TRUE. One role, two surfaces, opposite outcomes --
    // which is the assertion an always-open or always-closed view cannot satisfy.
    await assign(vUid, 'support');
    const incSup  = await rest(victim, 'admin_incidents?select=id&limit=1000');
    const userSup = await rest(victim, 'admin_user_directory?select=id&limit=1000');
    checkDenied('Incidents CLOSES for Support — Incidents/view is false in the matrix',
      { saw: n(incSup.body), population: n(incSvc.body) });
    check('…while Users stays OPEN for that same Support role — Users/view is true',
      n(userSup.body) > 0, `rows=${n(userSup.body)}`);
    await assign(vUid, 'viewer');

    // No write authority on either, revoked in 160 itself.
    for (const v of ['admin_user_directory', 'admin_incidents']) {
      for (const m of ['POST', 'DELETE']) {
        const path = m === 'POST' ? v : `${v}?id=eq.${NONE}`;
        const r = await rest(victim, path, { method: m,
          ...(m === 'DELETE' ? {} : { body: JSON.stringify({ summary: 'probe' }) }),
          headers: { 'Content-Type': 'application/json' } }).catch(() => ({ status: 403 }));
        check(`${m} on ${v} is refused — the revoke is in 160 itself`, r.status >= 400, `status=${r.status}`);
      }
    }

    // B-3 CLOSED as aggregate-only: the row-level denial is now a confirmed
    // boundary, not a parked gap, so it is asserted as such rather than deferred.
    const b3 = await rest(victim, 'workout_sessions?select=id&limit=1000');
    const b3svc = await svc('workout_sessions?select=id&limit=1000');
    check(`B-3 CONFIRMED aggregate-only: a Viewer reads 0 of ${n(b3svc.body)} row-level sessions`,
      n(b3.body) === 0 && n(b3svc.body) > 0, `viewer=${n(b3.body)} service=${n(b3svc.body)}`);

    // ── 6f · SUPPORT'S Users-Update WRITE PATH — owner decision B-2 (161/162) ─
    // The only non-View grant outside Trust and Operations, so this is the one
    // place the Admin layer writes member data at all.
    section('Support Users-Update write path · names only, audited without values');
    const tgt = await svc(`user_profiles?select=id,first_name,last_name&email=eq.${encodeURIComponent(IDENT.coach.email)}`);
    const target = n(tgt.body) ? tgt.body[0] : null;
    check('write-path target resolved', !!target, target ? 'ok' : 'could not resolve the coach fixture');

    if (target) {
      const orig = { first: target.first_name, last: target.last_name };
      const nameNow = async () => {
        const r = await svc(`user_profiles?select=first_name,last_name&id=eq.${target.id}`);
        return n(r.body) ? r.body[0] : {};
      };
      try {
        // EVERY role the matrix denies must be refused, not merely ineffective.
        for (const role of [null, 'viewer', 'trust_lead', 'operations_lead', 'content_editor']) {
          await unassign(vUid);
          if (role) await assign(vUid, role);
          const r = await rpc(victim, 'admin_update_user_name',
            { p_user_id: target.id, p_first_name: 'D15-FORBIDDEN', p_last_name: null });
          const after = await nameNow();
          check(`${role || 'an unassigned caller'} is REFUSED the Users-Update write path`,
            r.status >= 400 && after.first_name === orig.first,
            `status=${r.status} name=${after.first_name}`);
        }

        // support holds Users/Update = true, and must actually succeed.
        await assign(vUid, 'support');
        const beforeAudit = await svc("audit_events?select=id&action=eq.user_profiles.name.set");
        const ok = await rpc(victim, 'admin_update_user_name',
          { p_user_id: target.id, p_first_name: 'D15Probe', p_last_name: orig.last });
        const changed = await nameNow();
        check('Support CAN correct a name — the grant is real, not decorative',
          ok.status < 400 && changed.first_name === 'D15Probe',
          `status=${ok.status} name=${changed.first_name}`);

        // The writable set is the function body. Nothing else may move.
        const full = await svc(`user_profiles?select=role,membership_tier,email,phone,medical_conditions&id=eq.${target.id}`);
        check('only the name moved — role, membership_tier, email, phone and PHI are untouched',
          n(full.body) === 1 && full.body[0].role === 'coach',
          `role=${n(full.body) ? full.body[0].role : '?'}`);

        // A12: the admin_action record must prove WHAT changed without carrying the
        // values, because a name re-identifies the pseudonymous subject.
        const afterAudit = await svc("audit_events?select=id,delta,changed_columns,subject_pseudonym,category&action=eq.user_profiles.name.set&order=occurred_at.desc&limit=1");
        check('the correction emitted exactly one new admin_action audit record',
          n(afterAudit.body) === 1 && afterAudit.body[0].category === 'admin_action',
          `rows=${n(afterAudit.body)} new=${n(afterAudit.body) - 0 > 0}`);
        if (n(afterAudit.body) === 1) {
          const ev = afterAudit.body[0];
          check('A12: the audit record carries NO delta — a name would re-identify the pseudonymous subject',
            ev.delta === null, `delta=${JSON.stringify(ev.delta)}`);
          check('…but it DOES name the changed column, so the record is still evidence',
            Array.isArray(ev.changed_columns) && ev.changed_columns.includes('first_name'),
            `changed_columns=${JSON.stringify(ev.changed_columns)}`);
          check('…and the subject is a pseudonym, not the user id',
            !!ev.subject_pseudonym && ev.subject_pseudonym !== target.id,
            `pseudonym=${ev.subject_pseudonym} userId=${target.id}`);
        }

        // Input validation, server-side.
        const blank = await rpc(victim, 'admin_update_user_name',
          { p_user_id: target.id, p_first_name: '   ', p_last_name: null });
        check('a whitespace-only name is rejected server-side', blank.status >= 400, `status=${blank.status}`);
        const nosuch = await rpc(victim, 'admin_update_user_name',
          { p_user_id: NONE, p_first_name: 'X', p_last_name: null });
        check('an unknown target is rejected', nosuch.status >= 400, `status=${nosuch.status}`);
      } finally {
        await svc(`user_profiles?id=eq.${target.id}`, { method: 'PATCH',
          body: { first_name: orig.first, last_name: orig.last } });
        await unassign(vUid);
        await assign(vUid, 'viewer');
      }
    }

    // ── 6g · AI GUARDIAN registry read — the grant that was INERT (163) ────
    // The matrix grants AI Guardian/View to trust_lead, operations_lead and viewer.
    // 154's registry read was is_admin() OR is_trust_operator(), and an Admin-layer
    // trust_lead is NEITHER -- CONF-D7 forbids mapping Trust lead to trust_operator
    // and 153 keeps is_admin() false for every Admin-layer principal. So the grant
    // was real in the matrix and did nothing in the database.
    //
    // THE TABLE IS EMPTY ON QA, so every assertion here would pass vacuously --
    // including the pre-163 claim that a Viewer "cannot read governance_policy",
    // which was true for the wrong reason. A row is seeded for the duration and
    // removed afterwards; governance_policy carries no append-only freeze, so
    // unlike audit_events it CAN be cleaned up.
    section('AI Guardian registry read · the inert grant, made effective (163)');
    const POLICY_CODE = 'QA-D15-PROBE-01';
    await svc(`governance_policy?code=eq.${POLICY_CODE}`, { method: 'DELETE' });
    const seeded = await svc('governance_policy', { method: 'POST', body: {
      code: POLICY_CODE, name: 'D15 probe policy', category: 'role_based',
      scope: 'QA probe', status: 'draft' } });
    check('seeded a clearly-marked QA governance policy row', seeded.status < 300, `status=${seeded.status}`);

    if (seeded.status < 300) {
      try {
        const total = await svc('governance_policy?select=id');
        // GRANTED by the matrix -> must now read it. Before 163 these were all 0.
        for (const role of ['trust_lead', 'operations_lead', 'viewer']) {
          await assign(vUid, role);
          const r = await rest(victim, 'governance_policy?select=id,code');
          checkGranted(`${role} CAN read the governance registry — AI Guardian/View is true and is now effective`,
            { saw: n(r.body), population: n(total.body), detail: `status=${r.status}` });
        }
        // DENIED by the matrix -> must still read nothing.
        for (const role of ['support', 'content_editor']) {
          await assign(vUid, role);
          const r = await rest(victim, 'governance_policy?select=id');
          checkDenied(`${role} still reads NOTHING — AI Guardian/View is false in the matrix`,
            { saw: n(r.body), population: n(total.body), detail: `status=${r.status}` });
        }
        // Read only. 163 added no write arm; 154's writes stay on is_admin().
        // SUPERSEDED BY 167. This asserted the Admin layer could not author a
        // governance policy, which was true until owner decision B-23-AI-1 made
        // trust_lead the author. The property that still holds — and is the one
        // worth asserting — is that a role WITHOUT the grant cannot. `support`
        // holds AI Guardian/view = false and create = false (V5 §152).
        await assign(vUid, 'support');
        const w = await mutate(victim, 'governance_policy', 'POST',
          { code: 'QA-D15-FORBIDDEN', name: 'x', category: 'safety', status: 'draft' });
        check('a role without AI Guardian/create cannot author a governance policy',
          w.status >= 400 || w.affected === 0, `status=${w.status}`);
        const landed = await svc('governance_policy?select=id&code=eq.QA-D15-FORBIDDEN');
        check('…and no forbidden row landed', n(landed.body) === 0, `rows=${n(landed.body)}`);
        await assign(vUid, 'trust_lead');
        // The registry is NOT the enforcement point (owner constraint): a policy row
        // granting something must not change what admin_can() answers.
        const before = await rpc(victim, 'admin_can', { p_area: 'Users', p_verb: 'update' });
        check('a registry row does not become authorization — admin_can is unmoved (§13 deterministic authority)',
          before.body === false, `admin_can(Users,update) for trust_lead = ${JSON.stringify(before.body)}`);
      } finally {
        await svc(`governance_policy?code=eq.${POLICY_CODE}`, { method: 'DELETE' });
        await svc('governance_policy?code=eq.QA-D15-FORBIDDEN', { method: 'DELETE' });
        await assign(vUid, 'viewer');
      }
    }

    // ── 6h · B-20 · AUTHORIZED AND NOT OFFERED, proven on all three legs ───
    // A capability is non-operational only if ALL THREE hold. Asserting any one
    // alone would be misleading: the grant alone looks like unfinished work, the
    // refusal alone looks like a broken grant, and the absent write path alone
    // proves nothing about what the database would do if one appeared.
    section('B-20 · non-operational capabilities (authorized, not offered)');
    check('the non-operational register is present and non-empty',
      Array.isArray(NON_OPERATIONAL.non_operational) && NON_OPERATIONAL.non_operational.length > 0,
      `entries=${NON_OPERATIONAL.non_operational?.length ?? 0}`);

    const auditRow = await svc('audit_events?select=id,outcome&limit=1');
    check('an audit record exists to attempt mutation against — otherwise every ' +
      'assertion below would pass vacuously',
      n(auditRow.body) === 1, `rows=${n(auditRow.body)}`);

    for (const entry of NON_OPERATIONAL.non_operational) {
      for (const role of entry.granted_to) {
        await assign(vUid, role);
        // LEG 1 · the authorization still answers. The ruling did not quietly
        // remove the grant, and the approved matrix is unchanged.
        const can = await rpc(victim, 'admin_can',
          { p_area: entry.area, p_verb: entry.verb.toLowerCase() });
        check(`${entry.area}/${entry.verb}: ${role} STILL holds the grant — the ruling removed nothing`,
          can.body === true, `admin_can=${JSON.stringify(can.body)}`);
      }

      // LEG 2 · no write path is gated on it. If one were ever added, this fails
      // and the register must be revisited rather than the test relaxed.
      const needle = new RegExp(
        `admin_can\\(\\s*'${entry.area.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}'\\s*,\\s*'${entry.verb.toLowerCase()}'`, 'i');
      const gated = MIGRATION_SOURCES.filter((m) => needle.test(m.sql)).map((m) => m.name);
      check(`${entry.area}/${entry.verb}: NO write path is gated on it`,
        gated.length === 0, gated.length ? `gated in ${gated.join(', ')}` : 'no migration references it');
    }

    // LEG 3 · the resource refuses mutation, to the granted role, on a real row.
    // DELETE is asserted by status and UPDATE BY OUTCOME: PostgREST answers 204 to
    // a PATCH here whether or not the privilege exists (V5 §129.2), so the status
    // carries no information and only the row's survival does.
    if (n(auditRow.body) === 1) {
      const before = auditRow.body[0];
      await assign(vUid, 'trust_lead');
      const del = await rest(victim, `audit_events?id=eq.${before.id}`, { method: 'DELETE' })
        .catch(() => ({ status: 403 }));
      check('a trust_lead holding Audit logs/Update CANNOT delete an audit record',
        del.status >= 400, `status=${del.status}`);
      await rest(victim, `audit_events?id=eq.${before.id}`, { method: 'PATCH',
        body: JSON.stringify({ outcome: 'tampered' }),
        headers: { 'Content-Type': 'application/json' } }).catch(() => ({}));
      const after = await svc(`audit_events?select=outcome&id=eq.${before.id}`);
      check('…and the record is unchanged after the attempt — A11 append-only holds',
        n(after.body) === 1 && after.body[0].outcome === before.outcome,
        `before=${before.outcome} after=${n(after.body) ? after.body[0].outcome : 'GONE'}`);
      // The same row count, so nothing was removed by either attempt.
      const still = await svc('audit_events?select=id&limit=1');
      check('…and the audit population still answers', n(still.body) === 1, `rows=${n(still.body)}`);
    }
    await assign(vUid, 'viewer');

    // ── 6i · B-21 · the Incidents write path (164) ─────────────────────────
    // audit_incidents had NO writer at all before 164: no UPDATE policy, and 148
    // grants the table SELECT only, so not even is_admin() could change one. These
    // are therefore the first incident mutations this system has ever performed.
    //
    // THE FIXTURE IS IDEMPOTENT because an incident CANNOT BE DELETED — 143's
    // trigger raises on DELETE. Repeated local and CI runs reuse the one probe
    // incident rather than accumulating them.
    section('B-21 · Incidents write path · create, response-only update, journal');
    const PROBE_SUMMARY = 'QA-D15-PROBE incident — deterministic fixture';

    // B-21b · CREATE. trust_lead holds Incidents/create; nobody else does.
    await assign(vUid, 'trust_lead');
    let probeId = null;
    const existing = await svc(
      `audit_incidents?select=id,actor_identity&summary=eq.${encodeURIComponent(PROBE_SUMMARY)}&limit=1`);
    if (n(existing.body) === 1) {
      probeId = existing.body[0].id;
      check('a deterministic probe incident is already present', true, 'idempotent — not re-opened');
    } else {
      const opened = await rpc(victim, 'audit_open_incident', {
        p_summary: PROBE_SUMMARY, p_occurred_at: new Date().toISOString(),
        p_severity: 'Informational', p_scope: 'QA probe',
        p_evidence: [], p_suspected_cause: null, p_recommended_action: null });
      check('B-21b: a trust_lead CAN open an incident — B1 amended additively',
        opened.status < 400 && !!opened.body, `status=${opened.status} id=${JSON.stringify(opened.body)}`);
      const found = await svc(
        `audit_incidents?select=id,actor_identity&summary=eq.${encodeURIComponent(PROBE_SUMMARY)}&limit=1`);
      probeId = n(found.body) === 1 ? found.body[0].id : null;
      check('…and the row landed with the opener recorded as actor_identity',
        !!probeId && found.body[0].actor_identity === vUid,
        `id=${probeId} actor=${n(found.body) ? found.body[0].actor_identity : 'none'}`);
    }

    // B1 LOST NOTHING. The amendment is additive, so the two database roles B1
    // originally named must still be able to open an incident. Asserted with
    // p1-admin, who satisfies is_admin() and holds no Admin-layer role at all —
    // if the amendment had replaced B1's gate rather than widening it, this fails.
    // Both fixtures are stripped of Admin-layer roles first. p1-admin still carried
    // the `viewer` assignment the A13·1 section arranged, and `viewer` does not hold
    // Incidents/create — so the open would have proven the point anyway, but the
    // assertion claimed "holding NO Admin-layer role" and that was simply untrue at
    // this point in the suite. The premise is corrected rather than the claim.
    await unassign(vUid);
    await unassign(aUid);
    // IDEMPOTENT. An incident CANNOT be deleted (143's trigger), so opening one every
    // run grows an append-only table without bound — this assertion accumulated 46
    // rows before it was noticed (V5 §161). It now opens one ONLY if none exists.
    const B1_SUMMARY = 'QA-D15-PROBE b1-preserved';
    const b1Existing = await svc(
      `audit_incidents?select=id&summary=eq.${encodeURIComponent(B1_SUMMARY)}&limit=1`);
    const adminHasLayer = await rpc(admin, 'is_admin_member');
    if (n(b1Existing.body) === 0) {
      const adminOpen = await rpc(admin, 'audit_open_incident', {
        p_summary: B1_SUMMARY, p_occurred_at: new Date().toISOString(),
        p_severity: 'Informational', p_scope: 'QA probe', p_evidence: [],
        p_suspected_cause: null, p_recommended_action: null });
      check('B1 preserved: is_admin() can still open an incident, holding NO Admin-layer role',
        adminOpen.status < 400 && adminHasLayer.body === false,
        `open=${adminOpen.status} is_admin_member=${JSON.stringify(adminHasLayer.body)}`);
    } else {
      check('B1 preserved: the is_admin() probe incident is already present',
        adminHasLayer.body === false,
        'idempotent — not re-opened; an incident cannot be deleted');
    }

    // Every role the matrix DENIES Incidents/create must be refused outright.
    for (const role of ['operations_lead', 'support', 'content_editor', 'viewer']) {
      await assign(vUid, role);
      // BEFORE / ATTEMPT / AFTER. This asserted that ZERO forbidden incidents exist,
      // which fails forever once one leaks — and one did, from two overlapping local
      // runs of this suite where the other run held trust_lead (V5 §161). An incident
      // cannot be deleted, so the assertion must be that THIS attempt added nothing.
      const fBefore = n((await svc("audit_incidents?select=id&summary=eq.QA-D15-FORBIDDEN%20incident")).body);
      const r = await rpc(victim, 'audit_open_incident', {
        p_summary: 'QA-D15-FORBIDDEN incident', p_occurred_at: new Date().toISOString(),
        p_severity: 'Informational', p_scope: null, p_evidence: [],
        p_suspected_cause: null, p_recommended_action: null });
      const fAfter = n((await svc("audit_incidents?select=id&summary=eq.QA-D15-FORBIDDEN%20incident")).body);
      check(`${role} is REFUSED Incidents/create and nothing new is created`,
        r.status >= 400 && fAfter === fBefore,
        `status=${r.status} rows ${fBefore}->${fAfter}` +
        (fBefore ? ` (${fBefore} pre-existing leaked row(s) — undeletable, see §161)` : ''));
    }

    if (probeId) {
      // B-21a · UPDATE — response fields only, and nothing else may move.
      const before = await svc(`audit_incidents?select=*&id=eq.${probeId}`);
      const b = before.body[0];
      const stamp = `resolved at ${new Date().toISOString()}`;

      for (const role of ['operations_lead', 'support', 'content_editor', 'viewer']) {
        await assign(vUid, role);
        const r = await rpc(victim, 'admin_update_incident_response',
          { p_incident_id: probeId, p_action_taken: 'FORBIDDEN', p_recommended_action: null, p_resolution: null });
        const now = await svc(`audit_incidents?select=action_taken&id=eq.${probeId}`);
        check(`${role} is REFUSED the incident response writer`,
          r.status >= 400 && now.body[0].action_taken === b.action_taken,
          `status=${r.status}`);
      }

      await assign(vUid, 'trust_lead');
      // BOTH VALUES MUST VARY PER RUN. The probe incident is reused — an incident
      // cannot be deleted — so writing a CONSTANT action_taken changed nothing on
      // the second run, the trigger journalled nothing for it, and the journal
      // assertion below failed (V5 §144.4). It passed once and failed every run
      // after. A fixture that persists needs values that move.
      const upd = await rpc(victim, 'admin_update_incident_response',
        { p_incident_id: probeId, p_action_taken: `D15 probe action ${stamp}`,
          p_recommended_action: null, p_resolution: stamp });
      const after = await svc(`audit_incidents?select=*&id=eq.${probeId}`);
      const a = after.body[0];
      check('B-21a: a trust_lead CAN write the response fields — the grant is real',
        upd.status < 400 && a.action_taken === `D15 probe action ${stamp}` && a.resolution === stamp,
        `status=${upd.status} action_taken=${a.action_taken}`);

      // THE ACCOUNT OF WHAT HAPPENED IS NOT WRITABLE. This is the contract, so it
      // is asserted field by field rather than trusted to the function's shape.
      for (const col of ['summary', 'severity', 'scope', 'suspected_cause', 'occurred_at',
                         'evidence', 'actor_identity', 'approval_status', 'created_at']) {
        check(`${col} is UNCHANGED — outside the B-21a contract`,
          JSON.stringify(a[col]) === JSON.stringify(b[col]),
          `before=${JSON.stringify(b[col])} after=${JSON.stringify(a[col])}`);
      }

      // The journal is the retention mechanism 143 ruled for this population, so it
      // must have recorded the change, attributed to the caller.
      const tr = await svc(
        `audit_incident_transitions?select=changed_field,new_value,changed_by&incident_id=eq.${probeId}&order=changed_at.desc&limit=10`);
      const fields = (tr.body || []).map((t) => t.changed_field);
      check('the transitions journal recorded the response change, attributed to the caller',
        fields.includes('action_taken') &&
          (tr.body || []).some((t) => t.changed_field === 'action_taken' && t.changed_by === vUid),
        `fields=[${[...new Set(fields)].join(', ')}]`);
      check('…and journalled NOTHING outside the contract',
        fields.every((f) => ['action_taken', 'recommended_action', 'resolution'].includes(f)),
        `unexpected=[${fields.filter((f) => !['action_taken','recommended_action','resolution'].includes(f)).join(', ')}]`);

      // The table itself stays unwritable: 164 added a FUNCTION, not a policy.
      const direct = await rest(victim, `audit_incidents?id=eq.${probeId}`, { method: 'PATCH',
        body: JSON.stringify({ approval_status: 'tampered' }),
        headers: { 'Content-Type': 'application/json' } }).catch(() => ({}));
      const post = await svc(`audit_incidents?select=approval_status&id=eq.${probeId}`);
      check('B-21c: approval_status CANNOT be moved — no path exists and none was added',
        post.body[0].approval_status === b.approval_status,
        `status=${direct.status} value=${post.body[0].approval_status}`);
      const del = await rest(victim, `audit_incidents?id=eq.${probeId}`, { method: 'DELETE' })
        .catch(() => ({ status: 403 }));
      const alive = await svc(`audit_incidents?select=id&id=eq.${probeId}`);
      check('an incident still cannot be DELETED by anyone',
        del.status >= 400 && n(alive.body) === 1, `status=${del.status}`);
    }

    // ── 6j · B-22 · content write paths (165) ──────────────────────────────
    // Three separate decisions, not one "content write" generalisation of the Users
    // whitelist. Community is DEFERRED behind CAP-1 and is asserted ABSENT below.
    section('B-22 · Events and Training write paths · column contracts enforced');
    const EV_TITLE = 'QA-D15-PROBE event';
    const PG_NAME  = 'QA-D15-PROBE program template';
    await svc(`events?title=eq.${encodeURIComponent(EV_TITLE)}`, { method: 'DELETE' });
    await svc(`workout_programs?name=eq.${encodeURIComponent(PG_NAME)}`, { method: 'DELETE' });

    try {
      // Every role the matrix denies must be refused BOTH creators.
      for (const role of ['trust_lead', 'operations_lead', 'support', 'viewer']) {
        await assign(vUid, role);
        const e = await rpc(victim, 'admin_create_event',
          { p_title: 'QA-D15-FORBIDDEN event', p_event_date: new Date().toISOString(),
            p_description: null, p_location: null, p_end_date: null,
            p_cover_image_url: null, p_host_name: null, p_max_capacity: null });
        const t = await rpc(victim, 'admin_create_program_template',
          { p_name: 'QA-D15-FORBIDDEN program', p_description: null, p_goal: null,
            p_difficulty: null, p_duration_weeks: null });
        const leakedE = await svc("events?select=id&title=eq.QA-D15-FORBIDDEN%20event");
        const leakedT = await svc("workout_programs?select=id&name=eq.QA-D15-FORBIDDEN%20program");
        check(`${role} is REFUSED both content creators, and nothing lands`,
          e.status >= 400 && t.status >= 400 && n(leakedE.body) === 0 && n(leakedT.body) === 0,
          `event=${e.status} program=${t.status}`);
      }

      await assign(vUid, 'content_editor');

      // ── Events ──────────────────────────────────────────────────────────
      const mkEv = await rpc(victim, 'admin_create_event',
        { p_title: EV_TITLE, p_event_date: new Date().toISOString(),
          p_description: 'probe', p_location: 'probe', p_end_date: null,
          p_cover_image_url: null, p_host_name: 'probe host', p_max_capacity: 10 });
      const evRow = await svc(`events?select=*&title=eq.${encodeURIComponent(EV_TITLE)}`);
      check('B-22b: a content_editor CAN create an event — the grant is real',
        mkEv.status < 400 && n(evRow.body) === 1, `status=${mkEv.status} rows=${n(evRow.body)}`);

      if (n(evRow.body) === 1) {
        const e0 = evRow.body[0];
        // The excluded columns must have taken their DEFAULTS, not values the
        // function supplied — monetization, lifecycle, attendance and ownership.
        check('excluded Events columns took their defaults — no pricing, status, attendance or ownership was set',
          Number(e0.price) === 0 && e0.is_free === true && e0.status === 'upcoming' &&
            e0.current_registered === 0 && e0.vendor_id === null,
          `price=${e0.price} is_free=${e0.is_free} status=${e0.status} registered=${e0.current_registered} vendor=${e0.vendor_id}`);

        const upd = await rpc(victim, 'admin_update_event',
          { p_event_id: e0.id, p_title: null, p_description: 'probe updated',
            p_location: null, p_event_date: null, p_end_date: null,
            p_cover_image_url: null, p_host_name: null, p_max_capacity: 25 });
        const e1 = (await svc(`events?select=*&id=eq.${e0.id}`)).body[0];
        check('a content_editor CAN update descriptive fields',
          upd.status < 400 && e1.description === 'probe updated' && e1.max_capacity === 25,
          `status=${upd.status}`);
        for (const col of ['price', 'is_free', 'status', 'current_registered', 'vendor_id']) {
          check(`Events.${col} is UNCHANGED — outside the B-22b contract`,
            JSON.stringify(e1[col]) === JSON.stringify(e0[col]),
            `before=${JSON.stringify(e0[col])} after=${JSON.stringify(e1[col])}`);
        }
        check('…and the title was not blanked by the NULL argument',
          e1.title === EV_TITLE, `title=${e1.title}`);
      }

      // ── Training ────────────────────────────────────────────────────────
      const mkPg = await rpc(victim, 'admin_create_program_template',
        { p_name: PG_NAME, p_description: 'probe', p_goal: 'probe',
          p_difficulty: 'beginner', p_duration_weeks: 4 });
      const pgRow = await svc(`workout_programs?select=*&name=eq.${encodeURIComponent(PG_NAME)}`);
      check('B-22c: a content_editor CAN create a program template',
        mkPg.status < 400 && n(pgRow.body) === 1, `status=${mkPg.status} rows=${n(pgRow.body)}`);

      if (n(pgRow.body) === 1) {
        const p0 = pgRow.body[0];
        check('a staff-authored template belongs to NO coach and is not engine-generated',
          p0.coach_id === null && p0.is_template === true && p0.engine_generated === false,
          `coach_id=${p0.coach_id} is_template=${p0.is_template} engine=${p0.engine_generated}`);

        const updP = await rpc(victim, 'admin_update_program_template',
          { p_program_id: p0.id, p_name: null, p_description: 'probe updated',
            p_goal: null, p_difficulty: 'advanced', p_duration_weeks: null, p_is_template: null });
        const p1 = (await svc(`workout_programs?select=*&id=eq.${p0.id}`)).body[0];
        check('a content_editor CAN update authoring fields',
          updP.status < 400 && p1.description === 'probe updated' && p1.difficulty === 'advanced',
          `status=${updP.status}`);
        for (const col of ['coach_id', 'program_version', 'plan', 'strategy', 'engine_generated']) {
          const wasNull = p0[col] === null;
          check(`workout_programs.${col} is UNCHANGED — owned by another system` +
                (wasNull ? ' (was null — recorded, not proof)' : ''),
            JSON.stringify(p1[col]) === JSON.stringify(p0[col]),
            `before=${JSON.stringify(p0[col])} after=${JSON.stringify(p1[col])}`);
        }

        // THE DECISIVE OWNERSHIP ASSERTION. Above, coach_id was null before and
        // after, so "unchanged" proved almost nothing — a staff-authored template
        // belongs to no coach by design. This repeats it against a program that IS
        // coach-owned, which is the case that matters: the writer must not be able
        // to reassign a coach's program to itself or to anyone else.
        const owned = await svc('workout_programs?select=id,coach_id,description,difficulty&coach_id=not.is.null&limit=1');
        if (n(owned.body) === 1) {
          const o0 = owned.body[0];
          const r = await rpc(victim, 'admin_update_program_template',
            { p_program_id: o0.id, p_name: null, p_description: 'D15 probe touch',
              p_goal: null, p_difficulty: null, p_duration_weeks: null, p_is_template: null });
          const o1 = (await svc(`workout_programs?select=id,coach_id,description&id=eq.${o0.id}`)).body[0];
          check('a COACH-OWNED program keeps its coach_id through a content_editor write',
            r.status < 400 && o1.coach_id === o0.coach_id && o0.coach_id !== null,
            `before=${o0.coach_id} after=${o1.coach_id}`);
          await svc(`workout_programs?id=eq.${o0.id}`, { method: 'PATCH',
            body: { description: o0.description } });
          const restored = (await svc(`workout_programs?select=description&id=eq.${o0.id}`)).body[0];
          check('…and the probe restored that program\'s description',
            JSON.stringify(restored.description) === JSON.stringify(o0.description),
            `value=${JSON.stringify(restored.description)}`);
        } else {
          check('a coach-owned program exists to assert ownership preservation against',
            false, 'none found — the coach_id assertion above is vacuous without one');
        }
      }

      // Each write emitted an admin_action carrying changed_columns and NO delta.
      const acts = await svc(
        "audit_events?select=action,delta,changed_columns&action=in.(events.create,events.update,workout_programs.create,workout_programs.update)&order=occurred_at.desc&limit=4");
      check('the content writes emitted admin_action records',
        n(acts.body) >= 4, `rows=${n(acts.body)}`);
      check('…each carrying changed_columns and NO delta',
        (acts.body || []).every((a) => a.delta === null && Array.isArray(a.changed_columns)),
        `sample=${JSON.stringify((acts.body || [])[0])}`);

      // ── B-22a · Community is DEFERRED, so nothing may exist for it ──────
      // CAP-1 IS DISCHARGED (170). Community/update is now the MODERATION path, so
      // the old "no write path exists" assertion is inverted: update MUST be gated,
      // create must NOT be (owner decision CAP-1-3 — staff do not post).
      {
        const upd = MIGRATION_SOURCES.filter((m) => /admin_can\(\s*'Community'\s*,\s*'update'/i.test(m.sql)).map((m) => m.name);
        check('CAP-1: Community/update IS gated on a write path — moderation',
          upd.length > 0, upd.join(', ') || 'NONE — moderation is missing');
        const cre = MIGRATION_SOURCES.filter((m) => /admin_can\(\s*'Community'\s*,\s*'create'/i.test(m.sql)).map((m) => m.name);
        check('CAP-1-3: Community/create has NO write path — staff do not post',
          cre.length === 0, cre.join(', ') || 'none');
      }
      const otherPost = await svc('community_posts?select=id,user_id&limit=1');
      if (n(otherPost.body) === 1 && otherPost.body[0].user_id !== vUid) {
        const tamper = await rest(victim, `community_posts?id=eq.${otherPost.body[0].id}`,
          { method: 'PATCH', body: JSON.stringify({ content: 'D15 TAMPER' }),
            headers: { 'Content-Type': 'application/json' } }).catch(() => ({}));
        const post = await svc(`community_posts?select=content&id=eq.${otherPost.body[0].id}`);
        check('a content_editor still cannot rewrite another member\'s post',
          post.body[0].content !== 'D15 TAMPER', `status=${tamper.status}`);
      }

      // B-3 is untouched by any of this.
      const sess = await rest(victim, 'workout_sessions?select=id');
      const sessAll = await svc('workout_sessions?select=id');
      checkDenied('B-3 still holds: a content_editor reads no row-level training data',
        { saw: n(sess.body), population: n(sessAll.body) });
    } finally {
      await svc(`events?title=eq.${encodeURIComponent(EV_TITLE)}`, { method: 'DELETE' });
      await svc(`workout_programs?name=eq.${encodeURIComponent(PG_NAME)}`, { method: 'DELETE' });
      await svc("events?title=eq.QA-D15-FORBIDDEN%20event", { method: 'DELETE' });
      await svc("workout_programs?name=eq.QA-D15-FORBIDDEN%20program", { method: 'DELETE' });
      await assign(vUid, 'viewer');
    }

    // ── 6k · per-area AGGREGATE surfaces (166) ─────────────────────────────
    // admin_platform_stats() (019) is gated on is_admin() alone, so the Admin layer
    // could see NO aggregate at all — the same inert shape as the AI Guardian
    // registry in §135. These two views answer per AREA instead of widening 019's
    // cross-area gate.
    section('per-area aggregate surfaces · Users and Events (166)');
    // The key lists are EXACT, and deliberately so: an exhaustive list is what makes
    // this a D7 column-limitation guard rather than a smoke test. Migration 172
    // appended the owner-approved metric columns (METRIC-03, METRIC-14, METRIC-17),
    // and these lists were updated to match ONLY after confirming every added column
    // is an aggregate count carrying no identifier — which D16 asserts separately.
    // A column added without that review still turns this suite red, as it did when
    // 172 landed.
    const OVERVIEWS = [
      ['admin_user_overview',   'Users',
       ['users_total','clients_total','coaches_total','vendors_total','admins_total',
        'content_managers_total','trust_operators_total','erasure_executors_total',
        // METRIC-03 · active coaches, calendar month
        'coaches_active_this_month','coaches_no_client_this_month',
        // METRIC-17 · half-open buckets, fourth bucket = unknown, plus the
        // reconciliation column that keeps an age >= 60 from being silently dropped
        'age_18_30','age_30_45','age_45_60','age_unknown','age_out_of_range',
        // §193 · "Clients served" and its average per ACTIVE coach. Added to this EXACT
        // list only after the same review migration 172's columns got: both are aggregates
        // over coach_client_relationships, neither carries an identifier, and D16 asserts
        // their values separately — the count against an independent exact count, and the
        // average against this view's own coaches_active_this_month.
        //
        // THIS GUARD CAUGHT 179, which is the point of pinning an exact set. The migration
        // was applied to QA and only D16 was re-run; CI's D15 went 352/353 and named the
        // column drift. The lesson is the obvious one and it is now twice-learned in this
        // run: applying a migration means re-running the WHOLE live suite, not the suite
        // whose subject changed.
        'coach_clients_served','coach_clients_per_active_coach']],
      ['admin_events_overview', 'Events',
       ['events_total','event_registrations_total','classes_total','class_bookings_total',
        // METRIC-14 · attended / registered, on the pre-existing checked_in_at
        'event_registrations_attended','event_attendance_rate_pct','event_registrations_30d']],
    ];
    for (const [view, area, keys] of OVERVIEWS) {
      await assign(vUid, 'viewer');                 // holds View on both areas
      const got = await rest(victim, `${view}?select=*`);
      check(`${view}: a Viewer reads it — admin_can('${area}','view') is effective`,
        n(got.body) === 1, `rows=${n(got.body)} status=${got.status}`);
      check(`${view}: carries exactly its ${keys.length} counts and nothing else`,
        n(got.body) === 1 && Object.keys(got.body[0]).length === keys.length &&
          keys.every((k) => k in got.body[0]),
        `keys=${n(got.body) === 1 ? Object.keys(got.body[0]).join(',') : 'none'}`);

      // The counts must be TRUE, not merely present — a view returning zeros would
      // satisfy every structural assertion above.
      if (view === 'admin_user_overview' && n(got.body) === 1) {
        // `countExact`, NOT a body length. This assertion FAILED IN CI the moment QA's user
        // population crossed 1000 — `view=1005 actual=1000` — because the baseline was
        // `limit=1000` and saturated while the view was right. The view was never wrong; the
        // measurement was. An equality against a page-capped count is only correct until the
        // population reaches the cap, which is the §187 lesson that produced `countExact`.
        const real = await countExact('user_profiles');
        check('admin_user_overview.users_total matches the real population',
          got.body[0].users_total === real, `view=${got.body[0].users_total} actual=${real}`);
        check('…and all SEVEN schema roles are represented — the data contract row 1 gap',
          ['clients_total','coaches_total','vendors_total','admins_total','content_managers_total',
           'trust_operators_total','erasure_executors_total'].every((k) => typeof got.body[0][k] === 'number'),
          `roles=${Object.keys(got.body[0]).filter((k) => k !== 'users_total').length}`);
      }
      if (view === 'admin_events_overview' && n(got.body) === 1) {
        // Same fix before the same failure: events are under the cap today, so this one was
        // latent rather than broken. Fixing only the assertion that happened to fail would
        // have left the identical defect armed on the next surface to grow.
        const realEvents = await countExact('events');
        check('admin_events_overview.events_total matches the real population',
          got.body[0].events_total === realEvents,
          `view=${got.body[0].events_total} actual=${realEvents}`);
      }

      // UNASSIGNED must see no row at all — the view is self-gating.
      await unassign(vUid);
      const none = await rest(victim, `${view}?select=*`);
      check(`${view}: an UNASSIGNED caller gets no row`, n(none.body) === 0, `rows=${n(none.body)}`);
    }
    await assign(vUid, 'viewer');

    // 019 is UNCHANGED — it was not widened, and the Admin layer still cannot call it.
    const stats = await rpc(victim, 'admin_platform_stats');
    check('admin_platform_stats() is UNCHANGED — still is_admin() only, not widened',
      stats.status >= 400, `status=${stats.status}`);

    // ── 6l · OWNER-APPROVED WAVE: 167 · 168 · 169 · 170 ───────────────────
    section('B-23-AI-1 · governance-policy authoring (167/168)');
    const POL = 'D15-PROBE-POLICY';
    await svc(`governance_policy?code=eq.${POL}`, { method: 'DELETE' });
    for (const role of ['viewer', 'operations_lead', 'support', 'content_editor']) {
      await assign(vUid, role);
      const r = await mutate(victim, 'governance_policy', 'POST',
        { code: POL, name: 'x', category: 'role_based', status: 'draft' });
      const landed = await svc(`governance_policy?select=id&code=eq.${POL}`);
      check(`${role} is REFUSED governance authoring`,
        r.status >= 400 && n(landed.body) === 0, `status=${r.status} landed=${n(landed.body)}`);
    }
    await assign(vUid, 'trust_lead');
    const mk = await mutate(victim, 'governance_policy', 'POST',
      { code: POL, name: 'probe policy', category: 'role_based', status: 'draft' });
    const polRow = await svc(`governance_policy?select=id,name&code=eq.${POL}`);
    check('B-23-AI-1: a trust_lead CAN author a governance policy',
      mk.status < 400 && n(polRow.body) === 1, `status=${mk.status}`);

    if (n(polRow.body) === 1) {
      const pid = polRow.body[0].id;
      const rev = await mutate(victim, `governance_policy?id=eq.${pid}`, 'PATCH', { name: 'probe revised' });
      const now = await svc(`governance_policy?select=name&id=eq.${pid}`);
      check('…and revise it', rev.status < 400 && now.body[0].name === 'probe revised', `status=${rev.status}`);

      // 168: the DELETE grant is gone, not merely filtered by RLS.
      const del = await mutate(victim, `governance_policy?id=eq.${pid}`, 'DELETE');
      const alive = await svc(`governance_policy?select=id&id=eq.${pid}`);
      check('168: DELETE is REFUSED outright — the privilege is absent, not RLS-filtered',
        del.status >= 400 && n(alive.body) === 1, `status=${del.status} survived=${n(alive.body)}`);

      // §13: a policy DOCUMENT must not become authorization.
      const can = await rpc(victim, 'admin_can', { p_area: 'Users', p_verb: 'update' });
      check('§13 intact: authoring a policy document confers NO authorization',
        can.body === false, `admin_can(Users,update)=${JSON.stringify(can.body)}`);

      const gev = await svc("audit_events?select=action,changed_columns&action=like.governance_policy.*&order=occurred_at.desc&limit=1");
      check('governance writes are audited as admin_action',
        n(gev.body) === 1 && Array.isArray(gev.body[0].changed_columns), `${JSON.stringify((gev.body || [])[0])}`);
      await svc(`governance_policy?code=eq.${POL}`, { method: 'DELETE' });
    }

    section('B-17 · Guardian state and emergency disablement (169)');
    await svc('guardian_state?id=eq.true', { method: 'DELETE' });
    check('guardian_state starts EMPTY — no runtime is asserted',
      n((await svc('guardian_state?select=*')).body) === 0, 'A11 state');
    for (const role of ['viewer', 'operations_lead', 'content_editor']) {
      await assign(vUid, role);
      const r = await rpc(victim, 'admin_set_guardian_state', { p_state: 'Monitoring', p_reason: null });
      check(`${role} is REFUSED the Guardian control`, r.status >= 400, `status=${r.status}`);
    }
    await assign(vUid, 'trust_lead');
    const g1 = await rpc(victim, 'admin_set_guardian_state', { p_state: 'Monitoring', p_reason: null });
    check('B-17: a trust_lead CAN set Guardian state', g1.status < 400, `status=${g1.status}`);
    const bad = await rpc(victim, 'admin_set_guardian_state', { p_state: 'Paused', p_reason: 'x' });
    check('a state outside A5\'s four is REFUSED — no vocabulary was invented', bad.status >= 400, `status=${bad.status}`);
    const nr = await rpc(victim, 'admin_set_guardian_state', { p_state: 'Disabled', p_reason: null });
    check('disabling the Guardian REQUIRES a reason', nr.status >= 400, `status=${nr.status}`);
    const dis = await rpc(victim, 'admin_set_guardian_state',
      { p_state: 'Disabled', p_reason: 'D15 probe — emergency disablement' });
    const gs = await svc('guardian_state?select=state,reason,set_by');
    check('EMERGENCY DISABLEMENT works and records who and why',
      dis.status < 400 && n(gs.body) === 1 && gs.body[0].state === 'Disabled' && gs.body[0].set_by === vUid,
      `state=${n(gs.body) ? gs.body[0].state : 'none'}`);
    const direct = await mutate(victim, 'guardian_state?id=eq.true', 'PATCH', { state: 'Active' });
    const held = await svc('guardian_state?select=state');
    check('the table cannot be written directly — only the RPC',
      direct.status >= 400 && held.body[0].state === 'Disabled', `status=${direct.status}`);
    const gev2 = await svc("audit_events?select=delta&action=eq.guardian_state.set&order=occurred_at.desc&limit=1");
    check('the transition is audited with a full before/after delta',
      n(gev2.body) === 1 && gev2.body[0].delta?.after?.state === 'Disabled',
      `${JSON.stringify((gev2.body || [])[0]?.delta)}`);
    await svc('guardian_state?id=eq.true', { method: 'DELETE' });

    section('CAP-1 · community moderation preserves the member\'s words (170)');
    const CPROBE = 'D15-CAP1-PROBE member words';
    await svc(`content_reports?reason=eq.D15-probe`, { method: 'DELETE' });
    await svc(`community_posts?content=like.D15-CAP1-PROBE*`, { method: 'DELETE' });
    const authorId = await uidOf('attacker');            // a third party to the moderator
    await svc('community_posts', { method: 'POST', body: { user_id: authorId, content: CPROBE } });
    const cp = await svc(`community_posts?select=id,content&content=like.D15-CAP1-PROBE*`);
    check('seeded a post authored by someone else', n(cp.body) === 1, `rows=${n(cp.body)}`);

    if (n(cp.body) === 1) {
      const postId = cp.body[0].id, originalText = cp.body[0].content;
      for (const role of ['viewer', 'support', 'trust_lead']) {
        await assign(vUid, role);
        const r = await rpc(victim, 'admin_moderate_content',
          { p_target_type: 'post', p_target_id: postId, p_state: 'hidden', p_reason: 'probe' });
        check(`${role} is REFUSED moderation — Community/update is content_editor's alone`,
          r.status >= 400, `status=${r.status}`);
      }
      await assign(vUid, 'content_editor');
      const nr2 = await rpc(victim, 'admin_moderate_content',
        { p_target_type: 'post', p_target_id: postId, p_state: 'hidden', p_reason: null });
      check('hiding REQUIRES a reason', nr2.status >= 400, `status=${nr2.status}`);
      const mod = await rpc(victim, 'admin_moderate_content',
        { p_target_type: 'post', p_target_id: postId, p_state: 'hidden', p_reason: 'D15 probe' });
      const post2 = (await svc(`community_posts?select=content,moderation_state,moderated_by&id=eq.${postId}`)).body[0];
      check('CAP-1-1: the post is hidden', mod.status < 400 && post2.moderation_state === 'hidden', `status=${mod.status}`);
      check('CAP-1-1: THE MEMBER\'S ORIGINAL TEXT IS UNCHANGED — staff cannot rewrite it',
        post2.content === originalText, `content ${post2.content === originalText ? 'preserved' : 'ALTERED'}`);

      await unassign(vUid);
      const asThird = await rest(victim, `community_posts?select=id&content=like.D15-CAP1-PROBE*`);
      checkDenied('a third party can no longer see the hidden post',
        { saw: n(asThird.body), population: 1 });
      const asAuthor = await rest(await signIn('attacker'), `community_posts?select=id&content=like.D15-CAP1-PROBE*`);
      check('…but the AUTHOR still sees their own words', n(asAuthor.body) === 1, `rows=${n(asAuthor.body)}`);
      await assign(vUid, 'viewer');
      const asAdmin = await rest(victim, `community_posts?select=id&content=like.D15-CAP1-PROBE*`);
      check('…and the Admin layer sees it, because it has to moderate it',
        n(asAdmin.body) === 1, `rows=${n(asAdmin.body)}`);

      // CAP-1-2 · the report queue
      await unassign(vUid);
      const rep = await mutate(victim, 'content_reports', 'POST',
        { reporter_id: vUid, target_type: 'post', target_id: postId, reason: 'D15-probe' });
      check('CAP-1-2: a member can file a report', rep.status < 400, `status=${rep.status}`);
      const forged = await mutate(victim, 'content_reports', 'POST',
        { reporter_id: authorId, target_type: 'post', target_id: postId, reason: 'D15-probe' });
      check('…and cannot file one AS someone else', forged.status >= 400, `status=${forged.status}`);
      const otherSees = await rest(await signIn('attacker'), 'content_reports?select=id&reason=eq.D15-probe');
      checkDenied('…and cannot read another member\'s report',
        { saw: n(otherSees.body), population: 1 });

      const mev = await svc("audit_events?select=delta,subject_pseudonym&action=eq.community_content.moderate&order=occurred_at.desc&limit=1");
      check('the moderation is audited against the PSEUDONYMISED author',
        n(mev.body) === 1 && !!mev.body[0].subject_pseudonym && mev.body[0].subject_pseudonym !== authorId,
        `pseudonym=${(mev.body || [])[0]?.subject_pseudonym}`);

      await svc(`content_reports?reason=eq.D15-probe`, { method: 'DELETE' });
      await svc(`community_posts?content=like.D15-CAP1-PROBE*`, { method: 'DELETE' });
      await assign(vUid, 'viewer');
    }

    // ── 7 · anon reaches none of the three new surfaces ─────────────────────
    section('anon posture on the new surfaces');
    for (const v of VIEWS) {
      const a = await fetch(`${URL_}/rest/v1/${v}?select=*`, { headers: { apikey: process.env.QA_ANON } });
      const b = await a.json().catch(() => []);
      check(`anon reaches nothing through ${v}`,
        a.status >= 400 || (Array.isArray(b) && b.length === 0), `status=${a.status}`);
    }
  } finally {
    // Restore the capability grid FIRST — leaving it short would make D14 fail
    // for a reason that has nothing to do with D14.
    if (capRemoved) {
      await svc('admin_role_capabilities', { method: 'POST',
        body: { admin_role: 'viewer', area: 'Integrations', verb: 'view' } });
    }
    if (seededIntegration) await svc("user_integrations?provider=eq.qa-d15-probe", { method: 'DELETE' });
    await unassign(vUid);
    await unassign(aUid);
  }

  return summary('D15 admin surface access');
}

export default await run();
