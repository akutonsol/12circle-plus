import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/checkins/domain/checkin_hub.dart';
import 'package:circle_fitness/features/checkins/domain/checkin_provider.dart';
import 'package:circle_fitness/features/checkins/presentation/checkin_hub_sections.dart';
import 'package:circle_fitness/features/checkins/presentation/coach_checkin_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/owned_writes_postgrest.dart';
import '../support/owner_harness.dart';
import '../support/pump_until.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-59c round 3 · the coach's reply stays with the client it was written to.
//
// With nothing selected the form shows the front of the queue, and a re-read
// (a client's new check-in, a send in another tab) that moved X off the front
// put Y's check-in under X's reply: Send then PATCHed X's private feedback onto
// Y's week, which Y can read. Now a check-in with a reply on it is PINNED, and
// Send refuses a check-in that is not the one on the form or that has left the
// queue. Which answer a check-in reviewed elsewhere gets is the server's (PD8);
// no rule about it is made here.
//
// Also: the hub and the queue with a read IN FLIGHT at the account switch.
//
// HOW TO SEE IT FAIL: run against ddce829's coach_checkin_review_screen.dart
// and checkin_hub_sections.dart.

const _refused = "Couldn't send your reply — this check-in is no longer in your "
    'review queue. Go back to open the next one.';

