// P0-FL-59e round 4 · one member's calories, macros, targets, meals, water and
// the advice built on them are never drawn for another.
//
// Meals and Nutrition drew `totals.valueOrNull` and `goals.valueOrNull` with no
// owner. Neither provider is disposed, so A's numbers stayed up through B's
// read — and, on Nutrition, after it failed. The rows were judged by nothing
// but PaywallGate, and riverpod 2.6.1 does not notify a refresh in flight that
// becomes the next member's read.
//
// The real screens, with and without the real PaywallGate; real auth
// transitions; no AccountScope.
//
// HOW TO SEE IT FAIL: put back e0736a6's nutrition_provider, nutrition_screen,
// meals_dashboard_screen and action_item_provider + action_center_screen (they
// share `readForMember`). Only the controls marked "(old too)" and "A signed
// out" pass there.
import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/nutrition/domain/nutrition_provider.dart';
import 'package:circle_fitness/features/nutrition/presentation/meals_dashboard_screen.dart';
import 'package:circle_fitness/features/nutrition/presentation/nutrition_screen.dart';
import 'package:circle_fitness/features/payments/domain/entitlements.dart';
import 'package:circle_fitness/features/payments/presentation/paywall_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/member_switch_server.dart';

const _failed = "Couldn't load today's totals";
const _kept = 'Try again in a moment. If it keeps happening, contact support. '
    'Showing what was last loaded.';

