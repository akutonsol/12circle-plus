#!/usr/bin/env node
/**
 * Skills-Agent coordinator — behavioural tests.
 *
 * These drive the REAL `scripts/skills-agent-coordinator.mjs` as a subprocess
 * inside a disposable sandbox, because the properties under test are about
 * durable on-disk state and process boundaries. Importing the module would test
 * a different thing: in-memory objects that never cross a process exit.
 *
 * Every sandbox gets its own directory, so a failing test cannot leak state
 * into the next one, and nothing here touches the repository's own
 * `.skills-agent/state.json`.
 */
import { spawnSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const COORD = path.join(ROOT, 'scripts', 'skills-agent-coordinator.mjs');

let passed = 0;
const failures = [];
function check(name, cond, detail = '') {
  if (cond) { passed++; console.log(`  PASS  ${name}${detail ? `  — ${detail}` : ''}`); }
  else { failures.push(name); console.log(`  FAIL  ${name}${detail ? `  — ${detail}` : ''}`); }
}
function section(t) { console.log(`\n── ${t} ${'─'.repeat(Math.max(0, 66 - t.length))}`); }

function sandbox(tasks) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'sa-test-'));
  fs.mkdirSync(path.join(dir, 'scripts'), { recursive: true });
  fs.mkdirSync(path.join(dir, '.skills-agent'), { recursive: true });
  fs.copyFileSync(COORD, path.join(dir, 'scripts', 'skills-agent-coordinator.mjs'));
  fs.writeFileSync(path.join(dir, '.skills-agent', 'tasks.json'),
    JSON.stringify({ version: 1, tasks }, null, 2));
  return dir;
}
// Returns {ok, out, err}. Never throws: a non-zero exit is an OUTCOME under
// test, not a harness failure.
function run(dir, args, env = {}) {
  const r = spawnSync(process.execPath,
    [path.join(dir, 'scripts', 'skills-agent-coordinator.mjs'), ...args],
    { encoding: 'utf8', env: { ...process.env, ...env } });
  // stdout AND stderr are kept whatever the exit code: the coordinator writes
  // operational notices (a stale-lock reclaim) to stderr while still
  // succeeding, and a non-zero exit is an OUTCOME under test, not a harness
  // failure.
  return { ok: r.status === 0, out: r.stdout ?? '', err: (r.stderr ?? '') + (r.stdout ?? '') };
}
const json = (r) => { try { return JSON.parse(r.out); } catch { return null; } };
const stateOf = (dir) =>
  JSON.parse(fs.readFileSync(path.join(dir, '.skills-agent', 'state.json'), 'utf8'));
const T = (id, extra = {}) => ({
  id, role: 'implementer', summary: id, dependsOn: [], paths: ['x'],
  acceptance: ['test'], maxRetries: 2, ...extra,
});

// ═══ 1 · concurrent claims and duplicate prevention ════════════════════════
section('1 · concurrent claims cannot hand the same task to two workers');
{
  const dir = sandbox([T('A')]);
  const first = json(run(dir, ['claim', 'implementer'], { SKILLS_AGENT_ID: 'w1' }));
  const second = json(run(dir, ['claim', 'implementer'], { SKILLS_AGENT_ID: 'w2' }));
  check('the first worker receives the task', first?.task?.id === 'A', `token=${first?.token?.slice(0, 8)}`);
  check('the second worker is refused, with a reason rather than a crash',
    second?.claimed === false && second?.reason === 'NO_ELIGIBLE_TASK_FOR_ROLE',
    JSON.stringify(second));
  check('only one lease token exists on disk',
    !!stateOf(dir).tasks.A.leaseToken && stateOf(dir).tasks.A.status === 'CLAIMED');
}

