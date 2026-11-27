// P0-FL-59e · W31 / E9: one member's coaches, slots and calls are never shown
// to, booked, cancelled, announced or scored for another.
//
// HOW TO SEE IT FAIL: put back a82f993's booking_screen.dart; every test but
// the POSITIVE / NEGATIVE CONTROLs fails. (Added in round 2: "switched before
// the dialog is drawn" and the signed-out copy fail on 5f8b7f3 too; round 3's,
// tapped "with B's own loaded" or before they are, fail on 3a90049 too; round
// 4's "A -> B -> A" fails on e0736a6 too.)
import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/booking/presentation/booking_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/member_switch_server.dart';

void main() {
  final server = MemberSwitchServer();
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(server);
    watchAuthChanges();
  });

  setUp(() async {
    server.reset();
    await signInAs(memberA);
    reported.clear();
    setFailureSink(reported.add);
    final soon = DateTime.now().toUtc().add(const Duration(days: 2));
    Map<String, Object?> rel(String c) => {
          'coach_id': c,
          'status': 'active',
          'activated_at': '2026-10-01T00:00:00Z',
        };
    Map<String, Object?> coach(String id, String first) =>
        {'id': id, 'first_name': first, 'last_name': 'Stone'};
    Map<String, Object?> slot(String id, String c) => {
          'id': id,
          'coach_id': c,
          'type': 'check_in',
          'duration_minutes': 30,
          'slot_time': soon.toIso8601String(),
        };
    server.rows.addAll({
      'coach_client_relationships': {
        memberA: [rel('coach-a')],
        memberB: [rel('coach-b')],
      },
      'public_profiles': {
        memberA: [coach('coach-a', 'Avery')],
        memberB: [coach('coach-b', 'Blake')],
      },
      'coach_availability': {
        memberA: [slot('slot-a', 'coach-a')],
        memberB: [slot('slot-b', 'coach-b')],
      },
      'coaching_calls': {
        memberA: [
          {
            'id': 'call-a',
            'client_id': memberA,
            'coach_id': 'coach-a',
            'status': 'scheduled',
            'call_type': 'check_in',
            'duration_minutes': 30,
            'scheduled_at': soon.toIso8601String(),
          }
        ],
      },
    });
  });
  tearDown(resetFailureSink);

  Iterable<SeenRequest> asB() => server.writes().where((w) => w.who == memberB);

  Future<void> settle(WidgetTester t, [int n = 8]) async {
    for (var i = 0; i < n; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(500, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
        const ProviderScope(child: MaterialApp(home: BookingScreen())));
    await settle(t);
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 12));
  }

  Future<void> switchTo(WidgetTester t, String uid) =>
      t.runAsync(() => signInAs(uid));

  Finder bookButton() => find.byType(ElevatedButton).last;

  void nothingOfA() {
    expect(find.textContaining('Avery'), findsNothing);
    expect(find.text('Your Upcoming Calls'), findsNothing,
        reason: "A's call is on B's screen");
  }

  testWidgets("A -> B: A's coach, slots and call go; B's own are read",
      (t) async {
    await open(t);
    expect(find.textContaining('Avery'), findsWidgets, reason: 'premise');
    expect(find.text('Your Upcoming Calls'), findsOneWidget);
    server.seen.clear();
    await switchTo(t, memberB);
    await settle(t);
    nothingOfA();
    expect(find.textContaining('Blake'), findsWidgets);
    expect(server.seen.map((r) => r.who).toSet(), {memberB});
    await close(t);
  });

  testWidgets("B's read pending, then failed: never A's", (t) async {
    await open(t);
    final key = 'GET coach_client_relationships:$memberB';
    final hold = server.holds[key] = Completer();
    server.fails.add(key);
    await switchTo(t, memberB);
    await settle(t);
    nothingOfA();
    hold.complete();
    await settle(t);
    nothingOfA();
    expect(find.text("Couldn't load your bookings"), findsOneWidget);
    expect(find.text('No Coach Selected Yet'), findsNothing);
    await close(t);
  });

  testWidgets("A's load answers after B signed in (before and after B's): "
      'dropped', (t) async {
    for (final aFirst in [true, false]) {
      await switchTo(t, memberA);
      final holdA = server.holds['GET coach_availability:$memberA'] = Completer();
      final holdB = server.holds['GET coach_availability:$memberB'] = Completer();
      await open(t);
      await switchTo(t, memberB);
      await settle(t);
      (aFirst ? holdA : holdB).complete();
      await settle(t);
      nothingOfA();
      (aFirst ? holdB : holdA).complete();
      await settle(t);
      nothingOfA();
      expect(find.textContaining('Blake'), findsWidgets, reason: '$aFirst');
      await close(t);
    }
  });

  testWidgets("booked from A's undrawn list once B is signed in: nothing is "
      'sent', (t) async {
    await open(t);
    await switchTo(t, memberB);
    await t.tap(bookButton());
    await settle(t);
    expect(server.writes(), isEmpty,
        reason: "B booked A's coach: ${server.writes().toList()}");
    nothingOfA();
    await close(t);
  });

  testWidgets("A's booking answers after B signed in: no notification and no "
      'points as B, nothing said to B', (t) async {
    await open(t);
    final hold = server.holds['POST coaching_calls:$memberA'] = Completer();
    await t.tap(bookButton());
    await settle(t, 2);
    await switchTo(t, memberB);
    hold.complete();
    await settle(t);
    expect(server.writes('coaching_calls').single.row['client_id'], memberA);
    expect(asB(), isEmpty);
    expect(find.byType(SnackBar), findsNothing);
    await close(t);
  });

  testWidgets("A's booking fails after B signed in: B is not told", (t) async {
    await open(t);
    final hold = server.holds['POST coaching_calls:$memberA'] = Completer();
    server.fails.add('POST coaching_calls:$memberA');
    await t.tap(bookButton());
    await settle(t, 2);
    await switchTo(t, memberB);
    hold.complete();
    await settle(t);
    expect(find.byType(SnackBar), findsNothing);
    expect(reported.map((f) => f.origin), contains('BookingScreen._book'));
    expect(asB(), isEmpty);
    await close(t);
  });

  testWidgets("A's cancel dialog goes with A; confirmed before it is redrawn, "
      'nothing is sent', (t) async {
    await open(t);
    await t.tap(find.text('Cancel'));
    await settle(t);
    expect(find.text('Cancel session?'), findsOneWidget, reason: 'premise');
    await switchTo(t, memberB);
    await t.tap(find.text('Cancel session'), warnIfMissed: false);
    await settle(t);
    expect(server.writes(), isEmpty);
    expect(find.text('Cancel session?'), findsNothing);
    await close(t);
  });

  testWidgets("A's cancel answers after B signed in: A's coach is not notified "
      'as B', (t) async {
    await open(t);
    final hold = server.holds['PATCH coaching_calls:$memberA'] = Completer();
    await t.tap(find.text('Cancel'));
    await settle(t);
    await t.tap(find.text('Cancel session'));
    await settle(t, 3);
    await switchTo(t, memberB);
    hold.complete();
    await settle(t);
    expect(server.writes('notifications'), isEmpty);
    expect(find.text('Session cancelled.'), findsNothing);
    await close(t);
  });

  testWidgets("A's cancel dialog, switched before it is drawn: never drawn for "
      'B, and it goes', (t) async {
    await open(t);
    await t.tap(find.text('Cancel'));
    await switchTo(t, memberB); // pushed; no frame yet
    await t.pump();
    expect(find.text('Cancel session?'), findsNothing);
    await settle(t);
    expect(find.byType(ModalBarrier), findsOneWidget,
        reason: 'only the page: an invisible dialog would swallow every tap');
    expect(server.writes(), isEmpty);
    await close(t);
  });

  testWidgets("B signs in while A's name is read for the notification: it is "
      'not sent as B, no points', (t) async {
    await open(t);
    final hold = server.holds['GET user_profiles:$memberA'] = Completer();
    server.seen.clear();
    await t.tap(bookButton());
    await settle(t, 4);
    expect(server.reads('user_profiles', memberA), hasLength(1),
        reason: 'premise');
    await switchTo(t, memberB);
    hold.complete();
    await settle(t);
    expect(server.writes('coaching_calls'), hasLength(1));
    expect(server.writes('notifications'), isEmpty);
    expect(asB(), isEmpty);
    expect(find.byType(SnackBar), findsNothing);
    await close(t);
  });

  /// B's own coaches and slots are loaded, and no frame is drawn: what is up
  /// is still A's.
  Future<void> bLoaded(WidgetTester t) async {
    await switchTo(t, memberB);
    await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)));
    expect(server.reads('coaching_calls', memberB), isNotEmpty,
        reason: 'premise: B is loaded');
    reported.clear();
    server.seen.clear();
  }

  testWidgets("A's slot, booked from the undrawn list with B's own loaded: "
      'nothing is sent, recorded', (t) async {
    await open(t);
    final book = t.widget<ElevatedButton>(bookButton()).onPressed!;
    await bLoaded(t);
    book();
    await settle(t);
    expect(server.writes(), isEmpty,
        reason: "B booked A's slot: ${server.writes().toList()}");
    expect(reported.map((f) => f.origin), contains('BookingScreen.identity'));
    expect(find.byType(SnackBar), findsNothing);
    expect(find.textContaining('Blake'), findsWidgets);
    await close(t);
  });

  testWidgets("A's call, cancelled from the undrawn list with B's own loaded: "
      'no dialog for B, nothing is sent', (t) async {
    await open(t);
    await bLoaded(t);
    await t.tap(find.text('Cancel'));
    await settle(t);
    expect(find.text('Cancel session?'), findsNothing);
    expect(server.writes(), isEmpty);
    await close(t);
  });

  testWidgets("A -> B -> A with no frame, B's own loaded between: A's old slot "
      "is not booked with B's coach; A's own are read again", (t) async {
    await open(t);
    final book = t.widget<ElevatedButton>(bookButton()).onPressed!;
    await bLoaded(t);
    // The instant A is back: the screen has not heard, and holds B's.
    await t.runAsync(() => switchAnd(memberA, book));
    await settle(t);
    expect(server.writes(), isEmpty,
        reason: "A's slot, B's coach: ${server.writes().toList()}");
    expect(reported.map((f) => f.origin), ['BookingScreen.identity']);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.textContaining('Avery'), findsWidgets);
    expect(find.textContaining('Blake'), findsNothing);
    // And theirs works.
    await t.tap(bookButton());
    await settle(t);
    final call = server.writes('coaching_calls').single;
    expect((call.who, call.row['coach_id']), (memberA, 'coach-a'));
    await close(t);
  });

  group("two coaches", () {
    testWidgets("A's other coach, picked in the undrawn list with B's own "
        'loaded: not read as B, B keeps their own', (t) async {
      await open(t);
      await bLoaded(t);
      await t.tap(find.text('Casey Moss'));
      await settle(t);
      expect(server.seen.where((r) => '${r.query}'.contains('coach-c')), isEmpty,
          reason: "A's coach was read for B");
      expect(reported.map((f) => f.origin), ['BookingScreen.identity']);
      expect(find.textContaining('Blake'), findsWidgets);
      expect(find.text("Couldn't load your bookings"), findsNothing);
      await close(t);
    });

    testWidgets("picked before B's are loaded: B's own still arrive",
        (t) async {
      await open(t);
      final hold =
          server.holds['GET coach_client_relationships:$memberB'] = Completer();
      await switchTo(t, memberB);
      await t.tap(find.text('Casey Moss'));
      hold.complete();
      await settle(t);
      expect(find.textContaining('Blake'), findsWidgets);
      await close(t);
    });

    setUp(() {
      Map<String, Object?> rel(String c) => {
            'coach_id': c,
            'status': 'active',
            'activated_at': '2026-10-01T00:00:00Z',
          };
      server.rows['coach_client_relationships']![memberA] = [
        rel('coach-a'), rel('coach-c'),
      ];
      server.rows['public_profiles']![memberA] = [
        {'id': 'coach-a', 'first_name': 'Avery', 'last_name': 'Stone'},
        {'id': 'coach-c', 'first_name': 'Casey', 'last_name': 'Moss'},
      ];
    });

    List<Map<String, Object?>> slotOf(String id) => [
          {
            'id': id,
            'coach_id': id,
            'type': 'check_in',
            'duration_minutes': 30,
            'slot_time': DateTime.now()
                .toUtc()
                .add(const Duration(days: 2))
                .toIso8601String(),
          },
        ];

    for (final fails in [false, true]) {
      testWidgets(
          "A's other coach's slots ${fails ? 'fail' : 'answer'} after B signed "
          "in and B's are shown: dropped", (t) async {
        await open(t);
        final key = 'GET coach_availability:$memberA';
        final hold = server.holds[key] = Completer();
        await t.tap(find.text('Casey Moss'));
        await settle(t, 2);
        if (fails) server.fails.add(key);
        await switchTo(t, memberB);
        await settle(t);
        expect(find.textContaining('Blake'), findsWidgets, reason: 'premise');
        hold.complete();
        await settle(t);
        expect(find.textContaining('Blake'), findsWidgets);
        expect(find.textContaining('Casey'), findsNothing);
        expect(find.text("Couldn't load your bookings"), findsNothing);
        await close(t);
      });
    }

    testWidgets('picked in the undrawn list once B is signed in: nothing of '
        "A's is read as B", (t) async {
      await open(t);
      server.seen.clear();
      await switchTo(t, memberB);
      await t.tap(find.text('Casey Moss'));
      await settle(t);
      expect(
          server.seen.where((r) =>
              r.who == memberB && '${r.query}'.contains('coach-c')),
          isEmpty);
      expect(find.textContaining('Casey'), findsNothing);
      await close(t);
    });

    testWidgets('the first coach\'s late slots are not shown as the second\'s',
        (t) async {
      await open(t);
      final key = 'GET coach_availability:$memberA';
      server.rows['coach_availability']![memberA] = slotOf('slot-c');
      final first = server.holds[key] = Completer();
      await t.tap(find.text('Casey Moss'));
      await settle(t, 2);
      server.rows['coach_availability']![memberA] = slotOf('slot-a2');
      final second = server.holds[key] = Completer();
      // Casey's slots are still out: back to Avery.
      await t.tap(find.text('Avery Stone').first);
      await settle(t, 2);
      second.complete();
      await settle(t);
      first.complete();
      await settle(t);
      await t.tap(bookButton());
      await settle(t);
      final call = server.writes('coaching_calls').single.row;
      expect((call['coach_id'], call['availability_slot_id']),
          ('coach-a', 'slot-a2'));
      await close(t);
    });

    testWidgets('another coach is picked while a booking is out: the one that '
        'was booked is told', (t) async {
      await open(t);
      final hold = server.holds['POST coaching_calls:$memberA'] = Completer();
      await t.tap(bookButton());
      await settle(t, 2);
      await t.tap(find.text('Casey Moss'));
      await settle(t);
      hold.complete();
      await settle(t);
      expect(server.writes('coaching_calls').single.row['coach_id'], 'coach-a');
      expect(server.writes('notifications').single.row['recipient_id'],
          'coach-a');
      await close(t);
    });
  });

  testWidgets("signed out: A's calls go away; A back in: theirs again",
      (t) async {
    await open(t);
    await t.runAsync(signOut);
    await settle(t);
    nothingOfA();
    expect(find.text('No Coach Selected Yet'), findsNothing,
        reason: 'a claim about a member nobody knows');
    expect(find.text("You're signed out — sign in again to book a call."),
        findsOneWidget);
    await switchTo(t, memberA);
    await settle(t);
    expect(find.text('Your Upcoming Calls'), findsOneWidget);
    await close(t);
  });

  testWidgets('POSITIVE CONTROL: a token refresh reads nothing; the booking is '
      'saved, announced and scored for its member', (t) async {
    await open(t);
    server.seen.clear();
    await t.runAsync(refreshSession);
    await settle(t);
    expect(server.seen, isEmpty);
    await t.tap(bookButton());
    await settle(t);
    final call = server.writes('coaching_calls').single;
    expect((call.who, call.row['client_id'], call.row['coach_id']),
        (memberA, memberA, 'coach-a'));
    expect(server.writes('notifications').single.row['recipient_id'], 'coach-a');
    expect(server.writes('award_points').single.who, memberA);
    expect(find.text('Call booked! Your coach has been notified.'),
        findsOneWidget);
    expect(reported, isEmpty);
    await close(t);
  });

  testWidgets('NEGATIVE CONTROL: a member with no coach is told so, not shown '
      'a failure', (t) async {
    server.rows.remove('coach_client_relationships');
    await open(t);
    expect(find.text('No Coach Selected Yet'), findsOneWidget);
    expect(reported, isEmpty);
    await close(t);
  });
}
