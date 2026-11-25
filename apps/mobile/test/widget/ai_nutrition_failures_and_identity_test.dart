import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/core/config/app_env.dart';
import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/core/observability/network_failure.dart';
import 'package:circle_fitness/features/ai_nutrition/data/ai_nutrition_service.dart';
import 'package:circle_fitness/features/ai_nutrition/domain/ai_nutrition_provider.dart';
import 'package:circle_fitness/features/ai_nutrition/domain/grocery_list.dart';
import 'package:circle_fitness/features/ai_nutrition/domain/meal_plan.dart';
import 'package:circle_fitness/features/ai_nutrition/presentation/ai_nutrition_screen.dart';
import 'package:circle_fitness/features/ai_nutrition/presentation/grocery_list_screen.dart';
import 'package:circle_fitness/features/ai_nutrition/presentation/meal_plan_screen.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/nutrition/domain/nutrition_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../support/two_member_postgrest.dart';

// P0-FL-60b (c) · the nutrition AI: chat, meal plan, grocery list.
//
// At a82f993: none of the three recorded a failure; a rebuild that failed
// replaced the plan / list already on screen; every answer but four statuses
// was "Could not reach the AI coach"; an edit to the SAME member's sign-up
// details wiped the chat; and a half-typed question, a "Thinking…", and the
// plan's targets and dietary restrictions were left on screen for the next
// member — whose build then sent them as their own.
//
// Real service (its Dio answered here), real auth client and transitions, the
// screens kept mounted across them, no AccountScope.
//
// HOW TO SEE IT FAIL: `git checkout a82f993 -- lib/features/ai_nutrition`;
// the controls pass.

const _env = EnvConfig(
  environment: AppEnvironment.qa,
  supabaseUrl: 'https://qa-ref.supabase.co',
  supabaseAnonKey: 'qa-anon-key',
  stripePublishableKey: 'pk_test_qa',
);

const _list = 'PRODUCE:\n- Spinach (2 bags)\n';
const _other = 'Try again in a moment. If it keeps happening, contact support.';
const _net = 'Check your connection and try again.';
const _noAnswer =
    "Couldn't get an answer from the AI coach — try again in a moment. If it "
    'keeps happening, contact support.';
const _notReached =
    "Couldn't reach the AI coach — check your connection and try again.";

typedef _Sent = ({String who, Map<String, dynamic> body});

