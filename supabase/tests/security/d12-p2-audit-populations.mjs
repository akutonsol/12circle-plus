// P2 · the four audit/observability populations, the identity mapping, severance
// and the audit read path — LIVE against QA.
//
// Covers migrations 142–147. Every assertion states the SECURE expectation and
// cites the ruling it comes from; V5 §75–§79 carry the specification and the
// traceability matrix.
//
// ONE PROPERTY OF THIS SUITE IS UNUSUAL AND DELIBERATE: it cannot clean up after
// itself. audit_events is append-only by A11 and its freeze trigger refuses
// DELETE to every caller including service_role, so the rows this suite writes
// are PERMANENT on QA. That is the population behaving as ruled, not a leak. Rows
// are tagged with a run-unique marker so they remain attributable.
import { URL_, ANON, SERVICE, IDENT, signIn, rest, svc, mutate, rpc,
         check, section, summary, beginSuite, n, countExact, checkDelta } from './lib.mjs';

const RUN = `p2probe-${Date.now()}`;
const H = (tok) => ({ apikey: ANON, Authorization: `Bearer ${tok}`, 'Content-Type': 'application/json' });
const SH = { apikey: SERVICE, Authorization: `Bearer ${SERVICE}`, 'Content-Type': 'application/json' };

// ── dedicated probe identities, so no shared fixture's role is disturbed ─────
async function mkUser(tag) {
  const email = `${RUN}-${tag}@qa.12circle.test`;
  const pw = `P2-Probe-${tag}-2026!`;
  const r = await fetch(`${URL_}/auth/v1/admin/users`, {
    method: 'POST', headers: SH,
    body: JSON.stringify({ email, password: pw, email_confirm: true }),
  });
  const u = await r.json();
  return { id: u.id, email, pw };
}
async function tokenFor(u) {
  const r = await fetch(`${URL_}/auth/v1/token?grant_type=password`, {
    method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: u.email, password: u.pw }),
  });
  return (await r.json()).access_token;
}
async function setRole(id, role) {
  return fetch(`${URL_}/rest/v1/user_profiles?id=eq.${id}`, {
    method: 'PATCH', headers: { ...SH, Prefer: 'return=minimal' },
    body: JSON.stringify({ role }),
  });
}

const admin  = await mkUser('admin');
const trust  = await mkUser('trust');
const eraser = await mkUser('eraser');
const subj   = await mkUser('subject');
for (const [u, r] of [[admin,'admin'],[trust,'trust_operator'],[eraser,'erasure_executor']]) await setRole(u.id, r);
const adminTok  = await tokenFor(admin);
const trustTok  = await tokenFor(trust);
const eraserTok = await tokenFor(eraser);
const subjTok   = await tokenFor(subj);

check('fixture: four probe identities exist with their roles',
  !!(adminTok && trustTok && eraserTok && subjTok), `run=${RUN}`);

// ─────────────────────────────────────────────────────────────────────────────
section('A2 · admin_set_user_role EMITS an audit Event (§8.3 named this gap)');

// COUNTED EXACTLY, FROM content-range. This was `n(await …json())` — the length of one
// PostgREST page. `admin_action` crossed 1000 rows on QA (1028 exact), so the page
// saturated and this assertion began comparing 1000 to 1000: it could no longer see the
// event appear, and could no longer see one FAIL to appear either, which is the property
// it exists to protect. The audit path was healthy the whole time. See V5 §174.
const nBefore = await countExact('audit_events?category=eq.admin_action');

const setR = await fetch(`${URL_}/rest/v1/rpc/admin_set_user_role`, {
  method: 'POST', headers: H(adminTok),
  body: JSON.stringify({ target_user: subj.id, new_role: 'coach' }),
});
check('an admin CAN set a role through the sanctioned path', setR.status < 300, `status=${setR.status}`);

const after = await fetch(`${URL_}/rest/v1/audit_events?select=id,actor_id,subject_pseudonym,actor_provenance&category=eq.admin_action&order=occurred_at.desc&limit=1`, { headers: SH });
const rows = await after.json();
const afterAll = await countExact('audit_events?category=eq.admin_action');
checkDelta('the role change EMITTED an admin_action Event (A2 IN; A3 application arm)',
  { before: nBefore, after: afterAll, expected: 1 });
