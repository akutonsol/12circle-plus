// A late `customer.subscription.updated` event cannot write a stale state.
//
//   node --test supabase/tests/functions/current_subscription.test.mjs
//
// No network, no Stripe account, no credential: a fake Stripe client stands in.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { currentSubscription } from '../../functions/stripe-webhook/current_subscription.mjs';

/** Stripe as it holds subscription `id` NOW, counting reads. */
function fakeStripe(now, { fail = false } = {}) {
  const reads = [];
  return {
    reads,
    subscriptions: {
      async retrieve(id) {
        reads.push(id);
        if (fail) throw new Error('stripe unavailable');
        return { ...now, id };
      },
    },
  };
}

test('a late `updated` event writes the current state, not the one it carried', async () => {
  // The renewal failed (past_due); an older event, created while it was active,
  // is delivered afterwards.
  const stripe = fakeStripe({ status: 'past_due' });
  const late = { id: 'sub_1', status: 'active' };
  const sub = await currentSubscription(stripe, 'customer.subscription.updated', late);
  assert.equal(sub.status, 'past_due', 'THE defect: the stale "active" would have restored access');
  assert.deepEqual(stripe.reads, ['sub_1']);
});

test('`deleted` is final and used as delivered (no read)', async () => {
  const stripe = fakeStripe({ status: 'active' });
  const payload = { id: 'sub_2', status: 'canceled' };
  assert.equal(await currentSubscription(stripe, 'customer.subscription.deleted', payload), payload);
  assert.deepEqual(stripe.reads, []);
});

test('a failed read throws, so the handler answers 500 and Stripe retries', async () => {
  const stripe = fakeStripe({}, { fail: true });
  await assert.rejects(currentSubscription(stripe, 'customer.subscription.updated', { id: 'sub_3' }));
});

test('the webhook reads the current state before it writes the subscription', () => {
  const src = readFileSync(new URL('../../functions/stripe-webhook/index.ts', import.meta.url), 'utf8');
  assert.match(src, /import \{ currentSubscription \} from '\.\/current_subscription\.mjs';/);
  const read = src.indexOf('await currentSubscription(');
  const write = src.indexOf("'update subscription status'");
  assert.ok(read > 0 && write > read, 'the current state is read before the status write');
  assert.match(src.slice(read, read + 160), /stripe, event\.type, event\.data\.object/);
});