// ═══ 2 · dependency blocking, independent work still runnable ══════════════
section('2 · a blocked dependency does not stall unrelated work');
{
  const dir = sandbox([T('A'), T('B', { dependsOn: ['A'] }), T('C')]);
  const one = json(run(dir, ['claim', 'implementer'], { SKILLS_AGENT_ID: 'w1' }));
  const two = json(run(dir, ['claim', 'implementer'], { SKILLS_AGENT_ID: 'w2' }));
  const got = [one?.task?.id, two?.task?.id].filter(Boolean).sort();
  check('the two independent tasks are dispatched, never the dependent one',
    got.length === 2 && got.join(',') === 'A,C', `dispatched=${got.join(',')}`);
  const st = json(run(dir, ['status']));
  const b = st.tasks.find((t) => t.id === 'B');
  check('B stays ineligible while A is unverified', b.eligible === false, `B.status=${b.status}`);
  // Block A outright; C must remain workable.
  run(dir, ['event', 'A', stateOf(dir).tasks.A.leaseToken, 'blocked-owner', 'needs a ruling'],
    { SKILLS_AGENT_ID: 'w1' });
  const after = json(run(dir, ['status']));
  check('a blocked A is recorded with its classification',
    after.tasks.find((t) => t.id === 'A').status === 'BLOCKED_OWNER');
  check('B remains blocked BY DEPENDENCY, not silently failed',
    after.tasks.find((t) => t.id === 'B').status === 'READY');
  check('C is untouched by A\'s blocker — unrelated work continues',
    after.tasks.find((t) => t.id === 'C').status === 'CLAIMED');
}

// ═══ 3 · expired leases ════════════════════════════════════════════════════
section('3 · expired implementation and verification leases recover honestly');
{
  const dir = sandbox([T('A')]);
  run(dir, ['claim', 'implementer'], { SKILLS_AGENT_ID: 'w1' });
  const s = stateOf(dir);
  s.tasks.A.leaseExpiresAt = new Date(Date.now() - 1000).toISOString();
  fs.writeFileSync(path.join(dir, '.skills-agent', 'state.json'), JSON.stringify(s, null, 2));
  const rec = json(run(dir, ['recover']));
  check('an expired implementation lease returns the task to RETRY_WAIT',
    rec.recovered === true && stateOf(dir).tasks.A.status === 'RETRY_WAIT');
  check('…and is NOT recorded as success',
    stateOf(dir).tasks.A.status !== 'VERIFIED' && stateOf(dir).tasks.A.lastFailure === 'LEASE_EXPIRED');

  const dir2 = sandbox([T('A')]);
  const c = json(run(dir2, ['claim', 'implementer'], { SKILLS_AGENT_ID: 'w1' }));
  run(dir2, ['event', 'A', c.token, 'implemented', 'done'], { SKILLS_AGENT_ID: 'w1' });
  run(dir2, ['claim', 'verifier'], { SKILLS_AGENT_ID: 'v1', SKILLS_AGENT_ROLE: 'verifier' });
  const s2 = stateOf(dir2);
  s2.tasks.A.verificationLeaseExpiresAt = new Date(Date.now() - 1000).toISOString();
  fs.writeFileSync(path.join(dir2, '.skills-agent', 'state.json'), JSON.stringify(s2, null, 2));
  run(dir2, ['recover']);
  const a2 = stateOf(dir2).tasks.A;
  check('an expired VERIFICATION lease returns to IMPLEMENTED, awaiting a new verifier',
    a2.status === 'IMPLEMENTED' && a2.verificationLeaseToken === null, `status=${a2.status}`);
  check('…and does not assume the work was good',
    a2.status !== 'VERIFIED' && !a2.evidence);
}

// ═══ 4 · stale token rejection ═════════════════════════════════════════════
section('4 · a stale worker cannot change state after its lease is gone');
{
  const dir = sandbox([T('A')]);
  const c = json(run(dir, ['claim', 'implementer'], { SKILLS_AGENT_ID: 'w1' }));
  const stale = c.token;
  const s = stateOf(dir);
  s.tasks.A.leaseExpiresAt = new Date(Date.now() - 1000).toISOString();
  fs.writeFileSync(path.join(dir, '.skills-agent', 'state.json'), JSON.stringify(s, null, 2));
  run(dir, ['recover']);
  const r = run(dir, ['event', 'A', stale, 'implemented', 'late'], { SKILLS_AGENT_ID: 'w1' });
  check('the expired worker\'s event is rejected by token mismatch',
    !r.ok && /lease token mismatch/.test(r.err), r.err.trim().slice(0, 80));
  check('and the task did not advance', stateOf(dir).tasks.A.status === 'RETRY_WAIT');
  const r2 = run(dir, ['event', 'A', 'totally-made-up-token', 'implemented', 'x'], { SKILLS_AGENT_ID: 'w1' });
  check('a fabricated token is rejected too', !r2.ok && /lease token mismatch/.test(r2.err));
}