const row = rows[0] ?? {};
check('the actor is the calling admin and provenance is GROUNDED (A3 sub-ruling 3)',
  row.actor_id === admin.id && row.actor_provenance === 'grounded',
  `actor=${row.actor_id === admin.id} provenance=${row.actor_provenance}`);

// ─────────────────────────────────────────────────────────────────────────────
section('A6 §8.9 · before/after delta — NON-PHI ONLY, phi_correction excluded');

// A6 lists admin actions among the nine delta-bearing categories and names the
// value they carry: "role". Migration 147 emitted without one because the column
// did not exist until 150.
const deltaRow = await (await fetch(`${URL_}/rest/v1/audit_events?select=delta&category=eq.admin_action&order=occurred_at.desc&limit=1`, { headers: SH })).json();
const dlt = deltaRow[0]?.delta ?? null;
check('the admin_action Event carries the role before/after pair (A6 — admin actions are delta-bearing)',
  !!dlt && dlt.before?.role && dlt.after?.role && dlt.before.role !== dlt.after.role,
  `before=${dlt?.before?.role} after=${dlt?.after?.role}`);

// A6: "PHI-CORRECTION DELTAS ARE EXCLUDED." Enforced as a constraint so a
// mislabelled record cannot put PHI into the ledger.
const phiDelta = await fetch(`${URL_}/rest/v1/rpc/audit_record_event`, {
  method: 'POST', headers: SH,
  body: JSON.stringify({ p_action: RUN, p_category: 'phi_correction', p_outcome: 'success',
                         p_delta: { before: { x: 1 }, after: { x: 2 } } }),
});
const phiDeltaRes = await phiDelta.json().catch(() => null);
check('a phi_correction Event carrying a delta is REFUSED (A6 excludes it by name)',
  phiDeltaRes === false, `result=${phiDeltaRes}`);

const occDelta = await fetch(`${URL_}/rest/v1/rpc/audit_record_event`, {
  method: 'POST', headers: SH,
  body: JSON.stringify({ p_action: RUN, p_category: 'phi_read', p_outcome: 'success',
                         p_delta: { before: {}, after: {} } }),
});
check('nor may one of A6\'s five OCCURRENCE categories carry a delta',
  (await occDelta.json().catch(() => null)) === false, 'phi_read + delta refused');

section('A12 ruling 2 · the subject is a PSEUDONYM, resolvable only through the map');

check('the recorded subject is NOT the target\'s real id',
  row.subject_pseudonym && row.subject_pseudonym !== subj.id,
  `pseudonym=${String(row.subject_pseudonym).slice(0,8)}… target=${subj.id.slice(0,8)}…`);

// Resolution is verified through the SANCTIONED PATH, not by reading the map.
// An earlier revision of this assertion queried audit_identity_map directly with
// service_role and passed -- until migration 148 revoked that grant, at which
// point it failed for the right reason. §19.3 permits resolution only "inside the
// audit read path", so asserting it any other way was testing a route the ruling
// forbids. The direct read is asserted separately, and must FAIL.
const viaPath = await rpc(trustTok, 'audit_read_events', { p_subject: subj.id, p_limit: 5 });
check('and it RESOLVES to the target — through the audit read path, the only place §19.3 allows',
  viaPath.status < 300 && n(viaPath.body) >= 1 && viaPath.body.every(r => r.subject_id === subj.id),
  `status=${viaPath.status} rows=${n(viaPath.body)}`);

// ─────────────────────────────────────────────────────────────────────────────
section('A11 · the Event population is FROZEN against every caller, service_role included');

const upd = await fetch(`${URL_}/rest/v1/audit_events?id=eq.${row.id}`, {
  method: 'PATCH', headers: SH, body: JSON.stringify({ outcome: 'failure' }),
});
check('service_role CANNOT update an audit Event', upd.status >= 400, `status=${upd.status}`);
const del = await fetch(`${URL_}/rest/v1/audit_events?id=eq.${row.id}`, { method: 'DELETE', headers: SH });
check('service_role CANNOT delete an audit Event', del.status >= 400, `status=${del.status}`);
const intact = await (await fetch(`${URL_}/rest/v1/audit_events?select=outcome&id=eq.${row.id}`, { headers: SH })).json();
check('and the row is intact after both attempts', intact[0]?.outcome === 'success', `outcome=${intact[0]?.outcome}`);

