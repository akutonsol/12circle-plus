// D20 · OWNER DECISION Q11 — monthly subscription churn, event-based (migration 180).
//
// WHY THIS NEEDS ITS OWN SUITE. The ruling's hardest requirement is not the arithmetic, it
// is the refusal: *"until sufficient real cancellation history exists, the Dashboard must
// render the appropriate A11 empty/insufficient-history state rather than a misleading 0%."*
// A view that returns 0 and a view that returns NULL both look like "no churn" from a
// screenshot, and only one of them is honest while departures are not being recorded. So the
// decisive assertion here is a PAIR: the numerator reads 0 while the rate reads NULL, and
// then — once a cancellation has been recorded at all — a month with no cancellations reads
// a REAL 0 instead.
//
// AND THE NO-BACKFILL REQUIREMENT IS ASSERTED, NOT ASSUMED. The ruling says *"preserve
// existing data; do not fabricate/backfill historical cancellation dates."* Section 1 proves
// the column arrived empty across all 173 pre-existing rows.
//
// EVERY FIXTURE IS REMOVED. `subscriptions` is a billing table: a row left behind would
// misstate revenue on a surface other suites read, so the teardown is asserted like D19's.
import { IDENT, signIn, svc, check, checkDenied,
         section, summary, beginSuite, n, countExact } from './lib.mjs';

const ONE = (b) => (Array.isArray(b) ? b[0] : b) || {};
const num = (v) => (v === null || v === undefined ? null : Number(v));
const TAG = 'QA-D20-CHURN';

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

/// Read the surface AS the signed-in caller: service_role bypasses RLS but `admin_can` is
/// false for it, so a service read of this view returns nothing and proves nothing.
const view = async (who) => {
  const r = await fetch(`${process.env.QA_URL}/rest/v1/admin_revenue_overview?select=*`, {
    headers: { apikey: process.env.QA_ANON, Authorization: `Bearer ${who}` },
  });
  const body = await r.json().catch(() => null);
  return { status: r.status, row: ONE(body) };
};

const monthStart = () => {
  const d = new Date();
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1));
};

const purge = () => svc(`subscriptions?stripe_subscription_id=like.${TAG}*`, { method: 'DELETE' });

beginSuite();

