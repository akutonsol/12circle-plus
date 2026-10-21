#!/usr/bin/env node
// V5 §165 · every cited design artifact must be readable by the person reading the doc.
//
// THE DEFECT THIS EXISTS FOR. `COMPONENT-SPECS.md:14` cites
// `docs/design/brand/tokens/admin.tokens.css` as the source of 126 tokens. That file is
// not on this branch — `docs/design/brand/` does not exist here, because the design
// publication commit is an ancestor of `design/12circle-plus-admin-dashboard` and of
// nothing else. The citation was true when written and unfollowable afterwards, and
// nothing detected the difference (V5 §164.1).
//
// A citation nobody can follow is indistinguishable, to a later reader, from one that
// was never checked. So: a cited design path must resolve in the working tree, OR at the
// pinned design commit with the citing document naming that commit so the reader knows
// where to look. Anything else fails.
import { execFileSync } from 'node:child_process';
import { readFileSync, readdirSync, existsSync, statSync } from 'node:fs';

const DESIGN_COMMIT = '931218b';
const line = '─'.repeat(74);

function mdFiles(dir) {
  const out = [];
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = `${dir}/${e.name}`;
    if (e.isDirectory()) out.push(...mdFiles(p));
    else if (e.name.endsWith('.md')) out.push(p);
  }
  return out;
}

const docs = mdFiles('docs');
if (docs.length < 20) {
  console.error(`  FAIL — scanned only ${docs.length} markdown file(s) under docs/. ` +
    'A scan that walks almost nothing reports every citation valid.');
  process.exit(1);
}

// What the design commit actually contains, read once.
let designTree = new Set();
let designReachable = true;
try {
  designTree = new Set(execFileSync('git',
    ['ls-tree', '-r', '--name-only', DESIGN_COMMIT], { encoding: 'utf8' })
    .split('\n').filter(Boolean));
} catch {
  designReachable = false;
}

// POSITIVE CONTROL. If the design ref is unreachable this check cannot do its job, and
// must say so rather than pass everything.
if (!designReachable) {
  console.error(`  FAIL — commit ${DESIGN_COMMIT} is unreachable, so no citation can be ` +
    'verified against the published design authority. Fetch ' +
    'design/12circle-plus-admin-dashboard. Refusing to report citations valid.');
  process.exit(1);
}
for (const canary of ['docs/design/brand/tokens/admin.tokens.css',
                      'docs/design/admin-dashboard/RESPONSIVE.md']) {
  if (!designTree.has(canary)) {
    console.error(`  FAIL — ${canary} is absent from ${DESIGN_COMMIT}, which publishes ` +
      'it. The listing is broken, not the design.');
    process.exit(1);
  }
}

