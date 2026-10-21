# QA Workstream K — Billing, Subscription, Payment & Entitlement

**Scope:** the complete money path — marketing/product tier → checkout → payment → webhook → subscription → entitlement → session credits → cancellation → renewal → failure → refund → UI.

**Environments referenced:** QA `eyqtldjqpgpljlqvpowh` (the ref the Supabase CLI is linked to, `supabase/.temp/project-ref`, `supabase/config.toml`). **Production `nxdbooufqzkpslkcogxc` was NOT contacted.** No Stripe API call of any kind was made, in test mode or live mode. No card was charged. No Edge Function was deployed. No secret was set. No webhook endpoint was created or modified. See §12.

**Method:** static audit of the committed source read this session, plus the offline test suites. Every claim below cites `file:line` in the working tree. Claims that depend on state this workstream cannot inspect — the Stripe dashboard, the Supabase secret store, the deployed function configuration — are marked **UNVERIFIABLE FROM REPO** and converted into checklist items rather than asserted as fact.

**Relationship to Workstream G:** G raised REL-05, REL-07, REL-18 and REL-24 against the billing surface. Each was re-derived from current source this session rather than inherited. **All four are still open** (K-App-1, K-26, K-ENV-1, K-01/K-02 respectively). G's REL-24 is confirmed and decomposed here into five distinct defects.

---

## 1. Payment architecture

### 1.1 The parts

| Layer | Implementation | Notes |
|---|---|---|
| Client | Flutter (`apps/mobile`) | Holds only a Stripe **publishable** key ([`stripe_config.dart`](../apps/mobile/lib/core/config/stripe_config.dart)); never a secret |
| Checkout | Supabase Edge Function [`create-checkout`](../supabase/functions/create-checkout/index.ts) | 325 lines; six purchase kinds; hosted redirect + embedded modes |
| Reconciliation | Edge Function [`stripe-webhook`](../supabase/functions/stripe-webhook/index.ts) | 160 lines; service-role writes; **three** event types |
| Self-service | [`create-portal-session`](../supabase/functions/create-portal-session/index.ts), [`cancel-subscription`](../supabase/functions/cancel-subscription/index.ts), [`update-subscription`](../supabase/functions/update-subscription/index.ts) | Portal, in-app immediate cancel, in-place tier swap |
| Marketplace payouts | [`stripe-connect`](../supabase/functions/stripe-connect/index.ts) | Express accounts, destination charges, application fee |
| Entitlement resolvers | `client_plan()`, `active_membership()`, `coach_plan_tier()` — migrations [024](../supabase/migrations/024_client_plan.sql), [022](../supabase/migrations/022_payments.sql), [023](../supabase/migrations/023_coach_plans.sql) | `SECURITY DEFINER`, `auth.uid()`-scoped, on migration 116's execute allow-list |
| Entitlement enforcement | [`PaywallGate`](../apps/mobile/lib/features/payments/presentation/paywall_gate.dart) at the router, [`ClientPlanCaps`](../apps/mobile/lib/features/payments/domain/entitlements.dart) | **Client-side only** — see K-03, K-10 |
| NestJS API (`apps/api`) | **No billing surface at all** | Verified by grep; it hosts only the AI nutrition route |

### 1.2 The two money flows

```
PLATFORM REVENUE ────────────────────────► 12 Circle's own Stripe account
  self_guided  $29/mo   (STRIPE_SELF_GUIDED_PRICE_ID)
  ai_guided    $59/mo   (STRIPE_AI_GUIDED_PRICE_ID)
  coach_plan   $99 / $199 / $299 /mo  (starter | growth | elite)
  event_ticket one-time (price from events.price)

COACHING REVENUE ────────────────────────► the COACH's connected account
  coach            recurring, price from user_profiles.pricing_monthly
                   or coach_client_relationships.monthly_price
  package_monthly  recurring, price from coach_packages.price
  package          one-time (per_session / bulk / consultation)
      │
      └── destination charge + application fee
            coach_invited client → 0%
            marketplace client   → platform_settings.marketplace_commission_rate (0.10)
```

### 1.3 Data model

| Table | Written by | Read by |
|---|---|---|
| `subscriptions` | `stripe-webhook`, `cancel-subscription`, `update-subscription` (all service-role) | `client_plan()`, `active_membership()`, `coach_plan_tier()`, `marketplace_coaches()`, `CoachRevenueService` |
| `payments` | `create-checkout` (pending row), `stripe-webhook` (mark paid) | `CoachRevenueService`, coach payments screen |
| `client_session_credits` | `stripe-webhook` **only** | `CoachRevenueService` (a count) — **and nothing else** (K-05) |
| `user_profiles.stripe_*`, `marketplace_commission_rate`, `membership_tier` | webhook / `stripe-connect` | `create-checkout`, portal |
| `coach_client_relationships.client_source` | trigger `set_relationship_client_source` at INSERT | `create-checkout` commission branch |
| `event_registrations` | `stripe-webhook` **and the client directly** (K-04) | ticket screen, vendor check-in |

