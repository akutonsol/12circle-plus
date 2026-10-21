#!/usr/bin/env node
// V5 §164 · generate the Admin Tier-3 token layer FROM the published design source.
//
// WHY THIS IS GENERATED AND NOT WRITTEN BY HAND. 130 `--adm-*` values transcribed by
// hand is 130 chances to make the mistake I already made once: DESIGN-02's first
// draft mapped `border: 0` to `--adm-type-caption-tracking` because both happened to
// be `0` (V5 §146). A generator cannot make that mistake, and `--check` makes a
// hand-edit of the output fail CI instead of silently becoming the new truth.
//
// WHY THE SOURCE IS READ FROM A COMMIT AND NOT FROM THE WORKING TREE. The published
// design authority — `admin.tokens.css`, `admin.contrast.md`, `RESPONSIVE.md`,
// `admin-icon-inventory.md` — lives on `design/12circle-plus-admin-dashboard` and is
// NOT an ancestor of this branch. Reading it at a pinned commit makes the provenance
// exact and immutable, and needs no merge of the design branch into this one.
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, existsSync } from 'node:fs';

const SOURCE_COMMIT = '931218b';
const SOURCE_PATH = 'docs/design/brand/tokens/admin.tokens.css';
const OUT = 'apps/mobile/lib/features/admin/presentation/admin_tokens.dart';

function readSource() {
  let css;
  try {
    css = execFileSync('git', ['show', `${SOURCE_COMMIT}:${SOURCE_PATH}`],
      { encoding: 'utf8', maxBuffer: 8 << 20 });
  } catch {
    throw new Error(
      `cannot read ${SOURCE_PATH} at ${SOURCE_COMMIT}. That commit publishes the ` +
      'approved design authority and lives on design/12circle-plus-admin-dashboard. ' +
      'Fetch that ref — do NOT substitute hand-written values for it.');
  }
  // POSITIVE CONTROL. A parse that finds nothing must fail, not emit an empty token
  // file that every downstream check then reports as clean (V5 §139.3).
  const decls = [...css.matchAll(/--adm-([a-z0-9-]+)\s*:\s*([^;]+);/gi)]
    .map(([, name, value]) => ({ name, value: value.trim() }));
  if (decls.length < 100) {
    throw new Error(`parsed only ${decls.length} --adm-* tokens from ${SOURCE_PATH}; ` +
      'the published file declares 126 (the count COMPONENT-SPECS:14 states). ' +
      'Refusing to generate from a broken parse.');
  }
  for (const canary of ['color-bg-canvas', 'radius-xl', 'space-8']) {
    if (!decls.some((d) => d.name === canary)) {
      throw new Error(`the parse did not find --adm-${canary}, which the published ` +
        'file definitely contains — the parse is broken, not the design');
    }
  }
  return decls;
}

const camel = (s) => s.replace(/-([a-z0-9])/g, (_, c) => c.toUpperCase());

// Colors become Dart `Color`s; everything else is carried as the literal source
// string, so nothing is silently reinterpreted. A `clamp()` gutter, an `em`
// tracking and a CSS font stack have no Flutter equivalent and are NOT invented
// here — they are exposed verbatim for a caller that knows what to do with them.
function dartColor(v) {
  let m = /^#([0-9a-f]{6})$/i.exec(v);
  if (m) return `Color(0xFF${m[1].toUpperCase()})`;
  m = /^rgba\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*([0-9.]+)\s*\)$/i.exec(v);
  if (m) {
    const a = Math.round(parseFloat(m[4]) * 255).toString(16).padStart(2, '0');
    const hex = [m[1], m[2], m[3]]
      .map((n) => Number(n).toString(16).padStart(2, '0')).join('');
    return `Color(0x${a.toUpperCase()}${hex.toUpperCase()})`;
  }
  return null;
}

// Flutter dimensions are `double`, always. Emitting `14` for a 14px token compiles
// as an `int` and then fails at every call site that wants a size — so the `.0` is
// added HERE, once, rather than being patched in at each use.
const px = (v) => {
  const m = /^(-?[0-9.]+)px$/.exec(v);
  if (!m) return null;
  return m[1].includes('.') ? m[1] : `${m[1]}.0`;
};
const unitless = (v) => (/^-?[0-9.]+$/.test(v) ? v : null);

