// P0-FL-59e round 3 · a scanned product's missing value is never saved as 0.
//
// `lookupBarcode` read a value the product does not give as 0 (and cached that
// 0 for the next scan), and the sheet's own `?? 0` did the same: a product with
// no nutrition was logged, with success, as a 0 kcal meal. The rule is the AI
// scan's (P0-FL-61): missing is said and not saved; a real 0 stays 0.
//
// HOW TO SEE IT FAIL: put back 3a90049's nutrition_service and
// meals_dashboard_screen: every test but the POSITIVE CONTROLs fails. (The
// service tests need `openFoodFacts`, new here: there they do not compile, so
// put back the two files one at a time for the sheet's.) Round 4's "not an
// amount" fail on e0736a6.
import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/nutrition/data/nutrition_service.dart';
import 'package:circle_fitness/features/nutrition/presentation/meals_dashboard_screen.dart';
import 'package:circle_fitness/features/nutrition/presentation/widgets/barcode_scan_view.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/member_switch_server.dart';

/// OpenFoodFacts, answering [answer] to everything.
class _Off implements HttpClientAdapter {
  Object answer = const {};
  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      ResponseBody.fromString(jsonEncode(answer), 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });
  @override
  void close({bool force = false}) {}
}

const _whole = {'calories': 250.0, 'protein': 5.0, 'carbs': 40.0, 'fat': 9.5};

