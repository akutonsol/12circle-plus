#!/usr/bin/env node
// PreToolUse guard · refuse tool writes to the repository's authority files.
//
// ── WHAT THIS IS, AND WHAT IT IS NOT ────────────────────────────────────────
//
// This is a Claude Code PreToolUse hook. It sees tool calls that Claude Code
// routes through its tool layer and can refuse them. It is NOT an operating
// system or sandbox boundary:
//
//   COVERED      Write, Edit, MultiEdit, NotebookEdit, and any other tool whose
//                input carries its destination as a STRING — at any depth, in
//                arrays or objects, under any key name. An unrecognised tool is
//                not assumed safe: its input is scanned the same way.
//                This is NOT comprehensive interception of every possible future
//                tool or payload schema, and the claim must be stated exactly,
//                because an earlier wording here was broader than the code.
//
//                WHAT IS CHECKED. A destination that appears in the payload as a
//                single-line string of 1..4096 characters, NOT under a
//                content-bearing key, and whose leading components resolve
//                inside a protected root.
//
//                WHAT IS THEREFORE NOT SEEN — four cases, each measured:
//                  * a destination under a content-bearing key. All 23 names in
//                    CONTENT_KEYS exclude the string, `content` and `text` and
//                    `title` alike. This is the deliberate price of having no
//                    false positives on file bodies that quote a path.
//                  * a destination that is not plausibly one path: empty,
//                    multi-line, or over 4096 characters (see plausiblePath).
//                  * a destination EMBEDDED after non-protected leading text in
//                    the same string. `{"args":"--output supabase/migrations/x.sql"}`
//                    is allowed, because the string resolves as one path whose
//                    first component is `--output`. Scanning substrings instead
//                    would reintroduce the false positives the inverted rule
//                    exists to avoid, so this is accepted, not fixed.
//                  * a destination encoded, or derived at run time.
//
//                No known tool carries a destination in any of those shapes.
//   NOT COVERED  Bash. A shell command can write any file, and classifying
//                arbitrary shell is not something this script pretends to do.
//                `printf x > supabase/migrations/999.sql` is not stopped here.
//   NOT COVERED  Any other process on the machine, an editor, or git itself.
//
// So: this reduces the chance of an ACCIDENTAL authority-file edit through the
// normal tool path. It does not make such an edit impossible. Anyone claiming
// otherwise is overstating it.
//
// ── WHY THE EXCEPTION LIST LIVES IN A TRACKED FILE ──────────────────────────
//
// The task queue's `paths` field and `.skills-agent/decisions.json` are NOT
// accepted as proof of authorization: both are writable by the same agent whose
// writes this guard exists to check, so trusting them would be circular. The
// only exception mechanism is `scripts/protected-paths.json`, which is
// git-tracked — so lifting a protection is a visible, reviewable diff rather
// than a runtime assertion.
//
// ── CONTRACT ────────────────────────────────────────────────────────────────
// stdin: the hook payload as JSON. Blocking is exit 2 with the reason on
// stderr, which Claude Code surfaces to the model. (The documented alternative
// is exit 0 with hookSpecificOutput.permissionDecision = "deny"; only one is
// used here, deliberately, because a third-party source reports stdout JSON is
// ignored when the exit code is 2 and that interaction is not worth relying on.)
//   exit 0  allow
//   exit 2  deny, reason on stderr
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import os from 'node:os';
import { spawnSync } from 'node:child_process';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const CONFIG = path.join(ROOT, 'scripts', 'protected-paths.json');

// Tools that can modify a file through the tool layer.
const WRITE_TOOLS = new Set(['Write', 'Edit', 'MultiEdit', 'NotebookEdit']);
// Tools that cannot. Listed explicitly so an unknown tool is never assumed safe.
const READ_TOOLS = new Set(['Read', 'Grep', 'Glob', 'LS', 'NotebookRead', 'WebFetch', 'WebSearch', 'TodoWrite', 'Task']);
// Out of scope by design — see the header.
const UNENFORCEABLE = new Set(['Bash', 'BashOutput', 'KillShell']);

