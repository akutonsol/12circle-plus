import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/vendor/presentation/event_agenda_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../support/coach_tools_server.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-62a2 (Cycle 13 FL-59a follow-up) · Manage Agenda belongs to the
// account that opened it, with the REAL session service and real sign-ins on
// one device, and NO AccountScope (which stops neither a write in flight nor a
// tab that draws no frame).
//
// It was tied to nobody: vendor A's sessions stayed on screen when vendor B
// signed in, A's open editor stayed open with A's draft, and its Save, an Edit
// or a Delete went out on B's token. A write RLS refused changed 0 rows and
// said nothing, so a refused update or delete looked saved; a failed read was
// "Could not load agenda." with no way to try again.
//
// HOW TO SEE IT FAIL: `git checkout a446926 -- apps/mobile/lib/features/vendor`;
// only the controls pass.

const _event = {
  'id': 'ev-a',
  'title': 'A Summit',
  'event_date': '2026-12-01T09:00:00Z',
};

Map<String, Object?> _session(String id, String title) => {
      'id': id,
      'event_id': 'ev-a',
      'title': title,
      'description': '$title words',
      'speaker_name': 'Dr. A',
      'starts_at': '2026-12-01T09:00:00Z',
      'ends_at': '2026-12-01T10:00:00Z',
      'sort_order': 0,
    };

