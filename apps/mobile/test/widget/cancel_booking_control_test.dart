import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/features/classes/domain/cancel_booking.dart';
import 'package:circle_fitness/features/classes/presentation/widgets/cancel_booking_control.dart';

// FIT-088 · "Cancellation — confirm → cancelled". The board marks this anchor
// `missing`, and it was: `/class-detail` cancelled on a single tap.
//
//   OutlinedButton(
//     onPressed: () async {
//       await ref.read(liveClassServiceProvider).cancelBooking(id);
//       ref.read(refreshClassesProvider.notifier).state++;
//       if (context.mounted) context.pop();
//     },
//     child: const Text('Cancel Booking'))
//
// No confirmation on an action that cannot be undone — cancelling frees the
// seat and `_promoteFromWaitlist` hands it straight to the next person, so a
// mis-tap does not merely cost the place, it gives it away. And the `await`
// was unguarded: a throw left the screen unchanged, still showing the user as
// booked, with nothing said either way.

Future<void> _pump(
  WidgetTester tester, {
  required Future<void> Function() onCancel,
  VoidCallback? onCancelled,
}) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(mainAxisSize: MainAxisSize.min, children: [
          CancelBookingControl(
            onCancel: onCancel,
            onCancelled: onCancelled ?? () {},
          ),
        ]),
      ),
    ));

void main() {
  testWidgets('the first tap asks; it does not cancel', (tester) async {
    var calls = 0;
    await _pump(tester, onCancel: () async => calls++);

    await tester.tap(find.text(cancelBookingLabel));
    await tester.pump();

    expect(calls, 0,
        reason: 'THE defect: one tap gave the place away, with the seat '
            'passed to the next person on the waitlist before the user could '
            'reconsider');
    expect(find.text(cancelConfirmTitle), findsOneWidget);
    expect(find.text(keepBookingLabel), findsOneWidget);
  });

  testWidgets('the confirm step says what actually happens', (tester) async {
    await _pump(tester, onCancel: () async {});
    await tester.tap(find.text(cancelBookingLabel));
    await tester.pump();

    // Not "are you sure?" — the seat does not sit empty waiting for a change
    // of mind.
    expect(find.text(cancelConfirmBody), findsOneWidget);
  });

  testWidgets('Keep it backs out and cancels nothing', (tester) async {
    var calls = 0;
    var cancelled = 0;
    await _pump(tester,
        onCancel: () async => calls++, onCancelled: () => cancelled++);

    await tester.tap(find.text(cancelBookingLabel));
    await tester.pump();
    await tester.tap(find.text(keepBookingLabel));
    await tester.pump();

    expect(calls, 0);
    expect(cancelled, 0);
    expect(find.text(cancelConfirmTitle), findsNothing);
    // And the way back in is still there.
    expect(find.text(cancelBookingLabel), findsOneWidget);
  });

  testWidgets('confirming cancels exactly once and reports it', (tester) async {
    var calls = 0;
    var cancelled = 0;
    await _pump(tester,
        onCancel: () async => calls++, onCancelled: () => cancelled++);

    await tester.tap(find.text(cancelBookingLabel));
    await tester.pump();
    // The sheet repeats the destructive action by name; this is the one
    // inside it.
    await tester.tap(find.text(cancelBookingLabel));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(cancelled, 1);
  });

  testWidgets('a second tap mid-flight does not cancel twice', (tester) async {
    var calls = 0;
    final gate = Completer<void>();
    await _pump(tester, onCancel: () async {
      calls++;
      await gate.future;
    });

    await tester.tap(find.text(cancelBookingLabel));
    await tester.pump();
    await tester.tap(find.text(cancelBookingLabel));
    await tester.pump();

    // In flight: both controls are inert.
    await tester.tap(find.text(keepBookingLabel), warnIfMissed: false);
    await tester.pump();
    expect(calls, 1);

    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('a failure is shown, and says the place is still theirs',
      (tester) async {
    var cancelled = 0;
    await _pump(tester,
        onCancel: () async => throw Exception('network'),
        onCancelled: () => cancelled++);

    await tester.tap(find.text(cancelBookingLabel));
    await tester.pump();
    await tester.tap(find.text(cancelBookingLabel));
    await tester.pumpAndSettle();

    expect(find.text(cancelFailedTitle), findsOneWidget,
        reason: 'the unguarded await left the screen unchanged — the user '
            'could not tell whether they still had a place');
    expect(find.text(cancelFailedBody), findsOneWidget);
    expect(find.text(cancelTryAgainLabel), findsOneWidget);
    expect(cancelled, 0,
        reason: 'a failed cancellation must not report itself as done');
  });

  testWidgets('Try again retries, and can succeed', (tester) async {
    var calls = 0;
    var cancelled = 0;
    await _pump(tester, onCancel: () async {
      calls++;
      if (calls == 1) throw Exception('network');
    }, onCancelled: () => cancelled++);

    await tester.tap(find.text(cancelBookingLabel));
    await tester.pump();
    await tester.tap(find.text(cancelBookingLabel));
    await tester.pumpAndSettle();
    expect(find.text(cancelTryAgainLabel), findsOneWidget);

    await tester.tap(find.text(cancelTryAgainLabel));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(cancelled, 1);
  });

  group('the copy is FIT-088\'s', () {
    test('the three controls the screen did not have', () {
      expect(cancelBookingLabel, 'Cancel place');
      expect(keepBookingLabel, 'Keep it');
      expect(cancelTryAgainLabel, 'Try again');
    });
  });
}
