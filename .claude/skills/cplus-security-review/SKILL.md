---
name: cplus-security-review
description: Method for reviewing 12circle-plus authorization, privacy and data access — finding what the UI hides but the server still allows, building ownership matrices, checking RLS/RPC/storage/Edge Function boundaries, and proving each finding with a failing test. Use for any 12circle-plus security review or sensitive change.
---

# Security review in 12circle-plus

## The question to ask everywhere

**Does the server refuse what the app hides?** A `PaywallGate`, a hidden button or a role check in
Dart is not enforcement. For every sensitive action, find the database or function rule that refuses
it, and prove it with a write issued as `authenticated` (local replay) — not by reading the policy.

## Where defects have actually been (check these classes first)

- Permissive policies with a caller-chosen column (`coach_id = auth.uid()` where the caller writes
  `coach_id`) — any user can name themselves (OD-14 / 185).
- A row that unlocks reads elsewhere (`can_read_program` via an assignment row — 196/197/200).
- SECURITY DEFINER RPCs that bypass the table's own owner policy (`update_exercise_media` — 199).
- Storage policies that check only `bucket_id` (exercise-media, coach-media — 199). Buckets are
  public by URL; RLS on `storage.objects` governs API list/sign/write only.
- Edge Functions that verify a JWT but not the caller's right (plan, role, service-only):
  `verify_jwt` accepts any project JWT.
- Client-writable state that should be server-derived (scores, challenge progress, credits).
- Self-activation of paid access (193); spoofable provenance (`user_profiles.email` vs `auth.users`).

## How to review

1. List the actors (client, coach, other coach, unrelated user, content_manager, admin, service).
2. Build a matrix: actor × action × object (own / another's / platform) → expected answer.
3. Read live policies read-only (`pg_policies`, `pg_get_functiondef`) and the app call sites.
4. Prove each "should refuse" with a failing replay assertion and each "should allow" with a
   positive control. Report severity (P0 data breach/takeover, P1 cross-tenant read/write or
   paid-resource bypass, P2 abuse/integrity, info).
5. Separate **defect** (contradicts an existing rule) from **decision** (no rule exists — e.g.
   program sharing). Decisions go to Julia with alternatives; they are not "fixed".

Never weaken a guard to make a test pass. Never query production. Never print secrets.
