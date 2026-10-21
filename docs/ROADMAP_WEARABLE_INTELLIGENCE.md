# ROADMAP — 12Circle Wearable Intelligence

**Status:** APPROVED — FUTURE BUILD  
**Implementation status:** NOT AUTHORIZED YET  
**Product:** 12Circle Fitness App  
**Initiative:** Wearable Intelligence  
**First platform:** Apple Watch / Apple HealthKit  
**Roadmap position:** Post core QA/remediation and release-readiness stabilization

---

## 1. Executive Summary

12Circle Wearable Intelligence is a future product initiative that turns wearable data into a real-time training intelligence layer.

The goal is not simply to connect an Apple Watch and display heart rate. The goal is for 12Circle to understand:

- what the member is supposed to be doing,
- how hard the member is actually working,
- whether observed intensity matches the intended workout,
- how the member responds over time,
- and how those observations can improve future coaching.

**Product principle:**

> 12Circle doesn't just track heart rate. It understands training intensity in context.

The initiative connects:

**Workout Prescription → Wearable Data → Real-Time Observation → Training Alignment → Historical Intelligence → Coaching Adaptation → AI Explanation**

The deterministic coaching system remains authoritative. AI does not independently determine heart-rate zones, training state, or safety-critical conclusions.

---

## 2. Strategic Product Role

Wearable Intelligence extends the product from:

> What did you do?

to:

> What did you do, how did your body respond, and was that response aligned with the training objective?

It strengthens the existing:

**PLAN → TRAIN → OBSERVE → UNDERSTAND → LEARN → ADAPT**

feedback loop.

Wearables primarily strengthen **OBSERVE** and **LEARN**, while eventually supplying governed evidence for **ADAPT**.

---

## 3. Product Differentiator

Most fitness applications can display heart rate.

12Circle should use heart rate as contextual training evidence.

The differentiator is:

> **Prescription-aware physiological intelligence.**

The system should understand the difference between strength, recovery, aerobic conditioning, interval training, HIIT, endurance, and other workout objectives.

A high heart rate is therefore not automatically "better."

The system asks:

> **Was the member's physiological intensity appropriate for what this workout was trying to accomplish?**

This is the foundation of Training Alignment.

---

# 4. Approved Ten-Wave Roadmap

| Wave | Capability | Outcome |
|---|---|---|
| **W1** | HealthKit integration + permissions | Establish Apple health-data connection |
| **W2** | Heart-rate ingestion | Bring heart-rate observations into 12Circle |
| **W3** | Live heart-rate display | Show current BPM during training |
| **W4** | Live zone calculation | Determine current training zone |
| **W5** | Workout-specific target zones | Compare actual intensity against workout intent |
| **W6** | Post-workout time-in-zone analytics | Understand completed training |
| **W7** | Training-alignment engine input | Feed wearable observations into deterministic coaching |
| **W8** | Apple Watch companion experience | Deliver real-time training information on the wrist |
| **W9** | Adaptive coaching | Use accumulated observations to influence future coaching |
| **W10** | Cross-platform Wearable Intelligence | Expand beyond Apple/HealthKit through a provider-independent layer |

---

# 5. W1 — HealthKit Foundation

## Objective

Establish a secure, explicit connection between 12Circle and Apple HealthKit.

## Requirements

12Circle must:

- request only required HealthKit permissions,
- explain why each permission is needed,
- distinguish read permissions from write permissions,
- handle denial and partial authorization,
- allow members to review/revisit connection state,
- never assume permission means data exists,
- identify source/provider where possible,
- fail clearly when wearable data is unavailable.

Heart rate is the first wearable signal.

Additional HealthKit signals require separate product/architecture approval.

---

# 6. W2 — Heart-Rate Ingestion

## Objective

Create the wearable data layer capable of receiving heart-rate observations.

A normalized observation should include, as applicable:

- timestamp,
- BPM,
- source,
- device,
- workout/session association,
- data quality/state,
- ingestion timestamp,
- provenance.

## Requirements

The ingestion layer must:

- preserve source data accurately,
- preserve timestamps,
- prevent duplicate observations,
- handle gaps and delayed observations,
- distinguish unavailable data from zero,
- preserve provenance,
- avoid treating stale observations as current.

