# 12CIRCLE AI MONETIZATION & UNIT ECONOMICS ROADMAP

**Status:** Approved roadmap direction  
**Owner:** Chief / Lead Architect  
**Product:** 12Circle Fitness App + 12Circle Fitness Operating Platform  
**Purpose:** Ensure 12Circle's AI-powered products are commercially sustainable and do not operate at a loss as AI usage scales.

---

## 1. Executive Objective

12Circle will be designed so that AI creates meaningful product value without creating uncontrolled operating costs.

The core commercial principle is:

> **AI should be invoked when AI adds value, and every AI-powered feature must have an economically sustainable operating model.**

The product will not rely on unlimited unbounded AI inference.

12Circle will combine:
- deterministic fitness logic,
- governed AI reasoning,
- model routing,
- usage controls,
- caching,
- cost observability,
- subscription revenue,
- professional/coach revenue,
- and future B2B platform revenue.

---

# 2. Commercial Architecture

The commercial ecosystem will contain four primary revenue layers.

## 2.1 Free

**Purpose:** acquisition and conversion.

Potential capabilities:
- basic profile
- basic workout/tracking
- limited progress
- basic community access
- educational content
- limited AI trial

The free tier should provide genuine value while creating a natural reason to upgrade.

---

## 2.2 12Circle AI

**Initial pricing hypothesis:** approximately **$19.99/month** or **$149.99/year**.

This is a hypothesis for economic modeling and testing, not a final locked price.

Potential capabilities:
- personalized workouts
- progressive programming
- workout tracking
- exercise substitutions
- nutrition tracking
- meal analysis
- AI coaching
- weekly insights
- progress analysis
- personalized recommendations
- future Wearable Intelligence

AI usage should be governed by plan allowances and/or economically controlled capacity.

---

## 2.3 12Circle Coach

**Initial pricing hypothesis:** approximately **$49–$99/month**, subject to final unit-economics analysis.

Potential capabilities:
- client management
- programming
- AI-assisted programming
- client insights
- check-in management
- communication
- progress dashboards
- business analytics
- AI administrative assistance

---

## 2.4 12Circle Fitness Operating Platform

Future B2B SaaS offering for:
- gyms
- coaches
- fitness businesses
- organizations
- potentially multi-location operators

Potential pricing models:
- organization subscription
- active-member pricing
- coach/seat pricing
- module pricing
- AI usage pricing
- enterprise/custom contracts

Illustrative future tiers may begin around:
- $99/month
- $249/month
- $499+/month
- Enterprise/custom

These are planning hypotheses only.

---

# 3. Core AI Economics Principle

12Circle must never assume that:

> subscription revenue > AI cost

is sufficient.

True contribution economics must account for:

- AI inference
- database
- storage
- edge functions
- API infrastructure
- email/notifications
- analytics
- payment processing
- App Store/platform fees
- monitoring
- support
- other variable infrastructure costs

### Required metric

**Contribution Margin = Revenue − Variable Cost to Serve**

The business should establish a healthy target contribution margin before launch.

---

# 4. AI Usage Architecture

## 4.1 AI Cost Classification

Every AI operation should have an internal cost class.

| Class | Examples |
|---|---|
| Low | simple coaching explanation |
| Medium | meal analysis, workout generation |
| High | complex plan generation |
| Very High | deep personalized analysis, intensive vision/context workloads |

The exact classification will be validated through real usage measurements.

---

# 5. AI Usage Controls

12Circle will not offer unrestricted expensive AI usage.

Potential controls include:

- monthly AI allowances
- operation-specific allowances
- advanced-generation limits
- vision/image-analysis limits
- deep-analysis limits
- fair-use controls
- controlled overage/AI capacity purchases
- abuse/rate protection

The user experience should remain simple. Users should see useful capacity information rather than raw token economics.

---

# 6. AI Usage Wallet

The platform should maintain an internal AI usage ledger/wallet.

Conceptual data:

```text
user_id
subscription_tier
monthly_ai_budget
usage
estimated_cost
actual_cost
remaining_budget
overage_policy
period_start
period_end
```

This is an internal economic-control mechanism.

The user-facing UI may eventually expose simplified usage/capacity information.

---

# 7. AI Cost Ledger

Every AI request should be observable.

Conceptual record:

```text
AI_REQUEST

user_id
feature
operation
model
input_tokens
output_tokens
estimated_cost
actual_cost
latency
success
cache_hit
request_timestamp
```

