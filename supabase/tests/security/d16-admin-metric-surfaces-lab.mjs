// D16 · THE AUTHORIZED METRIC SURFACES — migrations 171/172, live against QA.
//
// WHY EVERY ASSERTION HERE IS A DELTA. An aggregate view is the easiest thing in
// this repository to test vacuously: `SELECT count(*)` over an empty table answers
// 0, HTTP 200, and a test that merely asserts "the admin got a row" passes whether
// or not the metric counts the right thing. Worse, four of these five metrics sit on
// populations that are EMPTY or near-empty on QA — checked_in_at on 0 of 2
// registrations, date_of_birth on 0 of 640 profiles, payments at 1 row. So this
// suite INSERTS a known fixture, re-reads, and asserts the specific column MOVED BY
// THE EXPECTED AMOUNT. A metric that counts nothing cannot pass.
//
// WHY THE BOUNDARY CASES ARE THE POINT FOR METRIC-17. The approved design's bucket
// labels overlap (30 and 45 each appear twice), so the only defect that matters is
// an age landing in two buckets or none. Ages 29/30/44/45/59/60 are each placed
// exactly once, and the totals are asserted to reconcile to users_total.
//
// WHY METRIC-02 IS TESTED AS AN AUTHORIZATION SPLIT. Option 3 reports a Session
// basis and a sign-in basis. The sign-in basis reads audit_events, which ruling B-1
// placed in the Security area. If the card leaked that figure to a Users-only role
// it would be an indirect read of the audit population. `support` holds Users·view
// and NOT Security·view in the approved matrix, so that role is the test.
import { IDENT, signIn, rest, mutate, rpc, svc, check, checkNoWrite, countExact,
         section, summary, beginSuite, n } from './lib.mjs';

const ONE = (b) => (Array.isArray(b) ? b[0] : b) || {};
const num = (v) => (v === null || v === undefined ? null : Number(v));

async function uidOf(key) {
  const r = await svc(`user_profiles?email=eq.${encodeURIComponent(IDENT[key].email)}&select=id`);
  return ONE(r.body).id;
}
async function assign(uid, role) {
  await svc(`admin_role_assignments?user_id=eq.${uid}`, { method: 'DELETE' });
  const r = await svc('admin_role_assignments', { method: 'POST', body: { user_id: uid, admin_role: role } });
  return r.status < 300;
}
async function unassign(uid) { if (uid) await svc(`admin_role_assignments?user_id=eq.${uid}`, { method: 'DELETE' }); }

// Read a metric view AS the signed-in caller, not as service: service bypasses RLS
// and admin_can() is false for it, so a service read proves nothing about access.
async function view(who, name) {
  const r = await rest(who, `${name}?select=*`);
  return { status: r.status, rows: n(r.body), row: ONE(r.body) };
}

