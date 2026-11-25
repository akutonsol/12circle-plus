import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/coach/presentation/coach_availability_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/coach_tools_server.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-59d (E8, W22) · Manage Availability stays the coach's who opened it.
//
// The page read once and kept: after a switch on this device (another tab, or
// a sign-out and sign-in) coach B saw coach A's clients and session times,
// "Publish Slot" in A's open sheet created the slot for B, and a cancel A had
// started reopened the slot and notified A's client as B.
//
// HOW TO SEE IT FAIL: `git checkout a82f993 -- apps/mobile/lib/features/
// coach/presentation/coach_availability_screen.dart`; only the controls pass.

void main() {
  final server = CoachToolsServer();
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(server);
  });

  String at(int hours) =>
      DateTime.now().toUtc().add(Duration(hours: hours)).toIso8601String();

  Map<String, Object?> session(String coach, String first) => {
        'id': 'call-$first', 'coach_id': coach, 'scheduled_at': at(30),
        'duration_minutes': 30, 'call_type': 'check_in', 'status': 'scheduled',
        'availability_slot_id': 'slot-$first', 'client_id': 'client-$first',
        'client': {'first_name': first, 'last_name': 'Client', 'avatar_url': null},
      };
  Map<String, Object?> slot(String coach, String type) => {
        'id': 'open-$type', 'coach_id': coach, 'slot_time': at(40),
        'duration_minutes': 45, 'type': type, 'is_booked': false,
      };

  setUp(() {
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
    server.tables['coaching_calls'] = [session(memberA, 'Ana'), session(memberB, 'Bob')];
    server.tables['coach_availability'] = [
      slot(memberA, 'consultation'), slot(memberB, 'nutrition_review'),
    ];
  });
  tearDown(resetFailureSink);

  Future<void> open(WidgetTester t, {String uid = memberA}) async {
    t.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 2400);
    addTearDown(t.view.reset);
    await t.runAsync(() => signInAs(uid));
    await t.pumpWidget(const MaterialApp(home: CoachAvailabilityScreen()));
    await settleReal(t);
  }

  final anas = find.text('Ana Client');
  final bobs = find.text('Bob Client');
  final anasSlot = find.text('Strategy Consultation');
  final bobsSlot = find.text('Nutrition Review');
  Iterable<String> changed() => reported
      .where((f) => '${f.error}'.contains('signed-in account changed'))
      .map((f) => f.origin);

  void nothingOfAs(WidgetTester t) {
    expect(anas, findsNothing, reason: "A's client is shown to B");
    expect(anasSlot, findsNothing, reason: "A's slot is shown to B");
  }

  group('what is shown', () {
    testWidgets('A→B: B sees B, never A — while B is being read, too', (t) async {
      await open(t);
      expect(anas, findsOneWidget, reason: 'premise');
      expect(anasSlot, findsOneWidget, reason: 'premise');
      final hold = server.hold((s) => s.who == memberB);
      await switchTo(t, memberB);
      nothingOfAs(t);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      hold.complete();
      await settleReal(t);
      nothingOfAs(t);
      expect(bobs, findsOneWidget);
      expect(bobsSlot, findsOneWidget);
      expect(reported, isEmpty);
      await unmountAll(t);
    });

    testWidgets("B's read failed: said, and still nothing of A's", (t) async {
      await open(t);
      server.failing = (s) => s.who == memberB;
      await switchTo(t, memberB);
      nothingOfAs(t);
      expect(find.textContaining("Couldn't load your availability"), findsOneWidget);
      expect(find.textContaining('SECRET'), findsNothing);
      await unmountAll(t);
    });

    for (final afterB in [false, true]) {
      testWidgets(
          "A's late answer is dropped (${afterB ? 'after' : 'before'} B's own)",
          (t) async {
        final late = server.hold(
            (s) => s.who == memberA && s.table == 'coach_availability');
        await open(t);
        final bHeld = afterB ? null : server.hold((s) => s.who == memberB);
        await switchTo(t, memberB);
        late.complete();
        await settleReal(t);
        nothingOfAs(t);
        if (afterB) expect(bobsSlot, findsOneWidget);
        bHeld?.complete();
        await settleReal(t);
        nothingOfAs(t);
        expect(bobsSlot, findsOneWidget);
        expect(
            server.to('coaching_calls').where((s) =>
                s.who == memberB && s.query.contains('coach_id=eq.$memberA')),
            isEmpty,
            reason: "A's second read is not sent as B");
        await unmountAll(t);
      });
    }

    for (final (read, afterB) in [
      ('coach_availability', false), ('coach_availability', true),
      ('coaching_calls', false), ('coaching_calls', true),
    ]) {
      testWidgets("A's late FAILED read of $read is not B's failure "
          "(${afterB ? 'after' : 'before'} B's own)", (t) async {
        final late = server.hold((s) => s.who == memberA && s.table == read);
        server.failing = (s) => s.who == memberA && s.table == read;
        await open(t);
        final bHeld = afterB ? null : server.hold((s) => s.who == memberB);
        await switchTo(t, memberB);
        if (afterB) expect(bobsSlot, findsOneWidget, reason: 'premise');
        late.complete();
        await settleReal(t);
        expect(find.textContaining("Couldn't"), findsNothing,
            reason: "A's failure is said to B");
        if (!afterB) {
          expect(find.byType(CircularProgressIndicator), findsOneWidget,
              reason: "B's own read is still pending");
        }
        bHeld?.complete();
        await settleReal(t);
        expect(bobsSlot, findsOneWidget);
        expect(find.textContaining("Couldn't"), findsNothing);
        expect(reported.map((f) => f.origin), ['CoachAvailabilityScreen._load'],
            reason: 'recorded all the same');
        await unmountAll(t);
      });
    }

    testWidgets('signed out: A is gone, and nothing is claimed to be empty',
        (t) async {
      await open(t);
      await signOutNow(t);
      nothingOfAs(t);
      expect(find.text('No availability published'), findsNothing);
      expect(
          find.text("You're signed out — sign in again to see your availability."),
          findsOneWidget);
      expect(reported, isEmpty);
      // Sign-out → sign-in, and the same coach back again: their own page.
      await switchTo(t, memberB);
      nothingOfAs(t);
      expect(bobs, findsOneWidget);
      await signOutNow(t);
      await switchTo(t, memberA);
      expect(anas, findsOneWidget);
      expect(bobs, findsNothing);
      await unmountAll(t);
    });

    testWidgets('negative control: B with nothing is empty, not an error',
        (t) async {
      server.tables['coaching_calls'] = [session(memberA, 'Ana')];
      server.tables['coach_availability'] = [slot(memberA, 'consultation')];
      await open(t);
      await switchTo(t, memberB);
      expect(find.text('No availability published'), findsOneWidget);
      expect(find.textContaining("Couldn't"), findsNothing);
      await unmountAll(t);
    });

    testWidgets('positive control: a token refresh keeps the page and an open sheet',
        (t) async {
      await open(t);
      await t.tap(find.text('Add Slot'));
      await settleReal(t);
      await t.tap(find.text('60 min'));
      await settleReal(t);
      final reads = server.log.length;
      await refreshToken(t);
      expect(server.log.length, reads, reason: 'nothing is read again');
      expect(find.text('Add Availability Slot'), findsOneWidget);
      expect(anas, findsOneWidget);
      await t.tap(find.text('Publish Slot'));
      await settleReal(t);
      final post = server.writes.single;
      expect(post.who, memberA);
      expect(post.json, containsPair('coach_id', memberA));
      expect(post.json, containsPair('duration_minutes', 60),
          reason: 'what was chosen before the refresh');
      expect(find.text('Add Availability Slot'), findsNothing);
      await unmountAll(t);
    });
  });

  group('Add slot', () {
    testWidgets("A→B: A's sheet closes with its date picker; nothing is published",
        (t) async {
      await open(t);
      await t.tap(find.text('Add Slot'));
      await settleReal(t);
      final publish = tapOf(t, 'Publish Slot');
      await t.tap(find.byIcon(Icons.calendar_today_rounded));
      await settleReal(t);
      expect(find.byType(DatePickerDialog), findsOneWidget, reason: 'premise');
      await switchTo(t, memberB);
      expect(find.text('Add Availability Slot'), findsNothing);
      expect(find.byType(DatePickerDialog), findsNothing);
      // The tap that was already on its way.
      publish();
      await settleReal(t);
      expect(server.writes, isEmpty, reason: "A's slot was created for B");
      expect(changed(), ['CoachAvailabilityScreen._AddSlotSheet._save']);
      expect(find.textContaining("Couldn't"), findsNothing,
          reason: "nothing about A's action is said to B");
      await unmountAll(t);
    });

    testWidgets('signed out: the sheet closes too', (t) async {
      await open(t);
      await t.tap(find.text('Add Slot'));
      await settleReal(t);
      await signOutNow(t);
      expect(find.text('Add Availability Slot'), findsNothing);
      await unmountAll(t);
    });

    testWidgets('switch during the save: stamped A; B is told nothing',
        (t) async {
      await open(t);
      await t.tap(find.text('Add Slot'));
      await settleReal(t);
      final hold = server.hold((s) => s.isWrite);
      server.failing = (s) => s.isWrite;
      await t.tap(find.text('Publish Slot'));
      await settleReal(t);
      await switchTo(t, memberB);
      hold.complete();
      await settleReal(t);
      expect(server.writes.single.json, containsPair('coach_id', memberA));
      expect(server.writesBy(memberB), isEmpty);
      expect(find.textContaining("Couldn't"), findsNothing);
      await unmountAll(t);
    });
  });

  group('cancel a session', () {
    Future<void> askCancel(WidgetTester t) async {
      await t.tap(find.widgetWithText(TextButton, 'Cancel'));
      await settleReal(t);
      expect(find.text('Cancel session?'), findsOneWidget, reason: 'premise');
    }

    testWidgets("A→B over A's question: it closes, nothing is sent",
        (t) async {
      await open(t);
      await askCancel(t);
      await switchTo(t, memberB);
      expect(find.text('Cancel session?'), findsNothing,
          reason: "B could answer it, about A's client");
      expect(server.writes, isEmpty);
      await unmountAll(t);
    });

    testWidgets("a Cancel tapped on A's list as B signed in asks B nothing",
        (t) async {
      await open(t);
      final cancel = tapOf(t, 'Cancel');
      await t.runAsync(() => signInAs(memberB));
      cancel(); // nothing has been drawn since (a hidden tab draws nothing)
      await settleReal(t);
      expect(find.text('Cancel session?'), findsNothing,
          reason: "B is asked about A's session");
      expect(server.writes, isEmpty);
      expect(changed(), ['CoachAvailabilityScreen._cancelSession']);
      await unmountAll(t);
    });

    testWidgets('switch after step 1: no slot is reopened, no client notified',
        (t) async {
      await open(t);
      await askCancel(t);
      final hold = server.hold((s) => s.table == 'coaching_calls' && s.isWrite);
      await t.tap(find.text('Cancel session'));
      await settleReal(t);
      expect(server.writes.single.who, memberA, reason: 'premise: step 1 is sent');
      await switchTo(t, memberB);
      hold.complete();
      await settleReal(t);
      expect(server.writesBy(memberB), isEmpty,
          reason: "A's client was notified, and A's slot reopened, as B");
      expect(changed(), ['CoachAvailabilityScreen._cancelSession']);
      expect(find.byType(SnackBar), findsNothing);
      expect(bobs, findsOneWidget, reason: "B's own page is there");
      await unmountAll(t);
    });

    testWidgets('switch after the slot: the client is not notified as B',
        (t) async {
      await open(t);
      await askCancel(t);
      final hold = server.hold((s) => s.table == 'coach_availability' && s.isWrite);
      await t.tap(find.text('Cancel session'));
      await settleReal(t);
      await switchTo(t, memberB);
      hold.complete();
      await settleReal(t);
      expect(server.to('notifications'), isEmpty);
      expect(changed(), ['CoachAvailabilityScreen._cancelSession']);
      await unmountAll(t);
    });

    testWidgets('switch during the notification: B is told nothing of it', (t) async {
      await open(t);
      await askCancel(t);
      final hold = server.hold((s) => s.table == 'notifications');
      await t.tap(find.text('Cancel session'));
      await settleReal(t);
      expect(server.to('notifications').single.who, memberA, reason: 'premise');
      await switchNoFrame(t, memberB);
      hold.complete();
      await settleNoFrame(t);
      await settleReal(t);
      expect(find.byType(SnackBar), findsNothing,
          reason: "A's cancelled session is told to B");
      expect(server.writesBy(memberB), isEmpty);
      expect(bobs, findsOneWidget);
      await unmountAll(t);
    });

    testWidgets('"Reopen slot" does not wait for B, and sends nothing as B',
        (t) async {
      await open(t);
      await askCancel(t);
      server.failing = (s) => s.table == 'coach_availability' && s.isWrite;
      await t.tap(find.text('Cancel session'));
      await settleReal(t);
      expect(find.text('Reopen slot'), findsOneWidget, reason: 'premise');
      final reopen = t.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed;
      final before = server.writes.length;
      await switchTo(t, memberB);
      expect(find.text('Reopen slot'), findsNothing);
      reopen();
      await settleReal(t);
      expect(server.writes.length, before);
      expect(changed(), ['CoachAvailabilityScreen._cancelSession.reopenSlot']);
      expect(find.byType(SnackBar), findsNothing);
      await unmountAll(t);
    });

    testWidgets('positive control: A cancels — call, slot, notification, all as A',
        (t) async {
      await open(t);
      await askCancel(t);
      await t.tap(find.text('Cancel session'));
      await settleReal(t);
      expect(server.writes.map((s) => '${s.method} ${s.table} ${s.who == memberA}'), [
        'PATCH coaching_calls true',
        'PATCH coach_availability true',
        'POST notifications true',
      ]);
      expect(find.text('Session cancelled — client notified.'), findsOneWidget);
      expect(reported, isEmpty);
      await unmountAll(t);
    });
  });

  group('remove a slot', () {
    testWidgets('a tap as B signed in sends nothing', (t) async {
      await open(t);
      final remove = t
          .widget<IconButton>(find.ancestor(
              of: find.byIcon(Icons.delete_outline_rounded),
              matching: find.byType(IconButton)))
          .onPressed!;
      await t.runAsync(() async {
        await signInAs(memberB);
      });
      // The screen has not drawn anything since (a hidden tab draws nothing).
      remove();
      await settleReal(t);
      expect(server.writes, isEmpty, reason: "A's slot removed by B's session");
      expect(changed(), ['CoachAvailabilityScreen._delete']);
      await unmountAll(t);
    });

    testWidgets("A's late failure is not said to B", (t) async {
      await open(t);
      final hold = server.hold((s) => s.method == 'DELETE');
      server.failing = (s) => s.method == 'DELETE';
      await t.tap(find.byIcon(Icons.delete_outline_rounded));
      await settleReal(t);
      await switchTo(t, memberB);
      hold.complete();
      await settleReal(t);
      expect(find.textContaining("Couldn't remove"), findsNothing);
      expect(reported.map((f) => f.origin), ['CoachAvailabilityScreen._delete'],
          reason: 'recorded all the same');
      await unmountAll(t);
    });

    testWidgets('positive control: A removes their slot', (t) async {
      await open(t);
      await t.tap(find.byIcon(Icons.delete_outline_rounded));
      await settleReal(t);
      expect(server.writes.single.toString(), contains('id=eq.open-consultation'));
      expect(server.writes.single.who, memberA);
      expect(reported, isEmpty);
      await unmountAll(t);
    });
  });

  group('the same coach: a refresh keeps what is shown (UX-5)', () {
    Future<void> remove(WidgetTester t) async {
      await t.tap(find.byIcon(Icons.delete_outline_rounded).first);
      await settleReal(t);
    }

    setUp(() => server.tables['coach_availability']!.add(slot(memberA, 'check_in')));
    final anasSecond = find.text('Weekly Check-In');
    const held = 'Try again in a moment. If it keeps happening, contact support. '
        'Changes are paused until it loads.';

    testWidgets('while it is read: the list, not a spinner; the removed slot is gone',
        (t) async {
      await open(t);
      final again = server.hold((s) => !s.isWrite);
      // (What the re-read will answer.)
      server.tables['coach_availability']!.removeWhere((s) => s['id'] == 'open-consultation');
      await remove(t);
      expect(server.writes.single.query, contains('id=eq.open-consultation'));
      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: 'THE defect: the list became a spinner, and its place was lost');
      expect(anas, findsOneWidget);
      expect(anasSecond, findsOneWidget);
      expect(anasSlot, findsNothing, reason: 'the server said it went');
      again.complete();
      await settleReal(t);
      expect(anasSecond, findsOneWidget);
      expect(anasSlot, findsNothing);
      await unmountAll(t);
    });

    testWidgets('a failed one: the list stays, said above it, changes held; Try again '
        'is busy-aware and loads', (t) async {
      final h = t.ensureSemantics();
      await open(t);
      server.failing = (s) => !s.isWrite;
      await remove(t);
      expect(find.text("Couldn't load your availability"), findsOneWidget);
      expect(find.text(held), findsOneWidget);
      expect(anas, findsOneWidget, reason: 'THE defect: the failure replaced the list');
      expect(anasSecond, findsOneWidget);
      expect(reported.map((f) => f.origin), ['CoachAvailabilityScreen._load']);
      // Nothing is changed on a schedule that could not be read again.
      final writes = server.writes.length;
      await t.tap(find.byIcon(Icons.delete_outline_rounded));
      await t.tap(find.widgetWithText(TextButton, 'Cancel'));
      await t.tap(find.text('Add Slot'));
      await settleReal(t);
      expect(server.writes.length, writes);
      expect(find.text('Cancel session?'), findsNothing);
      expect(find.text('Publish Slot'), findsNothing);
      final cancel = t.getSemantics(
          find.bySemanticsLabel(RegExp('^Cancel session with Ana Client'))).getSemanticsData();
      expect(cancel.hasAction(SemanticsAction.tap), isFalse);

      server.failing = (_) => false;
      final hold = server.hold((s) => !s.isWrite);
      final reads = server.log.length;
      await t.tap(find.text('Try again'));
      await t.pump();
      await t.tap(find.bySemanticsLabel('Retrying'), warnIfMissed: false);
      await settleReal(t);
      expect(server.log.length, reads + 1);
      expect(anas, findsOneWidget);
      hold.complete();
      await settleReal(t);
      expect(find.textContaining("Couldn't"), findsNothing);
      await t.tap(find.byIcon(Icons.delete_outline_rounded).first);
      await settleReal(t);
      expect(server.writes.length, writes + 1, reason: 'live again');
      h.dispose();
      await unmountAll(t);
    });

    testWidgets("kept over A's failed refresh, it is still never B's", (t) async {
      await open(t);
      server.failing = (s) => !s.isWrite;
      await remove(t);
      expect(anas, findsOneWidget, reason: 'premise');
      await switchTo(t, memberB);
      nothingOfAs(t);
      expect(anasSecond, findsNothing);
      expect(find.textContaining("Couldn't load your availability — "), findsOneWidget,
          reason: "B's first read failed: B's own failure, in place of a list");
      server.failing = (_) => false;
      await t.tap(find.text('Try again'));
      await settleReal(t);
      expect(bobs, findsOneWidget);
      expect(find.textContaining("Couldn't"), findsNothing);
      await unmountAll(t);
    });

    testWidgets('a cancelled session leaves the list at once, also when the '
        'refresh fails', (t) async {
      await open(t);
      server.failing = (s) => !s.isWrite;
      await t.tap(find.widgetWithText(TextButton, 'Cancel'));
      await settleReal(t);
      await t.tap(find.text('Cancel session'));
      await settleReal(t);
      expect(find.text('Session cancelled — client notified.'), findsOneWidget);
      expect(anas, findsNothing, reason: 'it was cancelled');
      expect(anasSecond, findsOneWidget);
      await unmountAll(t);
    });

    testWidgets('negative control: the last one removed is an empty calendar', (t) async {
      server.tables['coaching_calls'] = [];
      server.tables['coach_availability'] = [slot(memberA, 'consultation')];
      await open(t);
      server.tables['coach_availability'] = [];
      await remove(t);
      expect(find.text('No availability published'), findsOneWidget);
      expect(find.textContaining("Couldn't"), findsNothing);
      await unmountAll(t);
    });
  });
}