This allows the business to answer:

- What does the average member cost?
- Which AI features are most expensive?
- Which subscription tiers are profitable?
- Which users have unusually high usage?
- Which models provide the best value?
- Where should inference be optimized?

---

# 8. Model Routing

12Circle should not automatically send every request to the most expensive model.

Future architecture:

```text
Request
   ↓
AI Model Router
   ↓
Can deterministic logic answer?
   ├── YES → deterministic system
   └── NO
        ↓
Does AI materially add value?
   ├── NO → deterministic/system response
   └── YES
        ↓
Select appropriate model
```

Potential routing:

- inexpensive model → simple tasks
- standard model → normal coaching
- advanced model → complex programming/reasoning
- vision model → meal/image analysis
- premium reasoning model → genuinely complex analysis

Model selection should remain abstracted from the user.

---

# 9. Deterministic Engine + AI Architecture

The deterministic engine is a major economic advantage.

12Circle should prefer:

**Deterministic Engine → AI Explanation/Enhancement**

over:

**AI → decides everything**

Examples:
- deterministic system calculates adherence
- AI explains the adherence trend
- deterministic engine determines training constraints
- AI explains the recommendation
- deterministic system calculates heart-rate zone
- AI interprets meaningful patterns when appropriate

This reduces unnecessary model calls and improves reliability.

---

# 10. AI Caching

The platform should identify responses that can be safely cached.

Potential candidates:
- general exercise education
- generic nutrition education
- zone explanations
- common coaching concepts
- non-personalized educational content

Personalized health/training outputs must remain appropriately personalized and governed.

---

# 11. Subscription Economics

Before launch, establish for each tier:

### Revenue
- monthly price
- annual price
- expected discount
- payment/platform fees

### Variable costs
- average AI cost/member
- infrastructure/member
- storage/member
- messaging/email/member
- analytics/monitoring/member
- other variable costs

### Business metrics
- contribution margin
- gross margin
- churn
- customer acquisition cost
- lifetime value
- LTV:CAC
- break-even member count

---

# 12. Usage Scenarios

The economics model must test at least:

### Low-use member
Few AI interactions.

### Average member
Normal workout, nutrition, and coaching usage.

### High-use member
Frequent coaching and analysis.

### Heavy AI member
High-volume generation and vision usage.

### Abuse scenario
Unusually high or automated AI consumption.

The system must remain economically protected in every scenario.

---

# 13. Pricing Experiments

Pricing should be treated as an evidence-driven product system.

Potential experiments:
- monthly vs annual
- $19.99 vs alternative price points
- different trial lengths
- AI allowance levels
- bundled vs separate AI capacity
- consumer vs coach tiers
- B2B active-member pricing
- seat-based vs organization pricing

No final pricing decision should be made solely from competitor pricing.

---

# 14. Wearable Intelligence Economics

Wearable Intelligence must be incorporated into unit economics before launch.

Potential variable costs include:
- additional data processing
- storage
- analytics
- synchronization
- notifications
- AI interpretation
- increased engagement/usage

The feature should create enough retention/value to justify its operating cost.

The existing Heart Rate Zones UI remains deferred until the Wearable Intelligence implementation is ready.

---

# 15. B2B Economics

For the 12Circle Fitness Operating Platform, model:

- revenue per organization
- revenue per active member
- revenue per coach
- AI cost per active member
- infrastructure cost per organization
- onboarding cost
- support cost
- retention
- expansion revenue
- enterprise usage

B2B contracts may include usage-based AI economics where appropriate.

---

# 16. Abuse and Cost Protection

The system should detect:
- abnormal AI request volume
- repeated expensive generations
- automated request patterns
- excessive image analysis
- suspicious account behavior
- unusually high cost/member

Controls may include:
- rate limits
- usage caps
- temporary throttling
- step-up confirmation
- plan upgrades
- controlled overage
- abuse prevention

---

# 17. Roadmap

## Wave 0 — Economic Baseline

Establish:
- AI provider/model cost table
- infrastructure cost table
- payment/App Store fee assumptions
- initial contribution-margin target
- cost-per-operation estimates

**Gate:** We can estimate the cost of serving one member.

---

## Wave 1 — AI Cost Instrumentation

Build:
- AI request ledger
- token/cost tracking
- feature attribution
- latency tracking
- success/failure tracking
- model tracking

