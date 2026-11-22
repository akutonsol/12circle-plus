import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/booking/presentation/booking_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/row_checking_postgrest.dart';

// P0-FL-42 · a client's booking cancellation is confirmed before it is
// reported.
//
// `_cancelBooking` sent
//
//   coaching_calls.update({'status': 'cancelled'}).eq('id', call['id'])
//
// without asking for the row back. PostgREST answers a 0-row PATCH (already
// cancelled, not this client's call, RLS) with the same 204 as a saved one, so
// the screen said "Session cancelled." and notified the coach about a
// cancellation that never happened. A thrown failure said "Could not cancel.
// Try again." -- old voice, nothing recorded, the same words for a dropped
// connection and a server refusal. And the Cancel text stayed live while the
// update was in flight, so a second tap sent a second cancel.
//
// HOW TO SEE IT FAIL: put back df35d5f's booking_screen.dart; every test here
// fails.

const _uid = '00000000-0000-4000-8000-0000000fl042';
const _callId = 'call-1';

/// Counts the coaching_calls reads, so a test can see the screen re-read
/// after a cancel that did not happen.
class _Server extends RowCheckingPostgrest {
  _Server() : super(_uid);
  int callReads = 0;

  /// The call's status as the SERVER holds it, when it differs from what the
  /// screen loaded (e.g. the coach cancelled it meanwhile). When set, a PATCH
  /// on coaching_calls is answered as PostgREST would: a `status=eq.scheduled`
  /// filter matches no row; without that filter the row matches (and the
  /// already-cancelled call is "cancelled" again).
  String? serverStatus;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (request.method == 'GET' && path.endsWith('/coaching_calls')) {
      callReads++;
    }
    if (serverStatus != null &&
        request.method == 'PATCH' &&
        path.endsWith('/coaching_calls')) {
      final body = request is http.Request ? request.body : '';
      writes.add('PATCH $path?${request.url.query} $body');
      final status = request.url.queryParameters['status'];
      final matches = status == null || status == 'eq.$serverStatus';
      return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode(matches
              ? [
                  {'id': _callId}
                ]
              : []))),
          200,
          request: request,
          headers: {'content-type': 'application/json'});
    }
    return super.send(request);
  }
}

void _seed(_Server s) {
  final soon = DateTime.now().toUtc().add(const Duration(days: 2));
  s.reads['coach_client_relationships'] = [
    {
      'coach_id': 'coach-a',
      'status': 'active',
      'pending_at': null,
      'activated_at': '2026-10-01T00:00:00Z',
    },
  ];
  s.reads['public_profiles'] = [
    {
      'id': 'coach-a',
      'first_name': 'Avery',
      'last_name': 'Stone',
      'avatar_url': null,
      'coach_title': null,
      'coach_bio': null,
      'specialties': null,
    },
  ];
  s.reads['coach_availability'] = [
    {
      'id': 'slot-2',
      'coach_id': 'coach-a',
      'is_booked': false,
      'type': 'check_in',
      'duration_minutes': 30,
      'slot_time': soon.add(const Duration(days: 1)).toIso8601String(),
    },
  ];
  s.reads['coaching_calls'] = [
    {
      'id': _callId,
      'client_id': _uid,
      'coach_id': 'coach-a',
      'availability_slot_id': 'slot-1',
      'status': 'scheduled',
      'call_type': 'check_in',
      'duration_minutes': 30,
      'scheduled_at': soon.toIso8601String(),
    },
  ];
}

