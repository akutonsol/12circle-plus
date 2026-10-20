// I-MIG-03 — the migration durability (class) guard.  Wave 2 task 2B.
//
// ── Why this file exists ────────────────────────────────────────────────────
//
// `CREATE OR REPLACE FUNCTION` preserves a function's ACL and its owner. It does
// NOT preserve `proconfig` (the `SET search_path` pin) and it obviously does not
// preserve a body — so an authorization guard written into the body of an
// earlier migration vanishes the moment a later migration reproduces that
// function from an older base. Nothing in Postgres warns. Nothing in a diff
// review reliably catches it: the later migration looks like a correct,
// self-contained function definition, because it is one.
//
// This has now happened three times in this repository (registry §4.2):
//
//   * 116 published `materialize_program_week` as a thin authorization wrapper
//     over `materialize_program_week_engine`. **119 replaced it with a bare
//     SECURITY DEFINER body and re-granted EXECUTE to `authenticated`.** That is
//     finding **F-J-01 / SEC-R1**, still open, remediated by migration 124 in
//     Wave 2 task 2A.
//   * 119/120/121 unpinned `search_path` on fifteen functions; migration 122
//     put the pin back.
//
// Migration 122's own header states the mechanism exactly and asks for the class
// fix. This is that class fix: the durable, standing check that no future
// migration may quietly drop a security property another migration established.
//
// ── What this guard is, and is not ──────────────────────────────────────────
//
// It is a **static guard** in the sense of the testing-governance vocabulary: it
// reads committed migration source and asserts an invariant about it. It never
// connects to a database, needs no credentials, and asserts nothing about the
// live catalog. A property restored by a *dynamic* catalog sweep (122 §1 runs
// `EXECUTE format('ALTER FUNCTION %s SET search_path = ...')` over a query) is
// not statically verifiable, and this guard says so in those words rather than
// reporting it as either a violation or a closure. The live half of that
// evidence is `function-search-path.sql`, which is not yet wired into CI
// (follow-up **FG-1**).
//
// ── The class, stated narrowly ──────────────────────────────────────────────
//
// I-MIG-03's class, and no wider: a function is *security-carrying* from the
// migration in which it first acquires any of
//
//   a. an authorization wrapper — a call, in the function body, to one of the
//      authorization predicates 116 established (`AUTH_PREDICATES` below);
//   b. a `search_path` pin — `SET search_path = ...` in the definition header;
//   c. a SECURITY DEFINER boundary — including the trigger functions 118/122
//      treat as part of the same posture.
//
// From that migration onward, every redefinition of that function must carry
// each property it had. A redefinition that drops one is a **strip event**.
//
// ── CI posture: ENFORCING ──────────────────────
//
// Migration 124 remediated F-J-01 and restored the authorization wrapper.
// `KNOWN_OPEN` is now empty, so the guard operates in full enforcement mode.
//
// The guard runs in two tiers, and the detection logic is identical in both:
//
//   * a strip event listed in `KNOWN_OPEN` — recorded, printed in full, and
//     **not counted as a failure**. This mechanism exists only for a finding
//     that has been explicitly accepted as open during a transition.
//   * any other unrestored strip event — **fatal**. A regression this programme
//     has not already accepted fails the guard the first time it appears.
//
// The guard therefore protects against the next authorization regression.
// If a finding is remediated but its `KNOWN_OPEN` entry is not removed,
// `staleKnownOpen` reports that stale exemption explicitly. This prevents
// a temporary records-mode exception from becoming a permanent bypass.
//
// Historical F-J-01 detection remains covered by the self-test: the synthetic
// 116 → 119 regression must still be detected, while the current migration
// chain must prove that migration 124 has closed it.
//
//   node supabase/tests/security/migration-durability-guard.mjs
//
// Exit code: 0 when every strip event is either restored or a recorded
// known-open finding; 1 when an unrecorded strip event exists.

import { readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
export const MIGRATIONS_DIR = join(HERE, '..', '..', 'migrations');

/**
 * The authorization predicates migration 116 established. A call to one of
 * these inside a function body IS the "authorization wrapper" of I-MIG-03.
 *
 * Deliberately narrow. `auth.uid()` is not in this list: a function that reads
 * `auth.uid()` may be doing anything at all with it, and treating that as an
 * authorization guard would make this guard fire on functions it does not
 * understand. The class is the one the registry documents, not a wider one.
 */
export const AUTH_PREDICATES = [
  'can_act_for',
  'can_act_on_program',
  'require_content_editor',
  'is_content_editor',
  'is_active_coach_of',
];

/**
 * Strip events the programme has already recorded, triaged and scheduled.
 * Recorded, not fatal. Every entry must name a finding and the task that closes
 * it — an exemption without an owner is not an exemption, it is a hole.
 */
export const KNOWN_OPEN = [];

// ── parsing ─────────────────────────────────────────────────────────────────

/** `123_some_name.sql` → `123`. Files are processed in this numeric order. */
const numberOf = (file) => {
  const m = /^(\d+)/.exec(file);
  return m ? m[1] : null;
};

export function migrationFiles(dir = MIGRATIONS_DIR) {
  return readdirSync(dir)
    .filter((f) => f.endsWith('.sql') && /^\d+/.test(f))
    .sort((a, b) => Number(numberOf(a)) - Number(numberOf(b)));
}

/**
 * Every `CREATE OR REPLACE FUNCTION public.<name>(` in one migration, with the
 * header (everything up to the opening `AS $tag$`) and the body separated.
 *
 * The split matters: `SET search_path` and `SECURITY DEFINER` are header
 * properties, an authorization guard is a body property, and a function whose
 * *body* merely mentions the words "search_path" (122 does, in a comment) must
 * not be read as pinning anything.
 */
/**
 * SQL with comments and single-quoted literals removed, so a security property
 * is decided by CODE and never by prose.
 *
 * MEASURED, not hypothetical. Before this existed, every one of this guard's
 * three properties could be satisfied by text that executes nothing:
 *
 *   auth-wrapper      `-- authorization is handled by public.can_act_for(p)`  -> true
 *   auth-wrapper      `/* was: public.is_active_coach_of(p) *\/`              -> true
 *   auth-wrapper      `RAISE NOTICE 'checked via require_content_editor()'`   -> true
 *   security-definer  `-- intentionally no longer SECURITY DEFINER`           -> true
 *   search-path-pin   `-- dropped the SET search_path = public, pg_temp pin`  -> true
 *
 * That direction matters: a false POSITIVE on a property makes `analyse()`
 * believe the property is still present, so the strip is never recorded and the
 * regression passes. A migration that deletes a real predicate and leaves a
 * "was: ..." comment beside it — the house comment style in this tree, see
 * 123:120 — would have gone undetected. That is precisely the F-J-01 class this
 * guard exists to catch.
 *
 * One pass, because order matters in both directions: a `--` inside a literal
 * is not a comment, and a `'` inside a comment does not open a literal. Doubled
 * `''` is an escaped quote and does not close the literal. Dollar-quoted inner
 * strings are left alone — the body has already been cut at its own tag, and a
 * nested tag carries no `'` to confuse this.
 *
 * Replacement preserves newlines so reported line positions do not shift.
 */
export function sqlCode(sql) {
  let out = '';
  let i = 0;
  const n = sql.length;
  while (i < n) {
    const c = sql[i];
    const next = sql[i + 1];
    if (c === '-' && next === '-') {                 // line comment
      while (i < n && sql[i] !== '\n') i += 1;
      continue;
    }
    if (c === '/' && next === '*') {                 // block comment
      i += 2;
      while (i < n && !(sql[i] === '*' && sql[i + 1] === '/')) {
        if (sql[i] === '\n') out += '\n';
        i += 1;
      }
      i += 2;
      continue;
    }
    if (c === "'") {                                 // single-quoted literal
      i += 1;
      while (i < n) {
        if (sql[i] === "'" && sql[i + 1] === "'") { i += 2; continue; }
        if (sql[i] === "'") { i += 1; break; }
        if (sql[i] === '\n') out += '\n';
        i += 1;
      }
      out += "''";                                   // keep it a syntactic literal
      continue;
    }
    if (c === '"') {                                 // quoted IDENTIFIER
      // Identifiers are code, not data, so they pass through verbatim. They
      // must still be consumed as a unit: this tree has identifiers that
      // contain an apostrophe — `"Coach: read an ACTIVE client's photos"`,
      // `"Child's Pose"` — and reading that quote as a literal opener would
      // swallow the code after it.
      out += c;
      i += 1;
      while (i < n) {
        if (sql[i] === '"' && sql[i + 1] === '"') { out += '""'; i += 2; continue; }
        out += sql[i];
        if (sql[i] === '"') { i += 1; break; }
        i += 1;
      }
      continue;
    }
    const dq = c === '$' ? /^\$[a-z_]*\$/i.exec(sql.slice(i)) : null;
    if (dq) {                                        // dollar-quoted literal
      // 44 of these exist in supabase/migrations: `$q$`, `$j$`, `$f$`, `$ddl$`.
      // A dollar-quoted block is a string, so it is stripped like one. Without
      // this, an apostrophe inside such a block — `$q$ it''s dynamic $q$` —
      // opens a phantom literal that swallows the rest of the body. That
      // direction is loud rather than silent (the predicate goes missing, a
      // strip is recorded, the guard fails), but a false alarm in an enforcing
      // guard teaches people to override it, so it is closed here.
      const tag = dq[0];
      const end = sql.indexOf(tag, i + tag.length);
      const inner = end === -1 ? sql.slice(i + tag.length) : sql.slice(i + tag.length, end);
      for (const ch of inner) if (ch === '\n') out += '\n';
      out += tag + tag;                              // keep it a syntactic literal
      i = end === -1 ? n : end + tag.length;
      continue;
    }
    out += c;
    i += 1;
  }
  return out;
}

export function parseDefinitions(sql) {
  const out = [];
  const re = /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+(?:public\.)?([a-z0-9_]+)\s*\(/gi;
  let m;
  while ((m = re.exec(sql)) !== null) {
    const name = m[1];
    const rest = sql.slice(m.index);

    // Header = up to the body-opening dollar quote, e.g. `AS $$` / `AS $fn$`.
    const open = /\bAS\s+(\$[a-z_]*\$)/i.exec(rest);
    if (!open) continue;
    const tag = open[1];
    const header = rest.slice(0, open.index);
    const afterOpen = rest.slice(open.index + open[0].length);
    const close = afterOpen.indexOf(tag);
    const body = close === -1 ? afterOpen : afterOpen.slice(0, close);

    // Properties are decided on CODE, never on prose. `header`/`body` stay raw
    // for reporting; `headerCode`/`code` are what any security test must read.
    const headerCode = sqlCode(header);
    const code = sqlCode(body);

    out.push({
      name,
      header,
      body,
      headerCode,
      code,
      properties: {
        'auth-wrapper': AUTH_PREDICATES.some((p) =>
          new RegExp(`\\b(?:public\\.)?${p}\\s*\\(`, 'i').test(code)),
        'search-path-pin': /\bSET\s+search_path\s*=/i.test(headerCode),
        'security-definer': /\bSECURITY\s+DEFINER\b/i.test(headerCode),
      },
    });
  }
  return out;
}

/**
 * Literal, per-function `ALTER FUNCTION public.f(...) SET search_path = ...`.
 * This restores the pin in a way a reader — and this guard — can verify.
 */
export function parseLiteralSearchPathRestores(sql) {
  const out = new Set();
  const re = /ALTER\s+FUNCTION\s+(?:public\.)?([a-z0-9_]+)\s*\([^)]*\)\s*SET\s+search_path\s*=/gi;
  let m;
  while ((m = re.exec(sql)) !== null) out.add(m[1]);
  return out;
}

/**
 * A dynamic catalog sweep — `EXECUTE format('ALTER FUNCTION %s SET search_path
 * = ...')` over a query, which is how 122 §1 repinned fifteen functions at once.
 *
 * It restores the property in the database and is invisible to static analysis:
 * the guard can see that the migration performs a sweep, never which functions
 * it reached. Reported as exactly that, and never as a closure.
 */
export function hasDynamicSearchPathSweep(sql) {
  return /EXECUTE\s+format\(\s*'ALTER\s+FUNCTION[^']*SET\s+search_path/i.test(sql);
}

// ── analysis ────────────────────────────────────────────────────────────────

export const PROPERTY_LABEL = {
  'auth-wrapper': 'authorization wrapper',
  'search-path-pin': 'search_path pin',
  'security-definer': 'SECURITY DEFINER boundary',
};

/**
 * Walk the migration chain in order, carrying each function's established
 * security properties forward, and record every redefinition that drops one.
 *
 * Returns { strips, wrappers, files } where `strips` carries a resolution:
 *   restored           — a later migration literally re-establishes it
 *   restored-by-sweep  — a later migration claims it dynamically (unverifiable)
 *   open               — nothing re-establishes it
 */
export function analyse(dir = MIGRATIONS_DIR) {
  const files = migrationFiles(dir);
  const established = new Map();   // fn -> { property -> migration number }
  const strips = [];
  const wrappers = new Map();      // fn -> { migration, predicates[] }

  for (const file of files) {
    const num = numberOf(file);
    const sql = readFileSync(join(dir, file), 'utf8');
    const literalRestores = parseLiteralSearchPathRestores(sql);
    const sweep = hasDynamicSearchPathSweep(sql);

    // A literal ALTER re-establishes the pin without redefining the function.
    for (const fn of literalRestores) {
      const prev = established.get(fn) || {};
      prev['search-path-pin'] = num;
      established.set(fn, prev);
      for (const s of strips) {
        if (s.fn === fn && s.property === 'search-path-pin' && s.resolution === 'open') {
          s.resolution = 'restored';
          s.resolvedBy = num;
        }
      }
    }

    if (sweep) {
      for (const s of strips) {
        if (s.property === 'search-path-pin' && s.resolution === 'open') {
          s.resolution = 'restored-by-sweep';
          s.resolvedBy = num;
        }
      }
    }

    for (const def of parseDefinitions(sql)) {
      const had = established.get(def.name) || {};

      // Record the wrapper set as the migration source defines it, so a
      // consumer (d04) can assert the class rather than a hand-copied list.
      if (def.properties['auth-wrapper']) {
        wrappers.set(def.name, {
          migration: num,
          predicates: AUTH_PREDICATES.filter((p) =>
            new RegExp(`\\b(?:public\\.)?${p}\\s*\\(`, 'i').test(def.code)),
        });
      } else if (wrappers.has(def.name)) {
        wrappers.delete(def.name);   // the wrapper is gone as of this migration
      }

      for (const property of Object.keys(PROPERTY_LABEL)) {
        if (had[property] && !def.properties[property]) {
          strips.push({
            fn: def.name,
            property,
            establishedBy: had[property],
            strippedBy: num,
            file,
            resolution: 'open',
            resolvedBy: null,
          });
          delete had[property];
        } else if (def.properties[property]) {
          had[property] = num;
          for (const s of strips) {
            if (s.fn === def.name && s.property === property && s.resolution === 'open') {
              s.resolution = 'restored';
              s.resolvedBy = num;
            }
          }
        }
      }
      established.set(def.name, had);
    }
  }

  return { strips, wrappers, files };
}

/**
 * The 116 engine-wrapper class: every function that migration 116 published as
 * a thin authorization wrapper in front of a `<name>_engine` implementation.
 *
 * Derived from the migration source rather than hand-listed, so that the live
 * suite asserting this class cannot silently fall behind the schema. If 116's
 * set ever grows, the consumer's completeness assertion fails and someone
 * extends the coverage deliberately — which is precisely the failure mode
 * F-J-01 exposed: `d04` pinned individual instances and the class grew a hole.
 *
 * A member appears here even after a later migration strips its guard — the
 * class is defined by what 116 established, and a stripped member is a finding,
 * not a non-member. `analyse().wrappers` reports the *current* guard state.
 *
 * `establishedIn` defaults to `'116'` because that is the class W2-2B and the
 * I-MIG-03 finding name. **Migration 117 applied the same wrapper-over-engine
 * shape to eight content-editor functions** (`intelligence_review_queue`,
 * `intelligence_stats`, `intelligence_low_confidence`, `decision_analytics`,
 * `movement_graph_stats`, `attribute_review_state`, `exercise_content_stats`,
 * `certification_summary`). They are structurally identical and none is
 * currently stripped — `engineWrapperClass({ establishedIn: null })` returns all
 * thirteen. Extending d04's class coverage to 117's eight is a reasonable
 * follow-up, and it is deliberately NOT done here: W2-2B authorises the 116
 * class, and widening scope inside an authorised task is how a task stops being
 * reviewable. Recorded so the choice is visible rather than lost.
 */
export function engineWrapperClass({ establishedIn = '116', dir = MIGRATIONS_DIR } = {}) {
  const members = new Map();
  for (const file of migrationFiles(dir)) {
    const num = numberOf(file);
    for (const def of parseDefinitions(readFileSync(join(dir, file), 'utf8'))) {
      const callsOwnEngine = new RegExp(`\\b(?:public\\.)?${def.name}_engine\\s*\\(`, 'i').test(def.code);
      if (callsOwnEngine && def.properties['auth-wrapper'] && !members.has(def.name)) {
        members.set(def.name, {
          establishedBy: num,
          predicates: AUTH_PREDICATES.filter((p) =>
            new RegExp(`\\b(?:public\\.)?${p}\\s*\\(`, 'i').test(def.code)),
        });
      }
    }
  }
  if (!establishedIn) return members;
  return new Map([...members].filter(([, w]) => w.establishedBy === establishedIn));
}

export const isKnownOpen = (s) =>
  KNOWN_OPEN.some((k) => k.fn === s.fn && k.property === s.property && k.strippedBy === s.strippedBy);

/** Register entries that no longer correspond to a real strip — i.e. stale exemptions. */
export const staleKnownOpen = (strips) =>
  KNOWN_OPEN.filter((k) => !strips.some(
    (s) => s.fn === k.fn && s.property === k.property && s.strippedBy === k.strippedBy
             && s.resolution === 'open'));

/**
 * The guard's verdict, mode-independent.
 *
 *   unrecorded — strip events that are open and NOT in KNOWN_OPEN: fatal
 *   recorded   — strip events that are open and in KNOWN_OPEN: printed, not fatal
 *   stale      — KNOWN_OPEN entries with no matching open strip: fatal, because
 *                a records-mode exemption that outlives its defect is how this
 *                kind of guard quietly stops guarding
 */
export function verdict(analysis = analyse()) {
  const open = analysis.strips.filter((s) => s.resolution === 'open');
  return {
    ...analysis,
    open,
    recorded: open.filter(isKnownOpen),
    unrecorded: open.filter((s) => !isKnownOpen(s)),
    sweepRestored: analysis.strips.filter((s) => s.resolution === 'restored-by-sweep'),
    stale: staleKnownOpen(analysis.strips),
  };
}

// ── CLI ─────────────────────────────────────────────────────────────────────

function report() {
  const v = verdict();
  const line = '─'.repeat(74);

  console.log(`\n${'█'.repeat(74)}`);
  console.log('██  I-MIG-03 · migration durability (class) guard');
  console.log('██  MODE: ENFORCING — no known-open exemptions');
  console.log('█'.repeat(74));
  console.log(`\n  ${v.files.length} migrations scanned · ${v.strips.length} strip event(s) found`);

  const c116 = engineWrapperClass();
  const cAll = engineWrapperClass({ establishedIn: null });
  console.log(`\n${line}\n  116 engine-wrapper class — the class d04 §8 asserts\n${line}`);
  for (const [fn, w] of [...c116].sort()) {
    const stripped = v.open.some((s) => s.fn === fn && s.property === 'auth-wrapper');
    console.log(`  ${stripped ? 'STRIPPED' : '  intact'}  ${fn.padEnd(28)} ${w.predicates.join(', ')}`);
  }
  console.log(`\n  Same shape, established elsewhere (${cAll.size - c116.size} functions, migration 117):`);
  console.log(`  ${[...cAll.keys()].filter((k) => !c116.has(k)).join(', ')}`);
  console.log('  None stripped. Out of W2-2B scope — extending d04 to cover them is a follow-up.');

  console.log(`\n${line}\n  Every authorization-carrying function, current guard state\n${line}`);
  if (v.wrappers.size === 0) {
    console.log('  (none — this is itself a finding: 116 established five)');
  } else {
    for (const [fn, w] of [...v.wrappers].sort()) {
      console.log(`  ${fn.padEnd(34)} ${w.predicates.join(', ')}  (migration ${w.migration})`);
    }
  }

  console.log(`\n${line}\n  Strip events\n${line}`);
  if (!v.strips.length) console.log('  none');
  for (const s of v.strips) {
    const mark = s.resolution === 'open' ? (isKnownOpen(s) ? 'RECORDED' : 'VIOLATION')
               : s.resolution === 'restored' ? 'restored'
               : 'sweep';
    console.log(`  [${mark.padEnd(9)}] ${s.fn}(${PROPERTY_LABEL[s.property]})`
      + `  established ${s.establishedBy} → stripped ${s.strippedBy}`
      + (s.resolvedBy ? ` → ${s.resolution === 'restored-by-sweep'
          ? `claimed by ${s.resolvedBy}'s dynamic sweep (NOT statically verifiable — live evidence is FG-1)`
          : `restored ${s.resolvedBy}`}` : ''));
  }

  if (v.recorded.length) {
    console.log(`\n${line}\n  RECORDED — known open, already triaged. Not counted as failures.\n${line}`);
    for (const s of v.recorded) {
      const k = KNOWN_OPEN.find((x) => x.fn === s.fn && x.property === s.property);
      console.log(`\n  ${s.fn} — ${PROPERTY_LABEL[s.property]} stripped by migration ${s.strippedBy}`);
      console.log(`    finding:  ${k.finding}`);
      console.log(`    closes:   ${k.closedBy}`);
      console.log(`    detail:   ${k.note}`);
    }
    console.log('\n  These are DETECTED, not fixed. This guard changes no migration and');
    console.log('  closes no finding. Enforcement is promoted in 2A, when the register empties.');
  }

  let failures = 0;

  if (v.unrecorded.length) {
    console.log(`\n${line}\n  VIOLATION — a security property was dropped and never restored\n${line}`);
    for (const s of v.unrecorded) {
      console.log(`  ${s.fn}: ${PROPERTY_LABEL[s.property]} established by migration `
        + `${s.establishedBy}, dropped by ${s.strippedBy} (${s.file}), never restored.`);
    }
    console.log('\n  Carry the property forward in a NEW migration — never by editing history.');
    console.log('  If this is a deliberate, reviewed change, it belongs in KNOWN_OPEN with a');
    console.log('  finding id and the task that closes it, not silently in the tree.');
    failures += v.unrecorded.length;
  }

  if (v.stale.length) {
    console.log(`\n${line}\n  STALE EXEMPTION — KNOWN_OPEN entry with no matching open strip\n${line}`);
    for (const k of v.stale) {
      console.log(`  ${k.fn} (${PROPERTY_LABEL[k.property]}, ${k.finding}) appears remediated.`);
      console.log('  Remove the entry and promote this guard to ENFORCING as part of that closure.');
    }
    failures += v.stale.length;
  }

  console.log(`\n${line}`);
  if (failures === 0) {
    console.log(`  PASS (enforcing) — ${v.recorded.length} recorded known-open, `
      + `${v.unrecorded.length} unrecorded, ${v.sweepRestored.length} sweep-claimed.`);
    console.log('  No unrecorded regression. KNOWN_OPEN is empty; F-J-01 is closed.');
  } else {
    console.log(`  FAIL — ${failures} condition(s) this guard does not exempt.`);
  }
  console.log(`${line}\n`);
  return failures;
}

// ── self-test ───────────────────────────────────────────────────────────────
//
// `--self-test` proves the detector still detects. A records-mode guard that
// quietly stopped working would look exactly like a clean tree, so this asserts
// three things against synthetic fixtures written to a temp directory, plus one
// against the real migration set:
//
//   1. a redefinition that DROPS a property is flagged;
//   2. a redefinition that CARRIES the property forward is not (no false alarm);
//   3. a later literal ALTER that restores the pin resolves the strip;
//   4. F-J-01 is detected in the REAL tree with the exemption removed — which is
//      the demonstration that the recorded entry is a real finding this guard
//      found, not a hardcoded string.
//
// It writes only to `os.tmpdir()` and never touches supabase/migrations.
//
//   node supabase/tests/security/migration-durability-guard.mjs --self-test

function selfTest() {
  const { mkdtempSync, writeFileSync, rmSync } = require_fs();
  const { tmpdir } = require_os();
  const dir = mkdtempSync(join(tmpdir(), 'imig03-'));
  let failures = 0;
  const t = (name, pass, detail) => {
    console.log(`  ${pass ? 'PASS' : 'FAIL'}  ${name}${detail ? `  — ${detail}` : ''}`);
    if (!pass) failures++;
  };

  const guarded = (n) => `CREATE OR REPLACE FUNCTION public.f_${n}(p uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF NOT public.can_act_for(p) THEN RAISE EXCEPTION 'no' USING ERRCODE='42501'; END IF;
  RETURN public.f_${n}_engine(p);
END;
$$;`;

  console.log('\n── I-MIG-03 guard self-test ───────────────────────────────────────────');
  try {
    // 1 — a bare redefinition drops both the wrapper and the pin.
    writeFileSync(join(dir, '001_establish.sql'), guarded('a'));
    writeFileSync(join(dir, '002_strip.sql'),
      `CREATE OR REPLACE FUNCTION public.f_a(p uuid)\nRETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$\nBEGIN RETURN '{}'::jsonb; END;\n$$;`);
    let v = verdict(analyse(dir));
    const strippedProps = v.open.filter((s) => s.fn === 'f_a').map((s) => s.property).sort();
    t('a redefinition that drops a wrapper and a pin is flagged',
      strippedProps.join(',') === 'auth-wrapper,search-path-pin', strippedProps.join(',') || 'nothing flagged');
    t('an unrecorded strip is fatal', v.unrecorded.length === 2, `unrecorded=${v.unrecorded.length}`);

    // 2 — carrying both properties forward is not a strip.
    writeFileSync(join(dir, '002_strip.sql'), guarded('a'));
    v = verdict(analyse(dir));
    t('a redefinition that carries both properties forward is NOT flagged',
      v.open.length === 0, `open=${v.open.length}`);

    // 3 — a later literal ALTER resolves the pin strip.
    writeFileSync(join(dir, '002_strip.sql'),
      `CREATE OR REPLACE FUNCTION public.f_a(p uuid)\nRETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$\nBEGIN\n  IF NOT public.can_act_for(p) THEN RAISE EXCEPTION 'no'; END IF;\n  RETURN '{}'::jsonb;\nEND;\n$$;`);
    writeFileSync(join(dir, '003_repin.sql'),
      'ALTER FUNCTION public.f_a(uuid) SET search_path = public, pg_temp;');
    v = verdict(analyse(dir));
    t('a later literal ALTER ... SET search_path resolves the pin strip',
      v.open.length === 0 && v.strips.some((s) => s.property === 'search-path-pin' && s.resolution === 'restored'),
      `open=${v.open.length}`);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }

  // 4 — historical F-J-01 detection remains proven without requiring the
  // current migration chain to retain the already-remediated defect.
  //
  // Migration 116 established the authorization wrapper. Migration 119 then
  // reproduced the public function without that wrapper. This synthetic
  // historical chain proves I-MIG-03 still detects that exact regression.
  const historicalDir = mkdtempSync(join(tmpdir(), 'imig03-fj01-history-'));
  try {
    writeFileSync(join(historicalDir, '116_establish.sql'),
      `CREATE OR REPLACE FUNCTION public.materialize_program_week(p uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF NOT public.can_act_on_program(p) THEN RAISE EXCEPTION 'no'; END IF;
  RETURN public.materialize_program_week_engine(p);
END;
$$;`);

    writeFileSync(join(historicalDir, '119_regression.sql'),
      `CREATE OR REPLACE FUNCTION public.materialize_program_week(p uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN '{}'::jsonb;
END;
$$;`);

    const historical = analyse(historicalDir);
    const fj01 = historical.strips.find((s) =>
      s.fn === 'materialize_program_week'
      && s.property === 'auth-wrapper'
      && s.resolution === 'open');

    t('F-J-01 historical regression remains detectable',
      Boolean(fj01),
      fj01 ? `established ${fj01.establishedBy} → stripped ${fj01.strippedBy}` : 'not detected');

    t('F-J-01 historical regression is attributed to migration 119',
      fj01?.strippedBy === '119',
      `strippedBy=${fj01?.strippedBy}`);
  } finally {
    rmSync(historicalDir, { recursive: true, force: true });
  }

  // 5 — the current tree must contain no open F-J-01 strip.
  const current = analyse();
  const currentFj01 = current.strips.find((s) =>
    s.fn === 'materialize_program_week'
    && s.property === 'auth-wrapper'
    && s.resolution === 'open');

  t('F-J-01 is closed in the current migration chain',
    !currentFj01,
    currentFj01
      ? `still open: ${currentFj01.establishedBy} → ${currentFj01.strippedBy}`
      : 'no open authorization-wrapper strip');


  // ── prose cannot satisfy a property ────────────────────────────────────────
  //
  // Each case below was MEASURED to return `true` before sqlCode() existed, by
  // importing this module's own parseDefinitions. A false positive on a property
  // makes analyse() believe it is still present, so the strip is never recorded
  // and the regression passes silently — the F-J-01 class this guard is for.
  {
    const prose = [
      ['auth-wrapper satisfied by a line comment', 'auth-wrapper',
       `CREATE OR REPLACE FUNCTION public.p1(p uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  -- authorization is handled by public.can_act_for(p) in the wrapper
  PERFORM 1;
END; $$;`],
      ['auth-wrapper satisfied by a block comment', 'auth-wrapper',
       `CREATE OR REPLACE FUNCTION public.p2(p uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  /* was: public.is_active_coach_of(p) */
  PERFORM 1;
END; $$;`],
      ['auth-wrapper satisfied by a string literal', 'auth-wrapper',
       `CREATE OR REPLACE FUNCTION public.p3(p uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  RAISE NOTICE 'checked via require_content_editor()';
END; $$;`],
      ['security-definer satisfied by a header comment', 'security-definer',
       `CREATE OR REPLACE FUNCTION public.p4() RETURNS void
LANGUAGE plpgsql
-- intentionally no longer SECURITY DEFINER; the caller is trusted
AS $$ BEGIN END; $$;`],
      ['search-path-pin satisfied by a header comment', 'search-path-pin',
       `CREATE OR REPLACE FUNCTION public.p5() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
-- dropped the SET search_path = public, pg_temp pin deliberately
AS $$ BEGIN END; $$;`],
    ];
    for (const [label, property, sql] of prose) {
      const def = parseDefinitions(sql)[0];
      t(`prose does NOT satisfy: ${label}`,
        Boolean(def) && def.properties[property] === false,
        def ? `${property}=${def.properties[property]}` : 'no definition parsed');
    }

    // The converse: real code still satisfies each property. Without this the
    // five above could pass by breaking detection outright.
    const real = parseDefinitions(
      `CREATE OR REPLACE FUNCTION public.p6(p uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF NOT public.can_act_for(p) THEN RAISE EXCEPTION 'denied'; END IF;
END; $$;`)[0];
    t('real code still satisfies all three properties',
      Boolean(real) && real.properties['auth-wrapper']
        && real.properties['search-path-pin'] && real.properties['security-definer'],
      real ? JSON.stringify(real.properties) : 'no definition parsed');

    // A `--` inside a literal is not a comment, and a quote inside a comment
    // does not open a literal. Both would corrupt a two-pass stripper.
    const tricky = sqlCode("SELECT 'a--b', 1; -- it's fine\nSELECT 2;");
    t('a -- inside a literal does not start a comment, and a quote in a comment is inert',
      tricky.includes('SELECT 2;') && !tricky.includes('a--b'),
      JSON.stringify(tricky));

    // ── SQL forms that actually occur in supabase/migrations ──────────────
    //
    // Both of these were verified present in this tree before being closed:
    // 44 nested dollar-quoted blocks (`$q$`, `$j$`, `$f$`, `$ddl$`), and
    // identifiers carrying an apostrophe — `"Coach: read an ACTIVE client's
    // photos"`, `"Child's Pose"`. Each would have opened a phantom literal
    // that swallowed the rest of the body, losing a REAL predicate. The
    // failure was loud rather than silent (a strip gets recorded and the guard
    // fails), but a false alarm in an enforcing guard teaches overrides.
    const forms = parseDefinitions(
      `CREATE OR REPLACE FUNCTION public.form1(p uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  EXECUTE format($q$ SELECT 'it''s dynamic $q$);
  DROP POLICY IF EXISTS "Coach: read an ACTIVE client's photos" ON storage.objects;
  IF NOT public.can_act_for(p) THEN RAISE EXCEPTION 'denied'; END IF;
END; $$;`)[0];
    t('a nested dollar quote and an apostrophe-bearing identifier do not hide a real predicate',
      Boolean(forms) && forms.properties['auth-wrapper'] === true,
      forms ? `auth-wrapper=${forms.properties['auth-wrapper']}` : 'no definition parsed');

    // A dollar-quoted block IS a string, so a predicate named only inside one
    // is prose for this purpose — it is not a call in this function's body.
    const dynOnly = parseDefinitions(
      `CREATE OR REPLACE FUNCTION public.form2(p uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  EXECUTE format($q$ SELECT public.can_act_for($1) $q$);
END; $$;`)[0];
    t('a predicate only inside a dollar-quoted string does NOT satisfy the property',
      Boolean(dynOnly) && dynOnly.properties['auth-wrapper'] === false,
      dynOnly ? `auth-wrapper=${dynOnly.properties['auth-wrapper']}` : 'no definition parsed');

    // Doubled quotes are an escape, not a close.
    t("doubled '' does not terminate a literal early",
      sqlCode("SELECT 'it''s -- not a comment'; SELECT 9;").includes('SELECT 9;'),
      JSON.stringify(sqlCode("SELECT 'it''s -- not a comment'; SELECT 9;")));
  }

  console.log(`\n  self-test: ${failures === 0 ? 'ALL PASS' : `${failures} FAILED`}\n`);
  return failures;
}

// Lazy CJS-style requires, so the module's import graph stays fs-only for the
// normal path and the self-test's extra deps load only when it runs.
function require_fs() { return fsMod; }
function require_os() { return osMod; }
import * as fsMod from 'node:fs';
import * as osMod from 'node:os';

const invokedDirectly = process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1];
if (invokedDirectly) {
  const failed = process.argv.includes('--self-test') ? selfTest() : report();
  process.exit(failed ? 1 : 0);
}

export { selfTest };
export default report;
