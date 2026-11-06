// OFFLINE self-test for the AI harness's reporting and substrate gate (PRQ-1).
// No network: only pure functions are exercised. A loopback dummy target is set
// BEFORE lib.mjs is imported, so a real QA_URL in the shell is never used.
//
//   node supabase/tests/ai/selftest.mjs        # exit 0 = every self-check held
process.env.QA_URL = 'http://127.0.0.1:9';
process.env.QA_ANON = 'offline-selftest';
delete process.env.AI_ALLOW_WRITES;

const lib = await import('./lib.mjs');
const { results, mark, check, characterize, skip, summary, suiteVerdict,
        substrateFrom, whenSubstrateEmpty } = lib;

let failed = 0;
const expect = (name, ok) => { console.log(`  ${ok ? 'ok  ' : 'FAIL'} ${name}`); if (!ok) failed++; };
const res = (status, range) => ({ status, headers: { get: (h) => (h === 'content-range' ? range : null) } });
const quiet = (fn) => { const log = console.log; console.log = () => {}; try { return fn(); } finally { console.log = log; } };

console.log('AI harness self-test (offline)');

// 1 · a skip is reported separately and counts as neither a pass nor a failure
{
  const from = mark();
  quiet(() => { check('a pass', true); skip('a skip', 'reason'); });
  const failures = quiet(() => summary('t1', from));
  const mine = results.slice(from);
  expect('skip is recorded as skipped, not as a pass', mine[1].skipped === true && mine[1].pass === null);
  expect('summary returns 0 failures with one pass and one skip', failures === 0);
  expect('the pass count excludes the skip', mine.filter(r => !r.skipped && r.pass).length === 1);
}

// 2 · a normal failed assertion still fails
{
  const from = mark();
  quiet(() => { check('a pass', true); check('a failure', false); skip('a skip', 'reason'); });
  expect('a failed assertion is counted as 1 failure', quiet(() => summary('t2', from)) === 1);
}

// 3 · a suite with no passing assertions and only skips is not a successful pass
{
  expect('only skips → SKIP, not PASS', suiteVerdict({ ran: 2, skipped: 2, failures: 0 }) === 'SKIP');
  expect('asserted and passing with a skip → PASS', suiteVerdict({ ran: 3, skipped: 1, failures: 0 }) === 'PASS');
  expect('a failure → FAIL even with skips', suiteVerdict({ ran: 3, skipped: 2, failures: 1 }) === 'FAIL');
  expect('a suite error with nothing recorded → FAIL', suiteVerdict({ ran: 0, skipped: 0, failures: 1 }) === 'FAIL');
}

// 4 · the substrate gate: empty preserves existing behaviour; populated skips; unknown fails
{
  const empty = { state: 'empty', detail: '0 rows' };
  let from = mark();
  quiet(() => whenSubstrateEmpty(empty, 'pinned', () => characterize('pinned', true, 'd')));
  let r = results.slice(from);
  expect('empty + holding assertion → it runs and passes, exactly as before',
    r.length === 1 && r[0].pass === true && r[0].kind === 'characterization');

  from = mark();
  quiet(() => whenSubstrateEmpty(empty, 'pinned', () => characterize('pinned', false, 'd')));
  r = results.slice(from);
  expect('empty + broken assertion → it still fails, exactly as before',
    r.length === 1 && r[0].pass === false && quiet(() => summary('t4b', from)) === 1);

  from = mark();
  let ran = false;
  quiet(() => whenSubstrateEmpty({ state: 'populated', detail: '621 rows' }, 'pinned', () => { ran = true; }));
  r = results.slice(from);
  expect('populated → assertion not run, recorded as a skip', !ran && r.length === 1 && r[0].skipped === true);

  for (const s of [{ state: 'unknown', detail: 'HTTP 500' }, undefined, {}]) {
    from = mark();
    ran = false;
    quiet(() => whenSubstrateEmpty(s, 'pinned', () => { ran = true; }));
    r = results.slice(from);
    expect(`unknown state (${JSON.stringify(s) ?? 'undefined'}) → a failure, never read as empty`,
      !ran && r.length === 1 && r[0].pass === false && !r[0].skipped);
  }
}

// 5 · the probe classifier fails closed
{
  expect('editor + "*/0" → empty', substrateFrom(true, res(200, '*/0')).state === 'empty');
  expect('editor + "*/621" → populated', substrateFrom(true, res(200, '*/621')).state === 'populated');
  expect('not an editor (RLS would show 0) → unknown', substrateFrom(false, res(200, '*/0')).state === 'unknown');
  expect('editor check not exactly true → unknown', substrateFrom('true', res(200, '*/0')).state === 'unknown');
  expect('HTTP error → unknown', substrateFrom(true, res(500, '*/0')).state === 'unknown');
  expect('no content-range → unknown', substrateFrom(true, res(200, null)).state === 'unknown');
  expect('unparseable content-range → unknown', substrateFrom(true, res(200, '0-0/*')).state === 'unknown');
  expect('no response → unknown', substrateFrom(true, undefined).state === 'unknown');
}

console.log(failed ? `\nSELF-TEST FAILED: ${failed} check(s)` : '\nself-test: all checks held');
process.exit(failed ? 1 : 0);
