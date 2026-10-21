#!/usr/bin/env node
/**
 * Minimal durable Skills-Agent queue coordinator.
 *
 * This process schedules bounded tasks; it does not launch Claude Code by itself.
 * A runner adapter must consume "claim" output and submit structured completion
 * or blocker events. State is persisted atomically on disk. Keep this workspace
 * on durable storage for restart recovery.
 */
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const TASKS_PATH = path.join(ROOT, '.skills-agent', 'tasks.json');
const STATE_PATH = path.join(ROOT, '.skills-agent', 'state.json');
const LOCK_PATH = path.join(ROOT, '.skills-agent', '.state.lock');
const DECISIONS_PATH = path.join(ROOT, '.skills-agent', 'decisions.json');
const DEFAULT_LEASE_MS = 30 * 60 * 1000;
const MAX_RETRIES_DEFAULT = 3;

function fail(message) { console.error(`skills-agent: ${message}`); process.exitCode = 1; }
function readJson(file, fallback) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); }
  catch (e) { if (e.code === 'ENOENT') return fallback; throw e; }
}
function writeAtomic(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const tmp = `${file}.${process.pid}.${crypto.randomUUID()}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(value, null, 2) + '\n', { flag: 'wx' });
  fs.renameSync(tmp, file);
}
// Is the process holding the lock still running?
//
// `process.kill(pid, 0)` sends no signal and only tests reachability. EPERM
// means the process EXISTS but belongs to another user — alive, and not ours to
// disturb. Anything else means gone.
function holderAlive(pid) {
  if (!Number.isInteger(pid) || pid <= 0) return false;
  try { process.kill(pid, 0); return true; }
  catch (e) { return e.code === 'EPERM'; }
}

function withLock(fn) {
  fs.mkdirSync(path.dirname(LOCK_PATH), { recursive: true });
  let fd;
  try {
    fd = fs.openSync(LOCK_PATH, 'wx');
  } catch (e) {
    if (e.code !== 'EEXIST') throw e;
    // A STALE lock used to deadlock the queue permanently.
    //
    // The lock is released in a `finally`, which a SIGKILL, a power loss or an
    // OOM kill never runs. The file then survived its owner, and every later
    // command failed with "queue lock already held" forever — so a single crash
    // retired the queue. Demonstrated by planting a lock naming a dead pid:
    // the next claim was refused although nothing held it.
    //
    // The recovery is deliberately FAIL-CLOSED. The lock is reclaimed only when
    // its recorded holder is PROVABLY gone. If the pid is reachable — including
    // EPERM, another user's process — the original refusal stands untouched.
    // A recycled pid therefore reads as alive and keeps the lock, which is the
    // safe direction to be wrong in.
    const held = readJson(LOCK_PATH, null);
    const pid = held?.pid;
    if (holderAlive(pid)) {
      throw new Error(`queue lock already held by running pid ${pid}; do not bypass it`);
    }
    console.error(`skills-agent: reclaiming a stale queue lock left by pid ${pid ?? 'unknown'} `
      + `(no such process; held since ${held?.at ?? 'unknown'})`);
    try { fs.unlinkSync(LOCK_PATH); } catch (e2) { if (e2.code !== 'ENOENT') throw e2; }
    // Single retry. If this races another reclaimer, that one wins and we refuse.
    try { fd = fs.openSync(LOCK_PATH, 'wx'); }
    catch (e3) {
      if (e3.code === 'EEXIST') throw new Error('queue lock was re-taken while reclaiming it; retry');
      throw e3;
    }
  }
  try { fs.writeFileSync(fd, JSON.stringify({ pid: process.pid, at: new Date().toISOString() })); return fn(); }
  finally { fs.closeSync(fd); fs.unlinkSync(LOCK_PATH); }
}
let policy = {};
function loadTasks() {
  const data = readJson(TASKS_PATH, { version: 1, tasks: [] });
  policy = data.policy ?? {};
  if (data.version !== 1 || !Array.isArray(data.tasks)) throw new Error('tasks.json must be { version: 1, tasks: [] }');
  const ids = new Set();
  for (const t of data.tasks) {
    if (!t.id || typeof t.id !== 'string' || ids.has(t.id)) throw new Error(`missing or duplicate task id: ${t.id}`);
    ids.add(t.id);
    if (!Array.isArray(t.dependsOn) || !Array.isArray(t.paths) || !Array.isArray(t.acceptance)) throw new Error(`${t.id}: dependsOn, paths, acceptance must be arrays`);
    if (!t.role || !t.summary) throw new Error(`${t.id}: role and summary are required`);
    if (!Number.isInteger(t.maxRetries ?? MAX_RETRIES_DEFAULT) || (t.maxRetries ?? MAX_RETRIES_DEFAULT) < 0) throw new Error(`${t.id}: maxRetries must be a non-negative integer`);
  }
  for (const t of data.tasks) for (const dep of t.dependsOn) if (!ids.has(dep)) throw new Error(`${t.id}: unknown dependency ${dep}`);
  detectCycles(data.tasks);
  return data.tasks;
}
function detectCycles(tasks) {
  const byId = new Map(tasks.map(t => [t.id, t]));
  const visiting = new Set(), visited = new Set();
  function visit(id) {
    if (visiting.has(id)) throw new Error(`dependency cycle at ${id}`);
    if (visited.has(id)) return;
    visiting.add(id);
    for (const dep of byId.get(id).dependsOn) visit(dep);
    visiting.delete(id); visited.add(id);
  }
  for (const t of tasks) visit(t.id);
}
function loadState(tasks) {
  const state = readJson(STATE_PATH, { version: 1, updatedAt: new Date().toISOString(), tasks: {} });
  if (state.version !== 1 || !state.tasks || typeof state.tasks !== 'object') throw new Error('state.json has invalid shape');
  for (const t of tasks) state.tasks[t.id] ??= { status: 'READY', attempts: 0, history: [] };
  return state;
}
// A task that declares an unresolved blocker must not be sitting in a runnable
// status. `eligible()` vetoes it either way, so this is about the FILE not
// lying: READY is the `??=` default above, so a blocked task added to
// tasks.json without a state entry reads as runnable to any human or agent
// inspecting state.json. Three tasks were in exactly that condition
// (V5-W2A-001, V5-W2B-001, V5-W3B-001) and two of them are gated Wave 2B /
// 3B-1 work. Reported, not thrown: the queue's status field is operator-owned,
// and a hard failure here would block every unrelated command.
// Drift means a RECORDED status contradicts a declared blocker. A task with no
// entry on disk has not recorded anything — `loadState` supplied READY as a
// placeholder — so reporting it as drift told a fresh clone to "correct" 24
// statuses that nobody had ever set. Only ids actually present in state.json
// count, which is why the raw file is read here rather than the defaulted object.
function idsRecordedOnDisk() {
  try {
    const raw = JSON.parse(fs.readFileSync(STATE_PATH, 'utf8'));
    return new Set(Object.keys(raw?.tasks ?? {}));
  } catch { return new Set(); }
}

function blockerStatusDrift(tasks, state) {
  const runnable = new Set(['READY', 'RETRY_WAIT']);
  const onDisk = idsRecordedOnDisk();
  return tasks
    .filter((t) => (Array.isArray(t.blockers) ? t.blockers : []).length > 0)
    .filter((t) => onDisk.has(t.id))
    .filter((t) => runnable.has(state.tasks[t.id]?.status))
    .map((t) => ({ id: t.id, status: state.tasks[t.id].status,
      kinds: [...new Set(t.blockers.map((b) => b.kind))] }));
}
// ── IDENTITY ───────────────────────────────────────────────────────────────
// Identity is self-asserted: a worker sets SKILLS_AGENT_ID. That is a real
// limit of a local coordinator and is NOT pretended away — see
// `docs/AUTONOMOUS_TEAM_OPERATING_MODEL.md`. What the coordinator CAN do, and
// now does, is refuse to record the same identity as both author and reviewer.
//
// The `pid:` fallback is deliberately NOT allowed for verification. It made
// identity free: the same worker got a different "identity" simply by running
// the verify step from a new process, so separation could be defeated without
// even setting a variable.
function workerId() {
  const id = process.env.SKILLS_AGENT_ID;
  if (id && id.trim()) return id.trim();
  // NO pid fallback, for EITHER role.
  //
  // An earlier version required an explicit id only for verification, and that
  // was not enough — found by running a real cycle, not by the tests, which
  // always supplied one. If the IMPLEMENTER may stay anonymous it is recorded
  // as `pid:1234`, which never equals a named verifier, so the independence
  // check passes trivially. Separation was defeatable by omission: the
  // implementer simply does not set a variable.
  //
  // Identity is the whole basis of the author/reviewer split, so a claim
  // without one is refused outright rather than invented.
  throw new Error(
    'SKILLS_AGENT_ID must be set to claim work. It is not defaulted: an anonymous '
    + 'implementer would be recorded under its pid, never match a named verifier, '
    + 'and defeat implementer/verifier separation by omission.');
}
// ── IDENTITY ATTESTATION ───────────────────────────────────────────────────
// The hole this addresses, demonstrated rather than assumed: an implementer
// that renames itself obtains the verification lease. Token replay, an
// undeclared role, and a third party reusing somebody else's lease are all
// already refused — renaming is the one attack that works, because identity is
// whatever the worker says it is.
//
// That cannot be closed by the coordinator alone: both roles run in the same
// shell, so any secret the coordinator checks is a secret the worker can read.
// What IS in scope is making the PROVENANCE of an identity claim part of the
// record, and providing the enforcement switch a real runner will need.
//
//   SKILLS_AGENT_ATTESTATION_KEY   held by the RUNNER, never by the worker
//   SKILLS_AGENT_IDENTITY_TOKEN    HMAC-SHA256(`${taskId}:${role}:${identity}`)
//                                  minted by the runner, passed to the worker
//
// With no key configured, identity is recorded `self-asserted` and nothing is
// refused — today's behaviour, now visible in the evidence instead of only in
// prose. With a key, the token must verify, and the trust level is `attested`.
// `policy.requireAttestedIdentity` makes an unattested verification a refusal.
//
// NOTE, and it is the whole point: while the runner and the worker are the same
// process tree, this is a CONTRACT, not an enforced boundary. It becomes a real
// boundary only when the key lives somewhere the worker cannot read. That is
// stated here so no later reader mistakes the field for proof.
function identityTrust(taskId, role, identity) {
  const key = process.env.SKILLS_AGENT_ATTESTATION_KEY;
  const token = process.env.SKILLS_AGENT_IDENTITY_TOKEN;
  if (!key) return { level: 'self-asserted', attested: false };
  if (!token) throw new Error(
    'SKILLS_AGENT_ATTESTATION_KEY is configured, so an identity token is required. '
    + 'The runner mints it; a worker cannot.');
  const expected = crypto.createHmac('sha256', key)
    .update(`${taskId}:${role}:${identity}`).digest('hex');
  const a = Buffer.from(expected, 'utf8');
  const b = Buffer.from(String(token), 'utf8');
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
    throw new Error(`identity attestation failed for "${identity}" as ${role} on ${taskId}`);
  }
  return { level: 'attested', attested: true };
}

function assertIndependentVerifier(taskState, verifierId) {
  const author = taskState.implementedBy ?? taskState.claimedBy;
  if (author && author === verifierId) {
    throw new Error(
      `independent verification required: "${verifierId}" implemented this task and `
      + `cannot also verify it. Setting SKILLS_AGENT_ROLE=verifier does not make a `
      + `worker independent of its own work.`);
  }
}

const terminal = new Set(['VERIFIED', 'FAILED_TERMINAL']);
const blocked = new Set(['BLOCKED_OWNER', 'BLOCKED_EXTERNAL', 'BLOCKED_GOVERNANCE']);
function depsVerified(task, state) { return task.dependsOn.every(id => state.tasks[id]?.status === 'VERIFIED'); }
// A declared blocker is, by this schema, an UNRESOLVED one: a blocker object is
// {kind, what, evidence, action} and carries no "resolved" flag, so the way a
// blocker goes away is that it is removed from the task. Until this check
// existed, `blockers` was a field the coordinator never read -- every one of the
// sixteen blocked tasks was held back only by a hand-set status in state.json.
// `:115` defaults a task with no state record to READY, so a blocked task added
// to tasks.json without a matching state entry, or any task whose status was
// reset, became eligible the moment its dependencies verified -- with its own
// declared owner/governance/external blocker sitting there unread. That is how a
// gated Wave 2B or 3B-1 task could have been claimed by a worker.
// The ONLY decision state that releases a gated task. Named once so the gate
// and its self-tests cannot drift apart.
const AUTHORIZING_STATE = 'implementation_authorized';

// AUDIT F1. `JSON.parse` keeps the LAST of two identical keys and discards the
// first, silently. Measured before this check existed:
//
//   {"OD-QAX-2":{"state":"proposed"},"OD-QAX-2":{"state":"implementation_authorized"}}
//
// parsed to the authorizing state and RELEASED the gate. A duplicate entry is a
// plausible merge artifact, so a careless edit could authorize a policy change
// nobody made. `check-migration-manifest.mjs` carries a dedicated rule for
// exactly this hazard on its own declaration file; the ledger had none.
//
// Any id appearing more than once in the RAW text is treated as unreadable and
// its gate is not released. Counted on raw text because the parsed object can no
// longer show what was lost.
function duplicateDecisionIds(raw, ids) {
  const dupes = [];
  for (const id of ids) {
    const esc = id.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const re = new RegExp('"' + esc + '"\\s*:', 'g');
    if ((raw.match(re) ?? []).length > 1) dupes.push(id);
  }
  return dupes;
}

function readDecisions() {
  let raw;
  try { raw = fs.readFileSync(DECISIONS_PATH, 'utf8'); }
  catch (e) { if (e.code === 'ENOENT') return {}; throw e; }
  const d = JSON.parse(raw);
  const map = (d && typeof d === 'object' && d.decisions && typeof d.decisions === 'object') ? d.decisions : {};
  const dupes = duplicateDecisionIds(raw, Object.keys(map));
  if (dupes.length === 0) return map;
  console.error(`skills-agent: decisions.json has duplicate id(s) ${dupes.join(', ')} — `
    + 'JSON keeps only the last. Those gates stay CLOSED until the duplication is removed.');
  const safe = { ...map };
  for (const id of dupes) delete safe[id];
  return safe;
}

// Blockers that still veto, after resolving any that name a decision.
//
// WHY THIS EXISTS. `blockers` was free-text prose — `{kind:'owner', what:'an
// undecided product contract'}` — with no link to a decision record and no way
// to clear itself. When an owner finally answered, a human had to remember to
// delete the right entry from the right task. 16 of 19 live tasks carry one, so
// that is 16 chances to forget in either direction: leaving a gate up after the
// answer stalls real work, and taking one down early implements an unmade
// decision. A blocker may now carry `decision: "<id>"`, and the gate is data.
//
// FAIL-CLOSED, deliberately. A decision id that is absent from the ledger, or a
// ledger that is missing or unreadable, KEEPS the veto. A typo in a decision id
// must never be the thing that authorizes a policy change. `decisions` is passed
// in so callers can inject a ledger; omitted, it is read from disk.
function declaredBlockers(task, decisions) {
  const all = Array.isArray(task.blockers) ? task.blockers : [];
  if (!all.some((b) => b && b.decision)) return all;
  const ledger = decisions ?? readDecisions();
  return all.filter((b) => {
    if (!b || !b.decision) return true;                       // ordinary blocker
    const d = ledger[b.decision];
    if (!d || typeof d.state !== 'string') return true;        // unknown -> veto
    if (d.state !== AUTHORIZING_STATE) return true;            // only this clears
    return authorizationIsIncomplete(d) !== null;              // ...and only when complete
  });
}

// A structural completeness check on an authorizing entry. NOT a proof of
// provenance, and the difference matters.
//
// WHAT THIS CANNOT DO. There is no machine-checkable link from an `OD-*` id to
// an authoritative record in this repository, verified rather than assumed:
// `MASTER_PRODUCT_DECISIONS.md` carries 7 `ANSWERED` markers but NO row for
// OD-QAX-2 or OD-14; `decision-log.md` embeds the id in prose; and
// `docs/adr/ADR-W1-001` has a machine-readable Status line but mentions no
// `OD-*` id anywhere. Matching prose would manufacture confidence, so no such
// check is attempted. CR-1 remains open and this is why.
//
// WHAT IT DOES. An entry may only authorize if it also DECLARES an owner, a
// date, and a record path that EXISTS on disk. That raises the bar from editing
// one word to asserting four things, one of which is a real file. It does not
// verify the file says what the entry claims — a reviewer still must read it.
function authorizationIsIncomplete(d) {
  const missing = ['owner', 'answeredAt', 'record'].filter(
    (k) => typeof d[k] !== 'string' || !d[k].trim());
  if (missing.length) return `declares ${AUTHORIZING_STATE} but has no ${missing.join(', ')}`;
  const rec = path.isAbsolute(d.record) ? d.record : path.join(ROOT, d.record);
  // `existsSync` was too weak: an independent review showed a DIRECTORY and an
  // EMPTY file both satisfied it, so `record: "docs"` authorized. A record must
  // be a real, non-empty regular file. This still does NOT read the file or
  // check that its contents support the entry — CR-1 — but it rules out the two
  // shapes that obviously cannot be a record.
  let st;
  try { st = fs.statSync(rec); }
  catch { return `names record "${d.record}", which does not exist`; }
  if (st.isDirectory()) return `names record "${d.record}", which is a directory, not a record`;
  if (!st.isFile()) return `names record "${d.record}", which is not a regular file`;
  if (st.size === 0) return `names record "${d.record}", which is empty`;
  return null;
}
// `paths` was the SECOND declared field the coordinator validated and then
// never used (`:92` checks it is an array; nothing read it). Demonstrated:
// two tasks both declaring `lib/shared/thing.dart` were handed to w1 and w2
// and BOTH held live leases, so two workers would edit one file concurrently.
// Leases protect a task from double-claim; nothing protected a FILE.
//
// Overlap is prefix-aware because the real queue mixes directories and files
// (`.skills-agent/` and `docs/V5_PROGRAMME_DEFINITION.md`), so `.skills-agent`
// must conflict with `.skills-agent/tasks.json` while `docs/A.md` and
// `docs/B.md` must not.
function normPath(p) {
  return String(p).trim().replace(/^\.\/+/, '').replace(/\/+$/, '').replace(/\/{2,}/g, '/');
}
function pathsOverlap(a, b) {
  const x = normPath(a); const y = normPath(b);
  if (!x || !y) return false;
  return x === y || x.startsWith(`${y}/`) || y.startsWith(`${x}/`);
}
// Only an implementer lease reserves files. A verifier reviews, and its
// independence is already enforced separately.
function heldPaths(tasks, state) {
  const out = [];
  for (const t of tasks) {
    const s = state.tasks[t.id];
    if (!s || !s.leaseToken) continue;
    if (!['CLAIMED', 'IMPLEMENTED'].includes(s.status)) continue;
    for (const p of (Array.isArray(t.paths) ? t.paths : [])) out.push({ id: t.id, path: p });
  }
  return out;
}
// `policy.maxConcurrentTasks` was the THIRD declared field nothing read.
// Demonstrated: with the policy set to 3, six workers took six live leases.
// Counted over implementer leases only -- a verification lease is review, not
// edit, and is already serialised by the independent-verifier rules. An unset
// or non-positive value means "no limit", preserving prior behaviour.
function concurrencyLimitReached(tasks, state) {
  const limit = Number(policy.maxConcurrentTasks);
  if (!Number.isFinite(limit) || limit <= 0) return false;
  const live = tasks.filter((t) => {
    const st = state.tasks[t.id];
    return st && st.leaseToken && ['CLAIMED', 'IMPLEMENTED'].includes(st.status);
  }).length;
  return live >= limit;
}
function pathConflict(task, tasks, state) {
  const held = heldPaths(tasks, state).filter((h) => h.id !== task.id);
  for (const p of (Array.isArray(task.paths) ? task.paths : [])) {
    const hit = held.find((h) => pathsOverlap(p, h.path));
    if (hit) return { path: p, heldBy: hit.id, heldPath: hit.path };
  }
  return null;
}
// Why `block` may refuse. Extracted so the self-test asserts the RULE rather
// than trusting that the CLI path happens to apply it.
function blockRefusalReason(task, s, unresolved) {
  if (!unresolved || unresolved.length === 0) {
    return 'declares no unresolved blocker, so it cannot be recorded as blocked. '
      + 'Add the blocker to tasks.json with its evidence and required action first — '
      + 'this command records a veto that already exists, it does not create one.';
  }
  if (s && (s.status === 'CLAIMED' || s.status === 'VERIFYING')) {
    return `holds a live lease (${s.status}). Let it expire or fail it first; `
      + 'blocking a task out from under a worker would lose its attempt record.';
  }
  return null;
}

// ── THE ADMISSION RULE ──────────────────────────────────────────────────────
//
// WHY IT EXISTS. An audit of this repository on 2026-10-21 measured where the
// autonomous workflow's output actually went. The committed window was mostly
// product-adjacent, but the uncommitted work was **4,425 lines, 0 of them
// product**: 47.5% agent infrastructure, 52.5% governance documentation. Zero
// lines of `apps/mobile/lib` changed across the whole workflow, and all 17
// VERIFIED tasks were infrastructure or governance.
//
// The cause was structural, not a lapse of judgment: every product task in the
// queue was blocked behind an owner decision, while every infrastructure and
// documentation task was self-authorizable. The system did the work it was
// permitted to do, and that work was about itself.
//
// So permission is no longer enough. While product work is available, that is
// what gets handed out. Infrastructure earns its turn by unblocking product
// work, not by being the only thing that is claimable.
const PRODUCT_PATH = /^(apps\/mobile\/(lib|test)\/|supabase\/(migrations|tests)\/)/;

// A task is PRODUCT if any declared path lands in the application or its tests.
// A task with no declared paths is not product: it cannot change the product.
function isProductTask(task) {
  return (Array.isArray(task.paths) ? task.paths : []).some((p) => PRODUCT_PATH.test(p));
}

// A fresh clone has no state.json — it is gitignored — so `loadState` defaults
// every task to READY. Measured on a simulated clone of this queue: 38 tasks all
// reported READY, 29 of which their own declared blockers veto, and `validate`
// listed 24 drift entries. The status field was the single most misleading thing
// a new environment saw.
//
// WHY THIS IS REPORTING ONLY, AND NOT A STORED STATUS. `eligible()` requires the
// status to be READY or RETRY_WAIT. Writing a derived BLOCKED_* into the state
// would therefore make the task uneligible FOREVER — including after its blocker
// is resolved, when it must become claimable again. That was measured before this
// was written, and it is why nothing here touches stored state or `eligible()`.
// The stored default stays READY; only what is REPORTED changes.
//
// Precedence is governance > external > everything else, because a governance
// prohibition is the strongest statement about why work cannot proceed. A
// `decision:` blocker derives BLOCKED_OWNER: an unmade owner decision is what it
// is waiting for.
function derivedBlockedStatus(task, decisions) {
  const unresolved = declaredBlockers(task, decisions);
  if (unresolved.length === 0) return null;
  const kinds = new Set(unresolved.map((b) => b.decision ? 'owner' : b.kind));
  if (kinds.has('governance')) return 'BLOCKED_GOVERNANCE';
  if (kinds.has('external')) return 'BLOCKED_EXTERNAL';
  return 'BLOCKED_OWNER';
}

function eligible(task, state, decisions) {
  const s = state.tasks[task.id];
  if (declaredBlockers(task, decisions).length > 0) return false;
  return ['READY', 'RETRY_WAIT'].includes(s.status) && depsVerified(task, state) && (s.retryAt == null || Date.parse(s.retryAt) <= Date.now());
}
function recoverExpired(tasks, state) {
  const now = Date.now(); let changed = false;
  for (const t of tasks) {
    const s = state.tasks[t.id];
    const verifyingExpired = s.status === 'VERIFYING' && s.verificationLeaseExpiresAt && Date.parse(s.verificationLeaseExpiresAt) <= now;
    const implementationExpired = ['CLAIMED', 'IMPLEMENTED'].includes(s.status) && s.leaseExpiresAt && Date.parse(s.leaseExpiresAt) <= now;
    if (verifyingExpired) {
      s.status = 'IMPLEMENTED';
      s.verificationLeaseToken = null; s.verificationLeaseExpiresAt = null; s.verifier = null;
      s.history.push({ at: new Date().toISOString(), event: 'VERIFICATION_LEASE_EXPIRED', note: 'Returned to independent verification without assuming task success.' });
      changed = true;
    } else if (implementationExpired) {
      s.status = 'RETRY_WAIT';
      s.lastFailure = 'LEASE_EXPIRED';
      s.leaseToken = null; s.leaseExpiresAt = null;
      s.history.push({ at: new Date().toISOString(), event: 'LEASE_EXPIRED', note: 'Recovered without assuming task success.' });
      changed = true;
    }
  }
  return changed;
}
function snapshot(tasks, state) {
  return tasks.map(t => {
    const s = state.tasks[t.id];
    // A RECORDED status always wins: it is what a worker or the `block` command
    // actually asserted. Derivation only fills the placeholder.
    const derived = s.status === 'READY' ? derivedBlockedStatus(t) : null;
    return { id: t.id, summary: t.summary, role: t.role,
      status: derived ?? s.status,
      statusSource: derived ? 'derived-from-blockers' : 'recorded',
      dependsOn: t.dependsOn, eligible: eligible(t, state), attempts: s.attempts,
      blocker: s.blocker ?? null };
  });
}
function main() {
  const [command, ...args] = process.argv.slice(2);
  if (command === '--self-test') return selfTest();
  const tasks = loadTasks();
  if (command === 'validate') {
    const drift = blockerStatusDrift(tasks, loadState(tasks));
        // AUDIT F3. validate reported `valid: true` with a garbage ledger, so the
    // one command an operator runs for queue health said nothing about the data
    // source the gate depends on. Reported separately: a broken ledger does not
    // make the QUEUE invalid, but it must not read as healthy either.
    let ledger = { readable: true, decisions: 0, duplicates: [], note: null };
    try {
      const raw = fs.readFileSync(DECISIONS_PATH, 'utf8');
      const parsed = JSON.parse(raw);
      const map = (parsed && typeof parsed === 'object' && parsed.decisions && typeof parsed.decisions === 'object') ? parsed.decisions : null;
      if (!map) { ledger = { readable: false, decisions: 0, duplicates: [], note: 'no usable `decisions` object; every decision gate stays CLOSED' }; }
      else {
        const dupes = duplicateDecisionIds(raw, Object.keys(map));
        const bad = Object.entries(map).filter(([, v]) => !v || typeof v.state !== 'string').map(([k]) => k);
        ledger = { readable: true, decisions: Object.keys(map).length, duplicates: dupes,
          malformed: bad, authorized: Object.entries(map).filter(([, v]) => v && v.state === AUTHORIZING_STATE).map(([k]) => k),
          note: (dupes.length || bad.length) ? 'entries listed above keep their gates CLOSED' : null };
      }
    } catch (e) {
      ledger = { readable: false, decisions: 0, duplicates: [],
        note: e.code === 'ENOENT' ? 'no decisions.json; every decision gate stays CLOSED' : `unreadable: ${e.message}` };
    }
    console.log(JSON.stringify({ valid: true, taskCount: tasks.length,
      blockerStatusDrift: drift, decisionLedger: ledger }, null, 2));
    if (!ledger.readable || (ledger.duplicates ?? []).length || (ledger.malformed ?? []).length) {
      console.error(`WARNING — the decision ledger is not healthy: ${ledger.note ?? ''}`
        + ((ledger.duplicates ?? []).length ? ` duplicates=[${ledger.duplicates.join(',')}]` : '')
        + ((ledger.malformed ?? []).length ? ` malformed=[${ledger.malformed.join(',')}]` : ''));
      console.error('Gates naming those ids stay CLOSED. The queue itself is still valid.');
    }
    if (drift.length) {
      console.error(`WARNING — ${drift.length} task(s) declare an unresolved blocker but sit in a runnable status:`);
      for (const d of drift) console.error(`  ${d.id}  status=${d.status}  blockerKinds=[${d.kinds.join(',')}]`);
      console.error('eligible() vetoes them regardless; the status field is misleading and should be corrected.');
    }
    return;
  }
  if (command === 'status') {
    const state = loadState(tasks); const changed = recoverExpired(tasks, state);
    if (changed) writeAtomic(STATE_PATH, state);
    const snap = snapshot(tasks, state);
    const counts = {};
    for (const t of snap) counts[t.status] = (counts[t.status] ?? 0) + 1;
    const derived = snap.filter((t) => t.statusSource === 'derived-from-blockers').length;
    console.log(JSON.stringify({ tasks: snap, counts,
      derivedStatuses: derived,
      derivedStatusNote: derived
        ? 'statuses marked derived-from-blockers are computed from tasks.json because no state entry exists (state.json is gitignored); they are not recorded completions'
        : null }, null, 2)); return;
  }
  if (command === 'claim') {
    const role = args[0];
    if (!role) throw new Error('usage: claim <role> [lease-minutes]');
    const leaseMs = Math.max(1, Number(args[1] ?? 30)) * 60 * 1000;
    const claimed = withLock(() => {
      const state = loadState(tasks); recoverExpired(tasks, state);
      const isVerifier = role === 'verifier';
      const task = isVerifier
        ? tasks.find(t => state.tasks[t.id]?.status === 'IMPLEMENTED' && !state.tasks[t.id]?.verificationLeaseToken && depsVerified(t, state))
        : concurrencyLimitReached(tasks, state)
          ? undefined
          : (() => {
            const claimable = tasks.filter(t => t.role === role && eligible(t, state) && !pathConflict(t, tasks, state));
            // Product first, always — and if this role has no product task but
            // ANOTHER role does, hand out nothing rather than letting
            // infrastructure proceed while product work waits for a worker.
            const mine = claimable.find(isProductTask);
            if (mine) return mine;
            const productWaitingElsewhere = tasks.some(t => isProductTask(t)
              && eligible(t, state) && !pathConflict(t, tasks, state));
            if (productWaitingElsewhere) return undefined;
            return claimable[0];
          })();
      if (!task) { writeAtomic(STATE_PATH, state); return null; }
      const s = state.tasks[task.id]; const token = crypto.randomUUID();
      if (isVerifier) {
        const vid = workerId();
        assertIndependentVerifier(s, vid);
        const trust = identityTrust(task.id, 'verifier', vid);
        if (policy.requireAttestedIdentity && !trust.attested) {
          throw new Error(
            'policy.requireAttestedIdentity is set: verification needs a runner-minted '
            + 'identity token, not a self-asserted SKILLS_AGENT_ID.');
        }
        s.verifierIdentityTrust = trust.level;
        s.status = 'VERIFYING'; s.verificationLeaseToken = token;
        s.leaseToken = null; s.leaseExpiresAt = null;
        s.verifier = vid;
        s.verificationLeaseExpiresAt = new Date(Date.now() + leaseMs).toISOString();
      } else {
        s.status = 'CLAIMED'; s.attempts += 1; s.leaseToken = token;
        // Recorded at CLAIM, so it survives the implementer's exit and is the
        // value the independence check compares against later.
        s.implementedBy = workerId();
        s.implementerIdentityTrust = identityTrust(task.id, role, s.implementedBy).level;
      }
      s.leaseExpiresAt = new Date(Date.now() + leaseMs).toISOString();
      if (!isVerifier) s.claimedBy = workerId();
      s.history.push({ at: new Date().toISOString(), event: isVerifier ? 'VERIFICATION_CLAIMED' : 'CLAIMED', worker: isVerifier ? s.verifier : s.claimedBy, attempt: s.attempts });
      state.updatedAt = new Date().toISOString(); writeAtomic(STATE_PATH, state);
      return { task, token, leaseExpiresAt: isVerifier ? s.verificationLeaseExpiresAt : s.leaseExpiresAt, assignment: isVerifier ? 'independent-verification' : 'implementation' };
    });
    if (!claimed) {
      const state = loadState(tasks);
      const productWaiting = tasks.filter(t => isProductTask(t) && eligible(t, state)).map(t => t.id);
      console.log(JSON.stringify(productWaiting.length
        ? { claimed: false, reason: 'PRODUCT_WORK_HAS_PRIORITY', role, productWaiting,
            note: 'Infrastructure and documentation tasks are withheld while product work is eligible. '
              + 'Claim one of the tasks above with its role, or state why it cannot proceed.' }
        : { claimed: false, reason: 'NO_ELIGIBLE_TASK_FOR_ROLE', role }, null, 2));
      return;
    }
    console.log(JSON.stringify(claimed, null, 2)); return;
  }
  if (command === 'event') {
    const [id, token, event, ...rest] = args;
    if (!id || !token || !event) throw new Error('usage: event <task-id> <lease-token> <implemented|verified|retry|blocked-owner|blocked-external|blocked-governance|failed> [note]');
    const note = rest.join(' ');
    const result = withLock(() => {
      const state = loadState(tasks); const task = tasks.find(t => t.id === id);
      if (!task) throw new Error(`unknown task ${id}`);
      const s = state.tasks[id];
      const isVerifierEvent = event === 'verified' || event === 'retry' && process.env.SKILLS_AGENT_ROLE === 'verifier';
      const validToken = isVerifierEvent ? s.verificationLeaseToken === token : s.leaseToken === token;
      if (!validToken) throw new Error('lease token mismatch; stale worker cannot change task state');
      if (event === 'implemented' && (s.status !== 'CLAIMED' || process.env.SKILLS_AGENT_ROLE === 'verifier')) throw new Error('only the assigned implementer may mark a CLAIMED task IMPLEMENTED');
      if (event === 'verified' && (s.status !== 'VERIFYING' || process.env.SKILLS_AGENT_ROLE !== 'verifier')) throw new Error('only the independently claimed verifier may verify an IMPLEMENTED task');
      const now = new Date().toISOString();
      const map = { implemented: 'IMPLEMENTED', verified: 'VERIFIED', retry: 'RETRY_WAIT',
        'blocked-owner': 'BLOCKED_OWNER', 'blocked-external': 'BLOCKED_EXTERNAL',
        'blocked-governance': 'BLOCKED_GOVERNANCE', failed: 'FAILED_TERMINAL' };
      if (!map[event]) throw new Error(`unsupported event ${event}`);
      // AUDIT F4. The gate used to be evaluated only at CLAIM. Measured: a task
      // claimed while its decision read `implementation_authorized` went on to
      // IMPLEMENTED and then VERIFIED after the ledger was reverted to
      // `proposed`. Authorization withdrawn, the change landed anyway, and the
      // queue recorded it as verified — a held lease outlived its authority.
      //
      // Re-checked here, where the status actually advances. Only ADVANCING
      // events are gated: retry, blocked-* and failed must stay available, or a
      // withdrawn authorization would trap the task with no way to record it.
      if (event === 'implemented' || event === 'verified') {
        const stillBlocked = declaredBlockers(task);
        if (stillBlocked.length > 0) {
          const gating = stillBlocked.filter((b) => b && b.decision).map((b) => b.decision);
          throw new Error(
            `authorization is no longer satisfied for ${id}; refusing to advance to ${map[event]}.`
            + (gating.length ? ` Gating decision(s) not in ${AUTHORIZING_STATE}: ${gating.join(', ')}.` : '')
            + ' Use retry or blocked-owner to record the situation instead.');
        }
      }
      if (event === 'verified' && process.env.SKILLS_AGENT_ROLE !== 'verifier') throw new Error('only an independently assigned verifier may mark a task VERIFIED');
      if (event === 'verified') {
        // Re-checked HERE as well as at claim: the lease could have been taken
        // before this guard existed, or the environment could differ between
        // the two calls. The event is where the status actually changes.
        const vid = workerId();
        assertIndependentVerifier(s, vid);
        if (s.verifier && s.verifier !== vid) {
          throw new Error(`verification lease belongs to "${s.verifier}", not "${vid}"`);
        }
      }
      if (event === 'verified' && (!note || !/https?:\/\/|^artifact:|^ci:|^commit:/i.test(note))) throw new Error('verified requires an evidence reference (URL, artifact:, ci:, or commit:)');
      // The check above accepts ANY of the four reference kinds for ANY task,
      // so a task whose own `evidenceRequired` says `commit:` could be verified
      // with a bare URL. Where the task declares a machine-checkable kind,
      // require THAT kind. Seven of nineteen tasks declare `commit:`; the other
      // twelve declare prose ("a recorded governance ruling", "explicit owner
      // authorization") that no rule can check, and this deliberately does not
      // pretend otherwise -- those still rest on the reviewer.
      if (event === 'verified') {
        const required = Array.isArray(task.evidenceRequired) ? task.evidenceRequired : [];
        const kinds = [...new Set(required
          .map((e) => /^(commit|ci|artifact):/i.exec(String(e).trim()))
          .filter(Boolean).map((m) => m[1].toLowerCase()))];
        if (kinds.length && !kinds.some((k) => new RegExp(`^${k}:`, 'i').test(note.trim()))) {
          throw new Error(`${task.id} requires ${kinds.map((k) => `${k}:`).join(' or ')} evidence; got "${note.trim().slice(0, 40)}"`);
        }
      }
      // A `commit:` reference must RESOLVE. Format validation alone accepted a
      // reference to a commit that did not contain the work: V5-AUTO-001 was
      // verified with `commit:3216bfe`, the BASELINE, while its deliverable
      // landed in 4c699dd. The shape was right and the content was wrong, and
      // nothing looked.
      //
      // Bounded on purpose: this resolves the object, it does not judge whether
      // the diff satisfies the acceptance criteria — a reviewer does that. It
      // only refuses a reference that points at nothing.
      if (event === 'verified') {
        const m = /^commit:([0-9a-f]{7,40})$/i.exec(note.trim());
        if (m) {
          // "not a git repository" and "that commit does not exist" both make
          // `cat-file` exit non-zero, and conflating them rejected VALID
          // evidence whenever the coordinator ran outside a checkout — which is
          // exactly how the sandboxed tests run. So the repo is established
          // first, and only then is a missing object treated as a failure.
          const inRepo = spawnSync('git', ['rev-parse', '--git-dir'],
            { cwd: ROOT, stdio: 'ignore' });
          const r = inRepo.error || inRepo.status !== 0
            ? null
            : spawnSync('git', ['cat-file', '-e', `${m[1]}^{commit}`],
                { cwd: ROOT, stdio: 'ignore' });
          if (r === null) {
            // No git, or no repository here. The claim is unverifiable rather
            // than false, and is recorded as such instead of silently passing.
            s.evidenceCheck = 'UNVERIFIABLE_NO_REPO';
          } else if (r.error) {
            s.evidenceCheck = 'UNVERIFIABLE_NO_GIT';
          } else if (r.status !== 0) {
            throw new Error(
              `evidence "${note.trim()}" does not resolve to a commit in this repository. `
              + `An unresolvable reference is not evidence.`);
          } else {
            s.evidenceCheck = 'COMMIT_RESOLVED';
          }
        }
      }
      if (event === 'retry' && s.attempts >= (task.maxRetries ?? MAX_RETRIES_DEFAULT) + 1) {
        s.status = 'FAILED_TERMINAL'; s.lastFailure = note || 'RETRY_BUDGET_EXHAUSTED';
      } else {
        s.status = map[event]; s.lastFailure = event === 'retry' ? (note || 'RETRY_REQUESTED') : null;
      }
      if (blocked.has(s.status)) s.blocker = { classification: s.status, note: note || 'No details supplied', at: now };
      else if (event === 'verified') s.evidence = { reference: note, recordedAt: now,
        verifiedBy: workerId(), verifiedByRole: process.env.SKILLS_AGENT_ROLE,
        // Carried INTO the evidence so a reader of the record can tell whether
        // the independence was attested by a runner or merely claimed.
        identityTrust: s.verifierIdentityTrust ?? 'self-asserted',
        implementedBy: s.implementedBy ?? null };
      else if (event !== 'retry') s.blocker = null;
      if (['verified', 'retry', 'failed', 'blocked-owner', 'blocked-external', 'blocked-governance'].includes(event) || s.status === 'FAILED_TERMINAL') {
        s.leaseToken = null; s.leaseExpiresAt = null;
        // The VERIFICATION lease was previously left dangling on these events.
        // A rejected task returning to the implementer kept a stale
        // verificationLeaseToken, and `claim verifier` skips any task that has
        // one — so once rejected, a task could never be re-verified.
        s.verificationLeaseToken = null; s.verificationLeaseExpiresAt = null;
        if (event !== 'verified') s.verifier = null;
      } else {
        s.leaseExpiresAt = new Date(Date.now() + DEFAULT_LEASE_MS).toISOString();
      }
      s.history.push({ at: now, event, note });
      state.updatedAt = now; writeAtomic(STATE_PATH, state); return { id, status: s.status };
    });
    console.log(JSON.stringify(result, null, 2)); return;
  }
  // ── block ─────────────────────────────────────────────────────────────────
  // WHY THIS EXISTS. `validate` reports a task that declares an unresolved
  // blocker while sitting in a runnable status, and says the status "should be
  // corrected" — but until now there was no way to correct it. `event` requires
  // a lease token, a lease comes only from `claim`, and `claim` selects on
  // `eligible()`, which the blocker itself vetoes. So the one status the queue
  // most needs to record was the one status the CLI could not reach, and the
  // existing BLOCKED_* rows in state.json had to be seeded by hand. Measured on
  // V5-GOV-009, added 2026-10-21.
  //
  // It takes no lease ON PURPOSE: a task this applies to cannot be claimed, so
  // requiring a lease would be requiring something unobtainable.
  //
  // IT CANNOT PARK RUNNABLE WORK. The task must already declare an unresolved
  // blocker. Without that check this would be a way to mark any inconvenient
  // task blocked and have the queue agree, which is exactly the failure mode the
  // blocker veto exists to prevent.
  if (command === 'block') {
    const [id, kindArg, ...rest] = args;
    const KINDS = { owner: 'BLOCKED_OWNER', external: 'BLOCKED_EXTERNAL', governance: 'BLOCKED_GOVERNANCE' };
    if (!id || !kindArg) throw new Error('usage: block <task-id> <owner|external|governance> [note]');
    if (!KINDS[kindArg]) throw new Error(`unknown block kind ${kindArg}; expected owner, external or governance`);
    const result = withLock(() => {
      const state = loadState(tasks);
      const task = tasks.find((t) => t.id === id);
      if (!task) throw new Error(`unknown task ${id}`);
      const unresolved = declaredBlockers(task);
      const s = state.tasks[id];
      const refusal = blockRefusalReason(task, s, unresolved);
      if (refusal) throw new Error(`${id} ${refusal}`);
      s.status = KINDS[kindArg];
      s.leaseToken = null; s.leaseExpiresAt = null;
      s.blockedKind = kindArg;
      s.blockedNote = rest.join(' ') || null;
      s.history.push({ at: new Date().toISOString(), event: KINDS[kindArg], worker: workerId(),
        note: s.blockedNote, blockerKinds: unresolved.map((b) => b.decision ? `decision:${b.decision}` : b.kind) });
      state.updatedAt = new Date().toISOString(); writeAtomic(STATE_PATH, state);
      return { id, status: s.status, recordedBlockers: unresolved.length };
    });
    console.log(JSON.stringify(result, null, 2)); return;
  }
  if (command === 'recover') {
    const result = withLock(() => { const state = loadState(tasks); const changed = recoverExpired(tasks, state); state.updatedAt = new Date().toISOString(); writeAtomic(STATE_PATH, state); return { recovered: changed, tasks: snapshot(tasks, state) }; });
    console.log(JSON.stringify(result, null, 2)); return;
  }
  throw new Error('commands: validate | status | claim <role> [lease-minutes] | event <task-id> <lease-token> <event> [note] | block <task-id> <owner|external|governance> [note] | recover | --self-test');
}
function countStatuses(state) {
  const counts = {};
  for (const s of Object.values(state.tasks)) counts[s.status] = (counts[s.status] ?? 0) + 1;
  return counts;
}
function selfTest() {
  const tasks = [
    { id: 'a', role: 'implementer', summary: 'a', dependsOn: [], paths: ['a'], acceptance: ['test'], maxRetries: 1 },
    { id: 'b', role: 'implementer', summary: 'b', dependsOn: ['a'], paths: ['b'], acceptance: ['test'], maxRetries: 1 },
    { id: 'c', role: 'implementer', summary: 'c', dependsOn: [], paths: ['c'], acceptance: ['test'], maxRetries: 1 }
  ];
  const state = { tasks: {
    a: { status: 'READY', attempts: 0, history: [] },
    b: { status: 'READY', attempts: 0, history: [] },
    c: { status: 'READY', attempts: 0, history: [] }
  }};
  if (!eligible(tasks[0], state) || eligible(tasks[1], state) || !eligible(tasks[2], state)) throw new Error('dependency scheduling self-test failed');

  // A declared blocker must veto eligibility even when every other condition
  // is satisfied. `d` is the exact shape that used to slip through: status
  // READY (the `??=` default for a task with no state record), no dependencies
  // to gate it, and an owner blocker the coordinator never read. Before this
  // check, `eligible(d)` was TRUE. The two assertions after it prove the veto
  // comes from the blocker and nothing else -- remove the blocker and the same
  // task becomes eligible again, so this cannot pass by vetoing everything.
  const d = { id: 'd', role: 'implementer', summary: 'd', dependsOn: [], paths: ['d'], acceptance: ['test'], maxRetries: 1,
    blockers: [{ kind: 'owner', what: 'an undecided product contract', evidence: 'self-test', action: 'owner ruling' }] };
  state.tasks.d = { status: 'READY', attempts: 0, history: [] };
  if (eligible(d, state)) throw new Error('declared-blocker veto self-test failed: a task with an unresolved blocker was eligible');
  if (!eligible({ ...d, blockers: [] }, state)) throw new Error('declared-blocker veto self-test failed: an empty blockers array must not block');
  if (!eligible({ ...d, blockers: undefined }, state)) throw new Error('declared-blocker veto self-test failed: an absent blockers field must not block');

  // `block` records a veto that already exists; it must never create one.
  const blk = { id: 'b', role: 'r', dependsOn: [], paths: [], acceptance: [],
    blockers: [{ kind: 'governance', what: 'a real conflict', evidence: 'self-test', action: 'owner ruling' }] };
  const free = { ...blk, blockers: [] };
  if (blockRefusalReason(free, { status: 'READY' }, declaredBlockers(free)) === null) {
    throw new Error('block self-test failed: a task with no unresolved blocker must be refused');
  }
  if (blockRefusalReason(blk, { status: 'READY' }, declaredBlockers(blk)) !== null) {
    throw new Error('block self-test failed: a task with an unresolved blocker must be recordable');
  }
  if (blockRefusalReason(blk, { status: 'CLAIMED' }, declaredBlockers(blk)) === null) {
    throw new Error('block self-test failed: a task holding a live lease must be refused');
  }
  if (blockRefusalReason(blk, { status: 'VERIFYING' }, declaredBlockers(blk)) === null) {
    throw new Error('block self-test failed: a task under verification must be refused');
  }

  // The admission rule. A task is product only if a declared path lands in the
  // application or its tests; no paths means it cannot change the product.
  const prodT = { id: 'p', role: 'implementer', dependsOn: [], acceptance: [], paths: ['apps/mobile/lib/features/x/'] };
  const testT = { ...prodT, paths: ['apps/mobile/test/unit/x_test.dart'] };
  const migT = { ...prodT, paths: ['supabase/migrations/999_x.sql'] };
  const dbTestT = { ...prodT, paths: ['supabase/tests/contract/x.mjs'] };
  const infraT = { ...prodT, paths: ['scripts/skills-agent-coordinator.mjs'] };
  const docT = { ...prodT, paths: ['docs/SOMETHING.md'] };
  const noPathT = { ...prodT, paths: [] };
  const mixedT = { ...prodT, paths: ['docs/A.md', 'apps/mobile/lib/f.dart'] };
  if (!isProductTask(prodT)) throw new Error('admission rule: an apps/mobile/lib path must be product');
  if (!isProductTask(testT)) throw new Error('admission rule: an apps/mobile/test path must be product');
  if (!isProductTask(migT)) throw new Error('admission rule: a supabase/migrations path must be product');
  if (!isProductTask(dbTestT)) throw new Error('admission rule: a supabase/tests path must be product');
  if (isProductTask(infraT)) throw new Error('admission rule: a scripts/ path must NOT be product');
  if (isProductTask(docT)) throw new Error('admission rule: a docs/ path must NOT be product');
  if (isProductTask(noPathT)) throw new Error('admission rule: a task with no paths must NOT be product');
  if (!isProductTask(mixedT)) throw new Error('admission rule: ANY product path makes the task product');
  // A near-miss must not count: the prefix is anchored, so a lookalike outside
  // the application does not smuggle an infrastructure task past the rule.
  if (isProductTask({ ...prodT, paths: ['vendor/apps/mobile/lib/x.dart'] })) {
    throw new Error('admission rule: the product prefix must be anchored at the start of the path');
  }

  // Derived status for a fresh clone, where state.json does not exist.
  const govT = { ...blk };
  const extT = { ...blk, blockers: [{ kind: 'external', what: 'x', evidence: 'e', action: 'a' }] };
  const decT = { ...blk, blockers: [{ kind: 'owner', decision: 'OD-TEST', what: 'x', evidence: 'e', action: 'a' }] };
  const mixT = { ...blk, blockers: [
    { kind: 'external', what: 'x', evidence: 'e', action: 'a' },
    { kind: 'governance', what: 'y', evidence: 'e', action: 'a' }] };
  if (derivedBlockedStatus(govT) !== 'BLOCKED_GOVERNANCE') throw new Error('derived status: a governance blocker must derive BLOCKED_GOVERNANCE');
  if (derivedBlockedStatus(extT) !== 'BLOCKED_EXTERNAL') throw new Error('derived status: an external blocker must derive BLOCKED_EXTERNAL');
  if (derivedBlockedStatus(decT) !== 'BLOCKED_OWNER') throw new Error('derived status: a decision blocker must derive BLOCKED_OWNER');
  if (derivedBlockedStatus(mixT) !== 'BLOCKED_GOVERNANCE') throw new Error('derived status: governance must take precedence over external');
  if (derivedBlockedStatus(free) !== null) throw new Error('derived status: a task with no unresolved blocker must derive nothing');
  // An AUTHORIZED decision must stop deriving a block, or a resolved decision
  // would leave the task reading blocked forever.
  if (derivedBlockedStatus(decT, { 'OD-TEST': { state: AUTHORIZING_STATE, owner: 'o', answeredAt: '2026-01-01', record: 'package.json' } }) !== null) {
    throw new Error('derived status: an authorized decision must stop deriving a block');
  }
  // A RECORDED status must win. snapshot() only derives over a READY placeholder.
  const snapState = { tasks: { [govT.id]: { status: 'VERIFIED', attempts: 1, history: [] } } };
  const snapped = snapshot([govT], snapState)[0];
  if (snapped.status !== 'VERIFIED' || snapped.statusSource !== 'recorded') {
    throw new Error('derived status: a recorded status must win over derivation');
  }

  state.tasks.a = { status: 'CLAIMED', attempts: 1, leaseExpiresAt: new Date(Date.now() - 1000).toISOString(), history: [] };
  if (!recoverExpired(tasks, state) || state.tasks.a.status !== 'RETRY_WAIT') throw new Error('expired lease recovery self-test failed');
  let cycleRejected = false;
  try { detectCycles([{ id: 'x', dependsOn: ['y'] }, { id: 'y', dependsOn: ['x'] }]); } catch { cycleRejected = true; }
  if (!cycleRejected) throw new Error('cycle detection self-test failed');
  // ── the decision gate ──────────────────────────────────────────────────────
  //
  // A blocker naming a decision must be released by the LEDGER and by nothing
  // else. Each assertion is paired with its converse so none can pass by
  // vetoing everything.
  const gated = { id: 'g', role: 'implementer', summary: 'g', dependsOn: [], paths: ['g'],
    acceptance: ['test'], maxRetries: 1,
    blockers: [{ kind: 'owner', decision: 'OD-TEST', what: 'an unmade decision', evidence: 'self-test', action: 'owner ruling' }] };
  const gstate = { tasks: { g: { status: 'READY', attempts: 0, history: [] } } };
  // A COMPLETE entry: authorizing now also requires owner, answeredAt and a
  // record path that exists. `package.json` is used only because it is a file
  // this repository certainly has.
  const atState = (st) => ({ 'OD-TEST': { state: st, owner: 'self-test', answeredAt: '2026-01-01', record: 'package.json' } });

  if (eligible(gated, gstate, atState('proposed'))) throw new Error('decision gate: proposed must veto');
  if (eligible(gated, gstate, atState('accepted'))) throw new Error('decision gate: accepted must veto - accepting is not authorizing');
  if (eligible(gated, gstate, atState('recorded'))) throw new Error('decision gate: recorded must veto - recording is not authorizing');
  if (!eligible(gated, gstate, atState(AUTHORIZING_STATE))) throw new Error('decision gate: the authorizing state must release');

  // Fail-closed: an absent id, an empty ledger, a malformed entry and a
  // case-mismatched id must all keep the veto. A typo must never authorize.
  if (eligible(gated, gstate, {})) throw new Error('decision gate: an unknown decision must veto');
  if (eligible(gated, gstate, { 'OD-TEST': {} })) throw new Error('decision gate: an entry with no state must veto');
  if (eligible(gated, gstate, { 'OD-TEST': { state: 42 } })) throw new Error('decision gate: a non-string state must veto');
  if (eligible(gated, gstate, { 'od-test': { state: AUTHORIZING_STATE } })) throw new Error('decision gate: ids must not match case-insensitively');

  // An ungated task is untouched by any of this.
  const plain = { id: 'p', role: 'implementer', summary: 'p', dependsOn: [], paths: ['p'], acceptance: ['test'], maxRetries: 1 };
  const pstate = { tasks: { p: { status: 'READY', attempts: 0, history: [] } } };
  if (!eligible(plain, pstate, {})) throw new Error('decision gate: an ungated task must stay eligible');

  // An authorizing entry with nothing behind it must NOT release. Each field is
  // removed in turn so no single assertion can pass by vetoing everything.
  const complete = { state: AUTHORIZING_STATE, owner: 'o', answeredAt: 'd', record: 'package.json' };
  for (const drop of ['owner', 'answeredAt', 'record']) {
    const partial = { ...complete }; delete partial[drop];
    if (eligible(gated, gstate, { 'OD-TEST': partial })) throw new Error(`provenance: missing ${drop} must veto`);
  }
  if (eligible(gated, gstate, { 'OD-TEST': { ...complete, owner: '   ' } })) throw new Error('provenance: a blank owner must veto');
  if (eligible(gated, gstate, { 'OD-TEST': { ...complete, record: 'docs/does-not-exist-xyz.md' } })) throw new Error('provenance: a record that does not exist must veto');
  if (eligible(gated, gstate, { 'OD-TEST': { ...complete, record: 'docs' } })) throw new Error('provenance: a DIRECTORY must not satisfy the record check');
  if (eligible(gated, gstate, { 'OD-TEST': { ...complete, record: 'scripts' } })) throw new Error('provenance: any directory must veto, not just docs');
  {
    // An EMPTY regular file must not satisfy it either. Written to the system
    // temp dir and removed immediately, so the repository is untouched.
    const d = fs.mkdtempSync(path.join(process.env.TMPDIR || '/tmp', 'rec-'));
    const empty = path.join(d, 'empty.md');
    fs.writeFileSync(empty, '');
    const nonEmpty = path.join(d, 'full.md');
    fs.writeFileSync(nonEmpty, 'an owner decision');
    try {
      if (eligible(gated, gstate, { 'OD-TEST': { ...complete, record: empty } })) throw new Error('provenance: an EMPTY record file must veto');
      if (!eligible(gated, gstate, { 'OD-TEST': { ...complete, record: nonEmpty } })) throw new Error('provenance: a non-empty regular file must satisfy the record check');
      // Structural completeness is not proof: an arbitrary owner still passes,
      // which is exactly why this is labelled completeness and not provenance.
      if (!eligible(gated, gstate, { 'OD-TEST': { ...complete, owner: 'anyone at all', record: nonEmpty } })) throw new Error('provenance: an arbitrary owner is still structurally complete — CR-1 remains open');
    } finally { fs.rmSync(d, { recursive: true, force: true }); }
  }
  if (!eligible(gated, gstate, { 'OD-TEST': complete })) throw new Error('provenance: a complete authorizing entry must release');

  // Releasing one gate must not release another.
  const twoGates = { ...gated, id: 'g2', paths: ['g2'],
    blockers: [ { kind: 'owner', decision: 'OD-TEST', what: 'x', evidence: 's', action: 'a' },
                { kind: 'external', what: 'no credential', evidence: 's', action: 'provision' } ] };
  const g2state = { tasks: { g2: { status: 'READY', attempts: 0, history: [] } } };
  if (eligible(twoGates, g2state, atState(AUTHORIZING_STATE))) throw new Error('decision gate: a second non-decision blocker must still veto');

  // AUDIT F1 regression · duplicate ids must be reported, not resolved.
  if (duplicateDecisionIds('{"X":{"state":"a"},"X":{"state":"b"}}', ['X']).length !== 1) throw new Error('F1: a duplicate id must be detected');
  if (duplicateDecisionIds('{"X":{"state":"a"}}', ['X']).length !== 0) throw new Error('F1: a single id must not be flagged');
  if (duplicateDecisionIds('{"X":{"state":"a"},"XY":{"state":"b"}}', ['X','XY']).length !== 0) throw new Error('F1: a longer id sharing a prefix must not count as a duplicate');
  if (duplicateDecisionIds('{"OD-14":{"s":1},"OD-14":{"s":2}}', ['OD-14']).length !== 1) throw new Error('F1: a hyphenated id must be detected');
  if (duplicateDecisionIds('{"a.b":{"s":1},"axb":{"s":2}}', ['a.b']).length !== 0) throw new Error('F1: the id must be regex-escaped, so a dot must not match any char');

  console.log('PASS: dependency scheduling, independent task eligibility, declared-blocker veto, expired-lease recovery, dependency-cycle rejection, decision gate (9), provenance completeness (11), F1 duplicate-id detection (5), block preconditions (4), derived status (7), admission rule (9) — all fail-closed');
}
try { main(); } catch (e) { fail(e.message); }