// ═══ 5 · independent verifier enforcement ══════════════════════════════════
section('5 · a worker cannot certify its own implementation');
{
  const dir = sandbox([T('A')]);
  const c = json(run(dir, ['claim', 'implementer'], { SKILLS_AGENT_ID: 'mallory' }));
  run(dir, ['event', 'A', c.token, 'implemented', 'done'], { SKILLS_AGENT_ID: 'mallory' });
  const self = run(dir, ['claim', 'verifier'], { SKILLS_AGENT_ID: 'mallory', SKILLS_AGENT_ROLE: 'verifier' });
  check('the implementer is refused the verification lease',
    !self.ok && /cannot also verify/.test(self.err), self.err.trim().slice(0, 90));
  const anon = run(dir, ['claim', 'verifier'], { SKILLS_AGENT_ROLE: 'verifier', SKILLS_AGENT_ID: '' });
  check('dropping SKILLS_AGENT_ID to earn a fresh pid identity is refused',
    !anon.ok && /SKILLS_AGENT_ID must be set/.test(anon.err), anon.err.trim().slice(0, 90));
  const v = json(run(dir, ['claim', 'verifier'], { SKILLS_AGENT_ID: 'alice', SKILLS_AGENT_ROLE: 'verifier' }));
  check('a genuinely different verifier may claim', v?.assignment === 'independent-verification');
  const noEv = run(dir, ['event', 'A', v.token, 'verified', 'looks fine to me'],
    { SKILLS_AGENT_ID: 'alice', SKILLS_AGENT_ROLE: 'verifier' });
  check('verification without an evidence reference is refused',
    !noEv.ok && /evidence reference/.test(noEv.err), noEv.err.trim().slice(0, 70));
  const ok = run(dir, ['event', 'A', v.token, 'verified', 'commit:abc123'],
    { SKILLS_AGENT_ID: 'alice', SKILLS_AGENT_ROLE: 'verifier' });
  const a = stateOf(dir).tasks.A;
  check('verification with evidence succeeds and records BOTH identities',
    ok.ok && a.status === 'VERIFIED' && a.implementedBy === 'mallory' && a.evidence?.verifiedBy === 'alice',
    `implementedBy=${a.implementedBy} verifiedBy=${a.evidence?.verifiedBy}`);
}

// ═══ 5b · separation cannot be defeated by OMITTING an identity ════════════
// This gap survived the first version of both the fix and this suite: the
// tests always passed SKILLS_AGENT_ID, so nobody exercised the anonymous path.
// Found by running a real cycle. An anonymous implementer was recorded as
// `pid:1234`, which never equals a named verifier — so separation was
// defeatable by simply not setting a variable.
section('5b · an anonymous worker cannot sidestep the independence check');
{
  const dir = sandbox([T('A')]);
  const anon = run(dir, ['claim', 'implementer'], { SKILLS_AGENT_ID: '' });
  check('an implementer claim without an identity is refused outright',
    !anon.ok && /SKILLS_AGENT_ID must be set/.test(anon.err), anon.err.trim().slice(0, 80));
  check('…and no task was claimed as a side effect',
    !fs.existsSync(path.join(dir, '.skills-agent', 'state.json'))
      || stateOf(dir).tasks.A.status === 'READY');
  const ws = run(dir, ['claim', 'implementer'], { SKILLS_AGENT_ID: '   ' });
  check('whitespace is not an identity', !ws.ok && /SKILLS_AGENT_ID must be set/.test(ws.err));
  // And the real shape of the original defect, end to end.
  const c = json(run(dir, ['claim', 'implementer'], { SKILLS_AGENT_ID: 'w1' }));
  run(dir, ['event', 'A', c.token, 'implemented', 'done'], { SKILLS_AGENT_ID: 'w1' });
  check('implementedBy is a real identity, not a pid',
    stateOf(dir).tasks.A.implementedBy === 'w1'
      && !/^pid:/.test(stateOf(dir).tasks.A.implementedBy),
    `implementedBy=${stateOf(dir).tasks.A.implementedBy}`);
}

