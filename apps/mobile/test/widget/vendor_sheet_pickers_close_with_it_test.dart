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

// RM-2 (C15-63a-01) · the vendor event editor sheet closes itself when its
// account leaves (P0-FL-63a), but it removed ONLY its own route: its date or
// time picker — pushed by the sheet, on the root navigator — stayed up over
// the next account's portal, A's draft date in it, and B's first tap went to
// it. The sheet now closes the pickers IT opened with it; a route it did not
// open stays (vendor_sheet_first_built_after_switch_test, "a route above the
// open sheet", is that negative control; one more is below).
//
// Mounted WITHOUT AccountScope, kept mounted across real auth transitions.
//
// HOW TO SEE IT FAIL: `git checkout 6d1611d --
// apps/mobile/lib/features/vendor/presentation/vendor_portal_screen.dart`;
// the picker is still found after the switch; only the controls pass.

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

  bool portalOnTop(WidgetTester t) =>
      ModalRoute.of(t.element(find.byType(VendorPortalScreen)))!.isCurrent;

  /// A's editor, open, with A's date picker up over it.
  Future<void> openDatePicker(WidgetTester t, {bool settle = true}) async {
    await t.tap(find.text('New Event'));
    await settleApp(t, 10);
    expect(find.byType(BottomSheet), findsOneWidget, reason: 'premise');
    await t.tap(find.descendant(
        of: find.byType(BottomSheet), matching: find.byIcon(Icons.event)));
    if (!settle) return; // pushed; not built yet
    await settleApp(t, 10);
    expect(find.byType(DatePickerDialog), findsOneWidget, reason: 'premise');
  }

  /// Nothing of A's is up any more, and the portal is the top route.
  void nothingOfALeft(WidgetTester t) {
    expect(find.byType(DatePickerDialog), findsNothing,
        reason: "THE defect: A's date picker stayed over B's portal");
    expect(find.byType(TimePickerDialog), findsNothing,
        reason: "THE defect: A's time picker stayed over B's portal");
    expect(find.byType(BottomSheet), findsNothing);
    expect(portalOnTop(t), isTrue, reason: 'nothing left over the portal');
    expect(_closedRecords, hasLength(1), reason: 'closed and recorded once');
    expect(_writes, isEmpty, reason: 'nothing sent');
    expect(find.byType(SnackBar), findsNothing, reason: 'nothing said');
    expect(t.takeException(), isNull);
  }

  testWidgets("A's date picker open over A's sheet, B signs in: both close, "
      'recorded once, nothing sent; B uses the portal', (t) async {
    await mount(t);
    await openDatePicker(t);
    await t.runAsync(() => signInAs(acctB));
    await settleApp(t);
    nothingOfALeft(t);
    expect(find.text('Bruno Yoga'), findsOneWidget);
    // B's first tap is B's own.
    await t.tap(find.text('New Event'));
    await settleApp(t, 10);
    expect(find.text('Create event'), findsOneWidget);
    expect(_closedRecords, hasLength(1));
    await end(t);
  });

  testWidgets("A's date picker open, A signs out: both close, recorded once",
      (t) async {
    await mount(t);
    await openDatePicker(t);
    await t.runAsync(signOut);
    await settleApp(t);
    nothingOfALeft(t);
    await end(t);
  });

  testWidgets("A's time picker (after the date) open, B signs in: both close",
      (t) async {
    await mount(t);
    await openDatePicker(t);
    await t.tap(find.text('OK'));
    await settleApp(t, 10);
    expect(find.byType(TimePickerDialog), findsOneWidget, reason: 'premise');
    await t.runAsync(() => signInAs(acctB));
    await settleApp(t);
    nothingOfALeft(t);
    await end(t);
  });

  testWidgets("A's date picker pushed, B signs in before its first frame (a "
      'hidden tab): it is never drawn and closes with the sheet', (t) async {
    await mount(t);
    await openDatePicker(t, settle: false);
    await t.runAsync(() async {
      await signInAs(acctB);
      await Future<void>.delayed(const Duration(milliseconds: 5));
    });
    for (var frame = 0; frame < 12; frame++) {
      await t.pump(const Duration(milliseconds: 50));
      expect(find.byType(DatePickerDialog), findsNothing,
          reason: "A's picker drawn for B (frame $frame)");
    }
    await settleApp(t);
    nothingOfALeft(t);
    await end(t);
  });

  testWidgets(
      'a route the sheet did not open, above its picker, stays; only the '
      "sheet's own picker and the sheet go", (t) async {
    await mount(t);
    await openDatePicker(t);
    final root = Navigator.of(t.element(find.byType(DatePickerDialog)),
        rootNavigator: true);
    unawaited(root.push(DialogRoute<void>(
        context: root.context,
        builder: (_) => const AlertDialog(content: Text('NOT THE SHEET\'S')))));
    await settleApp(t, 4);
    await t.runAsync(() => signInAs(acctB));
    await settleApp(t);
    expect(find.text("NOT THE SHEET'S"), findsOneWidget,
        reason: 'a route the sheet did not open is never removed by it');
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    expect(_closedRecords, hasLength(1));
    expect(_writes, isEmpty);
    Navigator.of(t.element(find.text("NOT THE SHEET'S"))).pop();
    await settleApp(t);
    expect(portalOnTop(t), isTrue);
    await end(t);
  });

  // ── Controls: the same vendor ────────────────────────────────────────────

  testWidgets(
      'control: a token refresh with the picker open keeps it; the date and '
      'time picked land in the sheet; nothing recorded', (t) async {
    await mount(t);
    await openDatePicker(t);
    await t.runAsync(renewToken);
    await settleApp(t, 4);
    expect(find.byType(DatePickerDialog), findsOneWidget,
        reason: 'the same vendor keeps their picker');
    await t.tap(find.text('OK'));
    await settleApp(t, 10);
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await t.runAsync(renewToken);
    await settleApp(t, 4);
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await t.tap(find.text('OK'));
    await settleApp(t, 10);
    expect(find.byType(TimePickerDialog), findsNothing);
    expect(find.byType(BottomSheet), findsOneWidget, reason: 'sheet kept');
    expect(_failures, isEmpty);
    expect(_writes, isEmpty);
    await end(t);
  });

  testWidgets(
      'control: a picker dismissed by the vendor, then B signs in: the sheet '
      'closes, recorded once, nothing else is popped', (t) async {
    await mount(t);
    await openDatePicker(t);
    await t.tap(find.text('Cancel'));
    await settleApp(t, 10);
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.byType(BottomSheet), findsOneWidget);
    await t.runAsync(() => signInAs(acctB));
    await settleApp(t);
    nothingOfALeft(t);
    expect(find.text('Bruno Yoga'), findsOneWidget,
        reason: 'the portal itself was not popped');
    await end(t);
  });

  testWidgets('control: the same vendor picks a date and creates once',
      (t) async {
    await mount(t);
    await openDatePicker(t);
    await t.tap(find.text('OK'));
    await settleApp(t, 10);
    await t.tap(find.text('OK'));
    await settleApp(t, 10);
    await t.enterText(find.byType(TextField).first, 'Alba Draft');
    await t.pump();
    await t.tap(find.text('Create event'));
    await settleApp(t);
    expect(_writes.map((s) => s.key), ['POST events:$acctA']);
    expect(_failures, isEmpty);
    await end(t);
  });
}