// ─────────────────────────────────────────────────────────────────────────────
section('A13 · readers — sub-ruling 1 excludes an admin from their OWN admin actions');

const adminSees = await rest(adminTok, `audit_events?select=id&category=eq.admin_action&actor_id=eq.${admin.id}`);
check('the acting admin reads NONE of the admin_action rows they caused (A13 sub-ruling 1)',
  n(adminSees.body) === 0, `rows=${n(adminSees.body)}`);

const trustSees = await rest(trustTok, `audit_events?select=id&category=eq.admin_action&actor_id=eq.${admin.id}`);
check('the Trust operator DOES read them — that is the point of sub-ruling 1',
  n(trustSees.body) >= 1, `rows=${n(trustSees.body)}`);

const subjSees = await rest(subjTok, 'audit_events?select=id');
check('the SUBJECT reads nothing — §8.8: not a reader of any audit population',
  n(subjSees.body) === 0, `rows=${n(subjSees.body)}`);

const eraserSees = await rest(eraserTok, 'audit_events?select=id');
check('the erasure executor reads nothing (§8.18·Q2 — never both authorities)',
  n(eraserSees.body) === 0, `rows=${n(eraserSees.body)}`);

// ─────────────────────────────────────────────────────────────────────────────
section('§19.3 · resolution happens ONLY inside the audit read path');

const pathAsTrust = await rpc(trustTok, 'audit_read_events', { p_limit: 5 });
check('the read path serves an entitled reader and RESOLVES the subject',
  pathAsTrust.status < 300 && n(pathAsTrust.body) >= 1
    && pathAsTrust.body.some(r => r.subject_id), `status=${pathAsTrust.status} rows=${n(pathAsTrust.body)}`);

const mapDirect = await rest(trustTok, 'audit_identity_map?select=*');
check('NO client role may read the map directly (§8.20·Q1 — no policy grants any)',
  n(mapDirect.body) === 0 || mapDirect.status >= 400, `status=${mapDirect.status} rows=${n(mapDirect.body)}`);

// ─────────────────────────────────────────────────────────────────────────────
section('A12 ruling 1 · ANONYMISE-AND-RETAIN — severance keeps the ledger');

const severByTrust = await rpc(trustTok, 'audit_sever_identity', { p_subject: subj.id });
check('severance is REFUSED to the Trust operator (A12 ruling 6; §8.18·Q1)',
  severByTrust.status >= 400, `status=${severByTrust.status}`);

const severByEraser = await rpc(eraserTok, 'audit_sever_identity', { p_subject: subj.id });
check('severance SUCCEEDS for the erasure executor', severByEraser.status < 300 && severByEraser.body === true,
  `status=${severByEraser.status} result=${severByEraser.body}`);

const stillThere = await (await fetch(`${URL_}/rest/v1/audit_events?select=id&id=eq.${row.id}`, { headers: SH })).json();
check('the audit row is RETAINED after severance — the frozen row is never mutated',
  n(stillThere) === 1, `rows=${n(stillThere)}`);

const mapGone = await (await fetch(`${URL_}/rest/v1/audit_identity_map?select=pseudonym&subject_id=eq.${subj.id}`, { headers: SH })).json();
check('and the identity is no longer resolvable', n(mapGone) === 0, `map rows=${n(mapGone)}`);

// ─────────────────────────────────────────────────────────────────────────────
section('A11 · Control evidence has NO RUNTIME WRITE PATH');

const ceIns = await fetch(`${URL_}/rest/v1/audit_control_evidence`, {
  method: 'POST', headers: SH,
  body: JSON.stringify({ requirement: RUN, implementation_location: 'x', test_evidence: 'y', result: 'pass', date_version: 'v1', owner: 'probe' }),
});
check('not even service_role may INSERT control evidence (A11 NO RUNTIME WRITE PATH)',
  ceIns.status >= 400, `status=${ceIns.status}`);

// Migration 148. The FIRST live run of this suite failed the assertion above with
// 201: Supabase's ALTER DEFAULT PRIVILEGES grants ALL on every new public table to
// authenticated and service_role, so 142-146's GRANT SELECT statements were
// additive no-ops and service_role -- which BYPASSES RLS -- held full DML. A bare
// postgres has no such defaults, which is why the local rung could not see it.
section('A3 sub-ruling 5 · service_role is CONSTRAINED where no freeze bound it');

