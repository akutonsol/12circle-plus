import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/features/challenges/data/models/challenge_model.dart';
import 'package:circle_fitness/features/challenges/domain/challenge_provider.dart';
import 'package:circle_fitness/features/classes/data/models/class_model.dart';
import 'package:circle_fitness/features/classes/domain/class_provider.dart';
import 'package:circle_fitness/features/classes/domain/whats_on_provider.dart';
import 'package:circle_fitness/features/classes/presentation/whats_on_view.dart';

/// FIT-027 · "What's on" — the wiring.
///
/// `test/unit/whats_on_test.dart` proves the rules. These mount the real view
/// over the three real source providers, so the combination is exercised too —
/// and so that "the rule is implemented but nothing acts on it" is a mutation
/// that fails rather than one that survives. That exact mutation survived on
/// `/profile` and was only caught because it was run.
///
/// ── THE ONE THAT MATTERS ───────────────────────────────────────────────────
/// A merged list invites a specific lie: when one of three sources fails, the
/// list still looks full, so nothing looks wrong — and the client concludes
/// there are no events this month. Several tests below exist only to make that
/// impossible.
void main() {
  FitnessClass aClass({String id = 'c1', DateTime? at, String title = 'Reformer'}) =>
      FitnessClass(
        id: id,
        title: title,
        description: '',
        category: ClassCategory.strength,
        status: ClassStatus.upcoming,
        startTime: at ?? DateTime(2026, 9, 11, 18, 30),
        durationMinutes: 45,
        capacity: 10,
        bookedCount: 6,
        waitlistCount: 0,
        instructor: ClassInstructor(id: 'i', name: 'Nadia', role: 'coach', rating: 5),
        location: 'Studio 2',
        isVirtual: false,
        isBooked: false,
        isWaitlisted: false,
        tags: const [],
      );

  Challenge aChallenge({String id = 'ch1', String title = 'September strength'}) =>
      Challenge(
        id: id,
        title: title,
        description: '',
        type: ChallengeType.workout,
        status: ChallengeStatus.active,
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2026, 9, 14, 20, 0),
        targetValue: 20,
        unit: 'sessions',
        myProgress: 0.4,
        participantCount: 24,
        leaderboard: const [],
        rewards: const [],
        badges: const [],
        isJoined: false,
        coachName: 'Nadia',
        emoji: '🏋️',
      );

  Map<String, dynamic> anEvent({String id = 'e1', String title = 'Workshop'}) => {
        'id': id,
        'title': title,
        'event_date': DateTime(2026, 9, 12, 18, 30).toIso8601String(),
        'current_registered': 12,
      };

  Override pin<T>(ProviderBase<AsyncValue<T>> p, AsyncValue<T> v) =>
      (p as FutureProvider<T>).overrideWith((ref) => v.when(
            data: (d) => d,
            error: (e, s) => Future<T>.error(e, s),
            loading: () => Completer<T>().future,
          ));

  Future<void> mount(
    WidgetTester t, {
    AsyncValue<List<FitnessClass>> classes = const AsyncData([]),
    AsyncValue<List<Map<String, dynamic>>> events = const AsyncData([]),
    AsyncValue<List<Challenge>> challenges = const AsyncData([]),
  }) async {
    await t.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(ProviderScope(
      overrides: [
        pin(liveClassesFromDbProvider, classes),
        pin(whatsOnEventsProvider, events),
        pin(liveChallengesProvider, challenges),
      ],
      child: const MaterialApp(
        home: Scaffold(body: WhatsOnView()),
      ),
    ));
    await t.pump();
  }

  final offline = AsyncError<List<Map<String, dynamic>>>(
      Exception('offline'), StackTrace.empty);

  group('FIT-027 the three sources become one list', () {
    testWidgets('rows from all three appear under day headers, in order',
        (t) async {
      await mount(t,
          classes: AsyncData([aClass(title: 'Reformer')]),
          events: AsyncData([anEvent(title: 'Workshop')]),
          challenges: AsyncData([aChallenge(title: 'September strength')]));

      expect(find.text('Reformer'), findsOneWidget);
      expect(find.text('Workshop'), findsOneWidget);
      expect(find.text('September strength'), findsOneWidget);

      // 11 Sep class, 12 Sep event, 14 Sep challenge.
      expect(find.text('11 Sep'), findsOneWidget);
      expect(find.text('12 Sep'), findsOneWidget);
      expect(find.text('14 Sep'), findsOneWidget);

      expect(t.getTopLeft(find.text('Reformer')).dy,
          lessThan(t.getTopLeft(find.text('Workshop')).dy));
      expect(t.getTopLeft(find.text('Workshop')).dy,
          lessThan(t.getTopLeft(find.text('September strength')).dy));
    });

    testWidgets('the detail line is the design\'s, built from the row',
        (t) async {
      await mount(t, classes: AsyncData([aClass()]));
      expect(find.text('Class · Studio 2 · 4 places left'), findsOneWidget);
      expect(find.text('Book'), findsOneWidget);
    });
  });

  group('FIT-027 a source that fails is NEVER drawn as an empty one', () {
    testWidgets('events fail, the others load — the list says so and still '
        'shows what loaded', (t) async {
      await mount(t,
          classes: AsyncData([aClass()]),
          events: offline,
          challenges: AsyncData([aChallenge()]));

      // The lie this test exists to prevent.
      expect(find.text('No upcoming events'), findsNothing);
      // The already-shipped line from `events_screen.dart:66`.
      expect(find.text('Could not load events'), findsOneWidget);
      // And the rows that DID load are still there — a failed source must not
      // take the working ones down with it.
      expect(find.text('Reformer'), findsOneWidget);
      expect(find.text('September strength'), findsOneWidget);
      // Only the source that failed is named.
      expect(find.text('Could not load classes'), findsNothing);
      expect(find.text('Could not load challenges'), findsNothing);
    });

    testWidgets('the notice sits ABOVE the rows, not buried under them',
        (t) async {
      await mount(t,
          classes: AsyncData([aClass()]), events: offline);
      expect(t.getTopLeft(find.text('Could not load events')).dy,
          lessThan(t.getTopLeft(find.text('Reformer')).dy));
    });

    testWidgets('a failure with nothing else to show is NOT an empty state',
        (t) async {
      await mount(t, events: offline);

      expect(find.text('Could not load events'), findsOneWidget);
      // None of the three shipped empty lines may appear beside a failure.
      expect(find.text('No upcoming events'), findsNothing);
      expect(find.text('No classes yet'), findsNothing);
      expect(find.text('No challenges here'), findsNothing);
    });

    testWidgets('every failure offers a way back', (t) async {
      await mount(t, events: offline);
      expect(find.text('Try again'), findsOneWidget);
      final size = t.getSize(find
          .ancestor(of: find.text('Try again'), matching: find.byType(GestureDetector))
          .first);
      expect(size.height, greaterThanOrEqualTo(44.0));
    });

    testWidgets('a failure line never carries a raw exception', (t) async {
      await mount(t, events: offline);
      expect(find.textContaining('Exception'), findsNothing);
      expect(find.textContaining('offline'), findsNothing);
    });

    // NOTE: "a failed read carrying STALE rows contributes none of them" is
    // NOT asserted here, deliberately. The `pin()` harness turns an
    // `AsyncError` into `Future.error`, so Riverpod rebuilds the provider with
    // a plain error and the previous value is discarded — the test would pass
    // whatever the code did. It was written that way first and the mutation
    // survived. It now lives in `test/unit/whats_on_test.dart` against
    // `combineWhatsOn`, where the state can actually be constructed.

    testWidgets('viewing Classes is not told that Challenges failed',
        (t) async {
      await mount(t,
          classes: AsyncData([aClass()]),
          challenges: AsyncError(Exception('x'), StackTrace.empty));
      await t.ensureVisible(find.text('Classes'));
      await t.tap(find.text('Classes'));
      await t.pump();

      expect(find.text('Reformer'), findsOneWidget);
      expect(find.text('Could not load challenges'), findsNothing);
    });

    testWidgets('viewing Challenges IS told that Challenges failed', (t) async {
      await mount(t,
          classes: AsyncData([aClass()]),
          challenges: AsyncError(Exception('x'), StackTrace.empty));
      await t.ensureVisible(find.text('Challenges'));
      await t.pumpAndSettle();
      await t.tap(find.text('Challenges'));
      await t.pump();

      expect(find.text('Could not load challenges'), findsOneWidget);
      expect(find.text('No challenges here'), findsNothing);
    });
  });

  group('FIT-027 a genuinely empty schedule still says so', () {
    testWidgets('all three empty shows the three shipped empty lines',
        (t) async {
      await mount(t);
      expect(find.text('No classes yet'), findsOneWidget);
      expect(find.text('No upcoming events'), findsOneWidget);
      expect(find.text('No challenges here'), findsOneWidget);
      expect(find.textContaining('Could not load'), findsNothing);
    });

    testWidgets('one empty segment shows only that kind\'s line', (t) async {
      await mount(t, classes: AsyncData([aClass()]));
      await t.ensureVisible(find.text('Events'));
      await t.tap(find.text('Events'));
      await t.pump();

      expect(find.text('No upcoming events'), findsOneWidget);
      expect(find.text('No classes yet'), findsNothing);
    });
  });

  testWidgets('FIT-027 nothing is drawn until every source has settled',
      (t) async {
    // A source still in flight contributes no rows, which is indistinguishable
    // from one that returned none. Rendering early shows a list that is
    // briefly, silently wrong — and on a fast connection nobody ever sees it.
    await mount(t,
        classes: AsyncData([aClass()]),
        events: const AsyncLoading());

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Reformer'), findsNothing);
    expect(find.text('No upcoming events'), findsNothing);
  });

  group('FIT-027 the segment row', () {
    testWidgets('is the design\'s four labels, All selected first', (t) async {
      final handle = t.ensureSemantics();
      await mount(t);

      for (final label in ['All', 'Classes', 'Events', 'Challenges']) {
        expect(find.bySemanticsLabel(label), findsOneWidget);
      }
      expect(
          t.getSemantics(find.bySemanticsLabel('All'))
              .getSemanticsData()
              .hasFlag(SemanticsFlag.isSelected),
          isTrue);
      handle.dispose();
    });

    testWidgets('announces one exclusive choice, not four buttons', (t) async {
      final handle = t.ensureSemantics();
      await mount(t);

      for (final label in ['All', 'Classes', 'Events', 'Challenges']) {
        final d = t.getSemantics(find.bySemanticsLabel(label)).getSemanticsData();
        expect(d.hasFlag(SemanticsFlag.isInMutuallyExclusiveGroup), isTrue,
            reason: '$label is part of one choice');
        expect(d.hasAction(SemanticsAction.tap), isTrue,
            reason: '$label announces as a button it must be able to press — '
                'excludeSemantics drops the child\'s actions');
      }
      handle.dispose();
    });

    testWidgets('selecting a segment moves the selection and filters the list',
        (t) async {
      final handle = t.ensureSemantics();
      await mount(t,
          classes: AsyncData([aClass()]),
          challenges: AsyncData([aChallenge()]));

      // The segment row scrolls horizontally, and the last segment can sit
      // outside a narrow surface — a tap on an off-screen target silently
      // misses, which is how a green test that proves nothing gets written.
      await t.ensureVisible(find.text('Challenges'));
      await t.pumpAndSettle();
      await t.tap(find.text('Challenges'));
      await t.pump();

      expect(find.text('September strength'), findsOneWidget);
      expect(find.text('Reformer'), findsNothing);
      expect(
          t.getSemantics(find.bySemanticsLabel('Challenges'))
              .getSemanticsData()
              .hasFlag(SemanticsFlag.isSelected),
          isTrue);
      expect(
          t.getSemantics(find.bySemanticsLabel('All'))
              .getSemanticsData()
              .hasFlag(SemanticsFlag.isSelected),
          isFalse);
      handle.dispose();
    });

    testWidgets('every segment clears the 44 dp target floor', (t) async {
      await mount(t);
      for (final label in ['All', 'Classes', 'Events', 'Challenges']) {
        final size = t.getSize(find
            .ancestor(of: find.text(label), matching: find.byType(GestureDetector))
            .first);
        expect(size.height, greaterThanOrEqualTo(44.0), reason: '$label');
        expect(size.width, greaterThanOrEqualTo(44.0), reason: '$label');
      }
    });
  });
}
