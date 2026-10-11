// D22 · OWNER DECISION Q2 / METRIC-02 sub-answer — the active-user ROLE SPLIT (migration 181).
//
// THE RULING: *"the active-user population is ALL users, with the role split PUBLISHED beside
// the total. Not clients-only and not an unexplained aggregate: the split is to be shown, so a
// reader can apply either definition."*
//
// WHAT MAKES THIS MORE THAN A SHAPE TEST. A split that merely sits next to a total is exactly
// the "unexplained aggregate" the ruling forbids — two numbers that look related and are not.
// The decisive assertion here is the EQUALITY: for every window, on both bases,
//     sum(the map's values) === the total column
// If that holds, the reader really can apply either definition, because the parts account for
// the whole. If it does not, the split is decoration.
//
// AND THE EQUALITY IS NOT VACUOUS. §1 asserts it on the live population; §4 then MOVES the
// population with a real session and asserts the total and the matching role bucket move
// TOGETHER, by one, from a measured baseline. An equality between two numbers that are both
// zero would pass §1 while proving nothing, which is the §203 lesson about a page-capped
// `1000 === 1000`.
//
// THREE-STATE, NOT TWO. `{}` and NULL are different findings and the suite insists on it:
// authorized-with-nobody-active is an empty MAP, unauthorized is NULL. A card that rendered
// NULL as "{}" would report "no coaches were active" to a reader who is simply not allowed to
// know. `support` holds Users·view and NOT Security·view in the approved matrix, so it is the
// role that separates them.
//
// EVERY FIXTURE IS REMOVED, AND THE REMOVAL IS ASSERTED — D19's lesson, where an unchecked
// teardown left QA's Guardian disabled.
import { IDENT, signIn, rest, svc, check, section, summary, beginSuite, n } from './lib.mjs';

const ONE = (b) => (Array.isArray(b) ? b[0] : b) || {};
const num = (v) => (v === null || v === undefined ? null : Number(v));
const TAG = 'QA-D22-SESSION';

// 142's role vocabulary, plus the two non-roles 181 keeps distinct. Any other key means the
// view invented a bucket.
const VOCAB = new Set([
  'client', 'coach', 'vendor', 'admin', 'content_manager', 'trust_operator',
  'erasure_executor',
  'no_profile',   // no user_profiles row at all — legitimate per 142:113
  'unrecorded',   // row exists, role column NULL — reachable, 115 added no NOT NULL
]);

const WINDOWS = ['today', 'week', 'month'];
const sumOf = (m) => Object.values(m || {}).reduce((a, b) => a + Number(b), 0);

async function uidOf(key) {
  const r = await svc(`user_profiles?email=eq.${encodeURIComponent(IDENT[key].email)}&select=id,role`);
  return ONE(r.body);
}
async function assign(uid, role) {
  await svc(`admin_role_assignments?user_id=eq.${uid}`, { method: 'DELETE' });
  const r = await svc('admin_role_assignments', { method: 'POST', body: { user_id: uid, admin_role: role } });
  return r.status < 300;
}
const unassign = async (uid) => { if (uid) await svc(`admin_role_assignments?user_id=eq.${uid}`, { method: 'DELETE' }); };

// Read AS the caller. service_role bypasses RLS but admin_can() is false for it, so a service
// read of this view returns nothing and would prove nothing about either gate.
async function view(who) {
  const r = await rest(who, 'admin_activity_overview?select=*');
  return { status: r.status, rows: n(r.body), row: ONE(r.body) };
}

