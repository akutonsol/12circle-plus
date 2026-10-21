// Stripe webhook → reconciles checkout + subscription lifecycle into Supabase.
// Handles:
//   checkout.session.completed         → record subscription / mark ticket paid
//   customer.subscription.updated      → sync status / period / cancel flag
//   customer.subscription.deleted      → mark canceled
// All writes use the service-role client (bypasses RLS). Signature is verified
// against STRIPE_WEBHOOK_SECRET so only Stripe can write here.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import Stripe from 'https://esm.sh/stripe@16.12.0?target=deno';

const STRIPE_SECRET_KEY = Deno.env.get('STRIPE_SECRET_KEY') ?? '';
const WEBHOOK_SECRET = Deno.env.get('STRIPE_WEBHOOK_SECRET') ?? '';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

const stripe = new Stripe(STRIPE_SECRET_KEY, {
  apiVersion: '2024-06-20',
  httpClient: Stripe.createFetchHttpClient(),
});
// Deno needs the async crypto provider for signature verification.
const cryptoProvider = Stripe.createSubtleCryptoProvider();

const db = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

// `canceled_at` is optional here and set only on the deleted event (Q11). Typed
// explicitly so adding it below is a checked assignment rather than a widening cast.
function subStatusFields(sub: Stripe.Subscription): {
  status: string;
  stripe_price_id: string | null;
  current_period_end: string | null;
  cancel_at_period_end: boolean;
  canceled_at?: string;
} {
  return {
    status: sub.status,
    stripe_price_id: sub.items.data[0]?.price?.id ?? null,
    current_period_end: sub.current_period_end
      ? new Date(sub.current_period_end * 1000).toISOString()
      : null,
    cancel_at_period_end: sub.cancel_at_period_end ?? false,
  };
}

