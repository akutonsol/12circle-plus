// Creates a Stripe Checkout Session for one of the three 12 Circle flows:
//   kind = 'coach'        → client subscribes to a coach (recurring, price from coach.pricing_monthly)
//   kind = 'coach_plan'   → COACH pays platform plan (recurring, tier starter|growth|elite)
//   kind = 'self_guided'  → Self-Guided membership $29/mo (recurring, STRIPE_SELF_GUIDED_PRICE_ID)
//   kind = 'ai_guided'    → AI-Guided membership   $59/mo (recurring, STRIPE_AI_GUIDED_PRICE_ID)
//   kind = 'event_ticket' → buy an event ticket (one-time, price from event.price)
// Runs in test mode until live keys are set. Secret key never leaves the server.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import Stripe from 'https://esm.sh/stripe@16.12.0?target=deno';

const STRIPE_SECRET_KEY = Deno.env.get('STRIPE_SECRET_KEY') ?? '';
const MEMBERSHIP_PRICE_IDS: Record<string, string> = {
  self_guided: Deno.env.get('STRIPE_SELF_GUIDED_PRICE_ID') ?? '',
  ai_guided: Deno.env.get('STRIPE_AI_GUIDED_PRICE_ID') ?? '',
};
const COACH_PLAN_PRICE_IDS: Record<string, string> = {
  starter: Deno.env.get('STRIPE_COACH_STARTER_PRICE_ID') ?? '',
  growth: Deno.env.get('STRIPE_COACH_GROWTH_PRICE_ID') ?? '',
  elite: Deno.env.get('STRIPE_COACH_ELITE_PRICE_ID') ?? '',
};
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') ?? '';