void main() {
  late OwnedWritesPostgrest server;
  late ProviderContainer container;
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = OwnedWritesPostgrest();
    await initTwoMemberSupabase(server);
  });

  Map<String, Object?> row(String id, String first) => {
        'id': id,
        'user_id': 'client-$id',
        'week_number': 47,
        'status': 'submitted',
        'notes': 'note of $first',
        'user_profiles': {'first_name': first, 'last_name': 'Osei'},
      };
  final amara = row('a1', 'Amara');
  final anton = row('a2', 'Anton');
  final yara = row('y0', 'Yara');

  setUp(() async {
    await signInAs(memberA);
    server.reset();
    server.rows['weekly_checkins:$memberA'] = [amara, anton];
    server.rows['weekly_checkins:$memberB'] = [row('b1', 'Bea')];
    reported.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  Future<void> open(WidgetTester t, {String first = 'Amara Osei'}) async {
    tallView(t);
    container = ProviderContainer();
    addTearDown(container.dispose);
    final router = GoRouter(initialLocation: '/review', routes: [
      GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('BEHIND')),
          routes: [
            GoRoute(
                path: 'review',
                builder: (_, __) => const CoachCheckinReviewScreen()),
          ]),
    ]);
    addTearDown(router.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await settleReal(t);
    expect(find.text(first), findsOneWidget, reason: 'premise');
  }

  Finder reply() => find.byType(TextField).at(0);
  Finder recommendation() => find.byType(TextField).at(1);
  String text(WidgetTester t, Finder f) =>
      t.widget<TextField>(f).controller!.text;
  VoidCallback sendTap(WidgetTester t) =>
      t.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed!;
  Iterable<Asked> patches() => server.sent('PATCH', 'weekly_checkins');

  Future<void> draft(WidgetTester t, [String words = 'for Amara only']) async {
    await t.enterText(reply(), words);
    await t.pump();
  }

  /// The queue read again, now as [rows].
  Future<void> reread(WidgetTester t, List<Map<String, Object?>> rows,
      {bool frame = true}) async {
    server.rows['weekly_checkins:$memberA'] = rows;
    container.invalidate(coachSubmittedCheckinsProvider);
    if (frame) {
      await settleReal(t);
    } else {
      for (var i = 0; i < 5; i++) {
        container.read(coachSubmittedCheckinsProvider);
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)));
        await t.idle();
      }
    }
  }

  void stillAmara(WidgetTester t, [String words = 'for Amara only']) {
    expect(find.text('Amara Osei'), findsOneWidget,
        reason: "THE defect: another client's check-in under Amara's reply");
    expect(find.text('Anton Osei'), findsNothing);
    expect(find.text('Yara Osei'), findsNothing);
    expect(text(t, reply()), words);
  }

  Future<void> sendIt(WidgetTester t) async {
    await t.ensureVisible(find.byType(ElevatedButton));
    await t.tap(find.byType(ElevatedButton));
    await settleReal(t);
  }

  void refused(WidgetTester t) {
    expect(patches(), isEmpty, reason: "THE defect: the reply sent");
    expect(find.text(_refused), findsOneWidget);
    expect(reported.map((f) => f.origin), ['CoachCheckinReviewScreen._submit']);
  }

  group('a reply on the form pins its check-in', () {
    testWidgets('X reviewed elsewhere (it left the queue): the form stays X, '
        'and Send is refused, said, recorded, the reply kept', (t) async {
      await open(t);
      await draft(t);
      await reread(t, [anton]);
      stillAmara(t);
      await sendIt(t);
      refused(t);
      stillAmara(t);
      await closeApp(t);
    });

    testWidgets('X resubmitted later (now behind Y): the form stays X, at its '
        'new place, and Send replies to X', (t) async {
      await open(t);
      await draft(t);
      await reread(t, [anton, amara]);
      stillAmara(t);
      expect(find.text('Week 47 · 2 of 2'), findsOneWidget);
      await sendIt(t);
      expect(patches().single.query['id'], 'eq.a1');
      expect(patches().single.json['feedback_message'], 'for Amara only');
      expect(reported, isEmpty);
      await closeApp(t);
    });

    testWidgets('a new Y in front: the form stays X; Send replies to X and '
        'opens the one after X, empty', (t) async {
      await open(t);
      await draft(t);
      await reread(t, [yara, amara, anton]);
      stillAmara(t);
      expect(find.text('Week 47 · 2 of 3'), findsOneWidget);
      await sendIt(t);
      expect(patches().single.query['id'], 'eq.a1');
      expect(find.text('Anton Osei'), findsOneWidget);
      expect(text(t, reply()), isEmpty);
      await closeApp(t);
    });

    testWidgets('the re-read lands with no frame, then Send: nothing is sent '
        'for a check-in no longer in the queue', (t) async {
      await open(t);
      await draft(t);
      final send = sendTap(t);
      await reread(t, [anton], frame: false);
      send();
      await settleReal(t);
      refused(t);
      stillAmara(t);
      await closeApp(t);
    });

    testWidgets("Send drawn for X with no reply, tapped after the form moved to "
        "Y and a reply for Y was typed: refused, nothing sent", (t) async {
      await open(t);
      final sendForX = sendTap(t);
      await reread(t, [anton]);
      expect(find.text('Anton Osei'), findsOneWidget, reason: 'premise');
      await draft(t, 'for Anton only');
      sendForX();
      await settleReal(t);
      refused(t);
      expect(text(t, reply()), 'for Anton only');
      await closeApp(t);
    });

    testWidgets('a recommendation alone pins it too', (t) async {
      await open(t);
      await t.enterText(recommendation(), 'rest day for Amara');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      expect(find.text('rest day for Amara'), findsOneWidget, reason: 'premise');
      await reread(t, [anton]);
      expect(find.text('Amara Osei'), findsOneWidget);
      expect(find.text('Anton Osei'), findsNothing);
      expect(find.text('rest day for Amara'), findsOneWidget);
      await closeApp(t);
    });

    testWidgets("a check-in opened with Next, replied to, then reviewed "
        'elsewhere: kept on the form, Send refused', (t) async {
      server.rows['weekly_checkins:$memberA'] = [yara, amara];
      await open(t, first: 'Yara Osei');
      await t.tap(find.bySemanticsLabel('Next'));
      await settleReal(t);
      expect(find.text('Amara Osei'), findsOneWidget, reason: 'premise');
      await draft(t);
      await reread(t, [yara]);
      stillAmara(t);
      await sendIt(t);
      refused(t);
      await closeApp(t);
    });

    testWidgets("undo in the next client's field does not bring X's reply back",
        (t) async {
      await open(t);
      await t.tap(reply());
      await t.enterText(reply(), 'for Amara only');
      await t.pump(const Duration(seconds: 1));
      await t.enterText(reply(), '');
      await t.pump(const Duration(seconds: 1));
      // Nothing typed now: the queue may move on.
      await reread(t, [anton]);
      expect(find.text('Anton Osei'), findsOneWidget, reason: 'premise');
      await t.tap(reply());
      await t.pump();
      await undo(t);
      await undo(t);
      expect(text(t, reply()), isEmpty,
          reason: "THE defect: Amara's words on Anton's form");
      await closeApp(t);
    }, variant: const TargetPlatformVariant({TargetPlatform.linux}));
  });

  group('controls', () {
    testWidgets('CONTROL: with nothing typed and nothing selected, the queue '
        'moves on as before', (t) async {
      await open(t);
      await reread(t, [anton]);
      expect(find.text('Anton Osei'), findsOneWidget);
      expect(find.text('Amara Osei'), findsNothing);
      await closeApp(t);
    });

    testWidgets('CONTROL: the only client: sent once, notified once, the reply '
        'gone, back where the coach came from', (t) async {
      server.rows['weekly_checkins:$memberA'] = [amara];
      await open(t);
      await draft(t);
      server.rows['weekly_checkins:$memberA'] = const [];
      await sendIt(t);
      expect(patches().single.query['id'], 'eq.a1');
      expect(server.sent('POST', 'notifications'), hasLength(1));
      expect(find.text('BEHIND'), findsOneWidget);
      expect(reported, isEmpty);
      await closeApp(t);
    });

    testWidgets('CONTROL: Send and open next, then Next, as before', (t) async {
      server.rows['weekly_checkins:$memberA'] = [amara, anton, yara];
      await open(t);
      await draft(t);
      server.rows['weekly_checkins:$memberA'] = [anton, yara];
      await sendIt(t);
      expect(patches().single.query['id'], 'eq.a1');
      expect(find.text('Anton Osei'), findsOneWidget);
      expect(find.text('Week 47 · 1 of 2'), findsOneWidget);
      expect(text(t, reply()), isEmpty);
      await t.tap(find.bySemanticsLabel('Next'));
      await settleReal(t);
      expect(find.text('Yara Osei'), findsOneWidget);
      expect(patches(), hasLength(1));
      await closeApp(t);
    });

    testWidgets("CONTROL: a refused send by the server keeps the reply and says "
        'so, as before', (t) async {
      await open(t);
      await draft(t);
      server.fails.add('PATCH weekly_checkins:$memberA');
      await sendIt(t);
      expect(find.text('Failed to submit feedback. Try again.'), findsOneWidget);
      stillAmara(t);
      await closeApp(t);
    });

    testWidgets('header: a failed re-read is said once, by the card (UX LOW 1)',
        (t) async {
      await open(t);
      await draft(t);
      server.fails.add('GET weekly_checkins:$memberA');
      container.invalidate(coachSubmittedCheckinsProvider);
      await settleReal(t);
      expect(find.textContaining("ouldn't load your review queue"),
          findsOneWidget);
      expect(find.text('Week 47 · 1 of 2'), findsOneWidget);
      await closeApp(t);
    });
  });

  group('a read in flight at the switch, frames pumped', () {
    testWidgets("the queue: A's refresh held, B's read pending: nothing of A",
        (t) async {
      await open(t);
      await draft(t);
      final holdA =
          server.holds['GET weekly_checkins:$memberA'] = Completer<void>();
      container.invalidate(coachSubmittedCheckinsProvider);
      await settleReal(t);
      expect(container.read(coachSubmittedCheckinsProvider).isLoading, isTrue,
          reason: 'premise');
      stillAmara(t);
      final holdB =
          server.holds['GET weekly_checkins:$memberB'] = Completer<void>();
      await switchNoFrame(t, memberB);
      await settleReal(t);
      expect(find.textContaining('Amara'), findsNothing);
      expect(find.textContaining('Anton'), findsNothing);
      expect(find.text('for Amara only'), findsNothing);
      holdA.complete();
      await settleReal(t);
      expect(find.textContaining('Amara'), findsNothing);
      holdB.complete();
      await settleReal(t);
      expect(find.text('Bea Osei'), findsOneWidget);
      expect(patches(), isEmpty);
      await closeApp(t);
    });

    Map<String, Object?> week(String member, int n) => {
          'id': 'w$n',
          'user_id': member,
          'week_number': n,
          'week_start_date': '2026-11-16',
          'status': 'submitted',
          'energy_level': 4,
          'submitted_at': '2026-11-20T10:00:00Z',
        };

    Future<void> openHub(WidgetTester t) async {
      tallView(t);
      container = ProviderContainer();
      addTearDown(container.dispose);
      await t.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
            home: Scaffold(body: SingleChildScrollView(child: CheckinHubSections()))),
      ));
      await settleReal(t);
    }

    testWidgets("the hub: A's read failed, A's retry in flight, B's read "
        "pending: neither A's failure nor its Retrying is B's", (t) async {
      final handle = t.ensureSemantics();
      server.rows['weekly_checkins:$memberB'] = [week(memberB, 7)];
      server.fails.add('GET weekly_checkins:$memberA');
      await openHub(t);
      expect(find.text(checkinHistoryFailure), findsOneWidget, reason: 'premise');
      server.fails.clear();
      final holdA =
          server.holds['GET weekly_checkins:$memberA'] = Completer<void>();
      await t.tap(find.text('Try again'));
      await settleReal(t);
      expect(find.bySemanticsLabel(RegExp('Retrying')), findsOneWidget,
          reason: 'premise: in flight');
      final holdB =
          server.holds['GET weekly_checkins:$memberB'] = Completer<void>();
      await switchNoFrame(t, memberB);
      await settleReal(t);
      expect(find.text(checkinHistoryFailure), findsNothing,
          reason: "THE defect (P3): A's failure and Retrying left for B");
      expect(find.bySemanticsLabel(RegExp('Retrying')), findsNothing);
      expect(find.bySemanticsLabel('Loading check-in history'), findsOneWidget);
      holdA.complete();
      holdB.complete();
      await settleReal(t);
      expect(find.textContaining('Week 7'), findsOneWidget);
      handle.dispose();
      await closeApp(t);
    });

    testWidgets("the hub: A's refresh held with weeks on screen, B's read "
        "pending: none of A's weeks", (t) async {
      server.rows['weekly_checkins:$memberA'] = [week(memberA, 41)];
      server.rows['weekly_checkins:$memberB'] = [week(memberB, 7)];
      await openHub(t);
      expect(find.textContaining('Week 41'), findsOneWidget, reason: 'premise');
      final holdA =
          server.holds['GET weekly_checkins:$memberA'] = Completer<void>();
      container.invalidate(checkinHistoryProvider);
      await settleReal(t);
      final holdB =
          server.holds['GET weekly_checkins:$memberB'] = Completer<void>();
      await switchNoFrame(t, memberB);
      await settleReal(t);
      expect(find.textContaining('Week 41'), findsNothing);
      holdA.complete();
      await settleReal(t);
      expect(find.textContaining('Week 41'), findsNothing);
      holdB.complete();
      await pumpUntil(t, () => find.textContaining('Week 7').evaluate().isNotEmpty,
          what: "B's week");
      await closeApp(t);
    });
  });
}