## Architecture

```text
Raw Observation
      ↓
Normalization
      ↓
Derived Zone
      ↓
Training Observation
      ↓
Training Intelligence
```

Raw observations must remain distinguishable from derived intelligence.

---

# 7. W3 — Live Heart-Rate Display

## Objective

Make heart rate useful during an active workout.

Example:

```text
HEART RATE

142 BPM

Zone 3
Aerobic / Cardio Endurance
```

The live experience should:

- display current BPM,
- indicate data freshness,
- show current zone when calculable,
- distinguish unavailable/stale readings,
- never block a workout when wearable data disappears,
- avoid excessive battery/network use,
- remain readable during training.

The current Heart Rate Zones screen becomes the conceptual foundation, but the future implementation should be a reusable **Live Training Intelligence** component rather than a static educational screen.

---

# 8. W4 — Live Heart-Rate Zone Calculation

## Objective

Translate current heart rate into an active training zone.

The current screen presents five zones:

- Zone 1 — 50–60% Max HR
- Zone 2 — 60–70% Max HR
- Zone 3 — 70–80% Max HR
- Zone 4 — 80–90% Max HR
- Zone 5 — 90–100% Max HR

It currently references:

> 220 − your age

## Architectural requirement

The `220 − age` calculation must not become an irreversible architectural assumption.

Future zone configuration must support an explicit source, potentially including:

1. 12Circle default zones,
2. user-configured zones,
3. coach-defined zones,
4. workout-specific zones,
5. supported platform/device-derived configuration where appropriate.

The system must know which configuration produced a zone.

A future zone configuration should represent:

- zone number,
- lower boundary,
- upper boundary,
- calculation/source method,
- effective date/time,
- applicable user/workout context.

---

# 9. W5 — Workout-Specific Target Zones

## Objective

Make heart-rate zones contextual to the workout.

Examples:

```text
RECOVERY SESSION
Target: Zone 1–2
```

```text
AEROBIC CONDITIONING
Target: Zone 2–3
```

```text
INTERVAL SESSION
Work: Zone 4–5
Recovery: Zone 1–2
```

Core principle:

> **Actual intensity is evaluated against intended intensity.**

12Circle must not reward higher heart rate indiscriminately.

---

# 10. W6 — Post-Workout Time-in-Zone Analytics

## Objective

Turn the physiological stream into useful post-workout information.

Example:

```text
TRAINING REPORT

42:18
Workout Duration

137 BPM
Average Heart Rate

171 BPM
Peak Heart Rate
```

### Time in Zones

```text
Zone 1    04:21
Zone 2    15:43
Zone 3    16:11
Zone 4    05:32
Zone 5    00:31
```

Future Training Alignment:

```text
TRAINING ALIGNMENT

87%

Your intensity was closely aligned
with today's planned session.
```

The exact scoring algorithm requires a future product/architecture decision.

Analytics must preserve:

- workout context,
- target context,
- observed zones,
- time in zone,
- average HR,
- peak HR,
- data completeness,
- provenance.

Incomplete wearable data must not be presented as complete.

---

# 11. W7 — Training-Alignment Engine Input

## Objective

Connect wearable observations to the deterministic 12Circle coaching system.

```text
Workout Prescription
        ↓
Wearable Observations
        ↓
Heart Rate / Zone Service
        ↓
Training Observation Layer
        ↓
Deterministic Coaching Engine
        ↓
Decision Trace
        ↓
AI Explanation Layer
        ↓
Member / Coach Experience
```

The deterministic engine remains authoritative for:

- configured zone interpretation,
- defined training rules,
- structured training observations,
- governed coaching decisions.

AI should explain and contextualize approved outputs rather than silently replacing deterministic rules.

Any wearable-derived coaching decision should eventually be traceable to:

- workout,
- prescription,
- wearable observation,
- zone configuration,
- derived metric,
- rule/version,
- decision,
- explanation.

---

# 12. W8 — Apple Watch Companion Experience

## Objective

Move important live training information onto the wrist.

Example:

```text
142 BPM

ZONE 3

TARGET
Zone 2–3

04:32
```

It may eventually also surface:

