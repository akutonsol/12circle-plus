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
function blockerStatusDrift(tasks, state) {
  const runnable = new Set(['READY', 'RETRY_WAIT']);
  return tasks
    .filter((t) => (Array.isArray(t.blockers) ? t.blockers : []).length > 0)
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
function declaredBlockers(task) { return Array.isArray(task.blockers) ? task.blockers : []; }
function eligible(task, state) {
  const s = state.tasks[task.id];
  if (declaredBlockers(task).length > 0) return false;
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
  return tasks.map(t => ({ id: t.id, summary: t.summary, role: t.role, status: state.tasks[t.id].status,
    dependsOn: t.dependsOn, eligible: eligible(t, state), attempts: state.tasks[t.id].attempts,
    blocker: state.tasks[t.id].blocker ?? null }));
}
function main() {
  const [command, ...args] = process.argv.slice(2);
  if (command === '--self-test') return selfTest();
  const tasks = loadTasks();
  if (command === 'validate') {
    const drift = blockerStatusDrift(tasks, loadState(tasks));
    console.log(JSON.stringify({ valid: true, taskCount: tasks.length,
      blockerStatusDrift: drift }, null, 2));
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
    console.log(JSON.stringify({ tasks: snapshot(tasks, state), counts: countStatuses(state) }, null, 2)); return;
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
        : tasks.find(t => t.role === role && eligible(t, state));
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
    console.log(JSON.stringify(claimed ?? { claimed: false, reason: 'NO_ELIGIBLE_TASK_FOR_ROLE', role }, null, 2)); return;
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
  if (command === 'recover') {
    const result = withLock(() => { const state = loadState(tasks); const changed = recoverExpired(tasks, state); state.updatedAt = new Date().toISOString(); writeAtomic(STATE_PATH, state); return { recovered: changed, tasks: snapshot(tasks, state) }; });
    console.log(JSON.stringify(result, null, 2)); return;
  }
  throw new Error('commands: validate | status | claim <role> [lease-minutes] | event <task-id> <lease-token> <event> [note] | recover | --self-test');
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

  state.tasks.a = { status: 'CLAIMED', attempts: 1, leaseExpiresAt: new Date(Date.now() - 1000).toISOString(), history: [] };
  if (!recoverExpired(tasks, state) || state.tasks.a.status !== 'RETRY_WAIT') throw new Error('expired lease recovery self-test failed');
  let cycleRejected = false;
  try { detectCycles([{ id: 'x', dependsOn: ['y'] }, { id: 'y', dependsOn: ['x'] }]); } catch { cycleRejected = true; }
  if (!cycleRejected) throw new Error('cycle detection self-test failed');
  console.log('PASS: dependency scheduling, independent task eligibility, declared-blocker veto, expired-lease recovery, dependency-cycle rejection');
}
try { main(); } catch (e) { fail(e.message); }
