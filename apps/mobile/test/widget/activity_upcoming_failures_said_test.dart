import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/core/realtime/realtime.dart';
import 'package:circle_fitness/features/activity/presentation/activity_screen.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/challenges/domain/challenge_provider.dart';
import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart';
import 'package:circle_fitness/features/coach/domain/coach_provider.dart';
import 'package:circle_fitness/features/community/domain/community_provider.dart';
import 'package:circle_fitness/features/dashboard/domain/dashboard_provider.dart';
import 'package:circle_fitness/features/dashboard/presentation/directory_screen.dart';
import 'package:circle_fitness/features/nutrition/domain/nutrition_provider.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:circle_fitness/features/workout/presentation/widgets/section_load_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/activity_server.dart';
import '../support/fit_matrix.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-60b (a)+(e) · Activity's streak, and both Upcoming panels (Activity's
// and Directory's bell).
//
// At a82f993: a failed streak read was "0 day streak · Start today!"; B was
// shown A's streak while B's read was pending or had failed; a failed classes
// or events read made the section vanish; the bells shook with animations
// turned off; Directory's bell was 40px with no name.
//
// The real providers, a real auth client, no AccountScope.
//
// HOW TO SEE IT FAIL: `git checkout a82f993 --` dashboard_provider.dart,
// activity_screen.dart and directory_screen.dart; the controls pass.

const _other = 'Try again in a moment. If it keeps happening, contact support.';
const _net = 'Check your connection and try again.';
const _streakFailed = "Couldn't load your streak";
const _classesFailed = "Couldn't load upcoming classes";
const _eventsFailed = "Couldn't load upcoming events";

void main() {
  late ActivityServer server;
  final reported = <AppFailure>[];
  late StreamController<int> ticks;

  /// The device's "remove animations".
  final still = ValueNotifier(false);

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = ActivityServer();
    await initTwoMemberSupabase(server);
  });

  setUp(() async {
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
    still.value = false;
    ticks = StreamController<int>.broadcast();
    await signInAs(memberA);
  });
  tearDown(() {
    resetFailureSink();
    unawaited(ticks.close());
  });

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 8; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<ProviderContainer> show(WidgetTester t, Widget screen,
      {double width = 390, double scale = 1}) async {
    fitWindow(t, width, 9000, scale);
    final c = ProviderContainer(overrides: [
      currentFirstNameProvider.overrideWithValue('Sam'),
      confirmedCurrentProfileProvider.overrideWithValue(null),
      tableTickerProvider.overrideWith((ref, table) async* {
        yield 0;
        if (table == 'daily_scores') yield* ticks.stream;
      }),
      liveChallengesProvider.overrideWith((ref) async => const []),
      liveGroupsProvider.overrideWith((ref) async => const []),
      assignedWorkoutsProvider.overrideWith((ref) async => const []),
      programSessionStatusProvider.overrideWith((ref) async => const {}),
      assignedCoachProvider.overrideWith((ref) async => null),
      monthScoresProvider.overrideWith((ref) async => const []),
      weekScoresProvider.overrideWith((ref) async => const []),
      todayNutritionProvider.overrideWith((ref) async => const {}),
    ]);
    addTearDown(c.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            builder: (context, child) => ValueListenableBuilder(
                valueListenable: still,
                builder: (context, off, _) => MediaQuery(
                    data:
                        MediaQuery.of(context).copyWith(disableAnimations: off),
                    child: child!)),
            home: screen)));
    await settle(t);
    return c;
  }

  /// postgrest repeats a GET that did not reach the server (1 s, 2 s, 4 s)
  /// before it gives up.
  Future<void> giveUp(WidgetTester t) async {
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(seconds: 1));
      await settle(t);
    }
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
  }

  Future<void> switchTo(WidgetTester t, String? uid) async {
    await t.runAsync(() => uid == null ? signOut() : signInAs(uid));
    await settle(t);
  }

  void nothingRaw() => expect(find.textContaining('SECRET'), findsNothing);

  /// The streak number on screen, or null when none is claimed.
  String? streakShown() {
    final label = find.text('day streak');
    if (label.evaluate().isEmpty) return null;
    final column = find.ancestor(of: label, matching: find.byType(Column)).first;
    return find
        .descendant(of: column, matching: find.byType(Text))
        .evaluate()
        .map((e) => (e.widget as Text).data ?? '')
        .firstWhere((s) => RegExp(r'^\d+$').hasMatch(s));
  }

  List<String> streakReads() =>
      server.calls.where((k) => k.contains('daily_scores')).toList();

  group('streak', () {
    for (final (network, hint) in [(false, _other), (true, _net)]) {
      testWidgets(
          '${network ? 'unreachable' : 'refused'}: said, recorded, not "0 day '
          'streak"; Try again reads it', (t) async {
        server.days[memberA] = 3;
        (network ? server.offline : server.fails).add('daily_scores');
        await show(t, const ActivityScreen());
        if (network) await giveUp(t);
        expect(streakShown(), isNull, reason: 'THE defect: "0 day streak"');
        expect(find.text('Start today!'), findsNothing);
        expect(find.text('Active'), findsNothing);
        expect(find.text(_streakFailed), findsOneWidget);
        expect(find.text(hint), findsOneWidget);
        expect(reported.map((f) => f.origin).toSet(), {'streakProvider'});
        nothingRaw();

        server.fails.clear();
        server.offline.clear();
        await t.tap(find.text('Try again'));
        await settle(t);
        expect(streakShown(), '3');
        expect(find.text(_streakFailed), findsNothing);
        await close(t);
      });
    }

    testWidgets('Try again is busy while it reads: one request, no second fire',
        (t) async {
      final h = t.ensureSemantics();
      server.fails.add('daily_scores');
      await show(t, const ActivityScreen());
      final gate = Completer<void>();
      server.holds['GET daily_scores:$memberA'] = gate;
      final before = streakReads().length;
      await t.tap(find.text('Try again'));
      await settle(t);
      expect(find.text(_streakFailed), findsOneWidget);
      expect(find.bySemanticsLabel('Retrying'), findsOneWidget);
      await t.tap(find.bySemanticsLabel('Retrying'));
      await settle(t);
      expect(streakReads(), hasLength(before + 1));
      gate.complete();
      await settle(t);
      h.dispose();
      await close(t);
    });

    testWidgets('a failed refresh keeps the number and says so', (t) async {
      server.days[memberA] = 6;
      await show(t, const ActivityScreen());
      expect(streakShown(), '6');
      server.fails.add('daily_scores');
      ticks.add(1);
      await settle(t);
      expect(streakShown(), '6');
      expect(find.text(_streakFailed), findsOneWidget,
          reason: 'THE defect: the number became 0');
      await close(t);
    });

    testWidgets('NEGATIVE CONTROL: a genuine 0 is still "0 day streak", no '
        'failure', (t) async {
      await show(t, const ActivityScreen());
      expect(streakShown(), '0');
      expect(find.text('Start today!'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text(_streakFailed), findsNothing);
      expect(reported, isEmpty);
      await close(t);
    });

    testWidgets('POSITIVE CONTROL: the number; a new User for the same member '
        'keeps it', (t) async {
      server.days[memberA] = 8;
      await show(t, const ActivityScreen());
      expect(streakShown(), '8');
      expect(find.text('🔥 Hot'), findsOneWidget);
      await t.runAsync(refreshSession);
      await settle(t);
      expect(streakShown(), '8');
      await close(t);
    });

    testWidgets("A → B, B's read pending: A's number is gone; B's own shows "
        'when it lands', (t) async {
      server
        ..days[memberA] = 9
        ..days[memberB] = 2;
      await show(t, const ActivityScreen());
      expect(streakShown(), '9', reason: 'premise');
      final gate = Completer<void>();
      server.holds['GET daily_scores:$memberB'] = gate;
      await switchTo(t, memberB);
      expect(streakReads().last, 'GET daily_scores:$memberB');
      expect(streakShown(), isNull, reason: "THE defect: B was shown A's 9");
      expect(find.text('9'), findsNothing);
      gate.complete();
      await settle(t);
      expect(streakShown(), '2');
      await close(t);
    });

    testWidgets("A → B, B's read failed: the failure, never A's number; a "
        'retry in flight still shows nothing of A', (t) async {
      server
        ..days[memberA] = 9
        ..days[memberB] = 2
        ..fails.add('GET daily_scores:$memberB');
      await show(t, const ActivityScreen());
      await switchTo(t, memberB);
      expect(streakShown(), isNull, reason: 'THE defect: "0 day streak"');
      expect(find.text(_streakFailed), findsOneWidget);
      final gate = Completer<void>();
      server.holds['GET daily_scores:$memberB'] = gate;
      server.fails.clear();
      await t.tap(find.text('Try again'));
      await settle(t);
      expect(streakShown(), isNull);
      gate.complete();
      await settle(t);
      expect(streakShown(), '2');
      await close(t);
    });

    testWidgets("A's failure is not B's: B pending shows no failure", (t) async {
      server.fails.add('GET daily_scores:$memberA');
      await show(t, const ActivityScreen());
      expect(find.text(_streakFailed), findsOneWidget, reason: 'premise');
      final gate = Completer<void>();
      server.holds['GET daily_scores:$memberB'] = gate;
      await switchTo(t, memberB);
      expect(find.text(_streakFailed), findsNothing);
      expect(streakShown(), isNull);
      gate.complete();
      await settle(t);
      expect(streakShown(), '0');
      await close(t);
    });

    for (final late in ['before', 'after']) {
      testWidgets("A's delayed answer lands $late B's own: never shown to B",
          (t) async {
        server
          ..days[memberA] = 9
          ..days[memberB] = 2;
        final a = server.holds['GET daily_scores:$memberA'] = Completer<void>();
        await show(t, const ActivityScreen());
        final b = server.holds['GET daily_scores:$memberB'] = Completer<void>();
        await switchTo(t, memberB);
        if (late == 'after') {
          b.complete();
          await settle(t);
          expect(streakShown(), '2');
        }
        a.complete();
        await settle(t);
        expect(streakShown(), late == 'after' ? '2' : null);
        if (late == 'before') b.complete();
        await settle(t);
        expect(streakShown(), '2');
        await close(t);
      });
    }

    testWidgets('sign-out takes the number away; A coming back has it again',
        (t) async {
      server.days[memberA] = 9;
      await show(t, const ActivityScreen());
      await switchTo(t, null);
      expect(find.text('9'), findsNothing);
      await switchTo(t, memberA);
      expect(streakShown(), '9');
      await close(t);
    });

    for (final w in fitPhones.keys) {
      for (final s in fitScales) {
        testWidgets('the failure fits ${w}dp at ${s}x, not shrunk', (t) async {
          final seen = recordOverflows();
          server.fails.add('daily_scores');
          await show(t, const ActivityScreen(), width: w.toDouble(), scale: s);
          expect(seen, isEmpty, reason: seen.join('\n\n'));
          expect(
              renderedFontSize(t, find.text(_streakFailed)), closeTo(13 * s, 0.01));
          expect(t.getSize(find.byType(TextButton)).height,
              greaterThanOrEqualTo(44));
          await close(t);
        });
      }
    }
  });

  for (final (name, screen) in <(String, Widget)>[
    ('Activity', const ActivityScreen()),
    ('Directory', const DirectoryScreen()),
  ]) {
    group('$name › Upcoming', () {
      Future<ProviderContainer> open(WidgetTester t,
          {double width = 390, double scale = 1}) async {
        final c = await show(t, screen, width: width, scale: scale);
        await t.tap(find.byIcon(Icons.notifications_outlined));
        await settle(t);
        return c;
      }

      void rows() {
        server
          ..classes.add({
            'id': 'k1', 'title': 'Reformer', 'max_capacity': 8,
            'scheduled_at': '2030-01-02T10:00:00Z',
          })
          ..events.add({
            'id': 'e1', 'title': 'Open Gym', 'location': 'Pier 4',
            'event_date': '2030-01-03T10:00:00Z',
          });
      }

      for (final (table, failed, gone, stays, origin) in [
        ('classes', _classesFailed, 'Reformer', 'Open Gym',
            'upcomingClassesProvider'),
        ('events', _eventsFailed, 'Open Gym', 'Reformer',
            'upcomingEventsProvider'),
      ]) {
        for (final (network, hint) in [(false, _other), (true, _net)]) {
          testWidgets(
              '$table ${network ? 'unreachable' : 'refused'}: said, recorded; '
              'the other section stays; Try again reads it', (t) async {
            final h = t.ensureSemantics();
            rows();
            (network ? server.offline : server.fails).add(table);
            await open(t);
            if (network) await giveUp(t);
            expect(find.text(failed), findsOneWidget,
                reason: 'THE defect: the section vanished');
            expect(find.text(hint), findsOneWidget);
            expect(
                t
                    .getSemantics(find.bySemanticsLabel('$failed. $hint'))
                    .flagsCollection
                    .isLiveRegion,
                isTrue);
            expect(find.text(gone), findsNothing);
            expect(find.text(stays), findsOneWidget);
            expect(reported.map((f) => f.origin), [origin]);
            nothingRaw();

            server.fails.clear();
            server.offline.clear();
            final gate = Completer<void>();
            server.holds['GET $table:$memberA'] = gate;
            Iterable<String> reads() =>
                server.calls.where((k) => k == 'GET $table:$memberA');
            final before = reads().length;
            await t.tap(find.text('Try again'));
            await settle(t);
            expect(find.text(failed), findsOneWidget);
            expect(find.bySemanticsLabel('Retrying'), findsOneWidget);
            await t.tap(find.bySemanticsLabel('Retrying'));
            await settle(t);
            expect(reads(), hasLength(before + 1));
            gate.complete();
            await settle(t);
            expect(find.text(failed), findsNothing);
            expect(find.text(gone), findsOneWidget);
            h.dispose();
            await close(t);
          });
        }
      }

      testWidgets('a failed refresh keeps the rows and says so', (t) async {
        rows();
        final c = await open(t);
        server.fails.addAll(['classes', 'events']);
        c
          ..invalidate(upcomingClassesProvider)
          ..invalidate(upcomingEventsProvider);
        await settle(t);
        expect(find.text('Reformer'), findsOneWidget,
            reason: 'THE defect: the rows vanished');
        expect(find.text('Open Gym'), findsOneWidget);
        expect(find.text(_classesFailed), findsOneWidget);
        expect(find.text(_eventsFailed), findsOneWidget);
        await close(t);
      });

      testWidgets('NEGATIVE CONTROL: read and empty shows nothing, no failure',
          (t) async {
        await open(t);
        expect(find.textContaining("Couldn't load"), findsNothing);
        expect(find.text('Try again'), findsNothing);
        expect(find.byType(CircularProgressIndicator).hitTestable(),
            findsNothing);
        expect(reported, isEmpty);
        await close(t);
      });

      testWidgets('POSITIVE CONTROL: both sections, no failure', (t) async {
        rows();
        await open(t);
        expect(find.text('Reformer'), findsOneWidget);
        expect(find.text('Open Gym'), findsOneWidget);
        expect(find.textContaining('Jan'), findsNWidgets(2));
        expect(reported, isEmpty);
        await close(t);
      });

      testWidgets('a date that cannot be read is said and recorded, not blank',
          (t) async {
        rows();
        server.classes.single['scheduled_at'] = 'soon';
        await open(t);
        expect(find.text('Date unavailable'), findsOneWidget);
        expect(find.textContaining('Jan'), findsOneWidget);
        expect(reported.map((f) => f.origin).toSet(),
            {'${name.toLowerCase()}.upcoming.date'});
        await close(t);
      });

      for (final s in fitScales) {
        testWidgets('both failures fit 320dp at ${s}x, not shrunk', (t) async {
          final seen = recordOverflows();
          server.fails.addAll(['classes', 'events']);
          // Opened at 1x: Directory's header bar is not this package's.
          await open(t, width: 320);
          t.platformDispatcher.textScaleFactorTestValue = s;
          await settle(t);
          expect(overflowsIn(t, seen, find.byType(SectionLoadFailure)), isEmpty);
          for (final m in [_classesFailed, _eventsFailed]) {
            expect(renderedFontSize(t, find.text(m)), closeTo(13 * s, 0.01));
          }
          await close(t);
        });
      }
    });

    group('$name › bell', () {
      double angle(WidgetTester t) {
        final m = t
            .widget<Transform>(find
                .ancestor(
                    of: find.byIcon(Icons.notifications_outlined),
                    matching: find.byType(Transform))
                .first)
            .transform;
        return m.storage[1]; // sin(angle)
      }

      Future<bool> shook(WidgetTester t) async {
        var moved = false;
        for (var i = 0; i < 260; i++) {
          await t.pump(const Duration(milliseconds: 20));
          moved = moved || angle(t).abs() > 0.001;
        }
        return moved;
      }

      testWidgets('animations turned off: it never moves', (t) async {
        still.value = true;
        await show(t, screen);
        expect(await shook(t), isFalse, reason: 'THE defect: it shook');
        await close(t);
      });

      testWidgets('POSITIVE CONTROL: it shakes, again and again', (t) async {
        await show(t, screen);
        expect(await shook(t), isTrue);
        expect(await shook(t), isTrue);
        await close(t);
      });

      testWidgets('turned off mid-shake: it stops level; turned on: it shakes',
          (t) async {
        await show(t, screen);
        for (var i = 0; i < 200 && angle(t).abs() < 0.05; i++) {
          await t.pump(const Duration(milliseconds: 20));
        }
        expect(angle(t).abs(), greaterThan(0.05), reason: 'premise: mid-shake');
        still.value = true;
        await t.pump();
        expect(angle(t), 0);
        expect(await shook(t), isFalse);
        still.value = false;
        await t.pump();
        expect(await shook(t), isTrue);
        await close(t);
      });

      testWidgets('at least 44×44, named, pressable by a screen reader',
          (t) async {
        final h = t.ensureSemantics();
        await show(t, screen);
        final bell = find.bySemanticsLabel('Show upcoming classes and events');
        expect(bell, findsOneWidget);
        final size = t.getSize(bell);
        expect(size.width, greaterThanOrEqualTo(44));
        expect(size.height, greaterThanOrEqualTo(44));
        final node = t.getSemantics(bell);
        expect(node.flagsCollection.isButton, isTrue);
        node.owner!.performAction(node.id, SemanticsAction.tap);
        await settle(t);
        expect(find.byType(BottomSheet), findsOneWidget);
        h.dispose();
        await close(t);
      });
    });
  }
}
