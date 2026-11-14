// Swaps the user's active platform membership to a different tier in place
// (Self-Guided <-> AI-Guided), prorated, with no second subscription and no new
// checkout. Returns { needsCheckout: true } when the user has no membership yet
// so the caller can start a fresh checkout instead.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import Stripe from 'https://esm.sh/stripe@16.12.0?target=deno';

const STRIPE_SECRET_KEY = Deno.env.get('STRIPE_SECRET_KEY') ?? '';
const PRICE_IDS: Record<string, string> = {
  self_guided: Deno.env.get('STRIPE_SELF_GUIDED_PRICE_ID') ?? '',
  ai_guided: Deno.env.get('STRIPE_AI_GUIDED_PRICE_ID') ?? '',
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
    status, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
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

    const { newKind } = await req.json() as { newKind: 'self_guided' | 'ai_guided' };
    const newPrice = PRICE_IDS[newKind];
    if (!newPrice) return json({ error: 'Unknown membership tier' }, 400);

    const db = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

    // Find the active platform membership subscription.
    const { data: sub } = await db
      .from('subscriptions')
      .select('id, kind, stripe_subscription_id')
      .eq('user_id', user.id)
      .in('kind', ['self_guided', 'ai_guided'])
      .in('status', ['active', 'trialing'])
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (!sub?.stripe_subscription_id) {
      // A membership whose payment is failing is still a membership: Stripe is
      // retrying it. Sending this member to a new checkout created a SECOND
      // subscription while the first kept billing. They fix the payment first.
      const { data: troubled, error: troubledError } = await db
        .from('subscriptions')
        .select('id, status')
        .eq('user_id', user.id)
        .in('kind', ['self_guided', 'ai_guided'])
        .in('status', ['past_due', 'incomplete', 'unpaid'])
        .limit(1)
        .maybeSingle();
      if (troubledError) return json({ error: 'Could not read your membership' }, 503);
      if (troubled) return json({ paymentIssue: true, status: troubled.status });
      // No membership to change — caller should start a normal checkout.
      return json({ needsCheckout: true });
    }
    if (sub.kind === newKind) return json({ ok: true, unchanged: true });

    // Swap the price on the existing Stripe subscription (prorated).
    const stripeSub = await stripe.subscriptions.retrieve(sub.stripe_subscription_id);
    const itemId = stripeSub.items.data[0]?.id;
    const updated = await stripe.subscriptions.update(sub.stripe_subscription_id, {
      items: [{ id: itemId, price: newPrice }],
      proration_behavior: 'create_prorations',
    });

    await db.from('subscriptions').update({
      kind: newKind,
      stripe_price_id: newPrice,
      status: updated.status,
      current_period_end: updated.current_period_end
        ? new Date(updated.current_period_end * 1000).toISOString() : null,
    }).eq('id', sub.id);

    return json({ ok: true });
  } catch (e) {
    console.error('update-subscription error:', e);
    return json({ error: String(e) }, 500);
  }
});
