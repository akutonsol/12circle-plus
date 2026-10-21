# 12 Circle — Decision Log

A concise record of **major product & architecture decisions and why** — not a
changelog. When someone asks "why is it built this way?", the answer lives here.

**How to use:** append a row when a decision is load-bearing (it constrains future
work or would be expensive to reverse). Keep the *why* honest, including the
trade-off. Mark superseded rows rather than deleting them.

---

## Core invariants

| Date | Decision | Why |
|------|----------|-----|
| 2026-07 | **The engine decides, the AI explains.** | Consistency, explainability, and trust. An LLM that invents programming can't be audited or trusted by coaches. |
| 2026-07 | **Every recommendation produces a decision trace.** | Auditing, debugging, coach review, and later prediction-vs-reality analysis. No black boxes. |
| 2026-07 | **Coaches approve consequential changes (approval matrix by mode).** | Preserve coach authority; keep the human at the center of the client relationship. Minor changes auto-apply for AI/self-guided to avoid friction. |
| 2026-07 | **Completed history is immutable; only the future adapts.** | Integrity of the training record; regeneration must never rewrite what a client already did. |
| 2026-07 | **Knowledge is human-reviewed before the engine trusts it.** | AI drafts are fast but fallible; certified knowledge keeps recommendations safe and defensible. |
| 2026-07 | **AI communications are drafts a coach edits before sending.** | Coaches own client communication; AI accelerates, it doesn't speak unsupervised. |

## Architecture choices

| Date | Decision | Why |
|------|----------|-----|
| 2026-06/07 | **Deterministic MIE (graph + scoring + rules) as the decision core; LLM as a pure presentation layer.** | The moat. Enables reproducibility, auditability, and safe AI. |
| 2026-07 | **Certification view is the single source of truth for "can module X use this exercise?"** | Every consumer (Workout Builder, AI Coach, Program Gen, Marketplace) gates on one computed view instead of re-checking fields. |
| 2026-07 | **Relationships & knowledge attributes are first-class *reviewable* assets (per-attribute review).** | A whole-profile approve/reject throws away good AI work; per-attribute review lets humans certify only the low-confidence parts. |
| 2026-07 | **Program Builder uses plan-then-materialize (plan the cycle up front, materialize each week just-in-time via `build_workout`).** | Reuses the workout engine (no duplication) and makes adaptive regeneration clean — only future weeks are (re)materialized. |
| 2026-07 | **Predictions & regenerations reuse the decision-trace + version pattern.** | One audit model across engines; enables decision-accuracy analysis and rollback. |
| 2026-08-27 | **Who may read a decision trace: the subject, its `created_by`, the subject's *active* coach, and `admin` — and nobody else.** `content_manager` is deliberately excluded. (PD-A05, option (a); owner: product + privacy.) | A decision trace carries the member's decision context and the per-candidate rejection reasons — injury-based rejections included, once the substrate is populated. That is health-adjacent, so read access is granted by **relationship**, not by **role class**: 12 Circle allows self-serve coach signup, so `coach` was never a trusted class, and a staff role is a standing grant over every member at once. **Trade-off, stated honestly:** this makes `decision_traces` stricter than its sibling tables (`predictions`, `program_versions`, `communications` all admit `content_manager`), and it leaves engine QA with no read path except `admin` — which under migration 019 also exposes every user's name and email. That cost was accepted in exchange for the narrower disclosure surface; the sibling policies were left as separate decisions rather than swept along. **`created_by` is retained** so a coach never loses the audit record of a decision they made when a relationship ends — auditability is the reason traces exist. |

## Notable engineering calls (with trade-offs)

| Date | Decision | Why |
|------|----------|-----|
| 2026-07 | **Dedicated `exercise_intelligence` table rather than the (empty) intelligence columns on `exercises`.** | Those columns were 0/623 populated; a separate reviewable table keeps the scoring engine's typed inputs clean and extensible without bloating `exercises`. |
| 2026-07 | **Content-enrichment writes to the `exercises` table, not `custom_exercises`.** | Discovered `custom_exercises` is empty and the older single-slug enricher targeted it — it would never have filled the live 623-exercise library. Corrected the target. |
| 2026-07 | **Content-completeness gaps are WARN, not FAIL, in QA/certification.** | Structural corruption (dup slug, missing name) blocks a release; a content backlog shouldn't perpetually gate deploys. |
| 2026-07 | **Rich profile + per-attribute confidence stored as JSONB; scoring-critical fields stay typed.** | Extensible knowledge without 30 new columns, while the deterministic scorer reads stable typed inputs. |
| 2026-08-28 | **The booking screen reads coach profiles in a second query against `public_profiles`, not through a PostgREST embed.** (PD-A23, option (b), product owner, 2026-08-28.) | `coach_client_relationships.coach_id` is a foreign key to **`auth.users`**, not to any relation in the `public` schema, so PostgREST cannot resolve `coach:coach_id(...)` and answers PGRST200 before reading a row — `/appointments` and `/book-call` were dead for every client (UIX-1 / `M-03`). Option (a), adding a FK to `user_profiles`, would work but costs a migration on a table in the security-sensitive coach graph. Option (b) needs **no migration**, keeps the read on the sanctioned non-sensitive projection, and matches the two-query pattern `coach_relationship_service.dart` already uses. Trade-off accepted: two round trips instead of one, and the join is maintained in Dart. |

## Process / phase

| Date | Decision | Why |
|------|----------|-----|
| 2026-07 | **Backend freeze after L8 (Communication Engine).** | Architecture is feature-complete; further foundational work has diminishing returns pre-beta. |
| 2026-07 | **Did NOT build a Recommendation Trust Rate on current data.** | The platform can't yet distinguish accepted-unchanged / edited / rewritten / rejected; any trust metric would be misleading. Restraint over a vanity number. |
| 2026-07 | **Three measurement capture hooks are the ONLY sanctioned backend exception in validation.** | They are measurement infrastructure, not product features, and they unlock the KPIs that define the mission (trust rate, decision accuracy, coach time saved). |
| 2026-07 | **Next milestone is validation (50 coaches × 90 days), not another feature.** | Product-market fit evidence outranks additional intelligence at this stage. |

---

## Superseded / revised

*(none yet — add here when a decision above is reversed, with the new rationale.)*
