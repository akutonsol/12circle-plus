import 'dart:convert';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/coach/domain/coach_provider.dart';
import 'package:circle_fitness/features/home/presentation/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/member_owner_server.dart';

// P0-FL-62a1 · Home › "Rate your coach" (A-15, W13).
//
// The dialog read the signed-in id at SUBMIT, not when it opened. A's open
// dialog — A's coach, A's stars, A's words — was upserted as B's review once B
// signed in on the same device (client_id = B, coach_id = A's coach): A's
// rating became B's public review. And the coach card read
// `assignedCoachProvider` straight, so when B's read failed Riverpod's held
// value drew A's coach, with a Rate button bound to A's coach, for B.
//
// The dialog and the card are mounted alone (their test hooks), WITHOUT
// AccountScope, and stay mounted across a real A -> B switch on the real
// auth client. The fake server answers by the bearer token, so the log says
// whom each request went out as.

const _thanks = 'Review submitted! Thank you.';
const _coachOfA = 'coach-of-a';
const _coachOfB = 'coach-of-b';

late MemberOwnerServer _server;
final _reported = <AppFailure>[];

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _as(WidgetTester t, String uid) async {
  await t.runAsync(() => signInAs(uid));
  expect(Supabase.instance.client.auth.currentUser?.id, uid, reason: 'premise');
}

Future<void> _close(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 6));
}

List<String> _reviewWrites({String? by}) =>
    _server.of('POST', 'coach_reviews', by: by);

Map<String, Object?> _bodyOf(String line) =>
    jsonDecode(line.substring(line.indexOf('{'))) as Map<String, Object?>;

/// The dialog, opened by whoever is signed in, for A's coach.
Future<void> _openDialog(WidgetTester t) async {
  t.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(1000, 2000);
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
            onPressed: () => showRateCoachDialogForTest(context, _coachOfA),
            child: const Text('open')),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await _settle(t);
  expect(find.text('Rate Your Coach'), findsOneWidget, reason: 'premise');
}

Future<void> _typeAndStar(WidgetTester t) async {
  await t.enterText(find.byType(TextField), 'typed by A');
  await t.tap(find.byIcon(Icons.star_rounded).at(3)); // 4 stars
  await t.pump();
}

