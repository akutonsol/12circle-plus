import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/vendor/presentation/vendor_portal_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/account_app.dart';

// P0-FL-59a round 4 — the vendor portal belongs to the account it was drawn
// for (sec B1, ux blocking 1, 59f's in-flight finding).
//
// Mounted WITHOUT AccountScope, across real auth transitions: a hidden web tab
// draws no frame, and a write already out is not stopped by a remount.
//
// - riverpod 2.6.1 does not tell a screen when a refresh already in flight
//   (AsyncData, isLoading) is restarted for another account: A's attendees
//   stayed drawn for B, also after frames.
// - Every vendor write read the uid at the moment it was sent: A's New Event
//   draft, saved after B signed in, was inserted with vendor_id = B.
// - A 0-row update or delete was a success; a thrown one was said nowhere.

final _server = AccountServer();
final _realtime = FakeRealtime();
final _store = MemoryStore();
final _failures = <AppFailure>[];

GoTrueClient get _auth => Supabase.instance.client.auth;

Iterable<AppFailure> get _changed =>
    _failures.where((f) => '${f.error}'.contains('account changed'));

Iterable<Sent> get _writes => _server.sent.where((s) =>
    s.method != 'GET' &&
    !s.url.path.startsWith('/auth/') &&
    !s.url.path.contains('/rpc/'));

