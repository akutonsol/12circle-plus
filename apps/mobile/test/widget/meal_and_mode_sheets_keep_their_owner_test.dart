// P0-FL-59e · W16 / W11: a food picked or scanned, or a coaching mode chosen,
// by one member is never saved for another.
//
// HOW TO SEE IT FAIL: put back a82f993's nutrition_screen, meals_dashboard
// _screen, nutrition_service and settings_screen; every test but the POSITIVE
// CONTROLs fails.
import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/nutrition/presentation/meals_dashboard_screen.dart';
import 'package:circle_fitness/features/nutrition/presentation/nutrition_screen.dart';
import 'package:circle_fitness/features/nutrition/presentation/widgets/ai_scan_view.dart';
import 'package:circle_fitness/features/payments/domain/entitlements.dart';
import 'package:circle_fitness/features/settings/presentation/settings_screen.dart';
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
  });

  setUp(() async {
    server.reset();
    await signInAs(memberA);
    reported.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  Iterable<String> origins() => reported.map((f) => f.origin);
  Iterable<SeenRequest> asB() => server.writes().where((w) => w.who == memberB);

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

  Future<void> switchTo(WidgetTester t, String uid) =>
      t.runAsync(() => signInAs(uid));

  Future<void> size(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(500, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
  }

  group('Log Meal (Meals)', () {
    var logged = 0;

    Future<void> open(WidgetTester t, {String mode = 'manual'}) async {
      logged = 0;
      await size(t);
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
      expect(find.text('Log Meal'), findsOneWidget, reason: 'premise');
      server.seen.clear();
    }

    Future<void> pickFood(WidgetTester t) async {
      await t.tap(find.text('Brown Rice'));
      await settle(t);
      expect(find.text('Log Brown Rice'), findsOneWidget, reason: 'premise');
    }

    const scan = ScanResult(
        name: "A's curry", calories: 500, protein: 20, carbs: 60, fat: 18,
        confidence: 90);

    testWidgets("a food A picked, logged in the undrawn sheet once B is signed "
        'in: no meal for B; the sheet goes', (t) async {
      await open(t);
      await pickFood(t);
      await switchTo(t, memberB);
      await t.tap(find.text('Log Brown Rice'), warnIfMissed: false);
      await settle(t);
      expect(asB(), isEmpty, reason: "A's meal is in B's nutrition_logs");
      expect(find.text('Log Brown Rice'), findsNothing);
      expect(find.text('Could not log meal.'), findsNothing);
      await close(t);
    });

    testWidgets("A's scan result still up, accepted once B is signed in: no "
        'meal for B, recorded', (t) async {
      await open(t, mode: 'ai_scan');
      final accept = t.widget<AiScanView>(find.byType(AiScanView)).onAccept;
      await switchTo(t, memberB);
      accept(scan); // no frame, no auth event delivered yet
      await settle(t);
      expect(asB(), isEmpty);
      expect(origins(), contains('AddMealSheet.identity'));
      expect(find.byType(AiScanView), findsNothing,
          reason: "A's scan is on B's screen");
      await close(t);
    });

    testWidgets("A's custom food sheet goes with A", (t) async {
      await open(t);
      await t.enterText(find.byType(TextField), 'z'); // matches no food
      await settle(t);
      await t.tap(find.textContaining('manually'));
      await settle(t);
      expect(find.text('Add Custom Food'), findsOneWidget, reason: 'premise');
      await switchTo(t, memberB);
      await settle(t);
      expect(find.text('Add Custom Food'), findsNothing);
      expect(find.text('Log Meal'), findsNothing);
      expect(find.text('open'), findsOneWidget, reason: 'the page is still up');
      await close(t);
    });

    testWidgets("A's meal answers after B signed in: no points for B, B is not "
        "shown A's meal", (t) async {
      await open(t);
      await pickFood(t);
      final hold = server.holds['POST nutrition_logs:$memberA'] = Completer();
      await t.tap(find.text('Log Brown Rice'));
      await settle(t, 2);
      await switchTo(t, memberB);
      hold.complete();
      await settle(t);
      expect(server.writes('nutrition_logs').single.row['user_id'], memberA);
      expect(asB(), isEmpty);
      expect(find.textContaining('Brown Rice'), findsNothing);
      expect(logged, 0);
      await close(t);
    });

    testWidgets("A's meal fails after B signed in: recorded, B is not told",
        (t) async {
      await open(t);
      await pickFood(t);
      final hold = server.holds['POST nutrition_logs:$memberA'] = Completer();
      server.fails.add('POST nutrition_logs:$memberA');
      await t.tap(find.text('Log Brown Rice'));
      await settle(t, 2);
      await switchTo(t, memberB);
      hold.complete();
      await settle(t);
      expect(origins(), contains('AddMealSheet._logFood'));
      expect(find.byType(SnackBar), findsNothing);
      await close(t);
    });

    testWidgets('POSITIVE CONTROL: after a token refresh the pick is still '
        'there and is logged for its member', (t) async {
      await open(t);
      await pickFood(t);
      await t.runAsync(refreshSession);
      await settle(t);
      await t.tap(find.text('Log Brown Rice'));
      await settle(t);
      final meal = server.writes('nutrition_logs').single;
      expect((meal.who, meal.row['user_id'], meal.row['food_name']),
          (memberA, memberA, 'Brown Rice'));
      expect(logged, 1);
      expect(reported, isEmpty);
      await close(t);
    });

    testWidgets('POSITIVE CONTROL: a scan is logged for its member', (t) async {
      await open(t, mode: 'ai_scan');
      t.widget<AiScanView>(find.byType(AiScanView)).onAccept(scan);
      await settle(t);
      expect(server.writes('nutrition_logs').single.row['user_id'], memberA);
      await close(t);
    });
  });

  group('Log Meal (Nutrition)', () {
    Future<void> open(WidgetTester t) async {
      await size(t);
      await t.pumpWidget(
          const ProviderScope(child: MaterialApp(home: NutritionScreen())));
      await settle(t);
      await t.tap(find.text('Log Meal'));
      await settle(t);
      await t.tap(find.text('Brown Rice'));
      await settle(t);
      server.seen.clear();
    }

    testWidgets("a food A picked, logged in the undrawn sheet once B is signed "
        'in: no meal for B', (t) async {
      await open(t);
      await switchTo(t, memberB);
      await t.tap(find.text('Log Brown Rice'), warnIfMissed: false);
      await settle(t);
      expect(asB(), isEmpty);
      expect(find.text('Log Brown Rice'), findsNothing);
      await close(t);
    });

    testWidgets("A's meal fails after B signed in: recorded, B is not told",
        (t) async {
      await open(t);
      final hold = server.holds['POST nutrition_logs:$memberA'] = Completer();
      server.fails.add('POST nutrition_logs:$memberA');
      await t.tap(find.text('Log Brown Rice'));
      await settle(t, 2);
      await switchTo(t, memberB);
      hold.complete();
      await settle(t);
      expect(origins(), contains('NutritionScreen.addMeal._log'));
      expect(find.byType(SnackBar), findsNothing);
      expect(asB(), isEmpty);
      await close(t);
    });

    testWidgets('POSITIVE CONTROL: logged for its member', (t) async {
      await open(t);
      await t.tap(find.text('Log Brown Rice'));
      await settle(t);
      expect(server.writes('nutrition_logs').single.row['user_id'], memberA);
      await close(t);
    });
  });

  group('Coaching mode sheet', () {
    Future<void> open(WidgetTester t, {bool coach = false}) async {
      Map<String, Object?> me(String id, String name) => {
            'id': id, 'role': 'client', 'first_name': name, 'last_name': 'Lee',
            'coaching_mode': 'coach_guided',
          };
      server.rows.addAll({
        'user_profiles': {
          memberA: [me(memberA, 'Ana')],
          memberB: [me(memberB, 'Ben')],
        },
        if (coach)
          'coach_client_relationships': {
            for (final m in [memberA, memberB])
              m: [{'id': 'rel-$m', 'coach_id': 'coach-a', 'status': 'active'}],
          },
        'public_profiles': {
          for (final m in [memberA, memberB])
            m: [{'id': 'coach-a', 'first_name': 'Avery', 'last_name': 'Stone'}],
        },
      });
      await t.binding.setSurfaceSize(const Size(500, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(ProviderScope(
        overrides: [
          clientPlanProvider.overrideWith((ref) async => ClientPlan.coachGuided),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ));
      await settle(t);
      await t.tap(find.text('Coach Guided'));
      await settle(t);
      await t.tap(find.text('Self Guided'));
      await settle(t);
      server.seen.clear();
    }

    Iterable<SeenRequest> modeWrites() => server
        .writes('user_profiles')
        .where((w) => '${w.body}'.contains('coaching_mode'));

    testWidgets("Apply tapped in A's undrawn sheet once B is signed in: B's "
        'mode and plan are not touched; the sheet goes', (t) async {
      await open(t);
      await switchTo(t, memberB);
      await t.tap(find.text('Apply'), warnIfMissed: false);
      await settle(t);
      expect(asB(), isEmpty);
      expect(find.text('Apply'), findsNothing);
      await close(t);
    });

    testWidgets("A's mode answers after B signed in: B's plan is not rebuilt",
        (t) async {
      await open(t);
      final hold = server.holds['PATCH user_profiles:$memberA'] = Completer();
      await t.tap(find.text('Apply'));
      await settle(t, 3);
      expect(modeWrites(), hasLength(1), reason: 'premise');
      await switchTo(t, memberB);
      hold.complete();
      await settle(t);
      expect(modeWrites().single.query['id'], 'eq.$memberA');
      expect(asB(), isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      await close(t);
    });

    testWidgets("the dialog naming A's coach goes with A; confirmed before it "
        "is redrawn, B's coaching is not ended", (t) async {
      await open(t, coach: true);
      await t.tap(find.text('Apply'));
      await settle(t);
      expect(find.text('End coaching with Coach Avery Stone?'), findsOneWidget,
          reason: 'premise');
      await switchTo(t, memberB);
      await t.tap(find.text('End & switch'), warnIfMissed: false);
      await settle(t);
      expect(asB(), isEmpty);
      expect(find.textContaining('End coaching with'), findsNothing);
      expect(find.text('Apply'), findsNothing);
      await close(t);
    });

    testWidgets('B signs in while the coaching is being ended: the mode does '
        'not follow as B', (t) async {
      await open(t, coach: true);
      final hold =
          server.holds['PATCH coach_client_relationships:$memberA'] = Completer();
      await t.tap(find.text('Apply'));
      await settle(t);
      await t.tap(find.text('End & switch'));
      await settle(t, 3);
      await switchTo(t, memberB);
      hold.complete();
      await settle(t);
      expect(modeWrites(), isEmpty);
      expect(find.text('Could not save coaching mode.'), findsNothing);
      await close(t);
    });

    testWidgets('signed out with the sheet open: nothing is sent', (t) async {
      await open(t);
      await t.runAsync(signOut);
      await t.tap(find.text('Apply'), warnIfMissed: false);
      await settle(t);
      expect(server.writes(), isEmpty);
      expect(find.text('Apply'), findsNothing);
      await close(t);
    });

    testWidgets("POSITIVE CONTROL: a token refresh keeps the sheet; Apply saves "
        "its member's mode and syncs their plan", (t) async {
      await open(t);
      await t.runAsync(refreshSession);
      await settle(t);
      await t.tap(find.text('Apply'));
      await settle(t);
      expect(modeWrites().single.query['id'], 'eq.$memberA');
      expect(server.writes('generate_client_plan').single.who, memberA);
      expect(find.text('Apply'), findsNothing);
      await close(t);
    });
  });
}