const stripe = new Stripe(STRIPE_SECRET_KEY, {
  apiVersion: '2024-06-20',
  httpClient: Stripe.createFetchHttpClient(),
});

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const authHeader = req.headers.get('Authorization') ?? '';
    const userDb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user } } = await userDb.auth.getUser();
    if (!user) return json({ error: 'Unauthorized' }, 401);

    const { kind, coachId, eventId, packageId, tier, successUrl, cancelUrl, embedded, returnUrl } =
      await req.json() as {
        kind: 'coach' | 'coach_plan' | 'self_guided' | 'ai_guided' | 'event_ticket' | 'package';
        coachId?: string;
        eventId?: string;
        packageId?: string;
        tier?: 'starter' | 'growth' | 'elite';
        successUrl?: string;
        cancelUrl?: string;
        embedded?: boolean;     // true → Stripe Embedded Checkout (returns client_secret)
        returnUrl?: string;     // embedded completion redirect
      };

    const db = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

    // K-08 · a second live subscription for what the user already pays for is a
    // double charge: nothing here checked, and every call minted another Stripe
    // subscription. Refuse BEFORE any Stripe call (no customer, no session).
    //   membership  -> any live self/AI membership: change it in place
    //                  (update-subscription), never buy a second one;
    //   coach_plan  -> any live coach plan: two plans bill twice and the later
    //                  webhook overwrites max_clients;
    //   coach       -> a live subscription to THIS coach.
    // Recurring packages are not checked: the subscription row does not record
    // which package it is, and whether two packages from one coach may run at
    // once is an open owner decision.
    const LIVE = ['active', 'trialing', 'past_due', 'incomplete', 'unpaid'];
    const sameProduct: Record<string, string[]> = {
      self_guided: ['self_guided', 'ai_guided'],
      ai_guided: ['self_guided', 'ai_guided'],
      coach_plan: ['coach_plan'],
      coach: ['coach'],
    };
    if (sameProduct[kind]) {
      if (kind === 'coach' && !coachId) return json({ error: 'coachId required' }, 400);
      let existingQuery = db
        .from('subscriptions')
        .select('id, kind, status')
        .eq('user_id', user.id)
        .in('kind', sameProduct[kind])
        .in('status', LIVE);
      if (kind === 'coach') existingQuery = existingQuery.eq('coach_id', coachId!);
      const { data: existing, error: existingError } = await existingQuery.limit(1).maybeSingle();
      if (existingError) {
        // Unknown is not "none": a failed check must not become a second charge.
        return json({ error: 'Could not check your current subscriptions. Try again.' }, 503);
      }
      if (existing) {
        return json({
          error: kind === 'coach_plan'
            ? 'You already have a coach plan. Change or cancel it from Billing first.'
            : kind === 'coach'
              ? 'You already subscribe to this coach.'
              : 'You already have a membership. Change your plan instead of buying a second one.',
          code: 'already_subscribed',
          subscriptionId: existing.id,
          existingKind: existing.kind,
          existingStatus: existing.status,
        }, 409);
      }
    }

    // Reuse or create the Stripe customer for this user.
    const { data: profile } = await db
      .from('user_profiles')
      .select('stripe_customer_id, email, first_name, last_name')
      .eq('id', user.id)
      .maybeSingle();

    let customerId = profile?.stripe_customer_id as string | null;
    if (!customerId) {
      const customer = await stripe.customers.create({
        email: profile?.email ?? user.email ?? undefined,
        name: [profile?.first_name, profile?.last_name].filter(Boolean).join(' ') || undefined,
        metadata: { supabase_user_id: user.id },
      });
      customerId = customer.id;
      await db.from('user_profiles').update({ stripe_customer_id: customerId }).eq('id', user.id);
    }

    const success = successUrl ?? 'https://12circle.app/payment-success';
    const cancel = cancelUrl ?? 'https://12circle.app/payment-cancel';

    // ── Build the per-kind session parameters (mode, line items, metadata) ──
    let mode: 'subscription' | 'payment';
    // deno-lint-ignore no-explicit-any
    let lineItems: any[];
    let metadata: Record<string, string>;
    let pendingPaymentId: string | null = null;
    let coachingAmountCents = 0; // > 0 → route via the coach's Connect account

    if (kind === 'coach') {
      if (!coachId) return json({ error: 'coachId required' }, 400);
      const { data: coach } = await db
        .from('user_profiles')
        .select('pricing_monthly, first_name, last_name')
        .eq('id', coachId)
        .maybeSingle();
      // A per-client custom price on the relationship overrides the global price.
      const { data: rel } = await db
        .from('coach_client_relationships')
        .select('monthly_price')
        .eq('client_id', user.id)
        .eq('coach_id', coachId)
        .maybeSingle();
      const monthly = Number(rel?.monthly_price ?? coach?.pricing_monthly ?? 0);
      if (!monthly || monthly <= 0) return json({ error: 'Coach has no price set' }, 400);
      coachingAmountCents = Math.round(monthly * 100);
      mode = 'subscription';
      lineItems = [{
        quantity: 1,
        price_data: {
          currency: 'usd',
          unit_amount: Math.round(monthly * 100),
          recurring: { interval: 'month' },
          product_data: {
            name: `Coaching — ${[coach?.first_name, coach?.last_name].filter(Boolean).join(' ') || 'Coach'}`,
          },
        },
      }];
      metadata = { kind: 'coach', user_id: user.id, coach_id: coachId };
    } else if (kind === 'coach_plan') {
      if (!tier) return json({ error: 'tier required (starter|growth|elite)' }, 400);
      const priceId = COACH_PLAN_PRICE_IDS[tier];
      if (!priceId) return json({ error: `Price ID for ${tier} plan not configured` }, 500);
      mode = 'subscription';
      lineItems = [{ price: priceId, quantity: 1 }];
      metadata = { kind: 'coach_plan', user_id: user.id, plan_tier: tier };
    } else if (kind === 'self_guided' || kind === 'ai_guided') {
      const priceId = MEMBERSHIP_PRICE_IDS[kind];
      if (!priceId) return json({ error: `Price ID for ${kind} membership not configured` }, 500);
      mode = 'subscription';
      lineItems = [{ price: priceId, quantity: 1 }];
      metadata = { kind, user_id: user.id };
    } else if (kind === 'event_ticket') {
      if (!eventId) return json({ error: 'eventId required' }, 400);
      const { data: ev } = await db
        .from('events')
        .select('title, price, is_free')
        .eq('id', eventId)
        .maybeSingle();
      if (!ev) return json({ error: 'Event not found' }, 404);
      if (ev.is_free) return json({ error: 'Event is free — no payment needed' }, 400);
      const cents = Math.round(Number(ev.price ?? 0) * 100);
      if (cents <= 0) return json({ error: 'Event has no price' }, 400);
      const { data: pay } = await db.from('payments').insert({
        user_id: user.id,
        kind: 'event_ticket',
        event_id: eventId,
        amount_cents: cents,
        currency: 'usd',
        status: 'pending',
      }).select('id').single();
      pendingPaymentId = pay?.id ?? null;
      mode = 'payment';
      lineItems = [{
        quantity: 1,
        price_data: {
          currency: 'usd',
          unit_amount: cents,
          product_data: { name: `Ticket — ${ev.title ?? 'Event'}` },
        },
      }];
      metadata = { kind: 'event_ticket', user_id: user.id, event_id: eventId, payment_id: pendingPaymentId ?? '' };
    } else if (kind === 'package') {
      // A client buys one of a coach's services. single session / package /
      // consultation → one-time payment; monthly & hybrid memberships →
      // recurring subscription. Price comes from the service row.
      if (!packageId) return json({ error: 'packageId required' }, 400);
      const { data: pkg } = await db
        .from('coach_packages')
        .select('id, coach_id, type, name, sessions, price')
        .eq('id', packageId)
        .maybeSingle();
      if (!pkg) return json({ error: 'Package not found' }, 404);
      const cents = Math.round(Number(pkg.price ?? 0) * 100);
      if (cents <= 0) return json({ error: 'Package has no price' }, 400);
      coachingAmountCents = cents;
      const pkgCoachId = pkg.coach_id as string;
      const sessions = Number(pkg.sessions ?? 0);
      const recurring = pkg.type === 'monthly' || pkg.type === 'hybrid';
      const sessionSuffix = pkg.type === 'bulk'
        ? ` (${sessions} sessions)`
        : pkg.type === 'hybrid' && sessions > 0
          ? ` (${sessions} sessions/mo)`
          : '';
      const label = `${pkg.name ?? 'Coaching package'}${sessionSuffix}`;

      if (recurring) {
        mode = 'subscription';
        lineItems = [{
          quantity: 1,
          price_data: {
            currency: 'usd',
            unit_amount: cents,
            recurring: { interval: 'month' },
            product_data: { name: label },
          },
        }];
        metadata = {
          kind: 'package_monthly', user_id: user.id, coach_id: pkgCoachId, package_id: packageId,
        };
      } else {
        // single session / package / consultation → one-time. Record a pending
        // payment to reconcile.
        const { data: pay } = await db.from('payments').insert({
          user_id: user.id,
          kind: 'package',
          coach_id: pkgCoachId,
          package_id: packageId,
          sessions,
          amount_cents: cents,
          currency: 'usd',
          status: 'pending',
        }).select('id').single();
        pendingPaymentId = pay?.id ?? null;
        mode = 'payment';
        lineItems = [{
          quantity: 1,
          price_data: { currency: 'usd', unit_amount: cents, product_data: { name: label } },
        }];
        metadata = {
          kind: 'package', user_id: user.id, coach_id: pkgCoachId, package_id: packageId,
          payment_id: pendingPaymentId ?? '', sessions: String(sessions),
        };
      }
    } else {
      return json({ error: 'Unknown kind' }, 400);
    }

    // ── Stripe Connect: coaching revenue is charged to the COACH's connected
    // account; 12 Circle takes only a commission (application fee). Platform
    // memberships (self/ai/coach_plan) and event tickets stay on the platform
    // account. coach_invited clients = 0% commission; marketplace = coach rate.
    // deno-lint-ignore no-explicit-any
    const connect: any = {};
    if (coachingAmountCents > 0 && metadata.coach_id) {
      const cId = metadata.coach_id;
      const { data: cAcct } = await db
        .from('user_profiles')
        .select('stripe_account_id, stripe_charges_enabled, marketplace_commission_rate')
        .eq('id', cId)
        .maybeSingle();
      const acct = cAcct?.stripe_account_id as string | null;
      if (!acct || !cAcct?.stripe_charges_enabled) {
        return json({ error: 'This coach has not finished setting up payments yet.' }, 409);
      }
      const { data: rel } = await db
        .from('coach_client_relationships')
        .select('client_source')
        .eq('client_id', user.id)
        .eq('coach_id', cId)
        .maybeSingle();
      const source = (rel?.client_source as string) ?? 'marketplace';
      // Admin-configurable global marketplace commission (platform_settings),
      // falling back to the coach's column then 10%.
      let marketRate = Number(cAcct?.marketplace_commission_rate ?? 0.10);
      const { data: setting } = await db.from('platform_settings')
        .select('value').eq('key', 'marketplace_commission_rate').maybeSingle();
      if (setting && Number.isFinite(Number(setting.value))) marketRate = Number(setting.value);
      const rate = source === 'coach_invited' ? 0 : marketRate;
      const feeCents = Math.round(coachingAmountCents * rate);
      metadata = {
        ...metadata,
        client_source: source,
        commission_rate: String(rate),
        platform_fee: String(feeCents),
        coach_payout: String(coachingAmountCents - feeCents),
        stripe_account_id: acct,
        service_id: metadata.package_id ?? '',
      };
      if (mode === 'payment') {
        connect.payment_intent_data = {
          transfer_data: { destination: acct },
          ...(feeCents > 0 ? { application_fee_amount: feeCents } : {}),
        };
      } else {
        connect.subscription_data = {
          transfer_data: { destination: acct },
          ...(rate > 0 ? { application_fee_percent: Math.round(rate * 100) } : {}),
        };
      }
      // Record the split on the pending payment row (one-time packages).
      if (pendingPaymentId) {
        await db.from('payments').update({
          client_source: source, commission_rate: rate,
          platform_fee: feeCents, coach_payout: coachingAmountCents - feeCents,
          stripe_account_id: acct, service_id: metadata.package_id || null,
        }).eq('id', pendingPaymentId);
      }
    }

    // ── Create the session in embedded or redirect mode ──
    // deno-lint-ignore no-explicit-any
    const base: any = { mode, customer: customerId, line_items: lineItems, metadata, ...connect };
    if (embedded) {
      base.ui_mode = 'embedded';
      // Embedded checkout redirects here on completion (with the session id).
      const ret = returnUrl ?? success;
      base.return_url = ret.includes('{CHECKOUT_SESSION_ID}')
        ? ret
        : `${ret}${ret.includes('?') ? '&' : '?'}session_id={CHECKOUT_SESSION_ID}`;
    } else {
      base.success_url = success;
      base.cancel_url = cancel;
    }

    const session = await stripe.checkout.sessions.create(base);

    if (pendingPaymentId) {
      await db.from('payments')
        .update({ stripe_checkout_session_id: session.id })
        .eq('id', pendingPaymentId);
    }

    return embedded
      ? json({ clientSecret: session.client_secret, sessionId: session.id })
      : json({ url: session.url, sessionId: session.id });
  } catch (e) {
    console.error('create-checkout error:', e);
    return json({ error: String(e) }, 500);
  }
});
