# 12Circle Specialist Training Agent Roadmap

## Status
**Approved roadmap addition — Future Product / AI Architecture**

## Purpose
12Circle will evolve from a single Personal Fitness AI Coach into a governed **Agentic Fitness Coaching System**. The Personal Fitness AI Coach remains the member-facing primary coach and orchestrator. Specialized training agents provide deep expertise in individual training modalities while operating under shared member context, safety governance, entitlement controls, and the deterministic training engine.

## Architectural Principle
Specialist agents are **governed specialist capabilities**, not independent autonomous coaches. The Personal Fitness AI Coach owns the member relationship and coordinates specialist expertise.

No specialist agent may bypass:
- safety constraints
- authorization
- member-data permissions
- entitlement rules
- deterministic workout contracts
- exercise identity rules
- prescription contracts
- auditability
- human-control boundaries

## Personal Fitness AI Coach
The Personal Fitness AI Coach understands the member as a whole: goals, training history, schedule, preferences, fitness level, equipment, adherence, recovery, nutrition, injuries and contraindications, PAR-Q risk, applicable women's-health constraints, wearable data, and progress. It determines when specialist expertise should be invoked.

## Initial Specialist Agent Roadmap

### 1. Strength Coach Agent
Strength, hypertrophy, progressive overload, resistance training, exercise selection, volume, intensity, RIR/RPE, and progression.

### 2. Pilates Coach Agent
Pilates programming, core control, stability, mobility, posture, movement quality, and progression.

### 3. Yoga Coach Agent
Yoga sequences, flexibility, mobility, balance, breathwork, recovery, and mind-body sessions.

### 4. Conditioning Coach Agent
Running, intervals, aerobic conditioning, threshold work, HIIT, HYROX, and endurance.

### 5. Functional Training Agent
Movement patterns, unilateral work, stability, coordination, functional strength, and athletic movement.

### 6. Mobility / Recovery Agent
Recovery sessions, mobility, stretching, low-intensity movement, and recovery-day recommendations.

## Future Specialist Agents
Potential future specialists include HYROX, Running, Athletic Performance, Women's Wellness, Senior Fitness, appropriately governed Prenatal/Postpartum, and rehabilitation-adjacent programming within a clearly defined non-clinical scope.

## Wearable Intelligence Integration
The Specialist Agent architecture should integrate with the approved Wearable Intelligence roadmap.

Wearable → heart-rate stream → 12Circle Wearable Intelligence → current HR zone + training context → Personal Fitness AI Coach → relevant Specialist Agent → Deterministic Training Engine → adaptive guidance.

The system can eventually interpret heart rate in context rather than merely display a number, subject to deterministic training and safety rules.

## Agent Governance

### Shared Member Context
One authoritative member context rather than independent agent-specific profiles.

### Shared Safety Layer
Safety constraints are enforced centrally.

### Shared Deterministic Engine
AI proposes or reasons; the deterministic system remains authoritative for enforceable workout contracts.

### Shared Audit Trail
Specialist recommendations and material decisions are attributable and auditable.

### Shared Entitlement System
Specialist AI usage respects subscription and consumption limits.

### Shared Human Control
Coaches and authorized humans remain able to review, approve, override, or constrain agent behavior where governance requires it.

## Agent Invocation Model
A future request can flow through:

Member request → Personal Fitness AI Coach → required specialist capabilities → Safety/Governance → Deterministic Training Engine → validated workout.

The member should experience one coherent coach rather than multiple disconnected bots.

## Example
For a member with limited time and a sensitive knee, the Personal Coach can evaluate goals, time, recovery, constraints, equipment, and preferences; consult Strength, Pilates, and Mobility/Recovery capabilities as appropriate; pass the result through safety governance; and have the deterministic engine validate the final prescription.

## Monetization Implication
Specialist agents strengthen the value proposition of paid 12Circle tiers:

- Personal AI Coach
- Strength Intelligence
- Pilates Intelligence
- Yoga Intelligence
- Recovery Intelligence
- Nutrition Intelligence
- Wearable Intelligence
- Adaptive Programming

Do not require an expensive model call from every specialist for every interaction. Use deterministic logic and routing where possible and invoke model reasoning when it provides meaningful value. AI operating costs must remain below subscription revenue.

## Implementation Phasing

### Phase 1 — Architecture
Add specialist-agent concepts to the AI architecture without implementing every specialist. Ensure the Personal Coach can eventually route to specialist capabilities.

### Phase 2 — Initial Specialists
Prioritize Strength, Pilates, Yoga, Mobility/Recovery, and Conditioning.

### Phase 3 — Advanced Specialization
Evaluate HYROX, Running, Athletic Performance, Women's Wellness, Senior Fitness, and appropriately governed prenatal/postpartum capabilities.

### Phase 4 — Wearable Intelligence
Connect specialist recommendations to heart-rate zones, workout intensity, recovery signals, and wearable-derived training context.

### Phase 5 — Adaptive Multi-Agent Coaching
Allow the Personal Coach to dynamically combine specialist capabilities while maintaining one member experience and one governed decision chain.

## Current Priority
**Roadmap only.** Do not begin implementation until the current QA remediation program reaches the appropriate architecture/AI gate.

The immediate priority remains:

**Discover → Remediate → Retest → Manual QA → UI transformation**

The specialist-agent architecture should be incorporated into future AI implementation planning rather than interrupting the current remediation program.

## Success Criteria
1. Personal Fitness AI Coach remains the primary member-facing coach.
2. Specialist expertise can be invoked when appropriate.
3. Specialists share authoritative member context.
4. Safety governance cannot be bypassed.
5. Deterministic workout contracts remain authoritative.
6. Specialist outputs are auditable.
7. Paid AI usage is entitlement-controlled.
8. Model usage is economically sustainable.
9. Wearable intelligence can provide relevant training context.
10. The member experiences one coherent coaching relationship rather than disconnected bots.
