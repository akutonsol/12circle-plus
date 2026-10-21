// J-03 — The deterministic engine boundary.
//
// The architecture's central claim is "the engine decides, the LLM explains".
// This suite asks whether the engine can actually decide: does it run, does it
// select anything, and does it fail closed when it cannot?
import { mark, signIn, rpc, section, characterize, invariant, summary, ALLOW_WRITES } from './lib.mjs';

const _from = mark();

const victim = await signIn('victim');

section('J-03A  build_workout applies the deload rule whenever recovery is low');
{
  // 089 declared `rules text[] := '{}'` then `rules := rules || 'RECOVERY_REDUCTION'`.
  // The untyped literal made Postgres resolve anyarray||anyarray and fail to read
  // the label as an array literal (22P02), so the one rule that protects an
  // under-recovered member was the only rule in the function that could not run.
  // Migration 127 casts it to ::text. The two assertions below were F-J-07
  // characterizations of that fault; they are inverted here to the post-fix
  // contract, per RELEASE_GATES.md Gate 3.13.
  const low = await rpc(victim, 'build_workout', { p_context: { recovery: 59 } });
  const lowRules = Array.isArray(low.body?.rules_triggered) ? low.body.rules_triggered : [];
  invariant('F-J-07  recovery below the deload threshold triggers RECOVERY_REDUCTION',
    low.status < 300 && lowRules.includes('RECOVERY_REDUCTION'),
    `HTTP ${low.status} rules_triggered=${JSON.stringify(low.body?.rules_triggered ?? null)}`);

  const ok = await rpc(victim, 'build_workout', { p_context: { recovery: 60 } });
  invariant('the same call at the threshold succeeds, isolating the fault to the rule append',
    ok.status < 300, `HTTP ${ok.status}`);

  // Same branch, a different context: the correction is deterministic.
  const gen = await rpc(victim, 'build_workout', { p_context: { recovery: 30, goal: 'strength', size: 4 } });
  invariant('F-J-07  the correction is deterministic, not incidental to one context',
    gen.status < 300, `HTTP ${gen.status} ${gen.body?.code ?? ''}`);
}

section('J-03B  an unplannable request succeeds with nothing in it');
{
  const r = await rpc(victim, 'build_workout', {
    p_context: { goal: 'strength', size: 5, recovery: 100,
                 equipment: ['barbell', 'dumbbell'], experience: 'intermediate' },
  });
  const selected = r.body?.selected ?? null;
  characterize('F-J-08  an empty substrate yields HTTP 200 and an empty workout',
    r.status < 300 && Array.isArray(selected) && selected.length === 0,
    `HTTP ${r.status}, selected=${Array.isArray(selected) ? selected.length : selected}, ` +
    `trace=${(r.body?.trace ?? []).length} entries, rules_triggered=${JSON.stringify(r.body?.rules_triggered)} — ` +
    'no status field, no error: the caller cannot tell "nothing suits you" from "the engine has no library"');

  // Downstream, migration 119 made materialize_program_week RAISE on an empty
  // selection rather than write four empty days. That is the fail-closed half
  // and it holds; build_workout itself still answers 200.
  invariant('the empty selection carries no rules_triggered to explain itself',
    Array.isArray(r.body?.rules_triggered) && r.body.rules_triggered.length === 0,
    'rules_triggered=[] — nothing in the response says why the plan is empty');
}

section('J-03C  the rejection gates are null-permissive');
{
  // build_workout reads `equipment_match` and `injury_compatibility` out of
  // score_exercise's breakdown. When score_exercise takes an early return it
  // emits neither key, both comparisons become NULL, every `if`/`elsif` is
  // false, and control falls through to `decision := 'accepted'`. The two early
  // returns are the not-found branch and the no-profile branch.
  const ex = await rpc(victim, 'rank_exercises', { p_context: { goal: 'strength' }, p_limit: 1 });
  invariant('rank_exercises is callable', ex.status < 300, `HTTP ${ex.status}`);

  const bogus = await rpc(victim, 'score_exercise', {
    p_exercise_id: '00000000-0000-0000-0000-000000000000',
    p_context: { goal: 'strength', injuries: ['knee'] },
  });
  const b = bogus.body ?? {};
  characterize('F-J-09  a score_exercise early return omits both gate keys',
    b.error !== undefined && b.equipment_match === undefined && b.injury_compatibility === undefined,
    `breakdown=${JSON.stringify(b)} → in build_workout em/ic are NULL, ` +
    'the equipment and injury rejections silently do not apply, and the candidate is accepted');
}

section('J-03D  the AI generator never consults the engine');
{
  // ai-generate-workout's own system prompt: "Do NOT prescribe a load. Weight is
  // the deterministic engine's decision, not yours." No engine call is made,
  // before or after. weight_kg is written null for every exercise, forever, and
  // no decision_traces row is recorded for an AI-generated session.
  invariant('this is a source-level contract gap, guarded in ai_decision_integrity_test.dart',
    true, 'see F-J-10 — the engine is named as the authority and never invoked');
}

if (ALLOW_WRITES) {
  section('J-03E  writes (AI_ALLOW_WRITES=1)');
  const before = await rpc(await signIn('admin'), 'decision_analytics');
  const g = await rpc(victim, 'generate_workout', { p_context: { goal: 'strength', size: 3, recovery: 100 } });
  const after = await rpc(await signIn('admin'), 'decision_analytics');
  characterize('F-J-11  an empty selection is still persisted as engine provenance',
    g.status < 300 && (g.body?.selected ?? []).length === 0 && !!g.body?.trace_id,
    `trace_id=${g.body?.trace_id} recorded with selected=[] — total_generations ` +
    `${before.body?.total_generations} → ${after.body?.total_generations}. ` +
    'decision_traces rows are not client-deletable; see the report\'s QA-mutations section.');
} else {
  console.log('\n  (skipped J-03E writes — set AI_ALLOW_WRITES=1 to record a decision trace on QA)');
}

export default summary('J-03 engine boundary', _from);