```text
NEXT SET

Bench Press
60 kg × 10

REST
00:42
```

The exact Watch scope requires a dedicated product/design phase.

Principle:

> The Watch should reduce the need to look at the phone during training.

---

# 13. W9 — Adaptive Coaching

## Objective

Use accumulated wearable observations to improve future training decisions.

Potential patterns:

- consistently exceeding intended intensity,
- consistently failing to reach intended intensity,
- unusually high physiological response,
- unusual recovery response,
- recurring mismatch between prescription and observed effort.

These observations may become inputs to future coaching decisions.

### Safety boundary

Adaptive coaching must not infer medical diagnoses from wearable data.

Features involving medical alerts, clinical thresholds, disease detection, emergency intervention, or treatment recommendations require a separate product/clinical/legal/compliance decision.

---

# 14. W10 — Cross-Platform Wearable Intelligence

Apple Watch/HealthKit is the first implementation.

The architecture should eventually support additional providers through an abstraction layer.

```text
              Wearable Intelligence
                       │
        ┌──────────────┼──────────────┐
        ↓              ↓              ↓
    Apple/HealthKit  Health Connect  Other
        │              │              │
        └──────────────┼──────────────┘
                       ↓
              12Circle Data Layer
                       ↓
              Training Intelligence
```

Provider-specific logic should terminate at the wearable data boundary rather than leak throughout the application.

---

# 15. Live Training Intelligence Component

The current Heart Rate Zones screen should evolve into a reusable product component.

Concept:

```text
┌──────────────────────────────┐
│ ❤️ HEART RATE                │
│                              │
│          142 BPM             │
│                              │
│          ZONE 3              │
│   Aerobic / Cardio Endurance │
│                              │
│ Target: Zone 2–3             │
│ ██████████████░░             │
│                              │
│ 04:32 in current zone        │
└──────────────────────────────┘
```

Potential placements:

- active workout,
- workout summary,
- Activity,
- Home,
- training analytics,
- Watch.

The underlying intelligence should be shared rather than duplicated between screens.

---

# 16. Home Experience

When a wearable is connected and a workout is active, Home may expose a compact live state:

```text
LIVE TRAINING

142 BPM
Zone 3

Target Zone 2–3

View Workout →
```

Outside an active workout, Home should favor meaningful summaries instead of constantly displaying raw BPM.

The Home screen should not become a health-monitor dashboard.

---

# 17. Activity Experience

Activity may eventually expose:

- workout heart-rate summary,
- time in zone,
- average HR,
- peak HR,
- Training Alignment,
- historical trends,
- relationship between prescription and observed intensity.

The experience should emphasize interpretation over raw data volume.

---

# 18. Coach Experience

Future coach surfaces may show:

- whether a client is following intended intensity,
- recurring intensity patterns,
- Training Alignment,
- trends across workouts,
- meaningful deviations.

Coach visibility must follow existing 12Circle authorization boundaries.

Wearable data must never become a mechanism for bypassing the existing coach/client privacy model.

---

# 19. 12Circle Score Integration

Wearable data may eventually contribute to the 12Circle Score.

However:

> **The score must not simply reward higher intensity.**

The preferred future concept is **Training Alignment**: whether the member trained according to the intended prescription.

Exact scoring rules require future product definition.

---

# 20. Privacy and Data Governance

Wearable data is sensitive personal data.

The architecture must preserve:

- explicit permission,
- source provenance,
- least-privilege access,
- user ownership,
- coach authorization boundaries,
- auditability,
- deletion behavior,
- permission revocation behavior,
- data minimization.

No wearable signal should become coach-visible merely because it exists.

Existing authorization boundaries remain authoritative.

---

# 21. AI Integration Rules

AI may eventually use wearable-derived observations for:

- explanations,
- summaries,
- coaching context,
- pattern descriptions,
- approved recommendations.

AI must not:

- invent missing readings,
- interpret missing data as zero,
- override deterministic zone calculations,
- make unsupported medical claims,
- silently change safety constraints,
- access wearable data outside the authorized context.

Wearable-derived AI decisions must retain provenance.

---

# 22. Data Quality Requirements

Wearable data is inherently imperfect.

The system must account for:

