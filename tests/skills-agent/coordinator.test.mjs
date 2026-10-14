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
// `paths` defaults to a PER-TASK path, not a shared 'x'. It was shared while
// `paths` was a field nothing read; once an implementer lease began reserving
// its paths, every default task conflicted with every other and two existing
// tests failed -- correctly. Those tests are about dependency scheduling and
// independent advancement, never about file contention, so the realistic
// default is one file per task. A test that WANTS contention passes `paths`
// explicitly.
const T = (id, extra = {}) => ({
  id, role: 'implementer', summary: id, dependsOn: [], paths: [`${id}.dart`],
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

  // The queue modelled ONLY infrastructure and governance until Milestone 6 —
  // zero product remediation, against a board carrying ~177 READY_TO_REMEDIATE
  // rows. These five are the wave-level product work at the current frontier.
  const product = ['V5-W2A-001', 'V5-W2B-001', 'V5-SECR-001', 'V5-CON-003', 'V5-W3B-001'];
  check('the product backlog is represented, not just the agent infrastructure',
    product.every((id) => ids.includes(id)), product.join(', '));
  check('each product task names its wave', 
    product.every((id) => !!realTasks.tasks.find((t) => t.id === id).wave));
  check('the Wave 3B-1 task keeps BOTH prerequisite edges the plan names — '
      + 'CON-03 and SEC-R2 — rather than being made startable',
    (() => {
      const d = realTasks.tasks.find((t) => t.id === 'V5-W3B-001').dependsOn;
      return d.includes('V5-CON-003') && d.includes('V5-SECR-001');
    })());
  check('Wave 2B stays sequenced behind 2A, as the plan requires',
    realTasks.tasks.find((t) => t.id === 'V5-W2B-001').dependsOn.includes('V5-W2A-001'));
  // Step 4 gates every row whose §2.1 class demands VERIFIED END-TO-END, and it
  // is NAMED but never DEFINED — the phrase occurs once, in a parenthetical. So
  // the authorization cannot even be requested until the definition exists, and
  // the queue must express that ordering rather than asking for a blank cheque.
  check('the Step 4 definition task exists and the verification task depends ON it',
    ids.includes('V5-GOV-006')
      && realTasks.tasks.find((t) => t.id === 'V5-SECR-001').dependsOn.includes('V5-GOV-006'));
  check('the status-vocabulary ruling is its OWN task, not folded into Step 4 — '
      + 'they are different decisions with different consequences',
    ids.includes('V5-GOV-007')
      && !/status-vocabulary/i.test(JSON.stringify(
           realTasks.tasks.find((t) => t.id === 'V5-SECR-001').blockers)));
  // CORRECTED in Milestone 9. This used to require UIX-1 and M-03 in the summary.
  // They are NOT blocked — §7.18 closed them on 2026-08-28 — so naming them here
  // was asserting a falsehood. The assertion is inverted: they must be ABSENT.
  check('the END-TO-END task names the two rows that are genuinely short of the '
      + 'rung, and no longer claims the two that closed',
    (() => {
      const sum = realTasks.tasks.find((t) => t.id === 'V5-SECR-001').summary;
      return ['SEC-R2', 'SEC-R3'].every((r) => sum.includes(r))
        && !/UIX-1|M-03/.test(sum);
    })());
  check('the promotion candidates whose blockers are already resolved are tracked',
    ids.includes('V5-PROM-001')
      && /SEC-04/.test(JSON.stringify(realTasks.tasks.find((t) => t.id === 'V5-PROM-001'))));

  // V5-SECR-001 USED to belong here. It gained a real edge in Milestone 7 — on
  // V5-GOV-006, because Step 4 cannot be authorized before it is defined — so
  // this now covers the tasks that genuinely have no sequence prerequisite and
  // are held purely by a decision.
  const decisionOnly = realTasks.tasks.filter(
    (t) => (t.dependsOn ?? []).length === 0 && (t.blockers ?? []).length > 0);
  check('every task with NO dependency edge is held by a recorded blocker, not '
      + 'left falsely startable',
    decisionOnly.length > 0
      && decisionOnly.every((t) => t.blockers.every((b) => b.kind && b.what && b.action)),
    `${decisionOnly.length} decision-only task(s): ${decisionOnly.map((t) => t.id).join(', ')}`);
  check('V5-CON-003 remains decision-only — the production column type is not a '
      + 'sequencing problem',
    decisionOnly.some((t) => t.id === 'V5-CON-003'));
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

// ═══ 13 · the Step 4 bar, asserted against the register itself ═════════════
// §2.1 puts SEC-R2 and SEC-R3 in the AI / safety input class — "all five. A
// safety input is never closed on source review" — and VERIFIED END-TO-END is
// Step 4, which "is not authorized to begin". The registry records both rows at
// four of five.
//
// Nothing stopped those rows being promoted anyway. This is that check: if the
// evidence columns change, or either row is moved to VERIFIED_CLOSED while
// END-TO-END is still absent, the build fails and names it.
section('13 · SEC-R2 / SEC-R3 cannot be promoted without the fifth state');
{
  const reg = fs.readFileSync(
    path.join(ROOT, 'docs', 'MASTER_REMEDIATION_REGISTRY.md'), 'utf8');
  const flat = reg.replace(/\s+/g, ' ');

  // UIX-1 and M-03 are NOT Step-4-blocked. §7.18 records them VERIFIED_CLOSED on
  // VERIFIED END-TO-END at CI run #49 (2026-08-28), and §7.x lines :2727/:2739
  // saying otherwise are a dated EARLIER checkpoint. A prior milestone cited
  // those lines as current state and got it wrong; this pins the correction.
  check('§7.18 still records UIX-1 / M-03 as VERIFIED END-TO-END and closed',
    flat.includes('UIX-1` / `M-03` VERIFIED END-TO-END and `VERIFIED_CLOSED`'),
    'registry:2940');
  check('M-03 still carries its VERIFIED_CLOSED date',
    /M-03`[^\n]*VERIFIED_CLOSED` 2026-08-28/.test(reg), 'registry:1060');
  check('and the queue no longer claims UIX-1 / M-03 are Step-4-blocked',
    !/UIX-1|M-03/.test(JSON.parse(fs.readFileSync(
      path.join(ROOT, '.skills-agent', 'tasks.json'), 'utf8'))
      .tasks.find((t) => t.id === 'V5-SECR-001').summary));

  // The per-row ruling pattern that actually produced that rung, twice.
  check('§7.13\'s confined-ruling pattern is still recorded — it is the route '
      + 'the precedent used, and C1 depends on it',
    flat.includes('explicitly confined') && flat.includes('extends §7.13'),
    'registry §7.13 / §7.18');

  for (const row of ['SEC-R2', 'SEC-R3']) {
    const line = reg.split('\n').find((l) => l.startsWith(`| **${row}** |`));
    check(`${row}'s evidence row is still present in the register`, !!line);
    if (!line) continue;
    check(`${row} still records VERIFIED END-TO-END as absent`,
      /❌\s*\*\*absent\*\*/.test(line), line.trim().slice(0, 86));
    check(`${row} still reads "4 of 5 present" — a promotion to 5 of 5 without `
        + `Step 4 would be a false evidence claim`,
      /4 of 5 present/.test(line));
  }

  // The structural statement, quoted. If this sentence is ever removed the
  // programme-wide consequence has changed and this test should be revisited
  // deliberately rather than silently.
  check('the register still states the consequence programme-wide, not per-row',
    flat.includes('no safety finding in this programme can reach'),
    'registry:1805');
  check('Step 4 is still recorded as unauthorized',
    /Step 4 is not authorized/.test(reg));

  // And the queue must not have quietly made the dependent task startable.
  const q = JSON.parse(fs.readFileSync(
    path.join(ROOT, '.skills-agent', 'tasks.json'), 'utf8'));
  const secr = q.tasks.find((t) => t.id === 'V5-SECR-001');
  // Also corrected: the blocker no longer has to say "Step 4" in its `what`,
  // because the route question is now C1-or-C2 and C1 does not involve the
  // phase at all. What must survive is that it is an OWNER blocker naming the
  // missing rung, with an action that points at the route decision.
  check('the dependent queue task still carries an owner blocker for the missing '
      + 'rung, pointing at the route decision',
    (secr.blockers ?? []).some((b) =>
      b.kind === 'owner'
      && /rung|END-TO-END/i.test(b.what)
      && /V5-GOV-006|C1|C2/.test(b.action)));
}

// ═══ 14 · the closure candidates' evidence claims, re-derived ══════════════
// Both claims rest on strings in the register. If those strings move, the
// matrices in V5_CLOSURE_CANDIDATES_AND_STEP4_PROPOSAL.md become stale
// assertions about a document that no longer says that — the exact decay this
// programme keeps finding. So they are re-derived here rather than trusted.
section('14 · SEC-04 / ENV-6 closure-candidate evidence');
{
  const reg = fs.readFileSync(
    path.join(ROOT, 'docs', 'MASTER_REMEDIATION_REGISTRY.md'), 'utf8');
  const flat = reg.replace(/\s+/g, ' ');

  // SEC-04 — the three requirements its own clause names.
  check('SEC-04\'s missing-evidence clause still names all three requirements',
    flat.includes('needs migration 124 + I-MIG-03 class guard + live 403 probe'),
    'registry:1585');
  check('requirement 1 — migration 124 exists',
    fs.existsSync(path.join(ROOT, 'supabase', 'migrations',
      '124_wave_2a_security_regressions.sql')));
  check('requirement 2 — the I-MIG-03 class guard exists AND is wired into CI',
    fs.existsSync(path.join(ROOT, 'supabase', 'tests', 'security',
      'migration-durability-guard.mjs'))
      && fs.readFileSync(path.join(ROOT, '.github', 'workflows', 'ci.yml'), 'utf8')
           .includes('migration-durability-guard'));
  check('requirement 3 — d04 carries the live authorization-error probe',
    fs.readFileSync(path.join(ROOT, 'supabase', 'tests', 'security',
      'd04-rpc-execution.mjs'), 'utf8')
      .includes('refuses an unauthorized caller with the AUTHORIZATION error'));
  check('the owner ruling for reading B is still recorded — SEC-04 needs the '
      + 'class guard RUNNING, not I-MIG-03\'s own closure',
    flat.includes('ruled on 2026-08-25 for **reading B**'), 'registry:1681-1686');
  check('SEC-04 is still recorded OPEN, so the ladder question is still live',
    /SEC-04[^\n]*unchanged, OPEN|unchanged, OPEN[^\n]*SEC-04/.test(reg)
      || flat.includes('SEC-04 / SEC-R1 / SEC-R2 / SEC-R3 / F-J-01 — unchanged, OPEN'),
    'registry:1719');

  // ENV-6 — one stated condition.
  check('ENV-6\'s criterion still reads "closes at the first PR"',
    flat.includes('closes at the first PR'), 'registry:1594');
  // The owner's ruling (§7.25, 2026-10-12) and the §6 row now agree. Milestone
  // 10B reconciled the authoritative row; these assertions hold that agreement
  // and, just as importantly, hold that the obsolete claim is presented as
  // HISTORY rather than as current fact.
  check('the owner\'s ENV-6 ruling is recorded in the register',
    flat.includes('ENV-6 is **VERIFIED_CLOSED as of 2026-10-12**')
      && flat.includes('interpretation A adopted'),
    'registry §7.25');

  const env6Section = reg.slice(reg.indexOf('### ENV-6 · No CI'),
                                reg.indexOf('### ENV-7'));
  check('the AUTHORITATIVE §6 ENV-6 row now reads VERIFIED_CLOSED, citing §7.25',
    /\*\*`VERIFIED_CLOSED`\*\*/.test(env6Section)
      && /§7\.25 Ruling A/.test(env6Section),
    env6Section.split('\n')[1].slice(0, 76));
  check('…and carries the actual CI evidence, not a bare status change',
    /38334189040/.test(env6Section) && /7 of 7 jobs/.test(env6Section));
  // Three plain conditions, not one clever one. The earlier version of this
  // assertion carried a double negative with a `=== false` clause and failed on
  // its own construction rather than on the register's content.
  const env6Flat = env6Section.replace(/\s+/g, ' ');
  check('the obsolete "not yet executed" claim survives only inside an '
      + 'explicitly HISTORICAL note — never as a current claim',
    env6Flat.includes('not yet executed')
      && env6Flat.includes('Historical, 2026-08-24 — superseded')
      && env6Flat.includes('That statement was true then and is not true now'),
    'obsolete claim present, labelled historical, and explicitly dated');

  check('the row no longer asserts it "cannot advance past REMEDIATED" as '
      + 'current fact',
    !/·\s*`REMEDIATED`\s*\*\(2026-08-24/.test(env6Section));

  // History preserved: the dated Wave 1 checkpoint table is NOT rewritten.
  check('the dated Wave 1 checkpoint table still records REMEDIATED — historical '
      + 'entries were preserved, not edited to fit',
    /\| ENV-6 \| 4 \| `REMEDIATED`/.test(reg), 'registry Wave 1 batch table');

  // §7.25's three rulings, pinned. The owner recorded them; a later edit that
  // dropped one would change what this programme is allowed to do.
  check('§7.25 records C1 as a PER-ROW route with no blanket authorization',
    flat.includes('per-row acceptance route selected; no blanket Step 4 authorization'),
    'registry §7.25 Ruling B');
  check('§7.25 keeps SEC-04 OPEN and says so explicitly',
    flat.includes('SEC-04 remains **OPEN**')
      && flat.includes('No\nSEC-04 status promotion is authorized or performed by this entry'.replace('\n', ' ')),
    'registry §7.25');
  check('§7.25 preserves the Step 4 authority conflict rather than reconciling it',
    flat.includes('is in tension with the per-row precedent in §7.18'),
    'registry §7.25');

  // And the proposal must not have been quietly applied.
  check('the proposal document exists and states that nothing was applied',
    fs.readFileSync(path.join(ROOT, 'docs',
      'V5_CLOSURE_CANDIDATES_AND_STEP4_PROPOSAL.md'), 'utf8')
      .includes('Nothing in this document has been applied'));
}

// ═══ 15 · SEC-R3's end-to-end prerequisite, tracked mechanically ═══════════
// SEC-R2 and SEC-R3 are NOT symmetric, and the asymmetry is the finding.
//
// SEC-R2's failure leg is already correct in the product: _finish() refuses on
// a null session and its catch leaves the intake "NOT marked complete".
//
// SEC-R3's is not. Every call site to the three affected functions swallows a
// failure into a benign default — `catch (_) { return null; }` — so a 22P02
// from the rule accumulator becomes `null` and the surface renders "no data".
// §2.1 requires "the correct FAILURE behaviour", and Wave 3B-1 names the fix
// ("refuse rather than degrade"), which is blocked.
//
// This is offline and reads source only: no QA, no network, no probe. It exists
// so the prerequisite cannot be quietly lost, and so a later claim that SEC-R3
// is end-to-end verified while the swallows remain fails loudly.
section('15 · SEC-R3 failure-leg prerequisite (offline source check)');
{
  const svc = fs.readFileSync(path.join(ROOT, 'apps', 'mobile', 'lib',
    'features', 'coach', 'data', 'coach_program_service.dart'), 'utf8');

  // STRENGTHENED in Milestone 12: the three SEC-R3 methods are named, rather
  // than a bare count being pinned. A count would be satisfied by any eleven
  // swallows anywhere in the file; what matters is that THESE methods still
  // convert a thrown RPC error into ordinary absence.
  //
  // Each is checked by its own enclosing method so the guard says which site
  // regressed. (The earlier attribution attempt used `Future<[^>]+>`, which
  // stops at the first `>` and so missed `Future<Map<String, dynamic>?>`
  // declarations entirely — the count was right and the names were wrong.)
  const methodSwallows = (name) => {
    const i = svc.indexOf(`> ${name}(`) >= 0 ? svc.indexOf(`> ${name}(`) : svc.indexOf(`${name}(`);
    if (i < 0) return null;
    const body = svc.slice(i, i + 900);
    return /catch \(_\) \{ return (?:null|false); \}/.test(body);
  };
  for (const m of ['predictClient', 'evaluateWeek', 'regenerateProgram']) {
    check(`SEC-R3 prerequisite: ${m} still converts a thrown RPC error into `
        + `ordinary absence — recorded as the BLOCKER, not an acceptable state`,
      methodSwallows(m) === true,
      'fix belongs to Wave 3B-4 (service-layer sweep), which follows 3B-1; '
      + '3B-1 depends on CON-03 and SEC-R2');
  }

  // The contract to adopt already exists and is deliberately unwired. If
  // reportFailure gains call sites, 3B-4 has begun and these assertions should
  // be revisited on purpose rather than quietly inverted.
  const sinkUsers = (fs.readFileSync(path.join(ROOT, 'apps', 'mobile', 'lib',
    'core', 'observability', 'app_failure.dart'), 'utf8').length > 0)
    && spawnSync('grep', ['-rl', 'reportFailure(',
        path.join(ROOT, 'apps', 'mobile', 'lib')], { encoding: 'utf8' })
       .stdout.split('\n').filter((f) => f && !f.includes('core/observability')).length;
  check('3B-0\'s AppFailure sink exists and is still UNWIRED — so 3B-4 has not '
      + 'silently begun',
    sinkUsers === 0, `${sinkUsers} call site(s) outside the sink`);

  // The product path must keep going through the WRAPPERS. If a call site were
  // switched to an *_engine name, authorization would leave §2.1's chain and
  // any future probe would be measuring the wrong thing.
  for (const fn of ['predict_client', 'evaluate_week']) {
    check(`${fn} is called by its PUBLIC wrapper name, so authorization stays `
        + `in the chain`,
      svc.includes(`rpc('${fn}'`) && !svc.includes(`rpc('${fn}_engine'`));
  }

  // And the contract suite's own limitation, quoted from the file, so nobody
  // later mistakes it for end-to-end evidence.
  const fj07 = fs.readFileSync(path.join(ROOT, 'supabase', 'tests', 'ai',
    'fj07-rule-accumulator-contract.sql'), 'utf8').replace(/\s+/g, ' ');
  check('fj07 still records that it calls the ENGINES and skips authorization — '
      + 'so it cannot serve as the end-to-end rung',
    fj07.includes('calls the ENGINES')
      && fj07.includes('deliberately not re-tested here'),
    'fj07 header');

  // Neither row may be presented as having the fifth state by this work.
  const matrices = fs.readFileSync(path.join(ROOT, 'docs',
    'V5_SECR2_SECR3_E2E_EVIDENCE_MATRICES.md'), 'utf8');
  check('the matrices state plainly that neither finding is promoted',
    /Neither finding is promoted/.test(matrices)
      && /neither has its fifth state/.test(matrices));
}

// ═══ 16 · CON-03's authority, pinned to the source that governs it ═════════
// I classified CON-03 as production-blocked across four milestones, from the
// registry's one-line "prod type unknown" summary, without consulting
// MASTER_PRODUCT_DECISIONS.md — the document this programme's own queue names
// as the authority for owner decisions. PD-A22 says the opposite.
//
// These assertions hold the correction in place: if PD-A22's Proceed? column
// or the corroborating wave text changes, the determination becomes stale and
// fails here rather than silently misleading a later reader.
section('16 · CON-03 authority (PD-A22 route b)');
{
  const pd = fs.readFileSync(path.join(ROOT, 'docs',
    'MASTER_PRODUCT_DECISIONS.md'), 'utf8');
  const pdFlat = pd.replace(/\s+/g, ' ');

  check('PD-A22 still authorizes proceeding via option (b) — converge from '
      + 'either type WITHOUT inspecting production',
    pdFlat.includes('write the forward migration to converge from either starting type without inspecting')
      && /PD-A22[\s\S]{0,1400}?\*\*Yes\*\* — via \(b\)/.test(pdFlat),
    'MASTER_PRODUCT_DECISIONS.md:136');
  check('…and still records that (a) is for the ROLLOUT plan, not QA work',
    pdFlat.includes('a prerequisite for the production rollout plan, not for QA work'));
  check('the document still states nothing in it is decided — so Proceed? is '
      + 'permission to work, NOT an answered decision',
    pdFlat.includes('Nothing in this document is decided'));
  check('PD-A22 is still NOT in the already-closed list — the decision remains '
      + 'open even though proceeding is authorized',
    !/Decisions already closed[\s\S]{0,900}?PD-A22/.test(pdFlat));

  const waves = fs.readFileSync(path.join(ROOT, 'docs',
    'MASTER_REMEDIATION_WAVES.md'), 'utf8').replace(/\s+/g, ' ');
  check('the wave plan still requires convergence from EITHER starting type',
    waves.includes('must converge from **either** starting type because production')
      || waves.includes('converge from **either** starting type'),
    'MASTER_REMEDIATION_WAVES.md:335');

  // Production stays out of reach: the corroborating source must keep saying so.
  const qa = fs.readFileSync(path.join(ROOT, 'docs',
    'MASTER_QA_RECONCILIATION.md'), 'utf8').replace(/\s+/g, ' ');
  check('Q-6 still records that production will NOT be inspected without '
      + 'explicit authorization',
    qa.includes('Production was not inspected and will not be without explicit authorization'),
    'MASTER_QA_RECONCILIATION.md:513');

  // And my own artifact must carry the correction, not the old claim.
  const q = JSON.parse(fs.readFileSync(path.join(ROOT, '.skills-agent',
    'tasks.json'), 'utf8'));
  const con = q.tasks.find((t) => t.id === 'V5-CON-003');
  check('the queue no longer classifies CON-03 as governance/production-blocked',
    con.blockers.every((b) => b.kind !== 'governance')
      && /CORRECTED/.test(JSON.stringify(con.blockers)),
    `kind=${con.blockers.map((b) => b.kind).join(',')}`);
}

// ── CON-03 forward-migration design: the facts the design rests on ──────────
//
// Milestone 14. Every one of these is a repository-source fact that, if it
// drifted, would silently invalidate V5_CON03_FORWARD_MIGRATION_DESIGN.md.
{
  const intake = fs.readFileSync(path.join(ROOT, 'apps', 'mobile', 'lib',
    'features', 'onboarding', 'domain', 'intake_data.dart'), 'utf8');

  // §1 — the asymmetry IS the defect. Both halves must be pinned: if either
  // serializer is changed, CON-03 is either fixed or changed shape, and the
  // design document must be re-read rather than trusted.
  check('toSupabasePartial still sends dietary_restrictions as an ARRAY',
    /m\['dietary_restrictions'\]\s*=\s*dietaryRestrictions\.toList\(\)/.test(intake),
    'intake_data.dart:213 — the per-step write that fails against a text column');
  check('toSupabase still sends dietary_restrictions as a JOINED STRING',
    /'dietary_restrictions':\s*dietaryRestrictions\.join\(','\)/.test(intake),
    'intake_data.dart:252');

  // §1.1 — scope is ONE column. The siblings are consistent; if one of them
  // ever gains a .toList() the finding widens and §1.1's table is wrong.
  for (const sib of ['medical_conditions', 'injury_locations']) {
    const partial = new RegExp(`m\\['${sib}'\\]\\s*=\\s*\\w+\\.join\\(','\\)`);
    const final_ = new RegExp(`'${sib}':\\s*\\w+\\.join\\(','\\)`);
    check(`${sib} comma-joins in BOTH serializers (so CON-03 stays one column)`,
      partial.test(intake) && final_.test(intake),
      'the premise of §1.1: only dietary_restrictions disagrees');
    check(`${sib} is never sent as an array`,
      !new RegExp(`m\\['${sib}'\\]\\s*=\\s*\\w+\\.toList\\(\\)`).test(intake),
      `a .toList() here would widen CON-03 beyond its finding`);
  }

  // §3.1 — the conversion expression is derived from _splitList. No trim and
  // no empty-filtering is not an oversight; it is the semantics the SQL must
  // reproduce. A trim added here would make §3.2's CASE expression wrong.
  check('_splitList maps empty/null to [] and otherwise splits on comma only',
    /if \(raw == null \|\| raw\.isEmpty\) return \[\];\s*return raw\.split\(','\);/
      .test(intake),
    'intake_data.dart:123-126 — delimiter and edge case the migration mirrors');
  const splitBody = intake.slice(intake.indexOf('static List<String> _splitList'));
  check('_splitList does NOT trim or filter (so the SQL must not either)',
    !/_splitList[\s\S]{0,200}(\.trim\(\)|where\()/.test(splitBody.slice(0, 220)),
    'a trim/filter here would silently change what stored rows mean');

  // §3.1 — the read path already converges from both types. This is why the
  // design says no client read change is needed under either target.
  check('the read path handles BOTH List and String (target-independent)',
    /d\['dietary_restrictions'\] is List/.test(intake)
      && /_splitList\(d\['dietary_restrictions'\] as String\?\)/.test(intake),
    'intake_data.dart:168-170');

  // §3.4 — "first column type change in the project's history". A single
  // ALTER COLUMN ... TYPE appearing anywhere falsifies that claim.
  const migDir = path.join(ROOT, 'supabase', 'migrations');
  const migs = fs.readdirSync(migDir).filter((f) => f.endsWith('.sql'));
  check('the migration corpus is large enough for this sweep to mean something',
    migs.length > 150, `${migs.length} migrations scanned`);
  const typeChanges = migs.filter((f) =>
    /ALTER\s+COLUMN\s+\w+\s+(SET\s+DATA\s+)?TYPE/i
      .test(fs.readFileSync(path.join(migDir, f), 'utf8')));
  check('ZERO committed migrations change a column type (§3.4)',
    typeChanges.length === 0,
    typeChanges.length ? `found in ${typeChanges.join(', ')}` : 'no precedent exists');

  // §3.4 — but text[] columns are conventional, which is the house style a
  // text[] target would follow. Positive control for the sweep above: this
  // proves the corpus IS being read, so the zero result is real.
  const arrayCols = migs.filter((f) =>
    /\w+\s+text\[\]/i.test(fs.readFileSync(path.join(migDir, f), 'utf8')));
  check('text[] columns DO exist (positive control + §3.4 house style)',
    arrayCols.length > 0, `${arrayCols.length} migration files use text[]`);

  // §3.2 — the starting state from repository history.
  const m013 = fs.readFileSync(path.join(migDir, '013_health_assessment.sql'), 'utf8');
  check('013 declares the column TEXT NOT NULL DEFAULT \'\' (why the \'\' guard matters)',
    /dietary_restrictions\s+TEXT\s+NOT NULL DEFAULT ''/.test(m013),
    '013_health_assessment.sql:15');

  // §4.2(3) — the hard cost of the text[] target. If 141 ever declares the
  // column as text[], that drop/recreate has happened and §4.2 is stale.
  const m141 = fs.readFileSync(path.join(migDir,
    '141_assessment_access_sleep_hours_type.sql'), 'utf8');
  check('the LIVE get_client_assessment() still declares dietary_restrictions text',
    /dietary_restrictions\s+text,/.test(m141),
    '141:69 — a text[] column would make this 42804 on every call');
  check('141 records that a return type cannot be changed by CREATE OR REPLACE',
    /return type cannot be changed by CREATE OR REPLACE/i.test(m141)
      || /cannot be changed by `CREATE OR REPLACE`/.test(m141),
    'the precedent §4.2(3) cites for the third drop/recreate');

  // §2 — the blocker. No target may be asserted as decided.
  const pd = fs.readFileSync(path.join(ROOT, 'docs',
    'MASTER_PRODUCT_DECISIONS.md'), 'utf8');
  check('PD-A22 authorizes route (b) and nothing more',
    /PD-A22/.test(pd) && /\*\*Yes\*\* — via \(b\)/.test(pd),
    'the authorization the design operates under');

  // §7 / the brief — a design proposal, NOT an executable migration. The
  // absence of a new migration file is itself the deliverable's boundary.
  check('no CON-03 migration file was created (execution boundary held)',
    !migs.some((f) => /dietary|con.?03/i.test(f)),
    'creating a migration file would not be permission to execute it');

  const design = fs.readFileSync(path.join(ROOT, 'docs',
    'V5_CON03_FORWARD_MIGRATION_DESIGN.md'), 'utf8');
  check('the design labels itself a proposal and disclaims execution',
    /PROPOSAL, NOT EXECUTABLE/.test(design)
      && /Nothing in this document has been applied to any database/.test(design),
    'so it cannot be mistaken for an applied change');
  check('the design records the offline-verification failure, not a success',
    /NOT POSSIBLE/.test(design) && /was not found/.test(design),
    '§5 — libpq ships initdb/pg_ctl without the postgres server');
}

// ── the offline harness must not claim a server it does not have ───────────
//
// Milestone 14 found this the hard way: libpq ships initdb/pg_ctl, `--version`
// answers 18.6 from them, and the old guard passed on a runner with no server
// at all -- then initdb died. Verified as a pair on this runner: old guard
// reached `say "postgres: ..."`, new guard dies naming the cause.
{
  const nc = fs.readFileSync(path.join(ROOT, 'supabase', 'scripts',
    'negative-control.sh'), 'utf8');
  check('find_pg requires the postgres SERVER binary, not just the wrappers',
    /-x "\$pgbin\/postgres"/.test(nc) && /command -v postgres/.test(nc),
    'a client-only install (Homebrew libpq) must be rejected up front');
  check('…and says WHY, so the next runner failure is not mysterious',
    /client-only install/.test(nc) && /Install a full postgresql server package/.test(nc),
    'the old message named the condition but could not detect it');
  // My first version of this asserted the script UNSETS the credential vars.
  // It does not -- it REFUSES TO RUN if any is set, which is strictly stronger
  // (fail closed, no silent sanitising). Assert the real, stronger guarantee.
  check('the harness still REFUSES to run when any credential var is set',
    /assert_no_credentials/.test(nc)
      && /is set in this environment/.test(nc)
      && /refuses rather than proceeding/.test(nc),
    'fail-closed, not unset — hardening find_pg must not have weakened this');
  check('…and still pins the target host to loopback',
    /PGHOST_=127\.0\.0\.1/.test(nc)
      && /the target host is not loopback/.test(nc),
    'negative-control.sh:47,86-87');
}

// ── CON-03 canonical storage contract (Milestone 15) ───────────────────────
//
// The memo's recommendation rests on a nine-artifact evidence split and on the
// value domain being closed. Both are repository facts that can drift.
{
  const R = (...p) => fs.readFileSync(path.join(ROOT, ...p), 'utf8');
  const migDir = path.join(ROOT, 'supabase', 'migrations');

  // §2 — the text[] intent is systemic, not one comment. The seed is the
  // artifact that disproved Milestone 14's "copied comment" framing. If it is
  // ever corrected, the memo's §2 table and the design's §8 go stale.
  const seed = R('supabase', 'seeds', 'test_accounts.sql');
  check('the seed still inserts ARRAY[]::text[] into dietary_restrictions',
    /dietary_restrictions/.test(seed) && /ARRAY\[\]::text\[\]/.test(seed),
    'seeds/test_accounts.sql:156 — a committed artifact assuming text[]');
  check('…and the same seed uses ARRAY[] correctly for real text[] columns',
    /ARRAY\['Fat Loss'/.test(seed) || /ARRAY\['NASM-CPT'/.test(seed),
    ':120-121 — so the author knew the idiom; this one column is the outlier');

  // …and it is still unexercised, which is why it has never failed.
  const refs = [];
  for (const f of ['package.json', 'Makefile']) {
    const fp = path.join(ROOT, f);
    if (fs.existsSync(fp) && /test_accounts/.test(fs.readFileSync(fp, 'utf8'))) refs.push(f);
  }
  for (const dir of [['.github'], ['supabase', 'scripts'], ['scripts']]) {
    const dp = path.join(ROOT, ...dir);
    if (!fs.existsSync(dp)) continue;
    const walk = (d) => fs.readdirSync(d, { withFileTypes: true }).flatMap((e) =>
      e.isDirectory() ? walk(path.join(d, e.name)) : [path.join(d, e.name)]);
    for (const f of walk(dp)) {
      try { if (/test_accounts/.test(fs.readFileSync(f, 'utf8'))) refs.push(f); } catch {}
    }
  }
  check('the seed is still referenced by no runner (why the array never failed)',
    refs.length === 0, refs.length ? `now referenced by ${refs.join(', ')}` : 'unexercised');

  // §2.1 — the out-of-band channel declares TEXT. Evidence about the channel,
  // NOT about production. The assertion is deliberately about the FILE only.
  const remote = R('supabase', 'APPLY_TO_REMOTE.sql');
  check('APPLY_TO_REMOTE.sql still declares the column TEXT NOT NULL DEFAULT \'\'',
    /dietary_restrictions\s+TEXT\s+NOT NULL DEFAULT ''/.test(remote),
    ':32 — the committed out-of-band channel; proves nothing about prod');
  check('…and is still an ADD COLUMN IF NOT EXISTS (so it cannot retype anything)',
    /ADD COLUMN IF NOT EXISTS dietary_restrictions/.test(remote),
    'the reason §2.1 is labelled inference and Q-6 stands');

  // §1.1 — no governing document answers the question, so §0.2's
  // "already answered → a finding, not a decision" path does not apply.
  for (const g of ['product-bible.md', 'decision-log.md', 'WORKOUT_DOMAIN_CONTRACT.md']) {
    check(`${g} still says nothing about dietary restrictions`,
      !/dietar/i.test(R('docs', g)),
      'if this ever changes, the decision may already be answered');
  }

  // §4 — losslessness is a property of the CLOSED SET. These are the two
  // facts that make it true; either one drifting silently breaks Option A.
  const flow = R('apps', 'mobile', 'lib', 'features', 'onboarding',
    'presentation', 'intake_flow_screen.dart');
  const chips = flow.match(/static const _restrictions = \[([\s\S]*?)\];/);
  check('the restriction vocabulary is still a hard-coded closed list',
    !!chips, 'intake_flow_screen.dart:5734-5737');
  const values = chips ? [...chips[1].matchAll(/'([^']*)'/g)].map((m) => m[1]) : [];
  check('…of nine values, none of which contains the delimiter',
    values.length === 9 && values.every((v) => !v.includes(',')),
    `${values.length} values: ${values.join(' | ')}`);
  check('…and selection cannot produce duplicates',
    /_selected\.contains\(r\) \? _selected\.remove\(r\) : _selected\.add\(r\)/.test(flow),
    '_toggle at :5749-5754 — so ordering/duplicate semantics are decidable');

  // The only TextField on that page must stay bound to allergies, not
  // restrictions. A free-text restriction field is exactly what breaks §4.
  check('the restrictions page has no free-text field for RESTRICTIONS',
    /_allergyCtrl/.test(flow)
      && !/onChanged:[^\n]*dietaryRestrictions\s*=\s*[^\n]*Ctrl\.text/.test(flow),
    'the lone TextField writes foodAllergies, a separate unsplit scalar');

  // §3 — Option B's cost. No application caller; one exerciser.
  const appDirs = [path.join(ROOT, 'apps')];
  let rpcCallSites = 0;
  const walkApp = (d) => fs.existsSync(d) ? fs.readdirSync(d, { withFileTypes: true })
    .flatMap((e) => e.isDirectory() ? walkApp(path.join(d, e.name)) : [path.join(d, e.name)]) : [];
  for (const f of appDirs.flatMap(walkApp)) {
    if (!/\.(dart|ts)$/.test(f) || /[/\\]test[/\\]/.test(f)) continue;
    if (/rpc\(\s*['"]get_client_assessment/.test(fs.readFileSync(f, 'utf8'))) rpcCallSites++;
  }
  check('get_client_assessment still has NO application call site',
    rpcCallSites === 0,
    'so Option B\'s 42804 breaks the d09 live suite, not the app');
  check('…and d09 is still its exerciser',
    fs.existsSync(path.join(ROOT, 'supabase', 'tests', 'security',
      'd09-assessment-access.mjs')),
    'supabase/tests/security/d09-assessment-access.mjs');
  const m141 = R('supabase', 'migrations', '141_assessment_access_sleep_hours_type.sql');
  check('the three grants Option B would have to re-issue are still there',
    (m141.match(/get_client_assessment\(uuid\)/g) || []).length >= 3,
    '141:135-137 — REVOKE PUBLIC, REVOKE anon, GRANT authenticated');

  // WAVES states two different parallelisms. Pin BOTH, so the inconsistency
  // cannot be silently "fixed" in one place and leave my correction wrong.
  const waves = R('docs', 'MASTER_REMEDIATION_WAVES.md');
  check('WAVES still contains the spine {3B-2 ∥ 3B-3}',
    /3B-0 → 3B-1 → \{3B-2 ∥ 3B-3\} → 3B-4 → 3B-5/.test(waves), 'WAVES:301');
  check('WAVES still ALSO contains the 3B-2/3B-4 disjointness prose',
    /the sites inside 3B-2 and 3B-4 touch disjoint service files/.test(waves),
    'WAVES:300 — the outlier my earlier artifact cited; reported, not resolved');
  check('3B-1 still depends on CON-03 AND SEC-R2',
    /Depends on CON-03[\s\S]{0,160}SEC-R2/.test(waves), 'WAVES:287-288');

  // §9 — the governance boundary. The memo must be PENDING, and the
  // source-of-truth decisions document must be untouched by it.
  const memo = R('docs', 'V5_CON03_STORAGE_CONTRACT_DECISION_MEMO.md');
  // Flattened: the disclaimer wraps across a line break, and a single-line
  // regex silently missed it -- the same wrap that hid "End-to-End Product
  // Verification" from a grep earlier in this programme.
  const memoFlat = memo.replace(/\s+/g, ' ');
  check('the memo declares itself PENDING, not requested and not approved',
    /PENDING — NOT REQUESTED, NOT APPROVED/.test(memoFlat)
      && /has NOT been requested, received, or approved/.test(memoFlat),
    'a recommendation must never read as consent');
  check('the memo states it does not modify MASTER_PRODUCT_DECISIONS.md',
    /is \*\*not modified by this memo\.\*\*/.test(memo), '§preamble');
  const pd = R('docs', 'MASTER_PRODUCT_DECISIONS.md');
  check('MASTER_PRODUCT_DECISIONS.md still says nothing in it is decided',
    /\*\*Nothing in this document is decided\.\*\*/.test(pd),
    'the row was not flipped to ANSWERED');
  check('…and PD-A22 is still not recorded as ANSWERED',
    !/PD-A22[^\n]*ANSWERED/.test(pd) && !/\*\*`PD-A22` is `ANSWERED`\*\*/.test(pd),
    'only PD-A05 and PD-A23 carry ANSWERED amendments');
  check('no CON-03 migration file exists (still design-only)',
    !fs.readdirSync(migDir).some((f) => /dietary|con.?03/i.test(f)),
    'the decision gates implementation');
}

// ── CON-03 decision state and the two vocabularies (Milestone 16) ──────────
//
// Milestone 15 cited the workstream REPORT for the meal-plan vocabulary. These
// assert the SOURCE, so the memo's §4.1 table cannot drift from the widgets.
{
  const R = (...p) => fs.readFileSync(path.join(ROOT, ...p), 'utf8');

  const intake = R('apps', 'mobile', 'lib', 'features', 'onboarding',
    'presentation', 'intake_flow_screen.dart');
  const meal = R('apps', 'mobile', 'lib', 'features', 'ai_nutrition',
    'presentation', 'meal_plan_screen.dart');

  const listOf = (src, re) => {
    const m = src.match(re);
    return m ? [...m[1].matchAll(/'([^']*)'/g)].map((x) => x[1]) : null;
  };
  const a = listOf(intake, /static const _restrictions = \[([\s\S]*?)\];/);
  // The meal-plan list is asserted by its exact literal below rather than
  // parsed: it has no named constant to anchor a parse on, and a parse that
  // silently returned null would make the comparisons pass vacuously.

  check('intake still declares exactly nine restriction values',
    a && a.length === 9, a ? a.join(' | ') : 'list not found');
  check('the meal-plan screen declares its own separate vocabulary',
    /'Vegetarian', 'Vegan', 'Gluten-Free', 'Dairy-Free', 'Nut-Free', 'Halal'/.test(meal),
    'meal_plan_screen.dart:27 — six values, verified from source');

  // The scope divergence, which is the part that matters to the owner.
  check('Nut-Free is in the meal-plan list but NOT in intake\'s',
    /'Nut-Free'/.test(meal) && a && !a.includes('Nut-Free'),
    'an allergen merged into restrictions; intake keeps allergens in food_allergies');
  check('only three values are spelled identically in both',
    a && ['Vegetarian', 'Vegan', 'Halal'].every((v) => a.includes(v)
      && new RegExp(`'${v}'`).test(meal))
      && a.includes('Gluten Free') && /'Gluten-Free'/.test(meal)
      && a.includes('Dairy Free') && /'Dairy-Free'/.test(meal),
    'the hyphenation split on Gluten/Dairy is real, in both directions');

  // Still display-only. If this ever writes, the collision becomes data.
  const mealWrites = /_restrictions[\s\S]{0,120}?(upsert|insert|update)\(/.test(meal)
    || /dietary_restrictions/.test(meal);
  check('the meal-plan list is still transient (no DB write, no column reference)',
    !mealWrites,
    'meal_plan_screen.dart:24 — so the divergence is display-only until E\'s fix #1');

  // Nothing enforces the closed domain. This is what makes CON-03-COMMA a
  // real decision rather than a formality.
  const migDir = path.join(ROOT, 'supabase', 'migrations');
  const constrained = fs.readdirSync(migDir).filter((f) => f.endsWith('.sql'))
    .filter((f) => /dietary_restrictions[^;]*(CHECK|ENUM)/i
      .test(fs.readFileSync(path.join(migDir, f), 'utf8')));
  check('NO migration constrains the column\'s values (no CHECK, no enum)',
    constrained.length === 0,
    constrained.length ? `constrained by ${constrained.join(', ')}`
      : 'the closed domain is one widget\'s list, enforced nowhere');

  // Decision state: still pending. These must fail the moment an owner answers,
  // so the memo cannot keep claiming "pending" after the fact.
  const pd = R('docs', 'MASTER_PRODUCT_DECISIONS.md');
  const answered = [...pd.matchAll(/\*\*`(PD-A\d+)` is `ANSWERED`\*\*/g)].map((m) => m[1]);
  check('exactly PD-A05 and PD-A23 are ANSWERED — no more, no fewer',
    answered.length === 2 && answered.includes('PD-A05') && answered.includes('PD-A23'),
    `ANSWERED: ${answered.join(', ') || 'none found'}`);
  check('decision-log.md still records no CON-03 / dietary answer',
    !/dietar|CON-03/i.test(R('docs', 'decision-log.md')),
    '§2 names decision-log.md as the standing record of a taken decision');

  // SEC-R2 independently gates 3B-1 and is unchanged.
  const reg = R('docs', 'MASTER_REMEDIATION_REGISTRY.md');
  const secr2 = reg.slice(reg.indexOf('### SEC-R2 ·'), reg.indexOf('### SEC-R3 ·'));
  check('SEC-R2 still lacks VERIFIED END-TO-END and is still NOT promoted',
    /\*\*VERIFIED END-TO-END is absent\.\*\*/.test(secr2)
      && /\*\*NOT promoted\*\*/.test(secr2),
    'so resolving CON-03 does not make 3B-1 startable');

  // The memo's own re-confirmation must stay honest about contact.
  const memo = R('docs', 'V5_CON03_STORAGE_CONTRACT_DECISION_MEMO.md')
    .replace(/\s+/g, ' ');
  check('the memo still states no owner was contacted',
    /No owner was contacted in this milestone or any previous one/.test(memo),
    '§10 — a pending decision must never read as a requested one');
  check('the memo records the TERMINAL CI result for daeca22, with its run id',
    /38413431946/.test(memo) && /conclusion=success/.test(memo)
      && /7 of 7 jobs/.test(memo),
    'and names the cancelled push run as not evidence');
}

// ── declared blockers must veto eligibility (Milestone 17) ─────────────────
//
// `.skills-agent/state.json` is GITIGNORED (.gitignore:40), and loadState's
// `??=` defaults every unknown task to READY. So on any fresh clone -- which
// is CI's situation and any new runner's -- all 16 blocker-declaring tasks
// read as READY. The hand-maintained statuses were the only thing holding
// them back and they do not travel. Measured on a fresh state with the veto
// removed in place: 12 tasks eligible, including V5-PROM-001/002 (finding
// promotions), V5-GOV-002 (protected-register edits), V5-GOV-006 (Step 4) and
// V5-CON-003 (writing the migration on an undecided contract). With the veto:
// 1 (V5-AUTO-001, read-only, no deps, no blockers).
{
  const coord = fs.readFileSync(path.join(ROOT, 'scripts',
    'skills-agent-coordinator.mjs'), 'utf8');

  check('eligible() vetoes any task that declares a blocker',
    /if \(declaredBlockers\(task\)\.length > 0\) return false;/.test(coord),
    'the only protection that survives a fresh clone');
  check('…and the veto sits inside eligible(), not somewhere bypassable',
    /function eligible\(task, state\)[\s\S]{0,220}?declaredBlockers\(task\)\.length > 0/
      .test(coord),
    'claim/status/event all route through eligible()');
  check('declaredBlockers treats a non-array blockers field as empty',
    /Array\.isArray\(task\.blockers\) \? task\.blockers : \[\]/.test(coord),
    'a malformed field must not silently block or silently pass');

  // The self-test must carry the regression case, not just the code.
  check('the coordinator self-test asserts the declared-blocker veto',
    /declared-blocker veto self-test failed/.test(coord)
      && /declared-blocker veto/.test(coord),
    'verified by mutation: removing the veto makes --self-test exit 1');
  check('…and proves the veto is not vetoing everything',
    /blockers: \[\] \}, state\)\) throw new Error\('declared-blocker veto/.test(coord)
      && /blockers: undefined \}/.test(coord),
    'an empty or absent blockers array must still be eligible');

  // state.json being gitignored is load-bearing for the reasoning above.
  const ignore = fs.readFileSync(path.join(ROOT, '.gitignore'), 'utf8');
  check('state.json is still gitignored (so READY defaults still ship)',
    /\.skills-agent\/state\.json/.test(ignore),
    '.gitignore:40 — if this changes, re-reason about the fresh-clone case');
  check('loadState still defaults an unknown task to READY',
    /state\.tasks\[t\.id\] \?\?= \{ status: 'READY'/.test(coord),
    'the default that made the veto necessary');

  // The drift reporter, and that it reports rather than throws.
  check('validate reports blocker/status drift',
    /blockerStatusDrift/.test(coord)
      && /declare an unresolved blocker but sit in a runnable status/.test(coord),
    'verified by positive control: re-setting V5-W3B-001 to READY reports 1');
  check('…as a warning, not a throw that would block unrelated commands',
    /console\.error\(`WARNING — \$\{drift\.length\} task\(s\) declare/.test(coord),
    'the status field is operator-owned');

  // The queue must not still claim CON-03 needs no owner ruling.
  const q = JSON.parse(fs.readFileSync(path.join(ROOT, '.skills-agent',
    'tasks.json'), 'utf8'));
  const con = q.tasks.find((t) => t.id === 'V5-CON-003');
  const conFlat = JSON.stringify(con);
  check('V5-CON-003 is classified as owner-blocked',
    con.blockers.length === 1 && con.blockers[0].kind === 'owner',
    `kind=${con.blockers.map((b) => b.kind).join(',')}`);
  // Assert the OPERATIVE field, not the narrative. The corrected `what`
  // deliberately QUOTES the old wording ("no owner ruling needed") to record
  // what was wrong with it, so a flattened-JSON match finds the very string it
  // is checking for -- the same self-documentation trap that caught the
  // workout-cursor detector, SEC-G9's `can\w*`, and the <Icon> glyph check.
  check('V5-CON-003\'s action now requires an owner answer',
    /owner answers CON-03-TYPE/.test(con.blockers[0].action),
    `action=${con.blockers[0].action.slice(0, 70)}`);
  check('…and the stale claim survives only as an attributed correction',
    /CORRECTED 2026-10-13[\s\S]*no owner ruling needed/.test(con.blockers[0].what)
      && /CON-03-TYPE/.test(conFlat),
    'the old wording is quoted as history, never asserted as current');
  check('…and still records that PD-A22 authorizes DESIGN only',
    /names no target/.test(conFlat) && /PD-A22/.test(conFlat),
    'Proceed? = Yes is not approval of the target type');

  // Every task that declares a blocker names an action, so a blocker is
  // actionable rather than a dead end.
  const noAction = q.tasks.filter((t) => (t.blockers || [])
    .some((b) => !b.action || !b.evidence));
  check('every declared blocker still names both evidence and an action',
    noAction.length === 0,
    noAction.length ? `missing on ${noAction.map((t) => t.id).join(', ')}` : 'all complete');
}

// ── a task's own evidenceRequired kind is enforced (Milestone 17) ──────────
//
// The generic check accepts ANY of URL / artifact: / ci: / commit: for ANY
// task, so a task whose evidenceRequired says `commit:` could be closed with a
// bare URL. Seven of nineteen tasks declare `commit:`. The other twelve
// declare prose no rule can check, and that is left to the reviewer rather
// than faked. Driven through the real lease dance, not asserted on source.
section('evidenceRequired kind is enforced for the kinds that are checkable');
{
  const dir = sandbox([T('A', { evidenceRequired: ['commit: containing the work'] })]);
  const c = json(run(dir, ['claim', 'implementer'], { SKILLS_AGENT_ID: 'mallory' }));
  run(dir, ['event', 'A', c.token, 'implemented', 'done'], { SKILLS_AGENT_ID: 'mallory' });
  const v = json(run(dir, ['claim', 'verifier'],
    { SKILLS_AGENT_ID: 'alice', SKILLS_AGENT_ROLE: 'verifier' }));

  // A URL passes the generic reference check and must STILL be refused,
  // because this task declared commit: evidence.
  const wrongKind = run(dir, ['event', 'A', v.token, 'verified', 'https://example.com/run/1'],
    { SKILLS_AGENT_ID: 'alice', SKILLS_AGENT_ROLE: 'verifier' });
  check('a URL is refused when the task declares commit: evidence',
    !wrongKind.ok && /requires commit: evidence/.test(wrongKind.err),
    wrongKind.err.trim().slice(0, 90));
  check('…and the task did NOT advance to VERIFIED',
    stateOf(dir).tasks.A.status !== 'VERIFIED',
    `status=${stateOf(dir).tasks.A.status}`);

  // The positive leg: the declared kind is accepted. Without this, the test
  // above would pass against a rule that refuses everything.
  const right = run(dir, ['event', 'A', v.token, 'verified', 'commit:abc123'],
    { SKILLS_AGENT_ID: 'alice', SKILLS_AGENT_ROLE: 'verifier' });
  check('the declared kind IS accepted',
    right.ok && stateOf(dir).tasks.A.status === 'VERIFIED',
    right.ok ? 'VERIFIED' : right.err.trim().slice(0, 90));
}
{
  // A task with prose-only evidenceRequired must not be made unverifiable by
  // the new rule -- twelve of nineteen tasks are in this position.
  const dir = sandbox([T('B', { evidenceRequired: ['a recorded governance ruling'] })]);
  const c = json(run(dir, ['claim', 'implementer'], { SKILLS_AGENT_ID: 'mallory' }));
  run(dir, ['event', 'B', c.token, 'implemented', 'done'], { SKILLS_AGENT_ID: 'mallory' });
  const v = json(run(dir, ['claim', 'verifier'],
    { SKILLS_AGENT_ID: 'alice', SKILLS_AGENT_ROLE: 'verifier' }));
  const ok = run(dir, ['event', 'B', v.token, 'verified', 'https://example.com/ruling'],
    { SKILLS_AGENT_ID: 'alice', SKILLS_AGENT_ROLE: 'verifier' });
  check('a prose-only requirement still accepts any valid reference kind',
    ok.ok && stateOf(dir).tasks.B.status === 'VERIFIED',
    ok.ok ? 'VERIFIED' : ok.err.trim().slice(0, 90));
}
{
  // And a task declaring NO evidenceRequired is unaffected.
  const dir = sandbox([T('C')]);
  const c = json(run(dir, ['claim', 'implementer'], { SKILLS_AGENT_ID: 'mallory' }));
  run(dir, ['event', 'C', c.token, 'implemented', 'done'], { SKILLS_AGENT_ID: 'mallory' });
  const v = json(run(dir, ['claim', 'verifier'],
    { SKILLS_AGENT_ID: 'alice', SKILLS_AGENT_ROLE: 'verifier' }));
  const ok = run(dir, ['event', 'C', v.token, 'verified', 'ci:12345'],
    { SKILLS_AGENT_ID: 'alice', SKILLS_AGENT_ROLE: 'verifier' });
  check('a task with no evidenceRequired is unaffected by the new rule',
    ok.ok && stateOf(dir).tasks.C.status === 'VERIFIED',
    ok.ok ? 'VERIFIED' : ok.err.trim().slice(0, 90));
}

// ── the attestation secret must never reach stdout or stderr ───────────────
//
// `identityTrust` reads SKILLS_AGENT_ATTESTATION_KEY and mints an HMAC from
// it. A source grep would only prove nobody wrote `console.log(key)` today, so
// this drives the real paths with sentinel values and asserts the sentinels
// appear in NO output -- including the error path, which is where a secret is
// most likely to be echoed back for "debuggability".
section('the attestation key and identity token stay out of all output');
{
  const SECRET = 'SENTINEL-ATTESTATION-KEY-d41d8cd9';
  const TOKEN = 'SENTINEL-IDENTITY-TOKEN-8f14e45f';
  const dir = sandbox([T('A')]);

  // 1 · key set, token MISSING -> the error path fires.
  const noTok = run(dir, ['claim', 'implementer'],
    { SKILLS_AGENT_ID: 'w1', SKILLS_AGENT_ATTESTATION_KEY: SECRET });
  check('a configured key with no identity token is refused',
    !noTok.ok && /identity token is required/.test(noTok.err),
    noTok.err.trim().slice(0, 70));
  check('…and that refusal does not echo the key',
    !`${noTok.out}${noTok.err}`.includes(SECRET),
    'the error path is where a secret most often leaks');

  // 2 · key set, token WRONG -> the mismatch path fires.
  const badTok = run(dir, ['claim', 'implementer'],
    { SKILLS_AGENT_ID: 'w1', SKILLS_AGENT_ATTESTATION_KEY: SECRET,
      SKILLS_AGENT_IDENTITY_TOKEN: TOKEN });
  const bothOut = `${badTok.out}${badTok.err}`;
  check('a wrong identity token leaks neither the key nor the token',
    !bothOut.includes(SECRET) && !bothOut.includes(TOKEN),
    bothOut.trim().slice(0, 70) || '(no output)');

  // 3 · the success path, with a correctly minted token, must not echo either.
  const expected = crypto.createHmac('sha256', SECRET)
    .update('A:implementer:w1').digest('hex');
  const good = run(dir, ['claim', 'implementer'],
    { SKILLS_AGENT_ID: 'w1', SKILLS_AGENT_ATTESTATION_KEY: SECRET,
      SKILLS_AGENT_IDENTITY_TOKEN: expected });
  const goodOut = `${good.out}${good.err}`;
  // The trust level is PERSISTED (:311), not returned in the claim JSON --
  // my first version of this looked in the claim output and failed while the
  // claim had in fact succeeded. Assert where the value actually lives.
  const trust = JSON.parse(fs.readFileSync(
    path.join(dir, '.skills-agent', 'state.json'), 'utf8'))
    .tasks.A.implementerIdentityTrust;
  check('a correctly attested claim succeeds and records attested trust',
    good.ok && trust && trust !== 'self-asserted',
    good.ok ? `trust=${trust}` : good.err.trim().slice(0, 70));
  check('…and the success path echoes neither the key nor the HMAC',
    !goodOut.includes(SECRET) && !goodOut.includes(expected),
    'an attested claim must not publish the proof it was given');

  // 4 · the persisted state must not carry them either -- it is committed in
  // other repositories even though it is gitignored here.
  const persisted = fs.readFileSync(path.join(dir, '.skills-agent', 'state.json'), 'utf8');
  check('the state file stores neither the key nor the token',
    !persisted.includes(SECRET) && !persisted.includes(expected),
    'state.json records trust LEVEL, not the secret that established it');
}

// ── the fresh-clone case, driven through `claim` (Milestone 18) ────────────
//
// `sandbox()` writes ONLY tasks.json, so these runs have NO state.json at all
// -- which is precisely the production scenario: state.json is gitignored
// (.gitignore:40) and loadState's `??=` defaults every unknown task to READY.
// Milestone 17 proved the veto's effect by counting eligibility in-process
// (12 -> 1). This asserts the same thing through the real `claim` command,
// which is what an actual worker invokes.
section('on a fresh clone with no state, a blocked task is never handed out');
{
  const dir = sandbox([
    T('BLOCKED', { blockers: [{ kind: 'owner', what: 'an undecided contract',
      evidence: 'memo', action: 'owner ruling' }] }),
    T('FREE'),
  ]);
  // No state.json exists yet -- assert the premise rather than assume it.
  check('the sandbox genuinely has no persisted state (the fresh-clone premise)',
    !fs.existsSync(path.join(dir, '.skills-agent', 'state.json')),
    'if this file existed, the test below would not be testing a fresh clone');

  const first = json(run(dir, ['claim', 'implementer'], { SKILLS_AGENT_ID: 'w1' }));
  check('claim hands out the UNBLOCKED task, not the blocked one',
    first?.task?.id === 'FREE',
    `claimed ${first?.task?.id ?? '(none)'}`);
  check('…and the blocked task defaulted to READY, so only the veto excluded it',
    stateOf(dir).tasks.BLOCKED.status === 'READY',
    'this is the exact condition that made the veto necessary');

  // With the only unblocked task taken, a second worker must get nothing --
  // NOT the blocked task.
  const second = json(run(dir, ['claim', 'implementer'], { SKILLS_AGENT_ID: 'w2' }));
  check('a second worker is refused rather than given the blocked task',
    second?.claimed === false && second?.reason === 'NO_ELIGIBLE_TASK_FOR_ROLE',
    JSON.stringify(second).slice(0, 80));
  check('…and the blocked task was never claimed',
    !stateOf(dir).tasks.BLOCKED.leaseToken
      && stateOf(dir).tasks.BLOCKED.status === 'READY',
    'no lease was ever issued against it');
}
{
  // The non-regression legs at command level: an empty and an absent blockers
  // array must both remain claimable, so the veto is not blocking everything.
  const dirEmpty = sandbox([T('A', { blockers: [] })]);
  const a = json(run(dirEmpty, ['claim', 'implementer'], { SKILLS_AGENT_ID: 'w1' }));
  check('an EMPTY blockers array is still claimable on a fresh clone',
    a?.task?.id === 'A', `claimed ${a?.task?.id ?? '(none)'}`);

  const dirAbsent = sandbox([T('B')]);
  const b = json(run(dirAbsent, ['claim', 'implementer'], { SKILLS_AGENT_ID: 'w1' }));
  check('an ABSENT blockers field is still claimable on a fresh clone',
    b?.task?.id === 'B', `claimed ${b?.task?.id ?? '(none)'}`);
}
{
  // A blocked task must not block its dependents' siblings either: the queue
  // has to keep advancing around it (the "blocked tasks do not prevent
  // unrelated tasks from advancing" requirement), and a task depending on a
  // blocked one must stay unreachable.
  const dir = sandbox([
    T('GATE', { blockers: [{ kind: 'governance', what: 'gated wave',
      evidence: 'waves', action: 'authorize the wave' }] }),
    T('DOWNSTREAM', { dependsOn: ['GATE'] }),
    T('UNRELATED'),
  ]);
  const got = [];
  for (const id of ['w1', 'w2', 'w3']) {
    const c = json(run(dir, ['claim', 'implementer'], { SKILLS_AGENT_ID: id }));
    if (c?.task?.id) got.push(c.task.id);
  }
  check('only the unrelated task is ever handed out',
    got.length === 1 && got[0] === 'UNRELATED',
    `handed out: [${got.join(', ')}]`);
  check('…and the task depending on a blocked task stays unclaimed',
    stateOf(dir).tasks.DOWNSTREAM.status === 'READY'
      && !stateOf(dir).tasks.DOWNSTREAM.leaseToken,
    'depsVerified already covered this; it must still hold with the veto');
}

// ── file ownership: `paths` must reserve files, not decorate the queue ─────
//
// `paths` was the SECOND declared field validated and never read. Demonstrated
// before the fix: two tasks both declaring `lib/shared/thing.dart` were handed
// to w1 and w2 and BOTH held live leases. Leases protected a TASK from
// double-claim; nothing protected a FILE.
section('an implementer lease reserves its declared paths');
{
  const P = 'lib/shared/thing.dart';
  const dir = sandbox([
    T('X', { paths: [P] }),
    T('Y', { paths: [P] }),
    T('Z', { paths: ['lib/other/elsewhere.dart'] }),
  ]);
  const a = json(run(dir, ['claim', 'implementer'], { SKILLS_AGENT_ID: 'w1' }));
  check('the first worker claims the contended task', a?.task?.id === 'X',
    `claimed ${a?.task?.id ?? '(none)'}`);

  // The queue must route AROUND the conflict, not stall on it.
  const b = json(run(dir, ['claim', 'implementer'], { SKILLS_AGENT_ID: 'w2' }));
  check('the second worker gets the NON-conflicting task, not nothing',
    b?.task?.id === 'Z', `claimed ${b?.task?.id ?? '(none)'}`);

  const c = json(run(dir, ['claim', 'implementer'], { SKILLS_AGENT_ID: 'w3' }));
  check('a worker is refused the task whose path is already held',
    c?.claimed === false && c?.reason === 'NO_ELIGIBLE_TASK_FOR_ROLE',
    JSON.stringify(c).slice(0, 70));
  check('…and the conflicting task holds no lease and stays READY',
    stateOf(dir).tasks.Y.status === 'READY' && !stateOf(dir).tasks.Y.leaseToken,
    'a path conflict must not consume a retry or change status');
}
{
  // Prefix-aware, because the real queue mixes directories and files.
  const dir = sandbox([
    T('DIR', { paths: ['.skills-agent/'] }),
    T('FILE', { paths: ['.skills-agent/tasks.json'] }),
  ]);
  run(dir, ['claim', 'implementer'], { SKILLS_AGENT_ID: 'w1' });
  const second = json(run(dir, ['claim', 'implementer'], { SKILLS_AGENT_ID: 'w2' }));
  check('a directory lease conflicts with a file inside it',
    second?.claimed === false,
    `got ${second?.task?.id ?? 'refused'} — '.skills-agent/' must cover its contents`);
}
{
  // And the inverse must NOT over-block: siblings in one directory are
  // independent. Without this leg the test above would pass against a rule
  // that treats every path as conflicting.
  const dir = sandbox([
    T('A', { paths: ['docs/A.md'] }),
    T('B', { paths: ['docs/B.md'] }),
  ]);
  const a = json(run(dir, ['claim', 'implementer'], { SKILLS_AGENT_ID: 'w1' }));
  const b = json(run(dir, ['claim', 'implementer'], { SKILLS_AGENT_ID: 'w2' }));
  check('sibling files in one directory are both claimable',
    a?.task?.id && b?.task?.id && a.task.id !== b.task.id,
    `claimed ${a?.task?.id} and ${b?.task?.id}`);
}
{
  // The reservation must be RELEASED, or a path conflict becomes a permanent
  // deadlock -- the failure mode the stale-lock fix already had to undo once.
  const P = 'lib/contended.dart';
  const dir = sandbox([T('X', { paths: [P] }), T('Y', { paths: [P] })]);
  const a = json(run(dir, ['claim', 'implementer'], { SKILLS_AGENT_ID: 'w1' }));
  const blocked = json(run(dir, ['claim', 'implementer'], { SKILLS_AGENT_ID: 'w2' }));
  check('Y is blocked while X holds the path', blocked?.claimed === false,
    'premise for the release test below');

  // Expire X's lease and recover it; Y must become claimable.
  const st = stateOf(dir);
  st.tasks.X.leaseExpiresAt = new Date(Date.now() - 60_000).toISOString();
  fs.writeFileSync(path.join(dir, '.skills-agent', 'state.json'),
    JSON.stringify(st, null, 2));
  run(dir, ['recover'], { SKILLS_AGENT_ID: 'w1' });
  const after = json(run(dir, ['claim', 'implementer'], { SKILLS_AGENT_ID: 'w3' }));
  check('once the holding lease expires, the path is released',
    after?.task?.id === 'X' || after?.task?.id === 'Y',
    `claimed ${after?.task?.id ?? 'refused'} — a conflict must not deadlock`);
}
{
  // A verifier reviews rather than writes, and its independence is enforced
  // separately, so path reservation must not stop verification.
  const P = 'lib/v.dart';
  const dir = sandbox([T('X', { paths: [P] }), T('Y', { paths: [P] })]);
  const c = json(run(dir, ['claim', 'implementer'], { SKILLS_AGENT_ID: 'mallory' }));
  run(dir, ['event', 'X', c.token, 'implemented', 'done'], { SKILLS_AGENT_ID: 'mallory' });
  const v = json(run(dir, ['claim', 'verifier'],
    { SKILLS_AGENT_ID: 'alice', SKILLS_AGENT_ROLE: 'verifier' }));
  check('a verifier can still claim a task whose paths are contended',
    v?.assignment === 'independent-verification',
    JSON.stringify(v).slice(0, 70));
}

// ── policy.maxConcurrentTasks must bound live leases ──────────────────────
//
// The THIRD declared field nothing read. Demonstrated before the fix: with the
// policy set to 3, six workers took six live leases.
section('policy.maxConcurrentTasks bounds concurrent implementer leases');
{
  const sandboxWithPolicy = (policy, tasks) => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'sa-conc-'));
    fs.mkdirSync(path.join(dir, 'scripts'), { recursive: true });
    fs.mkdirSync(path.join(dir, '.skills-agent'), { recursive: true });
    fs.copyFileSync(COORD, path.join(dir, 'scripts', 'skills-agent-coordinator.mjs'));
    fs.writeFileSync(path.join(dir, '.skills-agent', 'tasks.json'),
      JSON.stringify({ version: 1, policy, tasks }, null, 2));
    return dir;
  };
  const six = [1, 2, 3, 4, 5, 6].map((n) => T(`T${n}`, { paths: [`f${n}.dart`] }));

  const dir = sandboxWithPolicy({ maxConcurrentTasks: 3 }, six);
  const got = [];
  for (const w of ['w1', 'w2', 'w3', 'w4', 'w5']) {
    const c = json(run(dir, ['claim', 'implementer'], { SKILLS_AGENT_ID: w }));
    got.push(c?.task?.id ?? 'refused');
  }
  check('exactly the limit is handed out, then claims are refused',
    got.slice(0, 3).every((g) => g !== 'refused')
      && got.slice(3).every((g) => g === 'refused'),
    `[${got.join(', ')}]`);
  const live = Object.values(stateOf(dir).tasks)
    .filter((v) => v.leaseToken && ['CLAIMED', 'IMPLEMENTED'].includes(v.status)).length;
  check('live leases never exceed the declared limit', live === 3, `live=${live}`);

  // Releasing a lease must free a slot, or the limit becomes a dead end.
  const st = stateOf(dir);
  const firstHeld = Object.keys(st.tasks).find((k) => st.tasks[k].leaseToken);
  st.tasks[firstHeld].leaseExpiresAt = new Date(Date.now() - 60_000).toISOString();
  fs.writeFileSync(path.join(dir, '.skills-agent', 'state.json'),
    JSON.stringify(st, null, 2));
  run(dir, ['recover'], { SKILLS_AGENT_ID: 'w1' });
  const after = json(run(dir, ['claim', 'implementer'], { SKILLS_AGENT_ID: 'w6' }));
  check('an expired lease frees a concurrency slot',
    !!after?.task?.id, `claimed ${after?.task?.id ?? 'refused'}`);

  // No limit declared -> prior behaviour, unbounded. Without this leg the test
  // above would pass against a rule that refuses everything beyond 3 always.
  const unlimited = sandboxWithPolicy({}, six);
  const n = ['a', 'b', 'c', 'd', 'e'].filter((w) =>
    json(run(unlimited, ['claim', 'implementer'], { SKILLS_AGENT_ID: w }))?.task?.id).length;
  check('with no limit declared, concurrency is unbounded as before',
    n === 5, `claimed ${n} of 5`);

  // A non-positive limit must also mean "no limit", not "refuse everything".
  const zero = sandboxWithPolicy({ maxConcurrentTasks: 0 }, six);
  const z = json(run(zero, ['claim', 'implementer'], { SKILLS_AGENT_ID: 'w1' }));
  check('a zero limit is treated as no limit, not a total block',
    !!z?.task?.id, `claimed ${z?.task?.id ?? 'refused'}`);
}

// ── the contract guard must not overstate its coverage ────────────────────
//
// Found by paired mutation, 2026-10-13. The schema contract guard's own
// contract says it checks "every .insert/.update/.upsert({...}) key names a
// real column". It reads keys only at brace depth 1 of the payload, so:
//
//   inline   .upsert({'zzz_bad': 1})            -> FAILS correctly
//   helper   key added to toSupabase(), which is spread in at
//            intake_flow_screen.dart:281 as .upsert({'id': uid, ...})  -> PASSES
//
// `.insert(payload)` is worse than partial: `body` is the identifier, there is
// no `{`, brace never reaches 1, and the site is skipped in SILENCE. Those two
// serializers are the subject of CON-03, so the guard cannot see the functions
// the finding is about. Reported, never failed — 31 of 174 sites are in this
// shape and failing them would break CI on pre-existing code.
{
  const runner = fs.readFileSync(path.join(ROOT, 'supabase', 'tests',
    'contract', 'run.mjs'), 'utf8');

  check('the contract guard counts its write sites by payload shape',
    /writeSites = \{ total: 0, inlineLiteral: 0, opaquePayload: 0, hasSpread: 0 \}/
      .test(runner),
    'so a PASS can be read against what was actually analysed');
  // Behavioural, not syntactic. The first version of this pinned the exact
  // `if (!body.includes('{')) writeSites.opaquePayload++;` text and broke the
  // moment the classification was refactored into two consts -- while the
  // behaviour was unchanged. Run the guard and check its own numbers instead,
  // so a refactor cannot break it and a REGRESSION cannot pass it.
  const cov = spawnSync(process.execPath,
    [path.join(ROOT, 'supabase', 'tests', 'contract', 'run.mjs')],
    { encoding: 'utf8', cwd: ROOT });
  const m = /write sites (\d+): (\d+) fully analysed, (\d+) with a spread[^,]*, (\d+) opaque/
    .exec(cov.stdout ?? '');
  check('the guard reports coverage numbers that add up',
    !!m && Number(m[2]) + Number(m[3]) + Number(m[4]) === Number(m[1]),
    m ? `${m[2]}+${m[3]}+${m[4]} = ${m[1]}` : 'COVERAGE line not found in output');
  check('…and still finds BOTH unseen shapes present in this tree',
    !!m && Number(m[3]) > 0 && Number(m[4]) > 0,
    m ? `spread=${m[3]} opaque=${m[4]} — if either hits 0, re-check the classifier`
      : 'no COVERAGE line');
  check('the guard prints a COVERAGE line next to its verdict',
    /COVERAGE {2}write sites \$\{writeSites\.total\}/.test(runner),
    'the number must travel with the PASS, not be inferable only from source');
  check('…and says in words that PASS does not mean every key was checked',
    /A PASS below does not mean every write key was checked/.test(runner),
    'the sixth vacuous-control lesson, written where it will be read');
  check('the blind spot is recorded with its cause, not just its existence',
    /brace never reaches 1/.test(runner) && /CON-03/.test(runner),
    'so a later reader knows why, and which finding it touches');

  // The coverage line must be derived, never hard-coded: a literal count would
  // go stale the moment a call site is added, which is exactly the failure
  // mode this check exists to prevent.
  check('the counts are computed, not hard-coded literals',
    !/write sites 174/.test(runner) && !/31 write site/.test(runner),
    'today\'s numbers are 174 / 143 / 11 / 20 -> 31 unseen, and must float');
}

// ── the blind spot must be auditable, not just counted ────────────────────
{
  const runner = fs.readFileSync(path.join(ROOT, 'supabase', 'tests',
    'contract', 'run.mjs'), 'utf8');
  check('--list-unseen names the sites behind the COVERAGE counts',
    /--list-unseen/.test(runner)
      && /Sites whose column keys this guard cannot see/.test(runner),
    'so the 31 can be audited instead of feared');
  check('…and is opt-in, so CI output stays stable',
    /const LIST_UNSEEN = process\.argv\.includes\('--list-unseen'\)/.test(runner)
      && /if \(LIST_UNSEEN && unseenSites\.length\)/.test(runner),
    'verified: the list does not print by default');
  check('the listing is built inside the resolved-table loop',
    /if \(LIST_UNSEEN && \(opaque \|\| spread\)\)[\s\S]{0,180}?table,/.test(runner),
    'a standalone re-implementation counted 31 as 81 — Map.update, List.insert '
      + 'and the vendored .plugin_symlinks tree all matched without the .from() window');
  check('…and that over-count is recorded where someone would repeat it',
    /over-counted 31 as 81/.test(runner) && /plugin_symlinks/.test(runner),
    'the reimplementation trap, written down');
}

console.log(`\n${'='.repeat(74)}`);
console.log(`Skills-Agent coordinator: ${passed}/${passed + failures.length} passed`);
if (failures.length) {
  console.log('FAILURES:');
  for (const f of failures) console.log(`  x ${f}`);
  process.exit(1);
}
