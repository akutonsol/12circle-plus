#!/usr/bin/env node
// Standing guard over two function-posture classes this programme has already been
// bitten by, and which NOTHING in CI was checking.
//
//   1. A SECURITY DEFINER function without a pinned search_path resolves unqualified
//      names through the CALLER's search_path. Migration 122 states the hazard and
//      the reason it recurs: "ACLs and ownership survive CREATE OR REPLACE;
//      proconfig does NOT." 118 and 122 each had to bulk re-pin EVERY function in
//      public after 116/119/120/121 silently dropped the pin. Nothing prevents the
//      next one — until this guard.
//
//   2. GRANT EXECUTE to anon or PUBLIC on a function. 122's own exit criteria name
//      "no EXECUTE for PUBLIC or anon".
//
// SCOPE IS DELIBERATELY POST-122, and that is not a loophole. Functions declared
// before the last bulk re-pin are pinned IN THE DATABASE by 118:284 / 122:71, which
// run `ALTER FUNCTION ... SET search_path` over everything that lacked it. Scanning
// their CREATE text would report 56 false positives (V5 §144.2) — the same mistake
// as reading RLS from literal ALTER statements when a FOREACH loop enabled it. A
// guard that cries wolf 56 times is a guard people switch off.
//
//   node supabase/scripts/check-function-posture.mjs
//   node supabase/scripts/check-function-posture.mjs --self-test
import { migrations } from './schema-facts.mjs';

const LAST_BULK_REPIN = 122;

const stripComments = (sql) =>
  sql.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/^\s*--.*$/gm, ' ');

export function scan(mig = migrations()) {
  const problems = [];

  // ── 1 · definer functions declared after the last bulk re-pin ─────────────
  const after = mig.filter((m) => parseInt(m.name, 10) > LAST_BULK_REPIN);
  if (after.length === 0) {
    throw new Error(`check-function-posture: found NO migrations after ${LAST_BULK_REPIN} — ` +
      'the scan window is empty, so a clean result would be meaningless');
  }
  const declared = new Map();
  for (const m of after) {
    for (const f of m.sql.matchAll(/CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(?:public\.)?([a-z0-9_]+)\s*\(/gi)) {
      declared.set(f[1].toLowerCase(), { mig: m.name, seg: m.sql.slice(f.index, f.index + 1600) });
    }
  }
  const definers = [...declared.entries()].filter(([, i]) => /SECURITY\s+DEFINER/i.test(i.seg));
  if (definers.length === 0) {
    throw new Error('check-function-posture: found NO SECURITY DEFINER functions after ' +
      `${LAST_BULK_REPIN} — the repository definitely has them, so the scan is broken`);
  }
  for (const [name, info] of definers) {
    if (!/SET\s+search_path/i.test(info.seg)) {
      problems.push(`${info.mig}: ${name}() is SECURITY DEFINER with NO pinned search_path — ` +
        'CREATE OR REPLACE drops proconfig, and no bulk re-pin runs after it');
    }
  }

  // ── 2 · EXECUTE granted to anon or PUBLIC, anywhere ──────────────────────
  for (const m of mig) {
    for (const g of stripComments(m.sql).matchAll(/GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+([^;]*?)\s+TO\s+([^;]+);/gi)) {
      if (/\b(anon|public)\b/i.test(g[2])) {
        problems.push(`${m.name}: GRANT EXECUTE ... TO ${g[2].trim()} on ${g[1].trim().slice(0, 70)}`);
      }
    }
  }

  return { definers: definers.length, scanned: after.length, problems };
}

if (process.argv[2] === '--self-test') {
  // Negative controls: the guard must FAIL on each of these, or it is decorative.
  const base = migrations();
  const cases = [
    ['a definer function with no search_path',
     "CREATE OR REPLACE FUNCTION public.d15_probe() RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$ BEGIN END; $$;"],
    ['EXECUTE granted to anon',
     'GRANT EXECUTE ON FUNCTION public.anything() TO anon;'],
    ['EXECUTE granted to PUBLIC',
     'GRANT EXECUTE ON FUNCTION public.anything() TO PUBLIC;'],
  ];
  let fails = 0;
  for (const [label, sql] of cases) {
    const { problems } = scan([...base, { name: '999_synthetic.sql', sql }]);
    const caught = problems.length > 0;
    console.log(`  ${caught ? 'ok  ' : 'FAIL'}  catches: ${label}`);
    if (!caught) fails++;
  }
  // And it must NOT fire on a comment mentioning anon.
  const { problems: p2 } = scan([...base,
    { name: '999_comment.sql', sql: '-- GRANT EXECUTE ON FUNCTION public.x() TO anon;\n' }]);
  const clean = p2.length === 0;
  console.log(`  ${clean ? 'ok  ' : 'FAIL'}  ignores the same text inside a comment`);
  if (!clean) fails++;
  console.log(fails ? `\n  FAIL — ${fails} self-test(s) failed\n` : '\n  OK — function-posture self-test passed\n');
  process.exit(fails ? 1 : 0);
}

const { definers, scanned, problems } = scan();
if (problems.length) {
  console.error('\n  FAIL — function posture:');
  for (const p of problems) console.error(`    · ${p}`);
  console.error('');
  process.exit(1);
}
console.log(`  OK — function posture: ${definers} SECURITY DEFINER function(s) declared across ` +
            `${scanned} migration(s) after ${LAST_BULK_REPIN}, every one pinning search_path; ` +
            'no EXECUTE granted to anon or PUBLIC.');
