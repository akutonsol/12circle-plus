// D19 · THE GUARDIAN EMERGENCY DISABLEMENT PATH — migration 169, live against QA.
//
// WHY THIS SUITE EXISTS NOW. `admin_set_guardian_state` has been applied since §150 and had
// NO caller and NO live coverage: the Trust page named it in a comment and never invoked it.
// Owner decision **Q9** placed the control on Trust → AI Guardian, so the path is now
// reachable from a UI — and the rung the QA_CLOSURE_STANDARD demands of a
// security/authorization change is live evidence, not a status code.
//
// WHY THIS IS THE MOST CONSEQUENTIAL WRITE IN THE ADMIN LAYER. Every other governed write
// edits a record. This one switches off autonomy supervision. A gate that silently failed
// open here would not corrupt a row; it would let any admin role stop the Guardian. So each
// assertion reads `guardian_state.state` BACK rather than trusting a 204, and the refusals
// are asserted by the STORED STATE being unmoved.
//
// WHAT THE UI CLAIMS, AND IS HELD TO. The card tells an operator the capability belongs to
// "the Trust lead alone". Section 1 proves that against the approved matrix itself rather
// than against the seed file, because a claim about who holds a capability is exactly the
// kind that rots quietly.
import { IDENT, signIn, svc, rpc, check,
         section, summary, beginSuite, n, countExact } from './lib.mjs';

const ONE = (b) => (Array.isArray(b) ? b[0] : b) || {};
const A5 = ['Active', 'Monitoring', 'Degraded', 'Disabled'];

async function uidOf(key) {
  const r = await svc(`user_profiles?email=eq.${encodeURIComponent(IDENT[key].email)}&select=id`);
  return ONE(r.body).id;
}
async function assign(uid, role) {
  await svc(`admin_role_assignments?user_id=eq.${uid}`, { method: 'DELETE' });
  await svc('admin_role_assignments', { method: 'POST', body: { user_id: uid, admin_role: role } });
}
const unassign = async (uid) =>
  svc(`admin_role_assignments?user_id=eq.${uid}`, { method: 'DELETE' });

const readState = async () => ONE((await svc(
  'guardian_state?select=state,reason,set_by,set_at')).body);
// PATCH-then-POST, AND IT IS NOT PEDANTRY — the first draft cost QA its Guardian.
//
// `guardian_state` is a one-row table (`id boolean PRIMARY KEY CHECK (id)`), so the first
// draft wrote it with a POST carrying `Prefer: resolution=merge-duplicates` in an
// `opts.headers`. **`svc` ignores `opts.headers` entirely** — it builds its own and honours
// only `opts.prefer` — so the upsert hint was silently dropped, the POST hit a primary-key
// conflict, and because nothing checked the status the teardown appeared to succeed. QA's
// Guardian was left DISABLED by a test whose own comment says that must never happen.
//
// So this patches the existing row and only inserts when there is none, and the caller
// asserts the result rather than assuming it.
const setState = async (state, reason = null) => {
  const patched = await svc('guardian_state?id=eq.true', { method: 'PATCH',
    body: { state, reason } });
  if (patched.status < 300 && n(patched.body) > 0) return patched;
  return svc('guardian_state', { method: 'POST', body: { id: true, state, reason } });
};

const auditCount = () =>
  countExact('audit_events?action=eq.guardian_state.set&select=id');

beginSuite();

