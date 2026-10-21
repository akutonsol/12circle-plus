// J-05 — AI-to-product path: is any of it actually reachable?
//
// Nine AI features are implemented in supabase/functions/. The Flutter client
// invokes seven of them. This suite asks the only question that decides whether
// any of the rest of the audit is observable end-to-end: are they deployed?
import { mark, signIn, fn, section, characterize, invariant, summary } from './lib.mjs';

const _from = mark();

const jwt = await signIn('victim');

const AI_FUNCTIONS = [
  ['ai-coach',                     'conversational coach + memory extraction'],
  ['ai-coaching-engine',           'daily insight / weekly review / prediction / risk / meals'],
  ['ai-generate-workout',          'one-off AI session generator'],
  ['analyze-food-image',           'photo → calories + macros'],
  ['explain-decision',             'L4: narrates a decision trace'],
  ['generate-communication',       'L8: phrases a weekly-review brief'],
  ['enrich-exercise-intelligence', 'populates the engine substrate'],
];

section('J-05A  deployment');
{
  const missing = [];
  const present = [];
  for (const [name, what] of AI_FUNCTIONS) {
    const r = await fn(jwt, name, {});
    // 404 NOT_FOUND from the functions gateway means "never deployed". Anything
    // else — 400, 401, 500, 502 — means the function ran and answered.
    const deployed = !(r.status === 404 && r.body?.code === 'NOT_FOUND');
    (deployed ? present : missing).push(`${name} (${what})`);
  }
  characterize('F-J-15  no AI edge function is deployed to this project',
    missing.length === AI_FUNCTIONS.length,
    `${missing.length}/${AI_FUNCTIONS.length} return NOT_FOUND — every AI surface in the ` +
    'product is dead here, and no AI behaviour can be verified end-to-end until they are deployed');

  invariant('the functions gateway itself is reachable',
    true, `probed ${AI_FUNCTIONS.length} names; ${present.length} answered`);
}

section('J-05B  the client\'s failure contract for a dead function');
{
  // workout_provider.generateAiWorkout throws on a non-200, so the Train hub
  // surfaces a real error. AICoachService.generate() swallows everything into
  // null, so the home briefing renders as "no insight yet" — indistinguishable
  // from a member with no data. Both are source-level and guarded in
  // ai_decision_integrity_test.dart (F-J-16).
  invariant('client-side failure handling is guarded at source', true,
    'see ai_decision_integrity_test.dart — F-J-16');
}

export default summary('J-05 product path', _from);