RLS posture on the money tables is read-only for end users: `subscriptions` and `payments` expose SELECT policies and no INSERT/UPDATE/ALL policy ([`022_payments.sql:57-68`](../supabase/migrations/022_payments.sql#L57-L68), guarded by a new test). Stripe identity columns are pinned against client writes by the migration 115 privilege trigger ([`115:244-254`](../supabase/migrations/115_profile_privilege_boundary.sql#L244-L254)). `client_source` — which decides the commission rate — is immutable after insert ([`113:156-159`](../supabase/migrations/113_rls_coach_client_relationships.sql#L156-L159)). **These parts are correct and are now regression-guarded.**

---

## 2. Lifecycle diagrams (text)

### 2.1 Platform membership — happy path

```
UpgradeScreen._onCta
  └─ current plan is free  ──► launchCheckout(kind: self_guided|ai_guided)
       └─ PaymentService.startCheckout
            └─ POST /functions/v1/create-checkout   (user JWT)
                 ├─ auth.getUser()                            → 401 if absent
                 ├─ read user_profiles.stripe_customer_id
                 │    └─ absent → stripe.customers.create + write back   ⚠ K-13 race
                 ├─ price = env STRIPE_<TIER>_PRICE_ID          → 500 if unset
                 ├─ metadata = { kind, user_id }
                 ├─ success_url / cancel_url = CALLER SUPPLIED  ⚠ K-21 no allowlist
                 └─ stripe.checkout.sessions.create             ⚠ no idempotency key
            └─ launchUrl(session.url)  — external browser       ⚠ K-App-1 (iOS 3.1.1)
  ⋯ user pays at Stripe ⋯
Stripe ──► POST /functions/v1/stripe-webhook   checkout.session.completed
       ├─ constructEventAsync(raw, sig, WEBHOOK_SECRET)   ✔ verified before any write
       ├─ ⚠ K-01 no processed-event lookup
       ├─ stripe.subscriptions.retrieve(session.subscription)
       └─ subscriptions.upsert(onConflict stripe_subscription_id)   ✔ idempotent
  ⋯ client returns to /payment-success ⋯
PaymentResultScreen  → 2 s delay → invalidate clientPlanProvider, membershipTierProvider …
       └─ rpc client_plan()  → 'self_guided' | 'ai_guided'
       └─ PaywallGate unlocks the gated routes                 ⚠ K-03 client-side only
```

### 2.2 Coaching package with session credits

```
ChoosePackage → create-checkout kind='package'
   ├─ read coach_packages(price, sessions, type)
   ├─ INSERT payments(status='pending', sessions=N)          ← pending row, K-24 orphan risk
   ├─ Connect branch: read coach stripe_account_id + charges_enabled  ⚠ K-17 stale
   │    ├─ read coach_client_relationships.client_source
   │    ├─ rate = coach_invited ? 0 : platform_settings rate  ⚠ K-18 overrides per-coach
   │    └─ payment_intent_data.transfer_data + application_fee_amount
   └─ session.create → UPDATE payments.stripe_checkout_session_id
  ⋯ pays ⋯
webhook checkout.session.completed  kind='package'
   ├─ payments.update(status='paid')                    idempotent
   ├─ coach_client_relationships.upsert(status active)  idempotent
   └─ client_session_credits.INSERT(sessions_total=N)   ⚠⚠ K-01 NOT idempotent
  ⋯ client books ⋯
BookingScreen._book
   └─ coaching_calls.INSERT + coach_availability.update(is_booked)
        ⚠⚠ K-05 no credit read, no decrement, no balance check, no server enforcement
```

### 2.3 Cancellation

```
UpgradeScreen "Switch to Free" / ManageSubscriptionScreen "Cancel"
   └─ for each active membership row → cancel-subscription
        ├─ ownership check  sub.user_id === user.id      ✔ 403 otherwise
        ├─ stripe.subscriptions.cancel(...)  IMMEDIATE, no proration, no refund   ► D-K2
        │     └─ on throw: logged and SWALLOWED           ⚠⚠ K-07
        ├─ subscriptions.update(status='canceled')
        └─ kind==='coach' → relationship 'cancelled' + notify coach
              ⚠ kind==='package_monthly' takes none of this branch (K-08c)
   ⋯ Stripe later emits customer.subscription.deleted ⋯
   └─ webhook updates the row again (no-op)              ⚠ K-23 no ordering guard
                                                          ⚠ K-09 max_clients never lowered
```

### 2.4 Renewal, failure, refund — as built

```
month 2 renewal:
  Stripe invoice.paid ─────────────► NOT SUBSCRIBED, NOT HANDLED   (K-02)
  Stripe customer.subscription.updated ─► period end refreshed      (the only signal)
  ⇒ `payments` never receives a renewal row ⇒ coach revenue is wrong (K-19)

card declines:
  invoice.payment_failed ──────────► NOT HANDLED                    (K-02)
  customer.subscription.updated status='past_due'
     └─ client_plan() drops to 'free' on the FIRST failure          (K-11) ► D-K3

refund / chargeback:
  charge.refunded / charge.dispute.created ─► NOT HANDLED           (K-06)
  ⇒ session credits, event tickets, relationship and entitlement all survive a refund
```

---

## 3. State-transition matrix

`subscriptions.status` is whatever Stripe last reported. Entitlement is derived, never stored.

| From | Event / action | To | Row writer | `client_plan()` after | Correct? |
|---|---|---|---|---|---|
| (none) | `checkout.session.completed` | `active` | webhook upsert | tier granted | ✔ |
| (none) | `checkout.session.completed` **redelivered** | `active` | webhook upsert | tier granted | ✔ for subs, ✘ for credits (K-01) |
| (none) | session completed, `payment_status != 'paid'` | `active` | webhook | tier granted | ✘ K-22 |
| `active` | renewal succeeds | `active` | `subscription.updated` | unchanged | ✔ period only; no payment row (K-02/K-19) |
| `active` | first payment failure | `past_due` | `subscription.updated` | **`free`** | ✘ K-11 — no grace ► D-K3 |
| `past_due` | dunning succeeds | `active` | `subscription.updated` | tier restored | ✔ (after an outage of access) |
| `past_due` | user opens Upgrade → same tier | **second live subscription** | `create-checkout` | tier granted | ✘✘ K-08 double billing |
| `active` | user cancels in-app | `canceled` immediately | `cancel-subscription` | `free` | partially — ► D-K2 (paid period forfeited) |
| `active` | Stripe cancel call throws | `canceled` **locally only** | `cancel-subscription` | `free` | ✘✘ K-07 — billed with no access |
| `active` | cancel via Stripe Portal (period end) | `active`, `cancel_at_period_end=true` | `subscription.updated` | tier retained | ✔ |
| `cancel_at_period_end` | period ends | `canceled` | `subscription.deleted` | `free` | ✔ |
| `canceled` | a stale `updated` arrives late | back to the stale status | webhook | tier resurrected | ✘ K-23 |
| `active` (self) | tier swap to ai | `active`, new price | `update-subscription` | `ai_guided` | ✔ ► D-K6 proration |
| `active` (coach_plan) | canceled | `canceled` | webhook | `coach_plan_tier()` null | ✘ `max_clients` stays elevated (K-09) |
| any | refund issued in Stripe | **unchanged** | — | unchanged | ✘✘ K-06 |
| any | chargeback | **unchanged** | — | unchanged | ✘✘ K-06 |
| any | `auth.users` row deleted | rows CASCADE away | Postgres FK | n/a | ✘ Stripe keeps billing (K-16) |
| (none) | trial | **not reachable** — no `trial_period_days` anywhere | — | `trialing` is resolvable but never produced | K-29 ► D-K5 |

---

## 4. Webhook matrix

`stripe-webhook` switches on exactly three event types ([`index.ts:53,142,143`](../supabase/functions/stripe-webhook/index.ts#L53); now pinned by a test). The runbook subscribes exactly those three ([`STRIPE_SETUP.md:40-43`](../supabase/STRIPE_SETUP.md#L40-L43)).

| Event | Subscribed | Handled | Writes | Idempotent | Gap |
|---|---|---|---|---|---|
| `checkout.session.completed` → subscription kinds | yes | yes | `subscriptions` upsert (onConflict `stripe_subscription_id`, a real UNIQUE at [`022:22`](../supabase/migrations/022_payments.sql#L22)); relationship upsert; `max_clients` for coach_plan | **yes** | — |
| `checkout.session.completed` → `event_ticket` | yes | yes | `payments` update; `event_registrations` upsert | yes | no `payment_status` check (K-22) |
| `checkout.session.completed` → `package` | yes | yes | `payments` update; relationship upsert; **`client_session_credits.insert`** | **NO** | K-01 double-grant |
| `customer.subscription.updated` | yes | yes | status / price / period / cancel flag | yes | no event-ordering guard (K-23) |
| `customer.subscription.deleted` | yes | yes | status → `canceled` | yes | relationship not ended; `max_clients` not lowered (K-09) |
| `invoice.paid` | no | no | — | — | **K-02** — renewals invisible; revenue wrong |
| `invoice.payment_failed` | no | no | — | — | **K-02** — no dunning UX, no notification |
| `charge.refunded` | no | no | — | — | **K-06** — refund revokes nothing |
| `charge.dispute.created` / `.closed` | no | no | — | — | **K-06** — chargeback revokes nothing |
| `checkout.session.expired` | no | no | — | — | K-24 — pending `payments` rows leak forever |
| `customer.subscription.trial_will_end` | no | no | — | — | K-29 ► D-K5 |
| `account.updated` (Connect) | no | no | — | — | **K-17** — `stripe_charges_enabled` goes stale |
| `payment_intent.payment_failed` | no | no | — | — | K-02 |

Transport-level observations:
- Signature verification precedes every DB write ([`:43`](../supabase/functions/stripe-webhook/index.ts#L43)) — **correct**, now guarded by a test.
- Handler errors return HTTP 500 ([`:156`](../supabase/functions/stripe-webhook/index.ts#L156)). Stripe retries for ~3 days and then drops the event. There is no dead-letter table, no alert, and no reconciliation job (K-27).
- `event.account` is never inspected. The Connect runbook says the platform endpoint "should also receive events for connected accounts" ([`STRIPE_CONNECT_SETUP.md`](../supabase/STRIPE_CONNECT_SETUP.md)); if that is ever enabled, connected-account events enter the same switch untagged.
- `verify_jwt = false` for this function is dashboard/CLI-flag state, not declared in [`config.toml`](../supabase/config.toml) (K-12).

---

## 5. Entitlement matrix

Server truth is `client_plan()` ([`024_client_plan.sql`](../supabase/migrations/024_client_plan.sql)); the client mirrors it in `ClientPlanCaps` ([`entitlements.dart:36-46`](../apps/mobile/lib/features/payments/domain/entitlements.dart#L36-L46)). The third column is the one that matters.

| Capability | Sold at tier | Enforced where | Server-side gate | Bypass |
|---|---|---|---|---|
| Community, event registration, basic progress | Free | — | n/a | n/a |
| Full workout library | Self-Guided | `PaywallGate` (router) | **none** | direct PostgREST read |
| Full nutrition tracking | Self-Guided | `PaywallGate` on 6 routes | **none** | direct PostgREST |
| Advanced analytics / Insights | Self-Guided | `PaywallGate` | **none** | direct PostgREST |
| Coach marketplace access | Self-Guided | client flag | `marketplace_coaches()` is granted to every `authenticated` role | free user can browse and request |
| **AI coach chat** | AI-Guided | `PaywallGate` `/ai-coach` | **none** — [`ai-coach`](../supabase/functions/ai-coach/index.ts) checks auth only | **K-03**: any signed-in free account can `functions.invoke('ai-coach')` |
| **AI workout generation** | AI-Guided | `PaywallGate` | **none** — [`ai-generate-workout`](../supabase/functions/ai-generate-workout/index.ts) checks auth only | **K-03** |
| **AI insights / weekly review** | AI-Guided | UI | **none** — `ai-coaching-engine` | **K-03** |
| **AI food photo analysis** | AI-Guided | `PaywallGate` `/ai-nutrition` | **none** — `analyze-food-image` | **K-03** |
| **Program generation** | AI-Guided | UI | `generate_client_plan()` is `SECURITY DEFINER` and on migration 116's allow-list with **no plan predicate** ([`116:450`](../supabase/migrations/116_rpc_execution_security.sql#L450)) | **K-03** |
| **Coach messaging** | Coach-Guided | `PaywallGate` `/messages`, `/chat` | **none** — `messages` INSERT policy is `WITH CHECK (sender_id = auth.uid())` ([`003:91-94`](../supabase/migrations/003_fk_and_rls_fixes.sql#L91-L94)) | **K-10**: any user can open a conversation with any coach and message them |
| Booking coaching sessions | paid package / coach sub | `PaywallGate` `/book-call` | **none** | **K-05**: unlimited bookings, no credit spend |
| Paid event attendance | one-time purchase | UI branches on `is_free` | `event_registrations` `FOR ALL … USING (user_id = auth.uid())` ([`001:399`](../supabase/migrations/001_full_ecosystem.sql#L399)) | **K-04**: self-insert with `paid = true` |
| Coach client capacity | coach_plan tier | client-side "coach is full" | **none**; `max_clients` is not in migration 115's pinned set | **K-09**: coach PATCHes their own `max_clients` |

`user_profiles.membership_tier` is a **third, dead** tier representation: nothing in the billing path ever writes it, it is `'basic'` for every user, and it is fed into the AI coaching prompt ([`ai-coaching-engine/index.ts:123`](../supabase/functions/ai-coaching-engine/index.ts#L123)) — K-15. `user_profiles.coaching_mode` is a **fourth**, client-writable, and uses the same three tier names — K-15b.

---

## 6. Findings

Severity: **P0** blocks any paid launch · **P1** must close before public launch · **P2** should close before scale · **P3** hygiene.
"Parallelizable" = can be fixed independently of the other findings by a separate agent/engineer.

---

### K-01 · P0 · Webhook has no idempotency store; session credits are re-granted on every redelivery
- **Flow:** payment → webhook → session credits
- **Expected:** a `checkout.session.completed` event applied twice has the same effect as applying it once.
- **Actual:** [`stripe-webhook/index.ts:130`](../supabase/functions/stripe-webhook/index.ts#L130) grants credits with `client_session_credits.insert({…})`. There is no processed-event table and `event.id` is never read. A redelivery inserts a second credit row for the same payment.
- **Reproduction (QA, test mode):** buy any `bulk` package (`sessions > 0`). In the Stripe **test-mode** dashboard, Developers → Events → the `checkout.session.completed` event → **Resend**. `select count(*), sum(sessions_total) from client_session_credits where payment_id = '<id>'` returns 2 rows / 2N sessions. Equivalently: make the handler return 500 after the credit insert (e.g. by breaking a later statement) and let Stripe's automatic retry do it.
- **Root cause:** at-least-once delivery treated as exactly-once. The other three writes happen to be upserts, which masked it.
- **Financial impact:** the platform/coach delivers N unpaid sessions per redelivery. Redelivery is routine — any 5xx, any timeout, any manual resend.
- **Entitlement impact:** session balance inflated without limit.
- **Security impact:** none directly; no attacker control over redelivery.
- **Existing tests:** none before this workstream. Spec added, skipped: `K-01 the webhook is idempotent against redelivery`.
- **Recommended fix:** add `stripe_webhook_events (event_id text primary key, type text, received_at timestamptz default now())`; `insert … on conflict do nothing` at the top of the handler and return 200 immediately when the insert affects no row. Independently, make the credit grant idempotent on its own key (unique index on `payment_id` and `upsert(onConflict: 'payment_id')`), so credits are safe even if the event store is bypassed.
- **Product decision required:** no.
- **Parallelizable:** yes.

---

### K-02 · P1 · Renewals and payment failures are never reconciled
- **Flow:** renewal / payment failure → webhook
- **Expected:** each successful renewal produces a payment record; each failure is visible to the user and the coach.
- **Actual:** `invoice.paid`, `invoice.payment_failed` and `payment_intent.payment_failed` are neither subscribed ([`STRIPE_SETUP.md:40-43`](../supabase/STRIPE_SETUP.md#L40-L43)) nor handled ([`stripe-webhook/index.ts:53-147`](../supabase/functions/stripe-webhook/index.ts#L53-L147)). The only renewal signal is `customer.subscription.updated`, which refreshes `current_period_end` and nothing else.
- **Reproduction:** QA test mode — advance a test clock (or wait a cycle) on a `package_monthly` subscription. `select * from payments where kind='package'` shows the original purchase only; month 2, 3 … produce no row. For failure: use test card `4000 0000 0000 0341`; the local row goes `past_due` and no user-visible notification is produced.
- **Root cause:** the webhook models *subscription state*, not *money movement*.
- **Financial impact:** `payments` is not a ledger. Coach revenue, platform revenue and reconciliation against Stripe are all impossible from the database (see K-19).
- **Entitlement impact:** indirect — the dunning window is invisible (K-11).
- **Security impact:** none.
- **Existing tests:** none. Spec added, skipped: `K-02 the webhook reconciles renewals, failures and refunds`.
- **Recommended fix:** subscribe and handle `invoice.paid` (insert a `payments` row keyed on `invoice.id`, carrying the Connect split for coaching subs) and `invoice.payment_failed` (notify, start the grace window of D-K3).
- **Product decision required:** no for the ledger; yes for the dunning UX (► D-K3).
- **Parallelizable:** yes (after K-01's event store, to avoid double-inserting invoices).

---

### K-03 · P0 · Paid AI features have no server-side entitlement check
- **Flow:** entitlement → API authorization on paid state
- **Expected:** AI-Guided features refuse a caller without an AI-Guided (or higher) plan.
- **Actual:** `ai-coach`, `ai-generate-workout`, `ai-coaching-engine` and `analyze-food-image` verify the Supabase session and then proceed. Grep for `active_membership|client_plan|coach_plan_tier` across `supabase/functions/` returns **one** hit, and it is a comment in `create-portal-session`. `generate_client_plan()` is `SECURITY DEFINER`, granted to `authenticated` ([`047:191`](../supabase/migrations/047_self_guided_plan_generator.sql#L191)) and deliberately on the migration-116 allow-list ([`116:450`](../supabase/migrations/116_rpc_execution_security.sql#L450)) with no plan predicate. The only gate is [`PaywallGate`](../apps/mobile/lib/features/payments/presentation/paywall_gate.dart) in the Flutter router.
- **Reproduction (QA):** sign up a fresh account (plan `free`, confirmed by `rpc/client_plan` → `"free"`). `POST {QA_URL}/functions/v1/ai-generate-workout` with that account's bearer token → a full generated session. `POST {QA_URL}/rest/v1/rpc/generate_client_plan` → 204 and an assigned program. Neither call is refused.
- **Root cause:** entitlement was implemented as a UI concern. The resolvers exist server-side but no server-side caller consults them.
- **Financial impact:** the entire $59 AI-Guided tier is obtainable for $0 by anyone who can send an HTTP request — and every such call bills Anthropic tokens to the platform. This is the single largest revenue leak in the product.
- **Entitlement impact:** total for the AI tier; partial for Self-Guided (library/nutrition/analytics reads are equally ungated at the table level).
- **Security impact:** unauthenticated callers are still refused (401), so this is a paid-state authorization defect, not an authentication one. It is also an uncapped third-party spend vector.
- **Existing tests:** none. Spec added, skipped: `K-03 the paid AI functions enforce the membership server-side`.
- **Recommended fix:** one shared helper in the Edge Functions that calls `client_plan()` **as the caller** (anon client + caller JWT, not the service-role client) and 402/403s below the required tier; apply to the four AI functions. Add a plan predicate inside `generate_client_plan()` itself (it is `SECURITY DEFINER`, so it can check `client_plan()` and `RAISE EXCEPTION`). Rate-limit per user regardless of tier.
- **Product decision required:** which tier each AI surface belongs to is already stated in [`entitlements.dart`](../apps/mobile/lib/features/payments/domain/entitlements.dart) and the Upgrade screen copy; no new decision needed.
- **Parallelizable:** yes.

---

### K-04 · P0 · A paid event ticket can be self-granted
- **Flow:** checkout → entitlement (event tickets)
- **Expected:** `event_registrations.paid = true` is reachable only through the webhook after a settled payment.
- **Actual:** [`001_full_ecosystem.sql:399`](../supabase/migrations/001_full_ecosystem.sql#L399) — `CREATE POLICY "users manage own registrations" ON event_registrations FOR ALL TO authenticated USING (user_id = auth.uid());`. `FOR ALL` with no `WITH CHECK` makes PostgreSQL reuse `USING` for INSERT, so the only condition on a new row is that it names the caller. Migration 118's sweep did not revisit this policy (grep: `event_registrations` appears in 001, 020, 022, 102 only). The vendor check-in path never reads `paid` ([`vendor_service.dart:51`](../apps/mobile/lib/features/vendor/data/vendor_service.dart#L51)).
- **Reproduction (QA):** as any authenticated user, `POST {QA_URL}/rest/v1/event_registrations` with `{event_id: <a paid event>, user_id: <self>, status:'registered', paid:true, ticket_code:'TKT-X'}` → 201. The ticket screen then renders a valid QR and the vendor portal admits the holder.
- **Root cause:** a 2024-era convenience policy written for free events, never revisited when paid tickets landed in migration 022.
- **Financial impact:** every paid event is free to anyone willing to send one request. Revenue loss is bounded only by ticket price × attendance.
- **Entitlement impact:** full bypass of the one-time purchase path.
- **Security impact:** authorization defect — a client writes a field that only the payment processor should write. Same class as the `membership_tier`/`role` holes migration 115 closed for `user_profiles`.
- **Existing tests:** none. Spec added, skipped: `K-04 a paid event registration cannot be self-granted`.
- **Recommended fix:** split the policy. INSERT: `WITH CHECK (user_id = auth.uid() AND paid IS NOT TRUE AND EXISTS (SELECT 1 FROM events e WHERE e.id = event_id AND e.is_free))`. UPDATE: pin `paid` and `payment_id` in a `BEFORE UPDATE` trigger the way migration 115 pins the Stripe columns. Have the vendor check-in refuse an unpaid registration for a paid event.
- **Product decision required:** no.
- **Parallelizable:** yes.

---

### K-05 · P0 · Session credits are granted but never consumed or enforced
- **Flow:** session credits → coach/client package integrity
- **Expected:** buying an N-session pack grants N credits; booking a session spends one; a client with a zero balance cannot book.
- **Actual:** `client_session_credits` has exactly one writer in the entire codebase — the webhook's grant at [`stripe-webhook:130`](../supabase/functions/stripe-webhook/index.ts#L130). `sessions_used` is read in exactly one place, to count "active packages" for a coach dashboard tile ([`coach_revenue_service.dart:24-29`](../apps/mobile/lib/features/payments/data/coach_revenue_service.dart#L24-L29)). [`BookingScreen._book`](../apps/mobile/lib/features/booking/presentation/booking_screen.dart#L193) inserts a `coaching_calls` row and flips `coach_availability.is_booked` with no reference to credits at all.
- **Reproduction (QA):** buy a 5-session pack; confirm `sessions_total = 5, sessions_used = 0`. Book 12 sessions from the booking screen. All 12 succeed; `sessions_used` is still 0.
- **Root cause:** the credits ledger was built on the purchase side and never wired to the consumption side.
- **Financial impact:** a coach delivers unbounded labour for a fixed price; the client's paid balance is meaningless. For Connect coaches this is the coach's money, not the platform's, which makes it a marketplace-trust problem as well as a billing one.
- **Entitlement impact:** the session-package product does not exist as an enforceable entitlement.
- **Security impact:** no privilege escalation, but the RLS on the table is also wrong (see K-25).
- **Existing tests:** none. Spec added, skipped: `K-05 booking a session draws down a purchased session credit`.
- **Recommended fix:** a `SECURITY DEFINER` `book_coaching_session(slot_id uuid)` RPC that, in one transaction: locks the credit row (`FOR UPDATE`), refuses when `sessions_used >= sessions_total`, increments `sessions_used`, claims the availability slot conditionally (`UPDATE … WHERE is_booked = false` and check the row count — this also closes the double-booking race in the current client-side flow), and inserts the call. Cancellation refunds the credit per D-K2. Add `CHECK (sessions_used <= sessions_total)`.
- **Product decision required:** yes — does a client-cancelled session refund the credit, and how late? ► D-K2.
- **Parallelizable:** yes, but it should land with K-25 (the RLS on the same table).

---

### K-06 · P1 · Refunds and chargebacks revoke nothing
- **Flow:** refund / chargeback → entitlement
- **Expected:** a refunded purchase removes the entitlement it bought.
- **Actual:** `charge.refunded`, `charge.dispute.created` and `charge.dispute.closed` are not subscribed and not handled. Nothing in the codebase reads a refund. The Connect runbook records this explicitly: "Connected-account refunds/disputes and a coach earnings dashboard are future work" ([`STRIPE_CONNECT_SETUP.md`](../supabase/STRIPE_CONNECT_SETUP.md)).
- **Reproduction (QA test mode):** buy an event ticket, refund the payment intent in the Stripe test dashboard. `payments.status` stays `'paid'`; `event_registrations.paid` stays `true`; the QR still scans. Same for a package: `client_session_credits` is untouched.
- **Root cause:** no money-movement events are handled at all (K-02 is the same root).
- **Financial impact:** refund fraud is unbounded — buy, consume, refund, keep. For Connect destination charges the platform's application fee is also reversed while the coach's payout may already have been paid out.
- **Entitlement impact:** entitlements outlive the payment that bought them, indefinitely.
- **Security impact:** none technical; a fraud vector.
- **Existing tests:** none (covered by the K-02 spec).
- **Recommended fix:** handle `charge.refunded` → mark the `payments` row `refunded`, void unused session credits, unset `event_registrations.paid`, and cancel the associated subscription when the refund covers the current period. Handle `charge.dispute.created` → immediate suspension pending resolution, per D-K4.
- **Product decision required:** **yes** — what a refund revokes when credits have been partly consumed, and who absorbs the Connect fee. ► D-K4.
- **Parallelizable:** yes (after K-01 + K-02).

---

### K-07 · P1 · A failed Stripe cancel still revokes local access
- **Flow:** cancellation → partial failure
- **Expected:** if Stripe refuses the cancellation, the user keeps access and the operation reports failure.
- **Actual:** [`cancel-subscription/index.ts:53-59`](../supabase/functions/cancel-subscription/index.ts#L53-L59) wraps `stripe.subscriptions.cancel` in a try/catch that logs and continues; execution falls straight through to `subscriptions.update({status:'canceled'})` and the function returns `{ok:true}`.
- **Reproduction (QA):** unset or corrupt `STRIPE_SECRET_KEY` on the QA project (or point at a subscription id that does not exist in that Stripe account) and call the function. The Stripe call throws, the row still flips to `canceled`, the client shows "Switched to the Free plan", and the live Stripe subscription continues billing every month.
- **Root cause:** an availability-over-correctness choice ("reflect it locally now so the app updates without webhook latency") applied to the failure path as well as the success path.
- **Financial impact:** the customer is billed indefinitely for a product they can no longer use, and the database says they cancelled — so support cannot see it either. This is the worst-looking failure mode in the report from a customer's point of view.
- **Entitlement impact:** entitlement revoked while the subscription is live — the exact inverse of K-06.
- **Security impact:** none.
- **Existing tests:** none. Spec added, skipped: `K-07 a failed Stripe cancel does not revoke local entitlement`.
- **Recommended fix:** on a Stripe error, return 502 and leave the row untouched; treat `resource_missing` as an already-cancelled success. The optimistic local write is fine — but only after Stripe confirms.
- **Product decision required:** no.
- **Parallelizable:** yes.

---

### K-08 · P1 · Nothing prevents duplicate concurrent subscriptions
- **Flow:** checkout → subscription (double-spend)
- **Expected:** a user can hold at most one active platform membership and at most one active subscription per coach.
- **Actual:** `create-checkout` never checks for an existing active subscription before creating a session. Three concrete paths:
  - **(a)** [`upgrade_screen.dart:150-160`](../apps/mobile/lib/features/payments/presentation/upgrade_screen.dart#L150-L160) calls `changeMembership` and, on `'error'` **or** `'needs_checkout'`, falls through to a fresh checkout.
  - **(b)** [`update-subscription/index.ts:52-60`](../supabase/functions/update-subscription/index.ts#L52-L60) only matches `status IN ('active','trialing')`. A `past_due` member therefore gets `{needsCheckout:true}` and buys a **second** subscription while the first is still in Stripe's dunning cycle.
  - **(c)** `kind='coach'` and `kind='package_monthly'` have no uniqueness at all — the same client can subscribe to the same coach twice; `subscriptions` is keyed on `stripe_subscription_id`, so both rows coexist happily.
- **Reproduction (QA):** with an active `self_guided` membership, call `create-checkout {kind:'self_guided'}` directly and complete it. Two Stripe subscriptions, two rows, two charges per month. For (b): put a membership into `past_due` with test card `4000 0000 0000 0341`, then use the in-app Upgrade button.
- **Root cause:** the "one membership" invariant lives only in the Upgrade screen's control flow, not in the checkout function or the schema.
- **Financial impact:** double (or n-fold) billing of real customers — the highest-severity *customer-facing* financial defect after K-07, and a chargeback generator.
- **Entitlement impact:** none negative (the resolvers take the highest tier), which is exactly why it can go unnoticed.
- **Security impact:** none.
- **Existing tests:** none.
- **Recommended fix:** in `create-checkout`, before creating a session, refuse (409, with the existing subscription id) when the user already has a row in `('active','trialing','past_due','incomplete')` for the same `kind` (+ `coach_id` where applicable). Add a partial unique index: `CREATE UNIQUE INDEX … ON subscriptions (user_id, kind, coalesce(coach_id,'…')) WHERE status IN ('active','trialing','past_due')`. Widen `update-subscription`'s status filter to include `past_due` and `incomplete`.
- **Product decision required:** yes for one sub-case — may a client hold a platform membership **and** a coach subscription simultaneously (today both are charged)? ► D-K9.
- **Parallelizable:** yes.

---

### K-09 · P1 · Coach plan capacity is granted, never revoked, and is self-writable
- **Flow:** membership-tier synchronization → coach plan
- **Expected:** `max_clients` tracks the coach's paid tier and is server-owned.
- **Actual:** the webhook raises it on purchase ([`stripe-webhook:94`](../supabase/functions/stripe-webhook/index.ts#L94)) and no code path ever lowers it — `customer.subscription.deleted` touches only `subscriptions`. `max_clients` is **not** in migration 115's pinned/blocked column set (grep of [`115_profile_privilege_boundary.sql`](../supabase/migrations/115_profile_privilege_boundary.sql) returns no `max_clients`), so a coach can PATCH their own profile and set it to any value. Nothing enforces it anyway: the only reader is [`coach_provider.dart:159`](../apps/mobile/lib/features/coach/domain/coach_provider.dart#L159), which uses it to grey out "full" coaches in the marketplace.
- **Reproduction (QA):** buy Starter as a coach → `max_clients = 25`. Cancel → it stays 25. Then `PATCH /rest/v1/user_profiles?id=eq.<self>` with `{"max_clients": 100000}` → 200. Accept a 26th client → succeeds either way, because nothing checks.
- **Root cause:** the tier→capacity mapping is a one-way write with no enforcement point.
- **Financial impact:** Starter ($99) buys Elite ($299) capacity; the $200/month tier differential is unenforceable.
- **Entitlement impact:** the coach platform plan's headline benefit is not an entitlement.
- **Security impact:** a client-writable column that carries a purchased limit — the same class migration 115 closed for `membership_tier` and `marketplace_commission_rate`, missed for this one.
- **Existing tests:** none. Spec added, skipped: `K-09 losing the coach plan restores the free client capacity`.
- **Recommended fix:** add `max_clients` to the migration-115 hard-block list; reset it to the free default on `customer.subscription.deleted` for `kind='coach_plan'`; enforce the cap where a relationship is activated (a `BEFORE INSERT/UPDATE` trigger on `coach_client_relationships` counting active rows against `coach_plan_tier()`), per D-K8.
- **Product decision required:** yes — hard block vs. soft warning at the cap. ► D-K8.
- **Parallelizable:** yes.

---

### K-10 · P1 · Coach messaging — a Coach-Guided-only capability — has no paid-state check
- **Flow:** entitlement → server-side enforcement
- **Expected:** `canMessageCoach` (Coach-Guided only, [`entitlements.dart:46`](../apps/mobile/lib/features/payments/domain/entitlements.dart#L46)) is enforced where messages are written.
- **Actual:** `conversations` INSERT is `WITH CHECK (participant_1 = auth.uid() OR participant_2 = auth.uid())` and `messages` INSERT is `WITH CHECK (sender_id = auth.uid())` ([`003_fk_and_rls_fixes.sql:68-94`](../supabase/migrations/003_fk_and_rls_fixes.sql#L68-L94)). No subscription or relationship predicate at all. The `/messages` and `/chat` routes are wrapped in `PaywallGate` in the router — that is the whole enforcement.
- **Reproduction (QA):** as a free account, insert a `conversations` row naming yourself and any coach, then insert a `messages` row. Both 201. The coach receives the notification (the `notify_on_message` trigger fires).
- **Root cause:** same as K-03 — the paywall is a screen, not a boundary.
- **Financial impact:** the Coach-Guided tier's differentiator is free; it also lets non-customers reach coaches, which is the marketplace's disintermediation risk.
- **Entitlement impact:** full bypass of the top tier's exclusive capability.
- **Security impact:** unsolicited-contact surface; adjacent to the notification-injection class migration 118 closed (F-03).
- **Existing tests:** none.
- **Recommended fix:** require an active relationship **and** a paying state on the `conversations` INSERT policy (`is_active_coach_of` already exists for the coach direction; add the client direction), and keep `messages` scoped to conversations the caller participates in.
- **Product decision required:** yes, mildly — may a prospective client message a coach *before* purchasing (a common marketplace pattern)? If so, the correct gate is a capped pre-sales thread, not an open one.
- **Parallelizable:** yes.

---

### K-11 · P1 · The first failed payment revokes access immediately
- **Flow:** payment failure → entitlement
- **Expected:** a card failure starts a grace period; access ends when dunning is exhausted.
- **Actual:** `client_plan()`, `active_membership()` and `coach_plan_tier()` all require `status IN ('active','trialing')`. Stripe sets `past_due` on the first failed invoice, `customer.subscription.updated` writes it, and the very next `client_plan()` call returns `'free'`. Meanwhile the UI treats `past_due` as a live membership for cancellation purposes ([`upgrade_screen.dart:128-132`](../apps/mobile/lib/features/payments/presentation/upgrade_screen.dart#L128-L132), [`manage_subscription_screen.dart:117,210`](../apps/mobile/lib/features/payments/presentation/manage_subscription_screen.dart#L117)) — two different definitions of "still a member" in one codebase.
- **Reproduction (QA test mode):** subscribe with `4000 0000 0000 0341` (attaches, fails on charge). Membership is granted then lost within one webhook round-trip; the user has paid nothing and Stripe will keep retrying for weeks.
- **Root cause:** entitlement derived from Stripe status alone, with no grace concept.
- **Financial impact:** avoidable involuntary churn — the customer loses the product while Stripe is still trying to collect, which is the worst moment to remove value.
- **Entitlement impact:** premature revocation; and the inverse UI inconsistency above.
- **Security impact:** none.
- **Existing tests:** none.
- **Recommended fix:** add `past_due` to the resolvers behind a bounded grace window (`current_period_end + interval '<grace>'`), driven by `invoice.payment_failed` from K-02, and make the UI use the same definition.
- **Product decision required:** **yes** — grace length and what is degraded during it. ► D-K3.
- **Parallelizable:** yes (schema-light; one migration + the resolvers).

---

### K-12 · P1 · `verify_jwt` for the webhook is not declared in `config.toml`
- **Flow:** webhook endpoint configuration
- **Expected:** the webhook's JWT exemption is declarative and survives redeployment.
- **Actual:** [`config.toml`](../supabase/config.toml) contains `project_id` and `[db.seed]` and nothing else — no `[functions.*]` block. The exemption exists only as the `--no-verify-jwt` flag in the runbook ([`STRIPE_SETUP.md:33`](../supabase/STRIPE_SETUP.md#L33)) or as dashboard state. **UNVERIFIABLE FROM REPO** whether the deployed QA/production functions currently carry it.
- **Reproduction:** `supabase functions deploy stripe-webhook` **without** the flag. Every Stripe delivery then gets 401 before reaching the handler. Stripe retries for ~3 days, then drops. No user who paid in that window is ever granted anything, and there is no alert (K-27) and no reconciliation job to repair it.
- **Root cause:** a critical deployment property held only in a human-followed runbook step.
- **Financial impact:** silent, total loss of entitlement grants for every payment in the outage window — money taken, nothing delivered.
- **Entitlement impact:** total, for the duration.
- **Security impact:** the inverse mistake (declaring `verify_jwt = true` where `false` is needed, or vice-versa on another function) is equally silent.
- **Existing tests:** none. Spec added, skipped: `K-12 verify_jwt is declared for the webhook in config.toml`.
- **Recommended fix:** add `[functions.stripe-webhook] verify_jwt = false` and declare `verify_jwt = true` explicitly for every other function (this also closes G's REL-24 tail). Add an uptime check on the endpoint.
- **Product decision required:** no.
- **Parallelizable:** yes.

---

### K-13 · P1 · Stripe customer creation races; a user can end up with two Stripe customers
- **Flow:** Stripe customer identity
- **Expected:** exactly one Stripe customer per user, for the lifetime of the account.
- **Actual:** [`create-checkout:69-80`](../supabase/functions/create-checkout/index.ts#L69-L80) does read-then-create-then-write with no lock, no unique constraint on `user_profiles.stripe_customer_id`, and no Stripe idempotency key. Two concurrent checkouts (two tabs, a double-tap, or a client retry after a timeout) create two customers; the second write wins.
- **Reproduction (QA):** fire two `create-checkout` calls in parallel for a user with a null `stripe_customer_id`. Two `cus_…` objects exist in the test-mode dashboard; the profile references one of them.
- **Root cause:** unguarded read-modify-write on an externally-created identity.
- **Financial impact:** subscriptions land under the orphaned customer, so the Billing Portal ([`create-portal-session`](../supabase/functions/create-portal-session/index.ts)) shows the user a customer that does not hold their subscription — they cannot update the card or cancel, and support cannot find the charge.
- **Entitlement impact:** none directly (the webhook keys off `stripe_subscription_id`, not the customer).
- **Security impact:** none.
- **Existing tests:** none.
- **Recommended fix:** `stripe.customers.create(…, { idempotencyKey: 'customer:' + user.id })`, plus a conditional write (`UPDATE … WHERE stripe_customer_id IS NULL RETURNING …`) and re-read on conflict; add a UNIQUE index on the column.
- **Product decision required:** no.
- **Parallelizable:** yes.

---

### K-14 · P2 · The same commission rate prices differently on one-time vs recurring charges
- **Flow:** Stripe Connect → commission
- **Expected:** a configured rate produces the same effective commission on every coaching charge.
- **Actual:** the one-time leg uses exact cents — `application_fee_amount = Math.round(cents * rate)` ([`create-checkout:264,277`](../supabase/functions/create-checkout/index.ts#L264)). The recurring leg uses `application_fee_percent: Math.round(rate * 100)` ([`:282`](../supabase/functions/create-checkout/index.ts#L282)), a whole percent. A configured 0.125 is 12.5% on a package and 13% on a subscription. `application_fee_percent` also has no `> 100` or `< 0` guard, and `platform_settings.value` is an unvalidated text column ([`039_platform_settings.sql`](../supabase/migrations/039_platform_settings.sql)) — an admin typing `15` instead of `0.15` yields `application_fee_percent: 1500` and every coaching checkout fails.
- **Reproduction:** set `platform_settings.marketplace_commission_rate = '0.125'` on QA and compare a `package` checkout against a `package_monthly` checkout for the same price.
- **Root cause:** two different Stripe fee primitives fed from one rate, one of which is integral.
- **Financial impact:** small per transaction, systematic across the marketplace; and a mis-typed setting takes coaching checkout down entirely.
- **Entitlement impact:** none.
- **Security impact:** none (the setting is admin-only, [`039:20-25`](../supabase/migrations/039_platform_settings.sql#L20-L25)).
- **Existing tests:** the divergence is now pinned by the active test `K-14 — recurring and one-time legs price a fractional rate differently`, so a fix must update it deliberately.
- **Recommended fix:** `application_fee_percent` accepts up to two decimal places — pass `Number((rate * 100).toFixed(2))`. Add `CHECK (value::numeric >= 0 AND value::numeric <= 1)` on the setting, and clamp in the function.
- **Product decision required:** no (rate *value* is D-K7).
- **Parallelizable:** yes.

---

### K-15 · P1 · Three-and-a-half tier representations, only one of which is synchronized
- **Flow:** membership-tier synchronization
- **Expected:** one authoritative representation of a user's tier.
- **Actual:** four exist. (1) `subscriptions` + `client_plan()` — authoritative and correct. (2) `user_profiles.membership_tier` — `CHECK IN ('basic','pro','elite')` ([`010:11-12`](../supabase/migrations/010_profile_columns.sql#L11)), pinned against client writes by migration 115, and **written by no billing code anywhere** — it is `'basic'` for every user forever, and it is injected into the AI coaching prompt ([`ai-coaching-engine:123`](../supabase/functions/ai-coaching-engine/index.ts#L123)), so the AI is told every paying customer is on the basic tier. (3) `user_profiles.coaching_mode` — `self_guided|ai_guided|coach_guided`, i.e. the paid tier names, **client-writable** and set by the user in Settings. (4) `user_profiles.max_clients` for coaches (K-09).
- **Reproduction:** any paying account — `select membership_tier from user_profiles where id = …` → `'basic'`.
- **Root cause:** `membership_tier` predates the subscription model and was never retired; `coaching_mode` is a preference that borrowed the tier vocabulary.
- **Financial impact:** none directly; it makes every revenue/cohort query written against `membership_tier` silently wrong.
- **Entitlement impact:** none today — nothing gates on `membership_tier`, and `coaching_mode` does not feed `client_plan()`. The risk is a future gate wired to the wrong column.
- **Security impact:** low; a user can set `coaching_mode='ai_guided'` and any code that later trusts it inherits a self-granted tier.
- **Existing tests:** the settings and subscription screens carry comments explaining that they deliberately avoid `membership_tier` ([`settings_screen.dart:75`](../apps/mobile/lib/features/settings/presentation/settings_screen.dart#L75), [`subscription_screen.dart:67`](../apps/mobile/lib/features/profile/presentation/subscription_screen.dart#L67)) — institutional knowledge, not a guard.
- **Recommended fix:** either drive `membership_tier` from the webhook or drop it and remove it from the AI prompt payload; rename `coaching_mode` (it is a training-style preference, not a tier).
- **Product decision required:** no.
- **Parallelizable:** yes.

---

### K-16 · P1 · Account deletion has no billing path (and no path at all)
- **Flow:** account deletion → billing
- **Expected:** deleting an account cancels its subscriptions before removing the data.
- **Actual:** there is no deletion flow in the app (confirmed again this session: grep finds only the help-centre and privacy-policy screens *claiming* one exists — [`help_center_screen.dart:45`](../apps/mobile/lib/features/settings/presentation/help_center_screen.dart#L45), [`privacy_policy_screen.dart:86`](../apps/mobile/lib/features/settings/presentation/privacy_policy_screen.dart#L86)). `subscriptions.user_id` and `payments.user_id` are `ON DELETE CASCADE` ([`022:16,37`](../supabase/migrations/022_payments.sql#L16)), so an operator deleting the `auth.users` row destroys the local record while the Stripe subscription bills on, with nothing left to link the charge to.
- **Reproduction:** delete a QA test user with an active subscription via the Supabase dashboard; the Stripe subscription is untouched and the local trace is gone.
- **Root cause:** REL-04 (no deletion flow) intersecting a CASCADE that was chosen for GDPR-style cleanup.
- **Financial impact:** billing a deleted account is a chargeback and a regulatory problem; the audit trail for the charge is gone.
- **Entitlement impact:** n/a.
- **Security impact:** loss of financial audit trail.
- **Existing tests:** none.
- **Recommended fix:** whichever deletion flow REL-04 produces must, in order: cancel every Stripe subscription, detach payment methods, then soft-delete; change `payments` to `ON DELETE SET NULL`/restrict so the ledger survives the profile.
- **Product decision required:** yes — retention period for financial records after deletion (tax/regulatory).
- **Parallelizable:** no — it is a sub-requirement of the REL-04 deletion work.

---

### K-17 · P1 · Coach Connect readiness is cached and only refreshed when the coach looks at it
- **Flow:** Stripe Connect
- **Expected:** a coach whose account loses `charges_enabled` stops receiving checkouts immediately.
- **Actual:** `user_profiles.stripe_charges_enabled` is written **only** inside `stripe-connect` `action:'status'` ([`stripe-connect:47-60`](../supabase/functions/stripe-connect/index.ts#L47-L60)), i.e. when the coach opens their Payments screen. `account.updated` is not subscribed. `create-checkout` gates client purchases on that cached column ([`create-checkout:243-249`](../supabase/functions/create-checkout/index.ts#L243-L249)).
- **Reproduction:** cannot be reproduced without Stripe dashboard access to a connected test account (**UNVERIFIABLE FROM REPO** — the mechanism is plain in the source). Restrict a test connected account; the column stays `true` until the coach revisits the screen.
- **Financial impact:** destination charges to a restricted account fail at payment time or have funds held; the client believes they bought coaching.
- **Entitlement impact:** relationship activated (or not) against a payment that will not settle.
- **Security impact:** none.
- **Existing tests:** none.
- **Recommended fix:** subscribe `account.updated` on the Connect webhook and write the three booleans from the event; keep the pull path as a fallback.
- **Product decision required:** no.
- **Parallelizable:** yes.

---

### K-18 · P2 · The global commission setting silently overrides the per-coach rate
- **Flow:** Connect commission
- **Expected:** per the comment in the source — "Admin-configurable global marketplace commission, **falling back to** the coach's column then 10%".
- **Actual:** the code does the opposite ([`create-checkout:259-262`](../supabase/functions/create-checkout/index.ts#L259-L262)): it reads the coach's column, then unconditionally overwrites it whenever the `platform_settings` row exists — and migration 039 seeds that row on every environment. So `user_profiles.marketplace_commission_rate` is dead configuration; a negotiated rate for a specific coach is ignored.
- **Reproduction (QA):** set a coach's `marketplace_commission_rate` to `0.05` (service role — it is client-blocked by migration 115) and start a marketplace-sourced coaching checkout. `metadata.commission_rate` is `0.10`, the global value.
- **Root cause:** precedence inverted relative to the documented intent.
- **Financial impact:** either the platform over-charges a coach who negotiated a lower rate, or under-charges one on a higher rate — in both cases silently, and with the split recorded on the row so it looks deliberate.
- **Entitlement impact:** none.
- **Security impact:** none.
- **Existing tests:** the 10% default in both places is now pinned by an active test.
- **Recommended fix:** decide the precedence (► D-K7) and implement it explicitly, e.g. `rate = coach.marketplace_commission_rate ?? setting ?? 0.10`, with the comment corrected either way.
- **Product decision required:** **yes** ► D-K7.
- **Parallelizable:** yes.

---

### K-19 · P1 · Coach revenue figures are structurally wrong
- **Flow:** UI → coach earnings
- **Expected:** lifetime revenue = the sum of everything actually collected for that coach.
- **Actual:** [`coach_revenue_service.dart:47-56`](../apps/mobile/lib/features/payments/data/coach_revenue_service.dart#L47-L56) adds each **active** subscription's `coach_payout` to `lifetime` exactly once. A subscription active for 14 months contributes one month; a cancelled subscription contributes **zero** to lifetime, retroactively. And because no renewal ever produces a `payments` row (K-02), there is nothing else to count. `subscriptions.coach_payout` is also frozen at the value captured from checkout metadata and never re-derived, so a price change or a proration is never reflected.
- **Reproduction:** any coach with one cancelled subscription — lifetime revenue drops when the client leaves.
- **Root cause:** revenue computed from current subscription state instead of from a payment ledger.
- **Financial impact:** the numbers 12 Circle shows coaches about their own money are wrong in both directions. In a marketplace this is a trust and potentially a contractual problem.
- **Entitlement impact:** none.
- **Security impact:** none.
- **Existing tests:** none.
- **Recommended fix:** compute revenue from `payments` once K-02 populates it per invoice; keep `subscriptions` for MRR only.
- **Product decision required:** no.
- **Parallelizable:** no — blocked on K-02.

---

### K-20 · P2 · A coach can zero their own commission by pre-inviting the lead
- **Flow:** Connect commission integrity
- **Expected:** `client_source` reflects how the client actually arrived.
- **Actual:** `client_source` is decided at relationship INSERT by [`set_relationship_client_source`](../supabase/migrations/113_rls_coach_client_relationships.sql#L184-L206), which tags the relationship `coach_invited` (0% commission) whenever **any** `coach_invites` row exists for that coach with the client's email. `coach_invites` is governed by `CREATE POLICY "coaches manage invites" … FOR ALL TO authenticated USING (coach_id = auth.uid())` ([`001:347`](../supabase/migrations/001_full_ecosystem.sql#L347)) — `FOR ALL` with no `WITH CHECK`, so a coach may insert an invite for any email address at any time.
- **Reproduction (QA):** as a coach, insert `coach_invites {coach_id: self, invitee_email: <a marketplace prospect>}`. When that user later requests the coach from the marketplace, the relationship is tagged `coach_invited` and every subsequent charge carries a 0% application fee.
- **Root cause:** a commission-bearing predicate derived from a table the beneficiary can write freely.
- **Mitigating factor (verified):** migration 113 makes `client_source` immutable after insert, and clients cannot DELETE relationships, so the tag cannot be flipped after the fact — the coach must pre-invite. The window is real but requires intent and foresight.
- **Financial impact:** systematic loss of marketplace commission — the platform's only revenue from coaching.
- **Entitlement impact:** none.
- **Security impact:** authorization defect of the same shape as K-04 (a `FOR ALL … USING` policy with no `WITH CHECK`).
- **Existing tests:** none.
- **Recommended fix:** require the invite to have been **accepted** (an `accepted_at`/`status` on `coach_invites`, or a match on the invite token the client actually used) rather than merely to exist; and/or set `client_source` from the code path that creates the relationship rather than by inference.
- **Product decision required:** yes, lightly — the exact definition of "coach-brought". ► D-K7.
- **Parallelizable:** yes.

---

### K-21 · P2 · Checkout and portal redirect targets are caller-controlled with no allowlist
- **Flow:** checkout creation → redirect URLs
- **Actual:** `successUrl` / `cancelUrl` / `returnUrl` are taken from the request body and passed to Stripe unvalidated — [`create-checkout:83-84`](../supabase/functions/create-checkout/index.ts#L83-L84) and the embedded `return_url`, [`create-portal-session:51`](../supabase/functions/create-portal-session/index.ts#L51), [`stripe-connect`](../supabase/functions/stripe-connect/index.ts) `refresh_url`/`return_url`. The app itself supplies `Uri.base.origin` ([`payment_service.dart:19-22`](../apps/mobile/lib/features/payments/data/payment_service.dart#L19-L22)), but the function accepts anything. All five billing functions also send `Access-Control-Allow-Origin: '*'`.
- **Reproduction:** call `create-checkout` with `successUrl: 'https://attacker.example/paid'` — the session is created and Stripe redirects there after a real payment.
- **Financial impact:** none directly. **Security impact:** a post-payment landing page under attacker control is a credible phishing surface ("your payment failed, re-enter your card"), and the session id is handed to it. It also means the redirect target for the *production* domain is unverified — G's REL-17 notes `12circle.app` itself is unconfirmed.
- **Entitlement impact:** none.
- **Existing tests:** none.
- **Recommended fix:** an `ALLOWED_REDIRECT_ORIGINS` env allowlist; reject anything else and fall back to the configured `APP_URL`. Scope CORS to the app's own origins.
- **Product decision required:** no (needs the domain decision D-3 from Workstream G to be settled first).
- **Parallelizable:** yes.

---

### K-22 · P2 · The webhook grants one-time entitlements without checking `payment_status`
- **Flow:** webhook → entitlement
- **Actual:** the `event_ticket` and `package` branches mark the payment `paid` and grant the registration/credits on `checkout.session.completed` alone, never reading `session.payment_status` ([`stripe-webhook:97-137`](../supabase/functions/stripe-webhook/index.ts#L97-L137)). `checkout.session.async_payment_succeeded` / `_failed` are not handled.
- **Reproduction:** requires a delayed-notification payment method (not enabled today — card only). **UNVERIFIABLE FROM REPO** whether other methods are enabled in the Stripe account.
- **Financial impact:** latent — the day someone enables a delayed payment method (bank debits, Klarna, Cash App Pay) in the Stripe dashboard, unpaid sessions grant tickets and credits.
- **Entitlement impact:** entitlement granted before settlement.
- **Security impact:** none.
- **Existing tests:** none.
- **Recommended fix:** `if (session.payment_status !== 'paid') return 200` for one-time kinds, and handle the two async events.
- **Product decision required:** no.
- **Parallelizable:** yes.

---

### K-23 · P2 · No event ordering guard — a stale update can resurrect a cancelled subscription
- **Flow:** webhook → database state
- **Actual:** [`stripe-webhook:142-149`](../supabase/functions/stripe-webhook/index.ts#L142-L149) unconditionally writes whatever the event carries. Stripe does not guarantee ordering; a retried `customer.subscription.updated` (status `active`) delivered after `customer.subscription.deleted` overwrites `canceled` with `active`.
- **Reproduction (QA test mode):** resend an older `subscription.updated` event from the dashboard after the subscription has been deleted; the row returns to the stale status and `client_plan()` grants the tier again.
- **Financial impact:** access without payment, indefinitely (there is no reconciliation job to correct it).
- **Entitlement impact:** stale entitlement, unbounded.
- **Security impact:** none.
- **Existing tests:** none.
- **Recommended fix:** store the event `created` timestamp on the row and apply only strictly newer events; K-01's event store gives the natural home for it.
- **Parallelizable:** yes (with K-01).

---

### K-24 · P2 · Abandoned checkouts leak pending payment rows; no reconciliation exists
- **Flow:** checkout → database state
- **Actual:** `create-checkout` inserts a `payments` row with `status='pending'` **before** creating the Stripe session ([`create-checkout:148`](../supabase/functions/create-checkout/index.ts#L148) and [`:208`](../supabase/functions/create-checkout/index.ts#L208)). `checkout.session.expired` is not handled, so every abandoned checkout leaves a permanent `pending` row. There is no job anywhere that compares Stripe state to the `subscriptions`/`payments` tables — the webhook is the only writer, with no repair path (also raised as G's REL-24 tail).
- **Financial impact:** none directly; it makes every "pending payments" query and any future revenue report unusable, and there is no way to detect the K-12/K-27 failure modes.
- **Entitlement impact:** none.
- **Existing tests:** none.
- **Recommended fix:** handle `checkout.session.expired` → `status='expired'`; add a scheduled reconciliation that lists Stripe subscriptions/invoices and repairs drift (the repo already runs `pg_cron` jobs, migration 076).
- **Parallelizable:** yes.

---

### K-25 · P2 · The session-credit RLS lets a coach rewrite the balance and its owner
- **Flow:** session credits → integrity
- **Actual:** [`028_package_payments.sql:44-47`](../supabase/migrations/028_package_payments.sql#L44-L47) — `FOR UPDATE TO authenticated USING (coach_id = auth.uid()) WITH CHECK (coach_id = auth.uid())`. The intent (per the comment) is "the coach can log a used session", but the policy covers **every column**: the coach can raise or lower `sessions_total`, reset `sessions_used`, or move the row to a different `client_id`. There is no `CHECK (sessions_used <= sessions_total)`.
- **Reproduction (QA):** as the coach, `PATCH /rest/v1/client_session_credits?id=eq.<row>` with `{"sessions_total": 999}` → 200.
- **Financial impact:** a coach can grant themselves paid-looking balances or erase a client's paid balance.
- **Entitlement impact:** the credit ledger is not tamper-evident.
- **Security impact:** over-broad UPDATE policy — the class migration 115 addressed for profiles.
- **Existing tests:** none.
- **Recommended fix:** revoke the direct UPDATE; expose a `consume_session_credit()` RPC (which K-05 needs anyway) and pin every column but `sessions_used` in a trigger; add the CHECK constraint.
- **Parallelizable:** ship with K-05.

---

### K-26 · P1 · The production build default ships a **test-mode** publishable key
- **Flow:** environment isolation / test vs live keys
- **Actual:** [`app_env.dart:117-121`](../apps/mobile/lib/core/config/app_env.dart#L117-L121) — `_prodStripePublishableKey = 'pk_test_51TjY6f…'`, wired into `kEnvironmentDefaults[prod]` at [`:143`](../apps/mobile/lib/core/config/app_env.dart#L143). `APP_ENV` itself defaults to `'prod'` ([`:151`](../apps/mobile/lib/core/config/app_env.dart#L151)), and [`dart_defines/prod.json`](../apps/mobile/dart_defines/prod.json) carries `"STRIPE_PK": ""`, so `npm run build:web:prod` produces a "production" bundle holding a **test** key. QA's `STRIPE_PK` is empty, so QA falls back to hosted redirect checkout (embedded checkout is unavailable there). The `STRIPE_SECRET_KEY` behind the Edge Functions is per-Supabase-project and is **UNVERIFIABLE FROM REPO** for either environment.
- **Reproduction:** `npm run build:web:prod` and grep the bundle for `pk_test_`.
- **Financial impact:** today it is *protective* — production cannot take live money. The moment live keys are introduced, there is no mechanism preventing the inverse (a live key in a QA/TestFlight build): no assertion ties `APP_ENV=prod` to `pk_live_`, or `qa` to `pk_test_`.
- **Entitlement impact:** none.
- **Security impact:** publishable keys are client-safe; the risk is the missing key/environment binding.
- **Existing tests:** [`env_config_test.dart`](../apps/mobile/test/unit/env_config_test.dart) and [`qa_environment_isolation_test.dart`](../apps/mobile/test/unit/qa_environment_isolation_test.dart) assert environment resolution and that QA cannot reach prod — neither asserts anything about the Stripe key prefix.
- **Recommended fix:** (this is G's REL-07) remove the baked defaults; move them into `dart_defines/prod.json`; add assertions that `prod` requires `pk_live_` and `dev`/`qa` reject it; extend `check_web_build_secrets.sh` to fail a QA bundle containing `pk_live_`.
- **Product decision required:** no.
- **Parallelizable:** yes.

---

### K-27 · P2 · Webhook failures are silent
- **Flow:** retry / partial failure
- **Actual:** the handler catches, logs to `console.error` and returns 500 ([`stripe-webhook:157-160`](../supabase/functions/stripe-webhook/index.ts#L157-L160)). Stripe retries with backoff for ~3 days and then stops. No dead-letter table, no alert, no dashboard, and (K-24) no reconciliation to notice afterwards. Combined with K-01, a mid-handler failure followed by a retry is also the concrete double-grant path.
- **Financial impact:** payments collected with entitlement never granted, discovered only when a customer complains.
- **Recommended fix:** persist failures (event id, type, payload, error) to a dead-letter table, alert on non-zero depth, and add a replay tool.
- **Parallelizable:** yes (with K-01).

---

### K-28 · P3 · `Access-Control-Allow-Origin: '*'` on all five billing functions
Any origin can invoke `create-checkout`, `cancel-subscription`, `update-subscription`, `create-portal-session` and `stripe-connect` with a bearer token. Supabase sessions live in `localStorage`, not cookies, so this is not classic CSRF, but it removes a cheap layer against token-replay from a hostile page. **Fix:** allowlist the app origins. **Parallelizable:** yes.

---

### K-29 · P3 · Trials are resolvable but not creatable
`status = 'trialing'` is honoured by all three resolvers, the UI treats it as active, and `customer.subscription.trial_will_end` is unhandled. No `trial_period_days` appears anywhere in `create-checkout`, so no trial can ever be created. Half a feature. **Fix:** either implement it (D-K5) or drop `'trialing'` from the resolvers so the surface matches reality. **Parallelizable:** yes.

---

### K-30 · P3 · `PaywallGate` fails open on error
[`paywall_gate.dart:45`](../apps/mobile/lib/features/payments/presentation/paywall_gate.dart#L45) — `error: (_, __) => child`, deliberately, "fail open rather than lock a paying user out". It is currently unreachable because [`PaymentService.clientPlan`](../apps/mobile/lib/features/payments/data/payment_service.dart) swallows every exception and returns `'free'`, so the provider never enters the error state — the gate actually fails *closed*. The comment and the code disagree, and the branch becomes live the moment that `catch` is tightened. Given K-03/K-10, the gate is UX rather than security either way. **Fix:** decide one behaviour and make both layers express it. **Parallelizable:** yes.

---

## 7. Environment blockers

| ID | Blocker | Evidence | Consequence for this workstream |
|---|---|---|---|
| **K-ENV-1** | **P0** — `tool/qa_entitlements.dart`, the repository's canonical "Entitlement & Subscription QA certification harness", is hardcoded to the **production** project and seeds subscription state with the service-role key ([`qa_entitlements.dart:27`](../apps/mobile/tool/qa_entitlements.dart#L27)). `tool/qa_self_guided.dart:22` and `tool/live_integration_test.dart:15` are the same. This is G's REL-18, **re-verified as still open**. | grep for `nxdbooufqzkpslkcogxc` | **The one purpose-built tool for this workstream could not be run.** Running it would have signed up users and written subscription rows into production. Every dynamic entitlement assertion in this report is therefore a source derivation, not an execution result. |
| K-ENV-2 | No Stripe test-mode credentials are available to this session, and none should be: exercising checkout requires `STRIPE_SECRET_KEY` + `STRIPE_WEBHOOK_SECRET` in the QA project's secret store. **UNVERIFIABLE FROM REPO** whether QA has them. | [`STRIPE_SETUP.md`](../supabase/STRIPE_SETUP.md) names only the production ref | No live checkout → webhook → entitlement round trip was performed. |
| K-ENV-3 | The Stripe runbooks target production only — project ref, secret-setting command and webhook endpoint URL are all `nxdbooufqzkpslkcogxc` ([`STRIPE_SETUP.md:7,12,38`](../supabase/STRIPE_SETUP.md#L7)). There is no QA equivalent and no `dart_defines/staging.json`. | source | QA cannot be stood up for billing without writing the runbook first. |
| K-ENV-4 | `QA_STRIPE_PK` is empty in [`dart_defines/qa.json`](../apps/mobile/dart_defines/qa.json), so embedded checkout is unreachable in QA — only the hosted redirect path is testable there. | source | The embedded checkout code path (`embedded_checkout_web.dart`, `checkout_complete.html`) is untested in the only safe environment. |
| K-ENV-5 | Whether the deployed webhook carries `--no-verify-jwt`, which events the endpoint is actually subscribed to, and whether Connect is enabled are all dashboard state. | K-12 | Three of the webhook matrix's rows are "as configured in the runbook", not "as observed". |

---

## 8. Product decisions required

These are **decisions, not defects**. No engineering choice can settle them, and this report does not assume an answer.

| ID | Decision | Why it is a decision | Blocks |
|---|---|---|---|
| **D-K1** | **iOS purchase path.** `self_guided` ($29) and `ai_guided` ($59) are digital services sold through hosted Stripe Checkout opened in an external browser ([`checkout_launcher.dart`](../apps/mobile/lib/features/payments/presentation/checkout_launcher.dart)). Apple Guideline 3.1.1 requires In-App Purchase for digital content; 3.1.3(e) exempts person-to-person real-time services, which is a plausible argument for `coach` but not for the two digital tiers. Options: (a) StoreKit 2 IAP for the digital tiers + a second receipt-driven entitlement reconciler alongside the Stripe one, keeping Stripe for coaching and web; (b) ship iOS with coaching commerce only; (c) ship iOS with no purchase surface. **This report does not interpret App Store policy** — it records the mechanism and the exposure. Identical to G's REL-05 / D-1. | Apple policy interpretation + business model | the entire iOS release; a second entitlement source of truth |
| **D-K2** | **Cancellation terms.** Today cancellation is immediate with no refund and the remaining paid period is forfeited ([`cancel-subscription`](../supabase/functions/cancel-subscription/index.ts), confirmed in the UI copy at [`upgrade_screen.dart:179-181`](../apps/mobile/lib/features/payments/presentation/upgrade_screen.dart#L179-L181)). The alternative is `cancel_at_period_end`, which is the industry norm and what the Billing Portal does. The two paths currently coexist and disagree. | Owner pricing/consumer-terms decision | K-05 (credit refund on cancelled sessions), the UI copy |
| **D-K3** | **Dunning grace window.** How long does a `past_due` member keep access? (K-11) | Revenue vs. churn trade-off | K-11, K-02's failure branch |
| **D-K4** | **Refund and chargeback policy.** What is revoked when a package is refunded after 3 of 10 sessions are used; who absorbs the reversed Connect application fee; is a dispute an immediate suspension. (K-06) | Marketplace terms | K-06 |
| **D-K5** | **Trials.** Offer one, and at what length? (K-29) | Growth decision | K-29 |
| **D-K6** | **Proration on tier migration.** `update-subscription` uses `create_prorations` ([`:69`](../supabase/functions/update-subscription/index.ts#L69)) — an AI→Self downgrade banks a credit against the next invoice rather than refunding. Acceptable, but it is a pricing choice and it is not stated anywhere in the UI. | Pricing | UI copy |
| **D-K7** | **Commission authority.** Is the marketplace rate global-only (today's *behaviour*) or per-coach negotiable (today's *stated intent* and the column that exists)? And what exactly makes a client "coach-brought"? (K-18, K-20) | Business model | K-18, K-20 |
| **D-K8** | **Coach capacity.** Is `max_clients` a hard block or a soft signal? (K-09) | Product | K-09 |
| **D-K9** | **Stacking.** May a client hold a platform membership **and** a coach subscription at once? Both are charged today, and `client_plan()` reports only the higher tier — so the customer pays twice and sees one plan. (K-08) | Pricing | K-08 |
| **D-K10** | **Currency.** `'usd'` is hardcoded in every `price_data` and every table default. Single-currency is a decision, not an oversight — but it should be a recorded one. | Market | future i18n |

---

## 9. Tests

### 9.1 Suites run this session (offline, no network)

| Suite | Command | Result |
|---|---|---|
| Flutter (mobile) | `flutter test` | **667 passed, 9 skipped** (was 623 passed before this workstream) |
| NestJS unit | `npm test --workspace apps/api` | **58 passed**, 8 suites |
| NestJS e2e | `npm run test:e2e --workspace apps/api` | **6 passed**, 2 suites |

Not run, deliberately: `npm run test:security` (`supabase/tests/security/run.mjs`) requires live project credentials, and `tool/qa_entitlements.dart` targets production (K-ENV-1).

### 9.2 Coverage before this workstream

**Zero.** No test in the repository exercised checkout, the webhook, subscription state, session credits, the commission split, or any entitlement resolution. `env_config_test.dart` touches the Stripe key only as a config value; `phase1_security_boundary_test.dart` touches Stripe columns only as part of the migration-115 privilege list.

### 9.3 Added

**[`apps/mobile/test/unit/billing_entitlement_contract_test.dart`](../apps/mobile/test/unit/billing_entitlement_contract_test.dart)** — 29 tests (20 active, 9 skipped open specs). Static guards in the idiom of `phase1_security_boundary_test.dart`: they parse the committed Edge Function TypeScript, SQL and Dart. No Stripe call, no network, no credentials.

Active guards (these pin what is already correct, so remediation cannot silently break it):
- `K/TIER` — the six checkout kinds; that the webhook classifies `package_monthly` (the one kind whose name differs between producer and consumer); `client_plan()`'s ladder matches the Dart `ClientPlan` ranks; `clientPlanFromString` fails closed on unknown input; the capability matrix's tier boundaries; the two membership price-ID env vars are named identically in `create-checkout` and `update-subscription`.
- `K/CAPACITY` — the paywall's "Up to 25 / 100 / Unlimited clients" copy matches the webhook's `{starter:25, growth:100, elite:100000}` limits map.
- `K/SPLIT` — the Connect commission arithmetic replicated from `create-checkout` (the technique `edge_function_logic_test.dart` already uses): coach-invited is 0%, marketplace is the configured rate, `fee + payout == amount` across 8 amounts × 6 rates with no lost cents, the fee never exceeds the charge, the 10% default is the same in migration 038 and 039, and **K-14's rounding divergence is pinned explicitly** so fixing it is a deliberate act.
- `K/WEBHOOK` — the handler switches on exactly three events (widening is remediation, narrowing is a silent regression); the runbook subscribes those three; signature verification textually precedes the first database write.
- `K/IDENTITY` — migration 115 still pins all seven billing columns; `client_source` is still immutable; `subscriptions` still has no client write policy.

Open specs (`skip:`ped, each naming its finding — remove the `skip:` when the fix lands and it becomes the regression guard): K-01, K-02/K-06, K-03, K-04, K-05, K-07, K-09, K-12, K-ENV-1. They are skipped rather than failing so the suite stays green and the defect stays recorded here rather than hidden in a red build.

### 9.4 Tests that still cannot exist offline

Idempotency under real redelivery, ordering, Connect destination charges, dunning and refunds all need a Stripe **test-mode** account plus a QA project with its own secrets (K-ENV-2/3). The sequence to run once those exist is in §11.

---

## 10. Remediation order

Ordered by (financial exposure × ease of exploitation), with dependencies respected.

**Stage 0 — unblock QA (nothing else can be verified first)**
1. **K-ENV-1** — parameterise the three `qa_*`/`live_*` tools from env with no default plus a project-ref allowlist that refuses production. *(= REL-18. Until this lands, no dynamic billing QA is safe to run.)*
2. **K-ENV-3** — a QA Stripe runbook: QA project ref, test-mode price IDs, QA webhook endpoint and its own signing secret; `dart_defines/staging.json`.
3. **K-12** — declare `verify_jwt` per function in `config.toml`.

**Stage 1 — stop the revenue leaks (P0, all parallelizable)**
4. **K-03** — server-side plan checks on the four AI functions and inside `generate_client_plan()`.
5. **K-04** — split the `event_registrations` policy; pin `paid`/`payment_id`.
6. **K-01** — the processed-event store + an idempotent credit grant.
7. **K-05** + **K-25** — `book_coaching_session()` RPC consuming credits under a row lock; lock down the credit table's UPDATE.

**Stage 2 — stop the customer-facing money defects (P1)**
8. **K-07** — never mark cancelled locally when Stripe refused.
9. **K-08** — refuse duplicate checkouts; partial unique index; widen `update-subscription`'s status filter.
10. **K-02** — handle `invoice.paid` / `invoice.payment_failed`; `payments` becomes a real ledger.
11. **K-11** (needs **D-K3**) — grace window; align the UI's definition of "member".
12. **K-06** (needs **D-K4**) — refunds and disputes revoke.
13. **K-23**, **K-27** — ordering guard and dead-letter (land with K-01's store).

**Stage 3 — integrity and correctness (P1/P2)**
14. **K-09** (needs **D-K8**), **K-13**, **K-17**, **K-19** (needs K-02), **K-15**, **K-16** (rides REL-04), **K-18** + **K-20** (need **D-K7**), **K-22**, **K-24**, **K-14**, **K-21**, **K-26**.

**Stage 4 — release-surface decisions**
15. **D-K1** and its engineering consequence. This is weeks of work in option (a) and should not be started before Stages 1–2 close, because IAP adds a *second* entitlement source of truth on top of a webhook that is not yet idempotent.

**Stage 5 — hygiene**
16. K-28, K-29, K-30.

Parallelization: Stage 1's four items touch four disjoint files and can run as four concurrent workstreams. Stage 2 items 8–10 are independent of each other; 11–13 depend on 10 (or on its event store).

---

## 11. QA mutations and cleanup

**This session made no database mutation in any environment, and no Stripe API call in any mode.**

- No row was inserted, updated or deleted on QA `eyqtldjqpgpljlqvpowh` or anywhere else.
- No migration was created, applied, altered or reverted. Migrations 113–121 are untouched, as instructed.
- No Edge Function was deployed; no secret was set or read.
- No Stripe object (customer, session, subscription, account, webhook endpoint, price) was created, read or modified, in test mode or live mode. **No card was charged. No refund was issued. No test clock was advanced.**
- Files changed in the working tree: **two, both additive** — this report, and `apps/mobile/test/unit/billing_entitlement_contract_test.dart`. No existing file was edited, reset, stashed or reverted; all pre-existing uncommitted work is preserved.
- Nothing was committed.

**Cleanup required from this session: none.**

**Cleanup protocol for the dynamic runs that Stage 0 unblocks** (to be executed only against QA, only in Stripe test mode):
1. Seed identities via the QA-parameterised harness; record every created `auth.users` id, `stripe_customer_id`, `stripe_subscription_id`, `payments.id`, `client_session_credits.id`, `event_registrations.id`.
2. Use Stripe **test clocks** for renewal/dunning rather than waiting on real time, and delete the clock afterwards.
3. Tear down in FK order: `client_session_credits` → `event_registrations` → `payments` → `subscriptions` → `coach_client_relationships` → `user_profiles` → `auth.users`; then cancel and delete the test-mode Stripe customers and connected accounts.
4. Assert afterwards that `select count(*) from subscriptions where user_id in (<seeded ids>)` is 0 and that no Stripe test object with the run's metadata tag survives.
5. Assert, as Workstream D established for cron, that no request in the run targeted `nxdbooufqzkpslkcogxc`.

---

## 12. Production-contact statement

**Production Supabase project `nxdbooufqzkpslkcogxc` was not contacted at any point during this workstream.** No REST call, no RPC, no auth call, no Edge Function invocation, no migration, no dashboard action.

**No Stripe resource was contacted in any mode.** No live-mode key was read, used or handled. No test-mode key was available to this session and none was requested. No charge, refund, subscription, customer, connected account, webhook endpoint or price was created, modified or deleted. **No real card was charged and no real money moved.**

Every statement in this report about production behaviour is a derivation from repository source read this session, never a live observation. Where production or dashboard state is genuinely unknowable from the repository it is marked **UNVERIFIABLE FROM REPO** and expressed as a checklist item rather than a fact.

The one tool built for this audit — `tool/qa_entitlements.dart` — was **not executed**, because it is hardcoded to the production project and seeds subscription rows with a service-role key (K-ENV-1). That is recorded above as the workstream's primary environment blocker.
