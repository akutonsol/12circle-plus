import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/classes/presentation/event_ticket_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/owned_rows_postgrest.dart';
import '../support/pump_until.dart';
import '../support/settled.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-60c (c) + E12 + S8 · the event ticket. A failed read of the
// registration offered "Register" to a registered member; failed writes were
// unrecorded; A's ticket and code stayed on screen for B.
//
// HOW TO SEE IT FAIL: `git checkout a82f993 --` event_ticket_screen.dart.

const _regs = 'event_registrations';
const _register = 'Register & Get Ticket';
const _support =
    'try again in a moment. If it keeps happening, contact support.';

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
  void registered(String uid, String? code) =>
      (server.rows[_regs] ??= []).add({
        'id': 'r-$uid', 'event_id': 'e1', 'user_id': uid,
        'qr_code': code, 'status': 'confirmed',
      });
  Iterable<String> origins() => reported.map((f) => f.origin);

  Future<void> settle(WidgetTester tester) => settledFrames(tester, server,
      step: const Duration(milliseconds: 20));

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

  Future<void> become(WidgetTester tester, String? uid) async {
    await tester.runAsync(() => uid == null ? signOut() : signInAs(uid));
    await settle(tester);
  }

  Future<void> done(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
  }

  testWidgets('control: a registered member sees their ticket', (tester) async {
    registered(memberA, 'TKT-A');
    await show(tester);
    expect(text('TKT-A'), findsOneWidget);
    expect(text(_register), findsNothing);
    await done(tester);
  });

  testWidgets('control: not registered is offered Register, and it registers',
      (tester) async {
    await show(tester);
    await tester.tap(text(_register));
    await settle(tester);
    final w = server.writes(_regs).single;
    expect(w.body['user_id'], memberA);
    expect(text(w.body['qr_code']! as String), findsOneWidget);
    expect(text('CONFIRMED'), findsOneWidget);
    expect(reported, isEmpty);
    await done(tester);
  });

  for (final (name, arrange, hint) in <(String, void Function(), String)>[
    ('refused', () => server.fails.add('GET $_regs:$memberA'),
        'Try again in a moment. If it keeps happening, contact support.'),
    ('offline', () => server.offline.add('GET $_regs:$memberA'),
        'Check your connection and try again.'),
  ]) {
    testWidgets('a status read that was $name is not "not registered"',
        (tester) async {
      registered(memberA, 'TKT-A');
      arrange();
      await show(tester);
      // postgrest retries a GET that never reached the server (1 s, 2 s, 4 s).
      await pumpUntil(
          tester,
          () =>
              text("Couldn't load your registration").evaluate().isNotEmpty ||
              text(_register).evaluate().isNotEmpty,
          what: 'the read to end', step: const Duration(milliseconds: 100));
      expect(text(_register), findsNothing,
          reason: 'THE defect: a registered member was offered Register');
      expect(text("Couldn't load your registration"), findsOneWidget);
      expect(text('$hint Registering is paused until it loads.'), findsOneWidget);
      expect(origins(), contains('EventTicketScreen.checkRegistration'));

      server.fails.clear();
      server.offline.clear();
      final hold = server.holds['GET $_regs:$memberA'] = Completer<void>();
      await tester.tap(text('Try again'));
      await settle(tester);
      expect(find.bySemanticsLabel('Retrying'), findsOneWidget);
      expect(text(_register), findsNothing);
      hold.complete();
      await settle(tester);
      expect(text('TKT-A'), findsOneWidget);
      expect(server.writes(_regs), isEmpty);
      await done(tester);
    });
  }

  testWidgets('a status read still pending offers nothing to tap',
      (tester) async {
    registered(memberA, 'TKT-A');
    final hold = server.holds['GET $_regs:$memberA'] = Completer<void>();
    await show(tester);
    expect(text(_register), findsNothing,
        reason: 'THE defect: Register was offered before the answer');
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull);
    hold.complete();
    await settle(tester);
    expect(text('TKT-A'), findsOneWidget);
    await done(tester);
  });

  testWidgets('registered with no code is registered: no second registration',
      (tester) async {
    registered(memberA, null);
    await show(tester);
    expect(text(_register), findsNothing);
    expect(find.textContaining("You're registered"), findsOneWidget);
    await done(tester);
  });

  testWidgets('a refused registration is recorded and said', (tester) async {
    server.fails.add('POST $_regs:$memberA');
    await show(tester);
    await tester.tap(text(_register));
    await settle(tester);
    expect(text("Couldn't complete your registration — $_support"), findsOneWidget);
    expect(origins(), contains('EventTicketScreen.register'),
        reason: 'THE defect: unrecorded');
    expect(text('CONFIRMED'), findsNothing);
    server.fails.clear();
    await tester.tap(text(_register));
    await settle(tester);
    expect(text('CONFIRMED'), findsOneWidget, reason: 'and can be tried again');
    await done(tester);
  });

  testWidgets('already registered (23505) shows the ticket that EXISTS',
      (tester) async {
    await show(tester);
    registered(memberA, 'TKT-REAL'); // on another device, since
    await tester.tap(text(_register));
    await settle(tester);
    expect(text('TKT-REAL'), findsOneWidget,
        reason: 'THE defect: "could not complete your registration"');
    expect(find.textContaining("Couldn't"), findsNothing);
    await done(tester);
  });

  testWidgets('already registered, but the re-read fails: said as unread',
      (tester) async {
    await show(tester);
    registered(memberA, 'TKT-REAL');
    server.fails.add('GET $_regs:$memberA');
    await tester.tap(text(_register));
    await settle(tester);
    expect(text(_register), findsNothing);
    expect(text('CONFIRMED'), findsNothing);
    expect(text("Couldn't load your registration"), findsOneWidget);
    await done(tester);
  });

  testWidgets('leaving while registering does not setState after dispose (S8)',
      (tester) async {
    final hold = server.holds['POST $_regs:$memberA'] = Completer<void>();
    await show(tester);
    await tester.tap(text(_register));
    await settle(tester);
    await tester.pumpWidget(const SizedBox());
    hold.complete();
    await settle(tester);
    expect(tester.takeException(), isNull,
        reason: 'THE defect: setState in finally without mounted');
  });

  testWidgets('a checkout that did not start is recorded and said',
      (tester) async {
    await show(tester, free: false);
    await tester.tap(find.byType(ElevatedButton));
    await pumpUntil(
        tester, () => origins().contains('EventTicketScreen.buyTicket'),
        what: 'the failed checkout');
    await settle(tester);
    expect(text("Couldn't start checkout — $_support"), findsOneWidget);
    expect(server.writes(_regs), isEmpty);
    await done(tester);
  });

  group('A->B', () {
    testWidgets("A's ticket goes at once; B's own status shows", (tester) async {
      registered(memberA, 'TKT-A');
      registered(memberB, 'TKT-B');
      await show(tester);
      final hold = server.holds['GET $_regs:$memberB'] = Completer<void>();
      await become(tester, memberB);
      expect(text('TKT-A'), findsNothing,
          reason: "THE defect: A's ticket was shown to B");
      expect(text(_register), findsNothing);
      hold.complete();
      await settle(tester);
      expect(text('TKT-B'), findsOneWidget);
      await done(tester);
    });

    testWidgets("B's read failed: no ticket, no Register", (tester) async {
      registered(memberA, 'TKT-A');
      await show(tester);
      server.fails.add('GET $_regs:$memberB');
      await become(tester, memberB);
      expect(text('TKT-A'), findsNothing);
      expect(text(_register), findsNothing);
      expect(text("Couldn't load your registration"), findsOneWidget);
      await done(tester);
    });

    for (final afterB in [false, true]) {
      testWidgets(
          "A's held read landing ${afterB ? 'after' : 'before'} B's is dropped",
          (tester) async {
        registered(memberA, 'TKT-A');
        final holdA = server.holds['GET $_regs:$memberA'] = Completer<void>();
        final holdB = server.holds['GET $_regs:$memberB'] = Completer<void>();
        await show(tester);
        await become(tester, memberB);
        if (afterB) {
          holdB.complete();
          await settle(tester);
          expect(text(_register), findsOneWidget, reason: "B's own answer");
        }
        holdA.complete();
        await settle(tester);
        expect(text('TKT-A'), findsNothing,
            reason: "THE defect: A's late ticket was shown to B");
        if (!afterB) holdB.complete();
        await settle(tester);
        expect(text(_register), findsOneWidget);
        await done(tester);
      });
    }

    testWidgets("A's registration in flight never becomes B's", (tester) async {
      final hold = server.holds['POST $_regs:$memberA'] = Completer<void>();
      await show(tester);
      await tester.tap(text(_register));
      await settle(tester);
      await become(tester, memberB);
      hold.complete();
      await settle(tester);
      expect(text('CONFIRMED'), findsNothing,
          reason: "THE defect: A's code was shown to B as confirmed");
      expect(text(_register), findsOneWidget);
      expect(
          tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
          isNotNull);
      expect(server.writes(_regs).map((w) => w.who), [memberA]);
      await done(tester);
    });

    testWidgets("A's Register tapped with B already signed in sends nothing",
        (tester) async {
      await show(tester);
      final tap = tester
          .widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed!;
      // The auth client has B; this screen has not been told yet.
      tester.element(find.byType(EventTicketScreen)); // still mounted
      await tester.runAsync(() => signInAs(memberB));
      tap();
      await settle(tester);
      expect(server.writes(_regs).where((w) => w.body['user_id'] == memberA),
          isEmpty);
      expect(server.writes(_regs), isEmpty,
          reason: 'THE defect: B was registered by a tap made as A');
      await done(tester);
    });

    testWidgets('sign-out takes the ticket; A again sees it', (tester) async {
      registered(memberA, 'TKT-A');
      await show(tester);
      await become(tester, null);
      expect(text('TKT-A'), findsNothing);
      expect(text(_register), findsNothing);
      await become(tester, memberA);
      expect(text('TKT-A'), findsOneWidget);
      await done(tester);
    });

    testWidgets('control: a token refresh keeps the ticket, reads nothing again',
        (tester) async {
      registered(memberA, 'TKT-A');
      await show(tester);
      final token = Supabase.instance.client.auth.currentSession!.accessToken;
      final asked = server.log.length;
      await tester.runAsync(refreshSession);
      await settle(tester);
      expect(Supabase.instance.client.auth.currentSession!.accessToken,
          isNot(token));
      expect(text('TKT-A'), findsOneWidget);
      expect(server.log.length, asked);
      await done(tester);
    });
  });
}
