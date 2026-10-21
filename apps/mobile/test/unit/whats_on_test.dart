import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/classes/domain/whats_on.dart';
import 'package:circle_fitness/features/classes/data/models/class_model.dart';
import 'package:circle_fitness/features/challenges/data/models/challenge_model.dart';

/// FIT-027 · "What's on" — `/classes · /events · /challenges under one list`.
///
/// The anchor folds three routes into one chronological list behind an
/// All / Classes / Events / Challenges segment row. Three shipped screens
/// become one, which means three independent reads behind one answer — and
/// that is where the interesting rule lives.
///
/// ── THE RULE THESE TESTS EXIST FOR ─────────────────────────────────────────
/// **A partial failure is reported, never hidden.** If Events fails and the
/// other two succeed, rendering the surviving two as "what's on" tells the
/// client there are no events — a false answer assembled from a true one and a
/// failure. It is the F-15 collapse with extra steps, and it is the failure
/// mode a merged list invites: the list still looks full, so nothing looks
/// wrong.
///
/// Three of the nine F-15 cases fixed so far were of exactly this shape
/// (`/train` answering "0 workouts", `/home` answering "0%", `/profile`
/// answering "no coach"). This screen is built so it cannot join them.
void main() {
  FitnessClass aClass({
    String id = 'c1',
    String title = 'Reformer, small group',
    String location = 'Studio 2',
    int capacity = 10,
    int booked = 6,
    bool isBooked = false,
    DateTime? at,
  }) =>
      FitnessClass(
        id: id,
        title: title,
        description: '',
        category: ClassCategory.strength,
        status: ClassStatus.upcoming,
        startTime: at ?? DateTime(2026, 9, 11, 18, 30),
        durationMinutes: 45,
        capacity: capacity,
        bookedCount: booked,
        waitlistCount: 0,
        instructor: ClassInstructor(id: 'i1', name: 'Nadia', role: 'coach', rating: 5),
        location: location,
        isVirtual: false,
        isBooked: isBooked,
        isWaitlisted: false,
        tags: const [],
      );

  Challenge aChallenge({
    String id = 'ch1',
    String title = 'September strength challenge',
    int participants = 24,
    bool joined = false,
    DateTime? ends,
  }) =>
      Challenge(
        id: id,
        title: title,
        description: '',
        type: ChallengeType.workout,
        status: ChallengeStatus.active,
        startDate: DateTime(2026, 9, 1),
        endDate: ends ?? DateTime(2026, 9, 14, 23, 59),
        targetValue: 20,
        unit: 'sessions',
        myProgress: 0.4,
        participantCount: participants,
        leaderboard: const [],
        rewards: const [],
        badges: const [],
        isJoined: joined,
        coachName: 'Nadia',
        emoji: '🏋️',
      );

  group('FIT-027 rows carry what the design draws', () {
    test('a class reads "Class · <place> · <n> places left"', () {
      final r = classRow(aClass());
      expect(r.title, 'Reformer, small group');
      expect(r.detail, 'Class · Studio 2 · 4 places left');
      expect(r.action, 'Book');
      expect(r.when, DateTime(2026, 9, 11, 18, 30));
    });

    test('a full class says so instead of reporting a negative number', () {
      final r = classRow(aClass(capacity: 8, booked: 8));
      expect(r.detail, contains('Full'));
      expect(r.detail, isNot(contains('-')));
      expect(r.action, isNull, reason: 'there is nothing left to book');
    });

    test('an over-subscribed class still says Full, never "-2 places left"', () {
      // Waitlists exist, so booked can exceed capacity in the data.
      final r = classRow(aClass(capacity: 8, booked: 10));
      expect(r.detail, 'Class · Studio 2 · Full');
    });

    test('a class already booked does not offer to book it again', () {
      final r = classRow(aClass(isBooked: true));
      expect(r.action, 'Booked');
    });

    test('a challenge is dated by when it CLOSES, not when it started', () {
      // The design draws "14 Sep · Challenge closes". The start date is not
      // what a client deciding whether to join needs.
      final r = challengeRow(aChallenge());
      expect(r.when, DateTime(2026, 9, 14, 23, 59));
      expect(r.detail, 'Challenge closes · 24 in');
      expect(r.action, isNull);
    });

    test('a joined challenge says so', () {
      expect(challengeRow(aChallenge(joined: true)).action, 'Joined');
    });

    test('an event reads "Event · <time> · <n> going"', () {
      final r = eventRow({
        'id': 7,
        'title': 'Strength basics workshop',
        'event_date': DateTime(2026, 9, 12, 18, 30).toIso8601String(),
        'current_registered': 12,
      });
      expect(r, isNotNull);
      expect(r!.title, 'Strength basics workshop');
      expect(r.detail, 'Event · 18:30 · 12 going');
      expect(r.id, 'event:7');
    });

    test('an event with no usable date is dropped, not given one', () {
      // Inventing a date would put a real event on a day it is not happening.
      expect(eventRow({'id': 1, 'title': 'x'}), isNull);
      expect(eventRow({'id': 1, 'title': 'x', 'event_date': 'not-a-date'}), isNull);
      expect(eventRow({'title': 'x', 'event_date': '2026-09-12T10:00:00Z'}), isNull,
          reason: 'a row with no id cannot be identified or navigated to');
    });

    test('ids are namespaced so two sources cannot collide', () {
      final c = classRow(aClass(id: '1'));
      final ch = challengeRow(aChallenge(id: '1'));
      final e = eventRow({
        'id': '1',
        'event_date': DateTime(2026, 9, 12).toIso8601String(),
      })!;
      expect({c.id, ch.id, e.id}, hasLength(3));
    });
  });

  group('FIT-027 the merged list', () {
    final classes = [
      classRow(aClass(id: 'c1', at: DateTime(2026, 9, 21, 9))),
      classRow(aClass(id: 'c2', at: DateTime(2026, 9, 11, 18, 30))),
    ];
    final events = [
      eventRow({
        'id': 'e1',
        'title': 'Workshop',
        'event_date': DateTime(2026, 9, 12, 18, 30).toIso8601String(),
      })!
    ];
    final challenges = [
      challengeRow(aChallenge(id: 'ch1', ends: DateTime(2026, 9, 14, 23, 59)))
    ];

    test('is chronological across all three sources', () {
      final merged =
          mergeWhatsOn(classes: classes, events: events, challenges: challenges);
      expect(merged.map((i) => i.id).toList(),
          ['class:c2', 'event:e1', 'challenge:ch1', 'class:c1']);
    });

    test('the order is total — equal timestamps do not reshuffle', () {
      final t = DateTime(2026, 9, 11, 18, 30);
      final a = mergeWhatsOn(
        classes: [classRow(aClass(id: 'b', at: t)), classRow(aClass(id: 'a', at: t))],
        events: const [],
        challenges: [challengeRow(aChallenge(id: 'z', ends: t))],
      );
      final b = mergeWhatsOn(
        classes: [classRow(aClass(id: 'a', at: t)), classRow(aClass(id: 'b', at: t))],
        events: const [],
        challenges: [challengeRow(aChallenge(id: 'z', ends: t))],
      );
      expect(a.map((i) => i.id).toList(), b.map((i) => i.id).toList());
    });

    test('a segment shows only its own kind, "All" shows everything', () {
      final merged =
          mergeWhatsOn(classes: classes, events: events, challenges: challenges);
      expect(itemsForSegment(merged, 0), hasLength(4));
      expect(itemsForSegment(merged, 1).map((i) => i.kind).toSet(),
          {WhatsOnKind.classes});
      expect(itemsForSegment(merged, 2).map((i) => i.kind).toSet(),
          {WhatsOnKind.events});
      expect(itemsForSegment(merged, 3).map((i) => i.kind).toSet(),
          {WhatsOnKind.challenges});
    });

    test('segments are the design\'s own four labels, in its order', () {
      expect(whatsOnSegments, ['All', 'Classes', 'Events', 'Challenges']);
    });

    test('rows group under a day header, in merged order', () {
      final merged =
          mergeWhatsOn(classes: classes, events: events, challenges: challenges);
      final groups = groupByDay(merged);
      expect(groups.map((g) => g.day).toList(),
          ['11 Sep', '12 Sep', '14 Sep', '21 Sep']);
      expect(groups.first.items.single.id, 'class:c2');
    });

    test('two rows on the same day share one header', () {
      final t = DateTime(2026, 9, 11);
      final groups = groupByDay(mergeWhatsOn(
        classes: [classRow(aClass(id: 'c1', at: t.add(const Duration(hours: 9))))],
        events: const [],
        challenges: [
          challengeRow(aChallenge(id: 'ch1', ends: t.add(const Duration(hours: 20))))
        ],
      ));
      expect(groups, hasLength(1));
      expect(groups.single.items, hasLength(2));
    });
  });

  group('FIT-027 a partial failure is reported, never hidden', () {
    test('"All" surfaces every source that failed', () {
      expect(failedForSegment({WhatsOnKind.events}, 0), {WhatsOnKind.events});
      expect(failedForSegment({WhatsOnKind.events, WhatsOnKind.classes}, 0),
          {WhatsOnKind.events, WhatsOnKind.classes});
    });

    test('a single segment surfaces its OWN failure', () {
      expect(failedForSegment({WhatsOnKind.events}, 2), {WhatsOnKind.events});
    });

    test("a single segment does not report another source's failure", () {
      // Telling someone looking at Classes that Challenges failed is noise.
      expect(failedForSegment({WhatsOnKind.challenges}, 1), isEmpty);
    });

    test('no failures means nothing to report on any segment', () {
      for (var s = 0; s < 4; s++) {
        expect(failedForSegment(const {}, s), isEmpty);
      }
    });

    test('the failure lines are strings this repository already ships', () {
      // `events_screen.dart:66` and `coach_classes_screen.dart:37` render the
      // first two verbatim; the third follows the "Could not load [noun]"
      // pattern used in fifteen other files. None of it is invented, which is
      // the only reason this screen can report a failure at all while OD-8 is
      // outstanding.
      expect(failureLine(WhatsOnKind.events), 'Could not load events');
      expect(failureLine(WhatsOnKind.classes), 'Could not load classes');
      expect(failureLine(WhatsOnKind.challenges), 'Could not load challenges');
    });

    test('a failure line never carries a raw exception', () {
      // F-2 and F-16 were raised about `$e` interpolated into user-facing text.
      for (final k in WhatsOnKind.values) {
        expect(failureLine(k), isNot(contains('Exception')));
        expect(failureLine(k), isNot(contains('\$')));
      }
    });
  });

  group('FIT-027 combineWhatsOn — the two rules a later edit would undo', () {
    final oneClass = AsyncData<List<FitnessClass>>([aClass()]);
    const noEvents = AsyncData<List<Map<String, dynamic>>>([]);
    const noChallenges = AsyncData<List<Challenge>>([]);

    test('it waits until every source has settled', () {
      // A source still in flight contributes no rows, which looks exactly like
      // one that returned none. Rendering early shows a list that is briefly,
      // silently wrong.
      final r = combineWhatsOn(
        classes: oneClass,
        events: const AsyncLoading<List<Map<String, dynamic>>>(),
        challenges: noChallenges,
      );
      expect(r, isA<AsyncLoading<WhatsOn>>());
    });

    test('a settled error counts as settled — it does not hang on a spinner', () {
      final r = combineWhatsOn(
        classes: oneClass,
        events: AsyncError(Exception('x'), StackTrace.empty),
        challenges: noChallenges,
      );
      expect(r.hasValue, isTrue);
      expect(r.value!.failed, {WhatsOnKind.events});
      expect(r.value!.items, hasLength(1));
    });

    test('a FAILED source contributes none of its stale rows', () {
      // Riverpod hands an AsyncError its previous value during a refresh, so
      // `.valueOrNull` on a failed read returns last week's rows. Showing those
      // under today's headings is a quieter version of the same lie — and
      // reaching for `.valueOrNull` is exactly how the /profile collapse
      // worked.
      final stale = AsyncError<List<FitnessClass>>(
              Exception('offline'), StackTrace.empty)
          .copyWithPrevious(AsyncData<List<FitnessClass>>([aClass(id: 'stale')]));
      expect(stale.valueOrNull, isNotNull,
          reason: 'guard the premise — the stale value really is carried');

      final r = combineWhatsOn(
        classes: stale,
        events: noEvents,
        challenges: noChallenges,
      );
      expect(r.value!.items, isEmpty);
      expect(r.value!.failed, {WhatsOnKind.classes});
    });

    test('a refresh in flight keeps showing what it already has', () {
      // The opposite failure: going back to a spinner every time the screen
      // refreshes. An AsyncLoading carrying a previous value has `hasValue`,
      // so it counts as settled.
      final refreshing = const AsyncLoading<List<FitnessClass>>()
          .copyWithPrevious(AsyncData<List<FitnessClass>>([aClass()]));
      final r = combineWhatsOn(
        classes: refreshing,
        events: noEvents,
        challenges: noChallenges,
      );
      expect(r, isNot(isA<AsyncLoading<WhatsOn>>()));
      expect(r.value!.items, hasLength(1));
    });

    test('nothing failed means nothing reported', () {
      final r = combineWhatsOn(
        classes: oneClass,
        events: noEvents,
        challenges: noChallenges,
      );
      expect(r.value!.failed, isEmpty);
    });
  });

  test('F-15 the challenges failure line is shared with /challenges', () {
    // `/challenges` renders this same string for the same source rather than
    // introducing a second sentence for the same failure. If someone changes
    // it here, they are changing it on both screens, which is the point of
    // having one definition.
    expect(failureLine(WhatsOnKind.challenges), 'Could not load challenges');
  });
}
