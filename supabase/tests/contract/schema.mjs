// Derives the `public` schema (tables → columns) from supabase/migrations by
// replaying CREATE TABLE / ALTER TABLE ADD|DROP|RENAME COLUMN in file order.
//
// This is the *offline* source of truth for the contract guard. It was verified
// byte-exact against a live `supabase db dump --linked` of QA
// (eyqtldjqpgpljlqvpowh) on 2026-08-24: 91 tables, 0 column drift. Views are
// listed separately because their column set comes from a SELECT list, not DDL.
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

const MIGRATIONS = 'supabase/migrations';

// Views ARE derived from DDL. They did not used to be, and the inventory drifted.
//
// ── WHY THIS CHANGED, AND IT IS THE FINDING ─────────────────────────────────
// This set was hand-maintained, with a header asserting "pg_class holds exactly
// these six views in public, no more and no fewer" as verified on 2026-09-27.
// Migrations 156-174 then added TWELVE `admin_*` views and none was added here, so
// the guard reported a real, applied view as "referenced but does not exist" — a
// FALSE POSITIVE that would have been resolved by deleting the reference to a view
// that is genuinely there.
//
// A hardcoded list covers the objects someone remembered. D15 learned this and
// switched to discovery (V5 §139.6); SEC-G4 learned it again this week. So the
// inventory is now derived from the migration set, and `HAND_VERIFIED_FLOOR` is kept
// only as a positive control: if discovery ever fails to find one of the views a
// human confirmed against the live catalog, the derivation is broken and this module
// refuses to load rather than reporting a clean schema.
//
// A VIEW'S COLUMNS ARE STILL NOT CHECKED HERE, which is unchanged: a view's column
// set comes from a SELECT list, not DDL. That coverage lives where it can be exact —
// D15 pins the admin overview views' column sets, and D16 asserts them against the
// live QA database.
const HAND_VERIFIED_FLOOR = new Set([
  'coach_client_workout_stats',
  'conversation_participant_profiles',
  'exercise_certifications',
  'exercises',
  'public_profiles',
  'team_member_profiles',
  'event_attendee_profiles',
]);

function deriveViews() {
  const found = new Set();
  for (const f of readdirSync(MIGRATIONS).filter((x) => x.endsWith('.sql')).sort()) {
    const sql = stripComments(readFileSync(`${MIGRATIONS}/${f}`, 'utf8'));
    for (const m of sql.matchAll(
      /CREATE\s+(?:OR\s+REPLACE\s+)?(?:MATERIALIZED\s+)?VIEW\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:public\.)?"?([a-z0-9_]+)"?/gi)) {
      found.add(m[1].toLowerCase());
    }
    // A view may also be dropped; a dropped-and-not-recreated view must not linger.
    for (const m of sql.matchAll(
      /DROP\s+VIEW\s+(?:IF\s+EXISTS\s+)?(?:public\.)?"?([a-z0-9_]+)"?/gi)) {
      found.delete(m[1].toLowerCase());
    }
  }
  if (found.size === 0) {
    throw new Error('schema.mjs: derived ZERO views from ' + MIGRATIONS +
      ' — the derivation is broken, not the schema; refusing to load');
  }
  const missing = [...HAND_VERIFIED_FLOOR].filter((v) => !found.has(v));
  if (missing.length) {
    throw new Error('schema.mjs: view derivation did not find ' + missing.join(', ') +
      ' — each was hand-verified against the live QA catalog, so the derivation is ' +
      'broken. Refusing to load rather than report a schema that is missing views.');
  }
  return found;
}


// `.from()` names that are Storage buckets, not relations.
export const STORAGE_BUCKETS = new Set(['avatars', 'exercise-media', 'progress-photos']);

