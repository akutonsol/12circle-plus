import 'dart:convert';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/ai_coach/presentation/ai_coach_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/member_owner_server.dart';

// P0-FL-62a1 · the member's AI coach screen (E6, W15).
//
// Its conversation, history, the in-flight chat reply, the style and memory
// chips and the brief / weekly review / goal prediction cards all live in
// State, and nothing tied that State to the member who opened it. With the
// screen mounted across A -> B (or a sign-out) B was shown A's conversation,
// injuries, style and brief; A's late chat reply or late read landed on B's
// screen; A's `_load` that found no brief went on to GENERATE one — as B, on
// the server; and a style, memory or delete A had started went out as B.
//
// The screen is mounted alone, WITHOUT AccountScope, and stays mounted across
// a real switch on the real auth client. The fake server answers by the
// bearer token, so its log says whom each read, write and invoke went out as.

late MemberOwnerServer _server;
final _reported = <AppFailure>[];

String _today() => DateTime.now().toIso8601String().substring(0, 10);

/// Everything the screen reads, for both members.
void _seed() {
  for (final (m, tag) in [(memberA, 'A'), (memberB, 'B')]) {
    _server.answers['ai_conversations:$m'] = [
      {
        'user_message': tag == 'A' ? 'my knee hurts' : 'B question',
        'ai_response': 'answer for $tag',
        'created_at': '2026-01-01T00:00:00Z',
      }
    ];
    _server.answers['ai_insights:daily_insight:$m'] = {
      'title': '$tag brief title', 'body': '$tag brief body', 'data': {}
    };
    _server.answers['ai_insights:progress:$m'] = {
      'title': '$tag progress title', 'body': '$tag progress body'
    };
    _server.answers['ai_reviews:$m'] = {
      'summary': '$tag weekly summary', 'period_end': _today(), 'metrics': {}
    };
    _server.answers['ai_goal_predictions:$m'] = {
      'summary': '$tag prediction summary', 'projected_date': '2027-03-01'
    };
    _server.answers['ai_profiles:$m'] = {
      'coach_persona': {'style': tag == 'A' ? 'calm' : 'scientific'}
    };
    _server.answers['ai_memories:$m'] = [
      {'id': 'mem-$tag', 'kind': 'injury', 'content': 'left knee $tag'}
    ];
    _server.functions['ai-coaching-engine:$m'] = {
      'result': {
        'title': 'generated for $tag',
        'body': 'generated for $tag',
        'summary': 'generated for $tag',
      }
    };
  }
}

const _aTexts = [
  'A brief title',
  'A progress title',
  'A weekly summary',
  'A prediction summary',
  'left knee A',
];
const _bTexts = [
  'B brief title',
  'B progress title',
  'B weekly summary',
  'B prediction summary',
  'left knee B',
];

Future<void> _settle(WidgetTester t, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _as(WidgetTester t, String uid) async {
  await t.runAsync(() => signInAs(uid));
  expect(Supabase.instance.client.auth.currentUser?.id, uid, reason: 'premise');
}

Future<void> _pumpScreen(WidgetTester t) async {
  t.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(900, 9000);
  addTearDown(t.view.reset);
  await t.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AICoachScreen())));
  await _settle(t);
}

Future<void> _close(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 6));
}

Future<void> _toConversation(WidgetTester t) async {
  await t.tap(find.text('Conversation'));
  await _settle(t, 4);
}

void _expectNone(List<String> texts, String why) {
  for (final s in texts) {
    expect(find.text(s), findsNothing, reason: '"$s" — $why');
  }
}

void _expectAll(List<String> texts, String why) {
  for (final s in texts) {
    expect(find.text(s), findsOneWidget, reason: '"$s" — $why');
  }
}

Map<String, Object?> _bodyOf(String line) =>
    jsonDecode(line.substring(line.indexOf('{'))) as Map<String, Object?>;

/// Every write and invoke in the log made by [uid].
List<String> _writesBy(String uid) => [
      for (final l in _server.log)
        if (!l.startsWith('GET ') && l.contains(':$uid ')) l
    ];

