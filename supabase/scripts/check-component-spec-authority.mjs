#!/usr/bin/env node
// V5 §218 · DESIGN-02's ratified boundary, held open.
//
// WHAT WAS RATIFIED, 2026-10-12. `D2-1a` made the derived specifications in
// `COMPONENT-SPECS.md` authoritative for the **24 components the approved screens
// actually depict** — and for nothing else. `D2-2b` ratified four more that the
// screens do depict, and left four that they do NOT:
//
//     radio · date range · toast · inline error
//
// Those four are ENUMERATED in `COMPONENTS.md` (which is why they are among the
// 32) but their anatomy and behaviour are not stated anywhere approved:
// `COMPONENTS.md` routes behaviour to "the page files", and the page files do not
// depict them. Specifying them therefore needs the owner input requested as
// `D2-3`, which is unanswered.
//
// THE DEFECT THIS EXISTS FOR, and it is a shape this programme has hit before.
// A boundary that lives only in prose decays silently. §213.2 recorded a measurement
// of these very components that was wrong for six weeks because a broken shell loop
// returned zeros and nothing checked that the probe worked. The risk here is the
// mirror of that: somebody — plausibly me, in a later session, reading "provide
// specifications for the four genuinely absent components" and forgetting that the
// visual details were explicitly NOT authorized — writes a `### Toast` section, and
// an invented design becomes indistinguishable from a ratified one.
//
// So this asserts the ratified SET, not the citations. `check-design-citations.mjs`
// already proves every cited path resolves; nothing proved the membership.
//
// It fails loudly if a spec appears for a component whose design input is still
// pending, and the failure names `D2-3` so the reader knows what to ask for rather
// than deleting the section to get green.
import { readFileSync } from 'node:fs';

const SPECS = 'docs/design/admin-dashboard/COMPONENT-SPECS.md';

// The 24 ratified under D2-1a, verbatim from the file at the time of ratification.
const RATIFIED = [
  'Environment strip', 'Header + six-item nav', 'User menu', 'Search',
  'Card', 'Panel', 'Drawer', 'Dialog', 'Menu item', 'Region',
  'Table', 'Stat tile', 'Chart', 'Severity badge', 'Status pill',
  'Progress bar', 'Tab', 'Text input', 'Select', 'Segmented control',
  'Switch', 'Checkbox', 'Degraded banner', 'Empty state',
];

// Absent from the approved screens. A spec for any of these needs D2-3 answered.
const AWAITING_D2_3 = ['radio', 'date range', 'toast', 'inline error'];

const src = readFileSync(SPECS, 'utf8');
const headings = [...src.matchAll(/^### (.+)$/gm)].map((m) => m[1].trim());

const problems = [];

if (headings.length !== RATIFIED.length) {
  problems.push(
    `COMPONENT-SPECS.md has ${headings.length} '###' sections; D2-1a ratified `
    + `${RATIFIED.length}. Added or removed specifications change what the ratification `
    + `covers, so the register and this list must move together.`);
}

const missing = RATIFIED.filter((r) => !headings.includes(r));
if (missing.length) {
  problems.push(`ratified specifications no longer present: ${missing.join(', ')}`);
}

const extra = headings.filter((h) => !RATIFIED.includes(h));
for (const h of extra) {
  const pending = AWAITING_D2_3.find((a) => h.toLowerCase().includes(a));
  problems.push(pending
    ? `'### ${h}' specifies '${pending}', which the approved screens do NOT depict. `
      + `Its visual details were explicitly NOT authorized — D2-3 requests the minimum `
      + `design input and is UNANSWERED. Do not delete this section to get green: either `
      + `D2-3 was answered (update RATIFIED here and the register together) or this is an `
      + `invented design presented as ratified.`
    : `'### ${h}' is not in D2-1a's ratified 24. If it was newly ratified, add it here and `
      + `to the register in the same change.`);
}

if (problems.length) {
  console.error('FAIL — DESIGN-02 ratified-set drift:');
  for (const p of problems) console.error(`  · ${p}`);
  process.exit(1);
}

console.log(`PASS — ${headings.length}/${RATIFIED.length} D2-1a specifications intact; `
  + `no specification exists for the ${AWAITING_D2_3.length} components awaiting D2-3 `
  + `(${AWAITING_D2_3.join(', ')}).`);
