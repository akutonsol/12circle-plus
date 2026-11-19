import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/coach/presentation/coach_availability_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/row_checking_postgrest.dart';

// P0-FL-39 · Manage Availability › Cancel session: two writes, each confirmed.
//
// At 6f8918f `_cancelSession` sent the coaching_calls status update and the
// coach_availability `is_booked` update without `.select('id')`. A 0-row
// update (RLS filtered it, or the call was already gone) answers 204 exactly
// like a saved one, so a cancel that changed NOTHING said "Session cancelled
// — client notified." and told the client their session was cancelled. A
// thrown failure said "Could not cancel. Try again." (not the house voice,
// never reported), and a slot that failed to reopen AFTER the call was
// cancelled was reported as "Could not cancel" — false: the call was
// cancelled.
//
// What the coach is told now:
//   * call update fails (throw or 0 rows) → "Couldn't cancel this session —
//     …"; nothing else is written, the client is not notified, the session
//     stays listed.
//   * call update saved, slot update fails → the session IS cancelled and the
//     client is notified (best-effort, as before); the coach is told the slot
//     could not be reopened, with a "Reopen slot" retry that re-sends only the
//     slot update.
//
// HOW TO SEE IT FAIL: with 6f8918f's coach_availability_screen.dart the
// 0-row tests show "Session cancelled — client notified." and post the client
// notification, and the PATCHes carry no `select=id`.

const _uid = '00000000-0000-4000-8000-0000000f1394';
const _cancelOffline =
    "Couldn't cancel this session — check your connection and try again.";
const _cancelFailed = "Couldn't cancel this session — try again in a moment. "
    'If it keeps happening, contact support.';
const _cancelGone = "Couldn't cancel this session — it may already be "
    'cancelled. Refreshing your sessions.';
const _slotFailed = "Session cancelled — client notified. Couldn't reopen its "
    'slot — tap Reopen slot to try again. If it keeps happening, contact '
    'support.';
const _slotOffline = "Session cancelled — client notified. Couldn't reopen its "
    'slot — check your connection and tap Reopen slot.';

String _inDays(int d) =>
    DateTime.now().toUtc().add(Duration(days: d)).toIso8601String();