// Cited paths: backticked design paths, and bare ones. Only paths with a file
// extension, so prose about a directory is not treated as a file citation.
const CITE = /(?:^|[\s`(\[])((?:docs\/)?design\/[A-Za-z0-9._\-/]+\.[a-z]{2,5})/g;

// ── BARE FILENAMES, WHICH IS HOW THE REAL CITATIONS ARE ACTUALLY WRITTEN ─────
// The first draft of this check matched only full paths and found SIX citations in
// 114 documents, while a plain grep showed `admin.contrast.md` alone named in five.
// Almost every real citation in this programme is a bare backticked filename —
// `admin.tokens.css`, `RESPONSIVE.md` — so a path-only matcher under-detects, which
// is precisely the defect this file exists to prevent. It reported "OK" over
// nothing, the §139.3 failure, in the guard written to stop that failure.
//
// Only DISTINCTIVE basenames count: ones the design commit publishes under
// docs/design/ that exist NOWHERE in this working tree. A name that is present here
// resolves for the reader by itself, and generic names like README.md would match
// every document in the repository.
const GENERIC = new Set(['README.md', 'index.md', 'NOTES.md']);

const treeBasenames = new Set();
(function walk(dir) {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    if (e.name === 'node_modules' || e.name === '.git') continue;
    const p = `${dir}/${e.name}`;
    if (e.isDirectory()) walk(p);
    else treeBasenames.add(e.name);
  }
})('.');

const danglingNames = new Map(); // basename -> its path at the design commit
for (const p of designTree) {
  if (!p.startsWith('docs/design/')) continue;
  const base = p.split('/').pop();
  if (GENERIC.has(base)) continue;
  if (treeBasenames.has(base)) continue;      // readable here already
  danglingNames.set(base, p);
}
if (danglingNames.size === 0) {
  console.error('  FAIL — found NO design artifact that is absent from this tree, ' +
    'yet docs/design/brand/ demonstrably does not exist here. The comparison is ' +
    'broken, not the tree.');
  process.exit(1);
}

const unresolvable = [];
const commitOnlyUnqualified = [];
let resolvedInTree = 0;
let resolvedAtCommit = 0;

for (const doc of docs) {
  const text = readFileSync(doc, 'utf8');
  const namesCommit = text.includes(DESIGN_COMMIT);
  const seen = new Set();
  for (const [, raw] of text.matchAll(CITE)) {
    const path = raw.startsWith('docs/') ? raw : `docs/${raw}`;
    if (seen.has(path)) continue;
    seen.add(path);
    if (existsSync(path) && statSync(path).isFile()) { resolvedInTree++; continue; }
    if (designTree.has(path)) {
      resolvedAtCommit++;
      // Readable, but only if the reader is told where. The citing document must
      // name the commit.
      if (!namesCommit) commitOnlyUnqualified.push(`${doc} → ${path}`);
      continue;
    }
    unresolvable.push(`${doc} → ${path}`);
  }

  // Now the bare-filename citations.
  for (const [base, atCommit] of danglingNames) {
    // Word-boundary match so `admin.tokens.css` does not also fire on
    // `admin.tokens.css.map` or a longer name ending in it.
    const re = new RegExp(`(?:^|[\\s\`([/])${base.replace(/[.]/g, '\\.')}(?![A-Za-z0-9._-])`);
    if (!re.test(text)) continue;
    if (seen.has(atCommit)) continue;
    seen.add(atCommit);
    resolvedAtCommit++;
    if (!namesCommit) commitOnlyUnqualified.push(`${doc} → ${base} (at ${atCommit})`);
  }
}

console.log(`\n${line}\n  DESIGN CITATION RESOLUTION — ${docs.length} documents scanned`);
console.log(`${line}`);
console.log(`  resolved in the working tree        ${resolvedInTree}`);
console.log(`  resolved at ${DESIGN_COMMIT} (design branch)  ${resolvedAtCommit}`);
console.log(`  unresolvable anywhere              ${unresolvable.length}`);
console.log(`  commit-only, commit not named      ${commitOnlyUnqualified.length}`);
console.log(line);

if (unresolvable.length) {
  console.log('\n  FAIL — these citations resolve nowhere, not even at the design commit:\n');
  for (const u of unresolvable) console.log(`   ${u}`);
  console.log('\n  Either the path is wrong, or the artifact was never published.');
  console.log(`${line}\n`);
  process.exit(1);
}
if (commitOnlyUnqualified.length) {
  console.log('\n  FAIL — these cite an artifact that is NOT on this branch, without');
  console.log(`  naming commit ${DESIGN_COMMIT} anywhere in the document, so a reader`);
  console.log('  cannot follow them:\n');
  for (const u of commitOnlyUnqualified) console.log(`   ${u}`);
  console.log(`\n  Add a provenance line naming ${DESIGN_COMMIT} and the branch it is on.`);
  console.log(`${line}\n`);
  process.exit(1);
}
console.log('\n  OK — every cited design artifact is readable, and every citation that');
console.log('  points off this branch says where to look.');
console.log(`${line}\n`);