// ═══ 5c · adversarial identity — what the boundary actually withstands ═════
// Four attacks were run against the coordinator by hand before these were
// written. Three were already refused; ONE worked — an implementer that renames
// itself obtains the verification lease. These tests pin the three that hold
// and record the one that does not, so neither set can regress unnoticed.
section('5c · adversarial identity probes');
{
  const dir = sandbox([T('A')]);
  const c = json(run(dir, ['claim', 'implementer'], { SKILLS_AGENT_ID: 'impl' }));
  run(dir, ['event', 'A', c.token, 'implemented', 'done'], { SKILLS_AGENT_ID: 'impl' });

  const replay = run(dir, ['event', 'A', c.token, 'verified', 'commit:aaa'],
    { SKILLS_AGENT_ID: 'impl', SKILLS_AGENT_ROLE: 'verifier' });
  check('ATTACK · replaying the implementation token as a verify is refused',
    !replay.ok && /lease token mismatch/.test(replay.err));

  const v = json(run(dir, ['claim', 'verifier'], { SKILLS_AGENT_ID: 'alice', SKILLS_AGENT_ROLE: 'verifier' }));
  const noRole = run(dir, ['event', 'A', v.token, 'verified', 'commit:bbb'], { SKILLS_AGENT_ID: 'alice' });
  check('ATTACK · verifying without declaring the verifier role is refused',
    !noRole.ok && /only the independently claimed verifier/.test(noRole.err));

  const thirdParty = run(dir, ['event', 'A', v.token, 'verified', 'commit:ccc'],
    { SKILLS_AGENT_ID: 'eve', SKILLS_AGENT_ROLE: 'verifier' });
  check('ATTACK · a third party cannot spend somebody else\'s verification lease',
    !thirdParty.ok && /lease belongs to "alice"/.test(thirdParty.err),
    thirdParty.err.trim().slice(0, 70));

  // The one that WORKS, asserted as a known limitation rather than hidden.
  const dir2 = sandbox([T('A')]);
  const c2 = json(run(dir2, ['claim', 'implementer'], { SKILLS_AGENT_ID: 'impl' }));
  run(dir2, ['event', 'A', c2.token, 'implemented', 'done'], { SKILLS_AGENT_ID: 'impl' });
  const renamed = run(dir2, ['claim', 'verifier'], { SKILLS_AGENT_ID: 'impl-alias', SKILLS_AGENT_ROLE: 'verifier' });
  check('KNOWN LIMIT · renaming DOES obtain the lease when identity is '
      + 'self-asserted — this documents the gap, it does not bless it',
    renamed.ok, 'closing it requires a runner-held attestation key (see 5d)');
}

