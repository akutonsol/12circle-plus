// D-02 (P0) — vertical privilege escalation through user_profiles.
//
// TWO independent root causes, both reproduced live on QA:
//
//   1. `users can update own profile` allowed the owner to write ANY column, so
//      PATCH user_profiles?id=eq.self {role:'admin'} returned 200 and the caller
//      immediately passed is_admin() — admin_recent_users() then returned every
//      user's name and email.
//   2. handle_new_user() (migration 044) copied `role` straight out of
//      raw_user_meta_data, which is caller-supplied at signup. An attacker never
//      needed step 1: they could simply sign up as an admin.
//
// Also asserted here: the PAR-Q risk classification. Intake computed risk_score /
// risk_level / risk_flags in Dart and wrote them from the client, so a high-risk
// member could self-declare 'low' and defeat the Q-4 training constraint. Those
// columns are now derived server-side from parq_answers.
import { rest, rpc, svc, mutate, blocked, landed, signIn, adminFindUser,
         check, section, summary, n, loadIds, URL_, ANON, SERVICE } from './lib.mjs';

const P = 'user_profiles';
const ids = await loadIds();
const attacker = await signIn('attacker');
const coach    = await signIn('coach');
const admin    = await signIn('admin');

const roleOf = async (id) => (await svc(`${P}?id=eq.${id}&select=role`)).body?.[0]?.role;
// Reset EVERY column this suite touches. A partial reset makes the next run's
// write a no-op, which reads as "blocked" and would hide a regression.
const PRISTINE = {
  role: 'client', membership_tier: 'basic', marketplace_commission_rate: 0.10,
  stripe_customer_id: null, stripe_account_id: null, stripe_charges_enabled: false,
  stripe_payouts_enabled: false, stripe_details_submitted: false, is_demo: true,
  parq_answers: {},
};
const restore = async () => {
  const r = await svc(`${P}?id=eq.${ids.attacker}`, { method: 'PATCH', body: PRISTINE });
  if (r.status >= 300) throw new Error(`reset failed: ${r.status} ${JSON.stringify(r.body)}`);
};
await restore();

// ═══ 1. self-escalation through a profile update ═══════════════════════════
section('1. Self-service role escalation');
for (const role of ['admin', 'coach', 'vendor', 'content_manager']) {
  const m = await mutate(attacker, `${P}?id=eq.${ids.attacker}`, 'PATCH', { role });
  const now = await roleOf(ids.attacker);
  check(`client cannot self-assign role = ${role}`, blocked(m) && now === 'client',
        `status=${m.status} affected=${m.affected} role=${now}`);
}

// ═══ 2. the other privilege columns ════════════════════════════════════════
section('2. Entitlement and billing columns');
{
  const tier = await mutate(attacker, `${P}?id=eq.${ids.attacker}`, 'PATCH',
    { membership_tier: 'elite' });
  check('client cannot self-assign membership_tier', blocked(tier), `status=${tier.status}`);

  const comm = await mutate(attacker, `${P}?id=eq.${ids.attacker}`, 'PATCH',
    { marketplace_commission_rate: 0 });
  check('client cannot zero their marketplace commission', blocked(comm), `status=${comm.status}`);

  const stripe = await mutate(attacker, `${P}?id=eq.${ids.attacker}`, 'PATCH',
    { stripe_account_id: 'acct_P1_FORGED', stripe_charges_enabled: true,
      stripe_payouts_enabled: true });
  check('client cannot forge Stripe Connect state', blocked(stripe), `status=${stripe.status}`);

  const demo = await mutate(attacker, `${P}?id=eq.${ids.attacker}`, 'PATCH', { is_demo: false });
  check('client cannot clear their is_demo flag', blocked(demo), `status=${demo.status}`);
}

// ═══ 3. the amplifier — admin surface must stay shut ═══════════════════════
section('3. Admin surface after a failed escalation');
{
  await mutate(attacker, `${P}?id=eq.${ids.attacker}`, 'PATCH', { role: 'admin' });
  check('role is still client after the escalation attempt',
        (await roleOf(ids.attacker)) === 'client', `role=${await roleOf(ids.attacker)}`);
  const users = await rpc(attacker, 'admin_recent_users', {});
  check('client cannot call admin_recent_users', users.status >= 400 || n(users.body) === 0,
        `status=${users.status} rows=${n(users.body)}`);
  const stats = await rpc(attacker, 'admin_platform_stats', {});
  const leaked = stats.status < 300 && stats.body && typeof stats.body === 'object'
                 && !Array.isArray(stats.body) && Object.keys(stats.body).length > 0;
  check('client cannot call admin_platform_stats', !leaked,
        `status=${stats.status} ${JSON.stringify(stats.body || '').slice(0, 90)}`);
}

