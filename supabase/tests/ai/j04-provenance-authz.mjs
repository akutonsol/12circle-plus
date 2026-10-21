// J-04 — Decision provenance and subject scoping.
//
// A decision trace is the audit record for a training decision made about a
// person's body. Two questions: does it record enough to replay the decision,
// and can only the right people read it?
import { mark, signIn, rest, rpc, section, characterize, invariant, summary } from './lib.mjs';

const _from = mark();

const victim   = await signIn('victim');
const attacker = await signIn('attacker');
const coach    = await signIn('coach');
const admin    = await signIn('admin');
const contentmgr = await signIn('contentmgr');

/** The `sub` claim — who this JWT actually is, without a service key or ids.json. */
const subjectOf = (jwt) =>
  JSON.parse(Buffer.from(jwt.split('.')[1], 'base64url').toString('utf8')).sub;

section('J-04A  who can read a decision trace');
{
  // The authorized policy is PD-A05 **option (a)**, ruled by the product owner
  // on 2026-08-27 and enforced by migration 128:
  //
  //     subject  OR  created_by  OR  the subject's ACTIVE coach  OR  admin
  //
  // and nobody else. Two arms are deliberately absent. The `coach` role alone is
  // never sufficient — that was F-J-12, migration 089's unscoped role arm, which
  // let a self-registered coach read every member's traces. And `content_manager`
  // is excluded even though every sibling engine-output table admits it
  // (`predictions` 095, `program_versions` 093, `communications` 096), because a
  // trace carries the member's decision context and per-candidate rejection
  // reasons: access is granted by relationship, not by role class.
  //
  // Migration 125 removed the coach arm and kept `content_manager` — option (b).
  // 128 is the narrowing to the authorized option (a).
  //
  // The two POSITIVE arms that need a service key to arrange their fixtures — the
  // active coach, and `created_by` surviving the end of a relationship (M-1) —
  // are proved in supabase/tests/security/d05-intelligence-substrate.mjs §9.
  // ── THE PRECONDITION IS "NO RELATIONSHIP THAT GRANTS ACCESS", NOT "NO ROW" ──
  // This used to require zero rows of any kind, and failed on a relationship left at
  // status `cancelled` by an earlier suite. That was an unsound precondition, not a
  // security finding: the arm under test is `is_active_coach_of(subject_id)`
  // (`128:93`), and that function is `status = 'active'` and nothing else
  // (`100:21-35`, the single definition migrations 136/137 exist to keep from
  // drifting). A cancelled relationship therefore grants exactly nothing, so its
  // presence cannot invalidate the negative assertions below.
  //
  // THE NEGATIVE ASSERTIONS THEMSELVES ARE UNCHANGED. What narrows here is only the
  // arrangement check — the claim "this coach has no access-granting relationship" —
  // which is now exactly as strong as the predicate it has to rule out, and no
  // stronger.
  //
  // Non-active rows are COUNTED AND REPORTED rather than ignored, so residue from
  // another suite stays visible in the output instead of becoming invisible. This
  // suite holds no service key by design, so it cannot delete them to arrange a clean
  // world; depending on one would make it fragile by construction.
  const rel = await rest(coach, 'coach_client_relationships?select=coach_id,client_id,status');
  const relRows = Array.isArray(rel.body) ? rel.body : null;
  const active = relRows?.filter((r) => r.status === 'active') ?? null;
  const inactive = relRows?.filter((r) => r.status !== 'active') ?? [];
  invariant('the probe coach holds no ACTIVE client relationship, so nothing grants ' +
    'it the is_active_coach_of read',
    active !== null && active.length === 0,
    `active=${active?.length ?? -1}` +
    (inactive.length
      ? `; ${inactive.length} non-active row(s) present and irrelevant to access ` +
        `[${[...new Set(inactive.map((r) => r.status))].join(', ')}]`
      : '; no other rows'));

  // Traces this coach AUTHORED are excluded, and only those. Under option (a)
  // the `created_by` arm (M-1) grants the creator a permanent read of their own
  // audit record — deliberately, and independently of any relationship — so a
  // coach-authored trace appearing here would be the policy working, not a
  // boundary failure. d05 §9 probe D creates exactly one such trace per run to
  // prove that arm, which is what made the unfiltered form of this query stop
  // testing the proposition its name states. Narrowing the QUERY keeps the
  // assertion itself intact: an unrelated coach, reading traces they did not
  // create, must still see nothing.
  const coachId = subjectOf(coach);
  //
  // THE FILTER INCLUDES NULLs, AND THAT IS THE POINT. `created_by=neq.X` alone
  // is NULL-REJECTING in PostgREST, so a trace with `created_by IS NULL` that
  // this coach could read through some other arm would be invisible to this
  // probe — the blind spot the registry records as retained limitation (ii) on
  // `F-J-12`. The proposition is "traces this coach did NOT create", and a trace
  // with no creator is one of those, so the filter now says so:
  //     or=(created_by.is.null, created_by.neq.<coach>)
  // `created_by` is nullable — 089 declares `created_by uuid references
  // user_profiles(id)` with no NOT NULL, and no later migration alters it — so
  // this is a reachable shape, not a hypothetical. Adding NOT NULL would be a
  // data-contract decision and is NOT taken here.
  const asCoach = await rest(coach,
    `decision_traces?select=id,subject_id&or=(created_by.is.null,created_by.neq.${coachId})`);
  const subjects = Array.isArray(asCoach.body)
    ? [...new Set(asCoach.body.map(r => r.subject_id))] : [];
  invariant('an unrelated coach cannot read another member\'s decision traces',
    Array.isArray(asCoach.body) && asCoach.body.length === 0,
    `${Array.isArray(asCoach.body) ? asCoach.body.length : asCoach.status} trace(s) across ` +
    `${subjects.length} subject(s) — decision-trace reads are scoped to authorized relationships`);

  // And the other half of limitation (ii), asserted rather than assumed. The
  // registry's parenthetical reads "(none is readable under option (a) today)".
  // That was a measurement nobody re-ran. This re-runs it every time, through
  // the AUTHORIZED read path rather than a service key: `admin` holds the admin
  // arm, so if any NULL-creator trace were readable at all, admin would see it.
  //
  // NON-VACUITY FIRST. "admin sees zero NULL-creator traces" is also what you get
  // when admin can read NOTHING — a denied read and an empty subset are the same
  // number. So admin's read capability is established BEFORE the subset claim is
  // made, in that order, or the assertion below proves nothing. This is the same
  // trap as a page-capped `1000 === 1000` (§203) and a suite reporting `PASS 0/0`
  // (§205.5): a zero that was never able to be non-zero.
  const anyTrace = await rest(admin, 'decision_traces?select=id&limit=1');
  invariant('admin can read decision traces at all — the premise the NULL-creator ' +
            'assertion below depends on',
    Array.isArray(anyTrace.body) && anyTrace.body.length > 0,
    `${Array.isArray(anyTrace.body) ? anyTrace.body.length : anyTrace.status} row(s) — ` +
    `if this is 0, the next assertion is vacuous rather than reassuring`);

  const nullCreator = await rest(admin, 'decision_traces?select=id&created_by=is.null');
  invariant('no decision trace with a NULL creator is readable — the arm the ' +
            'created_by filter above now covers is empty, and that is measured ' +
            'against a read path proved non-empty',
    Array.isArray(nullCreator.body) && nullCreator.body.length === 0,
    `${Array.isArray(nullCreator.body) ? nullCreator.body.length : nullCreator.status} ` +
    `NULL-creator trace(s) visible to admin`);

  const asClient = await rest(attacker, 'decision_traces?select=id,subject_id');
  invariant('an unrelated CLIENT still reads nothing',
    Array.isArray(asClient.body) && asClient.body.length === 0,
    `${Array.isArray(asClient.body) ? asClient.body.length : asClient.status} row(s)`);

  // F-J-12 / PD-A05(a) — the ONE arm that distinguishes option (a) from option
  // (b). Everything above this line passes identically under both, so without
  // this probe the ruling is unverifiable in either direction.
  const asContentMgr = await rest(contentmgr, 'decision_traces?select=id,subject_id');
  const cmRows = Array.isArray(asContentMgr.body) ? asContentMgr.body : null;
  invariant('a content_manager cannot read another member\'s decision traces',
    cmRows !== null && cmRows.length === 0,
    `${cmRows === null ? `HTTP ${asContentMgr.status}` : `${cmRows.length} row(s)`} — PD-A05 ` +
    'option (a) grants no staff arm below admin; migration 125 granted this role and 128 removes it');

  // The subject arm, positively. A policy that refused EVERYONE would satisfy
  // every negative assertion above and be a different defect, not a fix.
  const victimId = subjectOf(victim);
  const own = await rest(victim, 'decision_traces?select=id,subject_id,created_by');
  const ownRows = Array.isArray(own.body) ? own.body : [];
  const asSubject = ownRows.filter(r => r.subject_id === victimId);
  const foreign = ownRows.filter(r => r.subject_id !== victimId && r.created_by !== victimId);
  invariant('the SUBJECT reads their own decision traces, and only rows they are subject or creator of',
    own.status < 300 && asSubject.length > 0 && foreign.length === 0,
    `HTTP ${own.status} — ${asSubject.length} of ${ownRows.length} row(s) have the caller as subject, ` +
    `${foreign.length} row(s) the caller is neither subject nor creator of`);
}