void main() {
  final server = _Server();
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initSignedInSupabase(server);
  });

  setUp(() {
    server.reset();
    server.callReads = 0;
    server.serverStatus = null;
    _seed(server);
    // Only the call update is failed; the notification (and anything else)
    // behaves normally, so each test sees the cancel's own check.
    server.modeAppliesTo = (w) => w.startsWith('PATCH /rest/v1/coaching_calls');
    reported.clear();
    setFailureSink(reported.add);
  });

  tearDown(resetFailureSink);

  List<String> callPatches() => server.writes
      .where((w) => w.startsWith('PATCH /rest/v1/coaching_calls'))
      .toList();
  List<String> notifications() => server.writes
      .where((w) => w.contains('/rest/v1/notifications'))
      .toList();

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> openScreen(WidgetTester tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: BookingScreen())));
    await settle(tester);
    expect(find.text('Your Upcoming Calls'), findsOneWidget);
  }

  Future<void> cancelAndConfirm(WidgetTester tester) async {
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel session'));
    await settle(tester);
  }

  /// Ends the test with no SnackBar timer pending.
  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  testWidgets('a cancel that changed no row is not reported as cancelled',
      (tester) async {
    server.mode = WriteMode.zeroRows;
    await openScreen(tester);
    final readsBefore = server.callReads;

    await cancelAndConfirm(tester);

    expect(callPatches(), hasLength(1));
    expect(callPatches().single, contains('select=id'),
        reason: 'without the row back a 0-row update answers 204, exactly '
            'like a saved one');
    expect(find.text('Session cancelled.'), findsNothing,
        reason: 'THE defect: a cancellation that never happened was reported '
            'as done');
    expect(
        find.text("Couldn't cancel this session — it may already be "
            'cancelled. Refreshing your sessions.'),
        findsOneWidget);
    expect(notifications(), isEmpty,
        reason: 'the coach was told about a cancellation that did not happen');
    expect(server.callReads, greaterThan(readsBefore),
        reason: 'the list is re-read so it shows what the server holds');
    expect(reported, isNotEmpty, reason: 'a 0-row cancel is a failure');
    expect(server.writes.where((w) => w.contains('coach_availability')),
        isEmpty,
        reason: 'the database reopens the slot (migration 187)');
    await drain(tester);
  });

  testWidgets('a dropped connection says so, records it, notifies no one',
      (tester) async {
    server.mode = WriteMode.network;
    await openScreen(tester);

    await cancelAndConfirm(tester);

    expect(
        find.text("Couldn't cancel this session — check your connection and "
            'try again.'),
        findsOneWidget);
    expect(find.text('Could not cancel. Try again.'), findsNothing);
    expect(find.text('Session cancelled.'), findsNothing);
    expect(notifications(), isEmpty);
    expect(reported.map((f) => f.origin),
        contains('BookingScreen._cancelBooking'));
    expect(
        find.ancestor(
            of: find.textContaining("Couldn't cancel"),
            matching: find.byWidgetPredicate(
                (w) => w is Semantics && w.properties.liveRegion == true)),
        findsWidgets,
        reason: 'a failure notice is announced (live region)');
    await drain(tester);
  });

  testWidgets('a server refusal is not called a connection problem',
      (tester) async {
    server.mode = WriteMode.serverError;
    await openScreen(tester);

    await cancelAndConfirm(tester);

    expect(
        find.text("Couldn't cancel this session — try again in a moment. If "
            'it keeps happening, contact support.'),
        findsOneWidget);
    expect(find.textContaining('connection'), findsNothing);
    expect(find.textContaining('refused'), findsNothing,
        reason: 'exception text is never shown');
    expect(find.text('Session cancelled.'), findsNothing);
    expect(notifications(), isEmpty);
    expect(reported.map((f) => f.origin),
        contains('BookingScreen._cancelBooking'));
    await drain(tester);
  });

  testWidgets('a confirmed cancel is said, the coach notified, list re-read',
      (tester) async {
    await openScreen(tester);
    final readsBefore = server.callReads;

    await cancelAndConfirm(tester);

    expect(callPatches().single, contains('select=id'),
        reason: 'success is reported only once the row is confirmed');
    expect(find.text('Session cancelled.'), findsOneWidget);
    expect(notifications(), hasLength(1));
    expect(server.callReads, greaterThan(readsBefore));
    expect(reported, isEmpty);
    await drain(tester);
  });

  testWidgets('a second tap while the cancel is in flight sends nothing',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await openScreen(tester);
      server.gate = Completer<void>();

      await cancelAndConfirm(tester);
      expect(callPatches(), hasLength(1));

      // A second tap and confirm, if the screen still offers them.
      if (find.text('Cancel').evaluate().isNotEmpty) {
        await tester.tap(find.text('Cancel'), warnIfMissed: false);
        await tester.pumpAndSettle();
      }
      if (find.text('Cancel session').evaluate().isNotEmpty) {
        await tester.tap(find.text('Cancel session'));
        await tester.pump();
      }
      expect(callPatches(), hasLength(1),
          reason: 'THE defect: the Cancel text stayed live and a second tap '
              'sent a second cancel');
      // In flight: the control is busy, and says so.
      expect(find.bySemanticsLabel('Cancelling session'), findsOneWidget);
    } finally {
      server.gate?.complete();
      await settle(tester);
      await drain(tester);
      semantics.dispose();
    }
  });

  // ── Review round (UX-F1/SEC-N1, lead mutant, QA, UX-F3, UX-F4) ──────────

  testWidgets(
      'a call the coach already cancelled is not cancelled again, and the '
      'coach is not notified twice', (tester) async {
    await openScreen(tester);
    // The screen still shows the call as scheduled; the coach has cancelled
    // it on the server meanwhile.
    server.serverStatus = 'cancelled';
    final readsBefore = server.callReads;

    await cancelAndConfirm(tester);

    expect(callPatches(), hasLength(1));
    expect(callPatches().single, contains('status=eq.scheduled'),
        reason: 'only a still-scheduled call may be cancelled by the client');
    expect(find.text('Session cancelled.'), findsNothing,
        reason: 'THE defect: an already-cancelled call matched the id-only '
            'update and was reported as cancelled by the client');
    expect(
        find.text("Couldn't cancel this session — it may already be "
            'cancelled. Refreshing your sessions.'),
        findsOneWidget);
    expect(notifications(), isEmpty,
        reason: 'the coach, who cancelled it, is not told the client did');
    expect(server.callReads, greaterThan(readsBefore));
    expect(reported, isNotEmpty);
    await drain(tester);
  });

  testWidgets(
      'two Cancel taps that both reach a confirm dialog send ONE update',
      (tester) async {
    await openScreen(tester);
    server.gate = Completer<void>();
    try {
      // Two activations of the control in one frame (a fast double tap, or
      // a pointer tap plus an accessibility action) before the dialog's
      // barrier is up: two confirm dialogs. Both pass the entry guard —
      // nothing is in flight yet — so only the guard AFTER the confirm can
      // stop the second cancel. (Pointer taps cannot model this: the
      // Navigator absorbs pointers as soon as a route is pushed.)
      final control = tester.widget<TextButton>(find.ancestor(
          of: find.text('Cancel'), matching: find.byType(TextButton)));
      control.onPressed!();
      control.onPressed!();
      await tester.pumpAndSettle();
      expect(find.text('Cancel session'), findsNWidgets(2));

      // Confirm the top dialog: its cancel goes out and is held in flight
      // (fixed pumps: the busy spinner never settles).
      await tester.tap(find.text('Cancel session').last);
      await settle(tester);
      expect(callPatches(), hasLength(1));

      // Confirm the other one while the first is still in flight.
      await tester.tap(find.text('Cancel session'));
      await settle(tester);
      expect(callPatches(), hasLength(1),
          reason: 'the post-confirm guard: a cancel already in flight is not '
              'sent a second time');
    } finally {
      server.gate?.complete();
      await settle(tester);
    }
    expect(notifications(), hasLength(1));
    await drain(tester);
  });

  testWidgets('after a failed cancel the Cancel control works again',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      server.mode = WriteMode.serverError;
      await openScreen(tester);

      await cancelAndConfirm(tester);
      expect(callPatches(), hasLength(1));
      expect(find.bySemanticsLabel('Cancelling session'), findsNothing,
          reason: 'a failed cancel does not leave the control busy');
      expect(find.bySemanticsLabel('Cancel this session'), findsOneWidget);

      // The server recovers; the client tries again from the same control.
      server.mode = WriteMode.oneRow;
      await tester.pump(const Duration(seconds: 5)); // let the notice go
      await cancelAndConfirm(tester);
      expect(callPatches(), hasLength(2),
          reason: 'the retry reached the server');
      expect(find.text('Session cancelled.'), findsOneWidget);
    } finally {
      await drain(tester);
      semantics.dispose();
    }
  });

  // UX-F3: the SnackBar already supplies the live region (this passes on
  // aa39f77 too); kept as a guard so a custom notice cannot drop it.
  testWidgets('"Session cancelled." is announced (live region)',
      (tester) async {
    await openScreen(tester);
    await cancelAndConfirm(tester);
    expect(
        find.ancestor(
            of: find.text('Session cancelled.'),
            matching: find.byWidgetPredicate(
                (w) => w is Semantics && w.properties.liveRegion == true)),
        findsWidgets);
    await drain(tester);
  });

  testWidgets('a session row with Cancel fits 320px at text scale 2.0',
      (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(320, 2400);
    addTearDown(tester.view.reset);
    // Booked calls show only beside at least one open slot, so a slot card
    // is on screen too. Its own overflow at this size (_SlotCard) is a
    // separate, recorded follow-up: every overflow is collected, and only
    // _SlotCard's are tolerated here.
    final overflows = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      // The deep form carries the creator chain (which widget overflowed).
      final text = details.toDiagnosticsNode().toStringDeep();
      if (text.contains('overflowed')) {
        overflows.add(text);
      } else {
        previous?.call(details);
      }
    };
    try {
      await tester.pumpWidget(ProviderScope(
          child: MaterialApp(
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(2.0)),
                  child: child!),
              home: const BookingScreen())));
      await settle(tester);
    } finally {
      FlutterError.onError = previous;
    }

    expect(find.text('Cancel'), findsOneWidget);
    expect(overflows.where((o) => !o.contains('_SlotCard')), isEmpty,
        reason: 'no RenderFlex overflow in the session row or the section '
            'headers');
    // The control stays a whole 44px target inside the 320px viewport.
    final r = tester.getRect(find.ancestor(
        of: find.text('Cancel'), matching: find.byType(TextButton)));
    expect(r.right, lessThanOrEqualTo(320));
    expect(r.height, greaterThanOrEqualTo(44));
    await drain(tester);
  });

  testWidgets('the Cancel control is labelled and at least 44px',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await openScreen(tester);
      final control = find.bySemanticsLabel('Cancel this session');
      expect(control, findsOneWidget);
      final size = tester.getSize(control);
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
      // A screen reader can press it.
      expect(
          tester
              .getSemantics(control)
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isTrue);
    } finally {
      await drain(tester);
      semantics.dispose();
    }
  });
}
