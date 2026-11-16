// Which subscription state a `customer.subscription.*` event may write.
//
// Stripe does not deliver events in order. An `updated` event carries the
// subscription AS IT WAS when the event was created, so a late, older event
// (say `active`) arriving after a newer one (`past_due` after a failed
// renewal) used to overwrite the newer state and restore access nobody is
// paying for. K-23 already stops any `updated` event from un-cancelling a row;
// this closes the same gap for every other status. The handler writes the
// subscription as Stripe holds it NOW, as the checkout branch already does.
//
// `deleted` is terminal and its payload is final, so it is used as delivered.
// A failed read throws: the handler answers 500 and Stripe retries, rather
// than applying a state that may be stale.
//
// Plain JavaScript so Node's test runner exercises it unchanged:
// supabase/tests/functions/current_subscription.test.mjs.

export async function currentSubscription(stripe, eventType, payload) {
  if (eventType !== 'customer.subscription.updated') return payload;
  return await stripe.subscriptions.retrieve(payload.id);
}
