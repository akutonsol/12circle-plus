import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/ai_coach/presentation/ai_coach_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/member_owner_server.dart';

// RM-2 round 2 (R-RM2-01 / UX N1) · the Meal Ideas, Progress Insight and Risk
// Assessment cards of the member's AI coach screen said NOTHING when
// `generate` (the member-facing `ai-coaching-engine`) failed. Meal Ideas went
// further: it set its list to `[]`, so the member's ideas vanished and the
// card showed its starting prompt again — a false empty. The brief, review and
// prediction cards already say "Could not generate …" in an OwnedText bar;
// these three now do the same, keep what they showed, and say nothing to B
// about A's failure.
//
// The screen is mounted alone, WITHOUT AccountScope, and stays mounted across
// a real switch on the real auth client. The fake answers by bearer token.
//
// HOW TO SEE IT FAIL: `git checkout 66f3ffd --
// apps/mobile/lib/features/ai_coach/presentation/ai_coach_screen.dart`: every
// "failure said" test finds no bar, and the Meal Ideas one finds A's ideas
// gone and the starting prompt back.

late MemberOwnerServer _server;
final _reported = <AppFailure>[];

const _engine = 'ai-coaching-engine';

class _Card {
  const _Card(this.name, this.type, this.failure, this.refresh, this.aText,
      this.bText, this.generated);
  final String name;
  final String type;
  final String failure;
  final String refresh;
  final String aText;
  final String bText;
  final String generated;
}

const _cards = [
  _Card('Meal Ideas', 'meal_suggestion', 'Could not generate meal ideas.',
      '↻ New ideas', 'A oats bowl', 'B oats bowl', 'generated meal'),
  _Card('Progress Insight', 'progress_insight',
      'Could not generate progress insight.', '↻ Refresh', 'A progress title',
      'B progress title', 'generated title'),
  _Card('Risk Assessment', 'risk_assessment',
      'Could not generate risk assessment.', '↻ Re-assess', 'A risk body',
      'B risk body', 'generated summary'),
];

String _today() => DateTime.now().toIso8601String().substring(0, 10);

void _seed() {
  for (final (m, tag) in [(memberA, 'A'), (memberB, 'B')]) {
    // A brief today and a recent review: those cards would otherwise
    // generate on open, and every POST counted here must be the card's own.
    _server.answers['ai_insights:daily_insight:$m'] = {
      'title': '$tag brief title', 'body': '$tag brief body', 'data': {}
    };
    _server.answers['ai_reviews:$m'] = {
      'summary': '$tag weekly summary', 'period_end': _today(), 'metrics': {}
    };
    _server.answers['ai_goal_predictions:$m'] = {
      'summary': '$tag prediction summary', 'projected_date': '2027-03-01'
    };
    _server.answers['ai_insights:meal_suggestion:$m'] = {
      'data': {
        'meals': [
          {'name': '$tag oats bowl', 'calories': 400}
        ]
      }
    };
    _server.answers['ai_insights:progress:$m'] = {
      'title': '$tag progress title', 'body': '$tag progress body'
    };
    _server.answers['ai_insights:risk:$m'] = {
      'body': '$tag risk body',
      'data': {'plateau_risk': 10, 'churn_risk': 20, 'injury_risk': 30}
    };
    _server.functions['$_engine:$m'] = {
      'result': {
        'meals': [
          {'name': 'generated meal', 'calories': 500}
        ],
        'title': 'generated title',
        'body': 'generated body',
        'summary': 'generated summary',
        'plateau_risk': 1,
        'churn_risk': 2,
        'injury_risk': 3,
      }
    };
  }
}

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