async function run() {
  beginSuite();
  const victim = await signIn('victim');
  const v = await uidOf('victim');

  const purge = async () => { await svc(`workout_sessions?workout_title=eq.${TAG}`, { method: 'DELETE' }); };

  try {
    await purge();
    await assign(v.id, 'viewer'); // viewer holds BOTH Users·view and Security·view

    // ── §1 · the equality that makes it a split and not two unrelated counts ──────────
    section('§1 · every map accounts for exactly its total');
    const base = (await view(victim)).row;
    for (const w of WINDOWS) {
      const total = num(base[`session_users_${w}`]);
      const map = base[`session_users_${w}_by_role`];
      check(`Q2 · session_users_${w}: the role split sums EXACTLY to the total`,
        map !== null && sumOf(map) === total,
        `total=${total} sum=${sumOf(map)} map=${JSON.stringify(map)}`);
    }
    for (const w of WINDOWS) {
      const total = num(base[`signin_users_${w}`]);
      const map = base[`signin_users_${w}_by_role`];
      check(`Q2 · signin_users_${w}: the role split sums EXACTLY to the total`,
        map !== null && sumOf(map) === total,
        `total=${total} sum=${sumOf(map)} map=${JSON.stringify(map)}`);
    }

    // ── §2 · no invented buckets ──────────────────────────────────────────────────────
    section('§2 · the keys are roles the schema actually defines');
    for (const b of ['session', 'signin']) {
      for (const w of WINDOWS) {
        const map = base[`${b}_users_${w}_by_role`] || {};
        const bad = Object.keys(map).filter((k) => !VOCAB.has(k));
        check(`Q2 · ${b}_users_${w}_by_role uses only 142's roles plus no_profile/unrecorded`,
          bad.length === 0, `unexpected keys: ${bad.join(', ') || 'none'}`);
      }
    }

    // ── §3 · three-state · {} is a measured emptiness, NULL is an absent authorization ─
    section('§3 · the split inherits its total\'s gate, and NULL is never rendered as {}');
    check('Q2 · a both-areas role receives MAPS for both bases, not NULL',
      base.session_users_today_by_role !== null && base.signin_users_today_by_role !== null,
      `session=${JSON.stringify(base.session_users_today_by_role)} signin=${JSON.stringify(base.signin_users_today_by_role)}`);

    await assign(v.id, 'support'); // Users·view YES, Security·view NO
    const sup = (await view(victim)).row;
    check('Q2 · support (Users, no Security) SEES the Session split',
      sup.session_users_today_by_role !== null,
      `${JSON.stringify(sup.session_users_today_by_role)}`);
    check('Q2 · support is given NULL — NOT {} — for all three sign-in splits, so the card ' +
          'cannot be read as "nobody signed in"',
      WINDOWS.every((w) => sup[`signin_users_${w}_by_role`] === null),
      WINDOWS.map((w) => `${w}=${JSON.stringify(sup[`signin_users_${w}_by_role`])}`).join(' '));
    check('Q2 · and the split is gated with the SAME verb as the total it splits — support ' +
          'sees neither the sign-in total nor its split',
      sup.signin_users_today === null && sup.signin_users_today_by_role === null,
      `total=${JSON.stringify(sup.signin_users_today)} split=${JSON.stringify(sup.signin_users_today_by_role)}`);

    // An unassigned caller reaches the view's own WHERE clause and receives no row at all.
    await unassign(v.id);
    const none = await view(victim);
    check('Q2 · an unassigned caller receives NO ROW — the split is not reachable without a ' +
          'capability at all',
      none.rows === 0, `rows=${none.rows}`);

    // ── §4 · the equality is non-vacuous: move the population and watch both move ──────
    section('§4 · a real session moves the total and its role bucket together');
    await assign(v.id, 'viewer');
    const before = (await view(victim)).row;
    const beforeTotal = num(before.session_users_today);
    const beforeBucket = Number((before.session_users_today_by_role || {})[v.role] || 0);

    const ins = await svc('workout_sessions', {
      method: 'POST',
      body: { user_id: v.id, workout_title: TAG, started_at: new Date().toISOString(), status: 'completed' },
    });
    check('Q2 · fixture session was actually written (an HTTP status alone would not prove it)',
      ins.status < 300, `status=${ins.status}`);

    const after = (await view(victim)).row;
    const afterTotal = num(after.session_users_today);
    const afterMap = after.session_users_today_by_role || {};
    const afterBucket = Number(afterMap[v.role] || 0);

    check(`Q2 · session_users_today rose by exactly 1 (${beforeTotal} -> ${afterTotal})`,
      afterTotal === beforeTotal + 1, `${beforeTotal} -> ${afterTotal}`);
    check(`Q2 · the '${v.role}' bucket rose by exactly 1 — the split tracks the SAME event ` +
          `as the total (${beforeBucket} -> ${afterBucket})`,
      afterBucket === beforeBucket + 1, `${beforeBucket} -> ${afterBucket}`);
    check('Q2 · and the equality still holds after the population moved — so §1 was not two ' +
          'zeroes agreeing with each other',
      sumOf(afterMap) === afterTotal, `total=${afterTotal} sum=${sumOf(afterMap)} map=${JSON.stringify(afterMap)}`);
    check('Q2 · the active user landed in the bucket for the role they actually hold, not in ' +
          'no_profile or unrecorded',
      afterMap[v.role] !== undefined && afterMap.no_profile === undefined,
      `role=${v.role} map=${JSON.stringify(afterMap)}`);

    // ── §5 · teardown, ASSERTED ───────────────────────────────────────────────────────
    section('§5 · the fixture is gone, and that is checked rather than hoped');
    await purge();
    const restored = (await view(victim)).row;
    check('Q2 · the fixture session was removed and the total returned to its baseline',
      num(restored.session_users_today) === beforeTotal,
      `baseline=${beforeTotal} now=${restored.session_users_today}`);
    check('Q2 · and the role bucket returned to ITS baseline too',
      Number((restored.session_users_today_by_role || {})[v.role] || 0) === beforeBucket,
      `baseline=${beforeBucket} now=${JSON.stringify(restored.session_users_today_by_role)}`);
    const left = await svc(`workout_sessions?workout_title=eq.${TAG}&select=id`);
    check('Q2 · no QA-D22 row survives anywhere in workout_sessions',
      n(left.body) === 0, `rows=${n(left.body)}`);
  } finally {
    await purge();
    await unassign(v.id);
  }

  return summary('D22 · Q2 active-user role split');
}

export default await run();
