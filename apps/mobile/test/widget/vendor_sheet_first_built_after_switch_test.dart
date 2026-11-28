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

// P0-FL-63a (Cycle 13 FL-59a follow-up, PR #228) — a vendor sheet pushed for
// account A and first BUILT after the account changed (B, or nobody) used to
// draw nothing of A's but stay open, empty, over the next account's portal:
// its listener registers in that first build, after the change, so it never
// fired, and nothing was recorded. B's first tap only dismissed it.
//
// Also (C14-62a2-02): Manage Agenda was pushed without the portal's owner, so
// the agenda took whoever was signed in at its first build — a switch between
// push and build opened A's event's agenda for B, read on B's token.
//
// Mounted WITHOUT AccountScope, kept mounted across real auth transitions.
//
// HOW TO SEE IT FAIL: `git checkout 7b9ce5c --
// apps/mobile/lib/features/vendor/presentation/vendor_portal_screen.dart`;
// only the controls pass.

final _server = AccountServer();
final _realtime = FakeRealtime();
final _store = MemoryStore();
final _failures = <AppFailure>[];

GoTrueClient get _auth => Supabase.instance.client.auth;

Iterable<AppFailure> get _closedRecords => _failures.where((f) =>
    f.origin == 'VendorPortalScreen.eventEditor' &&
    '${f.error}'
        .contains('event editor closed: the signed-in account changed'));

