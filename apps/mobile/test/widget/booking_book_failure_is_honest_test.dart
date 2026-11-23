import 'dart:convert';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/booking/presentation/booking_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/row_checking_postgrest.dart';

// P0-FL-46 · Book a Call › Book: a failed booking says what happened.
//
// At 185261e `_book` caught every failure other than a taken slot (23505) and
// said "Could not book — please try again." It recorded nothing, gave the same
// words for a dropped connection and a server refusal, and told a client the
// database REFUSED (42501 — row-level security, or migration 195's
// Coach-Guided check once it is applied) to "try again", which can never
// work. Now:
//
//   * connection failure → "Couldn't book this session — check your
//     connection and try again." (the shared isNetworkFailure rule)
//   * any other server answer → "… try again in a moment. If it keeps
//     happening, contact support."
//   * 42501 → "… this booking isn't available for your account. If you think
//     this is wrong, contact support." Neither a connection problem nor
//     "try again", and no claim about WHY (that is the owner's rule, not the
//     app's to restate): the screen is already behind the Coach-Guided
//     paywall, so the plan surface is not the honest pointer.
//   * 23505 (slot taken) → unchanged: "That time was just taken — pick
//     another." and the list is re-read.
//
// Every one of them is recorded (reportError) except the taken slot, which is
// an expected answer, not a fault; the failure notices are live regions.
//
// It also proves _SlotCard fits 320px at text scale 2.0 (it overflowed at
// 185261e; the FL-42 test tolerated that), and at 1.0, 1.3 and 1.35 — either
// side of the scale > 1.3 stacking threshold (review N1).
//
// HOW TO SEE IT FAIL: `git checkout 185261e -- apps/mobile/lib/features/
// booking/presentation/booking_screen.dart`; every test but the 23505
// control fails.

const _uid = '00000000-0000-4000-8000-0000000fl046';

const _offline =
    "Couldn't book this session — check your connection and try again.";
const _failed = "Couldn't book this session — try again in a moment. If it "
    'keeps happening, contact support.';
const _refused = "Couldn't book this session — this booking isn't available "
    'for your account. If you think this is wrong, contact support.';
const _taken = 'That time was just taken — pick another.';

/// Answers the call INSERT with a chosen PostgREST error (status + code).
class _Server extends RowCheckingPostgrest {
  _Server() : super(_uid);

