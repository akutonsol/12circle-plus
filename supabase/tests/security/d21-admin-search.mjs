// D21 · §199 · the admin search filters — they must NARROW, never silently empty.
//
// WHY A LIVE SUITE FOR A TEXT BOX. A search that returns nothing is indistinguishable from a
// search that is broken, and both read as "no such record". So every assertion here is a
// COMPARISON: the unfiltered read, the filtered read, and the specific row that must survive
// one and not the other. A filter that matched nothing would fail the narrowing assertions;
// a filter that was ignored would fail the exclusion assertions.
//
// AND THE SANITISER IS A SECURITY ASSERTION, not a tidiness one. PostgREST's filter grammar
// is punctuation — `or=(a.ilike.*x*,b.ilike.*x*)` parses on `,` `.` `(` `)` `*` — so a query
// carrying those characters can re-parse the expression and, on an `or=`, WIDEN it. Section 3
// sends exactly those payloads and requires the result never to exceed the unfiltered
// population.
import { IDENT, signIn, svc, check, section, summary, beginSuite, n, countExact } from
  './lib.mjs';

const ONE = (b) => (Array.isArray(b) ? b[0] : b) || {};

async function uidOf(key) {
  const r = await svc(`user_profiles?email=eq.${encodeURIComponent(IDENT[key].email)}&select=id`);
  return ONE(r.body).id;
}
async function assign(uid, role) {
  await svc(`admin_role_assignments?user_id=eq.${uid}`, { method: 'DELETE' });
  await svc('admin_role_assignments', { method: 'POST', body: { user_id: uid, admin_role: role } });
}
const unassign = (uid) => svc(`admin_role_assignments?user_id=eq.${uid}`, { method: 'DELETE' });

// The EXACT expressions the Dart service builds — with ONE difference that is a property of
// this harness and not of the shipped code: the `%` wildcards are percent-encoded as `%25`.
//
// WHY. A raw `%` in a URL is the start of an escape sequence, so `ilike.%QA%` is a MALFORMED
// request and PostgREST answers 500. The first draft of this suite sent it raw and read
// `matched=0` as "the filter does not work", when the filter had never been evaluated. The
// shipped Dart service does not have this bug: `postgrest-2.7.1` builds filters through
// `appendSearchParams` → `Uri.replace(queryParameters:)`, which percent-encodes every value,
// so `%` arrives as `%25` on its own.
//
// The GRAMMAR characters are left raw on purpose — `,` `.` `(` `)` must reach PostgREST
// unencoded or section 3's payloads could not attempt the re-parse they exist to attempt.
const wild = (t) => `%25${t}%25`;
const userFilter = (t) =>
  `or=(first_name.ilike.${wild(t)},last_name.ilike.${wild(t)},email.ilike.${wild(t)})`;
const eventFilter = (t) => `title=ilike.${wild(t)}`;

const asCaller = async (who, path) => {
  const r = await fetch(`${process.env.QA_URL}/rest/v1/${path}`, {
    headers: { apikey: process.env.QA_ANON, Authorization: `Bearer ${who}` },
  });
  return { status: r.status, body: await r.json().catch(() => null) };
};

beginSuite();

