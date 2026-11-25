import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/core/realtime/realtime.dart';
import 'package:circle_fitness/features/activity/presentation/activity_screen.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/challenges/domain/challenge_provider.dart';
import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart';
import 'package:circle_fitness/features/coach/domain/coach_provider.dart';
import 'package:circle_fitness/features/community/domain/community_provider.dart';
import 'package:circle_fitness/features/nutrition/domain/nutrition_provider.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/activity_server.dart';
import '../support/fit_matrix.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-60b round 4 · Activity's calories card and macros grid read today's
// totals with `valueOrNull`: A's kcal and macros were drawn as B's while B's
// read was pending, and for good after it failed; a refresh in flight at the
// switch, or an invalidate before the flush, carried them the same way. And
// B's first read, pending, read "0 kcal" — a claim, not "not loaded".
//
// A real auth client and real transitions (no AccountScope). The totals read
// is replaced, keyed each way it can follow the sign-in ([_Key]): today's
// provider watches the whole User; by uid is the ruled pattern.
//
// HOW TO SEE IT FAIL: `git checkout 1ead31b -- apps/mobile/lib/features/
// activity/presentation/activity_screen.dart`; the CONTROLs pass there, except
// where one says otherwise.

enum _Key { uid, user }

var _key = _Key.user;

String? _signedIn(Ref ref) => _key == _Key.uid
    ? ref.watch(currentUserProvider.select((u) => u?.id))
    : ref.watch(currentUserProvider)?.id;

const _aTotals = {'calories': 1840.0, 'protein': 132.0, 'carbs': 201.0, 'fat': 61.0};
const _bTotals = {'calories': 950.0, 'protein': 40.0, 'carbs': 120.0, 'fat': 30.0};

class _Today {
  final answers = <String, Map<String, double>>{
    memberA: _aTotals,
    memberB: _bTotals,
    'nobody': const {},
  };
  final holds = <String, Completer<void>>{};
  final fails = <String>{};
  var reads = 0;

  Future<Map<String, double>> call(Ref ref) async {
    final uid = _signedIn(ref) ?? 'nobody';
    reads++;
    final hold = holds[uid];
    if (hold != null) await hold.future;
    if (fails.contains(uid)) throw StateError('SECRET totals read');
    return answers[uid]!;
  }

  void release() {
    for (final h in holds.values) {
      if (!h.isCompleted) h.complete();
    }
  }
}