void main() {
  final server = MemberSwitchServer();
  final reported = <AppFailure>[];
  late ProviderContainer container;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(server);
    watchAuthChanges();
  });

  /// A: 777 kcal, 33 g of 161 g protein. B: 444 kcal, 22 g of 99 g.
  setUp(() async {
    server.reset();
    await signInAs(memberA);
    reported.clear();
    setFailureSink(reported.add);
    Map<String, Object?> meal(String who, String food, int kcal, int protein) =>
        {
          'id': 'meal-$food', 'user_id': who, 'meal_type': 'breakfast',
          'food_name': food, 'calories': kcal, 'protein': protein, 'carbs': 7,
          'fat': 3, 'amount_g': 100, 'serving_unit': 'g',
          'logged_at': DateTime.now().toUtc().toIso8601String(),
        };
    Map<String, Object?> plan(int kcal, int protein) => {
          'calories_target': kcal, 'protein_g': protein, 'carbs_g': 188,
          'fat_g': 66,
        };
    server.rows.addAll({
      'user_profiles': {
        for (final m in [memberA, memberB])
          m: [{'id': m, 'role': 'client', 'first_name': 'F', 'last_name': 'L'}],
      },
      'nutrition_logs': {
        memberA: [meal(memberA, 'Porridge', 777, 33)],
        memberB: [meal(memberB, 'Kedgeree', 444, 22)],
      },
      'client_nutrition_plans': {
        memberA: [plan(1511, 161)],
        memberB: [plan(2222, 99)],
      },
    });
  });
  tearDown(resetFailureSink);

  Iterable<String> origins() => reported.map((f) => f.origin);

  Future<void> settle(WidgetTester t, [int n = 10]) async {
    for (var i = 0; i < n; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> noFrame(WidgetTester t) => t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)));

  Future<void> switchTo(WidgetTester t, String uid) =>
      t.runAsync(() => signInAs(uid));

  Future<void> mount(WidgetTester t, Widget screen, {bool gate = true}) async {
    await t.binding.setSurfaceSize(const Size(900, 3000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    container = ProviderContainer(overrides: [
      clientPlanProvider.overrideWith((ref) async => ClientPlan.selfGuided),
    ]);
    addTearDown(container.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: gate
                ? PaywallGate(
                    required: ClientPlan.selfGuided,
                    featureName: 'Nutrition Tracking',
                    child: screen)
                : screen)));
    await settle(t);
  }

  Future<void> open(WidgetTester t, Widget screen, {bool gate = true}) async {
    await mount(t, screen, gate: gate);
    expect(find.textContaining('777'), findsWidgets, reason: 'premise');
    expect(find.textContaining('161g'), findsWidgets, reason: 'premise');
    expect(find.text('Porridge'), findsOneWidget, reason: 'premise');
    expect(find.textContaining('still need 128g'), findsOneWidget,
        reason: 'premise');
    server.seen.clear();
    reported.clear();
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 12));
  }

  void nothingOfA() {
    expect(find.textContaining('777'), findsNothing, reason: "A's calories");
    expect(find.textContaining('161'), findsNothing, reason: "A's target");
    expect(find.textContaining('1511'), findsNothing, reason: "A's target");
    expect(find.textContaining('33'), findsNothing, reason: "A's protein");
    expect(find.textContaining('128g'), findsNothing,
        reason: "advice built on A's numbers");
    expect(find.text('Porridge'), findsNothing, reason: "A's meal");
  }

  /// Nobody's numbers: not zeros, not the defaults, no advice.
  void noNumbers() {
    nothingOfA();
    expect(find.textContaining('still need'), findsNothing);
    expect(find.textContaining('2000'), findsNothing);
    expect(find.textContaining('0/'), findsNothing);
    expect(find.text('0'), findsNothing);
  }

  void bsOwn() {
    nothingOfA();
    expect(find.textContaining('444'), findsWidgets);
    expect(find.textContaining('99g'), findsWidgets);
    expect(find.text('Kedgeree'), findsOneWidget);
    expect(find.textContaining('Couldn\'t load'), findsNothing);
  }

  Completer<void> holdAll(String uid) {
    final hold = Completer<void>();
    server.holds['GET nutrition_logs:$uid'] = hold;
    server.holds['GET client_nutrition_plans:$uid'] = hold;
    return hold;
  }

  void invalidateBoth() {
    container.invalidate(todayNutritionProvider);
    container.invalidate(nutritionGoalsProvider);
  }

  for (final (name, screen) in [
    ('Meals', const MealsDashboardScreen()),
    ('Nutrition', const NutritionScreen()),
  ]) {
    for (final gate in [true, false]) {
      final where = gate ? 'through PaywallGate' : 'no gate';

      testWidgets("$name, $where: B's reads pending: nothing of A's, and no "
          "invented numbers; then B's own", (t) async {
        await open(t, screen, gate: gate);
        final hold = holdAll(memberB);
        await switchTo(t, memberB);
        await settle(t);
        noNumbers();
        expect(find.byType(CircularProgressIndicator), findsWidgets);
        hold.complete();
        await settle(t);
        bsOwn();
        await close(t);
      });

      testWidgets("$name, $where: B's reads failed: said, nothing of A's; Try "
          "again reads B's own", (t) async {
        await open(t, screen, gate: gate);
        server.fails.addAll([
          'GET nutrition_logs:$memberB',
          'GET client_nutrition_plans:$memberB',
        ]);
        await switchTo(t, memberB);
        await settle(t);
        noNumbers();
        expect(find.text(name == 'Meals' ? "Couldn't load today" : _failed),
            findsOneWidget);
        expect(find.textContaining('last loaded'), findsNothing,
            reason: 'nothing of theirs was');
        expect(find.text('No breakfasts logged'), findsNothing);
        expect(find.text('No meals logged yet'), findsNothing);
        server.fails.clear();
        while (find.text('Try again').evaluate().isNotEmpty) {
          await t.tap(find.text('Try again').first);
          await settle(t);
        }
        bsOwn();
        await close(t);
      });

      for (final (state, frames) in [
        ('frames pumped', true),
        ('no frame', false),
      ]) {
        testWidgets("$name, $where: A's refresh in flight at the switch, "
            "$state, B pending: nothing of A's; nor when A's answer lands",
            (t) async {
          await open(t, screen, gate: gate);
          final holdA = holdAll(memberA);
          final holdB = holdAll(memberB);
          invalidateBoth();
          if (frames) {
            await settle(t, 4);
            expect(find.textContaining('777'), findsWidgets,
                reason: 'a refresh keeps the numbers up');
            expect(server.reads('nutrition_logs', memberA), hasLength(1),
                reason: 'premise');
          } else {
            // The read goes out with no frame, too.
            unawaited(container.read(todayNutritionProvider.future).then(
                (_) {}, onError: (_) {}));
            await noFrame(t);
          }
          await switchTo(t, memberB);
          await settle(t);
          noNumbers();
          holdA.complete();
          await settle(t);
          noNumbers();
          holdB.complete();
          await settle(t);
          bsOwn();
          await close(t);
        });
      }

      testWidgets("$name, $where: invalidated before the switch is flushed, B "
          "pending, then failed: nothing of A's, and the failure is said",
          (t) async {
        await open(t, screen, gate: gate);
        final hold = holdAll(memberB);
        server.fails.add('GET nutrition_logs:$memberB');
        await switchTo(t, memberB);
        invalidateBoth();
        await settle(t);
        // The premise: riverpod carries A's.
        expect(container.read(todayNutritionProvider).hasValue, isTrue,
            reason: 'premise');
        noNumbers();
        hold.complete();
        await settle(t);
        noNumbers();
        expect(find.text(name == 'Meals' ? "Couldn't load today" : _failed),
            findsOneWidget);
        await close(t);
      });

      testWidgets("$name, $where: A signed out: nothing of A's", (t) async {
        await open(t, screen, gate: gate);
        await t.runAsync(signOut);
        await settle(t);
        nothingOfA();
        await close(t);
      });

      testWidgets("$name, $where: POSITIVE CONTROL (old too): B's own, then "
          "A's own when A comes back", (t) async {
        await open(t, screen, gate: gate);
        await switchTo(t, memberB);
        await settle(t);
        bsOwn();
        await switchTo(t, memberA);
        await settle(t);
        expect(find.textContaining('777'), findsWidgets);
        expect(find.textContaining('161g'), findsWidgets);
        expect(find.text('Kedgeree'), findsNothing);
        await close(t);
      });

      testWidgets("$name, $where: a token refresh of the same member keeps the "
          'numbers up and reads nothing again', (t) async {
        await open(t, screen, gate: gate);
        holdAll(memberA);
        await t.runAsync(refreshSession);
        await t.pump();
        for (var i = 0; i < 6; i++) {
          expect(find.textContaining('777'), findsWidgets);
          expect(find.textContaining('161g'), findsWidgets);
          expect(find.text('Porridge'), findsOneWidget);
          await settle(t, 1);
        }
        expect(server.reads('nutrition_logs'), isEmpty);
        expect(server.reads('client_nutrition_plans'), isEmpty);
        await close(t);
      });

      testWidgets("$name, $where: the same member's refresh that fails keeps "
          'the numbers up and says so; Try again clears it', (t) async {
        await open(t, screen, gate: gate);
        server.fails.addAll([
          'GET nutrition_logs:$memberA',
          'GET client_nutrition_plans:$memberA',
        ]);
        invalidateBoth();
        await settle(t);
        expect(find.textContaining('777'), findsWidgets);
        expect(find.textContaining('161g'), findsWidgets);
        expect(find.text(_failed), findsOneWidget);
        expect(find.text("Couldn't load your targets"), findsOneWidget);
        expect(find.text(_kept), findsNWidgets(2));
        server.fails.clear();
        for (var i = 0; i < 2; i++) {
          await t.tap(find.text('Try again').first);
          await settle(t);
        }
        expect(find.textContaining("Couldn't load"), findsNothing);
        expect(find.textContaining('777'), findsWidgets);
        await close(t);
      });
    }

    testWidgets("$name: the rows: the same member's refresh keeps them up while "
        'it is read; one that fails keeps them, and says so', (t) async {
      await open(t, screen, gate: false);
      Future<void> pull() async {
        await t.drag(find.byType(SingleChildScrollView).first,
            const Offset(0, 600));
        await settle(t);
      }

      final hold = holdAll(memberA);
      await pull();
      expect(server.reads('nutrition_logs', memberA), isNotEmpty,
          reason: 'premise');
      expect(find.text('Porridge'), findsOneWidget);
      expect(find.textContaining('777'), findsWidgets);
      hold.complete();
      await settle(t);
      server.fails.add('GET nutrition_logs:$memberA');
      await pull();
      expect(find.text('Porridge'), findsOneWidget);
      expect(find.text("Couldn't load your meals"), findsOneWidget);
      expect(find.text(_kept), findsNWidgets(2)); // totals and meals
      await close(t);
    });

    testWidgets("$name: the rows: A's refresh in flight at the switch, B "
        "pending: nothing of A's", (t) async {
      await open(t, screen, gate: false);
      final holdA = holdAll(memberA);
      final holdB = holdAll(memberB);
      await t.drag(
          find.byType(SingleChildScrollView).first, const Offset(0, 600));
      await settle(t);
      expect(server.reads('nutrition_logs', memberA), hasLength(2),
          reason: 'premise: totals and rows');
      await switchTo(t, memberB);
      await settle(t);
      noNumbers();
      holdA.complete();
      await settle(t);
      noNumbers();
      holdB.complete();
      await settle(t);
      bsOwn();
      await close(t);
    });

    testWidgets("$name: A -> B -> A with no frame, read as B meanwhile: A's, "
        "never B's, and not left waiting", (t) async {
      await open(t, screen, gate: false);
      await t.runAsync(() => switchAnd(memberB, () {
            invalidateBoth();
            unawaited(container.read(todayNutritionProvider.future));
            unawaited(container.read(nutritionGoalsProvider.future));
          }));
      expect(server.reads('nutrition_logs', memberB), isNotEmpty,
          reason: 'premise');
      await switchTo(t, memberA);
      await t.pump();
      expect(find.textContaining('444'), findsNothing);
      expect(find.textContaining('99g'), findsNothing);
      await settle(t);
      expect(find.textContaining('777'), findsWidgets);
      expect(find.textContaining('161g'), findsWidgets);
      expect(find.text('Porridge'), findsOneWidget);
      await close(t);
    });

    // ── Water: never saved; the count of whoever tapped it ──────────────────
    final first = name == 'Meals' ? '0 / 8' : '3 / 8 glasses';
    final five = name == 'Meals' ? '5 / 8' : '5 / 8 glasses';
    Finder drop(int n) => name == 'Meals'
        ? find.byWidgetPredicate((w) =>
            w is Icon &&
            (w.icon == Icons.water_drop ||
                w.icon == Icons.water_drop_outlined)).at(n - 1)
        : find.byIcon(Icons.water_drop).at(n - 1);

    testWidgets("$name: A's glasses are not B's", (t) async {
      await open(t, screen, gate: false);
      await t.tap(drop(5));
      await settle(t, 2);
      expect(find.text(five), findsOneWidget, reason: 'premise');
      await switchTo(t, memberB);
      await settle(t);
      expect(find.text(five), findsNothing);
      expect(find.text(first), findsOneWidget);
      await close(t);
    });

    testWidgets("$name: A's undrawn glasses tapped once B is signed in: not "
        "counted for B, recorded", (t) async {
      await open(t, screen, gate: false);
      await switchTo(t, memberB);
      await t.tap(drop(5));
      await settle(t);
      expect(find.text(first), findsOneWidget);
      expect(origins(), [
        name == 'Meals'
            ? 'MealsDashboard.water.identity'
            : 'NutritionScreen.water.identity'
      ]);
      await close(t);
    });

    testWidgets("$name: POSITIVE CONTROL (old too): a token refresh keeps the "
        'glasses, and the next tap counts', (t) async {
      await open(t, screen, gate: false);
      await t.tap(drop(5));
      await settle(t, 2);
      await t.runAsync(refreshSession);
      await settle(t);
      expect(find.text(five), findsOneWidget);
      await t.tap(drop(5)); // the last one, untapped
      await settle(t, 2);
      expect(find.text(five), findsNothing);
      expect(find.textContaining('4 / 8'), findsOneWidget);
      expect(reported, isEmpty);
      await close(t);
    });

    testWidgets('$name: NEGATIVE CONTROL (old too): nothing logged and no plan '
        'is still nothing logged and the defaults', (t) async {
      server.rows['nutrition_logs'] = {};
      server.rows['client_nutrition_plans'] = {};
      await mount(t, screen);
      expect(find.textContaining('120g'), findsWidgets);
      expect(find.text('0'), findsOneWidget);
      expect(
          find.text(name == 'Meals'
              ? 'No breakfasts logged'
              : 'No meals logged yet'),
          findsOneWidget);
      expect(find.textContaining("Couldn't load"), findsNothing);
      expect(reported, isEmpty);
      await close(t);
    });

    testWidgets('$name: no plan for A, none for B: the defaults of one are not '
        "the other's answer while B's read is pending", (t) async {
      server.rows['client_nutrition_plans'] = {};
      await mount(t, screen, gate: false);
      expect(find.textContaining('120g'), findsWidgets, reason: 'premise');
      server.holds['GET client_nutrition_plans:$memberB'] = Completer();
      await switchTo(t, memberB);
      await settle(t);
      expect(find.textContaining('120g'), findsNothing);
      expect(find.textContaining('still need'), findsNothing);
      await close(t);
    });
  }
}
