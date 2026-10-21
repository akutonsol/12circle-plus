#!/usr/bin/env node
// Validates a supplied Admin capability matrix against the V5 §115 vocabulary.
//
// Step 1 of the mechanical sequence that closes CONF-D8. It exists so that a
// supplied matrix is accepted or rejected DETERMINISTICALLY, with every defect
// named, rather than discovered during seeding.
//
//   node supabase/scripts/validate-admin-capability-matrix.mjs [path]
//
// Accepts the schema the owner specified: areas[] -> verbs[] -> grants{role}.
// A grant is `true`, `false`, or an explicit unresolved marker
// { "unresolved": true, "reason": "..." } — because the request permits a cell to
// be intentionally undecided, and a guess is worse than a gap. UNRESOLVED cells
// are reported and are NOT seedable: absent a row, admin_can() denies, which is
// the safe reading of "undecided".
import { readFileSync } from 'node:fs';

export const GROUPS = {
  Ecosystem:  ['Community', 'Events', 'Training', 'Monetization', 'Wearable intelligence'],
  Trust:      ['AI Guardian', 'Security', 'Incidents', 'Audit logs'],
  Operations: ['QA', 'Releases', 'Integrations', 'System'],
  Settings:   ['Organization', 'Users', 'Roles', 'Configuration'],
};
export const VERBS = ['View', 'Create', 'Update', 'Manage', 'Approve'];
export const ROLES = ['trust_lead', 'operations_lead', 'support', 'content_editor', 'viewer'];
const ALL_AREAS = Object.values(GROUPS).flat();

export function validate(doc) {
  const errors = [], warnings = [];
  const seen = new Map();          // "Area|Verb" -> grants
  let granted = 0, denied = 0, unresolved = 0;

  if (!doc || typeof doc !== 'object') return { ok: false, errors: ['document is not an object'] };
  if (!Array.isArray(doc.areas)) return { ok: false, errors: ['missing top-level "areas" array'] };
  if (!doc.authority || !String(doc.authority).trim())
    errors.push('missing "authority" — the matrix must name who designated it');

  for (const a of doc.areas) {
    const area = a?.area, group = a?.group;
    if (!ALL_AREAS.includes(area)) { errors.push(`unknown area ${JSON.stringify(area)}`); continue; }
    if (group && !GROUPS[group]?.includes(area))
      errors.push(`area "${area}" is declared in group "${group}" but belongs to "${Object.keys(GROUPS).find(g => GROUPS[g].includes(area))}"`);
    if (!Array.isArray(a.verbs)) { errors.push(`area "${area}" has no verbs array`); continue; }

    for (const v of a.verbs) {
      const verb = v?.verb;
      if (!VERBS.includes(verb)) { errors.push(`area "${area}": unknown verb ${JSON.stringify(verb)}`); continue; }
      const key = `${area}|${verb}`;
      if (seen.has(key)) { errors.push(`duplicate cell ${area} × ${verb}`); continue; }
      seen.set(key, v.grants);

      const g = v.grants;
      if (!g || typeof g !== 'object') { errors.push(`${area} × ${verb}: missing "grants"`); continue; }
      for (const r of ROLES) {
        if (!(r in g)) { errors.push(`${area} × ${verb}: no grant for role "${r}"`); continue; }
        const val = g[r];
        if (val === true) granted++;
        else if (val === false) denied++;
        else if (val && typeof val === 'object' && val.unresolved === true) {
          unresolved++;
          if (!val.reason || !String(val.reason).trim())
            errors.push(`${area} × ${verb} / ${r}: marked unresolved without a reason`);
        } else {
          errors.push(`${area} × ${verb} / ${r}: grant must be true, false, or {unresolved:true,reason}; got ${JSON.stringify(val)}`);
        }
      }
      for (const k of Object.keys(g)) if (!ROLES.includes(k)) errors.push(`${area} × ${verb}: unknown role "${k}"`);
    }
  }

  for (const area of ALL_AREAS)
    for (const verb of VERBS)
      if (!seen.has(`${area}|${verb}`)) errors.push(`MISSING cell ${area} × ${verb}`);

  const cells = seen.size, values = granted + denied + unresolved;
  if (cells !== 85) errors.push(`expected 85 cells, found ${cells}`);
  if (values !== 425 && errors.length === 0) errors.push(`expected 425 grant values, found ${values}`);
  if (unresolved) warnings.push(`${unresolved} grant(s) marked UNRESOLVED — these are NOT seeded; admin_can() denies them`);

  return { ok: errors.length === 0, errors, warnings,
           stats: { cells, values, granted, denied, unresolved, seedable: granted } };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const path = process.argv[2] || 'docs/design/admin-dashboard/ADMIN-CAPABILITY-MATRIX.json';
  let doc; try { doc = JSON.parse(readFileSync(path, 'utf8')); }
  catch (e) { console.error(`  cannot read ${path}: ${e.message}`); process.exit(2); }
  const r = validate(doc);
  console.log(`\n  ADMIN CAPABILITY MATRIX — validation of ${path}\n`);
  if (r.stats) console.log(`  cells ${r.stats.cells}/85 · values ${r.stats.values}/425 · granted ${r.stats.granted} · denied ${r.stats.denied} · unresolved ${r.stats.unresolved}`);
  for (const w of r.warnings ?? []) console.log(`  ⚠ ${w}`);
  if (r.ok) { console.log(`\n  VALID — ${r.stats.seedable} capability row(s) are seedable.\n`); process.exit(0); }
  console.log(`\n  INVALID — ${r.errors.length} problem(s):`);
  for (const e of r.errors.slice(0, 25)) console.log(`    · ${e}`);
  if (r.errors.length > 25) console.log(`    … and ${r.errors.length - 25} more`);
  console.log('\n  Nothing is seeded. Fix the matrix; do not relax the validator.\n');
  process.exit(1);
}
