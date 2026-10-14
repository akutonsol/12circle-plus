// Schema-contract guard — QA Workstream I.
//
//   node supabase/tests/contract/run.mjs      (or: npm run test:contract)
//
// Offline. Contacts no environment. Derives the `public` schema from
// supabase/migrations (schema.mjs) and asserts that every relation and every
// column the application names actually exists:
//
//   * every  .from('<relation>')                  resolves to a table or view;
//   * every  .select('a, b, c')                   names real columns;
//   * every  .insert/.update/.upsert({...}) key   names a real column.
//
// Why this exists: PostgREST rejects an unknown column with HTTP 400 / 42703
// BEFORE it checks authorization (verified live against QA), and the client
// swallows that 400 in a catch that returns an empty value. A misspelled column
// therefore ships as a silently dead feature, not as a crash. Nine such defects
// were open when this guard was written; see known-violations.json.
//
// It also asserts that every *embedded resource* named through a bare column
// hint — `coach:coach_id(...)` — resolves through a foreign key whose target is
// in the `public` schema. PostgREST cannot traverse a FK into `auth`, so such an
// embed is answered PGRST200 before any row is read. UIX-1 / M-03 was exactly
// that, and the column check below could not see it: bracketed spans are an
// embedded resource's own column list and are dropped whole.
//
// Blind spot, stated so it is not mistaken for coverage: a payload key assigned
// dynamically (`row['metadata'] = value`) rather than written as an object
// literal is invisible to this guard. I-NOT-01 is exactly that shape.
//
// Known-open defects are allowlisted in known-violations.json and checked in
// both directions, so the list can only shrink.
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { deriveSchema, deriveForeignKeys, VIEWS, STORAGE_BUCKETS } from './schema.mjs';

// apps/api/src was a third root until the NestJS retirement (V5 §55).
const ROOTS = ['apps/mobile/lib', 'supabase/functions'];
const known = JSON.parse(readFileSync('supabase/tests/contract/known-violations.json', 'utf8'));

function sources(dir, acc = []) {
  for (const e of readdirSync(dir)) {
    const p = join(dir, e);
    if (statSync(p).isDirectory()) sources(p, acc);
    else if (p.endsWith('.dart') || p.endsWith('.ts')) acc.push(p);
  }
  return acc;
}

function closing(s, open) {
  let d = 0;
  for (let i = open; i < s.length; i++) {
    if ('({['.includes(s[i])) d++;
    else if (')}]'.includes(s[i])) { d--; if (d === 0) return i; }
  }
  return -1;
}