const mapDel = await fetch(`${URL_}/rest/v1/audit_identity_map?subject_id=eq.${subj.id}`, {
  method: 'DELETE', headers: SH,
});
check('service_role CANNOT sever an identity directly — only the executor\'s path may (A12 ruling 6)',
  mapDel.status >= 400, `status=${mapDel.status}`);

const mapIns = await fetch(`${URL_}/rest/v1/audit_identity_map`, {
  method: 'POST', headers: SH, body: JSON.stringify({ subject_id: admin.id }),
});
check('service_role CANNOT write the identity map directly (§8.20·Q1)',
  mapIns.status >= 400, `status=${mapIns.status}`);

// ─────────────────────────────────────────────────────────────────────────────
section('A1 pop. 2 · the Incident population is WRITE-CLOSED — its RPC is unbuilt');

// A3 §8.5 gives the Incident population the write path "RPC + application". No
// RPC exists, because NO RULING DETERMINES WHO MAY OPEN AN INCIDENT: the record
// specifies the eleven fields (V5_DECISION_RESOLUTION:114), the readers (A13),
// the mutation semantics (A11 APPEND-STATE-TRANSITIONS), the retention (A12
// ruling 4) and the write-path MECHANISM — but not the creating authority.
// Building an RPC would mean inventing that boundary. Until it is ruled the
// population is correctly write-closed, and these assertions hold it closed so
// the gap cannot be filled by accident. See V5 §81.
const incIns = await fetch(`${URL_}/rest/v1/audit_incidents`, {
  method: 'POST', headers: SH,
  body: JSON.stringify({ summary: RUN, occurred_at: new Date().toISOString(),
                         severity: 'High', actor_provenance: 'system' }),
});
check('service_role CANNOT create an incident — no write path is ruled yet (A3 §8.5)',
  incIns.status >= 400, `status=${incIns.status}`);

const incInsAuth = await mutate(trustTok, 'audit_incidents', 'POST',
  { summary: RUN, occurred_at: new Date().toISOString(), severity: 'High', actor_provenance: 'system' });
check('nor may the Trust operator — Trust reviews, it does not author (§19.2)',
  incInsAuth.status >= 400, `status=${incInsAuth.status}`);

const trIns = await fetch(`${URL_}/rest/v1/audit_incident_transitions`, {
  method: 'POST', headers: SH,
  body: JSON.stringify({ incident_id: subj.id, changed_field: 'x', changed_by_provenance: 'system' }),
});
check('nor may anyone forge a retained transition directly (A11 §8.6)',
  trIns.status >= 400, `status=${trIns.status}`);

section('D12 · the observability population carries no subject, and retention is bound');

const obsCols = await fetch(`${URL_}/rest/v1/observability_events?select=*&limit=1`, { headers: SH });
check('observability_events is reachable by service_role', obsCols.status === 200, `status=${obsCols.status}`);

// Migration 149. service_role's direct INSERT was revoked: §8.16·Q4 discharges
// this population's deferral "ON THE SAME TERMS AS THE AUDIT POPULATIONS —
// service_role is NOT the writer of record", and a direct grant made it exactly
// that. Writes now go through a definer function, as they do for the audit
// populations.
const obsDirect = await fetch(`${URL_}/rest/v1/observability_events`, {
  method: 'POST', headers: SH,
  body: JSON.stringify({ component: 'metric', retention_class: 'operational_90d' }),
});
check('service_role CANNOT insert observability directly — it is not the writer of record (§8.16·Q4)',
  obsDirect.status >= 400, `status=${obsDirect.status}`);

const obsRpc = await fetch(`${URL_}/rest/v1/rpc/observability_record`, {
  method: 'POST', headers: SH,
  body: JSON.stringify({ p_component: 'metric', p_retention_class: 'operational_90d' }),
});
const obsRpcOk = await obsRpc.json().catch(() => null);
check('but the definer write path accepts a correctly-classed record',
  obsRpc.status < 300 && obsRpcOk === true, `status=${obsRpc.status} result=${obsRpcOk}`);

