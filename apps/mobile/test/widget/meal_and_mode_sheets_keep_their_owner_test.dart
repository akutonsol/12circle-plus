// P0-FL-59e · W16 / W11: a food picked or scanned, or a coaching mode chosen,
// by one member is never saved for another.
//
// HOW TO SEE IT FAIL: put back a82f993's nutrition_screen, meals_dashboard
// _screen, nutrition_service, food_added_dialog and settings_screen; every test
// fails but the POSITIVE CONTROLs, "signed out with the sheet open" (signed
// out, the notifier itself sends nothing) and, in the dialog group, the
// "answers after" ones. The "Food Added!" group, the dialog "switched before it
// is drawn", the swiped-away sheet and the food search fail on 5f8b7f3 too.
import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/coach/domain/coach_provider.dart';
import 'package:circle_fitness/features/nutrition/presentation/meals_dashboard_screen.dart';
import 'package:circle_fitness/features/nutrition/presentation/nutrition_screen.dart';
import 'package:circle_fitness/features/nutrition/presentation/widgets/ai_scan_view.dart';
import 'package:circle_fitness/features/nutrition/presentation/widgets/barcode_scan_view.dart';
import 'package:circle_fitness/features/payments/domain/entitlements.dart';
import 'package:circle_fitness/features/settings/presentation/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/member_switch_server.dart';

/// Whether a dialog has been pushed, before any frame draws it.
class _Dialogs extends NavigatorObserver {
  int pushed = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is DialogRoute) pushed++;
  }
}