void _expectStopped(String what) => expect(
    _reported.map((f) => f.error.toString()),
    contains(endsWith('$what: the signed-in account changed')));

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    _server = MemberOwnerServer();
    await initTwoMemberSupabase(_server);
  });

  setUp(() {
    _server.reset();
    _seed();
    _reported.clear();
    setFailureSink(_reported.add);
  });
  tearDown(resetFailureSink);

  testWidgets(
      "A -> B with the screen open: A's brief, review, prediction, memories "
      "and conversation go; B gets B's own, freshly read", (t) async {
    await _as(t, memberA);
    await _pumpScreen(t);
    _expectAll(_aTexts, 'premise');

    await _as(t, memberB);
    await _settle(t);

    _expectNone(_aTexts, "A's card was still drawn for B");
    _expectAll(_bTexts, "B's own screen is read for B");
    await _toConversation(t);
    expect(find.text('my knee hurts'), findsNothing,
        reason: "A's conversation was drawn for B");
    expect(find.text('B question'), findsOneWidget);
    expect(_writesBy(memberB), isEmpty,
        reason: 'B wrote or invoked nothing; nothing of A\'s went out as B');
    await _close(t);
  });

  testWidgets("A's chat reply arriving after B signed in is never drawn",
      (t) async {
    await _as(t, memberA);
    await _pumpScreen(t);
    await _toConversation(t);
    final gate = holdOn(_server, 'POST ai-coach:$memberA');
    await t.enterText(find.byType(TextField), 'hello from A');
    await t.tap(find.byIcon(Icons.send_rounded));
    await _settle(t, 3);
    expect(_server.of('POST', 'ai-coach', by: memberA), hasLength(1),
        reason: 'premise');

    await _as(t, memberB);
    await _settle(t);
    gate.complete();
    await _settle(t);

    expect(find.text('reply for $memberA'), findsNothing,
        reason: "A's late reply was added to the conversation B sees");
    expect(find.text('hello from A'), findsNothing);
    if (find.text('Conversation').evaluate().isNotEmpty) await _toConversation(t);
    expect(find.text('reply for $memberA'), findsNothing);
    expect(find.text('B question'), findsOneWidget);
    expect(_server.of('POST', 'ai-coach', by: memberB), isEmpty);
    await _close(t);
  });

  testWidgets(
      "A's brief and review reads land after B signed in (no frame): nothing "
      'is generated as B', (t) async {
    // A has no brief today and no recent review: each card would GENERATE.
    _server.answers.remove('ai_insights:daily_insight:$memberA');
    _server.answers.remove('ai_reviews:$memberA');
    final insights = holdOn(_server, 'GET ai_insights:$memberA');
    final reviews = holdOn(_server, 'GET ai_reviews:$memberA');
    await _as(t, memberA);
    await _pumpScreen(t);
    expect(_server.calls, contains('GET ai_reviews:$memberA'), reason: 'premise');

    await _as(t, memberB);
    insights.complete();
    reviews.complete();
    await _settle(t);

    expect(_server.of('POST', 'ai-coaching-engine', by: memberB), isEmpty,
        reason: "A's card went on to generate a brief / review — as B");
    expect(_server.of('POST', 'ai-coaching-engine'), isEmpty);
    _expectNone(['generated for B', 'generated for A'], 'nothing was generated');
    _expectAll(_bTexts, "B's own screen");
    // Round 2 (mutant screen-daily-insight-read-then-generate-no-guard): the
    // CARD stops at its own check after the read. Without it the card goes on
    // to ask for a generation and only the service's owner check refuses it —
    // recorded as a refused generate that nobody asked for.
    expect(
        _reported.map((f) => f.error.toString()),
        isNot(contains(contains('Generating'))),
        reason: "A's card, its read answered after B signed in, went on to "
            'ask for a brief / review: it must stop at its own check');
    await _close(t);
  });

  testWidgets(
      "A's goal prediction generated, answering after B signed in, is never "
      'drawn or announced', (t) async {
    _server.answers.remove('ai_goal_predictions:$memberA');
    await _as(t, memberA);
    await _pumpScreen(t);
    final gate = holdOn(_server, 'POST ai-coaching-engine:$memberA');
    await t.tap(find.text('Predict My Goal Date'));
    await _settle(t, 3);
    expect(_server.of('POST', 'ai-coaching-engine', by: memberA), hasLength(1),
        reason: 'premise');

    await _as(t, memberB);
    await _settle(t);
    gate.complete();
    await _settle(t);

    expect(find.text('generated for A'), findsNothing,
        reason: "A's prediction was drawn for B");
    expect(find.text('Could not generate prediction.'), findsNothing);
    expect(find.text('B prediction summary'), findsOneWidget);
    expect(_server.of('POST', 'ai-coaching-engine', by: memberB), isEmpty);
    await _close(t);
  });

  testWidgets(
      "A's style chip pressed after B signed in (no frame): B's persona is "
      'not written, B is told nothing', (t) async {
    await _as(t, memberA);
    await _pumpScreen(t);
    final chip = t.widget<GestureDetector>(find
        .ancestor(of: find.text('Tough Love'), matching: find.byType(GestureDetector))
        .first);

    await _as(t, memberB);
    chip.onTap!();
    await _settle(t);

    expect(_server.of('POST', 'ai_profiles'), isEmpty,
        reason: "A's style choice was upserted onto B's ai_profiles row");
    _expectStopped('Saving the coach style');
    expect(find.text("Couldn't change the coach style — try again."), findsNothing);
    expect(find.text('Coach style updated — your next brief will match.'),
        findsNothing);
    await _close(t);
  });

  testWidgets(
      "A's Add memory dialog: A -> B closes it with A's words; Save pressed "
      'with no frame writes nothing as B', (t) async {
    await _as(t, memberA);
    await _pumpScreen(t);
    await t.tap(find.bySemanticsLabel('Add memory'));
    await _settle(t, 3);
    await t.enterText(find.byType(TextField).last, 'A secret injury');
    await t.pump();

    // With a frame: the dialog goes, and A's words with it.
    await _as(t, memberB);
    await _settle(t);
    expect(find.text('A secret injury'), findsNothing,
        reason: "A's draft survived into B's session");
    expect(find.text('Tell your coach'), findsNothing);
    final save = find.widgetWithText(TextButton, 'Save');
    if (save.evaluate().isNotEmpty) {
      await t.tap(save);
      await _settle(t);
    }
    expect(_server.of('POST', 'ai_memories'), isEmpty,
        reason: "A's memory was saved onto B's record");
    await _close(t);
  });

  testWidgets(
      "A's memory Save pressed after B signed in (no frame) writes nothing",
      (t) async {
    await _as(t, memberA);
    await _pumpScreen(t);
    await t.tap(find.bySemanticsLabel('Add memory'));
    await _settle(t, 3);
    await t.enterText(find.byType(TextField).last, 'A secret injury');
    await t.pump();
    final save =
        t.widget<TextButton>(find.widgetWithText(TextButton, 'Save'));

    await _as(t, memberB);
    save.onPressed!();
    await _settle(t);

    expect(_server.of('POST', 'ai_memories'), isEmpty,
        reason: "A's memory went out as B (user_id = B)");
    _expectStopped('Saving a coaching memory');
    expect(find.text("Couldn't save that for your coach — try again."),
        findsNothing);
    await _close(t);
  });

  testWidgets(
      "A's memory delete pressed after B signed in (no frame) sends nothing",
      (t) async {
    await _as(t, memberA);
    await _pumpScreen(t);
    final del = t.widget<IconButton>(find
        .ancestor(of: find.byIcon(Icons.close_rounded), matching: find.byType(IconButton))
        .first);

    await _as(t, memberB);
    del.onPressed!();
    await _settle(t);

    expect(_server.of('DELETE', 'ai_memories'), isEmpty,
        reason: "A's delete of mem-A went out as B");
    _expectStopped('Removing a coaching memory');
    expect(find.text("Couldn't remove that — try again."), findsNothing);
    await _close(t);
  });

  testWidgets(
      "sign-out takes A's screen away; A back in gets A's own, read again",
      (t) async {
    await _as(t, memberA);
    await _pumpScreen(t);
    _expectAll(_aTexts, 'premise');

    await t.runAsync(signOut);
    await _settle(t);
    _expectNone(_aTexts, 'signed out is a change of account');

    final readsBefore =
        _server.calls.where((c) => c == 'GET ai_memories:$memberA').length;
    await _as(t, memberA);
    await _settle(t);
    _expectAll(_aTexts, "A's screen, read for A again");
    expect(
        _server.calls.where((c) => c == 'GET ai_memories:$memberA').length,
        readsBefore + 1,
        reason: 'a fresh read, not a held one');
    expect(_server.of('GET', 'ai_memories', by: 'anon'), isEmpty,
        reason: 'nothing was read signed out');
    await _close(t);
  });

  testWidgets("B's reads pending: nothing of A's, and not a new conversation",
      (t) async {
    await _as(t, memberA);
    await _pumpScreen(t);
    final gates = [
      for (final table in [
        'ai_conversations', 'ai_insights', 'ai_reviews',
        'ai_goal_predictions', 'ai_profiles', 'ai_memories',
      ])
        holdOn(_server, 'GET $table:$memberB')
    ];

    await _as(t, memberB);
    await _settle(t);
    _expectNone(_aTexts, "A's card drawn while B's read is pending");
    await _toConversation(t);
    expect(find.text('my knee hurts'), findsNothing);
    expect(find.textContaining("I'm your AI Coach"), findsNothing,
        reason: 'B has history still being read: not a new conversation');

    for (final g in gates) {
      g.complete();
    }
    await _settle(t);
    expect(find.text('B question'), findsOneWidget);
    await _close(t);
  });

  testWidgets("B's reads failed: B is told so, never shown A's", (t) async {
    await _as(t, memberA);
    await _pumpScreen(t);
    _server.fails
      ..add('GET ai_memories:$memberB')
      ..add('GET ai_conversations:$memberB');

    await _as(t, memberB);
    await _settle(t);
    expect(find.text('left knee A'), findsNothing);
    expect(find.text("Couldn't load what your coach remembers"), findsOneWidget);
    await _toConversation(t);
    expect(find.text('my knee hurts'), findsNothing);
    expect(find.text("Couldn't load your conversation"), findsOneWidget);
    expect(find.textContaining("I'm your AI Coach"), findsNothing);
    await _close(t);
  });

  // ── Round 2: the owner checks each layer carries on its own ───────────────
  group('round 2', () {
    testWidgets(
        "Send pressed after B signed in (no frame): A's message never goes to "
        'the AI coach as B', (t) async {
      await _as(t, memberA);
      await _pumpScreen(t);
      await _toConversation(t);
      await t.enterText(find.byType(TextField), 'typed by A');
      await t.pump();
      final send = t.widget<GestureDetector>(find
          .ancestor(
              of: find.byIcon(Icons.send_rounded),
              matching: find.byType(GestureDetector))
          .first);

      await _as(t, memberB);
      send.onTap!();
      await _settle(t);

      expect(_server.of('POST', 'ai-coach'), isEmpty,
          reason: "A's message was sent to ai-coach with B's token");
      _expectStopped('Asking the AI coach');
      expect(find.text('reply for $memberB'), findsNothing);
      expect(find.text('typed by A'), findsNothing);
      await _close(t);
    });

    testWidgets(
        "Predict pressed after B signed in (no frame): nothing is generated "
        'as B', (t) async {
      _server.answers.remove('ai_goal_predictions:$memberA');
      await _as(t, memberA);
      await _pumpScreen(t);
      final predict = t.widget<GestureDetector>(find
          .ancestor(
              of: find.text('Predict My Goal Date'),
              matching: find.byType(GestureDetector))
          .first);

      await _as(t, memberB);
      predict.onTap!();
      await _settle(t);

      expect(_server.of('POST', 'ai-coaching-engine'), isEmpty,
          reason: "A's Predict ran the engine as B");
      _expectStopped('Generating goal_prediction');
      expect(find.text('generated for B'), findsNothing);
      expect(find.text('Could not generate prediction.'), findsNothing);
      expect(find.text('B prediction summary'), findsOneWidget);
      await _close(t);
    });

    testWidgets(
        "A's goal prediction failing, answered after B signed in and before a "
        'frame: B is never shown a bar for it', (t) async {
      _server.answers.remove('ai_goal_predictions:$memberA');
      await _as(t, memberA);
      await _pumpScreen(t);
      const key = 'POST ai-coaching-engine:$memberA';
      final gate = holdOn(_server, key);
      _server.fails.add(key);
      await t.tap(find.text('Predict My Goal Date'));
      await _settle(t, 3);
      expect(_server.of('POST', 'ai-coaching-engine', by: memberA),
          hasLength(1), reason: 'premise');

      // B signs in and A's failure answers in the same gap: no frame between.
      await t.runAsync(() async {
        await signInAs(memberB);
        _server.holds.remove(key);
        gate.complete();
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      // Let A's answer run to the end with NO frame drawn (fake time and
      // microtasks only): a hidden tab, or the gap before B's first frame.
      for (var i = 0; i < 10; i++) {
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)));
        await t.binding.delayed(const Duration(milliseconds: 5));
      }
      var barSeen = false;
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 50));
        barSeen |= find.byType(SnackBar).evaluate().isNotEmpty;
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)));
      }

      expect(barSeen, isFalse,
          reason: "a bar for A's failed prediction came up on B's screen "
              '(emptied by OwnedText, but still a bar)');
      expect(find.text('Could not generate prediction.'), findsNothing);
      expect(_server.of('POST', 'ai-coaching-engine', by: memberB), isEmpty);
      expect(find.text('B prediction summary'), findsOneWidget);
      await _close(t);
    });

    testWidgets(
        "A's style save in flight across A -> B: one write, stamped A; B is "
        'told nothing and keeps B\'s style', (t) async {
      await _as(t, memberA);
      await _pumpScreen(t);
      final gate = holdOn(_server, 'POST ai_profiles:$memberA');
      await t.tap(find.text('Tough Love'));
      await _settle(t, 3);
      expect(_server.of('POST', 'ai_profiles', by: memberA), hasLength(1),
          reason: 'premise: in flight');

      await _as(t, memberB);
      await _settle(t);
      gate.complete();
      await _settle(t);

      final writes = _server.of('POST', 'ai_profiles');
      expect(writes, hasLength(1), reason: 'one write, never repeated as B');
      expect(_bodyOf(writes.single)['user_id'], memberA);
      expect(find.byType(SnackBar), findsNothing,
          reason: "B was told about A's style save");
      expect(
          find.text('Coach style updated — your next brief will match.'),
          findsNothing);
      expect(
          find.bySemanticsLabel('Coach style: Scientific'), findsOneWidget);
      expect(
          t.getSemantics(find.bySemanticsLabel('Coach style: Scientific')),
          isSemantics(isSelected: true),
          reason: "B's own style, freshly read, is the one shown as B's");
      await _close(t);
    });

    testWidgets(
        "A's add memory in flight across A -> B: one write, stamped A; B sees "
        "B's memories and no message", (t) async {
      await _as(t, memberA);
      await _pumpScreen(t);
      await t.tap(find.bySemanticsLabel('Add memory'));
      await _settle(t, 3);
      await t.enterText(find.byType(TextField).last, 'A secret injury');
      final gate = holdOn(_server, 'POST ai_memories:$memberA');
      await t.tap(find.widgetWithText(TextButton, 'Save'));
      await _settle(t, 3);
      expect(_server.of('POST', 'ai_memories', by: memberA), hasLength(1),
          reason: 'premise: in flight');

      await _as(t, memberB);
      await _settle(t);
      gate.complete();
      await _settle(t);

      final writes = _server.of('POST', 'ai_memories');
      expect(writes, hasLength(1));
      expect(_bodyOf(writes.single),
          allOf(containsPair('user_id', memberA),
              containsPair('content', 'A secret injury')));
      expect(find.text('A secret injury'), findsNothing);
      expect(find.text('left knee A'), findsNothing);
      expect(find.text('left knee B'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(_server.of('GET', 'ai_memories', by: memberA), hasLength(1),
          reason: "A's card did not re-read after its save: A had left");
      await _close(t);
    });

    testWidgets(
        "A's delete in flight, failing after A -> B: one delete, as A; B is "
        'not told "Couldn\'t remove that"', (t) async {
      await _as(t, memberA);
      await _pumpScreen(t);
      const key = 'DELETE ai_memories:$memberA';
      final gate = holdOn(_server, key);
      _server.zeroRows.add(key);
      await t.tap(find.bySemanticsLabel('Delete memory: left knee A'));
      await _settle(t, 3);
      expect(_server.of('DELETE', 'ai_memories', by: memberA), hasLength(1),
          reason: 'premise: in flight');

      await _as(t, memberB);
      await _settle(t);
      gate.complete();
      await _settle(t);

      final deletes = _server.of('DELETE', 'ai_memories');
      expect(deletes, hasLength(1));
      expect(deletes.single, contains('id=eq.mem-A'));
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text("Couldn't remove that — try again."), findsNothing);
      expect(find.text('left knee B'), findsOneWidget);
      expect(
          _reported
              .where((f) => f.origin == 'AICoachService.deleteMemory'),
          hasLength(1),
          reason: "A's 0-row delete is still recorded, once");
      await _close(t);
    });

    testWidgets(
        'control: the same member retries a failed conversation read and '
        'gets their history', (t) async {
      _server.fails.add('GET ai_conversations:$memberA');
      await _as(t, memberA);
      await _pumpScreen(t);
      await _toConversation(t);
      expect(find.text("Couldn't load your conversation"), findsOneWidget,
          reason: 'premise');
      expect(find.text('my knee hurts'), findsNothing);

      _server.fails.remove('GET ai_conversations:$memberA');
      await t.tap(find.widgetWithText(TextButton, 'Try again'));
      await _settle(t);

      expect(find.text("Couldn't load your conversation"), findsNothing);
      expect(find.text('my knee hurts'), findsOneWidget);
      expect(find.text('answer for A'), findsOneWidget);
      expect(find.textContaining("I'm your AI Coach"), findsNothing,
          reason: 'A has history: not a new conversation');
      expect(_server.calls.where((c) => c == 'GET ai_conversations:$memberA'),
          hasLength(2), reason: 'read, then read again on Try again');
      expect(_server.of('GET', 'ai_conversations', by: memberB), isEmpty);
      expect(
          _reported.where(
              (f) => f.origin == 'AICoachService.getConversationHistory'),
          hasLength(1),
          reason: 'the first failure, recorded once');
      expect(_reported.map((f) => f.error.toString()),
          isNot(contains(contains('signed-in account changed'))));
      await _close(t);
    });
  });

  group('controls: the same member', () {
    testWidgets(
        'loads, sends once, and a token refresh keeps the conversation and '
        'the half-typed message', (t) async {
      await _as(t, memberA);
      await _pumpScreen(t);
      _expectAll(_aTexts, 'normal load');
      await _toConversation(t);
      expect(find.text('my knee hurts'), findsOneWidget);

      await t.enterText(find.byType(TextField), 'hello from A');
      await t.tap(find.byIcon(Icons.send_rounded));
      await _settle(t);
      final sent = _server.of('POST', 'ai-coach');
      expect(sent, hasLength(1));
      expect(sent.single, startsWith('POST ai-coach:$memberA'));
      expect(_bodyOf(sent.single)['message'], 'hello from A');
      expect(find.text('reply for $memberA'), findsOneWidget);

      await t.enterText(find.byType(TextField), 'half typed');
      await t.runAsync(refreshSession);
      await _settle(t);
      expect(Supabase.instance.client.auth.currentUser?.id, memberA,
          reason: 'premise');
      expect(find.text('half typed'), findsOneWidget,
          reason: 'a token refresh is the same member');
      expect(find.text('reply for $memberA'), findsOneWidget);
      expect(find.text('my knee hurts'), findsOneWidget);
      expect(_server.calls.where((c) => c == 'GET ai_conversations:$memberA'),
          hasLength(1), reason: 'nothing was read again');
      expect(_reported, isEmpty);
      await _close(t);
    });

    testWidgets('style, memory add and delete go out once, as the member',
        (t) async {
      await _as(t, memberA);
      await _pumpScreen(t);

      await t.tap(find.text('Tough Love'));
      await _settle(t);
      final style = _server.of('POST', 'ai_profiles');
      expect(style, hasLength(1));
      expect(style.single, startsWith('POST ai_profiles:$memberA'));
      expect(_bodyOf(style.single)['user_id'], memberA);
      expect(find.text('Coach style updated — your next brief will match.'),
          findsOneWidget);

      await t.tap(find.bySemanticsLabel('Add memory'));
      await _settle(t, 3);
      await t.enterText(find.byType(TextField).last, 'likes rows');
      await t.tap(find.widgetWithText(TextButton, 'Save'));
      await _settle(t);
      final added = _server.of('POST', 'ai_memories');
      expect(added, hasLength(1));
      expect(_bodyOf(added.single),
          allOf(containsPair('user_id', memberA), containsPair('content', 'likes rows')));

      await t.tap(find.bySemanticsLabel('Delete memory: left knee A'));
      await _settle(t);
      final deleted = _server.of('DELETE', 'ai_memories');
      expect(deleted, hasLength(1));
      expect(deleted.single, startsWith('DELETE ai_memories:$memberA'));
      expect(_reported, isEmpty);
      await _close(t);
    });
  });
}