const obsBad = await fetch(`${URL_}/rest/v1/rpc/observability_record`, {
  method: 'POST', headers: SH,
  body: JSON.stringify({ p_component: 'metric', p_retention_class: 'audit_6y' }),
});
const obsBadRes = await obsBad.json().catch(() => null);
check('a 6-year class still cannot attach to a non-audit component (§8.16·Q2)',
  obsBadRes === false, `result=${obsBadRes}`);

const obsRow = ((await (await fetch(`${URL_}/rest/v1/observability_events?select=*&order=recorded_at.desc&limit=1`, { headers: SH })).json())[0]) ?? {};
check('and the stored record carries NO subject identifier (D12·Q5)',
  !('subject_id' in obsRow) && !('user_id' in obsRow), Object.keys(obsRow).join(','));

const anonObs = await fetch(`${URL_}/rest/v1/audit_events?select=id`, { headers: { apikey: ANON, Authorization: `Bearer ${ANON}` } });
check('anon reads nothing from the audit ledger', anonObs.status >= 400 || n(await anonObs.json()) === 0, `status=${anonObs.status}`);

// ═══════════════════════════════════════════════════════════════════════════
// Migration 151 — the four owner-approved emitters, B1-B4, verified LIVE.
// Each assertion names the decision it proves and the ruling behind it.
section('B1 · incident creation authority — admin and trust_operator ONLY');

const openAsAdmin = await rpc(adminTok, 'audit_open_incident',
  { p_summary: `${RUN} admin`, p_occurred_at: new Date().toISOString(), p_severity: 'High' });
check('an ADMIN may open an incident (owner decision B1)',
  openAsAdmin.status < 300 && !!openAsAdmin.body, `status=${openAsAdmin.status}`);

const openAsTrust = await rpc(trustTok, 'audit_open_incident',
  { p_summary: `${RUN} trust`, p_occurred_at: new Date().toISOString(), p_severity: 'Warning' });
check('a TRUST OPERATOR may open an incident (owner decision B1)',
  openAsTrust.status < 300 && !!openAsTrust.body, `status=${openAsTrust.status}`);

const openAsSubject = await rpc(subjTok, 'audit_open_incident',
  { p_summary: `${RUN} nope`, p_occurred_at: new Date().toISOString(), p_severity: 'High' });
check('an ordinary client may NOT — 42501 (B1 excludes clients and coaches)',
  openAsSubject.status >= 400, `status=${openAsSubject.status}`);

const openAsEraser = await rpc(eraserTok, 'audit_open_incident',
  { p_summary: `${RUN} nope`, p_occurred_at: new Date().toISOString(), p_severity: 'High' });
check('nor may the erasure executor (B1 excludes it by name)',
  openAsEraser.status >= 400, `status=${openAsEraser.status}`);

const openAsService = await fetch(`${URL_}/rest/v1/rpc/audit_open_incident`, {
  method: 'POST', headers: SH,
  body: JSON.stringify({ p_summary: `${RUN} nope`, p_occurred_at: new Date().toISOString(), p_severity: 'High' }),
});
check('nor may service_role — not granted EXECUTE, and the auth.uid() gate refuses it',
  openAsService.status >= 400, `status=${openAsService.status}`);

const incRow = (await (await fetch(`${URL_}/rest/v1/audit_incidents?select=actor_identity,actor_provenance,severity&summary=eq.${RUN}%20admin`, { headers: SH })).json())[0] ?? {};
check('the incident records the ACTOR identity, grounded (B1: "actor identity must be recorded")',
  incRow.actor_identity === admin.id && incRow.actor_provenance === 'grounded',
  `actor=${incRow.actor_identity === admin.id} provenance=${incRow.actor_provenance}`);

// ─────────────────────────────────────────────────────────────────────────────
section('B2 · relationship_change — material STATUS transitions only');

const relBefore = await countExact('audit_events?category=eq.relationship_change');
const mkRel = await fetch(`${URL_}/rest/v1/coach_client_relationships`, {
  method: 'POST', headers: { ...SH, Prefer: 'return=representation' },
  body: JSON.stringify({ coach_id: trust.id, client_id: subj.id, status: 'pending' }),
});
const relId = ((await mkRel.json())[0] ?? {}).id;
check('fixture: a relationship exists at status pending', !!relId, `status=${mkRel.status}`);