void main() {
  late RowCheckingPostgrest server;
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = RowCheckingPostgrest(_uid);
    await initSignedInSupabase(server);
  });

  setUp(() {
    server.reset();
    server.reads['coach_availability'] = [
      {
        'id': 'slot-1',
        'coach_id': _uid,
        'slot_time': _inDays(2),
        'duration_minutes': 30,
        'type': 'check_in',
        'is_booked': true,
      }
    ];
    server.reads['coaching_calls'] = [
      {
        'id': 'call-1',
        'scheduled_at': _inDays(2),
        'duration_minutes': 30,
        'call_type': 'check_in',
        'status': 'scheduled',
        'availability_slot_id': 'slot-1',
        'client_id': 'client-1',
        'client': {'first_name': 'Jo', 'last_name': 'Ray', 'avatar_url': null},
      }
    ];
    reported.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: CoachAvailabilityScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Jo Ray'), findsOneWidget, reason: 'premise: one session');
  }

  Future<void> cancelSession(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel session'));
    await tester.pumpAndSettle();
  }

  List<String> callWrites() =>
      server.writes.where((w) => w.contains('/rest/v1/coaching_calls')).toList();
  List<String> slotWrites() => server.writes
      .where((w) => w.contains('/rest/v1/coach_availability'))
      .toList();
  List<String> notifyWrites() =>
      server.writes.where((w) => w.contains('/rest/v1/notifications')).toList();

  bool onCalls(String w) => w.contains('/rest/v1/coaching_calls');
  bool onSlots(String w) => w.contains('/rest/v1/coach_availability');

  group('step 1 · the call update', () {
    testWidgets('0 rows: not "Session cancelled"; nothing else written, the '
        'client is not notified, reported', (tester) async {
      await open(tester);
      server.mode = WriteMode.zeroRows;
      server.modeAppliesTo = onCalls;
      await cancelSession(tester);

      expect(callWrites().single, contains('select=id'),
          reason: 'the update must ask for its row back to see 0 rows');
      expect(callWrites().single, contains('"status":"cancelled"'));
      expect(find.textContaining('Session cancelled'), findsNothing,
          reason: 'THE defect: a cancel that changed nothing said it was done');
      expect(notifyWrites(), isEmpty,
          reason: 'THE defect: the client was told of a cancel that did not '
              'happen');
      expect(slotWrites(), isEmpty, reason: 'no slot reopened under a live call');
      expect(find.text(_cancelGone), findsOneWidget);
      expect(reported.single.origin, 'CoachAvailabilityScreen._cancelSession');
    });

    testWidgets('server error: house voice, no connection hint, session '
        'still listed', (tester) async {
      await open(tester);
      server.mode = WriteMode.serverError;
      server.modeAppliesTo = onCalls;
      await cancelSession(tester);
      expect(find.text(_cancelFailed), findsOneWidget);
      expect(find.textContaining('Could not cancel'), findsNothing);
      expect(find.textContaining('refused'), findsNothing);
      expect(find.text('Jo Ray'), findsOneWidget, reason: 'not shown cancelled');
      expect(notifyWrites(), isEmpty);
      expect(slotWrites(), isEmpty);
      expect(reported, hasLength(1));
    });

    testWidgets('connection failure: the connection hint', (tester) async {
      await open(tester);
      server.mode = WriteMode.network;
      server.modeAppliesTo = onCalls;
      await cancelSession(tester);
      expect(find.text(_cancelOffline), findsOneWidget);
      expect(find.text('Jo Ray'), findsOneWidget);
      expect(notifyWrites(), isEmpty);
      expect(reported, hasLength(1));
    });
  });

  group('step 2 · the slot reopen, after the call was cancelled', () {
    testWidgets('0 rows: said as cancelled-but-slot-not-reopened, never as '
        'a failed cancel; a Reopen slot retry re-sends only the slot',
        (tester) async {
      await open(tester);
      server.mode = WriteMode.zeroRows;
      server.modeAppliesTo = onSlots;
      await cancelSession(tester);

      expect(slotWrites().single, contains('select=id'));
      expect(slotWrites().single, contains('"is_booked":false'));
      expect(notifyWrites(), hasLength(1),
          reason: 'the cancel IS saved, so the client is told');
      expect(find.text(_slotFailed), findsOneWidget,
          reason: 'THE defect: a slot left booked passed as reopened');
      expect(find.text('Session cancelled — client notified.'), findsNothing);
      expect(reported.single.origin,
          'CoachAvailabilityScreen._cancelSession.reopenSlot');

      // The retry: one slot write, no second call update or notification.
      server.mode = WriteMode.oneRow;
      await tester.tap(find.text('Reopen slot'));
      await tester.pumpAndSettle();
      expect(slotWrites(), hasLength(2));
      expect(callWrites(), hasLength(1));
      expect(notifyWrites(), hasLength(1));
      expect(find.text('Slot reopened.'), findsOneWidget);
    });

    testWidgets('connection failure: the connection hint, still cancelled',
        (tester) async {
      await open(tester);
      server.mode = WriteMode.network;
      server.modeAppliesTo = onSlots;
      await cancelSession(tester);
      expect(find.text(_slotOffline), findsOneWidget);
      expect(reported, hasLength(1));
    });
  });

  testWidgets('control: both writes confirmed → unchanged success copy, the '
      'same keys, the client notified', (tester) async {
    await open(tester);
    await cancelSession(tester);
    expect(callWrites().single, contains('"status":"cancelled"'));
    expect(slotWrites().single, contains('"is_booked":false'));
    expect(notifyWrites(), hasLength(1));
    expect(find.text('Session cancelled — client notified.'), findsOneWidget);
    expect(find.textContaining("Couldn't"), findsNothing);
    expect(reported, isEmpty);
  });
}
