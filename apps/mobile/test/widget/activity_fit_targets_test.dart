import 'dart:convert';

import 'package:circle_fitness/core/realtime/realtime.dart';
import 'package:circle_fitness/features/activity/presentation/activity_screen.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/challenges/data/live_challenge_service.dart';
import 'package:circle_fitness/features/challenges/data/models/challenge_model.dart';
import 'package:circle_fitness/features/challenges/domain/challenge_provider.dart';
import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart';
import 'package:circle_fitness/features/community/data/models/post_model.dart';
import 'package:circle_fitness/features/community/domain/community_provider.dart';
import 'package:circle_fitness/features/dashboard/domain/dashboard_provider.dart';
import 'package:circle_fitness/features/nutrition/domain/nutrition_provider.dart';
import 'package:circle_fitness/features/workout/data/models/workout_model.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/fit_matrix.dart';

// P0-FL-58 (a) · Activity: fit and touch targets.
//
// At f191d48: "Browse", "Join", "Log food", "Explore" and the header's three
// buttons were under 44px, with no button role and no item in their name; the
// eight water dots were 8px each; "See All" / "Enable" were 44px but a screen
// reader had no tap action on them; and ten Rows/Columns overflowed (the
// performance ring row, the fixed-ratio macro grid, the 64px header, …).
//
// Activity is a primary member screen, so the matrix includes 3.0×.
// Overflows anywhere on the screen fail these tests.
//
// HOW TO SEE IT FAIL: `git checkout f191d48 -- lib/features/activity/
// presentation/activity_screen.dart`; only the controls pass.

class _Rest extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(Stream.value(utf8.encode('[]')), 200,
          request: request, headers: {'content-type': 'application/json'});
}

class _MemoryStore extends GotrueAsyncStorage {
  final Map<String, String> _m = {};
  @override
  Future<String?> getItem({required String key}) async => _m[key];
  @override
  Future<void> setItem({required String key, required String value}) async =>
      _m[key] = value;
  @override
  Future<void> removeItem({required String key}) async => _m.remove(key);
}

class _Joins extends LiveChallengeService {
  final joined = <String>[];
  @override
  Future<void> joinChallenge(String challengeId) async => joined.add(challengeId);
}

Challenge _challenge(String id, String title, {bool joined = false}) => Challenge(
      id: id,
      title: title,
      description: '',
      type: ChallengeType.steps,
      status: ChallengeStatus.active,
      startDate: DateTime.now().subtract(const Duration(days: 1)),
      endDate: DateTime.now().add(const Duration(days: 10, hours: 1)),
      targetValue: 100,
      unit: 'steps',
      myProgress: 40,
      participantCount: 12345,
      leaderboard: const [],
      rewards: const [],
      badges: const [],
      isJoined: joined,
      coachName: '',
      emoji: '🏆',
    );

const _longTitle = 'Ten Thousand Steps Every Day';
const _longGroup = 'Early Morning Lifters';

class _World {
  /// No challenges, no groups, no plan, no scores.
  bool empty = false;
  bool prompt = false;
  String name = 'Sam';
  int percent = 73;
  final joins = _Joins();
}

late _World _w;

Workout _today() => Workout(
      id: 'w1',
      title: 'Lower body strength and conditioning',
      description: '',
      estimatedDuration: 48,
      difficulty: 'intermediate',
      category: 'strength',
      exercises: const [],
      scheduledDate: DateTime.now(),
    );

GoRouter _router() => GoRouter(initialLocation: '/activity', routes: [
      GoRoute(path: '/activity', builder: (_, __) => const ActivityScreen()),
      for (final p in [
        '/challenges', '/community', '/nutrition', '/profile', '/messages',
        '/train', '/notification-preferences', '/appointments', '/directory',
      ])
        GoRoute(path: p, builder: (_, __) => Scaffold(body: Text('AT $p'))),
    ]);

