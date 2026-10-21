#!/usr/bin/env node
// Reads schema facts out of the migration set, and FAILS LOUDLY when it finds
// nothing rather than reporting a clean result.
//
// WHY THIS EXISTS. V5 §129.3 and §139.3: three ad-hoc checkers in this programme
// found nothing and announced success.
//   · a BSD-sed extractor printed "user_integrations  clean" for a table holding
//     access_token and refresh_token — `sed` does not support \? or \b, so the
//     table body never matched and the empty result was printed as a verdict;
//   · an RLS scan reported three tables as having no ENABLE ROW LEVEL SECURITY
//     because its regex assumed single spaces; all sixteen had it;
//   · a python extractor silently skipped workout_logs, because the baseline
//     migration QUOTES its identifiers ("workout_logs") and the pattern did not.
//
// All three were the same bug: a zero result treated as an answer. So every
// lookup here THROWS when the object is not found, quoted identifiers are handled,
// and `--self-test` proves the scanner can still see things it must see.
//
//   node supabase/scripts/schema-facts.mjs --self-test
//   node supabase/scripts/schema-facts.mjs columns user_integrations
import { readdirSync, readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

// RUN THE CLI ONLY WHEN THIS FILE IS THE ENTRY POINT. Without this, importing the
// module from another script that happens to carry --self-test in argv ran THIS
// self-test and then process.exit(0) — so the importing script's own self-test
// never executed and reported success. Found while building
// check-function-posture.mjs, whose negative controls were silently skipped
// (V5 §144.3). A guard that cannot run its own failure cases is decorative.
const IS_MAIN = import.meta.url === pathToFileURL(process.argv[1] ?? '').href;

const DIR = 'supabase/migrations';

export function migrations() {
  const files = readdirSync(DIR).filter((f) => f.endsWith('.sql')).sort();
  if (files.length < 100) {
    throw new Error(`schema-facts: found only ${files.length} migration(s) in ${DIR} — ` +
      'refusing to answer from a set this small, because "not found" would then be meaningless');
  }
  return files.map((name) => ({ name, sql: readFileSync(`${DIR}/${name}`, 'utf8') }));
}

// `"name"` and `name` are the same object. The baseline migration quotes every
// identifier, which is exactly how workout_logs went missing from an audit.
const ident = (t) => `"?${t.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}"?`;

/** Every column of `table`, from CREATE TABLE plus any later ADD COLUMN. Throws if the table is never declared. */
export function columnsOf(table, mig = migrations()) {
  const out = [];
  let declared = false;
  const create = new RegExp(
    `CREATE\\s+TABLE\\s+(?:IF\\s+NOT\\s+EXISTS\\s+)?(?:"?public"?\\.)?${ident(table)}\\s*\\(([\\s\\S]*?)\\n\\s*\\)\\s*;`, 'i');
  const add = new RegExp(
    `ALTER\\s+TABLE\\s+(?:IF\\s+EXISTS\\s+)?(?:"?public"?\\.)?${ident(table)}\\s+ADD\\s+COLUMN\\s+(?:IF\\s+NOT\\s+EXISTS\\s+)?"?([a-zA-Z_][a-zA-Z0-9_]*)"?\\s+([^;]+);`, 'gi');

  for (const m of mig) {
    const c = m.sql.match(create);
    if (c) {
      declared = true;
      for (let line of c[1].split('\n')) {
        line = line.trim().replace(/,$/, '');
        if (!line || line.startsWith('--')) continue;
        if (/^(PRIMARY|UNIQUE|FOREIGN|CONSTRAINT|CHECK|EXCLUDE)\b/i.test(line)) continue;
        const col = line.match(/^"?([a-zA-Z_][a-zA-Z0-9_]*)"?\s+(.+)/);
        if (col) out.push({ name: col[1], type: col[2], source: m.name });
      }
    }
    for (const a of m.sql.matchAll(add)) {
      declared = true;
      out.push({ name: a[1], type: a[2].trim(), source: `${m.name} (ALTER)` });
    }
  }
  if (!declared) {
    throw new Error(`schema-facts: table "${table}" is declared in NO migration. ` +
      'This is an error, not an empty answer — check the name before concluding anything about it.');
  }
  return out;
}

const SECRETISH = /token|secret|password|passwd|credential|cvv|iban|ssn|api_key|private_key/i;
/** Columns of `table` whose names suggest a credential. Throws if the table is unknown. */
export function secretColumnsOf(table, mig = migrations()) {
  return columnsOf(table, mig).filter((c) => SECRETISH.test(c.name)).map((c) => c.name);
}

/**
 * True if any migration enables RLS on `table`, by either mechanism. Throws if the
 * table is unknown.
 *
 * DYNAMIC ENABLEMENT IS THE SECOND MECHANISM AND IT IS EASY TO MISS. Migration 074
 * secures five ai_* tables with
 *
 *     foreach t in array array['ai_profiles','ai_memories', ...] loop
 *       execute format('alter table %I enable row level security', t);
 *
 * so no literal `ALTER TABLE ai_memories ENABLE ROW LEVEL SECURITY` exists anywhere.
 * An earlier version of this function matched only the literal form and reported all
 * five as UNPROTECTED (V5 §144). They are fully protected — the live probe proved a
 * member reads only their own rows — and acting on that false positive would have
 * meant "fixing" working RLS. A checker that invents a defect is as dangerous as one
 * that misses it.
 *
 * The result says WHICH mechanism, so a dynamic grant stays visible rather than
 * blending into the literal ones.
 */
export function rlsEnabled(table, mig = migrations()) {
  columnsOf(table, mig);                       // asserts the table exists first
  const literal = new RegExp(
    `ALTER\\s+TABLE\\s+(?:"?public"?\\.)?${ident(table)}\\s+ENABLE\\s+ROW\\s+LEVEL\\s+SECURITY`, 'i');
  if (mig.some((m) => literal.test(m.sql))) return 'literal';
  // Dynamic: a DO block that both enables RLS and names this table in an array.
  const named = new RegExp(`'${table.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}'`, 'i');
  for (const m of mig) {
    for (const blk of m.sql.matchAll(/do\s*\$\$[\s\S]*?end\s*\$\$\s*;/gi)) {
      const b = blk[0];
      if (/enable\s+row\s+level\s+security/i.test(b) && named.test(b)) return 'dynamic';
    }
  }
  return false;
}

// ── self-test ───────────────────────────────────────────────────────────────
if (IS_MAIN && process.argv[2] === '--self-test') {
  const mig = migrations();
  const fails = [];
  const t = (name, pass, detail = '') => {
    console.log(`  ${pass ? 'ok  ' : 'FAIL'}  ${name}${detail ? `  — ${detail}` : ''}`);
    if (!pass) fails.push(name);
  };

  // Each case is one of the three historical misses, turned into a standing test.
  const ui = columnsOf('user_integrations', mig).map((c) => c.name);
  t('user_integrations exposes its token columns (the §129.3 miss)',
    ui.includes('access_token') && ui.includes('refresh_token'), ui.join(','));
  t('secretColumnsOf flags exactly those two',
    JSON.stringify(secretColumnsOf('user_integrations', mig).sort()) ===
    JSON.stringify(['access_token', 'refresh_token']));

  const wl = columnsOf('workout_logs', mig).map((c) => c.name);
  t('workout_logs is found despite QUOTED identifiers (the third miss)',
    wl.includes('user_id') && wl.includes('duration_minutes'), `${wl.length} columns`);

  const ae = columnsOf('audit_events', mig).map((c) => c.name);
  t('audit_events picks up ALTER-added columns (delta, changed_columns)',
    ae.includes('delta') && ae.includes('changed_columns'), `${ae.length} columns`);

  t('RLS is detected despite multi-space formatting (the second miss)',
    ['payments', 'user_integrations', 'admin_role_assignments'].every((x) => rlsEnabled(x, mig) === 'literal'));
  // V5 §144: these five are secured by a FOREACH loop in 074, with no literal
  // ALTER TABLE anywhere. Reporting them unprotected was a false positive that
  // would have led to "fixing" RLS that works.
  t('RLS enabled inside a DO/FOREACH loop is detected (the fourth miss)',
    ['ai_profiles', 'ai_memories', 'ai_insights', 'ai_reviews', 'ai_goal_predictions']
      .every((x) => rlsEnabled(x, mig) === 'dynamic'));

  let threw = false;
  try { columnsOf('a_table_that_does_not_exist', mig); } catch { threw = true; }
  t('an unknown table THROWS rather than returning []', threw);

  console.log(fails.length ? `\n  FAIL — ${fails.length} self-test(s) failed\n` : '\n  OK — schema-facts self-test passed\n');
  process.exit(fails.length ? 1 : 0);
}

if (IS_MAIN && process.argv[2] === 'columns') {
  for (const c of columnsOf(process.argv[3])) console.log(`  ${c.name.padEnd(28)} ${c.type.slice(0, 50).padEnd(52)} ${c.source}`);
}