/// Presses Submit from the last frame drawn, without drawing another: what a
/// tap queued in a hidden tab does.
void _pressSubmitNoFrame(WidgetTester t) {
  final submit = t.widget<TextButton>(find.widgetWithText(TextButton, 'Submit'));
  submit.onPressed!();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    _server = MemberOwnerServer();
    await initTwoMemberSupabase(_server);
  });

  setUp(() {
    _server.reset();
    _reported.clear();
    setFailureSink(_reported.add);
  });
  tearDown(resetFailureSink);

  group('Rate your coach — the dialog', () {
    testWidgets(
        "A -> B with A's dialog open: it closes, A's words are gone, nothing "
        'is written as B', (t) async {
      await _as(t, memberA);
      await _openDialog(t);
      await _typeAndStar(t);

      await _as(t, memberB);
      await _settle(t);

      expect(find.text('typed by A'), findsNothing,
          reason: "A's words must not survive into a dialog B sees");
      expect(find.text('Rate Your Coach'), findsNothing,
          reason: "A's dialog must close when A leaves");
      // Whatever is still there, B presses it.
      final submit = find.text('Submit');
      if (submit.evaluate().isNotEmpty) {
        await t.tap(submit);
        await _settle(t);
      }
      expect(_reviewWrites(), isEmpty,
          reason: "A's rating was upserted as B's review of A's coach");
      expect(find.text(_thanks), findsNothing);
      await _close(t);
    });

    testWidgets(
        'A -> B with no frame drawn, Submit pressed: nothing is sent, the '
        'stop is recorded', (t) async {
      await _as(t, memberA);
      await _openDialog(t);
      await _typeAndStar(t);

      await _as(t, memberB);
      _pressSubmitNoFrame(t);
      await _settle(t);

      expect(_reviewWrites(), isEmpty,
          reason: 'the upsert went out as B (client_id = B) with A\'s stars, '
              "words and coach");
      expect(_reported.map((f) => f.error.toString()),
          contains(endsWith('Rating your coach: the signed-in account changed')));
      expect(find.text('typed by A'), findsNothing);
      expect(find.text(_thanks), findsNothing);
      await _close(t);
    });

    testWidgets(
        "switch during submit: A's write stays A's, and B is not told "
        '"Review submitted!"', (t) async {
      await _as(t, memberA);
      await _openDialog(t);
      await _typeAndStar(t);
      final gate = holdOn(_server, 'POST coach_reviews:$memberA');

      await t.tap(find.text('Submit'));
      await t.pump();
      expect(_reviewWrites(by: memberA), hasLength(1), reason: 'premise');
      await _as(t, memberB);
      await _settle(t);
      gate.complete();
      await _settle(t);

      final write = _bodyOf(_reviewWrites().single);
      expect(write['client_id'], memberA,
          reason: 'stamped with the member who opened the dialog');
      expect(write['coach_id'], _coachOfA);
      expect(_reviewWrites(by: memberB), isEmpty);
      expect(find.text(_thanks), findsNothing,
          reason: "B was thanked for A's review");
      expect(find.text('typed by A'), findsNothing);
      expect(_reported.map((f) => f.error.toString()),
          contains(endsWith('Rating your coach: the signed-in account changed')));
      await _close(t);
    });

    testWidgets(
        "A's failed submit landing after B signed in says nothing to B",
        (t) async {
      await _as(t, memberA);
      await _openDialog(t);
      await _typeAndStar(t);
      final gate = holdOn(_server, 'POST coach_reviews:$memberA');
      _server.fails.add('POST coach_reviews:$memberA');

      await t.tap(find.text('Submit'));
      await t.pump();
      await _as(t, memberB);
      _server.holds.remove('POST coach_reviews:$memberA');
      gate.complete();
      await _settle(t);

      expect(find.text(kReviewFailedMessage), findsNothing,
          reason: "A's failure was drawn in a dialog B sees");
      expect(find.text('typed by A'), findsNothing);
      expect(find.text('Rate Your Coach'), findsNothing);
      expect(_reviewWrites(by: memberB), isEmpty);
      await _close(t);
    });

    testWidgets(
        "A's failed submit landing after B signed in AND after A's dialog "
        'closed: nothing is drawn into the closed dialog', (t) async {
      // Round 2 (mutant rate-failure-after-switch-drawn). Here the dialog has
      // already gone (frames ran after B signed in) when A's failure answers,
      // so drawing the failure means a setState on a disposed dialog — an
      // uncaught error after the member left.
      await _as(t, memberA);
      await _openDialog(t);
      await _typeAndStar(t);
      const key = 'POST coach_reviews:$memberA';
      final gate = holdOn(_server, key);
      _server.fails.add(key);

      await t.tap(find.text('Submit'));
      await t.pump();
      await _as(t, memberB);
      await _settle(t);
      expect(find.text('Rate Your Coach'), findsNothing,
          reason: "premise: A's dialog closed before A's answer");

      _server.holds.remove(key);
      gate.complete();
      await _settle(t);

      expect(t.takeException(), isNull);
      expect(find.text(kReviewFailedMessage), findsNothing);
      expect(find.text(kReviewOfflineMessage), findsNothing);
      expect(find.text(_thanks), findsNothing);
      expect(_reviewWrites(), hasLength(1));
      expect(_reviewWrites(by: memberB), isEmpty);
      expect(_reported.where((f) => f.origin == 'home.rateCoach'),
          hasLength(1), reason: "A's failure is recorded, once");
      await _close(t);
    });

    testWidgets(
        'sign-out closes it; the same member back in gets an empty dialog '
        'and submits once, as themselves', (t) async {
      await _as(t, memberA);
      await _openDialog(t);
      await _typeAndStar(t);

      await t.runAsync(signOut);
      await _settle(t);
      expect(find.text('typed by A'), findsNothing,
          reason: 'signed out is a change of account');
      expect(find.text('Rate Your Coach'), findsNothing);

      await _as(t, memberA);
      await _settle(t);
      await t.tap(find.text('open'));
      await _settle(t);
      expect(find.text('typed by A'), findsNothing, reason: 'a fresh dialog');
      await t.enterText(find.byType(TextField), 'again');
      await t.tap(find.text('Submit'));
      await _settle(t);

      expect(_reviewWrites(), hasLength(1));
      final write = _bodyOf(_reviewWrites(by: memberA).single);
      expect(write['client_id'], memberA);
      expect(write['review_text'], 'again');
      expect(find.text(_thanks), findsOneWidget);
      await _close(t);
    });

    testWidgets('control: the same member submits once, as themselves',
        (t) async {
      await _as(t, memberA);
      await _openDialog(t);
      await _typeAndStar(t);
      await t.tap(find.text('Submit'));
      await _settle(t);

      expect(_reviewWrites(), hasLength(1));
      final line = _reviewWrites(by: memberA).single;
      expect(line, contains('select=id'));
      expect(_bodyOf(line), allOf(
          containsPair('client_id', memberA),
          containsPair('coach_id', _coachOfA),
          containsPair('rating', 4),
          containsPair('review_text', 'typed by A')));
      expect(find.text(_thanks), findsOneWidget);
      expect(find.text('Rate Your Coach'), findsNothing);
      expect(_reported, isEmpty);
      await _close(t);
    });

    testWidgets(
        "control: a token refresh keeps A's words and stars, and A's submit "
        'goes out as A', (t) async {
      await _as(t, memberA);
      await _openDialog(t);
      await _typeAndStar(t);

      await t.runAsync(refreshSession);
      await _settle(t);
      expect(Supabase.instance.client.auth.currentUser?.id, memberA,
          reason: 'premise');
      expect(find.text('typed by A'), findsOneWidget,
          reason: 'the same member refreshing its token wiped the draft');
      await t.tap(find.text('Submit'));
      await _settle(t);

      expect(_bodyOf(_reviewWrites(by: memberA).single),
          allOf(containsPair('rating', 4), containsPair('review_text', 'typed by A')));
      expect(find.text(_thanks), findsOneWidget);
      await _close(t);
    });

    testWidgets('control: a 0-row write says it failed, inside the dialog',
        (t) async {
      await _as(t, memberA);
      await _openDialog(t);
      _server.zeroRows.add('POST coach_reviews:$memberA');
      await t.tap(find.text('Submit'));
      await _settle(t);
      expect(find.text(kReviewFailedMessage), findsOneWidget);
      expect(find.text(_thanks), findsNothing);
      expect(find.text('Rate Your Coach'), findsOneWidget);
      await _close(t);
    });

    testWidgets('control: offline says check your connection', (t) async {
      await _as(t, memberA);
      await _openDialog(t);
      _server.offline.add('POST coach_reviews:$memberA');
      await t.tap(find.text('Submit'));
      await _settle(t);
      expect(find.text(kReviewOfflineMessage), findsOneWidget);
      expect(find.text(_thanks), findsNothing);
      await _close(t);
    });
  });

  group('Rate your coach — the card', () {
    void seedCoaches() {
      _server.answers['coach_client_relationships:$memberA'] = {
        'coach_id': _coachOfA, 'status': 'active'
      };
      _server.answers['public_profiles:$memberA'] = {
        'id': _coachOfA, 'first_name': 'Alpha', 'last_name': 'Trainer'
      };
      _server.answers['coach_client_relationships:$memberB'] = {
        'coach_id': _coachOfB, 'status': 'active'
      };
      _server.answers['public_profiles:$memberB'] = {
        'id': _coachOfB, 'first_name': 'Beta', 'last_name': 'Trainer'
      };
    }

    Future<void> pumpCard(WidgetTester t) async {
      await t.pumpWidget(ProviderScope(
          child: MaterialApp(home: Scaffold(body: coachCardForTest()))));
      await _settle(t);
    }

    testWidgets("B's coach read failed: A's coach is not drawn for B",
        (t) async {
      seedCoaches();
      await _as(t, memberA);
      await pumpCard(t);
      expect(find.text('Coach Alpha Trainer'), findsOneWidget, reason: 'premise');

      _server.fails.add('GET coach_client_relationships:$memberB');
      await _as(t, memberB);
      await _settle(t);

      expect(
          _server.calls, contains('GET coach_client_relationships:$memberB'),
          reason: "premise: B's read went out");
      expect(find.text('Coach Alpha Trainer'), findsNothing,
          reason: "B was shown A's coach, with a Rate button bound to A's "
              'coach');
      expect(find.text('Rate'), findsNothing);
      expect(_reported.map((f) => f.origin), contains('home.coachCard'),
          reason: 'the failed read is recorded');
      await _close(t);
    });

    testWidgets(
        "Rate on A's card tapped after B signed in (no frame) opens nothing",
        (t) async {
      seedCoaches();
      await _as(t, memberA);
      await pumpCard(t);
      expect(find.text('Rate'), findsOneWidget, reason: 'premise');
      final rate = t.getCenter(find.text('Rate'));

      await _as(t, memberB);
      await t.tapAt(rate);
      await t.pump();

      expect(find.text('Rate Your Coach'), findsNothing,
          reason: "B was handed a dialog to review A's coach");
      await _close(t);
    });

    testWidgets("B's coach read pending: nothing of A's is drawn", (t) async {
      seedCoaches();
      await _as(t, memberA);
      await pumpCard(t);
      expect(find.text('Coach Alpha Trainer'), findsOneWidget, reason: 'premise');

      final gate = holdOn(_server, 'GET coach_client_relationships:$memberB');
      await _as(t, memberB);
      await _settle(t);
      expect(find.text('Coach Alpha Trainer'), findsNothing);
      gate.complete();
      await _settle(t);
      expect(find.text('Coach Beta Trainer'), findsOneWidget,
          reason: "B's own coach once B's read answers");
      await _close(t);
    });

    testWidgets(
        "control: the same member's coach read reloads: A's coach again, "
        'read twice as A, Rate still opens for A', (t) async {
      seedCoaches();
      await _as(t, memberA);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await t.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: Scaffold(body: coachCardForTest()))));
      await _settle(t);
      expect(find.text('Coach Alpha Trainer'), findsOneWidget,
          reason: 'premise');

      container.invalidate(assignedCoachProvider);
      await _settle(t);

      expect(find.text('Coach Alpha Trainer'), findsOneWidget,
          reason: "the same member's reload dropped their own coach");
      expect(
          _server.calls
              .where((c) => c == 'GET coach_client_relationships:$memberA'),
          hasLength(2),
          reason: 'read, then read again on the reload');
      expect(_server.of('GET', 'coach_client_relationships', by: memberB),
          isEmpty);
      expect(_reported, isEmpty);

      await t.tap(find.text('Rate'));
      await _settle(t);
      expect(find.text('Rate Your Coach'), findsOneWidget,
          reason: "A's own card still opens A's dialog after the reload");
      await _close(t);
    });

    testWidgets(
        "control: A's coach loads; a token refresh keeps it; A -> B draws "
        "B's", (t) async {
      seedCoaches();
      await _as(t, memberA);
      await pumpCard(t);
      expect(find.text('Coach Alpha Trainer'), findsOneWidget);

      await t.runAsync(refreshSession);
      await _settle(t);
      expect(find.text('Coach Alpha Trainer'), findsOneWidget);

      await _as(t, memberB);
      await _settle(t);
      expect(find.text('Coach Beta Trainer'), findsOneWidget);
      expect(find.text('Coach Alpha Trainer'), findsNothing);
      expect(_reported, isEmpty);
      await _close(t);
    });
  });
}