void main() {
  late ActivityServer server;
  late _Today today;
  final reported = <AppFailure>[];

  // A's figures, anywhere on the screen.
  final aCalories = find.text('1840');
  final aCaloriesCell = find.text('1840 kcal');
  final aProtein = find.text('132g');
  final bCalories = find.text('950');
  final bProtein = find.text('40g');
  // The steps card draws its own dash; these are the totals' only.
  late final dash = find.bySemanticsLabel(RegExp(r"^Today's \w+ not loaded$"));
  final zero = find.text('0 kcal');
  const failedTitle = "Couldn't load today's nutrition";
  final notice = find.text(failedTitle);

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = ActivityServer();
    await initTwoMemberSupabase(server);
  });

  setUp(() async {
    server.reset();
    today = _Today();
    _key = _Key.user;
    reported.clear();
    setFailureSink(reported.add);
    await signInAs(memberA);
  });
  tearDown(resetFailureSink);

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 8; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<ProviderContainer> show(WidgetTester t,
      {num width = 430, double scale = 1}) async {
    fitWindow(t, width, 9000, scale);
    t.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final c = ProviderContainer(overrides: [
      currentFirstNameProvider.overrideWithValue('Sam'),
      confirmedCurrentProfileProvider.overrideWithValue(null),
      tableTickerProvider.overrideWith((ref, table) => Stream.value(0)),
      liveGroupsProvider.overrideWith((ref) async => const []),
      assignedCoachProvider.overrideWith((ref) async => null),
      todayNutritionProvider.overrideWith((ref) => today(ref)),
      monthScoresProvider.overrideWith((ref) async => const []),
      weekScoresProvider.overrideWith((ref) async => const []),
      assignedWorkoutsProvider.overrideWith((ref) async => const []),
      liveChallengesProvider.overrideWith((ref) async => const []),
    ]);
    addTearDown(c.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
        container: c, child: const MaterialApp(home: ActivityScreen())));
    await settle(t);
    return c;
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
  }

  /// The transition is delivered on the real auth stream; NO frame runs.
  Future<void> hear(WidgetTester t, Future<void> Function() transition) async {
    final heard = <AuthChangeEvent>[];
    await t.runAsync(() async {
      final sub = Supabase.instance.client.auth.onAuthStateChange
          .skip(1)
          .listen((s) => heard.add(s.event));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await transition();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await sub.cancel();
    });
    expect(heard, isNotEmpty, reason: 'premise: the event arrived');
  }

  Future<void> switchTo(WidgetTester t, String? uid) =>
      hear(t, () => uid == null ? signOut() : signInAs(uid));

  void expectNothingOfA(String why) {
    expect(aCalories, findsNothing, reason: why);
    expect(aCaloriesCell, findsNothing, reason: why);
    expect(aProtein, findsNothing, reason: why);
  }

  /// Unknown: dashes in the card and the four cells, never "0 kcal".
  void expectUnknown() {
    expect(dash, findsNWidgets(5), reason: 'card + four cells, not loaded');
    expect(find.text('—'), findsNWidgets(6), reason: 'drawn as dashes (+ steps)');
    expect(zero, findsNothing, reason: 'unknown is not 0');
    expect(find.bySemanticsLabel("Today's calories not loaded"),
        findsNWidgets(2));
    expect(find.bySemanticsLabel("Today's protein not loaded"),
        findsOneWidget);
  }

  Future<ProviderContainer> asA(WidgetTester t) async {
    final c = await show(t);
    expect(aCalories, findsOneWidget, reason: "premise: A's own totals");
    expect(aProtein, findsOneWidget);
    return c;
  }

  /// Ways A's value is carried into B's read; on return B is signed in and no
  /// frame has run since the switch.
  final around = <String,
      Future<void> Function(WidgetTester, ProviderContainer)>{
    'B signs in': (t, c) async {
      today.holds[memberB] = Completer<void>();
      await switchTo(t, memberB);
    },
    'invalidated, then B signs in before the flush': (t, c) async {
      today.holds[memberB] = Completer<void>();
      c.invalidate(todayNutritionProvider);
      await switchTo(t, memberB);
    },
    'B signs in, then invalidated before the flush': (t, c) async {
      today.holds[memberB] = Completer<void>();
      await switchTo(t, memberB);
      c.invalidate(todayNutritionProvider);
    },
    "A's refresh in flight, then B signs in": (t, c) async {
      today.holds[memberB] = Completer<void>();
      today.holds[memberA] = Completer<void>();
      c.invalidate(todayNutritionProvider);
      await settle(t);
      await switchTo(t, memberB);
    },
  };

  for (final key in _Key.values) {
    for (final way in around.entries) {
      testWidgets('${way.key} (by ${key.name}), B pending: no A totals from the '
          'first frame, a dash not 0; then B\'s own', (t) async {
        _key = key;
        final c = await asA(t);
        await way.value(t, c);
        await t.pump();
        expectNothingOfA("THE defect: A's totals as B's");
        await settle(t);
        expectNothingOfA("THE defect: A's totals as B's");
        expectUnknown();
        expect(notice, findsNothing, reason: 'pending is not a failure');
        today.release();
        await settle(t);
        expect(bCalories, findsOneWidget);
        expect(bProtein, findsOneWidget);
        expect(dash, findsNothing);
        await close(t);
      });

      testWidgets('${way.key} (by ${key.name}), B failed: said once, nothing of A '
          'under it nor while B retries; then B\'s own', (t) async {
        _key = key;
        today.fails.add(memberB);
        final c = await asA(t);
        await way.value(t, c);
        await t.pump();
        expectNothingOfA("THE defect: A's totals as B's");
        today.release();
        await settle(t);
        expectNothingOfA("THE defect: A's totals kept as B's");
        expectUnknown();
        expect(notice, findsOneWidget, reason: 'said once, on the macros');
        expect(find.textContaining('SECRET'), findsNothing);
        expect(find.text("Couldn't load today's nutrition"), findsOneWidget);
        // Busy-aware retry.
        today.holds
          ..clear()
          ..[memberB] = Completer<void>();
        today.fails.clear();
        await t.tap(find.text('Try again'));
        await settle(t);
        expect(find.bySemanticsLabel('Retrying'), findsOneWidget);
        expectNothingOfA('nor while B retries');
        today.release();
        await settle(t);
        expect(notice, findsNothing);
        expect(bCalories, findsOneWidget);
        await close(t);
      });

      testWidgets("${way.key} (by ${key.name}): A's failure is not B's",
          (t) async {
        _key = key;
        today.fails.add(memberA);
        final c = await show(t);
        expect(notice, findsOneWidget, reason: 'premise');
        await way.value(t, c);
        await t.pump();
        expect(notice, findsNothing, reason: "A's failure, said to B");
        today.release();
        await settle(t);
        expect(notice, findsNothing);
        expect(bCalories, findsOneWidget);
        await close(t);
      });
    }

    testWidgets('signed out with A\'s totals drawn (by ${key.name}): A\'s go; '
        'A back has them', (t) async {
      _key = key;
      final c = await asA(t);
      today.holds['nobody'] = Completer<void>();
      c.invalidate(todayNutritionProvider);
      await switchTo(t, null);
      await t.pump();
      expectNothingOfA('THE defect');
      today.release();
      await settle(t);
      expectNothingOfA('THE defect');
      await switchTo(t, memberA);
      await settle(t);
      expect(aCalories, findsOneWidget);
      await close(t);
    });

    // ── Same member ───────────────────────────────────────────────────────
    testWidgets('CONTROL (by ${key.name}): a token refresh keeps the numbers, '
        'with its re-read in flight', (t) async {
      _key = key;
      final c = await asA(t);
      final before = c.read(currentUserProvider);
      final readsBefore = today.reads;
      today.holds[memberA] = Completer<void>();
      await hear(t, refreshSession);
      await t.pump();
      expect(c.read(currentUserProvider), isNot(before),
          reason: 'premise: a new User for the same member');
      expect(c.read(currentUserProvider)?.id, memberA);
      expect(aCalories, findsOneWidget);
      expect(aProtein, findsOneWidget);
      await settle(t);
      if (key == _Key.user) {
        expect(today.reads, greaterThan(readsBefore),
            reason: 'premise: keyed by the User, it re-reads');
      }
      expect(aCalories, findsOneWidget);
      expect(dash, findsNothing);
      today.release();
      await settle(t);
      expect(aCalories, findsOneWidget);
      await close(t);
    });

    testWidgets('CONTROL (by ${key.name}): a refresh in flight keeps the '
        'numbers; a failed one keeps them and says so', (t) async {
      _key = key;
      final c = await asA(t);
      today.holds[memberA] = Completer<void>();
      c.invalidate(todayNutritionProvider);
      await settle(t);
      expect(aCalories, findsOneWidget);
      expect(aProtein, findsOneWidget);
      today.fails.add(memberA);
      today.release();
      await settle(t);
      expect(aCalories, findsOneWidget, reason: 'same member: kept');
      expect(aCaloriesCell, findsOneWidget);
      expect(aProtein, findsOneWidget);
      expect(notice, findsOneWidget, reason: 'and said');
      expect(dash, findsNothing);
      await close(t);
    });
  }

  testWidgets('CONTROL: a read that said 0 is drawn as 0, not a dash',
      (t) async {
    today.answers[memberA] = const {
      'calories': 0, 'protein': 0, 'carbs': 0, 'fat': 0,
    };
    await show(t);
    expect(find.text('0'), findsWidgets);
    expect(zero, findsOneWidget);
    expect(find.text('0g'), findsNWidgets(3));
    expect(dash, findsNothing);
    expect(notice, findsNothing);
    await close(t);
  });

  testWidgets("CONTROL: A's first read pending is not loaded, not 0",
      (t) async {
    // At 1ead31b this was "0 kcal": a claim about A's day.
    today.holds[memberA] = Completer<void>();
    await show(t);
    expectUnknown();
    today.release();
    await settle(t);
    expect(aCalories, findsOneWidget);
    await close(t);
  });

  // ── Layout ──────────────────────────────────────────────────────────────
  Finder cardOf(Finder text) => find
      .ancestor(
          of: text,
          matching: find.byWidgetPredicate((w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).borderRadius ==
                  BorderRadius.circular(20)))
      .first;

  testWidgets('a loaded value is laid out as at 1ead31b (390dp, 1x)',
      (t) async {
    await show(t, width: 390);
    String at(Finder text) {
      final card = t.getRect(cardOf(text));
      final r = t.getRect(text);
      return '${card.size} @${r.topLeft - card.topLeft} ${r.size}';
    }

    // Measured at 1ead31b with the same totals.
    expect({
      'card 1840': at(aCalories),
      'card kcal': at(find.text('kcal')),
      'card goal': at(find.text('Goal: 2000 kcal')),
      'cell 1840 kcal': at(aCaloriesCell),
      'cell 132g': at(aProtein),
      'cell FAT': at(find.text('FAT')),
    }, _pinned390);
    await close(t);
  });

  for (final scale in fitScales) {
    for (final failed in [false, true]) {
      testWidgets('320dp at ${scale}x, ${failed ? 'failed' : 'pending'} '
          'and loaded: no overflow', (t) async {
        final seen = recordOverflows();
        if (failed) {
          today.fails.add(memberA);
        } else {
          today.holds[memberA] = Completer<void>();
        }
        await show(t, width: 320, scale: scale);
        expect(dash, findsNWidgets(5));
        if (failed) expect(notice, findsOneWidget);
        final screen = find.byType(ActivityScreen);
        expect(overflowsIn(t, seen, screen), isEmpty);
        today
          ..fails.clear()
          ..release();
        if (failed) {
          await t.ensureVisible(find.text('Try again'));
          await t.tap(find.text('Try again'));
        }
        await settle(t);
        expect(aCaloriesCell, findsOneWidget);
        expect(overflowsIn(t, seen, screen), isEmpty);
        await close(t);
      });
    }
  }
}

const _pinned390 = <String, String>{};