// Top-level names of a PostgREST select list; embedded resources — `other(...)`
// — are relationship names, not columns, and are skipped.
function selectColumns(spec) {
  let top = '', d = 0;
  for (const ch of spec) {
    if (ch === '(') { d++; continue; }
    if (ch === ')') { d--; continue; }
    if (d === 0) top += ch;
  }
  const embedded = new Set([...spec.matchAll(/([a-z0-9_]+)\s*(?:!inner|![a-z0-9_]+)?\s*\(/gi)].map((m) => m[1]));
  return top
    .split(',')
    .map((x) => x.trim().split(':').pop().trim().split('.')[0].replace('!inner', '').trim())
    .filter((x) => /^[a-z0-9_]+$/.test(x))
    .filter((x) => !embedded.has(x));
}

// The column check above reads one string literal. Dart and TypeScript both
// concatenate adjacent literals, and the defect this guard exists to catch was
// written across three of them, so the embed check joins the whole `.select(…)`
// argument instead. Deliberately separate: the column check's behaviour is
// unchanged by this file.
function selectSpecJoined(seg) {
  const head = /^\s*\.?\s*\n?\s*\.select\(/.exec(seg);
  if (!head) return null;
  let depth = 1, quote = null, out = '';
  for (let i = head[0].length; i < seg.length; i++) {
    const ch = seg[i];
    if (quote) {
      if (ch === '\\') { i++; continue; }
      if (ch === quote) quote = null; else out += ch;
      continue;
    }
    if (ch === "'" || ch === '"' || ch === '`') { quote = ch; continue; }
    if (ch === '(') depth++;
    else if (ch === ')') { depth--; if (depth === 0) return out; }
  }
  return null;
}

// The token immediately before each depth-0 `(` is that embed's head.
function embedHeads(spec) {
  const heads = [];
  let depth = 0, buf = '';
  for (const ch of spec) {
    if (ch === '(') {
      if (depth === 0) {
        const h = buf.split(',').pop().trim();
        if (h) heads.push(h);
      }
      depth++; buf = '';
    } else if (ch === ')') { depth--; buf = ''; }
    else if (depth === 0) buf += ch;
  }
  return heads;
}

const schema = deriveSchema();
const foreignKeys = deriveForeignKeys();
const relations = new Set([...schema.keys(), ...VIEWS]);
const found = { missingRelation: new Map(), missingColumn: new Map() };
// Write-site COVERAGE, not a pass/fail signal. The key check below reads keys
// only at brace depth 1 of the payload, so `.insert(payload)` yields NO keys --
// `body` is the identifier, there is no `{`, brace never reaches 1, and the site
// is skipped in silence. A spread (`{...row, 'user_id': uid}`) is worse: the
// literal keys ARE checked, so the site looks covered while the spread's keys are
// not. Verified by paired mutation: an inline bad key FAILS correctly, the same
// bad key added to `toSupabase()` -- spread in at intake_flow_screen.dart:281 as
// `.upsert({'id': uid, ..._data.toSupabase()})` -- PASSES. Those two serializers
// are the subject of CON-03, so this blind spot covers the very functions the
// finding is about. Reported rather than failed: 19 of 145 sites are in this
// shape today, and failing them would break CI on pre-existing code. Resolving a
// payload across functions needs dataflow analysis and is not attempted here.
const writeSites = { total: 0, inlineLiteral: 0, opaquePayload: 0, hasSpread: 0 };
// `--list-unseen` names the sites behind the COVERAGE counts, so the blind spot
// can be audited instead of merely feared. It must come from HERE, inside the
// scanning loop where the table is already resolved: a standalone
// re-implementation of this walk over-counted 31 as 81, because it matched
// Dart's own `Map.update(k, fn, ifAbsent:)` and `List.insert(i, x)` and the
// vendored plugin tree under `linux/flutter/ephemeral/.plugin_symlinks/`. The
// `.from(...)` window above excludes all of that; a reimplementation did not.
// Opt-in, so CI output stays stable.
const LIST_UNSEEN = process.argv.includes('--list-unseen');
const unseenSites = [];
const unresolvableEmbed = new Map();
const detail = [];

for (const path of ROOTS.flatMap((r) => sources(r))) {
  const s = readFileSync(path, 'utf8');
  for (const m of s.matchAll(/\.from\(\s*['"]([a-z0-9_]+)['"]\s*\)/g)) {
    const table = m[1];
    const line = s.slice(0, m.index).split('\n').length;
    if (STORAGE_BUCKETS.has(table)) continue;

    if (!relations.has(table)) {
      if (!found.missingRelation.has(table)) found.missingRelation.set(table, []);
      found.missingRelation.get(table).push(`${path}:${line}`);
      continue;
    }
    if (VIEWS.has(table)) continue;               // no DDL column list to check
    const cols = schema.get(table);

    // Stop the window at the next `.from(` so a later chain is not attributed here.
    let seg = s.slice(m.index + m[0].length, m.index + m[0].length + 3000);
    const cut = seg.indexOf('.from(');
    if (cut >= 0) seg = seg.slice(0, cut);
    const base = m.index + m[0].length;

    const sm = /^\s*\.?\s*\n?\s*\.select\(\s*(['"])([\s\S]*?)\1/.exec(seg);
    if (sm && sm[2].trim() && sm[2].trim() !== '*') {
      for (const c of selectColumns(sm[2])) {
        if (!cols.has(c)) {
          const k = `${table}.${c}`;
          if (!found.missingColumn.has(k)) found.missingColumn.set(k, []);
          found.missingColumn.get(k).push(`${path}:${line} (select)`);
        }
      }
    }

    // Embedded resources. A head spelled `alias:column` or a bare `column`
    // names a FK column; PostgREST needs that FK to land inside `public`. A
    // head spelled `relation!hint` names the relation itself and is checked by
    // the relation pass above.
    const joined = selectSpecJoined(seg);
    if (joined) {
      for (const head of embedHeads(joined)) {
        if (head.includes('!') || head.includes('$') || head.includes('{')) continue;
        const col = head.includes(':') ? head.split(':').pop().trim() : head.trim();
        if (!/^[a-z0-9_]+$/.test(col)) continue;
        if (!cols.has(col)) continue;             // not a column of this table
        const fk = foreignKeys.get(`${table}.${col}`);
        if (fk && fk.schema === 'public') continue;
        const k = `${table}.${col}`;
        if (!unresolvableEmbed.has(k)) unresolvableEmbed.set(k, []);
        unresolvableEmbed.get(k).push(
          `${path}:${line} (embed '${head}' -> ${fk ? `${fk.schema}.${fk.table}` : 'no foreign key'})`,
        );
      }
    }

    const wm = /\.(insert|update|upsert)\(/.exec(seg);
    if (wm) {
      const open = base + wm.index + wm[0].length - 1;
      const end = closing(s, open);
      if (end > 0) {
        const body = s.slice(open, end);
        writeSites.total++;
        const opaque = !body.includes('{');
        const spread = !opaque && body.includes('...');
        if (opaque) writeSites.opaquePayload++;
        else {
          writeSites.inlineLiteral++;
          if (spread) writeSites.hasSpread++;
        }
        if (LIST_UNSEEN && (opaque || spread)) {
          unseenSites.push({
            shape: opaque ? 'opaque' : 'spread', table, op: wm[1],
            at: `${path}:${line}`,
            payload: body.trim().replace(/\s+/g, ' ').slice(0, 46),
          });
        }
        // A key is a column only at brace depth 1 of the payload object; a key
        // deeper than that belongs to a nested jsonb value, not to the table.
        let brace = 0;
        for (let i = 0; i < body.length; i++) {
          if (body[i] === '{') { brace++; continue; }
          if (body[i] === '}') { brace--; continue; }
          const km = /^['"]([a-z][a-z0-9_]*)['"]\s*:/.exec(body.slice(i));
          if (!km || brace !== 1) continue;
          // Must be in key position: a quoted word followed by `:` is also the
          // middle of a ternary (`x ? 'metric' : 'imperial'`).
          const prev = body.slice(0, i).replace(/\s+$/, '').slice(-1);
          if (prev !== '{' && prev !== ',') continue;
          i += km[0].length - 1;
          if (cols.has(km[1])) continue;
          const key = `${table}.${km[1]}`;
          if (!found.missingColumn.has(key)) found.missingColumn.set(key, []);
          found.missingColumn.get(key).push(`${path}:${line} (${wm[1]})`);
        }
      }
    }
  }
}

const allowedRel = new Map(known.missingRelation.map((v) => [v.table, v.finding]));
const allowedCol = new Map(known.missingColumn.map((v) => [`${v.table}.${v.column}`, v.finding]));
let failures = 0;

const report = (label, foundMap, allowed) => {
  for (const [k, sites] of foundMap) {
    if (allowed.has(k)) {
      console.log(`  known  ${label} ${k.padEnd(38)} ${allowed.get(k)}  (${sites.length} site${sites.length > 1 ? 's' : ''})`);
    } else {
      failures++;
      console.log(`  FAIL   ${label} ${k} is referenced but does not exist`);
      sites.forEach((x) => console.log(`           at ${x}`));
    }
  }
  for (const [k, finding] of allowed) {
    if (!foundMap.has(k)) {
      failures++;
      console.log(`  FAIL   ${label} ${k} no longer reproduces — remove it from known-violations.json (${finding})`);
    }
  }
};

console.log(
  `\nSchema contract guard — ${schema.size} tables + ${VIEWS.size} views + ` +
  `${foreignKeys.size} foreign keys derived from supabase/migrations\n`,
);
report('relation', found.missingRelation, allowedRel);
report('column  ', found.missingColumn, allowedCol);

// A guard that silently parsed nothing would pass forever. These two anchors
// are read from the migrations, not asserted about the client.
for (const [key, want] of [
  ['coach_client_relationships.coach_id', 'auth'],
  ['coaching_calls.coach_id', 'public'],
]) {
  const fk = foreignKeys.get(key);
  if (!fk || fk.schema !== want) {
    failures++;
    console.log(`  FAIL   selftest ${key} should resolve to schema '${want}', got ${fk ? fk.schema : 'nothing'}`);
  }
}

for (const [k, sites] of unresolvableEmbed) {
  failures++;
  console.log(`  FAIL   embed    ${k} is embedded but no foreign key reaches the public schema`);
  sites.forEach((x) => console.log(`           at ${x}`));
}

const unseen = writeSites.opaquePayload + writeSites.hasSpread;
console.log(
  `  COVERAGE  write sites ${writeSites.total}: ${writeSites.inlineLiteral - writeSites.hasSpread} fully analysed, `
  + `${writeSites.hasSpread} with a spread (literal keys only), ${writeSites.opaquePayload} opaque (payload by variable)`,
);
if (LIST_UNSEEN && unseenSites.length) {
  console.log('\n  Sites whose column keys this guard cannot see:');
  for (const u of unseenSites.sort((a, b) => a.table.localeCompare(b.table))) {
    console.log(`    ${u.shape.padEnd(6)} ${u.table.padEnd(24)} ${u.op.padEnd(6)} ${u.at}  ${u.payload}`);
  }
  console.log('');
}
if (unseen > 0) {
  console.log(
    `  COVERAGE  ${unseen} write site(s) contribute column keys this guard CANNOT see. `
    + 'A PASS below does not mean every write key was checked.',
  );
}
console.log(
  failures === 0
    // The scope rides ON the verdict line, not only above it. This is the line
    // that gets grepped and quoted into evidence ledgers, and quoted alone a
    // bare PASS reads as "every write key was checked", which is false for the
    // `unseen` sites. Keeping the caveat adjacent is not enough when the
    // quotable line travels without its context.
    ? `\nPASS  no unknown relation or column outside the ${allowedRel.size + allowedCol.size}-entry known-violations allowlist`
      + ` — scope: ${writeSites.inlineLiteral - writeSites.hasSpread} of ${writeSites.total} write sites fully analysed, ${unseen} NOT (see COVERAGE)\n`
    : `\nFAIL  ${failures} contract violation(s)\n`,
);
process.exit(failures === 0 ? 0 : 1);
