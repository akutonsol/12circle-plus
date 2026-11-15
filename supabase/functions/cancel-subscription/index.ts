// Cancels a subscription immediately and reflects it in the DB right away
// (no waiting on the async webhook). For coach subscriptions it also ends the
// coaching relationship and notifies the coach. Auth required; the caller can
// only cancel their own subscription.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import Stripe from 'https://esm.sh/stripe@16.12.0?target=deno';

const STRIPE_SECRET_KEY = Deno.env.get('STRIPE_SECRET_KEY') ?? '';
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

    const { subscriptionId } = await req.json() as { subscriptionId: string };
    if (!subscriptionId) return json({ error: 'subscriptionId required' }, 400);

    const db = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

    // Load the row and confirm ownership.
    const { data: sub } = await db
      .from('subscriptions')
      .select('id, user_id, kind, coach_id, stripe_subscription_id, current_period_end')
      .eq('id', subscriptionId)
      .maybeSingle();
    if (!sub) return json({ error: 'Subscription not found' }, 404);
    if (sub.user_id !== user.id) return json({ error: 'Forbidden' }, 403);

    // OWNER DECISION 2, 2026-11-15 (Julia): ending COACHING cancels the paid
    // coaching subscription at the END of the period already paid for, and
    // coaching lasts until then -- no refund needed. A coaching subscription
    // (coach, or the monthly package the app sells) is therefore scheduled to
    // cancel at period end; the relationship stays active and the Stripe webhook
    // ends it when the subscription is deleted. Platform memberships keep the
    // immediate cancellation below.
    //
    // The same K-07 invariant: nothing local changes unless Stripe accepted the
    // change. A subscription Stripe already reports gone falls through to the
    // immediate path, whose end state it already is.
    const coachScoped = sub.kind === 'coach' || sub.kind === 'package_monthly';
    if (coachScoped && sub.stripe_subscription_id) {
      let scheduled: { endsAt: string | null } | null = null;
      try {
        const updated = await stripe.subscriptions.update(sub.stripe_subscription_id, {
          cancel_at_period_end: true,
        });
        scheduled = {
          endsAt: updated.current_period_end
            ? new Date(updated.current_period_end * 1000).toISOString()
            : (sub.current_period_end as string | null) ?? null,
        };
      } catch (e) {
        const err = e as { code?: string; raw?: { code?: string } };
        let gone = (err?.code ?? err?.raw?.code) === 'resource_missing';
        if (!gone) {
          try {
            const remote = await stripe.subscriptions.retrieve(sub.stripe_subscription_id);
            gone = remote?.status === 'canceled';
          } catch (probe) {
            const pErr = probe as { code?: string; raw?: { code?: string } };
            gone = (pErr?.code ?? pErr?.raw?.code) === 'resource_missing';
          }
        }
        if (!gone) {
          console.error('Stripe period-end cancel failed -- nothing changed (K-07):', e);
          return json({
            error: 'stripe_cancel_failed',
            message: 'Your coaching could not be ended with the payment provider. '
                   + 'Nothing has changed. Please try again.',
          }, 502);
        }
        // Already gone at Stripe: continue to the immediate path below.
      }

      if (scheduled) {
        const { error: rowError } = await db.from('subscriptions')
          .update({ cancel_at_period_end: true })
          .eq('id', sub.id);
        if (rowError) {
          // Stripe has it scheduled; a retry repeats an idempotent update.
          console.error('cancel-subscription: local cancel_at_period_end failed:', rowError);
          return json({ error: 'Could not record the cancellation. Try again.' }, 500);
        }
        // Tell the coach when coaching ends (best effort; the schedule is saved).
        try {
          const { data: client } = await db.from('user_profiles')
            .select('first_name, last_name').eq('id', sub.user_id).maybeSingle();
          const name = [client?.first_name, client?.last_name].filter(Boolean).join(' ') || 'A client';
          const when = scheduled.endsAt ? new Date(scheduled.endsAt).toDateString() : 'the end of their paid period';
          await db.from('notifications').insert({
            recipient_id: sub.coach_id,
            type: 'coaching_ending',
            title: 'A client is ending coaching',
            body: `${name} has cancelled. Coaching continues until ${when}, the end of the period they paid for.`,
            read: false,
          });
        } catch (e) {
          console.error('cancel-subscription: coach notification failed:', e);
        }
        return json({ ok: true, endsAt: scheduled.endsAt });
      }
    }

    // Cancel immediately at Stripe (no refund for the remaining period).
    //
    // K-07. This block used to swallow the Stripe error and fall through to the
    // local update, with the comment "continuing to mark local". The consequence
    // is the worst way round: Stripe keeps billing the customer, the local row
    // says `canceled`, the coaching relationship is ended and the coach is
    // notified — so the member pays for access they no longer have, while the UI
    // reports "Switched to the Free plan".
    //
    // THE INVARIANT: local entitlement is revoked ONLY when the remote
    // subscription is actually gone. A failure returns 502 and changes NOTHING
    // locally, so the caller can safely retry.
    //
    // IDEMPOTENCY. A retry must not fail because the first attempt succeeded. Two
    // outcomes mean "already gone" and are treated as success:
    //   · `resource_missing` — Stripe has no such subscription;
    //   · the subscription exists and its status is already `canceled`.
    // Both leave the end state this function is trying to reach.
    if (sub.stripe_subscription_id) {
      try {
        await stripe.subscriptions.cancel(sub.stripe_subscription_id);
      } catch (e) {
        const err = e as { code?: string; raw?: { code?: string } };
        const code = err?.code ?? err?.raw?.code;
        let alreadyGone = code === 'resource_missing';

        if (!alreadyGone) {
          // Ask Stripe what it actually holds before calling this a failure.
          try {
            const remote = await stripe.subscriptions.retrieve(sub.stripe_subscription_id);
            alreadyGone = remote?.status === 'canceled';
          } catch (probe) {
            const pErr = probe as { code?: string; raw?: { code?: string } };
            alreadyGone = (pErr?.code ?? pErr?.raw?.code) === 'resource_missing';
          }
        }

        if (!alreadyGone) {
          console.error('Stripe cancel failed — local entitlement PRESERVED (K-07):', e);
          return json({
            error: 'stripe_cancel_failed',
            message: 'The subscription could not be cancelled with the payment '
                   + 'provider. Your access is unchanged and you have not been '
                   + 'switched to the Free plan. Please try again.',
          }, 502);
        }
        console.warn('Stripe reports the subscription already cancelled; proceeding (K-07 idempotency).');
      }
    }

    // Reflect locally now so the app updates without webhook latency.
    await db.from('subscriptions')
      .update({ status: 'canceled', cancel_at_period_end: false })
      .eq('id', sub.id);

    // A coach subscription also ends the relationship + notifies the coach.
    // (A coaching subscription only reaches here when Stripe already had it gone.)
    if (coachScoped && sub.coach_id) {
      await db.from('coach_client_relationships')
        .update({ status: 'cancelled' })
        .eq('client_id', sub.user_id)
        .eq('coach_id', sub.coach_id);

      const { data: client } = await db
        .from('user_profiles')
        .select('first_name, last_name')
        .eq('id', sub.user_id)
        .maybeSingle();
      const name = [client?.first_name, client?.last_name].filter(Boolean).join(' ') || 'A client';
      await db.from('notifications').insert({
        recipient_id: sub.coach_id,
        type: 'coaching_ended',
        title: 'A client ended coaching',
        body: `${name} has cancelled their coaching subscription.`,
        read: false,
      });
    }

    return json({ ok: true });
  } catch (e) {
    console.error('cancel-subscription error:', e);
    return json({ error: String(e) }, 500);
  }
});