// ═══ 5d · the attestation contract, for when a runner exists ═══════════════
section('5d · runner-minted identity attestation');
{
  const KEY = 'runner-held-secret';
  const mint = (taskId, role, id) =>
    crypto.createHmac('sha256', KEY).update(`${taskId}:${role}:${id}`).digest('hex');
  const withPolicy = (tasks) => {
    const dir = sandbox(tasks);
    const f = path.join(dir, '.skills-agent', 'tasks.json');
    const d = JSON.parse(fs.readFileSync(f, 'utf8'));
    d.policy = { requireAttestedIdentity: true };
    fs.writeFileSync(f, JSON.stringify(d, null, 2));
    return dir;
  };

  // Backward compatibility first: no key configured changes nothing.
  const plain = sandbox([T('A')]);
  const pc = json(run(plain, ['claim', 'implementer'], { SKILLS_AGENT_ID: 'impl' }));
  check('with NO attestation key, behaviour is unchanged and trust is recorded '
      + 'as self-asserted',
    !!pc?.token && stateOf(plain).tasks.A.implementerIdentityTrust === 'self-asserted',
    `trust=${stateOf(plain).tasks.A.implementerIdentityTrust}`);

  const dir = withPolicy([T('A')]);
  const env = (id, role, tok) => ({
    SKILLS_AGENT_ID: id, SKILLS_AGENT_ROLE: role,
    SKILLS_AGENT_ATTESTATION_KEY: KEY, SKILLS_AGENT_IDENTITY_TOKEN: tok,
  });
  const ic = json(run(dir, ['claim', 'implementer'], env('impl', 'implementer', mint('A', 'implementer', 'impl'))));
  check('an attested implementer claim succeeds and is recorded attested',
    !!ic?.token && stateOf(dir).tasks.A.implementerIdentityTrust === 'attested');
  run(dir, ['event', 'A', ic.token, 'implemented', 'done'], { SKILLS_AGENT_ID: 'impl' });

  const bare = run(dir, ['claim', 'verifier'], { SKILLS_AGENT_ID: 'alice', SKILLS_AGENT_ROLE: 'verifier' });
  check('under the policy, an UNATTESTED verifier is refused',
    !bare.ok && /requireAttestedIdentity/.test(bare.err), bare.err.trim().slice(0, 70));

  const forged = run(dir, ['claim', 'verifier'], env('alice', 'verifier', 'deadbeef'));
  check('a forged attestation token is refused',
    !forged.ok && /attestation failed/.test(forged.err));

  const wrongId = run(dir, ['claim', 'verifier'], env('alice', 'verifier', mint('A', 'verifier', 'someone-else')));
  check('a token minted for a DIFFERENT identity is refused — the token is '
      + 'bound to who it names, not merely to the key',
    !wrongId.ok && /attestation failed/.test(wrongId.err));

  const good = json(run(dir, ['claim', 'verifier'], env('alice', 'verifier', mint('A', 'verifier', 'alice'))));
  check('a correctly attested verifier may claim', !!good?.token);
  run(dir, ['event', 'A', good.token, 'verified', 'commit:abc'],
    { SKILLS_AGENT_ID: 'alice', SKILLS_AGENT_ROLE: 'verifier' });
  const ev = stateOf(dir).tasks.A.evidence;
  check('the evidence records the trust level and the implementer it is '
      + 'independent OF',
    ev?.identityTrust === 'attested' && ev?.implementedBy === 'impl',
    `identityTrust=${ev?.identityTrust} implementedBy=${ev?.implementedBy}`);
}

// ═══ 6 · rejected verification returns work to the implementer ═════════════
section('6 · a rejected verification returns the task, and can be re-verified');
{
  const dir = sandbox([T('A')]);
  const c = json(run(dir, ['claim', 'implementer'], { SKILLS_AGENT_ID: 'w1' }));
  run(dir, ['event', 'A', c.token, 'implemented', 'v1'], { SKILLS_AGENT_ID: 'w1' });
  const v = json(run(dir, ['claim', 'verifier'], { SKILLS_AGENT_ID: 'alice', SKILLS_AGENT_ROLE: 'verifier' }));
  run(dir, ['event', 'A', v.token, 'retry', 'evidence insufficient'],
    { SKILLS_AGENT_ID: 'alice', SKILLS_AGENT_ROLE: 'verifier' });
  const a = stateOf(dir).tasks.A;
  check('rejection returns the task to RETRY_WAIT for the implementer',
    a.status === 'RETRY_WAIT', `status=${a.status}`);
  check('the verification lease is CLEARED on rejection — otherwise the task '
      + 'could never be verified again',
    a.verificationLeaseToken == null, `token=${a.verificationLeaseToken}`);
  const c2 = json(run(dir, ['claim', 'implementer'], { SKILLS_AGENT_ID: 'w1' }));
  check('the implementer can pick it back up', c2?.task?.id === 'A');
  run(dir, ['event', 'A', c2.token, 'implemented', 'v2'], { SKILLS_AGENT_ID: 'w1' });
  const v2 = json(run(dir, ['claim', 'verifier'], { SKILLS_AGENT_ID: 'alice', SKILLS_AGENT_ROLE: 'verifier' }));
  check('and a verifier can claim the re-submitted work', !!v2?.token);
}

