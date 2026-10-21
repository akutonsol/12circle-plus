# 12Circle Cowork File Ownership

## Purpose

This document defines default ownership boundaries for the 12Circle multi-agent Cowork workspace.

Ownership exists to prevent concurrent agents from overwriting one another and to make task responsibility explicit.

**Task-specific assignment always overrides default ownership.**

An agent must not modify a file outside its assigned boundary unless the orchestrator explicitly authorizes it.

## 1. Authority Hierarchy

File ownership follows:

1. Explicit current task assignment
2. Active orchestrator decision
3. This default ownership map
4. General repository conventions

When two tasks claim the same file, the orchestrator must resolve ownership before either agent writes to the shared file.

## 2. Core Ownership Domains

| Domain | Default Owner | Primary Scope |
|---|---|---|
| Architecture / Governance | ARCH | `docs/COWORK_*`, architecture records, wave coordination |
| Security | SEC | RLS, grants, authorization, security guards |
| Database / Schema | DB | `supabase/migrations`, schema contracts, database tests |
| Environment / Release | ENV | `.github/`, environment config, release configuration, deployment safety |
| Error Contract | ERR | service/provider error propagation and error-state behavior |
| AI / Engine | AI | Edge Functions, AI engine contracts, decision integrity |
| Billing | BILL | Stripe, subscriptions, entitlements, payment flows |
| Product Journey | JOURNEY | user-facing feature flows, route reachability, surface integration |
| Verification / QA | QA | test orchestration, regression verification, evidence |
| UI / Design | UI | visual system and UI transformation — future phase |

## 3. Documentation

### Default ARCH ownership

```text
docs/COWORK_ENGINEERING_GOVERNANCE.md
docs/COWORK_FILE_OWNERSHIP.md
docs/COWORK_AGENT_REGISTRY.md
docs/cowork/**
docs/MASTER_QA_RECONCILIATION.md
docs/REMEDIATION_EXECUTION_PLAN.md
docs/decision-log.md
```

Agents may contribute evidence to architecture documents only when authorized by the orchestrator.

Do not rewrite historical reports to make current results look cleaner.

## 4. Supabase Migrations

### Default DB / Security ownership

```text
supabase/migrations/**
```

Migrations are a high-conflict area.

No agent may modify a migration merely because it encounters an adjacent defect.

Before changing a migration:

- inspect relevant prior migrations;
- identify security properties;
- identify whether the object was replaced;
- inspect migration history;
- identify production-forward implications.

Security-sensitive migrations require SEC review.

Database migrations affecting application contracts require DB ownership.

## 5. Supabase Edge Functions

### Default AI / Backend ownership

```text
supabase/functions/**
```

Security-sensitive function changes require SEC review.

AI behavior changes require AI ownership.

Billing-related functions require BILL ownership.

A function may therefore have a **primary owner** plus a required reviewer.

## 6. Mobile Application

### Core configuration

Default ENV ownership:

```text
apps/mobile/lib/core/config/**
```

### Workout

Default ERR / Workout ownership:

```text
apps/mobile/lib/features/workout/**
```

Workout contract changes must respect the Phase 2 workout domain contract.

### Billing

Default BILL ownership:

```text
apps/mobile/lib/features/billing/**
```

### AI / coaching

Default AI ownership:

```text
apps/mobile/lib/features/ai/**
apps/mobile/lib/features/coaching/**
```

Where exact directories differ from the current repository, the orchestrator must use the actual repository structure rather than inventing paths.

### Product journeys

Default JOURNEY ownership:

```text
apps/mobile/lib/features/**/presentation/**
apps/mobile/lib/features/**/providers/**
apps/mobile/lib/features/**/services/**
```

This is a default only. A task assignment can narrow ownership to exact files.

## 7. Mobile Tests

### Default QA ownership

```text
apps/mobile/test/**
```

Agents may add task-specific regression tests.

Tests that assert security invariants require SEC review.

Tests that encode database contracts require DB review.

Do not delete or weaken tests belonging to another task.

## 8. API

### Default backend/API ownership

```text
apps/api/**
```

API changes affecting:

- security → SEC review
- billing → BILL review
- AI → AI review
- environment/release → ENV review

## 9. Supabase Tests

Default ownership is split by test domain:

```text
supabase/tests/security/**
    SEC

supabase/tests/ai/**
    AI + SEC where authorization is involved

supabase/tests/workout/**
    DB + Workout

supabase/tests/**
    QA for cross-domain orchestration
```

A test suite's ownership does not grant permission to modify production-facing implementation without the relevant implementation owner.

## 10. CI / Release Configuration

Default ENV ownership:

```text
.github/**
config.toml
deployment configuration
release configuration
environment manifests
```

Any change that could alter a production target requires explicit review.

