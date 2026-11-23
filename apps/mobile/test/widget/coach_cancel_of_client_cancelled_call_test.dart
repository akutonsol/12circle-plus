import 'dart:convert';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/coach/presentation/coach_availability_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/row_checking_postgrest.dart';

// P0-FL-46 · Manage Availability › Cancel session on a call the CLIENT has
// already cancelled.
//
// At 185261e (after P0-FL-39) the coach's cancel filtered coaching_calls only
// by id. A call the client cancelled meanwhile still matched that row, so the
// update "changed" one row: the coach saw "Session cancelled — client
// notified." and the client got a second, false "Your coach had to cancel"
// notification for a session they cancelled themselves. The screen offers
// Cancel only for scheduled sessions, so the update now also requires
// `status = scheduled` (the same reasoning P0-FL-42 applied to the client's
// cancel); an already-cancelled call matches no row and takes the existing
// honest 0-row path.
//
// HOW TO SEE IT FAIL: `git checkout 185261e -- apps/mobile/lib/features/coach/
// presentation/coach_availability_screen.dart`; the first test fails.
//
// Review N2: both cancel failure notices (0-row and caught) are live regions,
// like Book a Call's. At 7f935d7 neither was; the first and third tests fail
// there.

const _uid = '00000000-0000-4000-8000-0000000c0046';

/// A PATCH on coaching_calls is answered as PostgREST would against a call
/// whose server-side status is [serverStatus]: a `status=eq.<x>` filter
/// matches only when x is that status; with no status filter the id matches.
class _Server extends RowCheckingPostgrest {
  _Server() : super(_uid);
  String serverStatus = 'scheduled';
  int callReads = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (request.method == 'GET' && path.endsWith('/coaching_calls')) {
      callReads++;
    }
    if (request.method == 'PATCH' &&
        path.endsWith('/coaching_calls') &&
        mode == WriteMode.oneRow) {
      final body = request is http.Request ? request.body : '';
      writes.add('PATCH $path?${request.url.query} $body');
      final status = request.url.queryParameters['status'];
      final matches = status == null || status == 'eq.$serverStatus';
      final asks = request.url.queryParameters.containsKey('select');
      if (!asks) {
        return http.StreamedResponse(const Stream.empty(), 204,
            request: request);
      }
      return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode(matches
              ? [
                  {'id': 'call-1'}
                ]
              : []))),
          200,
          request: request,
          headers: {'content-type': 'application/json'});
    }
    return super.send(request);
  }
}

String _inDays(int d) =>
    DateTime.now().toUtc().add(Duration(days: d)).toIso8601String();

void main() {
  final server = _Server();
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initSignedInSupabase(server);
  });

  setUp(() {
    server.reset();
    server.serverStatus = 'scheduled';
    server.callReads = 0;
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

  Future<void> openAndCancel(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: CoachAvailabilityScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Jo Ray'), findsOneWidget, reason: 'premise: one session');
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel session'));
    await tester.pumpAndSettle();
  }

  // The notice's OWN text is wrapped in a live region. Matching any
  // live-region ancestor is vacuous: the SnackBar route already supplies one
  // (an ancestor-only finder passed at 7f935d7, where the coach notices had
  // no wrapper), so this pins the app's wrapper directly around the Text.
  Finder liveRegionAround(String text) => find.byWidgetPredicate((w) =>
      w is Semantics &&
      w.properties.liveRegion == true &&
      w.child is Text &&
      (w.child! as Text).data == text);

  List<String> callWrites() =>
      server.writes.where((w) => w.contains('/rest/v1/coaching_calls')).toList();
  List<String> slotWrites() => server.writes
      .where((w) => w.contains('/rest/v1/coach_availability'))
      .toList();
  List<String> notifyWrites() =>
      server.writes.where((w) => w.contains('/rest/v1/notifications')).toList();

  testWidgets(
      'a call the client already cancelled: the 0-row path, no second '
      'notification, nothing reopened', (tester) async {
    // The screen loaded it as scheduled; the client cancels it meanwhile.
    server.serverStatus = 'cancelled';
    await openAndCancel(tester);
    final readsAfterLoad = server.callReads;

    expect(callWrites(), hasLength(1));
    expect(find.textContaining('Session cancelled'), findsNothing,
        reason: 'THE defect: an already-cancelled call matched the id-only '
            'update and was reported as cancelled by the coach');
    expect(notifyWrites(), isEmpty,
        reason: 'THE defect: the client was told their coach cancelled a '
            'session they cancelled themselves');
    expect(slotWrites(), isEmpty,
        reason: 'the slot step runs only after a confirmed cancel');
    expect(
        find.text("Couldn't cancel this session — it may already be "
            'cancelled. Refreshing your sessions.'),
        findsOneWidget);
    expect(reported.single.origin, 'CoachAvailabilityScreen._cancelSession');
    expect(callWrites().single, contains('status=eq.scheduled'),
        reason: 'only a still-scheduled call may be cancelled by the coach');
    expect(callWrites().single, contains('select=id'));
    expect(readsAfterLoad, greaterThanOrEqualTo(2),
        reason: 'the list is re-read so it shows what the server holds');
    // Review N2 · announced, like Book a Call's failure notices.
    expect(
        liveRegionAround("Couldn't cancel this session — it may already be "
            'cancelled. Refreshing your sessions.'),
        findsWidgets);
  });

  testWidgets(
      'a cancel the server rejects is said in the house voice and announced '
      '(review N2)', (tester) async {
    server.mode = WriteMode.serverError;
    server.modeAppliesTo = (w) => w.startsWith('PATCH /rest/v1/coaching_calls');
    await openAndCancel(tester);

    const failed = "Couldn't cancel this session — try again in a moment. If "
        'it keeps happening, contact support.';
    expect(find.text(failed), findsOneWidget);
    expect(liveRegionAround(failed), findsWidgets,
        reason: 'the catch-path failure notice was not a live region');
    expect(find.textContaining('Session cancelled'), findsNothing);
    expect(slotWrites(), isEmpty);
    expect(notifyWrites(), isEmpty);
    expect(reported.single.origin, 'CoachAvailabilityScreen._cancelSession');
  });

  testWidgets('control: a still-scheduled call is cancelled as before',
      (tester) async {
    await openAndCancel(tester);
    expect(callWrites().single, contains('"status":"cancelled"'));
    expect(slotWrites().single, contains('"is_booked":false'));
    expect(notifyWrites(), hasLength(1));
    expect(find.text('Session cancelled — client notified.'), findsOneWidget);
    expect(reported, isEmpty);
  });
}