/// The `ai-nutrition` function: what was asked, and as whom (bearer `sub`).
class _Ai implements HttpClientAdapter {
  final sent = <_Sent>[];
  int status = 200;
  DioExceptionType? down;
  Object body = const {'text': 'reply'};
  Completer<void>? gate;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final jwt = '${options.headers['Authorization']}'.split('.');
    final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(jwt[1])))) as Map;
    sent.add((
      who: claims['sub'] as String,
      body: Map<String, dynamic>.from(options.data as Map)
    ));
    final (s, b, d) = (status, body, down);
    final g = gate;
    if (g != null) await g.future;
    if (d != null) throw DioException(requestOptions: options, type: d);
    return ResponseBody.fromString(jsonEncode(b), s, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late TwoMemberPostgrest server;
  late _Ai ai;
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = TwoMemberPostgrest();
    await initTwoMemberSupabase(server);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugin.csdcorp.com/speech_to_text'),
            (call) async => false);
  });

  setUp(() async {
    server.reset();
    ai = _Ai();
    reported.clear();
    setFailureSink(reported.add);
    await signInAs(memberA);
  });
  tearDown(resetFailureSink);

  Iterable<String> origins() => reported.map((f) => f.origin);

  Map<String, double> goalsA = const {};
  Completer<void>? goalsGate;

  ProviderContainer container() {
    goalsA = {'calories': 2600, 'protein': 190, 'carbs': 300, 'fat': 90};
    goalsGate = null;
    final c = ProviderContainer(overrides: [
      aiNutritionServiceProvider.overrideWith((ref) => AiNutritionService(
          dio: Dio()..httpClientAdapter = ai, env: _env)),
      nutritionGoalsProvider.overrideWith((ref) async {
        final uid = ref.watch(currentUserProvider.select((u) => u?.id));
        if (uid == memberA) return goalsA;
        final g = goalsGate;
        if (g != null) await g.future;
        return {'calories': 1500, 'protein': 100, 'carbs': 150, 'fat': 50};
      }),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 8; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<ProviderContainer> show(WidgetTester t, Widget screen) async {
    t.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 2600);
    addTearDown(t.view.reset);
    final c = container();
    await t.pumpWidget(UncontrolledProviderScope(
        container: c, child: MaterialApp(home: screen)));
    await settle(t);
    return c;
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 7));
  }

  Future<void> switchTo(WidgetTester t, String? uid) async {
    await t.runAsync(() => uid == null ? signOut() : signInAs(uid));
    await settle(t);
  }

  void nothingRaw() {
    expect(find.textContaining('SECRET'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
  }

  Finder failedLoad(String what) => find.text("Couldn't load $what");

  // ── chat ──────────────────────────────────────────────────────────────────
  group('chat', () {
    Future<void> ask(WidgetTester t, String text) async {
      await t.enterText(find.byType(TextField), text);
      await t.tap(find.byIcon(Icons.send));
      await settle(t);
    }

    String draft(WidgetTester t) =>
        t.widget<TextField>(find.byType(TextField)).controller!.text;

    for (final (name, set, sentence, network) in <(
      String,
      void Function(),
      String,
      bool
    )>[
      ('a 500', () => ai.status = 500, _noAnswer, false),
      ('a 404', () => ai.status = 404, _noAnswer, false),
      ('an empty reply', () => ai.body = {'text': ''}, _noAnswer, false),
      ('no connection', () => ai.down = DioExceptionType.connectionError,
          _notReached, true),
      ('a timeout', () => ai.down = DioExceptionType.receiveTimeout,
          _notReached, true),
      ('a bad certificate', () => ai.down = DioExceptionType.badCertificate,
          _noAnswer, false),
    ]) {
      testWidgets('$name: recorded once, the right next step, not kept as a '
          'turn the coach said', (t) async {
        set();
        await show(t, const AiNutritionScreen());
        await ask(t, 'What now?');
        expect(find.text(sentence), findsOneWidget);
        expect(origins(), ['aiNutrition.chat.send'],
            reason: 'THE defect: nothing was recorded');
        expect(isNetworkFailure(reported.single.error), network);
        expect(reported.single.error, isNot(isA<DioException>()),
            reason: "it carries the member's token and what they asked");
        nothingRaw();

        // The next turn's history has none of it.
        ai
          ..status = 200
          ..down = null
          ..body = {'text': 'reply'};
        await ask(t, 'And now?');
        expect(find.text('reply'), findsOneWidget);
        expect(jsonEncode(ai.sent.last.body['history']),
            isNot(contains("Couldn't")));
        await close(t);
      });
    }

    testWidgets('Send it again: one request while it runs, then the answer',
        (t) async {
      ai.status = 503;
      await show(t, const AiNutritionScreen());
      await ask(t, 'What now?');
      ai
        ..status = 200
        ..gate = Completer<void>();
      await t.tap(find.text('Send it again'));
      await settle(t);
      expect(find.text('Thinking...'), findsOneWidget,
          reason: 'THE defect: nothing showed, and Send stayed open');
      await t.tap(find.byIcon(Icons.send));
      await settle(t);
      expect(ai.sent, hasLength(2));
      ai.gate!.complete();
      await settle(t);
      expect(find.text('reply'), findsOneWidget);
      expect(find.text('What now?'), findsOneWidget);
      await close(t);
    });

    testWidgets('POSITIVE CONTROL: asked and answered; nothing recorded; the '
        'request has the same shape', (t) async {
      await show(t, const AiNutritionScreen());
      await ask(t, 'What now?');
      expect(find.text('reply'), findsOneWidget);
      expect(reported, isEmpty);
      expect(ai.sent.single.who, memberA);
      expect(ai.sent.single.body.keys, ['message', 'history']);
      expect(ai.sent.single.body['message'], 'What now?');
      await close(t);
    });

    testWidgets('a new User for the same member keeps the chat, the draft and '
        'the answer in flight', (t) async {
      final c = await show(t, const AiNutritionScreen());
      ai.gate = Completer<void>();
      await ask(t, 'What now?');
      await t.enterText(find.byType(TextField), 'half typed');
      final before = c.read(currentUserProvider);
      await t.runAsync(refreshSession);
      await settle(t);
      expect(c.read(currentUserProvider), isNot(before), reason: 'premise');
      expect(find.text('What now?'), findsOneWidget,
          reason: 'THE defect: an edit to their details wiped the chat');
      expect(draft(t), 'half typed');
      ai.gate!.complete();
      await settle(t);
      expect(find.text('reply'), findsOneWidget);
      await close(t);
    });

    for (final to in [memberB, null]) {
      final how = to == null ? 'sign-out' : 'A → B';
      testWidgets("$how: A's turns, half-typed question and Thinking… are gone",
          (t) async {
        await show(t, const AiNutritionScreen());
        await ask(t, 'I am diabetic');
        ai.gate = Completer<void>();
        await ask(t, 'What now?');
        await t.enterText(find.byType(TextField), 'my weight is');
        await switchTo(t, to);
        expect(find.text('I am diabetic'), findsNothing);
        expect(draft(t), isEmpty, reason: 'THE defect: left in the composer');
        expect(find.text('Thinking...'), findsNothing);

        // A's answer lands: to nobody.
        ai.body = {'text': 'for B'};
        ai.gate!.complete();
        ai.gate = null;
        await settle(t);
        expect(find.text('reply'), findsNothing);
        expect(reported, isEmpty, reason: 'dropped, not thrown');
        if (to != null) {
          await ask(t, 'Hello');
          expect(find.text('for B'), findsOneWidget);
          expect(ai.sent.last.who, memberB);
          expect(jsonEncode(ai.sent.last.body), isNot(contains('diabetic')));
        }
        await switchTo(t, memberA);
        expect(find.text('I am diabetic'), findsNothing);
        await close(t);
      });
    }

    testWidgets("A's late failure is recorded, and is nothing to B; B's own "
        'Thinking… outlives it', (t) async {
      await show(t, const AiNutritionScreen());
      ai
        ..status = 500
        ..gate = Completer<void>();
      final a = ai.gate!;
      await ask(t, 'What now?');
      await switchTo(t, memberB);
      ai
        ..status = 200
        ..gate = Completer<void>();
      final b = ai.gate!;
      await ask(t, 'Hello');
      a.complete();
      await settle(t);
      expect(find.text(_noAnswer), findsNothing);
      expect(find.text('Thinking...'), findsOneWidget,
          reason: "THE defect: A's answer ended B's wait");
      expect(origins(), ['aiNutrition.chat.send']);
      b.complete();
      await settle(t);
      expect(find.text('reply'), findsOneWidget);
      await close(t);
    });

    testWidgets("a send in the instant before the screen hears that B signed "
        'in: nothing goes out, recorded', (t) async {
      final c = await show(t, const AiNutritionScreen());
      await ask(t, 'I am diabetic');
      final asA = c.read(aiNutritionNotifierProvider.notifier);
      final sentBefore = ai.sent.length;
      String? owner;
      await t.runAsync(() async {
        final switched = signInAs(memberB);
        while (Supabase.instance.client.auth.currentUser?.id == memberA) {
          await null;
        }
        owner = Supabase.instance.client.auth.currentUser?.id;
        unawaited(asA.sendMessage('and 92 kg'));
        unawaited(asA.retryLastTurn());
        await switched;
      });
      await settle(t);
      expect(owner, memberB, reason: 'premise');
      expect(ai.sent, hasLength(sentBefore),
          reason: "A's question and turns went out under B's login");
      expect(reported, isNotEmpty);
      expect(origins().toSet(), {'aiNutrition.identity'});
      expect('${reported.first.error}',
          contains('the signed-in account changed'));
      expect(find.text('I am diabetic'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      await close(t);
    });
  });

  // ── meal plan ─────────────────────────────────────────────────────────────
  group('meal plan', () {
    Future<void> tap(WidgetTester t, String label) async {
      await t.ensureVisible(find.text(label));
      await t.tap(find.text(label));
      await settle(t);
    }

    Future<ProviderContainer> built(WidgetTester t) async {
      final c = await show(t, const MealPlanScreen());
      ai.body = {'text': 'Mon: oats'};
      await tap(t, 'Generate Meal Plan');
      expect(find.text('Mon: oats'), findsOneWidget, reason: 'premise');
      return c;
    }

    for (final (name, set, hint) in <(String, void Function(), String)>[
      ('a 500', () => ai.status = 500, _other),
      ('no connection', () => ai.down = DioExceptionType.connectionError, _net),
      ('a blank plan', () => ai.body = {'text': ' \n '}, _other),
    ]) {
      testWidgets('rebuild → $name: the plan stays, said, recorded; Try again '
          'replaces it', (t) async {
        final h = t.ensureSemantics();
        await built(t);
        set();
        await tap(t, mealPlanRebuildLabel);
        expect(find.text('Mon: oats'), findsOneWidget,
            reason: 'THE defect: the plan was thrown away');
        expect(find.text(mealPlanFailedTitle), findsNothing);
        expect(failedLoad('a different plan'), findsOneWidget);
        expect(find.text('$hint The plan below has not changed.'),
            findsOneWidget);
        expect(origins(), ['aiNutrition.mealPlan.build']);
        expect(find.text(mealPlanToGroceryLabel), findsOneWidget);
        nothingRaw();

        ai
          ..status = 200
          ..down = null
          ..body = {'text': 'Mon: eggs'}
          ..gate = Completer<void>();
        final n = ai.sent.length;
        await tap(t, 'Try again');
        expect(find.bySemanticsLabel('Retrying'), findsOneWidget);
        await t.tap(find.bySemanticsLabel('Retrying'));
        await settle(t);
        expect(ai.sent, hasLength(n + 1));
        ai.gate!.complete();
        await settle(t);
        expect(find.text('Mon: eggs'), findsOneWidget);
        expect(failedLoad('a different plan'), findsNothing);
        h.dispose();
        await close(t);
      });
    }

    testWidgets('the first build fails: FIT-093 as before (no failure text as '
        'a plan), now recorded and announced', (t) async {
      final h = t.ensureSemantics();
      ai.status = 500;
      final c = await show(t, const MealPlanScreen());
      await tap(t, 'Generate Meal Plan');
      expect(find.text(mealPlanFailedTitle), findsOneWidget);
      expect(c.read(mealPlanNotifierProvider).content, isNull);
      expect(origins(), ['aiNutrition.mealPlan.build']);
      expect(failedLoad('a different plan'), findsNothing);
      expect(
          t
              .getSemantics(find.text(mealPlanFailedTitle))
              .flagsCollection
              .isLiveRegion,
          isTrue);
      h.dispose();
      await close(t);
    });

    testWidgets('POSITIVE CONTROL: built, with the targets on screen; nothing '
        'recorded', (t) async {
      await built(t);
      expect(reported, isEmpty);
      expect(ai.sent.single.who, memberA);
      expect(ai.sent.single.body['message'], contains('2600 kcal'));
      expect(ai.sent.single.body['history'], isEmpty);
      await close(t);
    });

    testWidgets('a new User for the same member keeps the plan and the form',
        (t) async {
      await built(t);
      await tap(t, 'Vegan');
      await t.runAsync(refreshSession);
      await settle(t);
      expect(find.text('Mon: oats'), findsOneWidget,
          reason: 'THE defect: an edit to their details wiped the plan');
      await tap(t, mealPlanRebuildLabel);
      expect(ai.sent.last.body['message'], contains('2600 kcal'));
      expect(ai.sent.last.body['message'], contains('restrictions: Vegan'));
      await close(t);
    });

    testWidgets("A → B: A's plan, targets, days and restrictions are gone; B's "
        "build sends B's own", (t) async {
      await built(t);
      await tap(t, 'Vegan');
      await tap(t, '3 days');
      final goals = goalsGate = Completer<void>();
      await switchTo(t, memberB);
      expect(find.text('Mon: oats'), findsNothing);
      expect(find.text('2600 kcal'), findsNothing,
          reason: "THE defect: A's targets stayed on B's form");
      goals.complete();
      await settle(t);
      expect(find.text('1500 kcal'), findsOneWidget);
      await tap(t, 'Generate Meal Plan');
      expect(ai.sent.last.who, memberB);
      final asked = ai.sent.last.body['message'] as String;
      expect(asked, contains('1500 kcal'));
      expect(asked, contains('restrictions: None'));
      expect(asked, contains('7-day'));
      await close(t);
    });

    testWidgets("A's plan lands after B signed in: not B's, and B can build at "
        'once', (t) async {
      await show(t, const MealPlanScreen());
      ai
        ..body = {'text': 'Mon: oats'}
        ..gate = Completer<void>();
      final a = ai.gate!;
      await tap(t, 'Generate Meal Plan');
      await switchTo(t, memberB);
      expect(find.text('Generating your meal plan...'), findsNothing);
      a.complete();
      ai
        ..gate = null
        ..body = {'text': 'B: rice'};
      await settle(t);
      expect(find.text('Mon: oats'), findsNothing);
      expect(reported, isEmpty, reason: 'dropped, not thrown');
      await tap(t, 'Generate Meal Plan');
      expect(find.text('B: rice'), findsOneWidget);
      await close(t);
    });

    testWidgets('sign-out then the same member back: an empty form and no plan',
        (t) async {
      await built(t);
      await switchTo(t, null);
      expect(find.text('Mon: oats'), findsNothing);
      await switchTo(t, memberA);
      expect(find.text('Mon: oats'), findsNothing);
      expect(find.text('2600 kcal'), findsOneWidget);
      await close(t);
    });
  });

  // ── grocery list ──────────────────────────────────────────────────────────
  group('grocery list', () {
    Future<ProviderContainer> ready(WidgetTester t) async {
      ai.body = {'text': 'Mon: oats'};
      final c = await show(t, const GroceryListScreen());
      await t.runAsync(() => c
          .read(mealPlanNotifierProvider.notifier)
          .generateMealPlan(calories: 1, protein: 1, carbs: 1, fat: 1,
              restrictions: const [], days: 1));
      await settle(t);
      return c;
    }

    Future<ProviderContainer> built(WidgetTester t) async {
      final c = await ready(t);
      ai.body = {'text': _list};
      await t.tap(find.text('Generate Grocery List'));
      await settle(t);
      expect(find.textContaining('Spinach'), findsOneWidget, reason: 'premise');
      return c;
    }

    for (final (name, set, hint) in <(String, void Function(), String)>[
      ('a 500', () => ai.status = 500, _other),
      ('no connection', () => ai.down = DioExceptionType.connectionError, _net),
      ('an unreadable list', () => ai.body = {'text': 'Sorry!'}, _other),
    ]) {
      testWidgets('rebuild → $name: the list stays, said, recorded; Try again '
          'replaces it', (t) async {
        await built(t);
        set();
        await t.tap(find.text(groceryRebuildLabel));
        await settle(t);
        expect(find.textContaining('Spinach'), findsOneWidget,
            reason: 'THE defect: the list was thrown away');
        expect(failedLoad('a new list'), findsOneWidget);
        expect(find.text('$hint The list below has not changed.'),
            findsOneWidget);
        expect(origins(), ['aiNutrition.groceryList.build']);
        nothingRaw();

        ai
          ..status = 200
          ..down = null
          ..body = {'text': 'DAIRY:\n- Milk\n'};
        await t.tap(find.text('Try again'));
        await settle(t);
        expect(find.textContaining('Milk'), findsOneWidget);
        expect(find.textContaining('Spinach'), findsNothing);
        expect(failedLoad('a new list'), findsNothing);
        await close(t);
      });
    }

    testWidgets('the first build fails: FIT-094 as before, now recorded and '
        'announced', (t) async {
      final h = t.ensureSemantics();
      await ready(t);
      ai.status = 500;
      await t.tap(find.text('Generate Grocery List'));
      await settle(t);
      expect(find.text(groceryFailedTitle), findsOneWidget);
      expect(origins(), ['aiNutrition.groceryList.build']);
      expect(
          t
              .getSemantics(find.text(groceryFailedTitle))
              .flagsCollection
              .isLiveRegion,
          isTrue);
      h.dispose();
      await close(t);
    });

    testWidgets('POSITIVE CONTROL: built; nothing recorded', (t) async {
      await built(t);
      expect(reported, isEmpty);
      await close(t);
    });

    testWidgets('a new User for the same member keeps the list', (t) async {
      await built(t);
      await t.runAsync(refreshSession);
      await settle(t);
      expect(find.textContaining('Spinach'), findsOneWidget);
      await close(t);
    });

    testWidgets('NEGATIVE CONTROL: no plan yet is not a failure', (t) async {
      await show(t, const GroceryListScreen());
      expect(find.text('No meal plan yet'), findsOneWidget);
      expect(find.textContaining("Couldn't"), findsNothing);
      expect(reported, isEmpty);
      await close(t);
    });

    testWidgets("A → B with A's list in flight: it is not B's", (t) async {
      final c = await ready(t);
      ai
        ..body = {'text': _list}
        ..gate = Completer<void>();
      await t.tap(find.text('Generate Grocery List'));
      await settle(t);
      await switchTo(t, memberB);
      expect(find.text('No meal plan yet'), findsOneWidget);
      ai.gate!.complete();
      await settle(t);
      expect(find.textContaining('Spinach'), findsNothing);
      expect(reported, isEmpty, reason: 'dropped, not thrown');
      expect(c.read(groceryListNotifierProvider).content, isNull);
      expect(c.read(mealPlanNotifierProvider).content, isNull);
      await close(t);
    });

    testWidgets("A's plan is not sent as B in the instant before the screens "
        'hear of B', (t) async {
      final c = await ready(t);
      final asA = c.read(groceryListNotifierProvider.notifier);
      final n = ai.sent.length;
      await t.runAsync(() async {
        final switched = signInAs(memberB);
        while (Supabase.instance.client.auth.currentUser?.id == memberA) {
          await null;
        }
        unawaited(asA.generateGroceryList('Mon: oats'));
        await switched;
      });
      await settle(t);
      expect(ai.sent, hasLength(n), reason: "A's plan went out as B");
      expect(origins(), ['aiNutrition.identity']);
      await close(t);
    });
  });
}