await fetch(`${URL_}/rest/v1/coach_client_relationships?id=eq.${relId}`, {
  method: 'PATCH', headers: SH, body: JSON.stringify({ specialty: 'strength', request_message: 'hello' }),
});
const relAfterMeta = await countExact('audit_events?category=eq.relationship_change');
// `expected: 0` through checkDelta rather than a bare `===`. An "emits nothing"
// assertion is blind to saturation in the OTHER direction: two capped pages always
// look equal, so a spurious event would be invisible exactly when the population is
// large. checkDelta refuses to answer instead of answering wrongly.
checkDelta('an INCIDENTAL metadata change emits NOTHING (B2: not every metadata change)',
  { before: relBefore, after: relAfterMeta, expected: 0 });

await fetch(`${URL_}/rest/v1/coach_client_relationships?id=eq.${relId}`, {
  method: 'PATCH', headers: SH, body: JSON.stringify({ status: 'active' }),
});
const relAfterStatus = await countExact('audit_events?category=eq.relationship_change');
check('a material STATUS transition DOES emit (B2)',
  relAfterStatus === relBefore + 1, `${relAfterMeta} -> ${relAfterStatus}`);

const relDelta = ((await (await fetch(`${URL_}/rest/v1/audit_events?select=delta,action&category=eq.relationship_change&order=occurred_at.desc&limit=1`, { headers: SH })).json())[0]) ?? {};
check('and the Event carries the status transition (A6 names this delta "status")',
  relDelta.delta?.before?.status === 'pending' && relDelta.delta?.after?.status === 'active',
  `${relDelta.delta?.before?.status} -> ${relDelta.delta?.after?.status} on ${relDelta.action}`);

// ─────────────────────────────────────────────────────────────────────────────
section('B3 · billing_entitlement — subscriptions is authoritative, NOT membership_tier');

const billBefore = await countExact('audit_events?category=eq.billing_entitlement');
const mkSub = await fetch(`${URL_}/rest/v1/subscriptions`, {
  method: 'POST', headers: { ...SH, Prefer: 'return=representation' },
  body: JSON.stringify({ user_id: subj.id, kind: 'app', status: 'active', plan_tier: 'basic' }),
});
const subId = ((await mkSub.json())[0] ?? {}).id;
check('fixture: a subscription exists at basic/active', !!subId, `status=${mkSub.status}`);

await fetch(`${URL_}/rest/v1/subscriptions?id=eq.${subId}`, {
  method: 'PATCH', headers: SH,
  body: JSON.stringify({ current_period_end: new Date(Date.now() + 2.6e9).toISOString() }),
});
const billAfterRoll = await countExact('audit_events?category=eq.billing_entitlement');
checkDelta('a period rollover is NOT an entitlement change and emits nothing',
  { before: billBefore, after: billAfterRoll, expected: 0 });

await fetch(`${URL_}/rest/v1/subscriptions?id=eq.${subId}`, {
  method: 'PATCH', headers: SH, body: JSON.stringify({ plan_tier: 'premium' }),
});
const billAfterTier = await countExact('audit_events?category=eq.billing_entitlement');
check('a plan_tier transition DOES emit, from the AUTHORITATIVE source (B3)',
  billAfterTier === billBefore + 1, `${billAfterRoll} -> ${billAfterTier}`);

const billDelta = ((await (await fetch(`${URL_}/rest/v1/audit_events?select=delta,action&category=eq.billing_entitlement&order=occurred_at.desc&limit=1`, { headers: SH })).json())[0]) ?? {};
check('the Event reads subscriptions(status, plan_tier) — not user_profiles.membership_tier',
  billDelta.action === 'subscriptions.entitlement'
    && billDelta.delta?.before?.plan_tier === 'basic' && billDelta.delta?.after?.plan_tier === 'premium',
  `${billDelta.action}: ${billDelta.delta?.before?.plan_tier} -> ${billDelta.delta?.after?.plan_tier}`);

// The legacy field must not be treated as authoritative: changing it emits nothing.
const legacyBefore = await countExact('audit_events?category=eq.billing_entitlement');
await fetch(`${URL_}/rest/v1/user_profiles?id=eq.${subj.id}`, {
  method: 'PATCH', headers: SH, body: JSON.stringify({ membership_tier: 'premium' }),
});
const legacyAfter = await countExact('audit_events?category=eq.billing_entitlement');
checkDelta('writing the LEGACY membership_tier emits nothing — it is not authoritative (B3)',
  { before: legacyBefore, after: legacyAfter, expected: 0 });

