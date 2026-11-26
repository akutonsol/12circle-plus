import 'package:flutter_test/flutter_test.dart';

import 'owned_rows_postgrest.dart';

// P0-FL-60c round 3 · Waiting without a fixed sleep. A sleep of 60-80 ms is a
// race against machine load: when the process is not scheduled for that long its
// timer is due before the turns that carry the answer (2 of 20 runs failed).
//
// [settled] waits for the positive marker that whatever was going to happen has:
// every request the app made is answered (or held by the test on purpose), every
// auth change was delivered, and [_stillRounds] rounds of event-loop TURNS, which
// take as long as they take, brought nothing more. It is what "nothing happened"
// is asserted after. [eventually] waits for a state that is expected to come.
// Neither can be passed by waiting less; both fail, naming what did not come.

const _bound = Duration(seconds: 25);
const _turns = 20;
const _stillRounds = 8;

Future<void> _turnTheLoop() async {
  for (var i = 0; i < _turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _Still {
  _Still(this._server);
  final OwnedRowsPostgrest _server;
  final _clock = Stopwatch()..start();
  var _rounds = 0;
  int? _seen;

  /// Whether the round that just ran was the last one needed.
  bool done() {
    final now = _server.activity;
    _rounds = _server.idle && now == _seen ? _rounds + 1 : 0;
    _seen = now;
    if (_rounds >= _stillRounds) return true;
    if (_clock.elapsed > _bound) {
      fail('Not settled after ${_bound.inSeconds} s: ${_server.waitingFor}.');
    }
    return false;
  }
}

/// In real time (a plain `test`, or inside `tester.runAsync`).
Future<void> settled(OwnedRowsPostgrest server) async {
  final still = _Still(server);
  do {
    await _turnTheLoop();
  } while (!still.done());
}

/// With frames: [frames] of [step] on the fake clock — always as many, so a
/// SnackBar or an animation is as old as it was — then as many as it takes, of
/// no time at all.
Future<void> settledFrames(
  WidgetTester tester,
  OwnedRowsPostgrest server, {
  required Duration step,
  int frames = 12,
}) async {
  final still = _Still(server);
  for (var i = 0;; i++) {
    await tester.runAsync(_turnTheLoop);
    await tester.pump(i < frames ? step : Duration.zero);
    if (still.done() && i + 1 >= frames) return;
  }
}

/// Answers land and events are delivered; NO frame runs.
Future<void> settledNoFrame(
    WidgetTester tester, OwnedRowsPostgrest server) async {
  final still = _Still(server);
  do {
    await tester.runAsync(_turnTheLoop);
    await tester.idle();
  } while (!still.done());
}

/// Real time: [actual] comes to match, within a bound no load reaches. What it
/// was when it did not is the failure, as with `expect`.
Future<void> eventually(Object? Function() actual, Object? matcher,
    {String? reason}) async {
  final m = wrapMatcher(matcher);
  final clock = Stopwatch()..start();
  while (!m.matches(actual(), <Object?, Object?>{}) && clock.elapsed < _bound) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(actual(), m, reason: reason);
}