Iterable<AppFailure> _generateRecords() =>
    _reported.where((f) => f.origin == 'AICoachService.generate');

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

  for (final c in _cards) {
    group(c.name, () {
      testWidgets(
          'a failed generate is said, and what the card showed stays',
          (t) async {
        await _as(t, memberA);
        await _pumpScreen(t);
        expect(find.text(c.aText), findsOneWidget, reason: 'premise');
        _server.fails.add('POST $_engine:$memberA');

        await t.tap(find.text(c.refresh));
        await _settle(t);

        expect(find.text(c.aText), findsOneWidget,
            reason: 'THE defect (Meal Ideas): a failure cleared what was '
                'shown — a false empty');
        expect(find.text(c.failure), findsOneWidget,
            reason: 'THE defect: the ${c.name} failure was not said');
        expect(find.text(c.generated), findsNothing);
        final posts = _server.of('POST', _engine);
        expect(posts, hasLength(1));
        expect(posts.single, startsWith('POST $_engine:$memberA'));
        expect(posts.single, contains('"type":"${c.type}"'));
        expect(_generateRecords(), hasLength(1),
            reason: 'recorded once, by the service');
        expect(_reported.map((f) => '${f.error}').join(),
            isNot(contains('account changed')));
        await _close(t);
      });

      testWidgets(
          "A's failed generate answering after B signed in (no frame): B is "
          'shown no bar, B keeps B\'s card, nothing goes out as B', (t) async {
        await _as(t, memberA);
        await _pumpScreen(t);
        final key = 'POST $_engine:$memberA';
        final gate = holdOn(_server, key);
        _server.fails.add(key);
        await t.tap(find.text(c.refresh));
        await _settle(t, 3);
        expect(_server.of('POST', _engine, by: memberA), hasLength(1),
            reason: 'premise: in flight');

        await t.runAsync(() async {
          await signInAs(memberB);
          _server.holds.remove(key);
          gate.complete();
          await Future<void>.delayed(const Duration(milliseconds: 30));
        });
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
        await _settle(t);

        expect(barSeen, isFalse,
            reason: "a bar for A's failed ${c.name} came up on B's screen");
        expect(find.text(c.failure), findsNothing);
        expect(find.text(c.aText), findsNothing, reason: "A's card for B");
        expect(find.text(c.bText), findsOneWidget, reason: "B's own card");
        expect(_server.of('POST', _engine, by: memberB), isEmpty);
        await _close(t);
      });

      testWidgets('control: a generate that succeeds shows the new result, '
          'no bar, once as the member', (t) async {
        await _as(t, memberA);
        await _pumpScreen(t);
        await t.tap(find.text(c.refresh));
        await _settle(t);

        expect(find.text(c.generated), findsOneWidget);
        expect(find.text(c.failure), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        final posts = _server.of('POST', _engine);
        expect(posts, hasLength(1));
        expect(posts.single, startsWith('POST $_engine:$memberA'));
        expect(_reported, isEmpty);
        await _close(t);
      });
    });
  }

  testWidgets(
      'Meal Ideas with none yet: a failed first suggestion is said (the '
      'prompt stays, it was the only thing shown)', (t) async {
    _server.answers.remove('ai_insights:meal_suggestion:$memberA');
    await _as(t, memberA);
    await _pumpScreen(t);
    _server.fails.add('POST $_engine:$memberA');
    await t.tap(find.text('Suggest Meals'));
    await _settle(t);
    expect(find.text('Could not generate meal ideas.'), findsOneWidget,
        reason: 'THE defect: the failure looked like a fresh card');
    expect(find.text('Suggest Meals'), findsOneWidget);
    expect(_generateRecords(), hasLength(1));
    await _close(t);
  });

  testWidgets(
      'control: a token refresh for the same member keeps the cards; a '
      'failure after it is still said to them', (t) async {
    await _as(t, memberA);
    await _pumpScreen(t);
    await t.runAsync(refreshSession);
    await _settle(t);
    expect(Supabase.instance.client.auth.currentUser?.id, memberA,
        reason: 'premise');
    for (final c in _cards) {
      expect(find.text(c.aText), findsOneWidget,
          reason: 'a token refresh is the same member');
    }
    _server.fails.add('POST $_engine:$memberA');
    await t.tap(find.text('↻ Re-assess'));
    await _settle(t);
    expect(find.text('Could not generate risk assessment.'), findsOneWidget);
    expect(find.text('A risk body'), findsOneWidget);
    await _close(t);
  });
}