function deny(msg) { process.stderr.write(`BLOCKED by scripts/guard-protected-paths.mjs\n${msg}\n`); process.exit(2); }
function allow() { process.exit(0); }

function readConfig() {
  // Fail closed: without a readable config there is nothing to check against,
  // and silently allowing would defeat the guard.
  const raw = fs.readFileSync(CONFIG, 'utf8');
  const c = JSON.parse(raw);
  // The emptiness check is explicit because the obvious spelling does not cover
  // it: `[].some(...)` is false, so an EMPTY array satisfied the old condition
  // and the guard loaded a config that protects nothing — while this very error
  // message said "non-empty". Measured: `{"protected":[],"exceptions":[]}`
  // allowed a write to every one of the eleven roots, silently.
  //
  // An empty list is not how a protection is lifted. The documented mechanism is
  // `exceptions`, which narrows one path and leaves a reviewable diff, or
  // removing one root deliberately. A `protected` array that has become empty is
  // far more likely a truncated or half-edited file, so it fails closed.
  if (!Array.isArray(c.protected) || c.protected.length === 0
      || c.protected.some((p) => typeof p !== 'string' || !p)) {
    throw new Error('`protected` must be a non-empty array of non-empty strings');
  }
  const except = Array.isArray(c.exceptions) ? c.exceptions.filter((p) => typeof p === 'string' && p) : [];
  return { protected: c.protected, exceptions: except };
}

// Resolve a candidate the way the KERNEL does: component by component,
// resolving each symlink as it is reached, so `..` applies to the RESOLVED
// directory rather than to the spelling.
//
// `path.resolve` is wrong for this and it was a real bypass, caught by test G-3
// before this rewrite. With `.guardtest/mig` a symlink to `supabase/migrations`:
//
//   path.resolve('.guardtest/mig/../migrations/993.sql')
//     -> .guardtest/migrations/993.sql      (lexical `..`, looks harmless)
//   the kernel
//     -> supabase/migrations/993.sql        (`..` from the LINK TARGET)
//
// The guard allowed that write. It no longer does. A path component that does
// not exist yet is kept lexically, so a NEW file under a symlinked directory is
// still resolved through the link.
function canonical(p) {
  const abs = path.isAbsolute(p);
  let cur = abs ? path.sep : ROOT;
  try { cur = fs.realpathSync(cur); } catch { /* keep as-is */ }
  for (const comp of p.split(/[/\\]+/)) {
    if (comp === '' || comp === '.') continue;
    if (comp === '..') { cur = path.dirname(cur); continue; }
    const next = path.join(cur, comp);
    try { cur = fs.realpathSync(next); } catch { cur = next; }
  }
  return cur;
}

function within(child, parent) {
  const c = canonical(child); const p = canonical(parent);
  return c === p || c.startsWith(p + path.sep);
}

// Every path-shaped value anywhere in the tool input. Recursive on purpose: a
// multi-file operation must not slip through because only one of its targets is
// protected, and the shape of a future tool's input is not known here.
// ── HOW A WRITE DESTINATION IS IDENTIFIED, AND WHY THE RULE IS INVERTED ─────
//
// The first version kept an allow-list of path-shaped KEY NAMES and only looked
// at string values directly under them. An independent review reproduced six
// payloads that named a protected file and were ALLOWED:
//
//   {"paths":["supabase/migrations/x.sql"]}        array under a known key
//   {"file_path":["supabase/migrations/x.sql"]}    array under a known key
//   {"file_paths":[...]} / {"file_paths":"..."}    plural key, not on the list
//   {"outfile":"..."} / {"to":"..."}               key names nobody enumerated
//
// A key allow-list can only ever enumerate the shapes someone thought of, so the
// rule is now inverted:
//
//   EVERY string anywhere in the tool input is a candidate write destination,
//   EXCEPT strings under a known CONTENT-bearing key, and except strings that
//   cannot plausibly be one path. The DECISION is then made by resolution: a
//   candidate denies only if it resolves inside a protected root.
//
// That is conservative in the right direction. A false positive needs a string
// that literally resolves into `supabase/migrations/` or another protected root
// — prose like "see the migrations folder" resolves to ROOT/see the migrations
// folder and is ignored. A false NEGATIVE now requires a tool to carry its
// destination under a content key, which would be a strange design.
//
// The content exclusions exist so an ordinary write is not denied because its
// CONTENT quotes a protected path — `{"file_path":"notes.md","content":"see
// supabase/migrations/131_x.sql"}` must stay allowed. Anything not excluded is
// treated as a possible destination.
const CONTENT_KEYS = /^(content|contents|new_?string|old_?string|body|text|command|prompt|description|message|note|notes|summary|pattern|query|replacement|instructions|reason|caption|title|label)$/i;