void main() {
  final server = MemberSwitchServer();
  final reported = <AppFailure>[];
  final off = _Off();

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const scanner = 'dev.steenbakker.mobile_scanner/scanner';
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('$scanner/method'),
        (call) async => switch (call.method) {
              'state' => 2, // denied: the view says so and stays up
              'request' => false,
              _ => null,
            });
    for (final name in ['event', 'deviceOrientation']) {
      messenger.setMockMethodCallHandler(
          MethodChannel('$scanner/$name'), (call) async => null);
    }
    await initTwoMemberSupabase(server);
    NutritionService.openFoodFacts.httpClientAdapter = off;
  });

  setUp(() async {
    server.reset();
    await signInAs(memberA);
    reported.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  Iterable<String> origins() => reported.map((f) => f.origin);

  Future<void> settle(WidgetTester t, [int n = 8]) async {
    for (var i = 0; i < n; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 12));
  }

  var logged = 0;
  Future<void> open(WidgetTester t,
      {Size size = const Size(500, 1600), String mode = 'barcode'}) async {
    logged = 0;
    await t.binding.setSurfaceSize(size);
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: ctx,
                isScrollControlled: true,
                builder: (_) => AddMealSheet(
                    initialMode: mode, onLogged: () => logged++),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await settle(t);
  }

  Future<void> scan(WidgetTester t, Map<String, Object?> food) async {
    t.widget<BarcodeScanView>(find.byType(BarcodeScanView)).onFound(food);
    await settle(t);
  }

  Iterable<SeenRequest> meals() => server.writes('nutrition_logs');

  group('the sheet', () {
    for (final (missing, said) in [
      (['calories'], 'calories'),
      (['protein'], 'protein'),
      (['carbs'], 'carbs'),
      (['fat'], 'fat'),
      (['calories', 'fat'], 'calories and fat'),
      (
        ['calories', 'protein', 'carbs', 'fat'],
        'calories, protein, carbs and fat'
      ),
    ]) {
      testWidgets('no $said: not logged, said, recorded, no points',
          (t) async {
        await open(t);
        await scan(t, {
          'name': 'Granola', ..._whole,
          for (final m in missing) m: null,
        });
        expect(server.writes(), isEmpty,
            reason: 'logged as 0: ${server.writes().toList()}');
        final notice = find.text("Couldn't read the $said for Granola — add it "
            'manually, or scan it again. Nothing was logged.');
        expect(notice, findsOneWidget);
        expect(notice.hitTestable(), findsOneWidget);
        expect(
            t.getSemantics(notice).getSemanticsData().flagsCollection.isLiveRegion,
            isTrue);
        expect(find.text('Food Added!'), findsNothing);
        expect(origins(), ['nutrition.barcode.incomplete']);
        expect(logged, 0);
        await close(t);
      });
    }

    testWidgets('a key that is not there at all is as missing as a null',
        (t) async {
      await open(t);
      await scan(t, {'name': 'Bar', 'calories': 100.0});
      expect(server.writes(), isEmpty);
      expect(find.textContaining("Couldn't read the protein, carbs and fat"),
          findsOneWidget);
      await close(t);
    });

    testWidgets('Add manually: what is known is filled in; what is missing is '
        'asked for, not 0; then it is logged as entered', (t) async {
      await open(t);
      await scan(t, {'name': 'Granola', ..._whole, 'calories': null, 'fat': null});
      await t.tap(find.text('Add manually'));
      await settle(t);
      expect(find.text('Add Custom Food'), findsOneWidget);
      String field(String hint) =>
          t.widget<TextField>(find.ancestor(
              of: find.text(hint), matching: find.byType(TextField)))
              .controller!
              .text;
      expect(field('Food name'), 'Granola');
      expect((field('Protein (g)'), field('Carbs (g)')), ('5', '40'));
      expect((field('Calories'), field('Fat (g)')), ('', ''));
      await t.tap(find.text('Add to List'));
      await settle(t);
      expect(find.text('Enter the calories, fat — 0 if there is none.'),
          findsOneWidget);
      expect(find.text('Add Custom Food'), findsOneWidget,
          reason: 'it was saved with a 0 nobody gave');
      await t.enterText(
          find.ancestor(
              of: find.text('Calories'), matching: find.byType(TextField)),
          '310');
      await t.enterText(
          find.ancestor(
              of: find.text('Fat (g)'), matching: find.byType(TextField)),
          '0'); // a real one
      await t.tap(find.text('Add to List'));
      await settle(t);
      expect(meals(), isEmpty, reason: 'listed, not logged yet');
      await t.tap(find.text('Log Granola'));
      await settle(t);
      final meal = meals().single;
      expect(
          (meal.who, meal.row['food_name'], meal.row['calories'],
              meal.row['protein'], meal.row['carbs'], meal.row['fat']),
          (memberA, 'Granola', 310, 5, 40, 0));
      await close(t);
    });

    testWidgets('Scan again: a new scanner, and the next whole product is '
        'logged', (t) async {
      await open(t);
      await scan(t, {'name': 'Granola', ..._whole, 'fat': null});
      expect(find.byType(BarcodeScanView), findsNothing);
      await t.tap(find.text('Scan again'));
      await settle(t);
      expect(find.byType(BarcodeScanView), findsOneWidget);
      expect(find.textContaining("Couldn't read"), findsNothing);
      await scan(t, {'name': 'Oats', ..._whole});
      expect(meals().single.row['food_name'], 'Oats');
      await close(t);
    });

    testWidgets('A\'s incomplete product goes with A; its buttons, undrawn, do '
        'nothing for B', (t) async {
      for (final button in ['Add manually', 'Scan again']) {
        await t.runAsync(() => signInAs(memberA));
        await open(t);
        await scan(t, {'name': 'Granola', ..._whole, 'fat': null});
        await t.runAsync(() => signInAs(memberB));
        await t.tap(find.text(button), warnIfMissed: false);
        await settle(t);
        expect(find.textContaining('Granola'), findsNothing);
        expect(find.text('Add Custom Food'), findsNothing);
        expect(find.text('Log Meal'), findsNothing);
        expect(server.writes(), isEmpty);
        await close(t);
      }
    });

    for (final scale in [1.0, 2.0, 3.0]) {
      testWidgets('320 wide, ${scale}x text: said whole, buttons 44 or more',
          (t) async {
        t.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        final previous = FlutterError.onError;
        final here = <String>[];
        FlutterError.onError = (d) {
          if (d.exceptionAsString().contains('overflowed')) {
            // (The sheet's own title row and tabs overflow on base too.)
            if ('${d.informationCollector?.call()}'.contains('_IncompleteProduct')) {
              here.add(d.exceptionAsString());
            }
            return;
          }
          previous?.call(d);
        };
        addTearDown(() => FlutterError.onError = previous);
        await open(t, size: const Size(320, 900));
        await scan(t, {'name': 'Granola', ..._whole, 'fat': null});
        FlutterError.onError = previous;
        expect(here, isEmpty);
        final notice = find.textContaining("Couldn't read the fat");
        expect(t.widget<Text>(notice).overflow, isNull);
        expect(t.widget<Text>(notice).maxLines, isNull);
        for (final b in ['Add manually', 'Scan again']) {
          final button = find.ancestor(
              of: find.text(b),
              matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));
          expect(t.getSize(button).height, greaterThanOrEqualTo(44));
          expect(
              t.getSemantics(button).getSemanticsData()
                  .hasAction(SemanticsAction.tap),
              isTrue);
        }
        await close(t);
      });
    }

    testWidgets('POSITIVE CONTROL: a whole product is logged as before, after a '
        'token refresh, and its real 0s stay 0', (t) async {
      await open(t);
      await t.runAsync(refreshSession);
      await scan(t, {
        'name': 'Cola Zero', 'calories': 0, 'protein': 0, 'carbs': 0, 'fat': 0,
      });
      final meal = meals().single;
      expect(
          (meal.who, meal.row['food_name'], meal.row['calories'],
              meal.row['protein'], meal.row['carbs'], meal.row['fat']),
          (memberA, 'Cola Zero', 0, 0, 0, 0));
      expect(logged, 1);
      expect(find.text('Food Added!'), findsOneWidget);
      expect(reported, isEmpty);
      await close(t);
    });
  });

  group('custom food: what is not an amount', () {
    Finder field(String hint) => find.ancestor(
        of: find.text(hint), matching: find.byType(TextField));

    Future<void> openCustom(WidgetTester t, {required bool scanned}) async {
      if (scanned) {
        await open(t);
        await scan(t, {'name': 'Granola', ..._whole, 'fat': null});
        await t.tap(find.text('Add manually'));
      } else {
        await open(t, mode: 'manual');
        await t.enterText(find.byType(TextField), 'z'); // matches no food
        await settle(t);
        await t.tap(find.textContaining('manually'));
        await settle(t);
        await t.enterText(field('Food name'), 'Granola');
        await t.enterText(field('Calories'), '250');
      }
      await settle(t);
      expect(find.text('Add Custom Food'), findsOneWidget, reason: 'premise');
    }

    /// A new food is listed, last, to be picked.
    Future<void> pickNew(WidgetTester t) async {
      await t.scrollUntilVisible(find.text('Granola'), 200,
          scrollable: find
              .descendant(
                  of: find.byType(AddMealSheet),
                  matching: find.byType(Scrollable))
              .last);
      await t.tap(find.text('Granola'));
      await settle(t);
    }

    for (final scanned in [false, true]) {
      for (final text in ['NaN', 'Infinity', '-Infinity', '1e999']) {
        testWidgets('$text is refused (${scanned ? 'a scanned' : 'a new'} food), '
            'then a number is taken', (t) async {
          await openCustom(t, scanned: scanned);
          await t.enterText(field('Fat (g)'), text);
          await t.tap(find.text('Add to List'));
          await settle(t);
          expect(find.text('Add Custom Food'), findsOneWidget,
              reason: '$text was saved as an amount');
          expect(find.text('Enter the fat — 0 if there is none.'),
              findsOneWidget);
          expect(t.takeException(), isNull);
          await t.enterText(
              find.ancestor(
                  of: find.text(text), matching: find.byType(TextField)),
              '2.5');
          await t.enterText(
              find.ancestor(
                  of: find.text('100'), matching: find.byType(TextField)),
              text); // the serving: as any that cannot be read, 100
          await t.tap(find.text('Add to List'));
          await settle(t);
          if (!scanned) await pickNew(t);
          await t.tap(find.text('Log Granola'));
          await settle(t);
          final meal = meals().single;
          expect((meal.who, meal.row['fat'], meal.row['amount_g']),
              (memberA, 2.5, 100));
          await close(t);
        });
      }
    }

    testWidgets('POSITIVE CONTROL (old too): a new food as entered, blanks as '
        'before', (t) async {
      await openCustom(t, scanned: false);
      await t.tap(find.text('Add to List'));
      await settle(t);
      expect(find.text('Add Custom Food'), findsNothing);
      await pickNew(t);
      await t.tap(find.text('Log Granola'));
      await settle(t);
      final meal = meals().single.row;
      expect((meal['calories'], meal['fat'], meal['amount_g']), (250, 0, 100));
      await close(t);
    });
  });

  group('the lookup', () {
    Map<String, Object?> product(Map<String, Object?> nutriments) => {
          'status': 1,
          'product': {'product_name': 'Granola', 'nutriments': nutriments},
        };

    Future<Map<String, dynamic>?> lookup() async {
      final found = await NutritionService().lookupBarcode('123');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return found;
    }

    test('a value the food database does not give is null, not 0 — and is '
        'cached as null', () async {
      off.answer = product({'proteins_100g': 5, 'fat_100g': 'unknown'});
      final found = await lookup();
      expect(found, {
        'name': 'Granola', 'calories': null, 'protein': 5.0, 'carbs': null,
        'fat': null,
      });
      final cached = server.writes('foods').single.body;
      final row = (cached is List ? cached.single : cached) as Map;
      expect(row.containsKey('calories_per_100g'), isTrue,
          reason: 'left out, the column defaults to 0');
      expect((row['calories_per_100g'], row['protein_per_100g'], row['fat_per_100g']),
          (null, 5, null));
    });

    test('a cached value that is null is null', () async {
      server.rows['foods'] = {
        memberA: [
          {
            'name': 'Granola', 'calories_per_100g': null, 'protein_per_100g': 5,
            'carbs_per_100g': 0, 'fat_per_100g': null,
          }
        ],
      };
      expect(await lookup(), {
        'name': 'Granola', 'calories': null, 'protein': 5.0, 'carbs': 0.0,
        'fat': null,
      });
    });

    test('a search does not cache a missing value as 0 for a later scan',
        () async {
      off.answer = {
        'products': [
          {
            'code': '123', 'product_name': 'Granola',
            'nutriments': {'energy-kcal_100g': 400, 'fat_100g': 0},
          }
        ],
      };
      final found = await NutritionService().searchFoodsOnline('granola');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(found.single.calories, 400);
      final row = (server.writes('foods').single.body as List).single as Map;
      expect(
          (row['calories_per_100g'], row['protein_per_100g'],
              row['carbs_per_100g'], row['fat_per_100g']),
          (400, null, null, 0));
    });

    test('POSITIVE CONTROL: a whole product, with its real 0', () async {
      off.answer = product({
        'energy-kcal_100g': 0, 'proteins_100g': 1, 'carbohydrates_100g': 2.5,
        'fat_100g': 0,
      });
      expect(await lookup(), {
        'name': 'Granola', 'calories': 0.0, 'protein': 1.0, 'carbs': 2.5,
        'fat': 0.0,
      });
    });

    test('NEGATIVE CONTROL: a product nobody knows is still not found',
        () async {
      off.answer = {'status': 0};
      expect(await lookup(), isNull);
    });
  });
}