// ═══ 7 · retry exhaustion ══════════════════════════════════════════════════
section('7 · retries are bounded and exhaustion is terminal, not silent');
{
  const dir = sandbox([T('A', { maxRetries: 1 })]);
  let last = 'READY';
  for (let i = 0; i < 5; i++) {
    const c = json(run(dir, ['claim', 'implementer'], { SKILLS_AGENT_ID: 'w1' }));
    if (!c?.token) break;
    run(dir, ['event', 'A', c.token, 'retry', 'still failing'], { SKILLS_AGENT_ID: 'w1' });
    last = stateOf(dir).tasks.A.status;
    if (last === 'FAILED_TERMINAL') break;
  }
  check('the retry budget terminates the task instead of looping forever',
    last === 'FAILED_TERMINAL', `final=${last} attempts=${stateOf(dir).tasks.A.attempts}`);
  check('the terminal failure records WHY', !!stateOf(dir).tasks.A.lastFailure,
    stateOf(dir).tasks.A.lastFailure);
  const c = run(dir, ['claim', 'implementer'], { SKILLS_AGENT_ID: 'w1' });
  check('a terminally failed task is not re-dispatched',
    json(c)?.claimed === false, JSON.stringify(json(c)));
}

// ═══ 8 · restart recovery ══════════════════════════════════════════════════
section('8 · state survives a process exit without inventing success');
{
  const dir = sandbox([T('A'), T('B', { dependsOn: ['A'] })]);
  const c = json(run(dir, ['claim', 'implementer'], { SKILLS_AGENT_ID: 'w1' }));
  run(dir, ['event', 'A', c.token, 'implemented', 'done'], { SKILLS_AGENT_ID: 'w1' });
  // Every `run` above was a SEPARATE OS process; this is a genuine restart.
  const after = json(run(dir, ['status']));
  const a = after.tasks.find((t) => t.id === 'A');
  check('a fresh process reads the persisted IMPLEMENTED state',
    a.status === 'IMPLEMENTED', `A=${a.status}`);
  check('the dependent task is still gated — restart did not mark A verified',
    after.tasks.find((t) => t.id === 'B').eligible === false);
  const v = json(run(dir, ['claim', 'verifier'], { SKILLS_AGENT_ID: 'alice', SKILLS_AGENT_ROLE: 'verifier' }));
  run(dir, ['event', 'A', v.token, 'verified', 'ci:12345'],
    { SKILLS_AGENT_ID: 'alice', SKILLS_AGENT_ROLE: 'verifier' });
  const final = json(run(dir, ['status']));
  check('once genuinely verified, the dependent task becomes eligible — the '
      + 'coordinator dispatches the next work by itself',
    final.tasks.find((t) => t.id === 'B').eligible === true);
}

// ═══ 8b · a crashed coordinator must not retire the queue ══════════════════
// The lock is released in a `finally`, which SIGKILL, power loss and an OOM
// kill never run. Before this, the orphaned file made every later command fail
// with "queue lock already held" FOREVER — one crash retired the queue.
section('8b · stale lock recovery, fail-closed');
{
  const dir = sandbox([T('A')]);
  const lock = path.join(dir, '.skills-agent', '.state.lock');

  fs.writeFileSync(lock, JSON.stringify({ pid: 999999, at: '2026-01-01T00:00:00Z' }));
  const stale = run(dir, ['claim', 'implementer'], { SKILLS_AGENT_ID: 'w1' });
  check('a lock whose holder is gone is reclaimed, and the claim proceeds',
    stale.ok && json(stale)?.task?.id === 'A');
  check('…and the reclaim is announced, not silent',
    /reclaiming a stale queue lock/.test(stale.err + stale.out));

  // The opposite direction matters more: a LIVE holder must still win.
  fs.writeFileSync(lock, JSON.stringify({ pid: process.pid, at: '2026-01-01T00:00:00Z' }));
  const live = run(dir, ['claim', 'implementer'], { SKILLS_AGENT_ID: 'w2' });
  check('a lock held by a RUNNING process is still refused — reclaim is '
      + 'fail-closed, so a recycled pid keeps the lock rather than losing it',
    !live.ok && /held by running pid/.test(live.err), live.err.trim().slice(0, 72));
  fs.unlinkSync(lock);

  const ok = run(dir, ['recover'], {});
  check('with the lock gone the queue works again', ok.ok);
}

