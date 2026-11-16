// The AI functions enforce the app's paywall on the server.
//
//   node --test supabase/tests/functions/
//
// No network, no credential, no QA project: `checkPlan` is driven with fake
// clients, and the wiring is read from each function's source.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { checkPlan, PLAN_RANK } from '../../functions/plan_gate.mjs';

/** A Supabase client stand-in: the caller's profile row and client_plan(). */
function fakeDb({ role = 'client', plan = 'free', profileError = null, planError = null } = {}) {
  const calls = { rpc: [] };
  return {
    calls,
    from(table) {
      assert.equal(table, 'user_profiles');
      return {
        select: () => ({
          eq: () => ({
            maybeSingle: async () => ({ data: profileError ? null : { role }, error: profileError }),
          }),
        }),
      };
    },
    async rpc(name) {
      calls.rpc.push(name);
      return { data: planError ? null : plan, error: planError };
    },
  };
}

test('a client below the tier is refused with 403 plan_required', async () => {
  for (const [plan, min] of [['free', 'ai_guided'], ['self_guided', 'ai_guided'], ['free', 'self_guided']]) {
    const r = await checkPlan(fakeDb({ plan }), 'u1', min);
    assert.equal(r.ok, false, `${plan} < ${min}`);
    assert.equal(r.status, 403);
    assert.deepEqual(r.body, { error: 'plan_required', required: min, plan });
  }
});

test('a client at or above the tier passes', async () => {
  for (const [plan, min] of [['ai_guided', 'ai_guided'], ['coach_guided', 'ai_guided'],
    ['self_guided', 'self_guided'], ['ai_guided', 'self_guided']]) {
    assert.deepEqual(await checkPlan(fakeDb({ plan }), 'u1', min), { ok: true }, `${plan} >= ${min}`);
  }
});

test("a coach passes without a client plan, as PaywallGate lets coaches through", async () => {
  const db = fakeDb({ role: 'coach', plan: 'free' });
  assert.deepEqual(await checkPlan(db, 'u1', 'ai_guided'), { ok: true });
  assert.deepEqual(db.calls.rpc, [], 'a coach is not asked for a client plan');
});

test('an unreadable plan or profile fails closed with 503, never as a paid plan', async () => {
  const boom = { message: 'network' };
  for (const db of [fakeDb({ planError: boom, plan: 'coach_guided' }), fakeDb({ profileError: boom })]) {
    const r = await checkPlan(db, 'u1', 'self_guided');
    assert.equal(r.ok, false);
    assert.equal(r.status, 503);
    assert.equal(r.body.error, 'plan_unverified');
  }
});

test('an unknown plan string is no paid plan', async () => {
  const r = await checkPlan(fakeDb({ plan: 'platinum' }), 'u1', 'self_guided');
  assert.equal(r.status, 403);
});

test('the tier order matches the app (entitlements.dart rank)', () => {
  const dart = readFileSync(new URL('../../../apps/mobile/lib/features/payments/domain/entitlements.dart', import.meta.url), 'utf8');
  const names = { free: 'free', self_guided: 'selfGuided', ai_guided: 'aiGuided', coach_guided: 'coachGuided' };
  for (const [sql, dartName] of Object.entries(names)) {
    assert.match(dart, new RegExp(`ClientPlan\\.${dartName} => ${PLAN_RANK[sql]},`), `${sql} rank`);
  }
});

// ── Wiring: each function applies the tier its app entry points apply ──────
//   ai-coach, ai-coaching-engine -> only from /ai-coach   (PaywallGate aiGuided)
//   ai-nutrition                 -> /ai-nutrition (aiGuided) and /meal-plan from
//                                   the Meals dashboard (selfGuided): the lower one
//   analyze-food-image           -> the Meals dashboard scan (selfGuided)
const WIRED = {
  'ai-coach': 'ai_guided',
  'ai-coaching-engine': 'ai_guided',
  'ai-nutrition': 'self_guided',
  'analyze-food-image': 'self_guided',
};
const src = (name) => readFileSync(new URL(`../../functions/${name}/index.ts`, import.meta.url), 'utf8');

for (const [name, tier] of Object.entries(WIRED)) {
  test(`${name} checks the plan (${tier}) before it calls the model`, () => {
    const s = src(name);
    assert.match(s, /import \{ checkPlan \} from '\.\.\/plan_gate\.mjs';/);
    const call = s.indexOf(`checkPlan(userDb, `);
    assert.ok(call > 0, 'checkPlan is called');
    assert.ok(s.slice(call, call + 80).includes(`'${tier}'`), `with tier ${tier}`);
    assert.match(s.slice(call), /^checkPlan\([^)]*\);\s*\n\s*if \(!gate\.ok\) return json\(gate\.body, gate\.status\);/);
    const model = s.indexOf('https://api.anthropic.com');
    assert.ok(model > call, 'the plan is checked before the first model call');
  });
}

test('ai-generate-workout is NOT gated: its tier is an open product decision', () => {
  // The button is on the ungated /workouts list (every plan), while
  // `canGenerateProgram` says AI-Guided and is used by no screen. Which one is
  // the policy is Julia's call; when she makes it, gate it and delete this.
  assert.doesNotMatch(src('ai-generate-workout'), /plan_gate/);
});