async function run() {
  beginSuite();
  const victim = await signIn('victim');
  const vUid = await uidOf('victim');
  const attackerUid = await uidOf('attacker');
  let created = { ws: [], reg: [], pay: [], fx: [], pod: [] };

  // Fixtures are deleted by MARKER first, so a crashed earlier run cannot leave rows
  // that make a correct delta assertion fail forever. Two such defects reached this
  // repository already (V5 §161).
  const purge = async () => {
    await svc(`workout_sessions?workout_title=eq.QA-D16-SESSION`, { method: 'DELETE' });
    await svc(`event_registrations?qr_code=like.QA-D16*`, { method: 'DELETE' });
    await svc(`payments?stripe_payment_intent_id=like.QA-D16*`, { method: 'DELETE' });
    await svc(`fx_rates?source=eq.QA-D16-FIXTURE`, { method: 'DELETE' });
    await svc(`accountability_pods?name=eq.QA-D16-POD`, { method: 'DELETE' });
    await svc(`coach_client_relationships?request_message=eq.QA-D16-CCR`, { method: 'DELETE' });
    await svc(`release_status?release_version=like.QA-D16*`, { method: 'DELETE' });
    await svc(`content_reports?reason=eq.QA-D16 moderation probe`, { method: 'DELETE' });
  };

  try {
    await purge();
    await assign(vUid, 'viewer');     // viewer holds Users, Security, Community, Events, Monetization · view

    // ── 1 · the gate, before any metric is trusted ─────────────────────────
    section('gates · an unassigned caller gets no row at all');
    await unassign(vUid);
    for (const v of ['admin_activity_overview', 'admin_user_overview',
                     'admin_events_overview', 'admin_community_overview',
                     'admin_revenue_overview', 'admin_release_status']) {
      const r = await view(victim, v);
      check(`${v} yields ZERO rows to an unassigned caller`, r.rows === 0,
        `status=${r.status} rows=${r.rows}`);
    }
    await assign(vUid, 'viewer');
    for (const v of ['admin_activity_overview', 'admin_user_overview',
                     'admin_events_overview', 'admin_community_overview',
                     'admin_revenue_overview']) {
      const r = await view(victim, v);
      check(`${v} answers a Viewer`, r.rows === 1, `status=${r.status} rows=${r.rows}`);
    }
    // admin_release_status is EXPECTED EMPTY and is asserted separately in §8b:
    // it has no ingestion producer, so "a Viewer sees one row" would be false.

    // ── 2 · METRIC-02 · the two bases, and the authorization split ─────────
    section('METRIC-02 · Session and sign-in, separately gated');
    const before02 = (await view(victim, 'admin_activity_overview')).row;
    const wsIns = await svc('workout_sessions', { method: 'POST', body: {
      user_id: vUid, workout_title: 'QA-D16-SESSION', started_at: new Date().toISOString(),
      status: 'in_progress' } });
    check('arranged: a Session exists for today', wsIns.status < 300, `status=${wsIns.status}`);
    const after02 = (await view(victim, 'admin_activity_overview')).row;
    for (const col of ['session_users_today', 'session_users_week', 'session_users_month']) {
      check(`METRIC-02 ${col} COUNTS a Session inserted today`,
        num(after02[col]) === num(before02[col]) + 1,
        `${before02[col]} -> ${after02[col]}`);
    }
    check('METRIC-02 session_users_prev_month is NOT moved by a session dated today',
      num(after02.session_users_prev_month) === num(before02.session_users_prev_month),
      `${before02.session_users_prev_month} -> ${after02.session_users_prev_month}`);

    // THE SPLIT. support = Users·view yes, Security·view no.
    await assign(vUid, 'support');
    const sup = (await view(victim, 'admin_activity_overview')).row;
    check('METRIC-02 · support (Users, no Security) SEES the Session basis',
      num(sup.session_users_today) !== null, `session_users_today=${sup.session_users_today}`);
    check('METRIC-02 · support is given NULL — not 0 — for the sign-in basis, so the ' +
          'card cannot be read as "nobody signed in"',
      sup.signin_users_today === null && sup.signin_users_month === null,
      `today=${JSON.stringify(sup.signin_users_today)} month=${JSON.stringify(sup.signin_users_month)}`);
    await assign(vUid, 'viewer');
    const vw = (await view(victim, 'admin_activity_overview')).row;
    check('METRIC-02 · a Security-holding role DOES see the sign-in basis',
      num(vw.signin_users_today) !== null && num(vw.signin_users_month) !== null,
      `today=${vw.signin_users_today} month=${vw.signin_users_month}`);
    check('METRIC-02 · the sign-in basis is non-vacuous (audit_events holds ' +
          'authentication rows this month)', num(vw.signin_users_month) >= 1,
      `signin_users_month=${vw.signin_users_month}`);

    // ── 176 · SESSIONS ARE NOT USERS, and the design requires both ─────────
    // The data contract (:97) calls DAU and sessions "distinct required measures",
    // because the approved card shows "947 Daily sessions" beside the DAU figure.
    // The only test that can tell the two apart is one member training TWICE: that is
    // ONE active user and TWO Sessions. A count(*) mistaken for a
    // count(DISTINCT user_id) passes every other assertion in this suite.
    const beforeTwo = (await view(victim, 'admin_activity_overview')).row;
    // The second Session is `completed`, not `in_progress`. A partial unique index
    // allows a member only ONE ACTIVE session at a time — correct product behaviour,
    // nobody is mid-workout twice — so the first draft's second insert returned 409
    // and the assertion failed on MY fixture rather than on the view. Two Sessions in
    // one day is a finished one plus a current one, which is also the real shape of
    // the case the design's "947 Daily sessions" figure counts.
    const ws2 = await svc('workout_sessions', { method: 'POST', body: {
      user_id: vUid, workout_title: 'QA-D16-SESSION', started_at: new Date().toISOString(),
      completed_at: new Date().toISOString(), status: 'completed' } });
    check('arranged: the SAME member records a second Session today (one finished, ' +
          'one active — a member may hold only one ACTIVE session)', ws2.status < 300,
      `status=${ws2.status}`);
    const afterTwo = (await view(victim, 'admin_activity_overview')).row;
    check('METRIC-02 · sessions_today counts the SESSION (+1), so it is count(*) and ' +
          'not a distinct-user count',
      num(afterTwo.sessions_today) === num(beforeTwo.sessions_today) + 1,
      `${beforeTwo.sessions_today} -> ${afterTwo.sessions_today}`);
    check('METRIC-02 · session_users_today does NOT move, because it is the same ' +
          'member — this is the assertion that tells the two measures apart',
      num(afterTwo.session_users_today) === num(beforeTwo.session_users_today),
      `${beforeTwo.session_users_today} -> ${afterTwo.session_users_today}`);
    check('METRIC-02 · sessions_today is >= session_users_today, which must hold for ' +
          'any population',
      num(afterTwo.sessions_today) >= num(afterTwo.session_users_today),
      `sessions=${afterTwo.sessions_today} users=${afterTwo.session_users_today}`);
    check('METRIC-02 · the session count is gated with the rest of the Session basis',
      num(afterTwo.sessions_month) !== null, `sessions_month=${afterTwo.sessions_month}`);

    // ── 176 · the windows are PUBLISHED, so "today" is not an assumption ───
    // The contract (:98) names the timezone as an unsettled sub-question. The view
    // cannot answer it, so it discloses what it actually used.
    const ws = afterTwo;
    const coherent = ws.day_start && ws.week_start && ws.month_start &&
      new Date(ws.day_start) >= new Date(ws.month_start) &&
      new Date(ws.week_start) >= new Date(ws.month_start) - 0;
    check('METRIC-02 · the day, week and month boundaries are published and coherent, ' +
          'so a reader can tell what window produced each figure',
      Boolean(coherent), `day=${ws.day_start} week=${ws.week_start} month=${ws.month_start}`);
    check('METRIC-02 · the timezone those boundaries were computed in is NAMED rather ' +
          'than assumed',
      typeof ws.window_timezone === 'string' && ws.window_timezone.length > 0,
      `window_timezone=${JSON.stringify(ws.window_timezone)}`);
    // The support role must not gain the Session basis through the new columns.
    await assign(vUid, 'support');
    const supWin = (await view(victim, 'admin_activity_overview')).row;
    check('METRIC-02 · support still sees the session COUNT (Users-gated) and still ' +
          'sees NULL for the sign-in basis — the new columns did not widen anything',
      num(supWin.sessions_today) !== null && supWin.signin_users_today === null,
      `sessions_today=${supWin.sessions_today} signin=${JSON.stringify(supWin.signin_users_today)}`);
    await assign(vUid, 'viewer');

    // ── 3 · METRIC-17 · half-open buckets, placed once each ────────────────
    section('METRIC-17 · the overlapping labels resolved to half-open intervals');
    const origAge = ONE((await svc(`user_profiles?id=eq.${vUid}&select=age,date_of_birth`)).body);
    const bucketFor = async (age) => {
      await svc(`user_profiles?id=eq.${vUid}`, { method: 'PATCH', body: { age, date_of_birth: null } });
      const r = (await view(victim, 'admin_user_overview')).row;
      return r;
    };
    const base = await (async () => {
      await svc(`user_profiles?id=eq.${vUid}`, { method: 'PATCH', body: { age: null, date_of_birth: null } });
      return (await view(victim, 'admin_user_overview')).row;
    })();
    const EDGES = [[29, 'age_18_30'], [30, 'age_30_45'], [44, 'age_30_45'],
                   [45, 'age_45_60'], [59, 'age_45_60'], [60, 'age_out_of_range'],
                   [17, 'age_out_of_range']];
    for (const [age, expected] of EDGES) {
      const r = await bucketFor(age);
      const moved = ['age_18_30', 'age_30_45', 'age_45_60', 'age_unknown', 'age_out_of_range']
        .filter((c) => num(r[c]) > num(base[c]));
      check(`METRIC-17 · age ${age} lands in ${expected} and NOWHERE else`,
        moved.length === 1 && moved[0] === expected, `moved=[${moved.join(',')}]`);
      const sum = ['age_18_30', 'age_30_45', 'age_45_60', 'age_unknown', 'age_out_of_range']
        .reduce((a, c) => a + num(r[c]), 0);
      check(`METRIC-17 · at age ${age} the buckets reconcile to users_total ` +
            '(nobody is silently dropped)', sum === num(r.users_total),
        `sum=${sum} users_total=${r.users_total}`);
    }
    // date_of_birth must WIN over the age fallback, or an edited age could override
    // the authoritative column.
    const dob = new Date(); dob.setFullYear(dob.getFullYear() - 35);
    await svc(`user_profiles?id=eq.${vUid}`, { method: 'PATCH',
      body: { age: 20, date_of_birth: dob.toISOString().slice(0, 10) } });
    const pref = (await view(victim, 'admin_user_overview')).row;
    check('METRIC-17 · date_of_birth (35) is preferred over the age column (20)',
      num(pref.age_30_45) === num(base.age_30_45) + 1 && num(pref.age_18_30) === num(base.age_18_30),
      `30_45 ${base.age_30_45}->${pref.age_30_45}, 18_30 ${base.age_18_30}->${pref.age_18_30}`);
    await svc(`user_profiles?id=eq.${vUid}`, { method: 'PATCH',
      body: { age: origAge.age ?? null, date_of_birth: origAge.date_of_birth ?? null } });

    // ── §193 · "Clients served", and the denominator the design's arithmetic fixes ──
    section('"Clients served" · counted exactly, and averaged per ACTIVE coach');
    {
      const row = (await view(victim, 'admin_user_overview')).row;

      // COUNTED INDEPENDENTLY, not re-read from the view that is under test. `countExact`
      // uses the content-range header, so it does not saturate at the 1000-row page cap —
      // which matters here: QA holds 170 active relationships today and a body-length
      // count would quietly become wrong as that grows past 1000.
      const served = await countExact('coach_client_relationships?status=eq.active&select=id');
      check('coach_clients_served equals an INDEPENDENT exact count of active ' +
            'relationships — not a body length, which saturates at the page cap',
        num(row.coach_clients_served) === served,
        `view=${row.coach_clients_served} independent=${served}`);

      // NOT VACUOUS. A count assertion over an empty population passes whatever the view
      // computes — §139.5's lesson, and the reason checkDenied exists.
      check('…and that was asserted against a NON-EMPTY population',
        served > 0, `active relationships=${served}`);

      // THE DENOMINATOR, RECONCILED AGAINST THE VIEW'S OWN OTHER COLUMNS. The approved
      // card reads 2,210 · "avg 15.7 per coach" · Active "141 of 164": 2210/141 = 15.7
      // while 2210/164 = 13.5, so the average is per ACTIVE coach. This recomputes it from
      // coaches_active_this_month — a figure METRIC-03 already proves above — so the two
      // halves of the card cannot drift apart.
      const activeCoaches = num(row.coaches_active_this_month);
      const expectAvg = activeCoaches === 0
        ? null
        : Math.round((served / activeCoaches) * 10) / 10;
      check('coach_clients_per_active_coach reconciles with coaches_active_this_month — ' +
            'the ACTIVE denominator the approved card\u2019s own arithmetic fixes ' +
            '(2210/141 = 15.7, where 2210/164 would be 13.5)',
        num(row.coach_clients_per_active_coach) === expectAvg,
        `view=${row.coach_clients_per_active_coach} expected=${expectAvg} ` +
        `(${served}/${activeCoaches})`);

      // The zero-denominator arm renders NULL rather than 0. QA carries active coaches, so
      // the arm is NOT reachable here and is reported as such instead of claimed: this
      // asserts only the half that IS measurable — a real denominator yields a real number.
      check('…and with a real denominator the average is a NUMBER, not null — the null ' +
            'arm (no active coach to divide by) is UNMEASURABLE on this QA, which has ' +
            `${activeCoaches}, and is not claimed here`,
        activeCoaches > 0 && row.coach_clients_per_active_coach !== null,
        `active_coaches=${activeCoaches} avg=${row.coach_clients_per_active_coach}`);

      // DELTA. An aggregate that counts nothing cannot pass: flip one relationship and
      // require the figure to move by exactly one.
      // ANY relationship row, not the probe client's. The first draft asked for
      // `client_id=eq.${attackerUid}` and found none — that row is arranged and torn down
      // by another section of this suite, so depending on it made the delta's availability
      // a function of test ORDER. The delta does not care whose relationship moves.
      const anyRel = await svc(
        'coach_client_relationships?select=id,status&limit=1');
      const rel = ONE(anyRel.body);
      if (rel.id) {
        const was = rel.status;
        const flipTo = was === 'active' ? 'cancelled' : 'active';
        await svc(`coach_client_relationships?id=eq.${rel.id}`, { method: 'PATCH',
          body: { status: flipTo } });
        const after = (await view(victim, 'admin_user_overview')).row;
        const expected = served + (flipTo === 'active' ? 1 : -1);
        check('flipping ONE relationship moves coach_clients_served by exactly one — a ' +
              'metric that counts nothing cannot pass this',
          num(after.coach_clients_served) === expected,
          `${served} -> ${after.coach_clients_served} (expected ${expected})`);
        await svc(`coach_client_relationships?id=eq.${rel.id}`, { method: 'PATCH',
          body: { status: was } });
        const restored = (await view(victim, 'admin_user_overview')).row;
        check('…and restoring it returns the figure, so the fixture left nothing behind',
          num(restored.coach_clients_served) === served,
          `back to ${restored.coach_clients_served}`);
      } else {
        check('arranged: a relationship exists to flip for the delta', false,
          'no coach_client_relationships row for the probe client');
      }
    }

    // ── 4 · METRIC-03 · active coaches on a calendar month ────────────────
    section('METRIC-03 · calendar month');
    const u0 = (await view(victim, 'admin_user_overview')).row;
    check('METRIC-03 · active + no-client partition the coach population exactly',
      num(u0.coaches_active_this_month) + num(u0.coaches_no_client_this_month) === num(u0.coaches_total),
      `${u0.coaches_active_this_month} + ${u0.coaches_no_client_this_month} = ${u0.coaches_total}`);
    // NON-VACUITY IS ARRANGED, NOT ASSUMED. The obvious shortcut — "QA holds 118
    // active relationships so the figure cannot be 0" — is FALSE, and measuring it
    // proved so: of the 118 distinct coach_ids on active rows only ONE belongs to a
    // profile with role='coach' (59 of the first 60 are `trust_operator`). The live
    // figure of 1 is therefore CORRECT and the inference was wrong. So the metric is
    // proved by inserting a relationship for a real coach and watching it move.
    const coachUid = await uidOf('coach');
    const ccr = await svc('coach_client_relationships', { method: 'POST', body: {
      coach_id: coachUid, client_id: attackerUid, status: 'active',
      initiated_by: coachUid, request_message: 'QA-D16-CCR' } });
    check('arranged: a real coach holds an active client relationship', ccr.status < 300,
      `status=${ccr.status}`);
    const u1 = (await view(victim, 'admin_user_overview')).row;
    const coachWasActive = num(u1.coaches_active_this_month) === num(u0.coaches_active_this_month);
    check('METRIC-03 · an active relationship makes its coach count as active this month',
      num(u1.coaches_active_this_month) >= num(u0.coaches_active_this_month) &&
      (coachWasActive || num(u1.coaches_active_this_month) === num(u0.coaches_active_this_month) + 1),
      `${u0.coaches_active_this_month} -> ${u1.coaches_active_this_month}` +
      (coachWasActive ? ' (p1-coach already held one)' : ''));
    check('METRIC-03 · the partition still holds exactly after the insert',
      num(u1.coaches_active_this_month) + num(u1.coaches_no_client_this_month) === num(u1.coaches_total),
      `${u1.coaches_active_this_month} + ${u1.coaches_no_client_this_month} = ${u1.coaches_total}`);
    check('METRIC-03 · the active figure is non-vacuous',
      num(u1.coaches_active_this_month) >= 1,
      `coaches_active_this_month=${u1.coaches_active_this_month}`);

    // ── 5 · METRIC-13 · a pod is an accountability_pods row ───────────────
    section('METRIC-13 · pods');
    const c0 = (await view(victim, 'admin_community_overview')).row;
    const podIns = await svc('accountability_pods', { method: 'POST', body: {
      coach_id: vUid, name: 'QA-D16-POD', max_members: 5, status: 'active' } });
    check('arranged: a pod exists', podIns.status < 300, `status=${podIns.status}`);
    const c1 = (await view(victim, 'admin_community_overview')).row;
    check('METRIC-13 · pods_total counts an accountability_pods row',
      num(c1.pods_total) === num(c0.pods_total) + 1, `${c0.pods_total} -> ${c1.pods_total}`);
    check('METRIC-13 · community_groups_total is NOT merged into the pod count',
      num(c1.community_groups_total) === num(c0.community_groups_total),
      `${c0.community_groups_total} -> ${c1.community_groups_total}`);

    // ── 6 · METRIC-14 · attended / registered, on the EXISTING column ─────
    section('METRIC-14 · attendance uses checked_in_at, which already exists');
    // TWO events, not two registrations on one: event_registrations carries
    // UNIQUE(event_id, user_id) (122:288), so the first draft's second insert
    // returned 409 and the metric assertions failed on MY fixture, not the view.
    const evs = (await svc('events?select=id&limit=2')).body;
    check('arranged: QA holds the two events this fixture needs', n(evs) === 2,
      `events available=${n(evs)}`);
    const e0 = (await view(victim, 'admin_events_overview')).row;
    const r1 = await svc('event_registrations', { method: 'POST', body: {
      event_id: evs[0].id, user_id: vUid, qr_code: 'QA-D16-A', status: 'registered' } });
    const r2 = await svc('event_registrations', { method: 'POST', body: {
      event_id: evs[1].id, user_id: vUid, qr_code: 'QA-D16-B', status: 'checked_in',
      checked_in_at: new Date().toISOString() } });
    check('arranged: one registration attended, one not', r1.status < 300 && r2.status < 300,
      `${r1.status}/${r2.status}`);
    const e1 = (await view(victim, 'admin_events_overview')).row;
    check('METRIC-14 · registrations_total counts both',
      num(e1.event_registrations_total) === num(e0.event_registrations_total) + 2,
      `${e0.event_registrations_total} -> ${e1.event_registrations_total}`);
    check('METRIC-14 · attended counts ONLY the one with checked_in_at',
      num(e1.event_registrations_attended) === num(e0.event_registrations_attended) + 1,
      `${e0.event_registrations_attended} -> ${e1.event_registrations_attended}`);
    const expectRate = Math.round(num(e1.event_registrations_attended) * 1000
      / num(e1.event_registrations_total)) / 10;
    check('METRIC-14 · the rate is attended / registered, not registrations / capacity',
      Math.abs(num(e1.event_attendance_rate_pct) - expectRate) < 0.11,
      `view=${e1.event_attendance_rate_pct} expected=${expectRate}`);
    check('METRIC-14 · the 30-day window counts a registration made now',
      num(e1.event_registrations_30d) >= 2, `30d=${e1.event_registrations_30d}`);

    // ── 7 · METRIC-06a/06b · the owner's calculation, and no fabrication ──
    section("METRIC-06 · gross / commission / net, and what the view REFUSES to invent");
    const p0 = (await view(victim, 'admin_revenue_overview')).row;
    const payIns = await svc('payments', { method: 'POST', body: {
      user_id: vUid, kind: 'coach', amount_cents: 5000, currency: 'usd', status: 'paid',
      commission_rate: 0.10, stripe_payment_intent_id: 'QA-D16-RATED' } });
    check('arranged: a coaching payment with a recorded rate', payIns.status < 300, `status=${payIns.status}`);
    const p1 = (await view(victim, 'admin_revenue_overview')).row;
    check('METRIC-06b · gross = sum of qualifying coaching amounts at source',
      num(p1.gross_coaching_cents) === num(p0.gross_coaching_cents) + 5000,
      `${p0.gross_coaching_cents} -> ${p1.gross_coaching_cents}`);
    check('METRIC-06b · commission = amount x the rate as it applied (5000 x 0.10 = 500)',
      num(p1.platform_commission_cents) === num(p0.platform_commission_cents) + 500,
      `${p0.platform_commission_cents} -> ${p1.platform_commission_cents}`);
    check('METRIC-06b · net = gross - commission, arithmetically consistent in the row',
      num(p1.net_platform_cents) === num(p1.gross_coaching_cents) - num(p1.platform_commission_cents),
      `${p1.gross_coaching_cents} - ${p1.platform_commission_cents} = ${p1.net_platform_cents}`);

    // NO FABRICATION. A payment with no recorded rate must raise the MISSING count
    // and must NOT be given a substituted rate.
    const unrated = await svc('payments', { method: 'POST', body: {
      user_id: vUid, kind: 'coach', amount_cents: 7000, currency: 'usd', status: 'paid',
      stripe_payment_intent_id: 'QA-D16-UNRATED' } });
    check('arranged: a coaching payment with NO recorded rate', unrated.status < 300, `status=${unrated.status}`);
    const p2 = (await view(victim, 'admin_revenue_overview')).row;
    check('METRIC-06b · gross includes the unrated payment',
      num(p2.gross_coaching_cents) === num(p1.gross_coaching_cents) + 7000,
      `${p1.gross_coaching_cents} -> ${p2.gross_coaching_cents}`);
    check('METRIC-06b · commission does NOT move for a payment with no recorded rate ' +
          '(no rate is substituted onto it)',
      num(p2.platform_commission_cents) === num(p1.platform_commission_cents),
      `${p1.platform_commission_cents} -> ${p2.platform_commission_cents}`);
    check('METRIC-06b · the gap is DISCLOSED: commission_rate_missing increments',
      num(p2.commission_rate_missing) === num(p1.commission_rate_missing) + 1,
      `${p1.commission_rate_missing} -> ${p2.commission_rate_missing}`);

    // EXCLUSION, asserted rather than assumed.
    const ticket = await svc('payments', { method: 'POST', body: {
      user_id: vUid, kind: 'event_ticket', amount_cents: 9900, currency: 'usd', status: 'paid',
      stripe_payment_intent_id: 'QA-D16-TICKET' } });
    const coachPlan = await svc('payments', { method: 'POST', body: {
      user_id: vUid, kind: 'coach_plan', amount_cents: 4900, currency: 'usd', status: 'paid',
      stripe_payment_intent_id: 'QA-D16-PLAN' } });
    check('arranged: a ticket and a coach_plan payment', ticket.status < 300 && coachPlan.status < 300,
      `${ticket.status}/${coachPlan.status}`);
    const p3 = (await view(victim, 'admin_revenue_overview')).row;
    check('METRIC-06b · event_ticket and coach_plan are EXCLUDED from coaching gross',
      num(p3.gross_coaching_cents) === num(p2.gross_coaching_cents),
      `${p2.gross_coaching_cents} -> ${p3.gross_coaching_cents}`);
    check('METRIC-06b · the exclusion is VISIBLE: excluded_non_coaching increments by 2',
      num(p3.excluded_non_coaching) === num(p2.excluded_non_coaching) + 2,
      `${p2.excluded_non_coaching} -> ${p3.excluded_non_coaching}`);
    // An unpaid coaching payment is not revenue.
    await svc('payments', { method: 'POST', body: {
      user_id: vUid, kind: 'coach', amount_cents: 11100, currency: 'usd', status: 'pending',
      commission_rate: 0.10, stripe_payment_intent_id: 'QA-D16-PENDING' } });
    const p4 = (await view(victim, 'admin_revenue_overview')).row;
    check('METRIC-06b · a PENDING coaching payment is not counted as revenue',
      num(p4.gross_coaching_cents) === num(p3.gross_coaching_cents),
      `${p3.gross_coaching_cents} -> ${p4.gross_coaching_cents}`);

    // ── 178 · REVENUE BY STREAM, and the split as recorded ────────────────
    // The approved design requires both (SCREEN-INVENTORY "Data each page needs"):
    // "revenue by stream" on the Dashboard and "payouts, commission" on Ecosystem.
    // The fixtures above already placed one payment in each of four streams, so these
    // assertions run against a genuinely multi-stream population rather than one kind.
    const st = (await view(victim, 'admin_revenue_overview')).row;
    check('178 · each stream is summed SEPARATELY — a coach payment does not land in ' +
          'the event_ticket column',
      num(st.stream_coach_cents) === 12000 &&      // 5000 rated + 7000 unrated
      num(st.stream_event_ticket_cents) === 9900 &&
      num(st.stream_coach_plan_cents) === 4900,
      `coach=${st.stream_coach_cents} ticket=${st.stream_event_ticket_cents} ` +
      `coach_plan=${st.stream_coach_plan_cents}`);
    check('178 · the six named streams plus `other` RECONCILE to the paid total, so no ' +
          'revenue can be silently dropped by an unrecognised kind',
      num(st.stream_coach_cents) + num(st.stream_coach_plan_cents) +
      num(st.stream_self_guided_cents) + num(st.stream_ai_guided_cents) +
      num(st.stream_event_ticket_cents) + num(st.stream_package_cents) +
      num(st.stream_other_cents) === num(st.paid_total_cents),
      `sum of streams vs paid_total=${st.paid_total_cents}`);
    check('178 · gross coaching equals the coach + package streams, so the METRIC-06b ' +
          'selector and the stream columns agree rather than drifting',
      num(st.gross_coaching_cents) ===
        num(st.stream_coach_cents) + num(st.stream_package_cents),
      `gross=${st.gross_coaching_cents} coach+package=` +
      `${num(st.stream_coach_cents) + num(st.stream_package_cents)}`);
    // THE SPLIT IS REPORTED, NOT DERIVED. Every fixture payment was inserted without a
    // coach_payout, so the totals must stay 0 and the gap must be disclosed — if the
    // view derived the split from amount x rate, coach_payout_cents would be non-zero.
    check('178 · the payout split is READ as recorded and never derived from ' +
          'amount x commission_rate',
      num(st.coach_payout_cents) === 0 && num(st.platform_fee_cents) === 0,
      `coach_payout=${st.coach_payout_cents} platform_fee=${st.platform_fee_cents}`);
    check('178 · …and the gap is DISCLOSED: payout_missing counts the coaching payments ' +
          'carrying no recorded split',
      num(st.payout_missing) >= 2,
      `payout_missing=${st.payout_missing}`);

    // METRIC-06a · FX is RECORDED, never assumed. NULL until a rate exists.
    check('METRIC-06a · with no usd->gbp rate recorded, the FX columns are NULL — the ' +
          'view does not invent a conversion',
      p4.fx_usd_gbp_rate === null && p4.fx_as_of === null && p4.fx_source === null,
      `rate=${JSON.stringify(p4.fx_usd_gbp_rate)} as_of=${JSON.stringify(p4.fx_as_of)}`);
    const fxIns = await svc('fx_rates', { method: 'POST', body: {
      base: 'usd', quote: 'gbp', rate: 0.79, as_of: new Date().toISOString().slice(0, 10),
      source: 'QA-D16-FIXTURE' } });
    check('arranged: an FX rate is recorded', fxIns.status < 300, `status=${fxIns.status}`);
    const p5 = (await view(victim, 'admin_revenue_overview')).row;
    check('METRIC-06a · the recorded rate, its date AND its source all reach the surface',
      Number(p5.fx_usd_gbp_rate) === 0.79 && p5.fx_as_of !== null && p5.fx_source === 'QA-D16-FIXTURE',
      `rate=${p5.fx_usd_gbp_rate} as_of=${p5.fx_as_of} source=${p5.fx_source}`);
    check('METRIC-06a · source_currency is declared, so no figure is currency-ambiguous',
      p5.source_currency === 'usd', `source_currency=${p5.source_currency}`);

    // ── 8 · the 158 lesson · a read surface must refuse mutation ──────────
    section('fx_rates · a read-only record cannot be written through PostgREST');
    // No `count=exact` header: these two counts are BODY LENGTHS, and `fx_rates` holds a
    // couple of rows, so the page cap cannot reach them. The header used to be passed here
    // and was silently dropped by `svc` — it is removed rather than made to work, because a
    // header that implies a counting method the assertion does not use is a lie about the
    // evidence.
    const fxBefore = (await svc('fx_rates?select=id'));
    const wIns = await mutate(victim, 'fx_rates', 'POST', {
      base: 'usd', quote: 'eur', rate: 1.0, as_of: '2026-01-01', source: 'QA-D16-FORBIDDEN' });
    const fxAfterIns = (await svc('fx_rates?select=id'));
    checkNoWrite('an admin-layer caller CANNOT insert an FX rate', {
      before: n(fxBefore.body), after: n(fxAfterIns.body), status: wIns.status,
      detail: 'an FX rate the Admin layer could set is a revenue figure it could set' });
    const wPatch = await mutate(victim, `fx_rates?source=eq.QA-D16-FIXTURE`, 'PATCH', { rate: 99 });
    const stillOk = ONE((await svc('fx_rates?source=eq.QA-D16-FIXTURE&select=rate')).body);
    check('an admin-layer caller CANNOT alter a recorded FX rate (checked by re-reading ' +
          'the row, not by the PATCH status — PostgREST answers 204 either way)',
      Number(stillOk.rate) === 0.79, `status=${wPatch.status} rate still ${stillOk.rate}`);
    const wDel = await mutate(victim, `fx_rates?source=eq.QA-D16-FIXTURE`, 'DELETE', null);
    const survives = (await svc('fx_rates?source=eq.QA-D16-FIXTURE&select=id')).body;
    check('an admin-layer caller CANNOT delete a recorded FX rate',
      n(survives) === 1, `status=${wDel.status} rows surviving=${n(survives)}`);

    // ── 8b · METRIC-11 · two verdicts that must not be collapsed ──────────
    section('METRIC-11 · CI and the V5 gate ledger, separately and with provenance');
    // THE EMPTY STATE IS THE CURRENT TRUTH, SO IT IS ASSERTED RATHER THAN ASSUMED.
    // No ingestion producer exists: the egress/webhook path at data-contract :220 is
    // gated on P10 and CONF-D9, neither released. A Viewer therefore sees NO ROW,
    // and the card renders its approved A11 state. If someone later seeds this table
    // to make a dashboard look finished, this assertion is what catches it.
    const relEmpty = await view(victim, 'admin_release_status');
    const relAll = await svc('release_status?select=id');
    check('METRIC-11 · the registry is EMPTY — no release was invented to populate it',
      n(relAll.body) === 0, `table rows=${n(relAll.body)}`);

    // ── 174's ROW SHAPE IS PART OF THE CONTRACT ───────────────────────────
    // 173 returned no row both when the caller lacked System·view and when nothing
    // was recorded, so a client had to guess which, and would necessarily mislabel
    // one of them. 174 separates the cases the way 172 already does for METRIC-02.
    check('METRIC-11 · an AUTHORIZED caller with nothing recorded gets exactly ONE ' +
          'row, not zero — so the card can say "not recorded" instead of guessing ' +
          'at a permission failure that did not happen',
      relEmpty.rows === 1, `rows=${relEmpty.rows} status=${relEmpty.status}`);
    const allNull = Object.entries(relEmpty.row || {}).filter(([, v]) => v !== null);
    check('METRIC-11 · every column of that row is NULL, so it carries no claim ' +
          'about any release',
      relEmpty.rows === 1 && allNull.length === 0,
      `non-null columns=[${allNull.map((x) => x[0]).join(',')}]`);
    await unassign(vUid);
    const relDenied = await view(victim, 'admin_release_status');
    check('METRIC-11 · an UNASSIGNED caller still gets NO row — the all-NULL row is ' +
          'for the authorized-but-empty case only, and is not a disclosure',
      relDenied.rows === 0, `rows=${relDenied.rows}`);
    await assign(vUid, 'viewer');

    // THE ANTI-FABRICATION CONSTRAINTS MUST ACTUALLY REFUSE. A CHECK nobody has
    // tried to violate is a comment.
    const badProv = await svc('release_status', { method: 'POST', body: {
      release_version: 'QA-D16-1', environment: 'staging', ci_status: 'Passing' } });
    check('METRIC-11 · a CI verdict WITHOUT its source and timestamp is REFUSED by ' +
          'the database, not merely discouraged',
      badProv.status >= 400, `status=${badProv.status}`);
    const badVocab = await svc('release_status', { method: 'POST', body: {
      release_version: 'QA-D16-2', environment: 'staging', gate_verdict: 'BLOCKED',
      gate_source: 'x', gate_recorded_at: new Date().toISOString() } });
    check('METRIC-11 · a gate verdict outside the ruled PASS/PARTIAL/FAIL vocabulary ' +
          'is REFUSED — no state vocabulary is invented at write time',
      badVocab.status >= 400, `status=${badVocab.status}`);
    const badCounts = await svc('release_status', { method: 'POST', body: {
      release_version: 'QA-D16-3', environment: 'staging', gate_verdict: 'FAIL',
      gate_source: 'x', gate_recorded_at: new Date().toISOString(),
      gates_pass: 5, gates_partial: 2, gates_fail: 8, gates_total: 99 } });
    check('METRIC-11 · a gate tally that does not reconcile to its total is REFUSED',
      badCounts.status >= 400, `status=${badCounts.status}`);

    // NOW RECORD A REAL, CITABLE DISAGREEMENT and prove both halves survive it.
    const now = new Date().toISOString();
    const rel = await svc('release_status', { method: 'POST', body: {
      release_version: 'QA-D16-REL', environment: 'QA-D16-env', is_current: true,
      ci_status: 'Passing', ci_checks_passed: 6, ci_checks_total: 6,
      ci_source: 'QA-D16 fixture', ci_recorded_at: now,
      gate_verdict: 'FAIL', gates_pass: 5, gates_partial: 2, gates_fail: 8,
      gates_total: 15, gate_source: 'QA-D16 fixture', gate_recorded_at: now } });
    check('arranged: a release recording CI Passing AND gate FAIL', rel.status < 300,
      `status=${rel.status}`);
    const relRow = (await view(victim, 'admin_release_status')).row;
    check('METRIC-11 · a System-holding role reads the recorded release',
      relRow.release_version === 'QA-D16-REL', `version=${relRow.release_version}`);
    check('METRIC-11 · BOTH verdicts reach the surface and the DISAGREEMENT survives ' +
          'intact — CI Passing beside gate FAIL, which is the real current state',
      relRow.ci_status === 'Passing' && relRow.gate_verdict === 'FAIL',
      `ci=${relRow.ci_status} gate=${relRow.gate_verdict}`);
    check('METRIC-11 · each verdict carries its OWN source and timestamp',
      relRow.ci_source !== null && relRow.ci_recorded_at !== null &&
      relRow.gate_source !== null && relRow.gate_recorded_at !== null,
      `ci=(${relRow.ci_source}, ${relRow.ci_recorded_at !== null}) ` +
      `gate=(${relRow.gate_source}, ${relRow.gate_recorded_at !== null})`);
    // THE COLLAPSE THE OWNER FORBADE, asserted structurally rather than trusted.
    const collapsed = Object.keys(relRow).filter((k) =>
      /^(overall|combined|release)_?(status|state|verdict|badge)$/.test(k) ||
      k === 'is_blocked' || k === 'is_releasable');
    check('METRIC-11 · NO column combines the two verdicts — the owner ruled they ' +
          '"must not be collapsed", and a single badge column would assert a release ' +
          'verdict neither authority gave',
      collapsed.length === 0, `collapsing columns=[${collapsed.join(',')}]`);
    // One current release per environment, enforced not hoped for.
    const dupe = await svc('release_status', { method: 'POST', body: {
      release_version: 'QA-D16-DUPE', environment: 'QA-D16-env', is_current: true } });
    check('METRIC-11 · a SECOND current release for the same environment is REFUSED',
      dupe.status >= 400, `status=${dupe.status}`);

    // The 158 posture, again: a read surface refuses mutation.
    const relBefore = await svc('release_status?select=id');
    const relIns = await mutate(victim, 'release_status', 'POST', {
      release_version: 'QA-D16-FORBIDDEN', environment: 'x' });
    const relAfter = await svc('release_status?select=id');
    checkNoWrite('an admin-layer caller CANNOT record a release status', {
      before: n(relBefore.body), after: n(relAfter.body), status: relIns.status,
      detail: 'a release verdict the Admin layer could write is one it could invent' });
    const relPatch = await mutate(victim,
      'release_status?release_version=eq.QA-D16-REL', 'PATCH', { ci_status: 'Failing' });
    const relStill = ONE((await svc(
      'release_status?release_version=eq.QA-D16-REL&select=ci_status')).body);
    check('an admin-layer caller CANNOT flip a recorded CI verdict (asserted by ' +
          're-reading the row, never by the PATCH status)',
      relStill.ci_status === 'Passing', `status=${relPatch.status} still ${relStill.ci_status}`);

    // ── 8c · the MODERATION QUEUE's resolve path, which had NO live coverage ──
    // `admin_moderate_content` is proved in D15 (§1292). `admin_resolve_report` had
    // ZERO references in any suite — and the Ecosystem moderation queue now calls it, so
    // a UI was shipping against an unproven write path. That is the gap this closes.
    section('moderation · admin_resolve_report, gated and non-destructive');
    const postRow = ONE((await svc('community_posts?select=id,moderation_state&limit=1')).body);
    check('arranged: QA holds a community post to report', Boolean(postRow.id),
      `post=${postRow.id}`);

    const mkReport = async () => {
      await svc(`content_reports?target_id=eq.${postRow.id}`, { method: 'DELETE' });
      const r = await svc('content_reports', { method: 'POST',
        headers: { Prefer: 'return=representation' },
        body: { reporter_id: attackerUid, target_type: 'post', target_id: postRow.id,
                reason: 'QA-D16 moderation probe' } });
      return ONE(r.body).id;
    };
    const reportId = await mkReport();
    check('arranged: an OPEN report exists', Boolean(reportId), `report=${reportId}`);

    // `resolved_at IS NULL` IS the queue, by 170's own comment.
    const openNow = await svc('content_reports?resolved_at=is.null&select=id');
    check('the OPEN queue is `resolved_at IS NULL`, and the new report is in it',
      n(openNow.body) >= 1, `open=${n(openNow.body)}`);

    // DENIAL FIRST, and asserted by re-reading the row. `viewer` holds Community·view
    // and NOT Community·update, so the resolve must be refused — and a PostgREST status
    // alone proves nothing about whether the row changed.
    await assign(vUid, 'viewer');
    const denied = await rpc(victim, 'admin_resolve_report', { p_report_id: reportId });
    const afterDenied = ONE((await svc(
      `content_reports?id=eq.${reportId}&select=resolved_at,resolved_by`)).body);
    check('a role WITHOUT Community·update cannot resolve a report — verified by ' +
          're-reading resolved_at, not by the RPC status',
      afterDenied.resolved_at === null && afterDenied.resolved_by === null,
      `status=${denied.status} resolved_at=${JSON.stringify(afterDenied.resolved_at)}`);

    // GRANT. content_editor holds Community·update in the approved matrix.
    await assign(vUid, 'content_editor');
    const granted = await rpc(victim, 'admin_resolve_report', { p_report_id: reportId });
    const afterGranted = ONE((await svc(
      `content_reports?id=eq.${reportId}&select=resolved_at,resolved_by`)).body);
    check('a role WITH Community·update resolves it, and resolved_by records WHO did',
      granted.status < 300 && afterGranted.resolved_at !== null &&
      afterGranted.resolved_by === vUid,
      `status=${granted.status} resolved_at=${afterGranted.resolved_at !== null} ` +
      `resolved_by=${afterGranted.resolved_by === vUid}`);

    const goneFromQueue = await svc(
      `content_reports?resolved_at=is.null&select=id&id=eq.${reportId}`);
    check('…and the report LEAVES the open queue',
      n(goneFromQueue.body) === 0, `still open=${n(goneFromQueue.body)}`);

    // THE CLAIM THE UI MAKES, PROVED. The Dismiss dialog tells the moderator "the
    // reported content is left exactly as it is". If resolving also moderated, that
    // sentence would be false.
    const postAfter = ONE((await svc(
      `community_posts?id=eq.${postRow.id}&select=moderation_state,moderated_by,content`)).body);
    check('resolving a report changes NOTHING about the content — the moderation state, ' +
          'the moderator and the text are all untouched, which is what the Dismiss ' +
          'dialog promises',
      postAfter.moderation_state === postRow.moderation_state &&
      postAfter.moderated_by === null,
      `state=${postAfter.moderation_state} (was ${postRow.moderation_state}) ` +
      `moderated_by=${JSON.stringify(postAfter.moderated_by)}`);

    await svc(`content_reports?target_id=eq.${postRow.id}`, { method: 'DELETE' });
    await assign(vUid, 'viewer');

    // ── 9 · no metric view discloses an individual ────────────────────────
    section('disclosure · the aggregates carry no identifier');
    for (const v of ['admin_activity_overview', 'admin_user_overview',
                     'admin_events_overview', 'admin_community_overview',
                     'admin_revenue_overview', 'admin_release_status']) {
      const row = (await view(victim, v)).row;
      const leaks = Object.entries(row).filter(([k, val]) =>
        typeof val === 'string' &&
        /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(val));
      const emails = Object.entries(row).filter(([, val]) =>
        typeof val === 'string' && val.includes('@'));
      check(`${v} exposes no uuid and no email`,
        leaks.length === 0 && emails.length === 0,
        `uuid=[${leaks.map((x) => x[0])}] email=[${emails.map((x) => x[0])}]`);
    }
  } finally {
    await purge();
    await unassign(vUid);
  }
  return summary('D16 · authorized metric surfaces');
}

// THE RUNNER CONTRACT, which the first draft of this file got wrong: every suite
// here runs AT IMPORT and its default export is the FAILURE COUNT, not a function
// and not a boolean. Exporting the function meant run.mjs imported D16 without ever
// executing it and scored the result NaN/0 — a suite that silently did not run,
// which is the most dangerous way for a security test to "pass".
export default await run();