async function run() {
  const victim = await signIn('victim');
  const vUid   = await uidOf('victim');
  // Captured before anything is written, so the teardown restores what was THERE.
  const original = await readState();

  try {
    // ── 1 · the capability is held by exactly one role ────────────────────
    section('the matrix grants AI Guardian·manage to ONE role, which the card names');

    const holders = await svc(
      "admin_role_capabilities?area=eq.AI%20Guardian&verb=eq.manage&select=admin_role");
    const roles = (holders.body || []).map((r) => r.admin_role).sort();
    check('AI Guardian·manage is granted to exactly one role, and it is trust_lead — the ' +
          'claim the Trust card makes to the operator in words',
      roles.length === 1 && roles[0] === 'trust_lead',
      `holders=[${roles.join(', ')}]`);

    // A positive control on the read itself: if the capability table were empty or the
    // filter wrong, the assertion above would pass for want of rows.
    // `select=admin_role`, not `select=id`: the table is (admin_role, area, verb) with a
    // composite key and NO id column, and `countExact` refused the bad path outright
    // rather than handing back an unmeasured 0 — which is exactly what it was built for.
    const anyCaps = await countExact('admin_role_capabilities?select=admin_role');
    check('…and the capability table was non-empty when that was asked',
      anyCaps > 0, `rows=${anyCaps}`);

    // ── 2 · a role WITHOUT ·manage cannot disable the Guardian ────────────
    section('refusal, proved by re-reading guardian_state and not by the RPC status');

    await setState('Active', null);
    const before = await readState();
    check('arranged: the Guardian is Active', before.state === 'Active',
      `state=${before.state}`);

    // `content_editor` holds Community verbs and no AI Guardian verb at all.
    await assign(vUid, 'content_editor');
    const deniedEditor = await rpc(victim, 'admin_set_guardian_state',
      { p_state: 'Disabled', p_reason: 'QA-D19 unauthorized attempt' });
    const afterEditor = await readState();
    check('a role with NO AI Guardian verb cannot disable it — the stored state is still ' +
          'Active',
      afterEditor.state === 'Active',
      `status=${deniedEditor.status} state=${afterEditor.state}`);

    // THE ARM THAT MATTERS MOST. `trust_analyst` can SEE the Guardian section and must not
    // be able to switch it off — view and manage are graded separately, and if the function
    // had been written against `·view` this is the assertion that would catch it.
    const viewers = await svc(
      "admin_role_capabilities?area=eq.AI%20Guardian&verb=eq.view&select=admin_role");
    const viewerRole = (viewers.body || [])
      .map((r) => r.admin_role).find((r) => r !== 'trust_lead');
    check('arranged: some role other than trust_lead holds AI Guardian·view, so the ' +
          'view/manage split is testable at all',
      Boolean(viewerRole), `role=${viewerRole}`);
    if (viewerRole) {
      await assign(vUid, viewerRole);
      const deniedViewer = await rpc(victim, 'admin_set_guardian_state',
        { p_state: 'Disabled', p_reason: 'QA-D19 view-only attempt' });
      const afterViewer = await readState();
      check(`${viewerRole} can READ the Guardian section and CANNOT disable it — ` +
            '·view does not confer ·manage',
        afterViewer.state === 'Active',
        `status=${deniedViewer.status} state=${afterViewer.state}`);
    }

    const anon = await rpc('anon', 'admin_set_guardian_state',
      { p_state: 'Disabled', p_reason: 'QA-D19 anon' });
    const afterAnon = await readState();
    check('an anonymous caller is refused and the state is unmoved',
      anon.status >= 400 && afterAnon.state === 'Active',
      `status=${anon.status} state=${afterAnon.state}`);

    // ── 3 · trust_lead CAN, and the input rules hold ──────────────────────
    section('trust_lead disables it — and 169 refuses a blank reason and a bad state');

    await assign(vUid, 'trust_lead');

    const noReason = await rpc(victim, 'admin_set_guardian_state',
      { p_state: 'Disabled' });
    const afterNoReason = await readState();
    check('disabling with NO reason is REFUSED and the Guardian stays Active — the rule ' +
          'the dialog enforces is the function’s, not the form’s',
      noReason.status >= 400 && afterNoReason.state === 'Active',
      `status=${noReason.status} state=${afterNoReason.state}`);

    const blankReason = await rpc(victim, 'admin_set_guardian_state',
      { p_state: 'Disabled', p_reason: '   ' });
    const afterBlank = await readState();
    check('…and a whitespace-only reason is refused too: 169 trims before it checks',
      blankReason.status >= 400 && afterBlank.state === 'Active',
      `status=${blankReason.status} state=${afterBlank.state}`);

    const badState = await rpc(victim, 'admin_set_guardian_state',
      { p_state: 'Paused', p_reason: 'QA-D19' });
    const afterBad = await readState();
    check('a state outside the A5 vocabulary is REFUSED — no Guardian state is invented ' +
          'at write time',
      badState.status >= 400 && afterBad.state === 'Active',
      `status=${badState.status} state=${afterBad.state}`);

    const auditBefore = await auditCount();
    const REASON = 'QA-D19 runaway evaluation loop';
    const ok = await rpc(victim, 'admin_set_guardian_state',
      { p_state: 'Disabled', p_reason: REASON });
    const afterOk = await readState();
    check('trust_lead disables it, and the STORED state actually changed to Disabled',
      ok.status < 300 && afterOk.state === 'Disabled',
      `status=${ok.status} state=${afterOk.state}`);
    check('…the reason is recorded, so the card can say WHY a safety control is off',
      afterOk.reason === REASON, `reason=${JSON.stringify(afterOk.reason)}`);
    check('…and set_by records WHO did it',
      afterOk.set_by === vUid, `set_by matches caller=${afterOk.set_by === vUid}`);

    // ── 4 · the transition is audited in full, and a no-op is not ─────────
    section('A6 · a Guardian state is not personal data, so the delta is recorded whole');

    const auditAfter = await auditCount();
    check('the transition emitted exactly ONE new audit row',
      auditAfter === auditBefore + 1, `${auditBefore} -> ${auditAfter}`);

    const row = ONE((await svc('audit_events?action=eq.guardian_state.set' +
      '&select=category,outcome,delta,changed_columns,subject_pseudonym' +
      '&order=occurred_at.desc&limit=1')).body);
    check('…recorded as an admin_action with a success outcome',
      row.category === 'admin_action' && row.outcome === 'success',
      `category=${row.category} outcome=${row.outcome}`);
    check('…carrying the FULL before/after pair — Active → Disabled — because a Guardian ' +
          'state is not personal data, the opposite of the name writer in §141',
      row.delta?.before?.state === 'Active' && row.delta?.after?.state === 'Disabled',
      `delta=${JSON.stringify(row.delta)}`);
    check('…and naming `state` as the changed column',
      Array.isArray(row.changed_columns) && row.changed_columns.includes('state'),
      `changed_columns=${JSON.stringify(row.changed_columns)}`);
    check('…with a pseudonym standing for the actor, not a raw id',
      Boolean(row.subject_pseudonym) && row.subject_pseudonym !== vUid,
      `pseudonym is the caller's uuid=${row.subject_pseudonym === vUid}`);

    // THE CLAIM THE UI RELIES ON to hide the button once the Guardian is off. 169 returns
    // early on a no-op, so a second Disable would record nothing — which is why the card
    // offers no control in that state rather than a button that appears to fail.
    const noop = await rpc(victim, 'admin_set_guardian_state',
      { p_state: 'Disabled', p_reason: 'QA-D19 second attempt' });
    const auditNoop = await auditCount();
    const afterNoop = await readState();
    check('disabling an ALREADY disabled Guardian records NOTHING — the no-op transition ' +
          'is not audited, which is why the card offers no control in that state',
      auditNoop === auditAfter && afterNoop.state === 'Disabled',
      `status=${noop.status} audit ${auditAfter} -> ${auditNoop}`);

    // ── 5 · the state the UI reads is the state that was written ──────────
    section('the surface the card reads agrees with the row');
    const asLead = await svc('guardian_state?select=state');
    check('guardian_state reports Disabled to a reader after the transition — the card ' +
          'reads the stored fact and never its own intention',
      ONE(asLead.body).state === 'Disabled', `state=${ONE(asLead.body).state}`);
    check('…and every A5 state is still the only vocabulary the column accepts',
      A5.includes(ONE(asLead.body).state), `state=${ONE(asLead.body).state}`);
  } finally {
    // Restore the Guardian to whatever it was before this suite ran. This is the one
    // teardown in the programme that must not be skipped: leaving QA's Guardian disabled
    // would be a real safety-posture change made by a test.
    const restoreTo =
      original.state && A5.includes(original.state) ? original.state : 'Active';
    await setState(restoreTo, original.state ? (original.reason ?? null) : null);
    await unassign(vUid);

    // THE TEARDOWN IS ASSERTED, not assumed. Every other suite here can leave a stray
    // fixture row and lose nothing but tidiness; this one can leave autonomy supervision
    // switched off. A silent restore failure is the worst outcome in this file, so it is
    // the one piece of cleanup that reports.
    const restored = await readState();
    check('TEARDOWN · the Guardian was restored, and the restore was VERIFIED rather ' +
          'than assumed — a silent failure here leaves QA\u2019s safety control off',
      restored.state === restoreTo,
      `state=${restored.state} expected=${restoreTo}`);
  }
  return summary('D19 · Guardian emergency disablement');
}

export default await run();
