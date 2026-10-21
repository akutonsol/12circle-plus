// Creates (or repairs) the four fixture identities the security suites use and
// seeds the victim with a little private health data, so an exploit has
// something real to steal. Idempotent — safe to re-run.
import { writeFileSync } from 'node:fs';
import { IDENT, ensureUser, svc } from './lib.mjs';

const ids = {};
for (const key of Object.keys(IDENT)) {
  ids[key] = await ensureUser(key);
  // The profile row itself is created by the auth trigger (migration 109);
  // role is forced here through service_role, which is the only path allowed
  // to set it once migration 115 lands.
  const r = await svc(`user_profiles?id=eq.${ids[key]}`, {
    method: 'PATCH',
    body: { role: IDENT[key].role, first_name: 'P1', last_name: key,
            email: IDENT[key].email, is_demo: true },
  });
  if (r.status >= 300) throw new Error(`profile ${key}: ${r.status} ${JSON.stringify(r.body)}`);
  console.log(`${key.padEnd(9)} ${ids[key]}  role=${IDENT[key].role}`);
}

const seed = [
  ['weight_logs',       { user_id: ids.victim, weight_kg: 82.7, logged_at: '2026-08-01T08:00:00Z' }],
  ['body_measurements', { user_id: ids.victim, waist_cm: 91.4, logged_at: '2026-08-01T08:00:00Z',
                          note: 'P1-FIXTURE' }],
  ['weekly_checkins',   { user_id: ids.victim, week_number: 901, week_start_date: '2026-08-03',
                          status: 'submitted', weight_kg: 82.7, stress_level: 4,
                          notes: 'P1-FIXTURE private health note' }],
];
for (const [table, row] of seed) {
  const existing = await svc(`${table}?user_id=eq.${ids.victim}&select=id&limit=1`);
  if (Array.isArray(existing.body) && existing.body.length) { console.log(`${table}: already seeded`); continue; }
  const w = await svc(table, { method: 'POST', body: row });
  console.log(`${table}: ${w.status < 300 ? 'seeded' : `FAILED ${w.status} ${JSON.stringify(w.body)}`}`);
}

writeFileSync(new URL('./ids.json', import.meta.url), JSON.stringify(ids, null, 1) + '\n');
console.log('\nids.json written');