// A string that could be one filesystem path. Multi-line text, empty strings and
// anything implausibly long are not; this keeps file bodies out of the scan
// without guessing at their meaning.
function plausiblePath(v) {
  return typeof v === 'string' && v.length > 0 && v.length <= 4096 && !/[\n\r\0]/.test(v);
}

// Every candidate destination in the input, at any depth, through arrays and
// objects alike. `underContent` is inherited so a nested object beneath a
// content key stays excluded.
function collectPaths(node, out = [], underContent = false) {
  if (node == null) return out;
  if (typeof node === 'string') { if (!underContent && plausiblePath(node)) out.push(node); return out; }
  if (Array.isArray(node)) { for (const v of node) collectPaths(v, out, underContent); return out; }
  if (typeof node !== 'object') return out;
  for (const [k, v] of Object.entries(node)) collectPaths(v, out, underContent || CONTENT_KEYS.test(k));
  return out;
}

// ── SELF-TEST ───────────────────────────────────────────────────────────────
//
// `node scripts/guard-protected-paths.mjs --self-test` (npm run guard:selftest).
//
// WHY IT SPAWNS ITSELF rather than calling the functions. The decision this
// guard makes is an EXIT CODE from a process fed JSON on stdin. Calling
// `collectPaths` directly would test the parts while leaving the actual
// contract — payload in, exit 2 out — unasserted, and the contract is where the
// six reproduced bypasses lived. So every case below runs the real script the
// way Claude Code runs it.
//
// The corpus is not invented. Each DENY case under "formerly permitted" is one
// of the six payload shapes an independent review reproduced as ALLOWED against
// the first version of this file. They are kept as assertions so that version
// can never come back silently.
function selfTest() {


  let pass = 0; const fails = [];

  // Run this very script, in a given ROOT, on a given payload. Exit 2 is deny.
  const verdict = (payload, script = fileURLToPath(import.meta.url)) => {
    const r = spawnSync(process.execPath, [script], {
      input: typeof payload === 'string' ? payload : JSON.stringify(payload),
      encoding: 'utf8',
    });
    if (r.status !== 0 && r.status !== 2) {
      return `CRASH(${r.status}) ${String(r.stderr).slice(0, 200)}`;
    }
    return r.status === 2 ? 'DENY' : 'ALLOW';
  };
  const check = (name, want, got) => {
    if (got === want) { pass++; return; }
    fails.push(`${name}: expected ${want}, got ${got}`);
  };
  const expect = (name, want, payload, script) => check(name, want, verdict(payload, script));

  const P = 'supabase/migrations/999_selftest_never_written.sql';

  // ── the six shapes an independent review reproduced as ALLOWED ────────────
  expect('formerly permitted: paths[]', 'DENY', { tool_name: 'Write', tool_input: { paths: [P] } });
  expect('formerly permitted: file_path[]', 'DENY', { tool_name: 'Write', tool_input: { file_path: [P] } });
  expect('formerly permitted: file_paths[]', 'DENY', { tool_name: 'Write', tool_input: { file_paths: [P] } });
  expect('formerly permitted: file_paths str', 'DENY', { tool_name: 'Write', tool_input: { file_paths: P } });
  expect('formerly permitted: outfile', 'DENY', { tool_name: 'Write', tool_input: { outfile: P } });
  expect('formerly permitted: to', 'DENY', { tool_name: 'Write', tool_input: { to: P } });

  // ── spellings of one destination that must all resolve the same ───────────
  expect('plain', 'DENY', { tool_name: 'Write', tool_input: { file_path: P } });
  expect('leading ./', 'DENY', { tool_name: 'Write', tool_input: { file_path: `./${P}` } });
  expect('absolute', 'DENY', { tool_name: 'Write', tool_input: { file_path: path.join(ROOT, P) } });
  expect('.. traversal', 'DENY', { tool_name: 'Write', tool_input: { file_path: `docs/../${P}` } });
  expect('double slash', 'DENY', { tool_name: 'Write', tool_input: { file_path: P.replace('/', '//') } });
  expect('trailing space', 'DENY', { tool_name: 'Write', tool_input: { file_path: `${P} ` } });
  expect('unenumerated key', 'DENY', { tool_name: 'Write', tool_input: { destination: P } });
  expect('nested 3 deep', 'DENY', { tool_name: 'Write', tool_input: { a: [{ b: [{ c: 'docs/decision-log.md' }] }] } });
  expect('unknown tool', 'DENY', { tool_name: 'FutureTool', tool_input: { whereToWriteIt: 'supabase/expected_applied.json' } });
  expect('the protected dir itself', 'DENY', { tool_name: 'Write', tool_input: { file_path: 'supabase/migrations' } });
  expect('MultiEdit, one of two protected', 'DENY',
    { tool_name: 'MultiEdit', tool_input: { edits: [{ file_path: 'docs/notes.md' }, { file_path: P }] } });

  // ── every EXPECTED root is enforced ───────────────────────────────────────
  // The list is written out here on purpose. An earlier version of this loop
  // iterated `readConfig().protected`, which made it self-referential: deleting
  // `docs/adr` from the config deleted its own assertion and the suite still
  // reported all-pass. Measured — 51 passed before the deletion, 50 passed
  // after, green both times. A protection can now only be removed by editing
  // this list too, in the same reviewable diff.
  const EXPECTED_ROOTS = [
    'supabase/migrations',
    'supabase/expected_applied.json',
    'docs/MASTER_PRODUCT_DECISIONS.md',
    'docs/decision-log.md',
    'docs/decisions',
    'docs/MASTER_REMEDIATION_REGISTRY.md',
    'docs/MASTER_REMEDIATION_WAVES.md',
    'docs/QA_CLOSURE_STANDARD.md',
    'docs/RELEASE_GATES.md',
    'docs/REMEDIATION_PROGRESS.md',
    'docs/adr',
  ];
  const configured = readConfig().protected;
  for (const root of EXPECTED_ROOTS) {
    const target = /\.(json|md)$/.test(root) ? root : `${root}/selftest_probe`;
    expect(`root enforced: ${root}`, 'DENY', { tool_name: 'Write', tool_input: { file_path: target } });
  }
  // And the config must not have QUIETLY GAINED one either: a root added
  // without being listed here is an unreviewed widening.
  const unexpected = configured.filter((r) => !EXPECTED_ROOTS.includes(r));
  check('config declares no unlisted root', 'none',
    unexpected.length ? `unlisted: ${unexpected.join(', ')}` : 'none');
  const missing = EXPECTED_ROOTS.filter((r) => !configured.includes(r));
  check('config still declares every expected root', 'none',
    missing.length ? `missing: ${missing.join(', ')}` : 'none');

  // ── the hook is actually WIRED, and wired to THIS file ────────────────────
  //
  // This is a fail-OPEN check, which is why it is here. Claude Code denies on
  // exit 2 and treats any other non-zero exit as an error, not a refusal.
  // Measured: `node /nonexistent/guard.mjs` exits **1**. So renaming or moving
  // this script, or deleting the hooks block, does not produce a denial — it
  // produces nothing, and every protected path becomes writable through the
  // tool layer with no signal that protection has stopped.
  //
  // The guard cannot verify that Claude Code loaded the hook. It can verify
  // that the configuration still names a file that exists and that the file is
  // this one, which is the part that rots.
  {
    const settings = path.join(ROOT, '.claude', 'settings.json');
    let conf = null;
    try { conf = JSON.parse(fs.readFileSync(settings, 'utf8')); }
    catch (e) { fails.push(`hook wiring: .claude/settings.json unreadable (${e.message})`); }
    if (conf) {
      const entries = Array.isArray(conf.hooks?.PreToolUse) ? conf.hooks.PreToolUse : [];
      const commands = entries.flatMap((e) => (Array.isArray(e.hooks) ? e.hooks : []))
        .map((h) => h && typeof h.command === 'string' ? h.command : '')
        .filter(Boolean);
      check('hook wiring: a PreToolUse hook is configured', true, commands.length > 0);

      const self = fileURLToPath(import.meta.url);
      // Resolve every path-shaped token in each command and look for this file.
      const resolved = commands.flatMap((cmd) =>
        cmd.split(/[\s"']+/).filter(Boolean).map((tok) => {
          const t = tok.replace(/^\$CLAUDE_PROJECT_DIR\//, '').replace(/^\$\{CLAUDE_PROJECT_DIR\}\//, '');
          try { return canonical(t); } catch { return null; }
        }).filter(Boolean));
      const existing = resolved.filter((p) => { try { return fs.statSync(p).isFile(); } catch { return false; } });
      check('hook wiring: the command names a file that exists', true, existing.length > 0);
      check('hook wiring: that file is THIS script', true, existing.some((p) => p === canonical(self)));
    }
  }

  // ── payloads that cannot be classified fail closed ────────────────────────
  expect('no tool named', 'DENY', { tool_name: '', tool_input: {} });
  expect('payload not JSON', 'DENY', 'not json at all');
  expect('payload not an object', 'DENY', '"a string"');

  // ── false positives: these are ordinary work and MUST be allowed ──────────
  // If any of these flips to DENY the guard has started blocking legitimate
  // writes, which is how a safety control gets switched off in practice.
  expect('FP content quotes a protected path', 'ALLOW',
    { tool_name: 'Write', tool_input: { file_path: 'notes.md', content: `see ${P}` } });
  expect('FP content IS a protected path', 'ALLOW',
    { tool_name: 'Write', tool_input: { file_path: 'notes.md', content: P } });
  expect('FP new_string names one', 'ALLOW',
    { tool_name: 'Edit', tool_input: { file_path: 'notes.md', old_string: 'a', new_string: P } });
  expect('FP ordinary source write', 'ALLOW',
    { tool_name: 'Write', tool_input: { file_path: 'apps/mobile/lib/main.dart', content: 'void main(){}' } });
  expect('FP read of a protected file', 'ALLOW', { tool_name: 'Read', tool_input: { file_path: P } });
  expect('FP prose mentioning migrations', 'ALLOW',
    { tool_name: 'Write', tool_input: { file_path: 'notes.md', content: 'see the migrations folder' } });

  // ── documented gaps. Asserted so they stay DOCUMENTED, not forgotten ──────
  // These are ALLOW on purpose. Each one is stated in the header. If a future
  // change closes one, this assertion fails and the header must be updated in
  // the same commit — which is the point.
  expect('documented gap: Bash', 'ALLOW',
    { tool_name: 'Bash', tool_input: { command: `printf x > ${P}` } });
  expect('documented gap: content-key destination', 'ALLOW',
    { tool_name: 'Write', tool_input: { content: P } });
  // These two are written so that REMOVING the carve-out flips them. An earlier
  // version used `a\n${P}` and `'a'.repeat(4097)`: neither resolves into a
  // protected root even when treated as a path, so deleting the newline test or
  // the length bound left the suite green. Measured both ways. The forms below
  // resolve INSIDE supabase/migrations the moment they are considered at all.
  expect('documented gap: multi-line string', 'ALLOW',
    { tool_name: 'Write', tool_input: { f: `${P}\ntrailing line` } });
  expect('documented gap: over 4096 chars', 'ALLOW',
    { tool_name: 'Write', tool_input: { f: `supabase/migrations/${'a'.repeat(4100)}.sql` } });
  expect('documented gap: embedded after prefix', 'ALLOW',
    { tool_name: 'Write', tool_input: { args: `--output ${P}` } });

  // ── the config fails closed ───────────────────────────────────────────────
  // Run a COPY of this script from a temp root so a broken config can be tested
  // without touching the repository's own.
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'guard-selftest-'));
  try {
    const dir = path.join(tmp, 'scripts');
    fs.mkdirSync(dir, { recursive: true });
    const copy = path.join(dir, 'guard.mjs');
    fs.copyFileSync(fileURLToPath(import.meta.url), copy);
    const cfgPath = path.join(dir, 'protected-paths.json');
    const ordinary = { tool_name: 'Write', tool_input: { file_path: 'docs/ordinary.md' } };

    // Premise check: with a GOOD config the copy must behave, or every
    // assertion below would pass for the wrong reason.
    fs.writeFileSync(cfgPath, JSON.stringify({ protected: ['supabase/migrations'], exceptions: [] }));
    expect('temp-root premise: good config denies a protected path', 'DENY',
      { tool_name: 'Write', tool_input: { file_path: P } }, copy);
    expect('temp-root premise: good config allows an ordinary path', 'ALLOW', ordinary, copy);

    fs.rmSync(cfgPath);
    expect('fail closed: config absent', 'DENY', ordinary, copy);
    fs.writeFileSync(cfgPath, '{ not json');
    expect('fail closed: config malformed', 'DENY', ordinary, copy);
    fs.writeFileSync(cfgPath, JSON.stringify({ exceptions: [] }));
    expect('fail closed: no `protected` key', 'DENY', ordinary, copy);
    fs.writeFileSync(cfgPath, JSON.stringify({ protected: 'nope', exceptions: [] }));
    expect('fail closed: `protected` not an array', 'DENY', ordinary, copy);
    fs.writeFileSync(cfgPath, JSON.stringify({ protected: [''], exceptions: [] }));
    expect('fail closed: `protected` holds an empty string', 'DENY', ordinary, copy);
    fs.writeFileSync(cfgPath, JSON.stringify({ protected: [], exceptions: [] }));
    expect('fail closed: `protected` is empty', 'DENY', ordinary, copy);

    // ── the G-3 symlink bypass, reproduced ─────────────────────────────────
    // This is the defect that made `within()` resolve component by component
    // instead of calling `path.resolve`. With `sandbox/mig` a symlink to
    // `supabase/migrations`, the path `sandbox/mig/../migrations/x.sql`
    // resolves two different ways:
    //
    //   lexically   sandbox/migrations/x.sql    not protected -> ALLOWED
    //   the kernel  supabase/migrations/x.sql   protected     -> DENIED
    //
    // The guard used to take the first answer and allow the write. Without
    // this case the suite cannot tell the two implementations apart: reverting
    // `within()` to `path.resolve` was measured to leave all other assertions
    // green. A symlink is needed to express it, which is why it lives in the
    // temp root and never in the repository.
    fs.writeFileSync(cfgPath, JSON.stringify({ protected: ['supabase/migrations'], exceptions: [] }));
    fs.mkdirSync(path.join(tmp, 'supabase', 'migrations'), { recursive: true });
    fs.mkdirSync(path.join(tmp, 'sandbox'), { recursive: true });
    let symlinked = true;
    try { fs.symlinkSync('../supabase/migrations', path.join(tmp, 'sandbox', 'mig'), 'dir'); }
    catch { symlinked = false; }
    // A filesystem without symlinks must not silently skip the case.
    check('symlink case is reachable', true, symlinked);
    if (symlinked) {
      expect('G-3: .. applies to the LINK TARGET, not the spelling', 'DENY',
        { tool_name: 'Write', tool_input: { file_path: 'sandbox/mig/../migrations/x.sql' } }, copy);
      // Premise: the lexical destination really is outside the protected root,
      // so the DENY above can only come from kernel-style resolution.
      expect('G-3 premise: the lexical destination is NOT protected', 'ALLOW',
        { tool_name: 'Write', tool_input: { file_path: 'sandbox/migrations/x.sql' } }, copy);
    }

    // The exception mechanism must still work, or lifting one protection would
    // be impossible and the only way out would be deleting the hook.
    fs.writeFileSync(cfgPath, JSON.stringify({
      protected: ['supabase/migrations'], exceptions: ['supabase/migrations/999_allowed.sql'] }));
    expect('exception lifts exactly one path', 'ALLOW',
      { tool_name: 'Write', tool_input: { file_path: 'supabase/migrations/999_allowed.sql' } }, copy);
    expect('exception does not lift its siblings', 'DENY',
      { tool_name: 'Write', tool_input: { file_path: 'supabase/migrations/998_other.sql' } }, copy);
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }

  if (fails.length) {
    process.stderr.write(`guard self-test: ${fails.length} FAILED of ${pass + fails.length}\n`);
    for (const f of fails) process.stderr.write(`  ${f}\n`);
    process.exit(1);
  }
  process.stdout.write(`guard self-test: ${pass} assertions passed\n`);
  process.exit(0);
}