section('J-04B  what a decision trace actually records');
{
  const traces = await rest(admin, 'decision_traces?select=id,subject_id,created_by,engine_version,rules_version,scoring_version,graph_version,context,rules_triggered,explanation_client,explain_model&order=created_at.desc&limit=25');
  const rows = Array.isArray(traces.body) ? traces.body : [];
  invariant('traces are readable for audit', traces.status < 300, `HTTP ${traces.status}`);

  if (rows.length) {
    invariant('every trace carries the four engine version stamps',
      rows.every(r => r.engine_version && r.rules_version && r.scoring_version && r.graph_version),
      `e.g. ${rows[0].engine_version}/${rows[0].rules_version}/${rows[0].scoring_version}/${rows[0].graph_version}`);

    invariant('every trace names a subject and a creator',
      rows.every(r => r.subject_id && r.created_by), `${rows.length} row(s) checked`);

    // A trace is replayable only if it records the inputs the decision was made
    // from. `context` is whatever the caller passed — nothing snapshots the
    // member's real goal, equipment, recovery or injuries at decision time.
    const noInjuries = rows.filter(r => !Object.keys(r.context ?? {}).includes('injuries'));
    characterize('F-J-13  the recorded context is not an input snapshot',
      noInjuries.length === rows.length,
      `${noInjuries.length}/${rows.length} traces record no injuries at all; ` +
      `example context = ${JSON.stringify(rows[0].context)} — the decision cannot be replayed ` +
      'and there is no record of what safety state the member was in');

    characterize('F-J-14  no trace records a model identifier or an AI contribution',
      rows.every(r => !r.explain_model && !r.explanation_client),
      'explain_model and explanation_client are null on every row — the AI half of ' +
      'the pipeline leaves no provenance, and explain-decision is the only writer');
  }

  const analytics = await rpc(admin, 'decision_analytics');
  if (analytics.status < 300) {
    characterize('F-J-08  recorded decisions triggered no rule and rejected nothing',
      analytics.body?.most_triggered_rule === null && analytics.body?.most_rejected_exercise === null,
      `total_generations=${analytics.body?.total_generations}, ` +
      `most_triggered_rule=${analytics.body?.most_triggered_rule}, ` +
      `most_rejected_exercise=${analytics.body?.most_rejected_exercise}, ` +
      `avg_recovery=${analytics.body?.avg_recovery} — every persisted decision is an empty one`);
  }
}