// ═══ 9 · invalid graphs ════════════════════════════════════════════════════
section('9 · malformed task graphs are rejected, not silently accepted');
{
  const bad = [
    ['a missing dependency', [T('A', { dependsOn: ['NOPE'] })], /unknown dependency/],
    ['a dependency cycle', [T('A', { dependsOn: ['B'] }), T('B', { dependsOn: ['A'] })], /cycle/],
    ['a duplicate id', [T('A'), T('A')], /duplicate task id/],
    ['a negative retry budget', [T('A', { maxRetries: -1 })], /maxRetries/],
    ['a non-array dependsOn', [{ ...T('A'), dependsOn: 'A' }], /must be arrays/],
    ['a missing role', [{ ...T('A'), role: undefined }], /role and summary/],
  ];
  for (const [name, tasks, re] of bad) {
    const r = run(sandbox(tasks), ['validate']);
    check(`${name} is rejected`, !r.ok && re.test(r.err), r.err.trim().slice(0, 70));
  }
}

// ═══ 10 · the REAL reconciled queue, not a synthetic one ═══════════════════
// Everything above runs on fixtures. These assertions run against the queue
// that actually ships, because a graph that only validates in a sandbox proves
// nothing about the inventory.
section('10 · the shipped .skills-agent/tasks.json');
{
  const realTasks = JSON.parse(
    fs.readFileSync(path.join(ROOT, '.skills-agent', 'tasks.json'), 'utf8'));
  const ids = realTasks.tasks.map((t) => t.id);

  check('the coordinator validator accepts the shipped queue',
    run(ROOT, ['validate']).ok, `${ids.length} tasks`);
  check('every task id is unique', new Set(ids).size === ids.length);
  check('every dependency resolves to a real task',
    realTasks.tasks.every((t) => (t.dependsOn ?? []).every((d) => ids.includes(d))));
  check('every task states runnerIndependent explicitly — it is what decides '
      + 'whether work can start today',
    realTasks.tasks.every((t) => typeof t.runnerIndependent === 'boolean'));
  check('every task cites at least one authoritative source',
    realTasks.tasks.every((t) => (t.sources ?? []).length > 0 || t.id === 'V5-INF-001'),
    'V5-INF-001 is exempt only because its blocker is an external billing page');
  check('the queue authority names documents, not a phantom register',
    !/V5_WORKSTREAM_REGISTRY/.test(realTasks.policy?.queueAuthority ?? ''),
    `authority=${(realTasks.policy?.queueAuthority ?? '').slice(0, 56)}…`);

  // The authority is the five mutually-referencing Wave 0 deliverables. Three
  // was the previous answer and it was INCOMPLETE — it omitted the authority
  // for owner decisions and for closure evidence, so the queue cited no source
  // for two of the five things it depends on.
  const authorityDocs = String(realTasks.policy?.queueAuthority ?? '')
    .split('+').map((x) => x.trim()).filter(Boolean);
  check('all five Wave 0 deliverables are named as authority',
    authorityDocs.length === 5
      && ['MASTER_REMEDIATION_WAVES', 'RELEASE_GATES', 'MASTER_REMEDIATION_REGISTRY',
          'MASTER_PRODUCT_DECISIONS', 'QA_CLOSURE_STANDARD']
         .every((d) => authorityDocs.some((a) => a.includes(d))),
    `${authorityDocs.length} documents`);
  check('each names what it governs, quoted from its own header',
    Object.keys(realTasks.policy?.authorityScope ?? {}).length === 5,
    Object.keys(realTasks.policy?.authorityScope ?? {}).join(', '));
  check('every authority document exists in this checkout',
    authorityDocs.every((a) => fs.existsSync(path.join(ROOT, a))));
  check('the owner-decision tasks cite the owner-decision authority',
    ['V5-GOV-002', 'V5-GOV-003', 'V5-GOV-004', 'V5-GOV-005'].every((id) =>
      realTasks.tasks.find((t) => t.id === id).sources
        .includes('docs/MASTER_PRODUCT_DECISIONS.md')));
  check('requireAttestedIdentity is OFF with a recorded reason — turning it on '
      + 'with no runner would block all verification',
    realTasks.policy?.requireAttestedIdentity === false
      && !!realTasks.policy?.requireAttestedIdentityNote);

  // Blocked tasks must not be claimable, and that must not come from deleting
  // their dependencies.
  const blockedIds = realTasks.tasks.filter((t) => (t.blockers ?? []).length > 0).map((t) => t.id);
  check('every task carrying a blocker says what would clear it',
    realTasks.tasks.filter((t) => blockedIds.includes(t.id))
      .every((t) => t.blockers.every((b) => b.kind && b.what && b.action)),
    `${blockedIds.length} blocked task(s)`);
  check('V5-AUTO-002 is blocked but KEEPS its dependency — blocked-ness is not '
      + 'manufactured by removing edges',
    realTasks.tasks.find((t) => t.id === 'V5-AUTO-002').dependsOn.includes('V5-AUTO-001'));
}