  /// When set, a POST to coaching_calls is refused with this (status, code).
  (int, String)? refuseBooking;
  int slotReads = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (request.method == 'GET' && path.endsWith('/coach_availability')) {
      slotReads++;
    }
    final refuse = refuseBooking;
    if (refuse != null &&
        request.method == 'POST' &&
        path.endsWith('/coaching_calls')) {
      final body = request is http.Request ? request.body : '';
      writes.add('POST $path?${request.url.query} $body');
      return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode({
            'code': refuse.$2,
            'message': 'refused by the server',
            'details': null,
            'hint': null,
          }))),
          refuse.$1,
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
      'id': 'slot-1',
      'coach_id': 'coach-a',
      'is_booked': false,
      'type': 'check_in',
      'duration_minutes': 30,
      'slot_time': soon.toIso8601String(),
    },
  ];
  s.reads['coaching_calls'] = <Object>[];
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
    server.refuseBooking = null;
    server.slotReads = 0;
    _seed(server);
    // Only the booking insert is failed; the coach notification behaves.
    server.modeAppliesTo = (w) => w.startsWith('POST /rest/v1/coaching_calls');
    reported.clear();
    setFailureSink(reported.add);
  });

  tearDown(resetFailureSink);

  List<String> bookings() => server.writes
      .where((w) => w.startsWith('POST /rest/v1/coaching_calls'))
      .toList();
  List<String> notifications() => server.writes
      .where((w) => w.contains('/rest/v1/notifications'))
      .toList();

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> openAndBook(WidgetTester tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: BookingScreen())));
    await settle(tester);
    expect(find.text('Book'), findsOneWidget, reason: 'premise: one open slot');
    await tester.tap(find.text('Book'));
    await settle(tester);
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  Finder liveRegionAround(String text) => find.ancestor(
      of: find.text(text),
      matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.liveRegion == true));

  testWidgets('a dropped connection says so, is recorded, notifies no one',
      (tester) async {
    server.mode = WriteMode.network;
    await openAndBook(tester);

    expect(bookings(), hasLength(1));
    expect(find.text(_offline), findsOneWidget);
    expect(find.text('Could not book — please try again.'), findsNothing);
    expect(find.textContaining('Call booked'), findsNothing);
    expect(notifications(), isEmpty);
    expect(reported.map((f) => f.origin), contains('BookingScreen._book'),
        reason: 'THE defect: a failed booking was never recorded');
    expect(liveRegionAround(_offline), findsWidgets,
        reason: 'a failure notice is announced');
    expect(find.text('Book'), findsOneWidget,
        reason: 'the slot stays bookable; the control is not left busy');
    expect(tester.widget<SnackBar>(find.byType(SnackBar)).duration,
        const Duration(seconds: 4),
        reason: 'control: only the refusal is held longer');
    await drain(tester);
  });

  testWidgets('a server failure is not called a connection problem',
      (tester) async {
    server.mode = WriteMode.serverError;
    await openAndBook(tester);

    expect(find.text(_failed), findsOneWidget);
    expect(find.textContaining('connection'), findsNothing);
    expect(find.textContaining('refused'), findsNothing,
        reason: 'exception text is never shown');
    expect(find.textContaining('Call booked'), findsNothing);
    expect(notifications(), isEmpty);
    expect(reported.map((f) => f.origin), contains('BookingScreen._book'));
    await drain(tester);
  });

  testWidgets(
      'a refusal (42501) is neither a connection problem nor "try again"',
      (tester) async {
    server.refuseBooking = (403, '42501');
    await openAndBook(tester);

    expect(bookings(), hasLength(1));
    expect(find.text(_refused), findsOneWidget);
    expect(find.textContaining('connection'), findsNothing);
    expect(find.textContaining('try again'), findsNothing,
        reason: 'THE defect: a refusal that cannot succeed said "please try '
            'again"');
    expect(find.textContaining('refused'), findsNothing);
    expect(find.textContaining('Call booked'), findsNothing);
    expect(notifications(), isEmpty);
    expect(reported.map((f) => f.origin), contains('BookingScreen._book'));
    expect(liveRegionAround(_refused), findsWidgets);
    // Review N5 · the refusal is long and offers no retry; the default 4 s
    // was too short to read it.
    expect(tester.widget<SnackBar>(find.byType(SnackBar)).duration,
        const Duration(seconds: 8));
    await drain(tester);
  });

  testWidgets('control: a taken slot (23505) still says pick another and '
      're-reads the list', (tester) async {
    server.refuseBooking = (409, '23505');
    await openAndBook(tester);
    final readsAfter = server.slotReads;

    expect(find.text(_taken), findsOneWidget);
    expect(find.textContaining("Couldn't book"), findsNothing);
    expect(readsAfter, greaterThanOrEqualTo(2),
        reason: 'the list is re-read to show what is free');
    expect(notifications(), isEmpty);
    await drain(tester);
  });

  testWidgets('control: a saved booking is said and the coach notified',
      (tester) async {
    await openAndBook(tester);
    expect(find.text('Call booked! Your coach has been notified.'),
        findsOneWidget);
    expect(notifications(), hasLength(1));
    expect(reported, isEmpty);
    await drain(tester);
  });

  // P0-FL-46 review N1 · 2.0 is far past the stacking threshold (scale >
  // 1.3). The scales either side of it are pinned too: 1.0 and 1.3 keep the
  // one-row layout, 1.35 is the first that stacks. None may overflow at 320.
  for (final scale in [1.0, 1.3, 1.35, 2.0]) {
    testWidgets('a slot card fits 320px at text scale $scale with no overflow',
        (tester) async {
      await expectSlotCardFits(tester, scale);
    });
  }
}

/// Pumps Book a Call at 320 logical px and [scale], and proves the slot card
/// has no overflow and Book is a whole >= 44px target inside the viewport.
/// Also pins WHICH layout ran, so a test at 1.35 really covers the stacked one.
Future<void> expectSlotCardFits(WidgetTester tester, double scale) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(320, 2400);
  addTearDown(tester.view.reset);
  final overflows = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
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
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: const BookingScreen())));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  } finally {
    FlutterError.onError = previous;
  }

  expect(find.text('Book'), findsOneWidget, reason: 'premise: a slot card');
  expect(overflows, isEmpty,
      reason: 'THE defect: _SlotCard overflowed at 2x on 320px; no scale '
          'either side of the stacking threshold may overflow');
  // Book stays a whole target inside the viewport.
  final r = tester.getRect(find.ancestor(
      of: find.text('Book'), matching: find.byType(ElevatedButton)));
  expect(r.left, greaterThanOrEqualTo(0));
  expect(r.right, lessThanOrEqualTo(320));
  expect(r.height, greaterThanOrEqualTo(44));
  expect(r.width, greaterThanOrEqualTo(44));
  // Which layout: one row up to 1.3, Book under the details past it.
  final details = tester.getRect(find.text('30 minutes · Video call'));
  if (scale > 1.3) {
    expect(r.top, greaterThan(details.bottom),
        reason: 'past 1.3 Book moves under the details');
  } else {
    expect(r.left, greaterThanOrEqualTo(details.right),
        reason: 'up to 1.3 the row is unchanged: Book beside the details');
  }
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}