const _networkHint = 'check your connection and try again.';
const _otherHint =
    'try again in a moment. If it keeps happening, contact support.';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await initAccountSupabase(_server, _realtime, _store);
    _auth.onAuthStateChange.listen((_) {}, onError: (Object _) {});
  });

  setUp(() {
    _server.reset();
    _failures.clear();
    setFailureSink(_failures.add);
    addTearDown(resetFailureSink);
    for (final (uid, ev, title, reg, att, first) in [
      (acctA, 'ev-a', 'Alba Bootcamp', 'reg-a', 'att-1', 'Ada'),
      (acctB, 'ev-b', 'Bruno Yoga', 'reg-b', 'att-2', 'Bea'),
    ]) {
      _server.rows['events:$uid'] = [
        {
          'id': ev,
          'vendor_id': uid,
          'title': title,
          'event_date': '2026-12-05T09:00:00Z',
          'is_free': true,
          'price': 0,
          'event_registrations': [
            {'count': 1}
          ],
        }
      ];
      _server.rows['event_registrations:$uid'] = [
        {
          'id': reg,
          'event_id': ev,
          'user_id': att,
          'status': 'registered',
          'checked_in_at': null,
          'registered_at': '2026-11-20T10:00:00Z',
        }
      ];
      _server.rows['event_attendee_profiles:$uid'] = [
        {'id': att, 'first_name': first, 'last_name': 'Attendee', 'email': '$first@x.test'}
      ];
    }
  });

  Future<void> mount(WidgetTester t) async {
    t.view.physicalSize = const Size(900, 2000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.runAsync(signOut);
    await t.runAsync(() => signInAs(acctA));
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const VendorPortalScreen()),
      GoRoute(
          path: '/login',
          builder: (_, __) => const Scaffold(body: Text('SIGN-IN'))),
    ]);
    addTearDown(router.dispose);
    await t.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)));
    await settleApp(t, 4);
    expect(find.text('Alba Bootcamp'), findsOneWidget, reason: 'premise');
  }

  Future<void> end(WidgetTester t) async {
    for (final h in _server.holds.values) {
      if (!h.isCompleted) h.complete();
    }
    await settleApp(t, 2);
    await t.pumpWidget(const SizedBox());
    await t.runAsync(signOut);
    await t.pump(const Duration(seconds: 5));
  }

  Future<void> openAttendees(WidgetTester t) async {
    await t.tap(find.text('Alba Bootcamp'));
    await settleApp(t, 6);
    expect(find.text('Ada Attendee'), findsOneWidget, reason: 'premise');
  }

  Future<void> pullToRefresh(WidgetTester t) async {
    // The screen's own RefreshIndicator, as a pull runs it.
    unawaited(t
        .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
        .show());
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    await settleApp(t, 2);
  }

  Finder snack(String text) =>
      find.descendant(of: find.byType(SnackBar), matching: find.text(text));

  // ── 1. Attendees ─────────────────────────────────────────────────────────

  group("attendees: A's re-read is in flight when B signs in", () {
    Future<Completer<void>> inFlight(WidgetTester t) async {
      await mount(t);
      await openAttendees(t);
      final hold =
          _server.holds['GET event_registrations:$acctA'] = Completer<void>();
      await t.tap(find.text('Check in'));
      await settleApp(t, 3);
      expect(_writes.map((s) => s.key), ['PATCH event_registrations:$acctA'],
          reason: 'premise: the check-in was saved');
      expect(_server.of('event_registrations', method: 'GET', by: acctA),
          hasLength(2), reason: 'premise: the re-read is out');
      expect(find.text('Ada Attendee'), findsOneWidget,
          reason: 'premise: rows kept while it reads');
      return hold;
    }

    testWidgets('with frames: none of A is drawn, nothing read as B with '
        "A's event", (t) async {
      final hold = await inFlight(t);
      await t.runAsync(() => signInAs(acctB));
      await settleApp(t);
      expect(find.text('Ada Attendee'), findsNothing,
          reason: "THE defect: A's attendee list drawn for B");
      expect(find.text('Alba Bootcamp'), findsNothing);
      hold.complete();
      await settleApp(t);
      expect(find.text('Ada Attendee'), findsNothing,
          reason: "A's late answer is not drawn either");
      expect(_server.of('event_registrations', by: acctB), isEmpty);
      expect(_server.of('event_attendee_profiles', by: acctB), isEmpty);
      await end(t);
    });

    testWidgets("with no frame: A's drawn check-in, tapped, sends nothing",
        (t) async {
      final hold = await inFlight(t);
      hold.complete();
      await settleApp(t, 3);
      _server.sent.clear();
      await t.runAsync(() async {
        await signInAs(acctB);
        await Future<void>.delayed(const Duration(milliseconds: 5));
      });
      // No frame since B signed in: A's row is what is hit.
      await t.tap(find.text('Check in'), warnIfMissed: false);
      await settleApp(t);
      expect(_writes, isEmpty,
          reason: "THE defect: A's row checked in on B's token");
      expect(_changed.map((f) => f.origin),
          contains('EventAttendeesScreen.setCheckedIn'));
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Ada Attendee'), findsNothing);
      await end(t);
    });

    testWidgets('signed out: none of A is drawn', (t) async {
      final hold = await inFlight(t);
      await t.runAsync(signOut);
      await settleApp(t);
      expect(find.text('Ada Attendee'), findsNothing);
      hold.complete();
      await settleApp(t);
      expect(find.text('Ada Attendee'), findsNothing);
      await end(t);
    });
  });

  testWidgets('attendees, control: a token refresh keeps the rows, with no '
      're-read', (t) async {
    await mount(t);
    await openAttendees(t);
    final reads = _server.of('event_registrations').length;
    await t.runAsync(renewToken);
    await settleApp(t);
    expect(find.text('Ada Attendee'), findsOneWidget);
    expect(_server.of('event_registrations'), hasLength(reads));
    await end(t);
  });

  testWidgets('attendees, control: a failed re-read keeps the rows and says so',
      (t) async {
    await mount(t);
    await openAttendees(t);
    _server.fails['GET event_registrations:$acctA'] = 500;
    await t.tap(find.text('Check in'));
    await settleApp(t);
    expect(find.text('Ada Attendee'), findsOneWidget);
    expect(find.text("Couldn't load attendees"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    _server.fails.clear();
    await t.tap(find.text('Try again'));
    await settleApp(t);
    expect(find.text("Couldn't load attendees"), findsNothing);
    expect(find.text('Ada Attendee'), findsOneWidget);
    await end(t);
  });

  testWidgets('attendees, control: back as A after B, A sees its own rows',
      (t) async {
    await mount(t);
    await openAttendees(t);
    await t.runAsync(() => signInAs(acctB));
    await settleApp(t);
    expect(find.text('Ada Attendee'), findsNothing, reason: 'premise');
    await t.runAsync(() => signInAs(acctA));
    await settleApp(t);
    expect(find.text('Ada Attendee'), findsOneWidget);
    await end(t);
  });

  // ── 1. The events list ───────────────────────────────────────────────────

  for (final b in ['pending', 'failed', 'answered']) {
    testWidgets("events: A's refresh in flight, then B signs in — B's read "
        '$b, A never drawn', (t) async {
      await mount(t);
      final holdA = _server.holds['GET events:$acctA'] = Completer<void>();
      await pullToRefresh(t);
      expect(_server.of('events', method: 'GET', by: acctA), hasLength(2),
          reason: "premise: A's refresh is out");
      expect(find.text('Alba Bootcamp'), findsOneWidget, reason: 'premise');
      final holdB = Completer<void>();
      if (b == 'pending') _server.holds['GET events:$acctB'] = holdB;
      if (b == 'failed') _server.fails['GET events:$acctB'] = 500;
      await t.runAsync(() => signInAs(acctB));
      await settleApp(t);
      expect(find.text('Alba Bootcamp'), findsNothing,
          reason: "THE defect: A's events drawn for B");
      switch (b) {
        case 'pending':
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
        case 'failed':
          expect(find.text("Couldn't load your events"), findsOneWidget);
          expect(find.text('Bruno Yoga'), findsNothing);
        case 'answered':
          expect(find.text('Bruno Yoga'), findsOneWidget);
      }
      holdA.complete();
      await settleApp(t);
      expect(find.text('Alba Bootcamp'), findsNothing);
      await end(t);
    });
  }

  testWidgets('events, control: a failed pull to refresh keeps the rows and '
      'says so', (t) async {
    await mount(t);
    _server.fails['GET events:$acctA'] = 500;
    await pullToRefresh(t);
    await settleApp(t);
    expect(find.text('Alba Bootcamp'), findsOneWidget);
    expect(find.text("Couldn't load your events"), findsOneWidget);
    expect(_failures.map((f) => f.origin), contains('myEventsProvider'));
    await end(t);
  });

  testWidgets('events, control: a token refresh keeps the rows', (t) async {
    await mount(t);
    await t.runAsync(renewToken);
    await settleApp(t);
    expect(find.text('Alba Bootcamp'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await end(t);
  });

  testWidgets('events, negative control: a vendor with no events sees the '
      'empty state, no failure', (t) async {
    _server.rows['events:$acctA'] = [];
    t.view.physicalSize = const Size(900, 2000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.runAsync(signOut);
    await t.runAsync(() => signInAs(acctA));
    await t.pumpWidget(
        const ProviderScope(child: MaterialApp(home: VendorPortalScreen())));
    await settleApp(t, 4);
    expect(find.textContaining('No events yet'), findsOneWidget);
    expect(find.textContaining("Couldn't"), findsNothing);
    expect(_failures, isEmpty);
    await end(t);
  });

  // ── 2. Writes ────────────────────────────────────────────────────────────

  Future<void> openNewEvent(WidgetTester t, String title) async {
    await t.tap(find.text('New Event'));
    await settleApp(t, 10);
    await t.enterText(find.byType(TextField).first, title);
    await t.pump();
  }

  VoidCallback createPress(WidgetTester t) => t
      .widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Create event'))
      .onPressed!;

  group("New Event: A's draft is never inserted for B", () {
    testWidgets('pressed after the switch, before anyone heard of it',
        (t) async {
      await mount(t);
      await openNewEvent(t, 'Alba Draft');
      final create = createPress(t);
      await t.runAsync(() async {
        unawaited(signInAs(acctB)); // the session is B's at once
        create();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await settleApp(t);
      expect(_writes, isEmpty,
          reason: "THE defect: A's draft inserted with vendor_id = B");
      expect(_changed.map((f) => f.origin),
          contains('VendorPortalScreen.createEvent'));
      expect(find.text('Alba Draft'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      await end(t);
    });

    testWidgets('tapped with no frame after B signed in', (t) async {
      await mount(t);
      await openNewEvent(t, 'Alba Draft');
      await t.runAsync(() async {
        await signInAs(acctB);
        await Future<void>.delayed(const Duration(milliseconds: 5));
      });
      await t.tap(find.text('Create event'), warnIfMissed: false);
      await settleApp(t);
      expect(_writes, isEmpty);
      expect(_changed, isNotEmpty);
      expect(find.text('Alba Draft'), findsNothing,
          reason: "A's sheet is not drawn for B");
      expect(find.text('Bruno Yoga'), findsOneWidget,
          reason: "B's portal is usable: the sheet is gone");
      await end(t);
    });

    testWidgets("with frames: A's sheet is closed and not drawn for B",
        (t) async {
      await mount(t);
      await openNewEvent(t, 'Alba Draft');
      await t.runAsync(() => signInAs(acctB));
      await settleApp(t);
      expect(find.text('Alba Draft'), findsNothing);
      expect(find.text('Create event'), findsNothing);
      expect(_writes, isEmpty);
      await end(t);
    });

    for (final outcome in ['saved', 'refused']) {
      testWidgets('the insert answers ($outcome) after B signed in: nothing is '
          'said to B', (t) async {
        await mount(t);
        await openNewEvent(t, 'Alba Draft');
        final hold = _server.holds['POST events:$acctA'] = Completer<void>();
        if (outcome == 'refused') _server.fails['POST events:$acctA'] = 500;
        await t.tap(find.text('Create event'));
        await settleApp(t, 3);
        expect(_writes.map((s) => s.key), ['POST events:$acctA']);
        expect(_writes.single.body, contains('"vendor_id":"$acctA"'));
        await t.runAsync(() => signInAs(acctB));
        await settleApp(t, 3);
        hold.complete();
        await settleApp(t);
        expect(find.byType(SnackBar), findsNothing);
        expect(_writes, hasLength(1));
        expect(
            _failures.where((f) => '${f.error}'.contains('answered after')),
            hasLength(1));
        await end(t);
      });
    }
  });

  testWidgets('New Event, control: the same vendor, through a token refresh, '
      'inserts once, stamped with its own id', (t) async {
    await mount(t);
    await openNewEvent(t, 'Alba Draft');
    await t.runAsync(renewToken);
    await settleApp(t, 3);
    expect(find.text('Alba Draft'), findsOneWidget, reason: 'draft kept');
    await t.tap(find.text('Create event'));
    await settleApp(t);
    expect(_writes.map((s) => s.key), ['POST events:$acctA']);
    expect(_writes.single.body, contains('"vendor_id":"$acctA"'));
    expect(_writes.single.body, contains('Alba Draft'));
    expect(_server.of('events', method: 'GET', by: acctA), hasLength(2),
        reason: 're-read after the save');
    expect(find.byType(SnackBar), findsNothing);
    expect(_failures, isEmpty);
    await end(t);
  });

  testWidgets('New Event, control: swiping the sheet away sends nothing, '
      'records nothing', (t) async {
    await mount(t);
    await openNewEvent(t, 'Alba Draft');
    await t.tapAt(const Offset(10, 10)); // the barrier
    await settleApp(t);
    expect(find.text('Create event'), findsNothing);
    expect(_writes, isEmpty);
    expect(_failures, isEmpty);
    await end(t);
  });

  testWidgets('New Event: a refused insert is recorded and said', (t) async {
    await mount(t);
    await openNewEvent(t, 'Alba Draft');
    _server.fails['POST events:$acctA'] = 500;
    await t.tap(find.text('Create event'));
    await settleApp(t);
    expect(snack("Couldn't create the event — $_otherHint"), findsOneWidget);
    expect(_failures.map((f) => f.origin),
        contains('VendorPortalScreen.createEvent'));
    await end(t);
  });

  Future<void> openMenu(WidgetTester t) async {
    await t.tap(find.byIcon(Icons.more_horiz));
    await settleApp(t, 10);
  }

  group('edit and delete', () {
    testWidgets("Delete, tapped with no frame after B signed in: A's event is "
        'not deleted on B\'s token', (t) async {
      await mount(t);
      await openMenu(t);
      await t.runAsync(() async {
        await signInAs(acctB);
        await Future<void>.delayed(const Duration(milliseconds: 5));
      });
      await t.tap(find.text('Delete'), warnIfMissed: false);
      await settleApp(t);
      expect(_writes, isEmpty, reason: 'THE defect: sent as B');
      expect(_changed.map((f) => f.origin),
          contains('VendorPortalScreen.deleteEvent'));
      expect(find.byType(SnackBar), findsNothing);
      await end(t);
    });

    testWidgets("Edit's Save, pressed after the switch: nothing is sent",
        (t) async {
      await mount(t);
      await openMenu(t);
      await t.tap(find.text('Edit'));
      await settleApp(t, 10);
      final save = t
          .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Save changes'))
          .onPressed!;
      await t.runAsync(() async {
        unawaited(signInAs(acctB));
        save();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await settleApp(t);
      expect(_writes, isEmpty);
      expect(_changed.map((f) => f.origin),
          contains('VendorPortalScreen.updateEvent'));
      await end(t);
    });

    for (final (what, act, said, origin) in [
      (
        'Delete',
        (WidgetTester t) async => t.tap(find.text('Delete')),
        "Couldn't delete the event",
        'VendorPortalScreen.deleteEvent'
      ),
      (
        'Edit',
        (WidgetTester t) async {
          await t.tap(find.text('Edit'));
          await settleApp(t, 10);
          await t.tap(find.text('Save changes'));
        },
        "Couldn't save the event",
        'VendorPortalScreen.updateEvent'
      ),
    ]) {
      testWidgets('$what that changed no row is a failure, recorded and said',
          (t) async {
        await mount(t);
        _server.emptyWrites = true;
        await openMenu(t);
        await act(t);
        await settleApp(t);
        expect(_writes.single.url.queryParameters['select'], 'id');
        expect(snack('$said — $_otherHint'), findsOneWidget,
            reason: 'THE defect: a 0-row write was a success');
        expect(_failures.map((f) => f.origin), contains(origin));
        expect(find.text('Alba Bootcamp'), findsOneWidget,
            reason: 'the stored state');
        await end(t);
      });

      testWidgets('$what that throws is recorded and said (connection)',
          (t) async {
        await mount(t);
        _server.drops.add(what == 'Delete' ? 'DELETE events' : 'PATCH events');
        await openMenu(t);
        await act(t);
        await settleApp(t);
        expect(snack('$said — $_networkHint'), findsOneWidget);
        expect(_failures.map((f) => f.origin), contains(origin));
        await end(t);
      });

      testWidgets('$what, control: the same vendor, one write by A, nothing '
          'said', (t) async {
        await mount(t);
        await openMenu(t);
        await act(t);
        await settleApp(t);
        expect(_writes.map((s) => s.who), [acctA]);
        expect(find.byType(SnackBar), findsNothing);
        expect(_failures, isEmpty);
        await end(t);
      });
    }

    testWidgets('Delete answering after B signed in: nothing said to B',
        (t) async {
      await mount(t);
      _server.emptyWrites = true; // it fails, too
      final hold = _server.holds['DELETE events:$acctA'] = Completer<void>();
      await openMenu(t);
      await t.tap(find.text('Delete'));
      await settleApp(t, 3);
      await t.runAsync(() => signInAs(acctB));
      await settleApp(t, 3);
      hold.complete();
      await settleApp(t);
      expect(find.byType(SnackBar), findsNothing);
      expect(_failures.map((f) => f.origin),
          contains('VendorPortalScreen.deleteEvent'));
      await end(t);
    });
  });

  group('check-in', () {
    testWidgets('that changed no row is a failure; the row shows what is '
        'stored', (t) async {
      await mount(t);
      await openAttendees(t);
      _server.emptyWrites = true;
      await t.tap(find.text('Check in'));
      await settleApp(t);
      expect(snack("Couldn't save the check-in — $_otherHint"), findsOneWidget,
          reason: 'THE defect: a 0-row update was a success');
      expect(find.text('Check in'), findsOneWidget);
      expect(_server.of('event_registrations', method: 'GET'), hasLength(2),
          reason: 'read again: the stored state');
      expect(_failures.map((f) => f.origin),
          contains('EventAttendeesScreen.setCheckedIn'));
      await end(t);
    });

    testWidgets('that throws is recorded and said', (t) async {
      await mount(t);
      await openAttendees(t);
      _server.drops.add('PATCH event_registrations');
      await t.tap(find.text('Check in'));
      await settleApp(t);
      expect(snack("Couldn't save the check-in — $_networkHint"),
          findsOneWidget);
      expect(find.text('Check in'), findsOneWidget);
      await end(t);
    });

    testWidgets('answering after B signed in: nothing said to B, nothing of '
        'A drawn', (t) async {
      await mount(t);
      await openAttendees(t);
      _server.fails['PATCH event_registrations:$acctA'] = 500;
      final hold = _server.holds['PATCH event_registrations:$acctA'] =
          Completer<void>();
      await t.tap(find.text('Check in'));
      await settleApp(t, 3);
      await t.runAsync(() => signInAs(acctB));
      await settleApp(t, 3);
      hold.complete();
      await settleApp(t);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Ada Attendee'), findsNothing);
      expect(_failures.where((f) => '${f.error}'.contains('answered after')),
          hasLength(1));
      await end(t);
    });

    testWidgets('control: the same vendor checks in once, as itself',
        (t) async {
      await mount(t);
      await openAttendees(t);
      _server.rows['event_registrations:$acctA']!.first['checked_in_at'] =
          '2026-12-05T09:05:00Z'; // what the server holds once it is saved
      await t.tap(find.text('Check in'));
      await settleApp(t);
      expect(_writes.map((s) => s.key), ['PATCH event_registrations:$acctA']);
      expect(_writes.single.url.queryParameters['id'], 'eq.reg-a');
      expect(find.text('In'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(_failures, isEmpty);
      await end(t);
    });
  });

  testWidgets("the event card, tapped with no frame after B: A's attendees "
      'are not opened', (t) async {
    await mount(t);
    await t.runAsync(() async {
      await signInAs(acctB);
      await Future<void>.delayed(const Duration(milliseconds: 5));
    });
    _server.sent.clear();
    await t.tap(find.text('Alba Bootcamp'), warnIfMissed: false);
    await settleApp(t);
    expect(find.text('Ada Attendee'), findsNothing);
    expect(_server.of('event_registrations'), isEmpty);
    await end(t);
  });

  // ── 4. Sign out ──────────────────────────────────────────────────────────

  testWidgets("sign out, tapped with no frame after B signed in: B's session "
      'is untouched, and it is recorded', (t) async {
    await mount(t);
    await t.runAsync(() async {
      await signInAs(acctB);
      await Future<void>.delayed(const Duration(milliseconds: 5));
    });
    _server.sent.clear();
    await t.tap(find.byIcon(Icons.logout_rounded), warnIfMissed: false);
    await settleApp(t);
    expect(_server.of('logout'), isEmpty, reason: 'THE defect: B signed out');
    expect(_auth.currentUser?.id, acctB);
    expect(_changed.map((f) => f.origin), contains('VendorPortalScreen.signOut'));
    expect(find.text('SIGN-IN'), findsNothing);
    await end(t);
  });

  testWidgets('sign out, control: the same vendor after a token refresh is '
      'signed out', (t) async {
    await mount(t);
    await t.runAsync(renewToken);
    await settleApp(t, 3);
    await t.tap(find.byIcon(Icons.logout_rounded));
    await settleApp(t);
    expect(_server.of('logout', by: acctA), hasLength(1));
    expect(_auth.currentSession, isNull);
    expect(find.text('SIGN-IN'), findsOneWidget);
    expect(_changed, isEmpty);
    await end(t);
  });
}
