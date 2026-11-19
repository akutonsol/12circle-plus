import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/dashboard/presentation/coach_dashboard_screen.dart';
import 'package:flutter_test/flutter_test.dart';

// P0-FL-14 review · the coach notifications stream re-opens when it ends:
// 2 s, doubling while it keeps ending without data, capped at 1 min — and
// back to 2 s once data has arrived (otherwise one bad hour leaves the bell a
// minute behind for the rest of the session). The provider's own stream is
// `reopenWhenDone` over supabase's `.stream()`; here the inner stream is under
// the test's control and time is the test binding's fake clock.
//
// Kills review mutant (b): dropping the `delay = first` reset on data makes
// the re-open after the data-bearing stream wait 16 s, not 2 s.

void main() {
  final reported = <AppFailure>[];
  setUp(() {
    reported.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  /// Each open hands back a fresh controller the test drives.
  late List<StreamController<int>> opened;
  Stream<int> open() {
    final c = StreamController<int>();
    opened.add(c);
    return c.stream;
  }

  /// Ends the latest inner stream (optionally after one value or an error) and
  /// asserts the next open comes exactly [gap] later — not a moment sooner.
  Future<void> endAndExpectReopenAfter(WidgetTester tester, Duration gap,
      {int? value, bool error = false}) async {
    final before = opened.length;
    final c = opened.last;
    if (value != null) c.add(value);
    if (error) c.addError(StateError('fetch failed'));
    await c.close();
    await tester.pump();
    await tester.pump(gap - const Duration(milliseconds: 1));
    expect(opened.length, before, reason: 're-opened before $gap');
    await tester.pump(const Duration(milliseconds: 1));
    expect(opened.length, before + 1, reason: 'not re-opened at $gap');
  }

  testWidgets('back-off doubles from 2 s, caps at 1 min, and resets to 2 s '
      'after data arrives', (tester) async {
    opened = [];
    final values = <int>[];
    final errors = <Object>[];
    final sub = reopenWhenDone<int>(open, origin: 'test.backoff')
        .listen(values.add, onError: errors.add);
    addTearDown(sub.cancel);
    await tester.pump();
    expect(opened, hasLength(1));

    // Failing: 2, 4, 8, 16, 32, then the 1-minute cap, and it stays capped.
    for (final s in [2, 4, 8, 16, 32, 60, 60]) {
      await endAndExpectReopenAfter(tester, Duration(seconds: s), error: true);
    }
    expect(errors, hasLength(7), reason: 'each failure reaches the consumer');
    expect(reported.map((f) => f.origin).toSet(), {'test.backoff'});

    // Data arrives on this stream, then it ends: the next re-open is 2 s.
    await endAndExpectReopenAfter(tester, const Duration(seconds: 2), value: 7);
    expect(values, [7]);
    // ...and a run of failures from there starts the doubling over.
    await endAndExpectReopenAfter(tester, const Duration(seconds: 4), error: true);
    await endAndExpectReopenAfter(tester, const Duration(seconds: 8), error: true);
  });

  testWidgets('the reset is on data, not on time: three failures, then data, '
      'then 2 s (not 16 s)', (tester) async {
    opened = [];
    final sub = reopenWhenDone<int>(open, origin: 'test.backoff')
        .listen((_) {}, onError: (_) {});
    addTearDown(sub.cancel);
    await tester.pump();
    await endAndExpectReopenAfter(tester, const Duration(seconds: 2), error: true);
    await endAndExpectReopenAfter(tester, const Duration(seconds: 4), error: true);
    await endAndExpectReopenAfter(tester, const Duration(seconds: 8), error: true);
    await endAndExpectReopenAfter(tester, const Duration(seconds: 2), value: 1);
  });

  testWidgets('control: cancelling stops the re-opens', (tester) async {
    opened = [];
    final sub = reopenWhenDone<int>(open, origin: 'test.backoff')
        .listen((_) {}, onError: (_) {});
    await tester.pump();
    await opened.last.close();
    await tester.pump();
    unawaited(sub.cancel());
    await tester.pump(const Duration(minutes: 5));
    expect(opened, hasLength(1));
  });
}