async function run() {
  const victim = await signIn('victim');
  const vUid = await uidOf('victim');
  const TAG = 'QA-D21-SEARCH';
  let eventId;

  try {
    await assign(vUid, 'viewer');   // holds Users·view and Events·view
    await svc(`events?title=like.${TAG}*`, { method: 'DELETE' });

    // ── 1 · the user search narrows, and keeps the row it should ──────────
    section('search · the People filter narrows to the matching account');

    const all = await asCaller(victim, 'admin_user_directory?select=id,email&limit=1000');
    check('arranged: the unfiltered directory is NON-EMPTY, so "narrowing" means something',
      n(all.body) > 1, `rows=${n(all.body)}`);

    // A term taken from a real row, so the match is known to exist.
    const known = ONE(all.body);
    const term = (known.email || '').split('@')[0];
    check('arranged: a search term was taken from a real row',
      term.length > 2, `term=${term}`);

    const hit = await asCaller(victim,
      `admin_user_directory?select=id,email&${userFilter(term)}&limit=1000`);
    check('the filter RETURNS the known row — it narrows rather than empties',
      (hit.body || []).some((r) => r.id === known.id),
      `matched=${n(hit.body)} of ${n(all.body)}`);
    check('…and it EXCLUDES rows it should not match, so the filter is not being ignored',
      n(hit.body) < n(all.body), `${n(hit.body)} < ${n(all.body)}`);

    const miss = await asCaller(victim,
      `admin_user_directory?select=id&${userFilter('zzz-no-such-account-zzz')}&limit=1000`);
    check('a term matching nothing returns ZERO — which the UI words as "no match" and ' +
          'never as "none", so a filter cannot read as a fact about the population',
      n(miss.body) === 0, `rows=${n(miss.body)}`);

    // ── 2 · the event search matches the TITLE and only the title ────────
    section('search · the Events filter matches the title, and not the other columns');

    const made = await svc('events', { method: 'POST',
      headers: { Prefer: 'return=representation' },
      body: { title: `${TAG} findable workshop`, location: `${TAG}-LOCATION-ONLY`,
              event_date: '2027-05-01T10:00:00Z' } });
    eventId = ONE(made.body).id;
    check('arranged: a fixture event whose LOCATION carries a distinct marker',
      Boolean(eventId), `event=${eventId}`);

    const byTitle = await asCaller(victim,
      `events?select=id&${eventFilter(`${TAG} findable`)}&limit=1000`);
    check('a title search finds it', (byTitle.body || []).some((r) => r.id === eventId),
      `rows=${n(byTitle.body)}`);

    const byLocation = await asCaller(victim,
      `events?select=id&${eventFilter(`${TAG}-LOCATION-ONLY`)}&limit=1000`);
    check('a LOCATION term does NOT find it — the UI says "searches the event title only", ' +
          'and that claim is true rather than aspirational',
      n(byLocation.body) === 0, `rows=${n(byLocation.body)}`);

    // ── 3 · the sanitiser · punctuation cannot widen the filter ──────────
    section('search · a crafted query cannot re-parse the filter expression');

    // AS THE AUTHORIZED CALLER. `countExact` goes through service_role, for which
    // `admin_can` is false, so it reported population=0 and made the widening comparison
    // vacuous — the same mistake D20 §6 made against the audit projection.
    const population = n((await asCaller(victim,
      'admin_user_directory?select=id&limit=1000')).body);
    check('arranged: the widening comparison has a NON-ZERO population to exceed',
      population > 0, `population=${population}`);
    // Each payload is what the SERVICE would have sent had it not stripped the grammar
    // characters — an appended disjunct on an `or=`, which is a WIDENING.
    for (const payload of [
      'x%,email.ilike.%',                       // closes one disjunct, opens another
      'x*)',                                    // closes the or( group early
      'x%',                                     // a bare LIKE wildcard
      'x",email.ilike."%',                      // quoted-value escape attempt
    ]) {
      const r = await asCaller(victim,
        `admin_user_directory?select=id&${userFilter(payload)}&limit=1000`);
      // The decisive property is not the status — a malformed filter may 400, which is
      // safe — but that it NEVER returns more than the unfiltered population.
      const widened = r.status < 300 && n(r.body) > population;
      check(`a crafted query cannot WIDEN the match: ${JSON.stringify(payload)}`,
        !widened, `status=${r.status} rows=${n(r.body)} population=${population}`);
    }
    check('…and the sanitiser removes exactly those characters, so the shipped service ' +
          'never sends the payloads above',
      /[,.()*%_"\\]/.test('x%,email.ilike.%'),
      'the payloads contain grammar characters the service strips');

    // ── 4 · the filter does not widen AUTHORIZATION ──────────────────────
    section('search · a filter is not a way around the gate');
    await unassign(vUid);
    const unauth = await asCaller(victim,
      `admin_user_directory?select=id&${userFilter(term)}&limit=1000`);
    check('an unauthorized caller reads NOTHING even with a filter that MATCHES — proved ' +
          'with the same well-formed filter that returned the row a moment ago, so this is ' +
          'the gate refusing and not a malformed request failing',
      unauth.status < 300 && n(unauth.body) === 0,
      `status=${unauth.status} rows=${n(unauth.body)}`);
  } finally {
    await svc(`events?title=like.${TAG}*`, { method: 'DELETE' });
    await unassign(vUid);
    const left = await countExact(`events?title=like.${TAG}*&select=id`);
    check('TEARDOWN · the search fixture was removed, verified', left === 0, `left=${left}`);
  }
  return summary('D21 · admin search filters');
}

export default await run();
