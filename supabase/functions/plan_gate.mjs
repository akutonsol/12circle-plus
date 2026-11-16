// The server side of the app's PaywallGate, for the AI functions.
//
// The app hides AI Coach and AI Nutrition behind `PaywallGate`
// (apps/mobile/lib/core/router/app_router.dart) and its rule
// (apps/mobile/lib/features/payments/presentation/paywall_gate.dart):
//   * a coach always passes -- their plan is a coach plan, not a client plan;
//   * a client passes when `client_plan()` ranks at or above the screen's tier.
// The functions behind those screens checked only that the caller was signed in,
// so any account -- free included -- could call them directly and spend the AI
// budget the paywall reserves for paid plans. This applies the SAME rule, with
// the SAME tier the app applies at each function's entry points. It decides no
// tier of its own.
//
// Plain JavaScript (no imports, no TypeScript) so Deno imports it from each
// function and Node's test runner exercises it unchanged:
// supabase/tests/functions/plan_gate.test.mjs.

/** Tier order, as `ClientPlanCaps.rank` in entitlements.dart. */
export const PLAN_RANK = Object.freeze({
  free: 0,
  self_guided: 1,
  ai_guided: 2,
  coach_guided: 3,
});

/**
 * Whether the signed-in caller may use a feature that needs at least [min].
 *
 * [userDb] is a Supabase client carrying the CALLER's JWT: `client_plan()`
 * answers for `auth.uid()`, and the caller's own profile row is readable to
 * them. Returns `{ ok: true }`, or `{ ok: false, status, body }` for the
 * function to return as-is:
 *   * 403 `plan_required` -- the caller's plan is below [min];
 *   * 503 `plan_unverified` -- the plan could not be read. Fail CLOSED: an
 *     unread plan is not a paid plan, and a paid resource is not spent on it.
 */
export async function checkPlan(userDb, uid, min) {
  if (!(min in PLAN_RANK)) throw new Error(`unknown tier: ${min}`);

  const { data: profile, error: profileError } = await userDb
    .from('user_profiles').select('role').eq('id', uid).maybeSingle();
  if (profileError) return unverified();
  if (profile?.role === 'coach') return { ok: true };

  const { data: plan, error: planError } = await userDb.rpc('client_plan');
  if (planError || typeof plan !== 'string') return unverified();

  const rank = PLAN_RANK[plan] ?? 0; // an unknown plan is no paid plan
  if (rank >= PLAN_RANK[min]) return { ok: true };
  return {
    ok: false,
    status: 403,
    body: { error: 'plan_required', required: min, plan },
  };
}

function unverified() {
  return {
    ok: false,
    status: 503,
    body: { error: 'plan_unverified', message: 'Could not verify your plan. Try again.' },
  };
}
