// D14 · THE APPROVED ADMIN CAPABILITY MATRIX — all 425 grants, live against QA.
//
// Owner-approved policy: docs/design/admin-dashboard/ADMIN-CAPABILITY-MATRIX.json
// (Julia, 2026-10-05). Seeded by migration 155. V5 §125.
//
// EVERY EXPECTATION IS READ FROM THE MATRIX FILE, never written here. The suite
// cannot drift from the approved policy, because it has no opinion of its own: if
// the matrix changes, the expectations change with it.
//
// It asserts the CLASS, not a sample — QA_CLOSURE_STANDARD §5.2, whose cited
// failure (F-J-01) was a suite that checked four of five wrappers individually.
// All 17 areas x 5 verbs x 5 roles are exercised: 116 expected-TRUE and 309
// expected-FALSE, each a real admin_can() call as that role.
//
// CASING: areas keep display spelling, verbs are lowercase — migration 155's
// contract. Passing 'View' would match no row and every assertion would pass
// vacuously, which is precisely the failure this suite exists to prevent.
import { readFileSync } from 'node:fs';
import { IDENT, signIn, rpc, svc, check, section, summary, beginSuite } from './lib.mjs';

const MATRIX = JSON.parse(readFileSync(
  new URL('../../../docs/design/admin-dashboard/ADMIN-CAPABILITY-MATRIX.json', import.meta.url), 'utf8'));
const ROLES = ['trust_lead', 'operations_lead', 'support', 'content_editor', 'viewer'];

async function run() {
  beginSuite();

  const seeded = await svc('admin_role_capabilities?select=admin_role');
  if (!Array.isArray(seeded.body)) {
    check('capability matrix is seeded', false, 'admin_role_capabilities unreachable — 155 not applied');
    return summary('D14 admin capability matrix');
  }
  const expectedTrue = MATRIX.areas.flatMap(a => a.verbs.flatMap(v =>
    ROLES.filter(r => v.grants[r] === true))).length;
  check(`capability rows match the approved matrix (${expectedTrue})`,
    seeded.body.length === expectedTrue, `on QA: ${seeded.body.length}`);
  check('matrix authority is named', !!MATRIX.authority, `authority=${MATRIX.authority}`);

  const uid = (await svc(`user_profiles?select=id&email=eq.${encodeURIComponent(IDENT.victim.email)}`)).body?.[0]?.id;
  const token = await signIn('victim');
  if (!uid) { check('fixture identity resolved', false); return summary('D14 admin capability matrix'); }

  let tested = 0, wrong = [];
  try {
    for (const role of ROLES) {
      await svc(`admin_role_assignments?user_id=eq.${uid}`, { method: 'DELETE' });
      const ins = await svc('admin_role_assignments', { method: 'POST', body: { user_id: uid, admin_role: role } });
      if (ins.status >= 300) { check(`arranged role ${role}`, false, `status=${ins.status}`); continue; }

      let roleWrong = 0, roleTrue = 0;
      for (const a of MATRIX.areas) {
        for (const v of a.verbs) {
          const expected = v.grants[role] === true;
          const got = (await rpc(token, 'admin_can', { p_area: a.area, p_verb: v.verb.toLowerCase() })).body;
          tested++;
          if (expected) roleTrue++;
          if (got !== expected) { roleWrong++; wrong.push(`${role} · ${a.area} · ${v.verb}: expected ${expected}, got ${got}`); }
        }
      }
      check(`${role} — all 85 cells match the approved matrix (${roleTrue} granted)`,
        roleWrong === 0, roleWrong ? `${roleWrong} mismatched` : '85/85');
    }

    section('coverage');
    check('all 425 role × area × verb combinations exercised', tested === 425, `tested=${tested}`);
    if (wrong.length) for (const w of wrong.slice(0, 10)) check(`MISMATCH ${w}`, false);
  } finally {
    await svc(`admin_role_assignments?user_id=eq.${uid}`, { method: 'DELETE' });
  }

  return summary('D14 admin capability matrix');
}

export default await run();
