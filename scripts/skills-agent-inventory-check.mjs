#!/usr/bin/env node
// Inventory invariants the coordinator's own validator does not cover.
//
// `loadTasks` proves the GRAPH is well formed — unique ids, resolvable
// dependencies, no cycles. It says nothing about whether a task's claimed
// evidence exists, and that is the failure this programme keeps producing: a
// citation that was true when written, or never true, and nothing looked.
//
// Two concrete instances behind this file:
//   * the queue declared `queueAuthority: V5_WORKSTREAM_REGISTRY_AND_MASTER_
//     REMEDIATION_WAVES`. No V5_WORKSTREAM_REGISTRY exists — not a tracked
//     file, and no document in docs/ carries that title.
//   * V5-AUTO-001 was VERIFIED with `commit:3216bfe`, the BASELINE, while its
//     deliverable landed in 4c699dd.
//
// So: a cited source path must resolve, or the task is reported as citing
// something that is not there. It is NOT silently dropped and NOT invented.
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const TASKS = path.join(ROOT, '.skills-agent', 'tasks.json');

// A source may be `path` (in this checkout) or `<commit>:path`, which is how
// this project already cites the approved design authority: commit 931218b on
// `design/12circle-plus-admin-dashboard` is NOT an ancestor of this branch, so
// those files are readable only through git. The first run of this validator
// caught exactly that mistake in this very queue — COMPONENTS.md cited as a
// working-tree path when it has never been on this branch.
function resolves(src) {
  const m = /^([0-9a-f]{7,40}):(.+)$/i.exec(src);
  if (!m) return fs.existsSync(path.join(ROOT, src));
  const r = spawnSync('git', ['cat-file', '-e', `${m[1]}:${m[2]}`],
    { cwd: ROOT, stdio: 'ignore' });
  // git missing or not a repo: unresolvable rather than false. Reported as a
  // problem either way, because an unverifiable citation is not evidence.
  return !r.error && r.status === 0;
}

const data = JSON.parse(fs.readFileSync(TASKS, 'utf8'));
const tasks = data.tasks ?? [];
const ids = new Set(tasks.map((t) => t.id));
const problems = [];
let checkedSources = 0;

for (const t of tasks) {
  // Cited sources must exist in THIS checkout.
  for (const src of t.sources ?? []) {
    checkedSources++;
    if (!resolves(src)) {
      problems.push(`${t.id}: cited source does not resolve — ${src}`);
    }
  }
  // Declared paths are the task's permitted blast radius; a path that cannot
  // exist is a scope statement nobody can honour. Directories are allowed to
  // be created, so only a file-shaped path with a missing PARENT is flagged.
  for (const p of t.paths ?? []) {
    const abs = path.join(ROOT, p);
    if (!fs.existsSync(abs) && !fs.existsSync(path.dirname(abs))) {
      problems.push(`${t.id}: declared path is unreachable — ${p} (parent missing)`);
    }
  }
  for (const c of t.conflictsWith ?? []) {
    if (!ids.has(c)) problems.push(`${t.id}: conflictsWith names an unknown task — ${c}`);
  }
  // A blocker must say what to DO about it, or it is a complaint rather than a
  // dependency somebody can clear.
  for (const b of t.blockers ?? []) {
    if (!b.kind || !b.what || !b.action) {
      problems.push(`${t.id}: a blocker is missing kind/what/action — ${JSON.stringify(b).slice(0, 70)}`);
    }
  }
  // `runnerIndependent` is what makes a task safely startable today, so it may
  // not be left to the reader to guess.
  if (typeof t.runnerIndependent !== 'boolean') {
    problems.push(`${t.id}: runnerIndependent must be stated explicitly (true or false)`);
  }
}

// `policy.authorityScope` maps each governed concern to the document that
// governs it, quoting that document's own header. Those paths must resolve too:
// the field was added in the same change that corrected the authority from
// three documents to five, and an unchecked mapping is how the original phantom
// citation survived in the first place.
for (const [concern, claim] of Object.entries(data.policy?.authorityScope ?? {})) {
  const m = /^([^\s—-]+\.md)/.exec(String(claim).trim());
  if (!m) {
    problems.push(`policy.authorityScope["${concern}"] does not begin with a document path`);
    continue;
  }
  checkedSources++;
  if (!resolves(m[1])) {
    problems.push(`policy.authorityScope["${concern}"] cites a document that does not resolve — ${m[1]}`);
  }
}

// Every document named in queueAuthority should also appear in authorityScope,
// or the queue claims an authority without saying what it governs.
const scopeDocs = new Set(Object.values(data.policy?.authorityScope ?? {})
  .map((v) => (/^([^\s—-]+\.md)/.exec(String(v).trim()) ?? [])[1])
  .filter(Boolean));
for (const a of String(data.policy?.queueAuthority ?? '').split('+').map((x) => x.trim())) {
  if (a && a.includes('/') && !scopeDocs.has(a)) {
    problems.push(`queueAuthority names ${a} but authorityScope never says what it governs`);
  }
}

// The queue's own declared authority must resolve too — that is where the first
// phantom citation was found.
for (const a of String(data.policy?.queueAuthority ?? '').split('+').map((x) => x.trim())) {
  if (a && a.includes('/')) {
    checkedSources++;
    if (!fs.existsSync(path.join(ROOT, a))) {
      problems.push(`policy.queueAuthority cites a document that does not exist — ${a}`);
    }
  }
}

if (problems.length) {
  console.error(`FAIL — inventory evidence problems (${problems.length}):`);
  for (const p of problems) console.error(`  · ${p}`);
  process.exit(1);
}
console.log(`PASS — ${tasks.length} tasks, ${checkedSources} cited sources all resolve; `
  + `every blocker names an action; runnerIndependent stated on every task.`);