if (process.argv[2] === '--self-test') selfTest();

let payloadRaw = '';
try { payloadRaw = fs.readFileSync(0, 'utf8'); } catch { payloadRaw = ''; }

let cfg;
try { cfg = readConfig(); }
catch (e) { deny(`the protected-path config could not be read (${e.message}). Failing closed: fix scripts/protected-paths.json.`); }

let payload;
try { payload = JSON.parse(payloadRaw); }
catch {
  // No parsable payload. Cannot classify, so cannot clear a write.
  deny('the hook payload was missing or not valid JSON, so this call could not be classified. Failing closed.');
}
if (!payload || typeof payload !== 'object') deny('the hook payload was not an object. Failing closed.');

// Tolerate naming variation across versions rather than assuming one spelling.
const tool = payload.tool_name ?? payload.toolName ?? payload.tool ?? null;
const input = payload.tool_input ?? payload.toolInput ?? payload.input ?? payload.parameters ?? {};

if (typeof tool !== 'string' || !tool) {
  deny('the payload named no tool, so the operation could not be classified. Failing closed.');
}
if (UNENFORCEABLE.has(tool)) allow();            // documented gap, not a silent one
if (READ_TOOLS.has(tool)) allow();

const candidates = collectPaths(input);
const hits = [];
for (const c of candidates) {
  let prot = null;
  try { prot = cfg.protected.find((p) => within(c, p)) ?? null; }
  catch (e) { deny(`path "${c}" could not be resolved (${e.message}), so it could not be cleared. Failing closed.`); }
  if (!prot) continue;
  if (cfg.exceptions.some((x) => within(c, x))) continue;   // tracked, reviewable
  hits.push({ target: c, root: prot });
}

if (hits.length === 0) {
  // A write tool with no protected target is ordinary development work.
  if (WRITE_TOOLS.has(tool)) allow();
  // An UNKNOWN tool with no path-shaped field: nothing to protect, so allow,
  // but only because no protected path is involved.
  allow();
}

const lines = hits.map((h) => `  ${path.relative(ROOT, h.target)}   (protected root: ${h.root})`);
deny(
  `${tool} would modify ${hits.length} protected path(s):\n${lines.join('\n')}\n\n`
  + 'These are the repository\'s authority files: the migration set and applied-state\n'
  + 'manifest, the governance decision records and logs, the remediation registry and\n'
  + 'wave authorization, and the accepted ADRs. A change here is a governance act.\n\n'
  + 'This guard does NOT accept the task queue\'s `paths` field or\n'
  + '.skills-agent/decisions.json as authorization: the same agent can write both, so\n'
  + 'trusting them would be circular.\n\n'
  + 'To proceed legitimately, a human adds the specific path to `exceptions` in\n'
  + 'scripts/protected-paths.json — a git-tracked change that shows up in review —\n'
  + 'or removes the hook from .claude/settings.json. Either is a visible diff.\n'
  + 'NOTE: this guard covers tool-layer writes only. A Bash command is outside it.');
