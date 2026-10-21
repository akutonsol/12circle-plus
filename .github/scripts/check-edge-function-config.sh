#!/usr/bin/env bash
# E-09 · every Edge Function declares its JWT posture explicitly.
#
# An undeclared function inherits the platform default (`verify_jwt = true`),
# which is a posture nobody chose. For `stripe-webhook` that default 401s every
# Stripe delivery; for the rest it reads like protection while only proving the
# caller holds the published anon key.
#
# This guard fails when config.toml and supabase/functions/ disagree in either
# direction, so adding a function forces a decision about how it is reached.
#
#   .github/scripts/check-edge-function-config.sh   (or: npm run check:functions)
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

node - <<'NODE'
const fs = require('fs');
const cfg = fs.readFileSync('supabase/config.toml', 'utf8');

const declared = [...cfg.matchAll(/^\[functions\.([a-z0-9-]+)\]\s*$/gm)].map(m => m[1]);
const present = fs.readdirSync('supabase/functions')
  .filter(f => fs.statSync(`supabase/functions/${f}`).isDirectory());

let fail = false;
const say = (ok, msg) => { console.log(`${ok ? 'OK  ' : 'FAIL'} — ${msg}`); if (!ok) fail = true; };

const undeclared = present.filter(f => !declared.includes(f));
say(!undeclared.length,
  undeclared.length
    ? `these functions have no [functions.<name>] block: ${undeclared.join(', ')}`
    : `all ${present.length} functions declare a JWT posture`);

const phantom = declared.filter(f => !present.includes(f));
say(!phantom.length,
  phantom.length
    ? `config.toml declares functions that do not exist: ${phantom.join(', ')}`
    : 'config.toml declares no function that is missing from disk');

const dupes = declared.filter((f, i) => declared.indexOf(f) !== i);
say(!dupes.length, dupes.length ? `duplicate blocks: ${dupes.join(', ')}` : 'no duplicate blocks');

// Every block must actually carry the setting, not just exist.
for (const name of declared) {
  const block = cfg.split(`[functions.${name}]`)[1] ?? '';
  const body = block.split(/^\[/m)[0];
  if (!/^verify_jwt\s*=\s*(true|false)\s*$/m.test(body)) {
    say(false, `[functions.${name}] does not set verify_jwt`);
  }
}

// Exactly one function may skip JWT verification, and it is the one that
// authenticates its caller by Stripe signature instead.
const open = declared.filter(name => {
  const body = (cfg.split(`[functions.${name}]`)[1] ?? '').split(/^\[/m)[0];
  return /^verify_jwt\s*=\s*false\s*$/m.test(body);
});
say(open.length === 1 && open[0] === 'stripe-webhook',
  open.length === 1 && open[0] === 'stripe-webhook'
    ? 'stripe-webhook is the only function with verify_jwt = false'
    : `unexpected verify_jwt = false on: ${open.join(', ') || '(none)'} — a function that skips JWT verification must authenticate its caller some other way; say how, here`);

// And that exception is only safe while the signature check is still there.
const wh = fs.readFileSync('supabase/functions/stripe-webhook/index.ts', 'utf8');
const guarded = wh.includes('stripe-signature') && wh.includes('constructEventAsync');
say(guarded,
  guarded
    ? 'stripe-webhook still verifies its Stripe signature'
    : 'stripe-webhook has verify_jwt = false but no longer verifies the Stripe signature — it is now open');

process.exit(fail ? 1 : 0);
NODE