**Gate:** Every AI operation has measurable economics.

---

## Wave 2 — AI Cost Dashboard

Build internal reporting for:
- cost/member
- cost/feature
- cost/model
- daily/monthly AI spend
- high-cost users
- subscription-tier profitability

**Gate:** Business can see where money is being spent.

---

## Wave 3 — Model Routing

Implement:
- task classification
- model selection
- fallback strategy
- cost-aware routing

**Gate:** Expensive models are used only where justified.

---

## Wave 4 — Usage Governance

Implement:
- subscription allowances
- operation limits
- fair-use controls
- rate limiting
- abuse detection
- controlled overage strategy

**Gate:** No individual member can create uncontrolled AI liability.

---

## Wave 5 — Caching & Optimization

Implement:
- safe response caching
- reusable educational responses
- context optimization
- prompt optimization
- token minimization
- redundant-call elimination

**Gate:** AI cost per useful outcome decreases.

---

## Wave 6 — Consumer Pricing

Finalize:
- Free
- 12Circle AI
- annual plan
- trial
- AI allowances
- overage/capacity policy

**Gate:** Pricing produces acceptable contribution economics under realistic usage.

---

## Wave 7 — Coach Economics

Finalize:
- Coach tier
- client limits
- AI allowances
- professional workflows
- pricing

**Gate:** Coach product is profitable at target usage.

---

## Wave 8 — B2B Platform Economics

Finalize:
- Starter
- Growth
- Professional
- Enterprise
- active-member pricing
- seat pricing
- AI usage economics

**Gate:** Platform economics support profitable organizational growth.

---

## Wave 9 — Launch Economics Validation

Before public launch:
- load test
- AI cost simulation
- low/average/high-use scenarios
- abuse simulation
- churn modeling
- CAC/LTV modeling
- break-even analysis

**Gate:** Launch only when the business model is economically defensible.

---

# 18. Required Launch Metrics

At minimum:

### Acquisition
- CAC
- conversion rate
- trial conversion

### Revenue
- MRR
- ARR
- ARPU
- revenue/member

### Retention
- monthly churn
- annual retention
- cohort retention

### AI economics
- AI cost/member
- AI cost/feature
- AI cost/revenue
- AI requests/member
- average inference cost
- high-cost member percentage

### Profitability
- contribution margin
- gross margin
- LTV
- LTV:CAC
- break-even members

---

# 19. Architectural Rules

These are binding design principles.

### Rule 1
**No unlimited unbounded expensive AI.**

### Rule 2
**Every AI feature must have measurable cost attribution.**

### Rule 3
**Use deterministic logic whenever it can reliably answer the problem.**

### Rule 4
**Use the least expensive model capable of meeting the required quality.**

### Rule 5
**AI cost must be visible internally even when it is invisible to users.**

### Rule 6
**Pricing decisions require unit-economic evidence.**

### Rule 7
**AI features cannot launch without a defined cost envelope.**

### Rule 8
**Wearable Intelligence must be evaluated for both user value and incremental operating cost.**

### Rule 9
**B2C and B2B economics must be modeled separately.**

### Rule 10
**The platform must protect the business from abnormal AI consumption.**

---

# 20. Definition of Done

The monetization/economics program is complete when:

- AI operations are cost-instrumented
- model usage is measurable
- infrastructure cost is measurable
- subscription economics are modeled
- AI usage allowances are defined
- model routing exists
- cost protections exist
- pricing is validated
- annual/monthly economics are understood
- B2B economics are modeled
- CAC/LTV assumptions exist
- break-even point is known
- high-usage scenarios remain profitable
- launch has a defined contribution-margin target

---

# 21. Strategic Principle

12Circle's competitive advantage is **not simply access to an AI model**.

The product differentiator is the combination of:

**Fitness data + deterministic training intelligence + governed AI + personalization + nutrition + check-ins + wearable intelligence + coaching workflows + long-term member context.**

AI should make the system more valuable.

It should never make the company structurally unprofitable.

---

## Status

**APPROVED FOR ROADMAP**

This roadmap is now a standing commercial/architecture workstream alongside:
- App Store readiness
- Wearable Intelligence
- QA remediation
- AI engine development
- 12Circle Fitness Operating Platform
- final UI/UX modernization

Final pricing remains intentionally open until real AI and infrastructure cost measurements are available.