section('J-04C  subject-scoped engine RPCs');
{
  // Migration 116 wrapped each subject/program-scoped engine function in a
  // can_act_for / can_act_on_program guard. Migration 119 then CREATE OR
  // REPLACEd one of them by its public name, which replaced the wrapper.
  // Migration 124 restored the authorization wrapper for
  // materialize_program_week() and its intended program-scoping boundary.
  const program = (await rest(admin, 'workout_programs?select=id,coach_id&coach_id=not.is.null&limit=1')).body?.[0];
  invariant('a program owned by someone else exists to probe', !!program, program?.id ?? 'none');

  if (program) {
    // Week 99 is not in any plan, so the engine aborts before its DELETE. The
    // probe is therefore non-destructive and still proves how far the caller got.
    const guarded = ['evaluate_week', 'regenerate_program'];
    for (const f of guarded) {
      const r = await rpc(attacker, f, { p_program_id: program.id, p_week: 99 });
      invariant(`${f} refuses an unrelated caller`,
        r.status === 403 || r.body?.code === '42501',
        `HTTP ${r.status} ${r.body?.message ?? ''}`);
    }

    const m = await rpc(attacker, 'materialize_program_week',
      { p_program_id: program.id, p_week: 99, p_context: { size: 3 } });
    invariant('materialize_program_week refuses an unrelated caller',
      m.status === 403 || m.body?.code === '42501',
      `HTTP ${m.status} ${m.body?.code ?? ''} "${m.body?.message ?? ''}" — ` +
      'the authorization boundary correctly prevents access to another coach\'s program.');
  }

  const forVictim = await rpc(attacker, 'generate_workout',
    { p_context: { size: 2 }, p_subject: (await rest(admin, 'decision_traces?select=subject_id&limit=1')).body?.[0]?.subject_id });
  invariant('generate_workout still refuses to forge provenance against another subject',
    forVictim.status === 403 || forVictim.body?.code === '42501',
    `HTTP ${forVictim.status} ${forVictim.body?.message ?? ''}`);
}

export default summary('J-04 provenance & scoping', _from);