## 11. Seeds and Fixtures

Default DB / QA ownership:

```text
supabase/seed.sql
supabase/seeds/**
QA fixture definitions
```

Seed changes must explicitly identify:

- target environment;
- credentials introduced;
- whether fixtures can be safely published;
- whether a seed can accidentally target production.

No seed may contain production secrets.

## 12. Tooling / QA Harnesses

Default QA / ENV ownership:

```text
tool/**
integration_test/**
```

Because prior audits found production-targeting QA harnesses, these files are considered **high-risk**.

Before executing a harness:

- inspect its target resolution;
- verify project/ref;
- inspect whether it uses service-role credentials;
- inspect whether it performs writes/deletes;
- confirm the environment.

Never execute an unfamiliar `qa_*` or `live_*` harness solely based on its filename.

## 13. Shared High-Conflict Files

The following require explicit orchestrator coordination before modification:

```text
package.json
pubspec.yaml
pubspec.lock
supabase/config.toml
known-violations.json
docs/decision-log.md
docs/MASTER_QA_RECONCILIATION.md
.github/**
supabase/migrations/**
apps/mobile/lib/core/**
apps/mobile/test/unit/phase1_security_boundary_test.dart
```

If a task needs one of these files, the task must identify itself as the owner before writing.

## 14. Known Violations / Allowlist Files

Files such as:

```text
known-violations.json
```

are treated as shared governance state.

Do not delete a violation from an allowlist merely to make a guard pass.

The underlying defect must be remediated first.

Then the allowlist entry may be removed as part of the same controlled task.

## 15. Lock / Coordination Protocol

For high-conflict files, agents should record active ownership under:

```text
docs/cowork/locks/
```

Suggested format:

```text
TASK: W1-TX
AGENT: SEC
FILES:
  supabase/migrations/123_*.sql
STATUS:
  ACTIVE
STARTED:
  YYYY-MM-DD
```

An agent encountering an active lock must not overwrite the file.

It should notify the orchestrator.

Locks are coordination records, not substitutes for version control.

## 16. Concurrent Work Protocol

If another agent modifies a file after your baseline:

1. stop;
2. inspect the diff;
3. identify ownership;
4. determine whether the changes are compatible;
5. coordinate through the orchestrator;
6. continue only after ownership is clear.

Never use a broad formatting pass or generated rewrite that could erase another agent's changes.

## 17. Task Handoff

When ownership moves between agents, the outgoing agent must provide:

- current state;
- changed files;
- tests;
- unresolved findings;
- known risks;
- environment status;
- relevant evidence.

The incoming agent must inspect the current file state before continuing.

Do not assume the outgoing agent's report perfectly represents the current working tree.

## 18. Commit Ownership

Agents should not create arbitrary commits during parallel work unless their task explicitly authorizes committing.

Preferred flow:

```text
Agent changes
    ↓
Targeted tests
    ↓
Regression tests
    ↓
Task report
    ↓
Architect review
    ↓
Custody / commit checkpoint
```

This keeps the history reviewable.

## 19. Ownership Does Not Mean Architectural Authority

A file owner may implement within the approved architecture.

Ownership does not grant permission to:

- change product requirements;
- bypass security;
- change clinical policy;
- alter monetization rules;
- contact production;
- redefine another domain's contract.

## 20. Escalation

An agent must escalate when:

- two agents require the same file;
- a task crosses ownership boundaries;
- a migration changes a security boundary;
- a product decision is required;
- a clinical decision is required;
- production access appears necessary;
- current code contradicts an authoritative contract;
- remediation requires destructive changes;
- concurrent work may be overwritten.

The orchestrator resolves the boundary.

## 21. Future Specialist-Agent Architecture

The future 12Circle product architecture will include governed specialist capabilities such as:

- Strength
- Pilates
- Yoga
- Conditioning
- Functional Training
- Mobility / Recovery

Those agents are not current repository file owners.

When that implementation phase begins, ownership must be explicitly assigned and documented before code is created.

## 22. Future Wearable Intelligence

Wearable Intelligence is roadmap architecture.

Its future ownership may span:

- mobile integrations;
- wearable data ingestion;
- training intelligence;
- safety/governance;
- deterministic engine.

Do not assign implementation ownership until the relevant roadmap phase is authorized.

## 23. Current Wave

Current active work:

**Wave 1 — Tasks W1-T2 through W1-T9**

Agents must use the exact task assignment from the authoritative Wave 1 execution board.

Do not assume default ownership overrides an explicit task assignment.

## 24. Ownership Principle

The purpose of ownership is not to create silos.

It is to allow parallel work while preserving:

- correctness;
- security;
- traceability;
- reversibility;
- architectural coherence;
- human control.

When ownership is unclear, **stop and coordinate rather than guess.**