void main() {
  final dialogs = _Dialogs();
  final server = MemberSwitchServer();
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // No camera here: the scanner view says so and stays up.
    const scanner = 'dev.steenbakker.mobile_scanner/scanner';
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('$scanner/method'),
        (call) async => switch (call.method) {
              'state' => 2, // denied
              'request' => false,
              _ => null,
            });
    for (final name in ['event', 'deviceOrientation']) {
      messenger.setMockMethodCallHandler(
          MethodChannel('$scanner/$name'), (call) async => null);
    }
    await initTwoMemberSupabase(server);
  });

  setUp(() async {
    server.reset();
    dialogs.pushed = 0;
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
          navigatorObservers: [dialogs],
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

    testWidgets("A's barcode food, found once B is signed in: no meal for B; "
        'refused at the sheet, recorded', (t) async {
      await open(t, mode: 'barcode');
      final found =
          t.widget<BarcodeScanView>(find.byType(BarcodeScanView)).onFound;
      await switchTo(t, memberB);
      found({'name': "A's bar", 'calories': 100.0});
      await settle(t);
      expect(asB(), isEmpty);
      expect(server.writes(), isEmpty);
      expect(origins(), ['AddMealSheet.identity'],
          reason: 'it went on to the service');
      expect(find.byType(BarcodeScanView), findsNothing);
      await close(t);
    });

    testWidgets("A's custom food, saved in its undrawn sheet once B is signed "
        'in: kept by nobody, and the page is still up', (t) async {
      await open(t);
      await t.enterText(find.byType(TextField), 'z'); // matches no food
      await settle(t);
      await t.tap(find.textContaining('manually'));
      await settle(t);
      await t.enterText(find.byType(TextField).at(1), "A's stew");
      await t.pump();
      final save = t
          .widget<GestureDetector>(find.ancestor(
              of: find.text('Add to List'),
              matching: find.byType(GestureDetector)).first)
          .onTap!;
      await switchTo(t, memberB);
      save(); // (the navigator absorbs taps until the routes are redrawn)
      await settle(t);
      expect(find.textContaining("A's stew"), findsNothing);
      expect(find.text('open'), findsOneWidget);
      expect(origins(), contains('AddMealSheet.identity'));
      expect(server.writes(), isEmpty);
      await close(t);
    });

    testWidgets('POSITIVE CONTROL: a custom food is on its member\'s list and '
        'is logged for them', (t) async {
      await open(t);
      await t.enterText(find.byType(TextField), 'z');
      await settle(t);
      await t.tap(find.textContaining('manually'));
      await settle(t);
      await t.enterText(find.byType(TextField).at(1), 'Stew');
      await t.tap(find.text('Add to List'));
      await settle(t);
      expect(find.text('Log Meal'), findsOneWidget);
      await t.enterText(find.byType(TextField), 'Stew');
      await settle(t);
      await t.tap(find.text('Stew').last);
      await settle(t);
      await t.tap(find.text('Log Stew'));
      await settle(t);
      expect(server.writes('nutrition_logs').single.row['food_name'], 'Stew');
      await close(t);
    });

    testWidgets("what A typed in the food search is not searched for as B",
        (t) async {
      await open(t);
      await t.enterText(find.byType(TextField), 'low FODMAP');
      await t.pump(const Duration(milliseconds: 100));
      await switchTo(t, memberB);
      // The debounce comes due before the next frame, as in a hidden tab.
      await t.pump(const Duration(milliseconds: 400));
      await settle(t);
      expect(server.seen.where((r) => '${r.query}'.contains('FODMAP')), isEmpty,
          reason: '${server.seen.toList()}');
      await close(t);
    });

    testWidgets('POSITIVE CONTROL: after a token refresh the search is sent as '
        'its member', (t) async {
      await open(t);
      await t.enterText(find.byType(TextField), 'low FODMAP');
      await t.pump(const Duration(milliseconds: 100));
      await t.runAsync(refreshSession);
      await t.pump(const Duration(milliseconds: 400));
      await settle(t);
      expect(
          server.reads('foods').where((r) => '${r.query}'.contains('FODMAP'))
              .map((r) => r.who),
          [memberA]);
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
      expect(find.byType(SnackBar), findsNothing);
      expect(origins(), contains('AddMealSheet._logFood'));
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

    group('"Food Added!"', () {
      /// Logs a meal by [path] up to (not through) its save's answer.
      Future<Completer<void>> log(WidgetTester t, String path) async {
        await open(t, mode: path);
        final hold =
            server.holds['POST nutrition_logs:$memberA'] = Completer<void>();
        switch (path) {
          case 'manual':
            await pickFood(t);
            await t.tap(find.text('Log Brown Rice'));
          case 'ai_scan':
            t.widget<AiScanView>(find.byType(AiScanView)).onAccept(scan);
          default:
            t
                .widget<BarcodeScanView>(find.byType(BarcodeScanView))
                // A whole product: one with a value missing is not logged.
                .onFound({
              'name': "A's curry", 'calories': 1.0, 'protein': 0.0,
              'carbs': 0.0, 'fat': 0.0,
            });
        }
        await settle(t, 2);
        return hold;
      }

      for (final path in ['manual', 'ai_scan', 'barcode']) {
        for (final signedOut in [false, true]) {
          final who = signedOut ? 'signed out' : 'B signed in';
          testWidgets('$path: up, then $who: it goes', (t) async {
            final hold = await log(t, path);
            hold.complete();
            await settle(t);
            expect(find.text('Food Added!'), findsOneWidget, reason: 'premise');
            await t.runAsync(() => signedOut ? signOut() : signInAs(memberB));
            await settle(t);
            expect(find.text('Food Added!'), findsNothing);
            expect(find.textContaining('diet schedule'), findsNothing);
            expect(find.text('open'), findsOneWidget);
            await close(t);
          });

          testWidgets('$path: pushed, then $who before its first frame: never '
              'drawn, and nothing is left over the page', (t) async {
            final hold = await log(t, path);
            await t.runAsync(() async {
              hold.complete();
              final clock = Stopwatch()..start();
              while (dialogs.pushed == 0 &&
                  clock.elapsed < const Duration(seconds: 5)) {
                await Future<void>.delayed(const Duration(milliseconds: 5));
              }
              expect(dialogs.pushed, 1, reason: 'premise');
              await (signedOut ? signOut() : signInAs(memberB));
            });
            await t.pump();
            expect(find.text('Food Added!'), findsNothing);
            await settle(t);
            expect(find.text('Food Added!'), findsNothing);
            expect(find.byType(ModalBarrier), findsOneWidget,
                reason: 'only the page');
            await close(t);
          });
        }
      }

      testWidgets('POSITIVE CONTROL: a token refresh keeps it; "Great, thanks!" '
          'closes it', (t) async {
        final hold = await log(t, 'ai_scan');
        hold.complete();
        await settle(t);
        await t.runAsync(refreshSession);
        await settle(t);
        expect(find.text('Food Added!'), findsOneWidget);
        await t.tap(find.text('Great, thanks!'));
        await settle(t);
        expect(find.text('Food Added!'), findsNothing);
        await close(t);
      });
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
          ProviderScope(child: MaterialApp(
              navigatorObservers: [dialogs], home: const NutritionScreen())));
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
      expect(find.byType(SnackBar), findsNothing);
      expect(asB(), isEmpty);
      expect(origins(), contains('NutritionScreen.addMeal._log'));
      await close(t);
    });

    for (final signedOut in [false, true]) {
      final who = signedOut ? 'signed out' : 'B signed in';
      testWidgets('"Food Added!" up, then $who: it goes', (t) async {
        await open(t);
        await t.tap(find.text('Log Brown Rice'));
        await settle(t);
        expect(find.text('Food Added!'), findsOneWidget, reason: 'premise');
        await t.runAsync(() => signedOut ? signOut() : signInAs(memberB));
        await settle(t);
        expect(find.text('Food Added!'), findsNothing);
        expect(find.textContaining('diet schedule'), findsNothing);
        await close(t);
      });

      testWidgets('"Food Added!" pushed, then $who before its first frame: '
          'never drawn', (t) async {
        await open(t);
        final hold =
            server.holds['POST nutrition_logs:$memberA'] = Completer<void>();
        await t.tap(find.text('Log Brown Rice'));
        await settle(t, 2);
        await t.runAsync(() async {
          hold.complete();
          final clock = Stopwatch()..start();
          while (dialogs.pushed == 0 &&
              clock.elapsed < const Duration(seconds: 5)) {
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          expect(dialogs.pushed, 1, reason: 'premise');
          await (signedOut ? signOut() : signInAs(memberB));
        });
        await t.pump();
        expect(find.text('Food Added!'), findsNothing);
        await settle(t);
        expect(find.byType(ModalBarrier), findsOneWidget);
        await close(t);
      });
    }

    testWidgets('POSITIVE CONTROL: logged for its member', (t) async {
      await open(t);
      await t.tap(find.text('Log Brown Rice'));
      await settle(t);
      expect(server.writes('nutrition_logs').single.row['user_id'], memberA);
      await close(t);
    });
  });

  group('Coaching mode sheet', () {
    Future<void> open(WidgetTester t,
        {bool coach = false, List<String> coaches = const ['coach-a']}) async {
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
              m: [
                for (final c in coaches)
                  {'id': 'rel-$c', 'coach_id': c, 'status': 'active'},
              ],
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
        child: MaterialApp(
          home: const SettingsScreen(),
          // Profile, further down the real stack, lists the coaches.
          builder: (_, child) => Consumer(builder: (_, ref, __) {
            ref.watch(myCoachesProvider);
            return child!;
          }),
        ),
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

    for (final fails in [false, true]) {
      testWidgets(
          'same member, the sheet swiped away while the coaching is ended'
          '${fails ? ' (and it fails)' : ''}: the coaches are read again once',
          (t) async {
        await open(t, coach: true);
        final key = 'PATCH coach_client_relationships:$memberA';
        final hold = server.holds[key] = Completer();
        if (fails) server.fails.add(key);
        await t.tap(find.text('Apply'));
        await settle(t);
        await t.tap(find.text('End & switch'));
        await settle(t, 4);
        expect(server.writes('coach_client_relationships'), hasLength(1),
            reason: 'premise');
        t.state<NavigatorState>(find.byType(Navigator).first).pop();
        await settle(t);
        expect(find.text('Apply'), findsNothing, reason: 'premise');
        server.seen.clear();
        hold.complete();
        await settle(t);
        expect(
            server.reads('coach_client_relationships', memberA).where(
                (r) => '${r.query['select']}'.contains('monthly_price')),
            hasLength(1),
            reason: 'the ended coach is still listed');
        expect(asB(), isEmpty);
        await close(t);
      });
    }

    testWidgets("A's coaching could not be ended, B signed in meanwhile: "
        'recorded, B is not told', (t) async {
      await open(t, coach: true);
      final key = 'PATCH coach_client_relationships:$memberA';
      final hold = server.holds[key] = Completer();
      server.fails.add(key);
      await t.tap(find.text('Apply'));
      await settle(t);
      await t.tap(find.text('End & switch'));
      await settle(t, 4);
      await switchTo(t, memberB);
      hold.complete();
      await settle(t);
      expect(find.byType(SnackBar), findsNothing);
      expect(asB(), isEmpty);
      expect(origins(), contains('CoachingModeSheet.apply.cancelCoach'));
      await close(t);
    });

    testWidgets("the dialog naming A's coach, switched before it is drawn: "
        'never drawn for B, and it goes', (t) async {
      await open(t, coach: true);
      await t.tap(find.text('Apply'));
      await t.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await signInAs(memberB);
      });
      await t.pump();
      expect(find.textContaining('End coaching with'), findsNothing);
      await settle(t);
      expect(find.text('Apply'), findsNothing);
      expect(find.byType(ModalBarrier), findsOneWidget);
      expect(asB(), isEmpty);
      await close(t);
    });

    testWidgets('two coaches, B signs in after the first is ended: the second '
        'is not ended as B', (t) async {
      await open(t, coach: true, coaches: ['coach-a', 'coach-c']);
      final hold =
          server.holds['PATCH coach_client_relationships:$memberA'] = Completer();
      await t.tap(find.text('Apply'));
      await settle(t);
      await t.tap(find.text('End & switch'));
      await settle(t, 4);
      await switchTo(t, memberB);
      hold.complete();
      await settle(t);
      expect(server.writes('coach_client_relationships'), hasLength(1));
      expect(
          server.seen.where((r) =>
              r.who == memberB &&
              r.target == 'subscriptions' &&
              '${r.query}'.contains('coach-c')),
          isEmpty, reason: "the second coach was looked up to be ended as B");
      expect(modeWrites(), isEmpty);
      // (The first coach's "ended coaching" notification is sent inside
      // cancelCoach: coach_relationship_service, P0-FL-59d.)
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