Deno.serve(async (req: Request) => {
  const sig = req.headers.get('stripe-signature');
  if (!sig) return new Response('Missing signature', { status: 400 });

  const raw = await req.text();
  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(raw, sig, WEBHOOK_SECRET, undefined, cryptoProvider);
  } catch (e) {
    console.error('Signature verification failed:', e);
    return new Response(`Bad signature: ${e}`, { status: 400 });
  }

  try {
    switch (event.type) {
      case 'checkout.session.completed': {
        const session = event.data.object as Stripe.Checkout.Session;
        const meta = session.metadata ?? {};
        const kind = meta.kind;
        const isSubscription = kind === 'coach' || kind === 'coach_plan' ||
          kind === 'self_guided' || kind === 'ai_guided' || kind === 'package_monthly';

        if (isSubscription) {
          // Pull the subscription to capture status + period end.
          const subId = session.subscription as string;
          const sub = await stripe.subscriptions.retrieve(subId);
          const coachScoped = kind === 'coach' || kind === 'package_monthly';
          await db.from('subscriptions').upsert({
            user_id: meta.user_id,
            kind,
            coach_id: coachScoped ? meta.coach_id : null,
            plan_tier: kind === 'coach_plan' ? meta.plan_tier : null,
            stripe_subscription_id: subId,
            // Connect split (coaching subs only).
            ...(coachScoped ? {
              service_id: meta.service_id || null,
              client_source: meta.client_source ?? null,
              commission_rate: meta.commission_rate ? Number(meta.commission_rate) : null,
              platform_fee: meta.platform_fee ? Number(meta.platform_fee) : null,
              coach_payout: meta.coach_payout ? Number(meta.coach_payout) : null,
              stripe_account_id: meta.stripe_account_id ?? null,
            } : {}),
            ...subStatusFields(sub),
          }, { onConflict: 'stripe_subscription_id' });

          // A client→coach subscription also activates the coaching relationship.
          if (coachScoped && meta.coach_id) {
            await db.from('coach_client_relationships').upsert({
              client_id: meta.user_id,
              coach_id: meta.coach_id,
              status: 'active',
            }, { onConflict: 'client_id,coach_id' });
          }

          // A coach platform plan sets the coach's client capacity.
          if (kind === 'coach_plan') {
            const limits: Record<string, number> = { starter: 25, growth: 100, elite: 100000 };
            await db.from('user_profiles')
              .update({ max_clients: limits[meta.plan_tier ?? 'starter'] ?? 25 })
              .eq('id', meta.user_id);
          }
        } else if (kind === 'event_ticket') {
          // Mark the pending payment paid and grant the registration.
          if (meta.payment_id) {
            await db.from('payments').update({
              status: 'paid',
              stripe_payment_intent_id: (session.payment_intent as string) ?? null,
            }).eq('id', meta.payment_id);
          }
          await db.from('event_registrations').upsert({
            event_id: meta.event_id,
            user_id: meta.user_id,
            status: 'registered',
            paid: true,
            payment_id: meta.payment_id || null,
          }, { onConflict: 'event_id,user_id' });
        } else if (kind === 'package') {
          // One-time package (per_session / bulk). Mark paid, activate the
          // coaching relationship, and grant session credits if any.
          if (meta.payment_id) {
            await db.from('payments').update({
              status: 'paid',
              stripe_payment_intent_id: (session.payment_intent as string) ?? null,
            }).eq('id', meta.payment_id);
          }
          if (meta.coach_id) {
            await db.from('coach_client_relationships').upsert({
              client_id: meta.user_id,
              coach_id: meta.coach_id,
              status: 'active',
            }, { onConflict: 'client_id,coach_id' });
          }
          const sessions = Number(meta.sessions ?? 0);
          if (sessions > 0 && meta.coach_id) {
            // I-PAY-01. Stripe delivers at least once and retries every
            // non-2xx, so a redelivery used to grant the sessions again — the
            // one write in this handler without a conflict target, while
            // payments, subscriptions, coach_client_relationships and
            // event_registrations were all already idempotent.
            //
            // ignoreDuplicates (ON CONFLICT DO NOTHING) rather than a merge:
            // this grant is money the client has already been given, and
            // sessions_used may have advanced since. A redelivery must be a
            // complete no-op, not a rewrite of a block that is being consumed.
            //
            // The conflict target is the unique index migration 131 adds on
            // payment_id. It is only reachable when payment_id is present —
            // Postgres treats NULLs as distinct — so a manual grant with no
            // payment still inserts, and two of them do not collide.
            await db.from('client_session_credits').upsert({
              client_id: meta.user_id,
              coach_id: meta.coach_id,
              package_id: meta.package_id || null,
              payment_id: meta.payment_id || null,
              sessions_total: sessions,
            }, { onConflict: 'payment_id', ignoreDuplicates: true });
          }
        }
        break;
      }

      case 'customer.subscription.updated':
      case 'customer.subscription.deleted': {
        const sub = event.data.object as Stripe.Subscription;
        const fields = subStatusFields(sub);
        if (event.type === 'customer.subscription.deleted') {
          fields.status = 'canceled';
          // OWNER DECISION Q11 · the authorized writer for the cancellation EVENT.
          //
          // Churn is defined as cancellations recorded WITHIN a month over the
          // subscriptions active when it began, so it needs the moment of departure and
          // not merely the resulting state. This handler is the system-of-record path for
          // that moment — it already writes `status = 'canceled'` here — so the timestamp
          // is written in the SAME update rather than inferred later by a trigger, which
          // would record when we noticed instead of when it happened.
          //
          // STRIPE'S OWN `canceled_at` IS PREFERRED, and the fallback is named rather than
          // silent: when Stripe omits it we record the moment this event was handled,
          // which is a real moment of the same event and the closest authoritative value
          // available. Neither is derived from `updated_at` or `current_period_end` — the
          // inference the ruling forbids, since one moves on any write and the other is a
          // billing boundary rather than a departure.
          fields.canceled_at = sub.canceled_at
            ? new Date(sub.canceled_at * 1000).toISOString()
            : new Date().toISOString();
        }
        await db.from('subscriptions')
          .update(fields)
          .eq('stripe_subscription_id', sub.id);
        break;
      }
    }
    return new Response(JSON.stringify({ received: true }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (e) {
    console.error('Webhook handler error:', e);
    return new Response(`Handler error: ${e}`, { status: 500 });
  }
});
