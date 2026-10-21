#!/usr/bin/env node
// QAX-COR guard — QA-ONLY EVIDENCE TOOL (Node, no Flutter SDK needed).
//
// Finds the "guarded write" shape in Dart code that UPDATEs/UPSERTs an existing row:
//     if (<x>.isNotEmpty) payload['col'] = ...;      if (x != null) 'col': x,
// Clearing that field in the UI never sends null, so the stored value silently survives
// while the UI reports success. INSERT-only methods are out of scope (omitting a null
// on a new row is harmless).
//
// Every hit must be classified in guarded_write_manifest.json at (file, column) granularity,
// and every manifest entry must still be found — both directions — so a new instance
// fails the guard AND a fix that forgets to shrink the manifest fails it too.
//
//   node guarded_write_scan.mjs            enforce against the manifest (exit 1 on drift)
//   node guarded_write_scan.mjs --list     print every classified hit
//   QAX_ROOT=<dir>                         scan a different lib/ root (used by mutation tests)
import fs from 'node:fs'; import path from 'node:path'; import { fileURLToPath } from 'node:url';
const here = path.dirname(fileURLToPath(import.meta.url));
const root = process.env.QAX_ROOT ?? path.resolve(here, '../../lib');
const manifestPath = process.env.QAX_MANIFEST ?? path.join(here, 'guarded_write_manifest.json');
const manifestDoc = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
// Methods that reach an UPDATE through a helper rather than calling .update( themselves.
// Declared in the manifest and checked both ways: a declared writer that no longer exists fails.
const indirect = manifestDoc.indirectWriters ?? [];
// Functions that BUILD a payload which the caller then sends as an UPDATE. A guarded
// write inside one is an UPDATE-path write even though the builder never calls
// .update( itself — without this, extracting a payload builder hides every defect in it.
const builders = manifestDoc.updatePayloadBuilders ?? [];
function spanOf(lines, fnName) {
  const decl = new RegExp(`^\\S.*\\b${fnName}\\s*\\(`);
  const start = lines.findIndex(l => decl.test(l));
  if (start < 0) return null;
  // The body opens at the first `) {` / `) async {` at or after the declaration —
  // NOT the first `{`, which for named parameters is the `({` of the parameter list.
  const bodyAt = lines.findIndex((l, k) => k >= start && /\)\s*(async\s*)?\{\s*$/.test(l));
  if (bodyAt < 0) return null;
  let d = 0;
  for (let k = bodyAt; k < lines.length; k++) {
    const from = k === bodyAt ? lines[k].lastIndexOf('{') : 0;
    for (const ch of lines[k].slice(from)) {
      if (ch === '{') d++; else if (ch === '}' && --d === 0) return [start, k];
    }
  }
  return null;
}

// Blank out comments and string *contents* except single-quoted column keys, preserving
// line numbers, so commented-out code can neither create nor hide a hit.
function stripComments(src) {
  let out = '', i = 0, n = src.length;
  while (i < n) {
    if (src.startsWith('//', i)) { while (i < n && src[i] !== '\n') { out += ' '; i++; } continue; }
    if (src.startsWith('/*', i)) { while (i < n && !src.startsWith('*/', i)) { out += src[i] === '\n' ? '\n' : ' '; i++; } out += '  '; i += 2; continue; }
    out += src[i++];
  }
  return out;
}
const HIT = /^\s*if\s*\((.+?)\)\s*(?:\w+\s*\[\s*'([a-z_]+)'\s*\]\s*=|'([a-z_]+)'\s*:)/;
const GUARD = /(isNotEmpty|!=\s*null|>\s*0)\s*$/;

function methodSpan(lines, idx) {            // nearest enclosing top-level member body
  let depth = 0;
  for (let i = idx; i >= 0; i--) {
    for (let j = lines[i].length - 1; j >= 0; j--) {
      const c = lines[i][j];
      if (c === '}') depth++;
      else if (c === '{') { if (depth === 0) {
        if (/^\s{0,4}\S/.test(lines[i]) && /\)\s*(async\s*)?\{\s*$|=>\s*\{\s*$|\{\s*$/.test(lines[i]) && /\w+\s*\(/.test(lines[i])) {
          let d = 0, end = lines.length - 1;
          outer: for (let k = i; k < lines.length; k++) for (const ch of lines[k]) { if (ch === '{') d++; else if (ch === '}' && --d === 0) { end = k; break outer; } }
          return [i, end];
        } } else depth--; }
    }
  }
  return [0, lines.length - 1];
}
const hits = [];
for (const f of fs.readdirSync(root, { recursive: true })) {
  if (!f.endsWith('.dart')) continue;
  const abs = path.join(root, f); const lines = stripComments(fs.readFileSync(abs, 'utf8')).split('\n');
  const relFile = f.split(path.sep).join('/');
  const builderSpans = builders.filter(b => b.file === relFile).map(b => {
    const sp = spanOf(lines, b.function);
    if (!sp) { console.log(`FAIL declared update-payload builder not found: ${b.file} ${b.function}(`); process.exitCode = 1; }
    return sp;
  }).filter(Boolean);
  lines.forEach((ln, i) => {
    const m = ln.match(HIT); if (!m || !GUARD.test(m[1].trim())) return;
    const [s, e] = methodSpan(lines, i); const body = lines.slice(s, e + 1).join('\n');
    const rel = f.split(path.sep).join('/');
    const viaHelper = indirect.some(w => w.file === rel && new RegExp(`\\b${w.call}\\s*\\(`).test(body));
    const inBuilder = builderSpans.some(([a, b]) => i >= a && i <= b);
    const kind = /\.(update|upsert)\s*\(/.test(body) || viaHelper || inBuilder ? 'UPDATE' : null;
    if (kind) hits.push({ file: f.split(path.sep).join('/'), column: m[2] ?? m[3], line: i + 1 });
  });
}
const manifest = manifestDoc.entries;
for (const w of indirect) {
  const src = fs.existsSync(path.join(root, w.file)) ? fs.readFileSync(path.join(root, w.file), 'utf8') : '';
  if (!new RegExp(`\\b${w.call}\\s*\\(`).test(stripComments(src))) { console.log(`FAIL declared indirect writer not found: ${w.file} ${w.call}(`); process.exitCode = 1; }
}
const key = h => `${h.file}#${h.column}`;
const found = new Map(hits.map(h => [key(h), h])); const known = new Map(manifest.map(e => [key(e), e]));
if (process.argv.includes('--list')) { for (const h of hits) console.log(`${h.file}:${h.line}\t${h.column}\t${known.get(key(h))?.classification ?? 'UNCLASSIFIED'}`); process.exit(0); }
const unclassified = [...found.keys()].filter(k => !known.has(k));
const stale = [...known.keys()].filter(k => !found.has(k));
console.log(`guarded writes in UPDATE/UPSERT methods: ${hits.length} · manifest: ${manifest.length}`);
for (const k of unclassified) console.log(`FAIL unclassified guarded write: ${found.get(k).file}:${found.get(k).line} '${found.get(k).column}'`);
for (const k of stale) console.log(`FAIL manifest entry no longer found (fixed? shrink the manifest): ${k}`);
if (unclassified.length || stale.length || process.exitCode) process.exit(1);
console.log('PASS every guarded write is classified and every manifest entry is live');