const stripComments = (sql) =>
  sql.replace(/\/\*[\s\S]*?\*\//g, '').replace(/--[^\n]*/g, '');

// Evaluated here, after stripComments exists — a `const` is not hoisted, and the
// first draft of this derivation crashed on exactly that.
export const VIEWS = deriveViews();

function splitTopLevel(body) {
  const out = [];
  let cur = '', depth = 0;
  for (const ch of body) {
    if (ch === '(') depth++;
    if (ch === ')') depth--;
    if (ch === ',' && depth === 0) { out.push(cur); cur = ''; continue; }
    cur += ch;
  }
  out.push(cur);
  return out;
}

export function deriveSchema(dir = MIGRATIONS) {
  const tables = new Map();
  const files = readdirSync(dir).filter((f) => f.endsWith('.sql')).sort();

  for (const f of files) {
    const sql = stripComments(readFileSync(join(dir, f), 'utf8'));

    const createRe =
      /create\s+table\s+(?:if\s+not\s+exists\s+)?(?:public\.)?"?([a-z0-9_]+)"?\s*\(([\s\S]*?)\n\)\s*;/gi;
    for (const m of sql.matchAll(createRe)) {
      const t = m[1];
      const cols = tables.get(t) ?? new Set();
      for (const raw of splitTopLevel(m[2])) {
        const c = raw.trim();
        if (/^(constraint|check|primary\s+key|unique|foreign\s+key|exclude)\b/i.test(c)) continue;
        const cm = /^"?([a-z0-9_]+)"?\s/.exec(c);
        if (cm) cols.add(cm[1]);
      }
      tables.set(t, cols);
    }

    const alterRe =
      /alter\s+table\s+(?:if\s+exists\s+)?(?:public\.)?"?([a-z0-9_]+)"?\s+([\s\S]*?);/gi;
    for (const m of sql.matchAll(alterRe)) {
      const t = m[1], clause = m[2];
      for (const a of clause.matchAll(/add\s+column\s+(?:if\s+not\s+exists\s+)?"?([a-z0-9_]+)"?/gi)) {
        if (!tables.has(t)) tables.set(t, new Set());
        tables.get(t).add(a[1]);
      }
      for (const a of clause.matchAll(/drop\s+column\s+(?:if\s+exists\s+)?"?([a-z0-9_]+)"?/gi)) {
        tables.get(t)?.delete(a[1]);
      }
      for (const a of clause.matchAll(/rename\s+column\s+"?([a-z0-9_]+)"?\s+to\s+"?([a-z0-9_]+)"?/gi)) {
        if (!tables.has(t)) tables.set(t, new Set());
        tables.get(t).delete(a[1]);
        tables.get(t).add(a[2]);
      }
    }
  }
  return tables;
}

// ── Foreign keys ─────────────────────────────────────────────────────────────
//
// PostgREST resolves an embedded resource through a foreign key. A FK whose
// target lives outside the `public` schema is invisible to it: the request is
// rejected with PGRST200 ("no matches were found") before any row is read, and
// every caller in this repository swallows that failure. UIX-1 / M-03 was
// exactly this — `coach_client_relationships.coach_id` references
// `auth.users`, so the booking screen's embed could never resolve.
//
// Returns `"<table>.<column>" -> { schema, table }` for the referenced side.
export function deriveForeignKeys(dir = MIGRATIONS) {
  const fks = new Map();
  const files = readdirSync(dir).filter((f) => f.endsWith('.sql')).sort();

  for (const f of files) {
    const sql = stripComments(readFileSync(join(dir, f), 'utf8'));

    // ALTER TABLE <t> ADD CONSTRAINT ... FOREIGN KEY (<c>) REFERENCES <s>.<r>
    const alterRe =
      /alter\s+table\s+(?:only\s+)?(?:if\s+exists\s+)?(?:public\.)?"?([a-z0-9_]+)"?[\s\S]{0,400}?foreign\s+key\s*\(\s*"?([a-z0-9_]+)"?\s*\)\s*references\s+(?:"?([a-z0-9_]+)"?\.)?"?([a-z0-9_]+)"?/gi;
    for (const m of sql.matchAll(alterRe)) {
      fks.set(`${m[1].toLowerCase()}.${m[2].toLowerCase()}`, {
        schema: (m[3] ?? 'public').toLowerCase(),
        table: m[4].toLowerCase(),
      });
    }

    // Column-level REFERENCES inside CREATE TABLE. First definition wins; a
    // later ALTER above overwrites it, which matches replay order.
    const createRe =
      /create\s+table\s+(?:if\s+not\s+exists\s+)?(?:public\.)?"?([a-z0-9_]+)"?\s*\(([\s\S]*?)\n\)\s*;/gi;
    for (const m of sql.matchAll(createRe)) {
      const t = m[1].toLowerCase();
      const inlineRe =
        /^\s*"?([a-z0-9_]+)"?\s+[^,]*?references\s+(?:"?([a-z0-9_]+)"?\.)?"?([a-z0-9_]+)"?/gim;
      for (const c of m[2].matchAll(inlineRe)) {
        const key = `${t}.${c[1].toLowerCase()}`;
        if (fks.has(key)) continue;
        fks.set(key, {
          schema: (c[2] ?? 'public').toLowerCase(),
          table: c[3].toLowerCase(),
        });
      }
    }
  }
  return fks;
}