function emit(decls) {
  const colors = [];
  const dims = [];
  const nums = [];
  const raw = [];
  for (const { name, value } of decls) {
    const id = camel(name);
    const c = name.startsWith('color-') ? dartColor(value) : null;
    if (c) { colors.push({ id, value: c, src: `--adm-${name}: ${value}` }); continue; }
    const p = px(value);
    if (p !== null) { dims.push({ id, value: p, src: `--adm-${name}: ${value}` }); continue; }
    const u = unitless(value);
    if (u !== null) { nums.push({ id, value: u, src: `--adm-${name}: ${value}` }); continue; }
    raw.push({ id, value, src: `--adm-${name}: ${value}` });
  }
  const line = (g) => g
    .map(({ id, value, src }) => `  /// \`${src}\`\n  static const ${id} = ${value};`)
    .join('\n');
  const rawLine = raw
    .map(({ id, value, src }) =>
      `  /// \`${src}\`\n  static const ${id} = ${JSON.stringify(value)};`)
    .join('\n');

  return `// GENERATED FILE — DO NOT EDIT BY HAND.
//
// Source of truth: \`${SOURCE_PATH}\` at commit \`${SOURCE_COMMIT}\`, the approved
// 12Circle+ Admin design authority. That commit lives on
// \`design/12circle-plus-admin-dashboard\` and is NOT an ancestor of this branch, so
// the values below are pinned to it rather than to a working-tree path.
//
// Regenerate with:  node supabase/scripts/gen-admin-tokens.mjs
// CI verifies with: node supabase/scripts/gen-admin-tokens.mjs --check
//
// ${decls.length} tokens. Every doc comment quotes the exact source declaration, so a
// value can be traced to the design without leaving the file.
//
// THIS IS TIER 3. The Helix rule is that components consume semantic tokens and never
// raw hex, which is precisely what the existing admin screen's \`const _brand =
// Color(0xFFA855F7)\` violates. New Admin UI reads from here.
//
// NOT EVERY TOKEN BECOMES A FLUTTER VALUE. A \`clamp()\` gutter, an \`em\` tracking and a
// CSS font stack have no Flutter equivalent; they are exposed as the literal source
// string under [AdminTokensRaw] rather than converted into a guess.
library;

import 'package:flutter/painting.dart';

/// Colors from the published \`--adm-color-*\` set.
abstract final class AdminColors {
${line(colors)}
}

/// Pixel dimensions — spacing, radii, sizes, type sizes. All \`double\`, because
/// every Flutter dimension is.
abstract final class AdminDims {
${line(dims)}
}

/// Unitless numbers — line heights, font weights, z-indices, opacities. These keep
/// the source literal's own type: a line height of \`1.3\` is a double, a font
/// weight of \`500\` is an int, because that is what each one is.
abstract final class AdminNums {
${line(nums)}
}

/// Values with no Flutter equivalent, carried verbatim so nothing is reinterpreted.
abstract final class AdminTokensRaw {
${rawLine}
}
`;
}

const decls = readSource();
const generated = emit(decls);
const check = process.argv.includes('--check');

if (check) {
  if (!existsSync(OUT)) {
    console.error(`  FAIL — ${OUT} does not exist. Run the generator.`);
    process.exit(1);
  }
  const onDisk = readFileSync(OUT, 'utf8');
  if (onDisk !== generated) {
    console.error(`  FAIL — ${OUT} does not match the published design tokens at ` +
      `${SOURCE_COMMIT}:${SOURCE_PATH}.\n` +
      '  Either the file was hand-edited, or the design source changed. Regenerate ' +
      'with:\n    node supabase/scripts/gen-admin-tokens.mjs');
    process.exit(1);
  }
  console.log(`  OK — ${OUT} matches all ${decls.length} published --adm-* tokens ` +
    `at ${SOURCE_COMMIT}.`);
} else {
  writeFileSync(OUT, generated);
  console.log(`  wrote ${OUT} — ${decls.length} tokens from ${SOURCE_COMMIT}:${SOURCE_PATH}`);
}