Iterable<Sent> get _writes => _server.sent.where((s) =>
    s.method != 'GET' &&
    !s.url.path.startsWith('/auth/') &&
    !s.url.path.contains('/rpc/'));

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
    for (final (uid, ev, title) in [
      (acctA, 'ev-a', 'Alba Bootcamp'),
      (acctB, 'ev-b', 'Bruno Yoga'),
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
            {'count': 0}
          ],
        }
      ];
      _server.rows['event_sessions:$uid'] = [
        {
          'id': 'ses-$uid',
          'event_id': ev,
          'title': '$title keynote',
          'starts_at': '2026-12-05T09:00:00Z',
          'ends_at': '2026-12-05T10:00:00Z',
          'sort_order': 0,
        }
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

  /// Nothing is over the portal: its own route is the top one.
  bool portalOnTop(WidgetTester t) =>
      ModalRoute.of(t.element(find.byType(VendorPortalScreen)))!.isCurrent;

  Future<void> openMenu(WidgetTester t) async {
    await t.tap(find.byIcon(Icons.more_horiz));
    await settleApp(t, 10);
  }

  /// The account changes with no frame since [push] pushed the sheet.
  Future<void> switchBeforeFirstBuild(
      WidgetTester t, Future<void> Function() change) async {
    await t.runAsync(() async {
      await change();
      await Future<void>.delayed(const Duration(milliseconds: 5));
    });
  }

  /// Frame by frame: nothing of A's sheet is drawn at any of them.
  Future<void> neverDrawn(WidgetTester t, List<Finder> ofA) async {
    for (var frame = 0; frame < 12; frame++) {
      await t.pump(const Duration(milliseconds: 50));
      for (final f in ofA) {
        expect(f, findsNothing, reason: "A's sheet drawn (frame $frame)");
      }
    }
    await settleApp(t);
  }

  final editorField = find.descendant(
      of: find.byType(TextField), matching: find.text('Alba Bootcamp'));

  // ── The defect ───────────────────────────────────────────────────────────

  testWidgets(
      'New Event tapped by A, B signs in before its first frame: the sheet '
      'closes itself, recorded once, nothing sent; B can use the portal',
      (t) async {
    await mount(t);
    await t.tap(find.text('New Event')); // pushed; not built yet
    await switchBeforeFirstBuild(t, () => signInAs(acctB));
    await neverDrawn(t, [find.text('Create event')]);
    expect(find.byType(BottomSheet), findsNothing,
        reason: "THE defect: an empty sheet left open over B's portal");
    expect(portalOnTop(t), isTrue, reason: 'the route stack is the portal');
    expect(_closedRecords, hasLength(1),
        reason: 'THE defect: nothing was recorded');
    expect(_writes, isEmpty);
    expect(find.byType(SnackBar), findsNothing, reason: 'nothing said to B');
    expect(find.text('Bruno Yoga'), findsOneWidget);
    // B's first tap is B's own: it opens B's editor, not a dismissal.
    await t.tap(find.text('New Event'));
    await settleApp(t, 10);
    expect(find.text('Create event'), findsOneWidget);
    expect(_closedRecords, hasLength(1));
    await end(t);
  });

  testWidgets(
      'Edit tapped by A, B signs in before its first frame: A\'s event is '
      'never drawn, the sheet closes itself, recorded once, nothing sent',
      (t) async {
    await mount(t);
    await openMenu(t);
    await t.tap(find.text('Edit')); // pushed; not built yet
    await switchBeforeFirstBuild(t, () => signInAs(acctB));
    await neverDrawn(t, [editorField, find.text('Save changes')]);
    expect(find.byType(BottomSheet), findsNothing,
        reason: "THE defect: an empty sheet left open over B's portal");
    expect(portalOnTop(t), isTrue);
    expect(_closedRecords, hasLength(1));
    expect(_writes, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Bruno Yoga'), findsOneWidget);
    await end(t);
  });

  testWidgets(
      'New Event tapped by A, signed out before its first frame: the sheet '
      'closes itself, recorded once, nothing sent', (t) async {
    await mount(t);
    await t.tap(find.text('New Event'));
    await switchBeforeFirstBuild(t, signOut);
    await neverDrawn(t, [find.text('Create event')]);
    expect(find.byType(BottomSheet), findsNothing,
        reason: 'THE defect: an empty sheet left open for nobody');
    expect(portalOnTop(t), isTrue);
    expect(_closedRecords, hasLength(1));
    expect(_writes, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
    await end(t);
  });

  testWidgets(
      'A -> B (before the first frame) -> A: the sheet stays closed, is '
      'recorded once, and A then creates its own event once', (t) async {
    await mount(t);
    await t.tap(find.text('New Event'));
    await switchBeforeFirstBuild(t, () => signInAs(acctB));
    await neverDrawn(t, [find.text('Create event')]);
    await t.runAsync(() => signInAs(acctA));
    await settleApp(t);
    expect(find.byType(BottomSheet), findsNothing,
        reason: "THE defect: the empty sheet is still open; it is not A's to "
            'reopen either');
    expect(portalOnTop(t), isTrue);
    expect(_closedRecords, hasLength(1), reason: 'recorded once, not twice');
    expect(_writes, isEmpty);
    expect(find.text('Alba Bootcamp'), findsOneWidget);
    // A's portal works as before.
    await t.tap(find.text('New Event'));
    await settleApp(t, 10);
    await t.enterText(find.byType(TextField).first, 'Alba Again');
    await t.pump();
    await t.tap(find.text('Create event'));
    await settleApp(t);
    expect(_writes.map((s) => s.key), ['POST events:$acctA']);
    expect(_writes.single.body, contains('"vendor_id":"$acctA"'));
    expect(_closedRecords, hasLength(1));
    await end(t);
  });

  testWidgets(
      'Manage Agenda tapped by A, B signs in before its first build: nothing '
      'opens for B, nothing is read on B\'s token', (t) async {
    await mount(t);
    await openMenu(t);
    _server.sent.clear();
    await t.tap(find.text('Manage Agenda')); // pushed; not built yet
    await switchBeforeFirstBuild(t, () => signInAs(acctB));
    await neverDrawn(t, [find.text('Add Session')]);
    expect(_server.of('event_sessions', by: acctB), isEmpty,
        reason: "THE defect: A's event's agenda read on B's token");
    expect(_server.of('event_sessions', by: acctA), isEmpty);
    expect(find.text('Agenda'), findsNothing,
        reason: "THE defect: A's event's agenda opened for B");
    expect(find.text('Add Session'), findsNothing);
    expect(portalOnTop(t), isTrue);
    expect(_writes, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
    await end(t);
  });

  // ── Round 2: only its own route, closed once (mutants M4, M7, M8) ────────

  /// A route that is not the sheet's, pushed above it on the same navigator.
  void pushAbove(WidgetTester t) {
    final nav = Navigator.of(t.element(find.byType(VendorPortalScreen)));
    unawaited(nav.push(DialogRoute<void>(
        context: nav.context,
        builder: (_) => const AlertDialog(content: Text('ROUTE ABOVE')))));
  }

  testWidgets(
      'a route above the open sheet when A leaves: only the sheet\'s own '
      'route is removed, the route above stays, nothing else is popped',
      (t) async {
    await mount(t);
    await t.tap(find.text('New Event'));
    await settleApp(t, 10);
    expect(find.byType(BottomSheet), findsOneWidget, reason: 'premise');
    pushAbove(t);
    await settleApp(t, 4);
    expect(find.text('ROUTE ABOVE'), findsOneWidget, reason: 'premise');
    await t.runAsync(() => signInAs(acctB));
    await settleApp(t);
    expect(find.byType(BottomSheet), findsNothing,
        reason: "the sheet's own route is the one removed");
    expect(find.text('ROUTE ABOVE'), findsOneWidget,
        reason: 'the route above is not the sheet\'s: it is not popped');
    expect(_closedRecords, hasLength(1));
    expect(_writes, isEmpty);
    // Under the route above sits the portal, nothing else.
    Navigator.of(t.element(find.text('ROUTE ABOVE'))).pop();
    await settleApp(t, 4);
    expect(portalOnTop(t), isTrue);
    expect(find.byType(BottomSheet), findsNothing);
    await end(t);
  });

  testWidgets(
      'a route above a sheet first built after the switch: only the sheet\'s '
      'own route is removed, the route above stays', (t) async {
    await mount(t);
    await t.tap(find.text('New Event')); // pushed; not built yet
    pushAbove(t); // and another route above it, still no frame
    await switchBeforeFirstBuild(t, () => signInAs(acctB));
    await neverDrawn(t, [find.text('Create event')]);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('ROUTE ABOVE'), findsOneWidget,
        reason: 'the route above is not the sheet\'s: it is not popped');
    expect(_closedRecords, hasLength(1));
    expect(_writes, isEmpty);
    Navigator.of(t.element(find.text('ROUTE ABOVE'))).pop();
    await settleApp(t, 4);
    expect(portalOnTop(t), isTrue);
    await end(t);
  });

  testWidgets(
      'first-build close, then a second change before the next frame (the '
      'listener): one route removed, recorded once, nothing throws', (t) async {
    await mount(t);
    await t.tap(find.text('New Event')); // pushed; not built yet
    await switchBeforeFirstBuild(t, () => signInAs(acctB));
    await t.pump(); // the first build: it closes itself after this frame
    await t.runAsync(() async {
      await signOut(); // its listener hears this before the next frame
      await Future<void>.delayed(const Duration(milliseconds: 5));
    });
    await settleApp(t);
    expect(t.takeException(), isNull);
    expect(find.byType(BottomSheet), findsNothing);
    expect(portalOnTop(t), isTrue);
    expect(_closedRecords, hasLength(1), reason: 'closed and recorded once');
    expect(_failures, hasLength(1), reason: 'nothing else went wrong');
    expect(_writes, isEmpty);
    await end(t);
  });

  // ── Controls: the same vendor ────────────────────────────────────────────

  testWidgets(
      'control: same-account rebuilds of the open sheet (a route above it '
      'and back, a token refresh) never close it', (t) async {
    await mount(t);
    await t.tap(find.text('New Event'));
    await settleApp(t, 10);
    await t.enterText(find.byType(TextField).first, 'Alba Draft');
    await t.pump();
    pushAbove(t); // the sheet's route status changes: it rebuilds
    await settleApp(t, 4);
    Navigator.of(t.element(find.text('ROUTE ABOVE'))).pop();
    await settleApp(t, 4);
    await t.runAsync(renewToken);
    await settleApp(t, 4);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Alba Draft'), findsOneWidget, reason: 'draft kept');
    expect(_failures, isEmpty);
    expect(_writes, isEmpty);
    await end(t);
  });

  testWidgets('control: the same vendor opens New Event, types, saves once',
      (t) async {
    await mount(t);
    await t.tap(find.text('New Event'));
    await settleApp(t, 10);
    expect(find.byType(BottomSheet), findsOneWidget);
    await t.enterText(find.byType(TextField).first, 'Alba Draft');
    await t.pump();
    await t.tap(find.text('Create event'));
    await settleApp(t);
    expect(_writes.map((s) => s.key), ['POST events:$acctA']);
    expect(_writes.single.body, contains('Alba Draft'));
    expect(find.byType(BottomSheet), findsNothing);
    expect(_failures, isEmpty);
    await end(t);
  });

  testWidgets('control: Edit opens with the event and saves once as A',
      (t) async {
    await mount(t);
    await openMenu(t);
    await t.tap(find.text('Edit'));
    await settleApp(t, 10);
    expect(editorField, findsOneWidget);
    await t.tap(find.text('Save changes'));
    await settleApp(t);
    expect(_writes.map((s) => s.key), ['PATCH events:$acctA']);
    expect(_failures, isEmpty);
    await end(t);
  });

  testWidgets(
      'control: a token refresh before the first frame and while open keeps '
      'the sheet and what was typed', (t) async {
    await mount(t);
    await t.tap(find.text('New Event'));
    await t.runAsync(renewToken); // same uid, before the first frame
    await settleApp(t, 10);
    expect(find.byType(BottomSheet), findsOneWidget);
    await t.enterText(find.byType(TextField).first, 'Alba Draft');
    await t.pump();
    await t.runAsync(renewToken); // and while open
    await settleApp(t, 3);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Alba Draft'), findsOneWidget, reason: 'draft kept');
    expect(_failures, isEmpty);
    expect(_writes, isEmpty);
    await end(t);
  });

  testWidgets(
      'control: an owner change while the sheet is open still closes it, '
      'recorded once, nothing sent', (t) async {
    await mount(t);
    await t.tap(find.text('New Event'));
    await settleApp(t, 10);
    await t.enterText(find.byType(TextField).first, 'Alba Draft');
    await t.pump();
    await t.runAsync(() => signInAs(acctB));
    await settleApp(t);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Alba Draft'), findsNothing);
    expect(portalOnTop(t), isTrue);
    expect(_closedRecords, hasLength(1));
    expect(_writes, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
    await end(t);
  });

  testWidgets('control: the same vendor opens Manage Agenda for its event',
      (t) async {
    await mount(t);
    await openMenu(t);
    _server.sent.clear();
    await t.tap(find.text('Manage Agenda'));
    await settleApp(t, 10);
    expect(find.text('Add Session'), findsOneWidget);
    expect(find.text('Alba Bootcamp keynote'), findsOneWidget);
    expect(
        _server.of('event_sessions', method: 'GET').map((s) => s.who), [acctA]);
    expect(_failures, isEmpty);
    await end(t);
  });
}
