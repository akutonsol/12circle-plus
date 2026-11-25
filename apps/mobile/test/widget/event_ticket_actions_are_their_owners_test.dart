import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/classes/presentation/event_ticket_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/owned_rows_postgrest.dart';
import '../support/pump_until.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-60c round 2 (QA 3) · A Register button drawn for A registered B: the
// screen follows the account without a frame, so once B's own "not registered"
// had been read the stale button passed every check — as B. Buy likewise, and
// its checkout would have been B's.
//
// HOW TO SEE IT FAIL: `git checkout fd5d076 --` event_ticket_screen.dart.

const _regs = 'event_registrations';
const _checkout = 'create-checkout';
const _register = 'Register & Get Ticket';

void main() {
  final server = OwnedRowsPostgrest();
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(server);
  });

  setUp(() async {
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
    await signInAs(memberA);
  });
  tearDown(resetFailureSink);

  Finder text(String s) => find.text(s);
  String? signedIn() => Supabase.instance.client.auth.currentUser?.id;
  Iterable<String> accountChanged() => reported
      .where((f) => '${f.error}'.contains('the signed-in account changed'))
      .map((f) => f.origin);
  Iterable<String> checkouts() =>
      server.calls.where((k) => k.contains(_checkout));

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  /// Real time passes and answers land; no frame runs.
  Future<void> noFrame(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.idle();
    }
  }

  Future<void> show(WidgetTester tester, {bool free = true}) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 2200);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        home: EventTicketScreen(event: {
      'id': 'e1', 'title': 'Run Club', 'is_free': free, 'price': 20,
      'event_date': '2026-11-12T18:00:00+00:00',
    })));
    await settle(tester);
  }

  Future<void> done(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
  }

  /// The rendered button, as it was built.
  VoidCallback button(WidgetTester tester) =>
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed!;

  for (final free in [true, false]) {
    final what = free ? 'Register' : 'Buy';
    final origin = 'EventTicketScreen.${free ? 'register' : 'buyTicket'}';

    for (final bRead in [false, true]) {
      testWidgets(
          "A's $what pressed with B signed in and no frame since"
          "${bRead ? ", B's status read" : ''}: nothing is sent", (tester) async {
        await show(tester, free: free);
        final tap = button(tester);
        if (!bRead) server.holds['GET $_regs:$memberB'] = Completer<void>();
        await tester.runAsync(() => signInAs(memberB));
        await noFrame(tester);
        expect(server.asked('GET $_regs:$memberB'), isTrue,
            reason: "premise: the screen follows, and B's status is asked for");
        tap();
        await noFrame(tester);
        expect(server.writes(_regs), isEmpty,
            reason: 'THE defect: B was registered by a button of A');
        expect(checkouts(), isEmpty,
            reason: "THE defect: A's button opened a checkout for B");
        expect(accountChanged(), [origin], reason: 'recorded');
        server.holds['GET $_regs:$memberB']?.complete();
        await settle(tester);
        expect(find.textContaining("Couldn't"), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        await done(tester);
      });
    }

    testWidgets("A's $what pressed in the turn the client changes: nothing is sent",
        (tester) async {
      await show(tester, free: free);
      final tap = button(tester);
      await tester.runAsync(() async {
        final switching = signInAs(memberB);
        expect(signedIn(), memberB, reason: 'premise: before any event');
        tap();
        await switching;
      });
      await settle(tester);
      expect(server.writes(_regs), isEmpty);
      expect(checkouts(), isEmpty);
      expect(accountChanged(), [origin]);
      expect(find.textContaining("Couldn't"), findsNothing);
      await done(tester);
    });

    testWidgets("control: B's own $what works after the switch", (tester) async {
      await show(tester, free: free);
      await tester.runAsync(() => signInAs(memberB));
      await settle(tester);
      button(tester)();
      await settle(tester);
      if (free) {
        expect(server.writes(_regs).single.body['user_id'], memberB);
        expect(text('CONFIRMED'), findsOneWidget);
      } else {
        expect(checkouts(), ['POST $_checkout:$memberB']);
      }
      expect(accountChanged(), isEmpty);
      await done(tester);
    });

    testWidgets('control: A\'s $what works across a token refresh, no frame since',
        (tester) async {
      await show(tester, free: free);
      final tap = button(tester);
      var refreshed = false;
      final sub = Supabase.instance.client.auth.onAuthStateChange.listen((s) {
        if (s.event == AuthChangeEvent.tokenRefreshed) refreshed = true;
      });
      await tester.runAsync(refreshSession);
      await noFrame(tester);
      expect(refreshed, isTrue, reason: 'premise: the event arrived');
      tap();
      await settle(tester);
      if (free) {
        expect(server.writes(_regs).single.body['user_id'], memberA);
        expect(text('CONFIRMED'), findsOneWidget);
      } else {
        expect(checkouts(), ['POST $_checkout:$memberA']);
      }
      expect(accountChanged(), isEmpty);
      unawaited(sub.cancel());
      await done(tester);
    });

    testWidgets("$what's spinner says what is on its way", (tester) async {
      server.holds['POST ${free ? _regs : _checkout}:$memberA'] =
          Completer<void>();
      await show(tester, free: free);
      button(tester)();
      await settle(tester);
      expect(
          find.bySemanticsLabel(free ? 'Registering' : 'Starting checkout'),
          findsOneWidget,
          reason: 'THE defect: a disabled button with no name');
      server.holds['POST ${free ? _regs : _checkout}:$memberA']!.complete();
      await settle(tester);
      await done(tester);
    });
  }

  for (final to in [memberB, null]) {
    final who = to == null ? 'nobody' : 'B';
    for (final fails in [false, true]) {
      testWidgets(
          "A's checkout, ${fails ? 'refused' : 'without a URL'}, landing with "
          '$who signed in and no frame since: nothing is said', (tester) async {
        final hold =
            server.holds['POST $_checkout:$memberA'] = Completer<void>();
        if (fails) server.fails.add('POST $_checkout:$memberA');
        await show(tester, free: false);
        button(tester)();
        await pumpUntil(tester, () => checkouts().isNotEmpty, what: 'the checkout');
        await tester.runAsync(() => to == null ? signOut() : signInAs(to));
        hold.complete();
        await pumpUntil(
            tester, () => accountChanged().contains('EventTicketScreen.buyTicket'),
            what: 'the dropped checkout to be recorded');
        await settle(tester);
        expect(find.textContaining("Couldn't"), findsNothing,
            reason: "A's checkout is not $who's news");
        expect(checkouts(), ['POST $_checkout:$memberA']);
        if (to != null) {
          expect(text(r'Buy Ticket — $20'), findsOneWidget,
              reason: "B's own button, not A's spinner");
          expect(button(tester), isNotNull);
        }
        await done(tester);
      });
    }
  }

  for (final (name, arrange) in <(String, void Function())>[
    ('taken', () {}),
    ('refused', () => server.fails.add('POST $_regs:$memberA')),
    (
      'a duplicate',
      () => (server.rows[_regs] ??= []).add({
            'id': 'r-A', 'event_id': 'e1', 'user_id': memberA,
            'qr_code': 'TKT-A', 'status': 'confirmed',
          })
    ),
  ]) {
    testWidgets("A's registration, $name, landing in the turn the client changes",
        (tester) async {
      final hold = server.holds['POST $_regs:$memberA'] = Completer<void>();
      await show(tester);
      arrange();
      button(tester)();
      await settle(tester);
      // The client has B; the screen has been told of nobody.
      final asked = server.log.length;
      await tester.runAsync(() async {
        hold.complete();
        final switching = signInAs(memberB);
        expect(signedIn(), memberB, reason: 'premise');
        await switching;
      });
      await noFrame(tester);
      await settle(tester);
      expect(text('CONFIRMED'), findsNothing);
      expect(find.textContaining("Couldn't"), findsNothing);
      expect(
          server.log.skip(asked).where((a) =>
              a.query['user_id'] == 'eq.$memberA'),
          isEmpty,
          reason: "A's registration is not read with B's session");
      expect(text(_register), findsOneWidget, reason: "B's own");
      await done(tester);
    });
  }
}