Future<void> _settle(WidgetTester tester) async {
  // The bell loops for ever: never pumpAndSettle. Long enough for the ring.
  for (var i = 0; i < 24; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<ProviderContainer> _show(WidgetTester tester,
    {double width = 390, double height = 9000, double scale = 1}) async {
  fitWindow(tester, width, height, scale);
  final c = ProviderContainer(overrides: [
    currentUserProvider.overrideWith((ref) => null),
    currentFirstNameProvider.overrideWithValue(_w.name),
    tableTickerProvider.overrideWith((ref, t) => Stream.value(0)),
    confirmedCurrentProfileProvider
        .overrideWithValue(_w.prompt ? {'notif_challenges': false} : null),
    liveChallengeServiceProvider.overrideWithValue(_w.joins),
    liveChallengesProvider.overrideWith((ref) async => _w.empty
        ? const []
        : [_challenge('c1', _longTitle), _challenge('c2', 'Push-up Week', joined: true)]),
    liveGroupsProvider.overrideWith((ref) async => [
          if (!_w.empty)
            CommunityGroup(id: 'g1', name: _longGroup, description: '',
                emoji: '💪', memberCount: 1234, isJoined: true),
        ]),
    assignedWorkoutsProvider
        .overrideWith((ref) async => _w.empty ? const [] : [_today()]),
    streakProvider.overrideWith((ref) async => _w.empty ? 0 : 365),
    monthScoresProvider.overrideWith((ref) async => [
          if (!_w.empty)
            {'total_score': _w.percent * DateTime.now().day, 'workout_points': 10},
        ]),
    weekScoresProvider.overrideWith((ref) async => [
          {'total_score': 10},
          {'total_score': 90},
        ]),
    todayNutritionProvider.overrideWith((ref) async => _w.empty
        ? const {}
        : {'calories': 1850.0, 'protein': 140.0, 'carbs': 210.0, 'fat': 60.0}),
    upcomingClassesProvider.overrideWith((ref) async => [
          {'id': 'k1', 'title': 'Reformer Pilates Foundations', 'max_capacity': 20,
           'scheduled_at': '2030-01-02T10:00:00Z'},
        ]),
    upcomingEventsProvider.overrideWith((ref) async => [
          {'id': 'e1', 'title': 'Open Gym Saturday', 'event_date': '2030-01-03T10:00:00Z',
           'location': '1200 Long Riverside Boulevard, Building 4'},
        ]),
  ]);
  addTearDown(c.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
      container: c, child: MaterialApp.router(routerConfig: _router())));
  await _settle(tester);
  return c;
}

/// Activity runs looping animations (the bell); unmount and drain them.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

Finder get _screen => find.byType(ActivityScreen);

void _expectWhole(WidgetTester tester, String text, double size, double scale) {
  final f = find.text(text);
  expect(f, findsOneWidget, reason: text);
  expect(renderedFontSize(tester, f), closeTo(size * scale, 0.01),
      reason: '"$text" is not drawn at its own size × $scale');
}

void main() {
  setUpAll(() async {
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _Rest(),
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryStore(),
        detectSessionInUri: false,
      ),
      debug: false,
    );
  });

  setUp(() => _w = _World());

  group('fit: no overflow, no shrunk text', () {
    for (final w in fitPhones.keys) {
      for (final s in fitScales) {
        testWidgets('with a plan, challenges and groups, ${w}dp at ${s}x', (tester) async {
          final seen = recordOverflows();
          _w
            ..percent = 100
            ..name = 'Maximiliana-Josephine';
          await _show(tester, width: w.toDouble(), scale: s);
          expect(seen, isEmpty, reason: seen.join('\n\n'));
          expectTextNotShrunk(tester, _screen, s);
          _expectWhole(tester, '100%', 48, s);
          _expectWhole(tester, 'Maximiliana-Josephine', 20, s);
          _expectWhole(tester, 'Log food', 11, s);
          _expectWhole(tester, 'Join', 12, s);
          _expectWhole(tester, 'Explore', 13, s);
          _expectWhole(tester, '1850 kcal', 14, s);
          if (s > 1.3) {
            // Nothing is cut to an ellipsis at large text.
            for (final t in [_longTitle, _longGroup]) {
              expect(tester.widget<Text>(find.text(t)).overflow, isNull, reason: t);
            }
          }
          await _unmount(tester);
        });

        testWidgets('with nothing yet, ${w}dp at ${s}x', (tester) async {
          final seen = recordOverflows();
          _w.empty = true;
          await _show(tester, width: w.toDouble(), scale: s);
          expect(seen, isEmpty, reason: seen.join('\n\n'));
          expectTextNotShrunk(tester, _screen, s);
          expect(find.text('Browse'), findsNWidgets(2), reason: 'premise');
          _expectWhole(tester, 'No active challenges', 13, s);
          _expectWhole(tester, 'No communities joined yet', 13, s);
          await _unmount(tester);
        });

        testWidgets('the Upcoming panel, ${w}dp at ${s}x', (tester) async {
          final seen = recordOverflows();
          await _show(tester, width: w.toDouble(), scale: s);
          await tester.tap(find.byIcon(Icons.notifications_outlined));
          await _settle(tester);
          expect(find.text('Open Gym Saturday'), findsOneWidget, reason: 'premise');
          expect(seen, isEmpty, reason: seen.join('\n\n'));
          expectTextNotShrunk(tester, find.byType(BottomSheet), s);
          _expectWhole(tester, 'Today & beyond', 11, s);
          await _unmount(tester);
        });
      }
    }

    testWidgets('the Enable prompt at 320dp, 3.0x', (tester) async {
      final seen = recordOverflows();
      _w.prompt = true;
      await _show(tester, width: 320, scale: 3);
      expect(seen, isEmpty, reason: seen.join('\n\n'));
      _expectWhole(tester, 'Enable', 12, 3);
      await _unmount(tester);
    });

    for (final s in fitScales) {
      testWidgets('on a real 320×568 phone the header keeps its buttons at ${s}x',
          (tester) async {
        final seen = recordOverflows();
        await _show(tester, width: 320, height: 568, scale: s);
        expect(seen, isEmpty, reason: seen.join('\n\n'));
        for (final i in [Icons.person_rounded, Icons.chat_bubble_outline_rounded,
            Icons.notifications_outlined]) {
          expect(find.byIcon(i).hitTestable(), findsOneWidget, reason: '$i');
        }
        // Three targets, none overlapping another or off screen.
        final rects = [
          for (final l in ['Open your profile', 'Open messages', 'Show upcoming classes and events'])
            tester.getRect(find.bySemanticsLabel(l))
        ];
        for (var i = 0; i < rects.length; i++) {
          expect(rects[i].left, greaterThanOrEqualTo(0));
          expect(rects[i].right, lessThanOrEqualTo(320));
          if (i > 0) expect(rects[i].left, greaterThanOrEqualTo(rects[i - 1].right));
        }
        await _unmount(tester);
      });
    }
  });

  group('targets', () {
    testWidgets('every target is at least 44×44 and named (with content)', (tester) async {
      final h = tester.ensureSemantics();
      await _show(tester, width: 320);
      expectTargets(tester, _screen, atLeast: 11);
      for (final label in [
        'Open your profile',
        'Open messages',
        'Show upcoming classes and events',
        "Log food for today's macros",
        'See all challenges',
        'Join $_longTitle',
        'Explore the community',
        'Open $_longTitle, 12345 joined, 10 days left',
        'Open Push-up Week, 12345 joined, 10 days left, joined',
        'Open $_longGroup, 1234 members, joined',
        "Open today's workout: Lower body strength and conditioning, 48 min, Not started yet",
      ]) {
        expectNamedButton(tester, label);
      }
      h.dispose();
      await _unmount(tester);
    });

    testWidgets('every target is at least 44×44 and named (empty, prompt off)', (tester) async {
      final h = tester.ensureSemantics();
      _w.empty = true;
      await _show(tester, width: 320);
      expectTargets(tester, _screen, atLeast: 8);
      expectNamedButton(tester, 'Browse challenges');
      expectNamedButton(tester, 'Browse community groups');
      expectNamedButton(tester, 'Open Train: No session assigned for today');
      h.dispose();
      await _unmount(tester);
    });

    testWidgets('the Upcoming panel rows are named buttons', (tester) async {
      final h = tester.ensureSemantics();
      await _show(tester, width: 320);
      await tester.tap(find.byIcon(Icons.notifications_outlined));
      await _settle(tester);
      expect(find.bySemanticsLabel(RegExp(r'^Open Reformer Pilates Foundations, .*, 20 spots$')),
          findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Open Open Gym Saturday, .*Building 4$')),
          findsOneWidget);
      expectTargets(tester, find.byType(BottomSheet), atLeast: 2);
      h.dispose();
      await _unmount(tester);
    });

    for (final (label, to) in [
      ("Log food for today's macros", '/nutrition'),
      ('See all challenges', '/challenges'),
      ('Explore the community', '/community'),
      ('Open your profile', '/profile'),
      ('Open messages', '/messages'),
      ('Open $_longTitle, 12345 joined, 10 days left', '/challenges'),
      ('Open $_longGroup, 1234 members, joined', '/community'),
    ]) {
      testWidgets('a screen reader can press "$label"', (tester) async {
        final h = tester.ensureSemantics();
        await _show(tester);
        tester.semantics.tap(find.semantics.byLabel(label));
        await _settle(tester);
        expect(find.text('AT $to'), findsOneWidget);
        h.dispose();
        await _unmount(tester);
      });
    }

    for (final (label, to, empty, prompt) in [
      ('Browse challenges', '/challenges', true, false),
      ('Browse community groups', '/community', true, false),
      ('Open Train: No session assigned for today', '/train', true, false),
      ('Enable challenge alerts', '/notification-preferences', false, true),
    ]) {
      testWidgets('a screen reader can press "$label"', (tester) async {
        final h = tester.ensureSemantics();
        _w
          ..empty = empty
          ..prompt = prompt;
        await _show(tester);
        final node = find.semantics.byPredicate((n) {
          final d = n.getSemanticsData();
          return d.label == label && d.flagsCollection.isButton;
        });
        tester.semantics.tap(node);
        await _settle(tester);
        expect(find.text('AT $to'), findsOneWidget);
        h.dispose();
        await _unmount(tester);
      });
    }

    testWidgets('Join joins THIS challenge, by touch at the edge of its target and '
        'by screen reader; the row itself still opens', (tester) async {
      final h = tester.ensureSemantics();
      await _show(tester);
      final rect = tester.getRect(find.bySemanticsLabel('Join $_longTitle'));
      await tester.tapAt(rect.topLeft + const Offset(2, 2));
      await _settle(tester);
      expect(_w.joins.joined, ['c1']);
      expect(find.text('AT /challenges'), findsNothing, reason: 'the row was not pressed');
      tester.semantics.tap(find.semantics.byLabel('Join $_longTitle'));
      await _settle(tester);
      expect(_w.joins.joined, ['c1', 'c1']);
      h.dispose();
      await _unmount(tester);
    });

    testWidgets('touching the edge of a 44px target presses it', (tester) async {
      _w.empty = true;
      await _show(tester);
      final rect = tester.getRect(find.bySemanticsLabel('Browse challenges'));
      expect(rect.height, greaterThanOrEqualTo(44));
      await tester.tapAt(rect.bottomCenter - const Offset(0, 2));
      await _settle(tester);
      expect(find.text('AT /challenges'), findsOneWidget);
      await _unmount(tester);
    });
  });

  group('water dots: one 44px control', () {
    testWidgets('it is named, adjustable, and 44px', (tester) async {
      final h = tester.ensureSemantics();
      final c = await _show(tester, width: 320);
      final f = find.bySemanticsLabel('Glasses of water today');
      expect(f, findsOneWidget);
      final n = tester.getSemantics(f);
      expect(n.rect.height, greaterThanOrEqualTo(44));
      expect(n.rect.width, greaterThanOrEqualTo(44));
      expect(n.value, '0 of 8');
      tester.semantics.increase(find.semantics.byLabel('Glasses of water today'));
      await _settle(tester);
      expect(c.read(waterIntakeProvider), 1);
      tester.semantics.decrease(find.semantics.byLabel('Glasses of water today'));
      await _settle(tester);
      expect(c.read(waterIntakeProvider), 0);
      h.dispose();
      await _unmount(tester);
    });

    testWidgets('a touch anywhere in its height sets the dot under it, and the last '
        'dot again takes one away', (tester) async {
      final c = await _show(tester);
      // The third of eight dots, at the bottom of the 44px.
      final card = tester.getRect(find.ancestor(of: find.text('glasses'),
          matching: find.byType(Column)).first);
      final y = card.bottom - 2;
      Offset dot(int i) => Offset(card.left + card.width * (i + 0.5) / 8, y);
      await tester.tapAt(dot(2));
      await _settle(tester);
      expect(c.read(waterIntakeProvider), 3);
      await tester.tapAt(dot(2));
      await _settle(tester);
      expect(c.read(waterIntakeProvider), 2);
      await tester.tapAt(dot(7));
      await _settle(tester);
      expect(c.read(waterIntakeProvider), 8);
      await _unmount(tester);
    });

    testWidgets('control: tapping a dot itself works as it did', (tester) async {
      final c = await _show(tester, width: 430);
      final y = tester.getRect(find.text('glasses')).bottom + 16; // on the dots
      final card = tester.getRect(find.ancestor(of: find.text('glasses'),
          matching: find.byType(Column)).first);
      await tester.tapAt(Offset(card.left + card.width * 4.4 / 8, y));
      await _settle(tester);
      expect(c.read(waterIntakeProvider), 5);
      await _unmount(tester);
    });
  });

  testWidgets('control: 1.0x on 390dp keeps its layout', (tester) async {
    recordOverflows(); // the base overflows its ring row by 8px in the test font
    await _show(tester);
    Rect r(Finder f) => tester.getRect(f);
    // The greeting is in the 64px bar, between the buttons.
    expect(r(find.text('Sam')).bottom, lessThan(64));
    expect(r(find.text('Sam')).left, greaterThan(r(find.byIcon(Icons.person_rounded)).right));
    // Streak beside water; the same top.
    final streak = r(find.byIcon(Icons.local_fire_department_rounded).first);
    final water = r(find.byIcon(Icons.water_drop_rounded));
    expect(water.left, greaterThan(195));
    expect(streak.right, lessThan(195));
    expect((streak.top - water.top).abs(), lessThan(4));
    // The ring beside the percentage.
    expect(r(find.text('73%')).right, lessThan(r(find.text('WORKOUT\nDAYS')).left));
    expect((r(find.text('WORKOUT\nDAYS')).center.dy - r(find.text('73%')).center.dy).abs(),
        lessThan(60));
    // Macros two per line, at the 2.4:1 cell they had.
    final cal = r(find.text('CALORIES')), pro = r(find.text('PROTEIN')), carb = r(find.text('CARBS'));
    expect(pro.top, cal.top);
    expect(pro.left - cal.left, closeTo(180, 0.5), reason: '170 cell + 10 gap');
    expect(carb.top - cal.top, closeTo(170 / 2.4 + 10, 0.5));
    // Log food / See All / Explore at the right; Join at the right of its row.
    for (final t in ['Log food', 'See All', 'Explore']) {
      expect(r(find.text(t)).right, closeTo(370, 0.5), reason: t);
    }
    expect(r(find.text('Join')).left, greaterThan(r(find.text(_longTitle)).left + 100));
    await _unmount(tester);
  });

  testWidgets('control: a long name at 1.0x on 430dp still shows whole', (tester) async {
    _w.name = 'Samantha';
    await _show(tester, width: 430);
    expect(find.text('Samantha'), findsOneWidget);
    expect(tester.getRect(find.text('Samantha')).bottom, lessThan(64));
    await _unmount(tester);
  });
}