void main() {
  final server = CoachToolsServer();
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(server);
  });

  setUp(() {
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
    server.tables['event_sessions'] = [_session('s-1', 'A keynote')];
  });
  tearDown(resetFailureSink);

  Iterable<String> changed() => reported
      .where((f) => '${f.error}'.contains('signed-in account changed'))
      .map((f) => f.origin);
  Iterable<Sent> by(String uid) => server.log.where((s) => s.who == uid);
  bool reads(Sent s) => s.table == 'event_sessions' && s.method == 'GET';

  late Routes routes;

  /// The agenda, pushed over a page (as the portal and the ticket push it),
  /// for [as].
  Future<void> open(WidgetTester t,
      {bool manage = true, String as = memberA, bool settle = true}) async {
    t.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1200, 2600);
    addTearDown(t.view.reset);
    await t.runAsync(() => signInAs(as));
    final c = ProviderContainer();
    addTearDown(c.dispose);
    routes = Routes();
    await t.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: pushedPage(
            routes, EventAgendaScreen(event: _event, canManage: manage))));
    await t.tap(find.text('go'));
    if (settle) await settleReal(t);
  }

  Future<void> agendaGone(WidgetTester t) async {
    await t.pump(const Duration(seconds: 1)); // the route's way out
    expect(find.text('A keynote'), findsNothing, reason: "A's sessions are shown to B");
    expect(find.byType(EventAgendaScreen), findsNothing, reason: "A's agenda stayed open");
    expect(find.text('go'), findsOneWidget, reason: 'the page under it is kept');
  }

  Future<void> openMenu(WidgetTester t) async {
    await t.tap(find.byIcon(Icons.more_horiz));
    await settleReal(t);
  }

  Future<void> openEditor(WidgetTester t) async {
    await openMenu(t);
    await t.tap(find.text('Edit'));
    await settleReal(t);
    expect(find.text('Edit Session'), findsOneWidget, reason: 'premise');
  }

  group('another account signs in', () {
    testWidgets("vendor A→vendor B: A's sessions leave with A's agenda; B reads nothing",
        (t) async {
      await open(t);
      expect(find.text('A keynote'), findsOneWidget, reason: 'premise');
      await switchTo(t, memberB);
      await agendaGone(t);
      expect(by(memberB), isEmpty, reason: "B re-read A's agenda: ${by(memberB).toList()}");
      expect(server.writes, isEmpty);
      await unmountAll(t);
    });

    testWidgets("A's open editor closes with A's draft; its Save writes nothing as B",
        (t) async {
      await open(t);
      await openEditor(t);
      await t.enterText(find.byType(TextField).first, 'A private retitle');
      final save = tapOf(t, 'Save changes');
      await switchTo(t, memberB);
      expect(find.text('Edit Session'), findsNothing, reason: "A's editor stayed open for B");
      expect(find.text('A private retitle'), findsNothing);
      save(); // the tap already on its way
      await settleReal(t);
      expect(server.writes, isEmpty, reason: "A's draft was saved by B: ${server.writes.toList()}");
      await agendaGone(t);
      await unmountAll(t);
    });

    testWidgets('a Save tapped before anything was drawn writes nothing as B', (t) async {
      await open(t);
      await openEditor(t);
      await t.enterText(find.byType(TextField).first, 'A private retitle');
      final save = tapOf(t, 'Save changes');
      await switchNoFrame(t, memberB);
      save();
      await settleNoFrame(t);
      await settleReal(t);
      expect(server.writesBy(memberB), isEmpty,
          reason: "A's edit went out on B's token: ${server.writes.toList()}");
      expect(changed(), contains('EventAgendaScreen.updateSession'));
      await unmountAll(t);
    });

    testWidgets('a Delete chosen before anything was drawn deletes nothing as B',
        (t) async {
      await open(t);
      await openMenu(t);
      await switchNoFrame(t, memberB);
      await t.tap(find.text('Delete'));
      await settleNoFrame(t);
      await settleReal(t);
      expect(server.writes, isEmpty,
          reason: "A's session was deleted on B's token: ${server.writes.toList()}");
      expect(changed(), contains('EventAgendaScreen.deleteSession'));
      await agendaGone(t);
      await unmountAll(t);
    });

    testWidgets('an Add Session tapped before anything was drawn opens nothing for B',
        (t) async {
      await open(t);
      final add = t.widget<FloatingActionButton>(find.byType(FloatingActionButton)).onPressed!;
      await switchNoFrame(t, memberB);
      add();
      await settleNoFrame(t);
      await settleReal(t);
      expect(find.text('New Session'), findsNothing, reason: "A's editor opened for B");
      expect(changed(), contains('EventAgendaScreen.addSession'));
      await unmountAll(t);
    });

    testWidgets('switch during a save: nothing more is sent, and B is told nothing',
        (t) async {
      await open(t);
      await openEditor(t);
      await t.enterText(find.byType(TextField).first, 'A retitle');
      final hold = server.hold((s) => s.isWrite);
      server.failing = (s) => s.isWrite;
      await t.tap(find.text('Save changes'));
      await settleReal(t);
      expect(server.writes.single.who, memberA, reason: 'premise: A sent it');
      await switchTo(t, memberB);
      hold.complete();
      await settleReal(t);
      expect(find.byType(SnackBar), findsNothing, reason: "A's failure was said to B");
      expect(find.textContaining("Couldn't"), findsNothing);
      expect(by(memberB), isEmpty, reason: "B re-read A's agenda: ${by(memberB).toList()}");
      expect(changed(), ['EventAgendaScreen.updateSession']);
      // Round 2 (security N2, the same rule here): one failure, one record.
      expect(reported, hasLength(1), reason: 'recorded twice: $reported');
      await agendaGone(t);
      await unmountAll(t);
    });

    testWidgets("A's delayed answer, landing after B signed in, is not shown to B",
        (t) async {
      final hold = server.hold(reads);
      await open(t);
      expect(find.text('A keynote'), findsNothing, reason: 'premise: still reading');
      await switchTo(t, memberB);
      hold.complete();
      await settleReal(t);
      await agendaGone(t);
      expect(find.text('A keynote'), findsNothing);
      expect(by(memberB), isEmpty);
      await unmountAll(t);
    });

    testWidgets("A's failed read is not said to B", (t) async {
      server.failing = reads;
      await open(t);
      // (Either wording: the premise holds on the base too.)
      expect(find.textContaining('load'), findsOneWidget, reason: 'premise: said to A');
      await switchTo(t, memberB);
      await t.pump(const Duration(seconds: 1));
      expect(find.textContaining('load'), findsNothing, reason: "A's failure is said to B");
      await agendaGone(t);
      await unmountAll(t);
    });

    testWidgets('signed out: the agenda closes; signed in again, it opens afresh',
        (t) async {
      await open(t);
      await signOutNow(t);
      await agendaGone(t);
      expect(server.writes, isEmpty);
      await switchTo(t, memberA);
      await t.tap(find.text('go'));
      await settleReal(t);
      expect(find.text('A keynote'), findsOneWidget);
      await unmountAll(t);
    });

    testWidgets("a member's read-only agenda (the ticket's View Agenda) leaves with them",
        (t) async {
      await open(t, manage: false);
      expect(find.text('A keynote'), findsOneWidget, reason: 'premise');
      expect(find.byIcon(Icons.more_horiz), findsNothing, reason: 'read-only, unchanged');
      expect(find.byType(FloatingActionButton), findsNothing);
      await switchTo(t, memberB);
      await agendaGone(t);
      expect(by(memberB), isEmpty);
      await unmountAll(t);
    });
  });

  // Round 2 (mutants M13, M14, M15): each binding on its own, with the layer
  // that normally stops the same case first taken out of the way.
  group('each binding on its own', () {
    testWidgets(
        "opened for vendor A (the opener's owner) while B is already signed in: "
        'it closes before B sees anything, and reads nothing', (t) async {
      t.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1200, 2600);
      addTearDown(t.view.reset);
      // The opener captured A at the tap; B signed in before the first frame.
      await t.runAsync(() => signInAs(memberB));
      final c = ProviderContainer();
      addTearDown(c.dispose);
      routes = Routes();
      await t.pumpWidget(UncontrolledProviderScope(
          container: c,
          child: pushedPage(routes,
              const EventAgendaScreen(event: _event, canManage: true, owner: memberA))));
      await t.tap(find.text('go'));
      await settleReal(t);
      await t.pump(const Duration(seconds: 1));
      expect(find.byType(EventAgendaScreen), findsNothing,
          reason: "A's agenda stayed open for B");
      expect(find.text('Add Session'), findsNothing);
      expect(find.text('go'), findsOneWidget);
      expect(server.log, isEmpty, reason: "A's agenda was read as B: ${server.log}");
      await unmountAll(t);
    });

    testWidgets(
        "A's editor sheet closes itself even when the page under it cannot "
        '(the agenda is the first route)', (t) async {
      t.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1200, 2600);
      addTearDown(t.view.reset);
      await t.runAsync(() => signInAs(memberA));
      final c = ProviderContainer();
      addTearDown(c.dispose);
      // The first route: the page's own binding blanks it but cannot pop it,
      // so only the sheet's binding can take A's draft away.
      await t.pumpWidget(UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(
              home: EventAgendaScreen(event: _event, canManage: true))));
      await settleReal(t);
      await openEditor(t);
      await t.enterText(find.byType(TextField).first, 'A private retitle');
      final save = tapOf(t, 'Save changes');
      await switchTo(t, memberB);
      await t.pump(const Duration(seconds: 1));
      expect(find.text('Edit Session'), findsNothing, reason: "A's editor stayed open for B");
      expect(find.text('A private retitle'), findsNothing, reason: "A's draft is shown to B");
      save(); // the tap already on its way
      await settleReal(t);
      expect(server.writes, isEmpty, reason: "A's draft was saved by B: ${server.writes.toList()}");
      await unmountAll(t);
    });

    testWidgets(
        "a rebuild before the page hears of B draws none of A's sessions",
        (t) async {
      // A listener subscribed before the page's own ones rebuilds the page
      // after B is signed in but before the page (and its binding) heard of
      // it: what that build draws must already be nothing of A's.
      bool? drawnInGap;
      final early = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
        if (drawnInGap != null ||
            Supabase.instance.client.auth.currentUser?.id != memberB) {
          return;
        }
        final page = find.byType(EventAgendaScreen);
        if (page.evaluate().isEmpty) return;
        final el = t.element(page);
        el.markNeedsBuild();
        el.owner!.buildScope(el);
        drawnInGap = find.text('A keynote').evaluate().isNotEmpty ||
            find.byIcon(Icons.more_horiz).evaluate().isNotEmpty;
      });
      addTearDown(early.cancel);
      await open(t);
      expect(find.text('A keynote'), findsOneWidget, reason: 'premise');
      await switchTo(t, memberB);
      expect(drawnInGap, isNotNull, reason: 'premise: built in the gap');
      expect(drawnInGap, isFalse, reason: "A's sessions were drawn while B was signed in");
      await agendaGone(t);
      expect(by(memberB), isEmpty);
      await unmountAll(t);
    });
  });

  group('round 2: more of the matrix', () {
    testWidgets("switch while A's delete is in flight: one delete, as A; B is told nothing",
        (t) async {
      await open(t);
      final hold = server.hold((s) => s.isWrite);
      await openMenu(t);
      await t.tap(find.text('Delete'));
      await settleReal(t);
      expect(server.writes.single.who, memberA, reason: 'premise: A sent it');
      await switchTo(t, memberB);
      hold.complete();
      await settleReal(t);
      expect(server.writes, hasLength(1));
      expect(server.writes.single.method, 'DELETE');
      expect(find.byType(SnackBar), findsNothing);
      expect(by(memberB), isEmpty, reason: "B re-read A's agenda: ${by(memberB).toList()}");
      expect(changed(), ['EventAgendaScreen.deleteSession']);
      await agendaGone(t);
      await unmountAll(t);
    });

    testWidgets("B's own read failed: said to B with Try again; never A's rows",
        (t) async {
      server.failing = reads;
      await open(t, as: memberB);
      expect(find.textContaining("Couldn't load the agenda"), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.textContaining('No sessions yet'), findsNothing);
      expect(server.log.where(reads).map((s) => s.who), [memberB]);
      await unmountAll(t);
    });

    testWidgets('the failure card fits a 320×568 screen at 3× text', (t) async {
      server.failing = reads;
      t.platformDispatcher.textScaleFactorTestValue = 3;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await t.runAsync(() => signInAs(memberA));
      t.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(320, 568);
      addTearDown(t.view.reset);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await t.pumpWidget(UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(
              home: EventAgendaScreen(event: _event, canManage: true))));
      await settleReal(t);
      expect(find.textContaining("Couldn't load the agenda"), findsOneWidget);
      expect(t.takeException(), isNull, reason: 'overflowed at 3× text');
      final retry = t.getSize(find.ancestor(
          of: find.text('Try again'), matching: find.bySubtype<ButtonStyleButton>()).first);
      expect(retry.height, greaterThanOrEqualTo(44));
      await unmountAll(t);
    });

    testWidgets('a failed refresh at 3× text on 320×568: the rows are kept under the card',
        (t) async {
      t.platformDispatcher.textScaleFactorTestValue = 3;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await t.runAsync(() => signInAs(memberA));
      t.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(320, 568);
      addTearDown(t.view.reset);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await t.pumpWidget(UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(
              home: EventAgendaScreen(event: _event, canManage: true))));
      await settleReal(t);
      expect(find.text('A keynote'), findsOneWidget, reason: 'premise');
      server.failing = reads;
      final refreshed =
          t.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show();
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      await settleReal(t);
      await t.pump(const Duration(seconds: 1));
      await refreshed;
      expect(find.textContaining("Couldn't load the agenda"), findsOneWidget);
      expect(t.takeException(), isNull, reason: 'overflowed at 3× text');
      await t.scrollUntilVisible(find.text('A keynote'), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('A keynote'), findsOneWidget, reason: 'the kept rows are reachable');
      await unmountAll(t);
    });
  });

  group('a write is saved only when the server says so', () {
    testWidgets('an update RLS refused (0 rows) is a failure, said', (t) async {
      server.zeroRows = (s) => s.isWrite;
      await open(t);
      await openEditor(t);
      await t.tap(find.text('Save changes'));
      await settleReal(t);
      final w = server.writes.single;
      expect(w.method, 'PATCH');
      expect(w.query, contains('select=id'), reason: 'the update must ask for its row back');
      expect(find.textContaining("Couldn't save the session — "), findsOneWidget,
          reason: 'a refused update looked saved');
      expect(reported.map((f) => f.origin), ['EventAgendaScreen.updateSession']);
      expect(find.text('A keynote'), findsOneWidget, reason: 'the stored state is shown');
      await unmountAll(t);
    });

    testWidgets('a delete RLS refused (0 rows) is a failure, said', (t) async {
      server.zeroRows = (s) => s.isWrite;
      await open(t);
      await openMenu(t);
      await t.tap(find.text('Delete'));
      await settleReal(t);
      final w = server.writes.single;
      expect(w.method, 'DELETE');
      expect(w.query, contains('select=id'), reason: 'the delete must ask for its row back');
      expect(find.textContaining("Couldn't delete the session — "), findsOneWidget,
          reason: 'a refused delete looked done');
      expect(reported.map((f) => f.origin), ['EventAgendaScreen.deleteSession']);
      await unmountAll(t);
    });

    testWidgets('an add the server refused is said, in the existing voice, never raw',
        (t) async {
      server.failing = (s) => s.isWrite;
      await open(t);
      await t.tap(find.text('Add Session'));
      await settleReal(t);
      await t.enterText(find.byType(TextField).first, 'A panel');
      await t.tap(find.text('Add session'));
      await settleReal(t);
      expect(find.textContaining("Couldn't add the session — try again in a moment"),
          findsOneWidget);
      expect(find.textContaining('SECRET_TABLE'), findsNothing);
      expect(reported.map((f) => f.origin), ['EventAgendaScreen.addSession']);
      await unmountAll(t);
    });

    testWidgets('offline: the connection is named', (t) async {
      server.offline = (s) => s.isWrite;
      await open(t);
      await openMenu(t);
      await t.tap(find.text('Delete'));
      await settleReal(t);
      expect(find.textContaining("Couldn't delete the session — check your connection"),
          findsOneWidget);
      await unmountAll(t);
    });
  });

  group('a failed read', () {
    testWidgets('is said with Try again, not as "no sessions"; the retry reads again',
        (t) async {
      server.failing = reads;
      await open(t);
      expect(find.textContaining("Couldn't load the agenda"), findsOneWidget);
      expect(find.textContaining('No sessions yet'), findsNothing);
      expect(find.textContaining('SECRET_TABLE'), findsNothing);
      expect(reported.map((f) => f.origin), ['eventSessionsProvider']);
      server.failing = (_) => false;
      await t.tap(find.text('Try again'));
      await settleReal(t);
      expect(find.text('A keynote'), findsOneWidget);
      expect(server.log.where(reads).map((s) => s.who), [memberA, memberA]);
      await unmountAll(t);
    });

    testWidgets('B, opening the agenda, waits for its own read (pending), then sees it',
        (t) async {
      await t.runAsync(() => signInAs(memberA));
      final hold = server.hold(reads);
      await open(t, as: memberB);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.textContaining('No sessions yet'), findsNothing, reason: 'not empty: still reading');
      hold.complete();
      await settleReal(t);
      expect(find.text('A keynote'), findsOneWidget);
      expect(server.log.where(reads).map((s) => s.who), [memberB]);
      await unmountAll(t);
    });
  });

  group('positive controls: the same vendor', () {
    testWidgets('normal load; add, edit and delete are each sent once, as A, keys literal',
        (t) async {
      await open(t);
      expect(find.text('A keynote'), findsOneWidget);
      await t.tap(find.text('Add Session'));
      await settleReal(t);
      await t.enterText(find.byType(TextField).first, 'A panel');
      await t.tap(find.text('Add session'));
      await settleReal(t);
      await openEditor(t);
      await t.enterText(find.byType(TextField).first, 'A keynote 2');
      await t.tap(find.text('Save changes'));
      await settleReal(t);
      await openMenu(t);
      await t.tap(find.text('Delete'));
      await settleReal(t);
      final w = server.writes.toList();
      expect(w.map((s) => s.method), ['POST', 'PATCH', 'DELETE']);
      expect(w.every((s) => s.who == memberA), isTrue);
      expect(w[0].json, allOf(containsPair('event_id', 'ev-a'), containsPair('title', 'A panel')));
      expect(w[1].query, contains('id=eq.s-1'));
      expect(w[1].json, containsPair('title', 'A keynote 2'));
      expect(w[2].query, contains('id=eq.s-1'));
      expect(find.byType(SnackBar), findsNothing);
      expect(reported, isEmpty);
      // Each write re-read the agenda, as A.
      expect(server.log.where(reads).map((s) => s.who), List.filled(4, memberA));
      await unmountAll(t);
    });

    testWidgets("a token refresh keeps the agenda and A's open draft; Save sends it once",
        (t) async {
      await open(t);
      await openEditor(t);
      await t.enterText(find.byType(TextField).first, 'Kept draft');
      await refreshToken(t);
      expect(find.text('Edit Session'), findsOneWidget, reason: 'the editor closed on a refresh');
      expect(find.text('Kept draft'), findsOneWidget);
      await t.tap(find.text('Save changes'));
      await settleReal(t);
      expect(server.writes.single.who, memberA);
      expect(server.writes.single.json, containsPair('title', 'Kept draft'));
      expect(reported, isEmpty);
      expect(find.text('A keynote'), findsOneWidget);
      await unmountAll(t);
    });

    testWidgets('a pull to refresh reads again, as A', (t) async {
      await open(t);
      final refreshed =
          t.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show();
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      await settleReal(t);
      await t.pump(const Duration(seconds: 1));
      await refreshed;
      expect(server.log.where(reads).map((s) => s.who), [memberA, memberA]);
      expect(find.text('A keynote'), findsOneWidget);
      await unmountAll(t);
    });
  });
}