async function run() {
  const victim = await signIn('victim');
  const vUid   = await uidOf('victim');
  const subject = await uidOf('attacker');

  try {
    await purge();
    await assign(vUid, 'viewer');     // holds Monetization·view

    // ── 1 · the column arrived EMPTY — nothing was backfilled ─────────────
    section('Q11 · no cancellation date was fabricated for any existing row');

    const everCanceled = await countExact('subscriptions?canceled_at=not.is.null&select=id');
    const total = await countExact('subscriptions?select=id');
    check('migration 180 added canceled_at and backfilled NOTHING — every pre-existing ' +
          'subscription carries a null, which is the truthful answer when no authoritative ' +
          'historical source exists',
      everCanceled === 0, `canceled_at set on ${everCanceled} of ${total} rows`);
    check('…asserted against a NON-EMPTY subscriptions population',
      total > 0, `rows=${total}`);

    // ── 2 · THE PAIR · 0 cancellations is NOT 0% churn ───────────────────
    section('Q11 · insufficient history renders NULL, never a misleading 0%');

    const before = await view(victim);
    check('the surface is readable by a Monetization·view holder',
      before.status < 300 && Object.keys(before.row).length > 0,
      `status=${before.status}`);
    check('THE DECISIVE PAIR · the numerator reads 0 and the rate reads NULL — a view that ' +
          'answered 0% here would assert "nobody left" while the truth is "departures were ' +
          'not being recorded"',
      num(before.row.churn_cancellations_month) === 0 &&
      before.row.churn_rate_pct === null,
      `cancellations=${before.row.churn_cancellations_month} rate=${JSON.stringify(before.row.churn_rate_pct)}`);
    check('…and the history marker is null, which is what makes the rate null',
      before.row.churn_first_cancellation_at === null,
      `first=${JSON.stringify(before.row.churn_first_cancellation_at)}`);
    check('the denominator is published and non-zero, so the null rate is NOT merely a ' +
          'division by nothing',
      num(before.row.churn_active_at_month_start) > 0,
      `denominator=${before.row.churn_active_at_month_start}`);
    check('the denominator BASIS is disclosed on the surface, so a reader need not infer ' +
          'that `status` is deliberately not consulted for a past instant',
      typeof before.row.churn_denominator_basis === 'string' &&
      before.row.churn_denominator_basis.includes('not yet canceled'),
      `basis=${JSON.stringify(before.row.churn_denominator_basis)}`);

    // ── 3 · a recorded cancellation makes the measure live ───────────────
    section('Q11 · once a cancellation is RECORDED the rate becomes computable');

    const ms = monthStart();
    const lastMonth = new Date(ms.getTime() - 86400000 * 5);   // inside the PREVIOUS month
    const thisMonth = new Date(ms.getTime() + 3600000);        // just inside THIS month

    // Two fixtures created BEFORE the month began, so both count in the denominator.
    const mk = async (tag, createdAt) => {
      const r = await svc('subscriptions', { method: 'POST',
        headers: { Prefer: 'return=representation' },
        body: { user_id: subject, kind: 'self_guided', status: 'active',
                stripe_subscription_id: `${TAG}-${tag}`,
                created_at: createdAt.toISOString() } });
      return ONE(r.body).id;
    };
    const idA = await mk('A', new Date(ms.getTime() - 86400000 * 40));
    const idB = await mk('B', new Date(ms.getTime() - 86400000 * 40));
    check('arranged: two subscriptions created before the month began',
      Boolean(idA) && Boolean(idB), `a=${Boolean(idA)} b=${Boolean(idB)}`);

    const withFixtures = await view(victim);
    const denomBase = num(withFixtures.row.churn_active_at_month_start);
    check('…and both are counted in "active at month start"',
      denomBase === num(before.row.churn_active_at_month_start) + 2,
      `${before.row.churn_active_at_month_start} -> ${denomBase}`);

    // A cancellation recorded in the PREVIOUS month: history now exists, but this month's
    // numerator must stay 0 — which is the arm that turns a null rate into a REAL zero.
    await svc(`subscriptions?id=eq.${idA}`, { method: 'PATCH',
      body: { status: 'canceled', canceled_at: lastMonth.toISOString() } });
    const afterPrior = await view(victim);
    check('a cancellation recorded in a PRIOR month makes the rate computable, and this ' +
          'month then reads a REAL 0 — the measured zero the null state was protecting',
      num(afterPrior.row.churn_cancellations_month) === 0 &&
      num(afterPrior.row.churn_rate_pct) === 0,
      `cancellations=${afterPrior.row.churn_cancellations_month} rate=${afterPrior.row.churn_rate_pct}`);
    check('…and the history marker now carries the earliest recorded cancellation',
      afterPrior.row.churn_first_cancellation_at !== null,
      `first=${afterPrior.row.churn_first_cancellation_at}`);
    check('…while a subscription canceled BEFORE the month began leaves the denominator, ' +
          'exactly as "active at month start" requires',
      num(afterPrior.row.churn_active_at_month_start) === denomBase - 1,
      `${denomBase} -> ${afterPrior.row.churn_active_at_month_start}`);

    // A cancellation recorded in THIS month moves the numerator by exactly one.
    await svc(`subscriptions?id=eq.${idB}`, { method: 'PATCH',
      body: { status: 'canceled', canceled_at: thisMonth.toISOString() } });
    const afterThis = await view(victim);
    check('a cancellation recorded in THIS month moves the numerator by exactly one — a ' +
          'metric that counts nothing cannot pass this',
      num(afterThis.row.churn_cancellations_month) === 1,
      `cancellations=${afterThis.row.churn_cancellations_month}`);
    const expected = Math.round(
      (1 / num(afterThis.row.churn_active_at_month_start)) * 100 * 10) / 10;
    check('…and the rate is numerator ÷ denominator as the ruling defines it, computed ' +
          'independently from the view’s own published components',
      num(afterThis.row.churn_rate_pct) === expected,
      `rate=${afterThis.row.churn_rate_pct} expected=${expected} ` +
      `(1/${afterThis.row.churn_active_at_month_start})`);

    // ── 4 · no plan-level split exists while Q13 is unresolved ───────────
    section('Q11 · no plan-level churn, and no `kind` reaches the surface');
    // SCOPED TO `churn_*`, and the first draft was not. It matched every column on the
    // view and flagged `stream_coach_plan_cents` — 178's revenue-by-stream column, where
    // `coach_plan` is a payments KIND from the create-checkout:52 vocabulary and has
    // nothing to do with a churn split. A true match for the regex and a false one for the
    // claim, which is why the claim now names the columns it is about.
    const keys = Object.keys(afterThis.row).filter((k) => k.startsWith('churn_'));
    check('arranged: the churn columns are present to be judged',
      keys.length >= 4, `churn columns=[${keys.join(', ')}]`);
    const planLeak = keys.filter((k) => /kind|plan|tier/i.test(k));
    check('no CHURN column is split by plan, kind or tier — a per-plan split would have ' +
          'to pick which of 022’s documented vocabulary or QA’s actual `app` value is ' +
          'authoritative, which is Q13 and the owner’s',
      planLeak.length === 0, `leaked=[${planLeak.join(', ')}]`);

    // ── 5 · the figure is gated, and carries no identifier ──────────────
    section('Q11 · gated on Monetization·view, and disclosing nobody');
    // NO ADMIN ROLE AT ALL, and that is forced by the approved matrix rather than chosen
    // for convenience: ALL FIVE roles — trust_lead, operations_lead, support,
    // content_editor, viewer — hold Monetization·view (155:49-53). There is therefore no
    // role that can be assigned to produce a denial, so the only reachable denial is an
    // unassigned caller. The first draft used `support` and failed for exactly that
    // reason: it read a row, because it is authorized to.
    await unassign(vUid);
    const denied = await view(victim);
    checkDenied('a caller with NO admin role reads NO row from the churn surface — all ' +
      'five approved roles hold Monetization·view, so this is the only denial the matrix ' +
      'makes reachable', {
      saw: denied.row && Object.keys(denied.row).length ? 1 : 0,
      population: 1,
      detail: `status=${denied.status}`,
    });
    await assign(vUid, 'viewer');
    const final = await view(victim);
    const ids = Object.entries(final.row).filter(([, v]) =>
      typeof v === 'string' &&
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v));
    const emails = Object.entries(final.row).filter(([, v]) =>
      typeof v === 'string' && v.includes('@'));
    check('the churn figures disclose no uuid and no email — churn is a population ' +
          'measure and names nobody',
      ids.length === 0 && emails.length === 0,
      `uuid=[${ids.map((x) => x[0])}] email=[${emails.map((x) => x[0])}]`);

    // ── 6 · Q12 · the audit projection cannot leak an actor NAME ─────────
    section('Q12 · the audit projection carries no name for the tail to render');
    // AS THE SIGNED-IN CALLER, not via service_role. `svc` bypasses RLS but `admin_can` is
    // FALSE for service_role, so the view's own WHERE returns nothing — the first draft read
    // keys=0 and reported it as a missing projection rather than as the gate working.
    // `viewer` holds Audit logs·view (155:82).
    const auditRes = await fetch(
      `${process.env.QA_URL}/rest/v1/admin_audit_events?select=*&limit=1`,
      { headers: { apikey: process.env.QA_ANON, Authorization: `Bearer ${victim}` } });
    const aKeys = Object.keys(ONE(await auditRes.json().catch(() => null)) || {});
    check('arranged: the audit projection returned a row to inspect',
      aKeys.length > 0, `keys=${aKeys.length}`);
    const nameish = aKeys.filter((k) => /name|email|first|last/i.test(k));
    check('admin_audit_events exposes NO name or email column, so the actor-anonymous tail ' +
          'is enforced by the SURFACE and not only by the widget that reads it',
      nameish.length === 0, `nameish=[${nameish.join(', ')}]`);
    check('…and it still carries the columns the ruling permits the tail to display',
      ['action', 'category', 'outcome', 'occurred_at'].every((k) => aKeys.includes(k)),
      `keys=${aKeys.join(',')}`);
  } finally {
    await purge();
    await unassign(vUid);
    // ASSERTED, like D19's. `subscriptions` is a billing table and a stray row would
    // misstate revenue on surfaces other suites read.
    const left = await countExact(`subscriptions?stripe_subscription_id=like.${TAG}*&select=id`);
    check('TEARDOWN · every churn fixture was removed, VERIFIED — a stray subscription ' +
          'would misstate revenue on a surface other suites read',
      left === 0, `rows left=${left}`);
    const stillClean = await countExact('subscriptions?canceled_at=not.is.null&select=id');
    check('…and no real subscription was left carrying a cancellation date',
      stillClean === 0, `canceled_at set on ${stillClean} rows`);
  }
  return summary('D20 · Q11 subscription churn + Q12 audit projection');
}

export default await run();