// ═══ 4. signup metadata route ══════════════════════════════════════════════
section('4. Role injected through signup metadata');
{
  // handle_new_user() fires on any auth.users INSERT, so the admin create API
  // exercises exactly the same trigger as /auth/v1/signup while avoiding the
  // project's outbound-email rate limit. The public route is probed too, and a
  // 429 is reported as "not exercised" rather than quietly counted as a pass.
  const mk = async (email, meta) => {
    const ex = await adminFindUser(email);
    if (ex) await fetch(`${URL_}/auth/v1/admin/users/${ex.id}`, { method: 'DELETE',
      headers: { apikey: SERVICE, Authorization: `Bearer ${SERVICE}` } });
    const r = await fetch(`${URL_}/auth/v1/admin/users`, {
      method: 'POST',
      headers: { apikey: SERVICE, Authorization: `Bearer ${SERVICE}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password: 'P1-Signup-Probe-2026!', email_confirm: true,
                             user_metadata: meta }),
    });
    const b = await r.json().catch(() => null);
    return b?.id || null;
  };
  const rm = async (id) => id && fetch(`${URL_}/auth/v1/admin/users/${id}`, { method: 'DELETE',
    headers: { apikey: SERVICE, Authorization: `Bearer ${SERVICE}` } });

  for (const requested of ['admin', 'content_manager', 'superuser']) {
    const id = await mk(`p1-signup-${requested}@qa.12circle.test`,
      { first_name: 'P1', last_name: requested, role: requested });
    const got = id ? await roleOf(id) : null;
    check(`signup metadata role='${requested}' degrades to client`, got === 'client', `role=${got}`);
    await rm(id);
  }

  // Self-service coach / vendor registration is the product's open model.
  for (const requested of ['coach', 'vendor', 'client']) {
    const id = await mk(`p1-signup-${requested}@qa.12circle.test`,
      { first_name: 'P1', last_name: requested, role: requested });
    const got = id ? await roleOf(id) : null;
    check(`self-service ${requested} registration still works`, got === requested, `role=${got}`);
    await rm(id);
  }

  // The real public route, best effort.
  const pubEmail = 'p1-signup-public@qa.12circlefitness.com';
  const ex = await adminFindUser(pubEmail);
  if (ex) await rm(ex.id);
  const pub = await fetch(`${URL_}/auth/v1/signup`, {
    method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: pubEmail, password: 'P1-Signup-Probe-2026!',
      data: { first_name: 'P1', last_name: 'public', role: 'admin' } }),
  });
  const pb = await pub.json().catch(() => null);
  const pubId = pb?.id || pb?.user?.id;
  if (pub.status === 429) {
    console.log('  SKIP  public /auth/v1/signup — project email rate limit (429); ' +
                'the same handle_new_user() trigger is covered above');
  } else {
    check('public signup cannot mint an admin', pubId ? (await roleOf(pubId)) === 'client' : false,
          `status=${pub.status} role=${pubId ? await roleOf(pubId) : 'n/a'}`);
    await rm(pubId);
  }
}

// ═══ 5. coach-side write into a client's privilege columns ═════════════════
section('5. Coach writing a client privilege column');
{
  const REL = 'coach_client_relationships';
  await svc(`${REL}?client_id=eq.${ids.attacker}`, { method: 'DELETE' });
  await svc(REL, { method: 'POST', body: { coach_id: ids.coach, client_id: ids.attacker,
    status: 'active', initiated_by: 'client', activated_at: new Date().toISOString() } });

  const m = await mutate(coach, `${P}?id=eq.${ids.attacker}`, 'PATCH', { role: 'admin' });
  const now = await roleOf(ids.attacker);
  check('an active coach cannot promote their client', blocked(m) && now === 'client',
        `status=${m.status} role=${now}`);

  const tier = await mutate(coach, `${P}?id=eq.${ids.attacker}`, 'PATCH',
    { membership_tier: 'elite' });
  check('an active coach cannot grant their client an entitlement', blocked(tier),
        `status=${tier.status}`);

  await svc(`${REL}?client_id=eq.${ids.attacker}`, { method: 'DELETE' });
}

// ═══ 6. legitimate mutable fields still writable ═══════════════════════════
section('6. Legitimate profile edits still work');
{
  const personal = await mutate(attacker, `${P}?id=eq.${ids.attacker}`, 'PATCH',
    { first_name: 'P1', last_name: 'attacker', gender: 'prefer_not_to_say',
      phone: '+15550100', height_cm: 180, weight_kg: 80, weight_goal_kg: 75,
      fitness_goal: 'lose_fat', activity_level: 'moderate', training_days_per_week: 4,
      training_location: 'gym', nutrition_goal: 'deficit', unit_preference: 'metric' });
  check('client can edit personal_info_screen fields', landed(personal),
        `status=${personal.status} ${JSON.stringify(personal.body || '').slice(0, 120)}`);

  const intake = await mutate(attacker, `${P}?id=eq.${ids.attacker}`, 'PATCH',
    { onboarding_step: 3, onboarding_complete: false, coaching_mode: 'self_guided',
      experience_level: 'beginner', sleep_hours: '7', stress_level: 3,
      occupation: 'desk', consent_agreed: true, has_injuries: false });
  check('client can write intake fields', landed(intake), `status=${intake.status}`);

  const notif = await mutate(attacker, `${P}?id=eq.${ids.attacker}`, 'PATCH',
    { notif_workout_reminders: false, notif_coach_messages: true });
  check('client can change notification preferences', landed(notif), `status=${notif.status}`);

  const business = await mutate(coach, `${P}?id=eq.${ids.coach}`, 'PATCH',
    { bio: 'P1 coach bio', pricing_monthly: 199, years_experience: 5, tagline: 'P1',
      specialties: ['strength'], certifications: ['NASM'], max_clients: 25,
      is_accepting_clients: true, coach_title: 'Head Coach' });
  check('coach can edit their business profile', landed(business), `status=${business.status}`);
}

// ═══ 7. PAR-Q risk is server-derived (Q-4) ═════════════════════════════════
section('7. PAR-Q risk classification authority');
{
  // Q1 = heart condition -> high risk, no matter what the client claims.
  const m = await mutate(attacker, `${P}?id=eq.${ids.attacker}`, 'PATCH',
    { parq_answers: { '1': true, '2': false }, risk_level: 'low', risk_score: 0, risk_flags: '' });
  check('the PAR-Q answers themselves are writable by the member', landed(m), `status=${m.status}`);

  const row = (await svc(`${P}?id=eq.${ids.attacker}&select=risk_level,risk_score,risk_flags`)).body?.[0];
  check('a self-declared low risk is overridden by the server', row?.risk_level === 'high',
        JSON.stringify(row));
  check('risk_score is derived from the answers', Number(row?.risk_score) === 1, JSON.stringify(row));
  check('risk_flags name the triggering condition',
        String(row?.risk_flags || '').includes('heart_condition'), JSON.stringify(row));

  const clean = await mutate(attacker, `${P}?id=eq.${ids.attacker}`, 'PATCH',
    { parq_answers: { '1': false, '2': false }, risk_level: 'high' });
  const row2 = (await svc(`${P}?id=eq.${ids.attacker}&select=risk_level,risk_score`)).body?.[0];
  check('clearing the answers re-derives a low risk', landed(clean) && row2?.risk_level === 'low',
        JSON.stringify(row2));
}

// ═══ 8. the legitimate privileged assignment path ══════════════════════════
section('8. Privileged role assignment');
{
  const byClient = await rpc(attacker, 'admin_set_user_role',
    { target_user: ids.attacker, new_role: 'admin' });
  check('a client cannot call admin_set_user_role', byClient.status >= 400,
        `status=${byClient.status} ${JSON.stringify(byClient.body || '').slice(0, 90)}`);
  check('...and the role did not move', (await roleOf(ids.attacker)) === 'client');

  const byCoach = await rpc(coach, 'admin_set_user_role',
    { target_user: ids.coach, new_role: 'admin' });
  check('a coach cannot call admin_set_user_role', byCoach.status >= 400, `status=${byCoach.status}`);

  const byAdmin = await rpc(admin, 'admin_set_user_role',
    { target_user: ids.attacker, new_role: 'coach' });
  check('an admin CAN assign a role', byAdmin.status < 300,
        `status=${byAdmin.status} ${JSON.stringify(byAdmin.body || '').slice(0, 90)}`);
  check('...and the assignment landed', (await roleOf(ids.attacker)) === 'coach');

  const bogus = await rpc(admin, 'admin_set_user_role',
    { target_user: ids.attacker, new_role: 'superuser' });
  check('an unknown role is rejected even for an admin', bogus.status >= 400, `status=${bogus.status}`);

  const back = await rpc(admin, 'admin_set_user_role',
    { target_user: ids.attacker, new_role: 'client' });
  check('an admin can demote back to client',
        back.status < 300 && (await roleOf(ids.attacker)) === 'client', `status=${back.status}`);

  const anonCall = await rpc('anon', 'admin_set_user_role',
    { target_user: ids.attacker, new_role: 'admin' });
  check('anon cannot call admin_set_user_role', anonCall.status >= 400, `status=${anonCall.status}`);

  // service_role remains the break-glass path.
  const svcSet = await svc(`${P}?id=eq.${ids.attacker}`, { method: 'PATCH', body: { role: 'client' } });
  check('service_role can still write role directly', svcSet.status < 300, `status=${svcSet.status}`);
}

// ═══ 9. role-derived authorization is still correct ════════════════════════
section('9. Role-derived authorization');
{
  const asAdmin = await rpc(admin, 'admin_recent_users', {});
  check('a real admin can still read the admin surface', asAdmin.status < 300 && n(asAdmin.body) > 0,
        `status=${asAdmin.status} rows=${n(asAdmin.body)}`);
  const asClient = await rpc(attacker, 'admin_recent_users', {});
  check('a client still cannot', asClient.status >= 400 || n(asClient.body) === 0,
        `status=${asClient.status} rows=${n(asClient.body)}`);
}

await restore();
export default summary('D-02 role escalation');