- missing readings,
- delayed readings,
- duplicate readings,
- stale readings,
- device disconnection,
- permission changes,
- device battery limitations,
- workout/session mismatch,
- source changes,
- incomplete workout windows.

Core rule:

> **Missing physiological data is missing data, not zero physiological effort.**

---

# 23. Non-Goals

This roadmap does not authorize:

- medical diagnosis,
- emergency response,
- disease detection,
- automatic medical advice,
- replacing a physician,
- unrestricted HealthKit access,
- collecting every available wearable signal,
- automatically changing workouts based solely on heart rate,
- rewarding maximum heart rate,
- building a standalone wearable device.

---

# 24. Dependencies

Wearable Intelligence depends on core 12Circle stability.

### Upstream foundations

- Core QA/remediation complete
- Workout domain contract stable
- Security boundaries stable
- Error-handling contract stable
- Deterministic engine contract stable
- App environment separation stable
- Release architecture established
- Manual QA completed
- Production readiness established

### Future technical dependencies

- Apple Developer configuration
- HealthKit entitlement/configuration
- iOS native build pipeline
- Apple Watch target
- appropriate device testing
- privacy disclosures
- data permission UX
- telemetry/observability
- release CI/CD

---

# 25. Future Epic Structure

When implementation is authorized:

- **WI-01 — HealthKit Foundation**
- **WI-02 — Wearable Data Layer**
- **WI-03 — Heart Rate Intelligence**
- **WI-04 — Live Training**
- **WI-05 — Training Alignment**
- **WI-06 — Post-Workout Intelligence**
- **WI-07 — Coaching Intelligence**
- **WI-08 — Apple Watch**
- **WI-09 — Adaptive Training**
- **WI-10 — Multi-Provider Wearables**

Each epic requires its own implementation plan, security review, QA strategy, and acceptance criteria before code changes.

---

# 26. Definition of Done

The initiative is not complete merely because an Apple Watch can send heart rate.

It is mature when 12Circle can:

1. securely connect an authorized wearable,
2. ingest trustworthy heart-rate observations,
3. display current heart rate during training,
4. determine the correct configured zone,
5. understand intended workout intensity,
6. compare observed intensity against intended intensity,
7. summarize the completed session,
8. preserve evidence behind derived intelligence,
9. provide useful member feedback,
10. provide appropriately authorized coach insight,
11. integrate approved observations into deterministic coaching,
12. use AI only within governed boundaries,
13. support an Apple Watch experience,
14. preserve privacy and authorization,
15. handle missing/stale data safely,
16. remain extensible to additional wearable providers.

---

# 27. Reserved Product Decisions

This roadmap intentionally does not decide:

- exact heart-rate zone methodology,
- manual zone overrides,
- coach zone configuration,
- Training Alignment formula,
- exact 12Circle Score contribution,
- adaptive-training rules,
- additional HealthKit signals,
- Apple Watch scope beyond the initial heart-rate experience,
- cross-platform provider priority,
- medical/clinical thresholds,
- emergency-alert behavior,
- retention duration for raw wearable observations.

These are future authority decisions.

---

# 28. Execution Rule

This roadmap is **approved but not currently authorized for implementation**.

Current execution remains:

```text
DISCOVER
   ↓
RECONCILE
   ↓
REMEDIATE
   ↓
RETEST
   ↓
DISCOVER AGAIN
   ↓
REMEDIATE AGAIN
   ↓
RETEST AGAIN
   ↓
MANUAL QA
   ↓
RELEASE READINESS
   ↓
UI/UX UPDATE
   ↓
APP STORE / LAUNCH
```

Wearable Intelligence enters active implementation only after its upstream dependencies are sufficiently stable.

---

# 29. Current Status

**APPROVED — FUTURE BUILD**

**Implementation:** NOT AUTHORIZED YET

**First target:** Apple Watch + HealthKit

**Strategic role:** Core 12Circle Training Intelligence

**Differentiator:** Prescription-aware physiological intelligence

**Immediate action:** Preserve roadmap; continue current QA/remediation program.

---

## Governing Principle

> **12Circle should not merely tell a member what their heart rate is. It should help them understand whether their body is responding to the training they were actually prescribed.**
