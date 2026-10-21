-- 128_scope_decision_trace_reads_option_a.sql
--
-- F-J-12 — enforce PD-A05 **option (a)**, as ruled by the product owner on
-- 2026-08-27 (governance record: docs/MASTER_PRODUCT_DECISIONS.md row PD-A05,
-- rationale in docs/decision-log.md, reconciliation in registry section 7.11).
--
-- ── WHAT THIS CHANGES ───────────────────────────────────────────────────────
-- Migration 125 closed the actual defect — 089's unscoped `role = coach` arm,
-- which let any self-registered coach read every member's decision traces — but
-- it retained `content_manager` in the staff arm. That is option (b). The
-- authorized policy is option (a):
--
--     subject  OR  created_by  OR  the subject's ACTIVE coach  OR  admin
--
-- and nothing else. `content_manager` is deliberately NOT granted.
--
-- 125 is NOT edited. It is applied, and an in-place edit of an applied migration
-- is ENV-2 / CRC-13 — the defect this programme is remediating. This file is the
-- forward correction, and it is a strict narrowing of 125 on exactly one arm.
--
-- ── WHY OPTION (A), IN ONE LINE ─────────────────────────────────────────────
-- A trace carries the member's decision context and the per-candidate rejection
-- reasons — injury-based rejections included, once the substrate is populated.
-- Read access is therefore granted by RELATIONSHIP, not by ROLE CLASS. The
-- accepted trade-off (this table is now stricter than its siblings; engine QA
-- has no read path but `admin`) is recorded in decision-log.md, not re-argued
-- here.
--
-- ── M-1: `created_by` IS RETAINED ───────────────────────────────────────────
-- The PD-A05 option text was silent on this arm; the owner resolved the silence
-- in favour of retention. A coach must not lose the audit record of a decision
-- they themselves made when the relationship ends — auditability is the reason
-- decision traces exist.
--
-- ── M-3: SIBLING POLICIES ARE NOT TOUCHED ───────────────────────────────────
-- `predictions` (095), `program_versions` (093), `communications` (096) and
-- `intelligence_attribute_reviews` (091) all admit `content_manager` and, in the
-- last case, `coach`. They remain SEPARATE DECISIONS and are deliberately left
-- exactly as they are by this migration.
--
-- ── PROPERTIES PRESERVED ────────────────────────────────────────────────────
--   * target role            `authenticated` (unchanged)
--   * subject self-read      `subject_id = auth.uid()` (unchanged)
--   * creator read           `created_by = auth.uid()` (unchanged, M-1)
--   * active-coach read      `is_active_coach_of(subject_id)` (unchanged from 125)
--   * admin read             now via `public.is_admin()` — SECURITY DEFINER,
--                            `search_path` pinned (019, re-pinned by 115/122),
--                            which is the predicate every other admin gate in
--                            this schema uses, rather than 125's inline
--                            `EXISTS (... user_profiles ...)`
--   * WRITE-DENY posture     `decision_traces` carries a SELECT policy and NO
--                            write policy. Under RLS "no policy" means deny, so
--                            no client can INSERT, UPDATE or DELETE a trace —
--                            asserted by 117 and pinned live by
--                            d05-intelligence-substrate.mjs section 3, including
--                            "not even an admin can hand-write a decision
--                            trace". This migration creates NO write policy and
--                            must never be extended to.
--   * ERASURE                stays with `service_role`, which bypasses RLS.
--                            Unchanged.
--   * `(SELECT auth.uid())`  retained from 125 — PostgreSQL caches it as an
--                            InitPlan instead of re-evaluating per row. A
--                            performance property, not a security one.
--
-- ── KNOWN LIMITATION, RECORDED NOT SILENTLY EXPANDED ────────────────────────
-- The I-MIG-03 migration-durability guard tracks FUNCTION properties only —
-- authorization wrapper, search_path pin, SECURITY DEFINER. **RLS policies are
-- outside its coverage**, so nothing in this repository would notice if a later
-- migration replaced this policy with a weaker one — the exact mechanism that
-- produced F-J-01. Whether Gate 0.14 should cover policies is a separate
-- governance question and is NOT decided here (registry section 7.11).
--
-- ── ROLLBACK ────────────────────────────────────────────────────────────────
--   Reinstating a broader scope requires a new forward migration and a new
--   PD-A05 ruling. Do not restore 089's `role = coach` arm under any
--   circumstances — that is F-J-12.

BEGIN;

-- Every prior name is dropped so this migration is idempotent on replay and
-- correct whether it lands on 089's policy or on 125's.
DROP POLICY IF EXISTS "dtrace read own/staff"                      ON public.decision_traces;
DROP POLICY IF EXISTS "dtrace read own/creator/scoped-staff"       ON public.decision_traces;
DROP POLICY IF EXISTS "dtrace read own/creator/active-coach/admin" ON public.decision_traces;

CREATE POLICY "dtrace read own/creator/active-coach/admin"
  ON public.decision_traces
  FOR SELECT
  TO authenticated
  USING (
    subject_id = (SELECT auth.uid())
    OR created_by = (SELECT auth.uid())
    OR public.is_active_coach_of(subject_id)
    OR public.is_admin()
  );

COMMENT ON POLICY "dtrace read own/creator/active-coach/admin"
  ON public.decision_traces IS
  'PD-A05 option (a), owner-ruled 2026-08-27. Readable by the subject, the trace''s creator (M-1: auditability survives the relationship ending), the subject''s ACTIVE coach, or an admin. content_manager is deliberately NOT granted, and the coach role alone is never sufficient (F-J-12). No write policy exists on this table and none may be added: provenance is written by SECURITY DEFINER engine functions and erased only by service_role.';

COMMIT;