// ─────────────────────────────────────────────────────────────────────────────
section('B4 · phi_correction — changed column NAMES only, never values');

const phiBefore = await countExact('audit_events?category=eq.phi_correction');
const mkChk = await fetch(`${URL_}/rest/v1/weekly_checkins`, {
  method: 'POST', headers: { ...SH, Prefer: 'return=representation' },
  body: JSON.stringify({ user_id: subj.id, week_number: 1, week_start_date: new Date().toISOString().slice(0,10),
                         weight_kg: 80.5, energy_level: 7, notes: 'felt strong' }),
});
const chkId = ((await mkChk.json())[0] ?? {}).id;
check('fixture: a weekly check-in exists with the subject\'s health answers', !!chkId, `status=${mkChk.status}`);

// The coach writes only review fields — 114's v_coach_cols. Not a PHI correction.
await fetch(`${URL_}/rest/v1/weekly_checkins?id=eq.${chkId}`, {
  method: 'PATCH', headers: SH,
  body: JSON.stringify({ feedback_message: 'good work', coach_name: 'T', reviewed_at: new Date().toISOString() }),
});
const phiAfterCoach = await countExact('audit_events?category=eq.phi_correction');
check('a COACH writing only review fields is NOT a correction and emits nothing (114 v_coach_cols)',
  phiAfterCoach === phiBefore, `${phiBefore} -> ${phiAfterCoach}`);

// The subject corrects their own submitted health answers. That IS the correction.
const selfCorrect = await mutate(subjTok, `weekly_checkins?id=eq.${chkId}`, 'PATCH',
  { weight_kg: 79.0, sleep_hours: 6.5, notes: 'corrected' });
const phiAfterSelf = await countExact('audit_events?category=eq.phi_correction');
check('the SUBJECT correcting their own health answers DOES emit (B4)',
  phiAfterSelf === phiBefore + 1, `status=${selfCorrect.status}  ${phiAfterCoach} -> ${phiAfterSelf}`);

const phiRow = ((await (await fetch(`${URL_}/rest/v1/audit_events?select=changed_columns,delta,action&category=eq.phi_correction&order=occurred_at.desc&limit=1`, { headers: SH })).json())[0]) ?? {};
check('it carries the changed column NAME SET (B4: names only)',
  Array.isArray(phiRow.changed_columns) && phiRow.changed_columns.includes('weight_kg')
    && phiRow.changed_columns.includes('sleep_hours'),
  `changed_columns=${JSON.stringify(phiRow.changed_columns)}`);

check('and delta is NULL — A6 excludes PHI-correction deltas, migration 150 enforces it',
  phiRow.delta === null || phiRow.delta === undefined, `delta=${JSON.stringify(phiRow.delta)}`);

const serialised = JSON.stringify(phiRow);
check('NO PHI VALUE appears anywhere in the Event (B4: never before/after values)',
  !/79|80\.5|6\.5|corrected|felt strong/.test(serialised), `scanned ${serialised.length} chars of the stored row`);

// ═══════════════════════════════════════════════════════════════════════════
// Migration 152 — owner decisions R-1 and S-2.
section('R-1 · audit reads are recorded as the A2 category `audit_read`');

const arBefore = await countExact('audit_events?category=eq.audit_read');

const arAccept = await fetch(`${URL_}/rest/v1/rpc/audit_record_event`, {
  method: 'POST', headers: SH,
  body: JSON.stringify({ p_action: `${RUN}-cat`, p_category: 'audit_read', p_outcome: 'success' }),
});
check('the promoted category `audit_read` is ACCEPTED (R-1, under A2\'s promotion clause)',
  (await arAccept.json()) === true, `status=${arAccept.status}`);

const arDelta = await fetch(`${URL_}/rest/v1/rpc/audit_record_event`, {
  method: 'POST', headers: SH,
  body: JSON.stringify({ p_action: `${RUN}-d`, p_category: 'audit_read', p_outcome: 'success',
                         p_delta: { before: {}, after: {} } }),
});
check('an audit_read carrying a delta is REFUSED — a read is an occurrence (A6)',
  (await arDelta.json()) === false, 'delta refused');