// ═══ 11 · inventory evidence must exist, not be asserted ═══════════════════
section('11 · inventory evidence validator');
{
  const r = spawnSync(process.execPath,
    [path.join(ROOT, 'scripts', 'skills-agent-inventory-check.mjs')],
    { encoding: 'utf8' });
  check('the shipped inventory passes the evidence validator',
    r.status === 0, (r.stdout || r.stderr).trim().slice(0, 96));
}

// ═══ 12 · migration ↔ wave coverage, reproducible from tracked files ══════
// The tool this exercises replaced a WRONG finding: "51 migrations beyond the
// plan", produced by matching the pre-assignment table with a narrow regex and
// reading absence from that table as absence from the plan. The plan's own
// final row says migrations >= 132 are "assigned at wave entry, never before".
section('12 · migration coverage reconciliation');
{
  const r = spawnSync(process.execPath,
    [path.join(ROOT, 'scripts', 'check-migration-wave-coverage.mjs'), '--json'],
    { encoding: 'utf8' });
  check('the coverage tool runs clean against the tracked tree', r.status === 0,
    (r.stderr || '').trim().slice(0, 80));
  let out = null;
  try { out = JSON.parse(r.stdout); } catch { /* reported below */ }
  check('it emits a machine-readable comparison', !!out && Array.isArray(out.rows),
    out ? `${out.rows.length} rows` : 'unparseable');

  if (out) {
    check('every authored migration is classified — none left unexplained',
      out.summary.unexplained === 0 && out.rows.length === out.summary.authored,
      `authored=${out.summary.authored} unexplained=${out.summary.unexplained}`);
    check('the plan floor is read from the document, not hardcoded as a count',
      out.summary.planFloor === 132 && out.summary.planAssignedRange === '123-131');
    check('the three classes account for every migration exactly once',
      out.summary.preProgramme + out.summary.preAssigned + out.summary.outsideByRule
        === out.summary.authored,
      `${out.summary.preProgramme}+${out.summary.preAssigned}+${out.summary.outsideByRule}`);
    check('the authored sequence is contiguous — Gate 0.9 forbids renumbering to '
        + 'close a gap, so a gap must surface rather than be tidied away',
      out.summary.contiguous === true);
    check('applied status is NOT inferred — it is reported as unestablished for '
        + 'every migration, because tracked files declare intent not outcome',
      out.rows.every((x) => /NOT ESTABLISHED HERE/.test(x.appliedStatus)));
    check('the QA project is confirmed from the manifest itself, not from a name',
      out.summary.qaRef === 'eyqtldjqpgpljlqvpowh', `ref=${out.summary.qaRef}`);
    check('declaration is derived from applied_through, which is a STRING in the '
        + 'manifest and must be coerced',
      out.summary.allDeclared === true && out.summary.appliedThrough === 181);
  }
}

console.log(`\n${'='.repeat(74)}`);
console.log(`Skills-Agent coordinator: ${passed}/${passed + failures.length} passed`);
if (failures.length) {
  console.log('FAILURES:');
  for (const f of failures) console.log(`  x ${f}`);
  process.exit(1);
}
