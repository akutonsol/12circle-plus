import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/profile/presentation/integrations_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/coach_tools_server.dart';
import '../support/fit_matrix.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-59d (W29, E16) · Integrations belong to the member signed in, and a
// failure is said.
//
// The page read once and kept: the next member saw the last one's connections
// and their tap wrote from them. A failed read was shown as "not connected", a
// failed or 0-row change was not recorded, and a disconnect that changed no
// row was shown as done.
//
// HOW TO SEE IT FAIL: `git checkout a82f993 -- apps/mobile/lib/features/
// profile/presentation/integrations_screen.dart`; only the controls pass.

void main() {
  final server = CoachToolsServer();
  final reported = <AppFailure>[];
  final launched = <String>[];
  var canLaunch = true;
  var launchWorks = true;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(server);
  });

  Map<String, Object?> row(String uid, String provider) =>
      {'user_id': uid, 'provider': provider, 'connected': true};

  setUp(() {
    server.reset();
    reported.clear();
    launched.clear();
    canLaunch = launchWorks = true;
    setFailureSink(reported.add);
    server.tables['user_integrations'] = [row(memberA, 'strava')];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/url_launcher'), (c) async {
      if (c.method == 'canLaunch') return canLaunch;
      launched.add((c.arguments as Map)['url'] as String);
      return launchWorks;
    });
  });
  tearDown(() {
    resetFailureSink();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/url_launcher'), null);
  });

  Future<void> open(WidgetTester t, {String uid = memberA}) async {
    t.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 2400);
    addTearDown(t.view.reset);
    await t.runAsync(() => signInAs(uid));
    await t.pumpWidget(const MaterialApp(home: IntegrationsScreen()));
    await settleReal(t);
  }

  final connected = find.text('Connected');
  const failedLoad = "Couldn't load your connected apps";
  Iterable<String> origins() => reported.map((f) => f.origin);

  /// The pill in [name]'s row.
  Finder pillOf(String name, String state) => find.descendant(
      of: find.ancestor(of: find.text(name), matching: find.byType(Padding)).first,
      matching: find.text(state));

  VoidCallback stravaTap(WidgetTester t) => t
      .widget<GestureDetector>(find.ancestor(
          of: pillOf('Strava', 'Connected'), matching: find.byType(GestureDetector)).first)
      .onTap!;

  group('whose connections', () {
    testWidgets("A→B: A's are gone while B's are read, and after", (t) async {
      await open(t);
      expect(connected, findsOneWidget, reason: 'premise');
      final hold = server.hold((s) => s.who == memberB);
      await switchTo(t, memberB);
      expect(connected, findsNothing, reason: "A's connection is shown to B");
      hold.complete();
      await settleReal(t);
      expect(connected, findsNothing);
      expect(reported, isEmpty);
      await unmountAll(t);
    });

    testWidgets("a tap on A's Connected as B signed in writes nothing", (t) async {
      server.tables['user_integrations']!.add(row(memberB, 'whoop'));
      await open(t);
      final tap = stravaTap(t);
      await t.runAsync(() async {
        await signInAs(memberB);
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      tap(); // drawn for A; B's own state is loaded, nothing drawn since
      await settleReal(t);
      expect(server.writes, isEmpty, reason: "B's row written from A's state");
      expect(origins(), ['IntegrationsScreen._toggleConnect']);
      expect(find.textContaining("Couldn't"), findsNothing);
      await unmountAll(t);
    });

    testWidgets("A's late answer never becomes B's", (t) async {
      final late = server.hold((s) => s.who == memberA);
      await open(t);
      await switchTo(t, memberB);
      late.complete();
      await settleReal(t);
      expect(connected, findsNothing);
      await unmountAll(t);
    });

    testWidgets("a change of A's landing after B is not shown as B's", (t) async {
      await open(t);
      final hold = server.hold((s) => s.isWrite);
      await t.tap(connected);
      await settleReal(t);
      server.tables['user_integrations'] = [row(memberB, 'strava')];
      await switchTo(t, memberB);
      expect(connected, findsOneWidget, reason: "premise: B's own");
      hold.complete();
      await settleReal(t);
      expect(server.writes.single.who, memberA);
      expect(server.writes.single.query, contains('user_id=eq.$memberA'));
      expect(connected, findsOneWidget,
          reason: "A's disconnect was applied to B's row on screen");
      await unmountAll(t);
    });

    testWidgets("B's read failed: said, nothing of A's, nothing claimed", (t) async {
      await open(t);
      server.failing = (s) => s.who == memberB;
      await switchTo(t, memberB);
      expect(find.text(failedLoad), findsOneWidget);
      expect(connected, findsNothing);
      expect(find.text('Connect'), findsNothing);
      await unmountAll(t);
    });

    testWidgets('signed out, then the same member again', (t) async {
      await open(t);
      await signOutNow(t);
      expect(connected, findsNothing);
      expect(find.text('Connect'), findsNothing);
      expect(
          find.text("You're signed out — sign in again to see your integrations."),
          findsOneWidget);
      await switchTo(t, memberA);
      expect(pillOf('Strava', 'Connected'), findsOneWidget);
      expect(reported, isEmpty);
      await unmountAll(t);
    });

    testWidgets("A's open sheet closes, and its Connect connects nothing for B",
        (t) async {
      await open(t);
      await t.tap(pillOf('WHOOP', 'Connect'));
      await settleReal(t);
      expect(find.text('Connect with WHOOP'), findsOneWidget, reason: 'premise');
      await switchTo(t, memberB);
      expect(find.text('Connect with WHOOP'), findsNothing);
      expect(launched, isEmpty);
      expect(server.writes, isEmpty);
      await unmountAll(t);
    });

    testWidgets('positive control: a token refresh keeps the page', (t) async {
      await open(t);
      final reads = server.log.length;
      await refreshToken(t);
      expect(server.log.length, reads);
      expect(connected, findsOneWidget);
      await unmountAll(t);
    });
  });

  group('failures are said', () {
    for (final offline in [false, true]) {
      testWidgets('a failed load (${offline ? 'network' : 'server'}): said with '
          'a retry, toggles disabled', (t) async {
        final h = t.ensureSemantics();
        bool isRead(Sent s) => s.table == 'user_integrations' && !s.isWrite;
        offline ? server.offline = isRead : server.failing = isRead;
        await open(t);
        // (postgrest retries a read that did not reach the server, for seconds)
        for (var i = 0; offline && i < 12; i++) {
          await t.pump(const Duration(seconds: 1));
        }
        expect(find.text(failedLoad), findsOneWidget,
            reason: 'THE defect: shown as "not connected"');
        expect(
            find.text(offline
                ? 'Check your connection and try again. Connecting is paused until it loads.'
                : 'Try again in a moment. If it keeps happening, contact support. '
                    'Connecting is paused until it loads.'),
            findsOneWidget);
        expect(find.textContaining('SECRET'), findsNothing);
        expect(find.text('Connect'), findsNothing);
        expect(find.text('Not loaded'), findsWidgets);
        for (final p in find.text('Not loaded').evaluate().toList()) {
          await t.tapAt(t.getCenter(find.byWidget(p.widget)));
        }
        await settleReal(t);
        expect(server.writes, isEmpty);
        expect(find.byType(BottomSheet), findsNothing);
        expect(origins(), ['IntegrationsScreen._loadConnected']);
        final d = t
            .getSemantics(find.bySemanticsLabel('Strava: connection not loaded'))
            .getSemanticsData();
        expect(d.hasAction(SemanticsAction.tap), isFalse);

        // Busy-aware: two taps, one read; then it loads.
        server.offline = server.failing = (_) => false;
        final hold = server.hold(isRead);
        final reads = server.log.length;
        await t.tap(find.text('Try again'));
        await t.pump();
        await t.tap(find.bySemanticsLabel('Retrying'), warnIfMissed: false);
        await settleReal(t);
        expect(server.log.length, reads + 1);
        hold.complete();
        await settleReal(t);
        expect(find.text(failedLoad), findsNothing);
        expect(pillOf('Strava', 'Connected'), findsOneWidget);
        h.dispose();
        await unmountAll(t);
      });
    }

    testWidgets('negative control: nothing connected is not an error', (t) async {
      server.tables['user_integrations'] = [];
      await open(t);
      expect(find.text(failedLoad), findsNothing);
      expect(find.text('Connect'), findsWidgets);
      expect(reported, isEmpty);
      await unmountAll(t);
    });

    testWidgets('a disconnect that changed no row is not shown as done', (t) async {
      server.zeroRows = (s) => true;
      await open(t);
      await t.tap(connected);
      await settleReal(t);
      expect(server.writes.single.method, 'PATCH', reason: 'premise');
      expect(connected, findsOneWidget, reason: 'it is still connected');
      expect(
          find.text("Couldn't disconnect Strava — try again in a moment. If it "
              'keeps happening, contact support.'),
          findsOneWidget);
      expect(origins(), ['IntegrationsScreen._toggleConnect']);
      await unmountAll(t);
    });

    testWidgets('a failed disconnect is recorded and said; the connection hint '
        'only for the connection', (t) async {
      server.offline = (s) => s.isWrite;
      await open(t);
      await t.tap(connected);
      await settleReal(t);
      expect(
          find.text("Couldn't disconnect Strava — check your connection and try again."),
          findsOneWidget);
      expect(origins(), ['IntegrationsScreen._toggleConnect']);
      await unmountAll(t);
    });

    testWidgets('no double fire while a change is in flight', (t) async {
      await open(t);
      final tap = stravaTap(t);
      final hold = server.hold((s) => s.isWrite);
      tap();
      tap();
      await settleReal(t);
      expect(server.writes, hasLength(1));
      hold.complete();
      await settleReal(t);
      await unmountAll(t);
    });

    testWidgets('an authorization page that did not open is said, and nothing '
        'is marked connected', (t) async {
      launchWorks = false;
      await open(t);
      await t.tap(pillOf('WHOOP', 'Connect'));
      await settleReal(t);
      await t.tap(find.text('Connect with WHOOP'));
      await settleReal(t);
      expect(server.writes, isEmpty);
      expect(find.textContaining("Couldn't open WHOOP — "), findsOneWidget);
      expect(origins(), ['IntegrationsScreen._showOAuthSheet']);
      await unmountAll(t);
    });
  });

  group('positive controls', () {
    testWidgets('disconnect', (t) async {
      await open(t);
      await t.tap(connected);
      await settleReal(t);
      final w = server.writes.single;
      expect(w.who, memberA);
      expect(w.query, allOf(contains('user_id=eq.$memberA'), contains('provider=eq.strava')));
      expect(w.json, containsPair('connected', false));
      expect(connected, findsNothing);
      expect(reported, isEmpty);
      await unmountAll(t);
    });

    testWidgets('connect', (t) async {
      await open(t);
      await t.tap(pillOf('WHOOP', 'Connect'));
      await settleReal(t);
      await t.tap(find.text('Connect with WHOOP'));
      await settleReal(t);
      expect(launched.single, contains('whoop'));
      final w = server.writes.single;
      expect(w.json, allOf(containsPair('user_id', memberA),
          containsPair('provider', 'whoop'), containsPair('connected', true)));
      expect(pillOf('WHOOP', 'Connected'), findsOneWidget);
      expect(reported, isEmpty);
      await unmountAll(t);
    });

    for (final s in [1.0, 3.0]) {
      testWidgets('every toggle is a named 44px target (${s}x)', (t) async {
        final h = t.ensureSemantics();
        await t.runAsync(() => signInAs(memberA));
        fitWindow(t, 900, 6000, s);
        await t.pumpWidget(const MaterialApp(home: IntegrationsScreen()));
        await settleReal(t);
        expectNamedButton(t, 'Connected: disconnect Strava');
        expectNamedButton(t, 'Connect WHOOP');
        h.dispose();
        await unmountAll(t);
      });
    }
  });
}