// One call through the sanctioned read path must emit exactly one Event.
const arMid = await countExact('audit_events?category=eq.audit_read');
const readCall = await rpc(trustTok, 'audit_read_events', { p_limit: 5 });
check('the read path still WORKS after gaining the emission (it returned rows)',
  readCall.status < 300 && n(readCall.body) >= 1, `status=${readCall.status} rows=${n(readCall.body)}`);

const arAfterOne = await countExact('audit_events?category=eq.audit_read');
check('ONE call emitted exactly ONE audit_read Event — the recursion boundary holds',
  arAfterOne === arMid + 1, `${arMid} -> ${arAfterOne}`);

const arRow = ((await (await fetch(`${URL_}/rest/v1/audit_events?select=actor_id,actor_provenance,subject_pseudonym,delta,changed_columns,action&category=eq.audit_read&action=eq.audit_events.read&order=occurred_at.desc&limit=1`, { headers: SH })).json())[0]) ?? {};
check('the Event identifies the ACTOR performing the read, grounded (R-1)',
  arRow.actor_id === trust.id && arRow.actor_provenance === 'grounded',
  `actor=${arRow.actor_id === trust.id} provenance=${arRow.actor_provenance}`);
check('and carries NO payload — no delta, no column names, no PHI (R-1)',
  (arRow.delta === null || arRow.delta === undefined)
  && (arRow.changed_columns === null || arRow.changed_columns === undefined),
  `delta=${JSON.stringify(arRow.delta)} changed_columns=${JSON.stringify(arRow.changed_columns)}`);

const arSeen = await rest(subjTok, 'audit_events?select=id&category=eq.audit_read');
check('A13 reader controls apply to the new category — a plain client sees none',
  n(arSeen.body) === 0, `rows=${n(arSeen.body)}`);

// ─────────────────────────────────────────────────────────────────────────────
section('S-2 · severance emits export_deletion carrying the SEVERED pseudonym');

const victim = await mkUser('victim2');
const vps = await (await fetch(`${URL_}/rest/v1/rpc/audit_mint_pseudonym`, {
  method: 'POST', headers: SH, body: JSON.stringify({ p_subject: victim.id }),
})).json();
check('fixture: a second subject has a pseudonym', !!vps, `pseudonym=${String(vps).slice(0,8)}…`);

const exBefore = await countExact('audit_events?category=eq.export_deletion');
const sever2 = await rpc(eraserTok, 'audit_sever_identity', { p_subject: victim.id });
check('the erasure executor severs the second subject', sever2.body === true, `status=${sever2.status}`);

const exAfter = await countExact('audit_events?category=eq.export_deletion');
check('severance emitted exactly ONE export_deletion Event (S-2)',
  exAfter === exBefore + 1, `${exBefore} -> ${exAfter}`);

const exRow = ((await (await fetch(`${URL_}/rest/v1/audit_events?select=subject_pseudonym,delta,action,actor_id&category=eq.export_deletion&order=occurred_at.desc&limit=1`, { headers: SH })).json())[0]) ?? {};
check('its subject is the SEVERED pseudonym, not the identifiable subject (S-2)',
  exRow.subject_pseudonym === vps && exRow.subject_pseudonym !== victim.id,
  `pseudonym match=${exRow.subject_pseudonym === vps}  is raw id=${exRow.subject_pseudonym === victim.id}`);
check('and it carries no delta — no identity reintroduced (S-2)',
  exRow.delta === null || exRow.delta === undefined, `delta=${JSON.stringify(exRow.delta)}`);

const stillResolves = n(await (await fetch(`${URL_}/rest/v1/audit_identity_map?select=pseudonym&pseudonym=eq.${vps}`, { headers: SH })).json());
check('the pseudonym NO LONGER RESOLVES after severance (S-2)',
  stillResolves === 0, `map rows=${stillResolves}`);

check('the identifiable subject appears NOWHERE in the severance Event (S-2)',
  !JSON.stringify(exRow).includes(victim.id), `scanned the stored row for ${victim.id.slice(0,8)}…`);

const sever2again = await rpc(eraserTok, 'audit_sever_identity', { p_subject: victim.id });
const exRepeat = await countExact('audit_events?category=eq.export_deletion');
check('a repeat severance emits nothing — there is nothing left to sever',
  sever2again.body === false && exRepeat === exAfter, `result=${sever2again.body}  ${exAfter} -> ${exRepeat}`);

export default summary('P2 audit populations');
