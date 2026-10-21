import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/checkins/data/weekly_checkin_service.dart';
import 'package:circle_fitness/features/checkins/domain/checkin_provider.dart';
import 'package:circle_fitness/features/checkins/presentation/coach_checkin_review_screen.dart';

/// FIT-033 · the review flow, mounted.
///
/// `test/unit/coach_review_queue_test.dart` pins the rules. This pins the part
/// the rules cannot: that the **flow** exists, which is the whole point of the
/// anchor —
///
/// > *"Six to review means the flow matters more than the screen: paged
/// > 1-of-6, and the primary action is send and open next."*
///
/// What shipped had no queue, no position and no next. `Back` was the only one
/// of five declared controls present, and a coach reviewing six check-ins
/// returned to a list between every one.

class _FakeCheckinService implements WeeklyCheckinService {
  final List<String> submitted = [];
  bool result = true;

  @override
  Future<bool> submitCoachFeedback({
    required String checkinId,
    required String message,
    required List<String> recommendations,
    required String coachName,
  }) async {
    submitted.add(checkinId);
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Map<String, dynamic> _checkin(
  String id, {
  required String first,
  int week = 14,
  Map<String, dynamic>? extra,
}) =>
    {
      'id': id,
      'week_number': week,
      'status': 'submitted',
      'user_profiles': {'first_name': first, 'last_name': 'Osei'},
      ...?extra,
    };

late _FakeCheckinService _service;

Future<ProviderContainer> _pump(
  WidgetTester tester,
  List<Map<String, dynamic>> queue, {
  int startAt = 0,
}) async {
  _service = _FakeCheckinService();
  final container = ProviderContainer(overrides: [
    coachSubmittedCheckinsProvider.overrideWith((ref) async => queue),
    selectedCoachCheckinProvider
        .overrideWith((ref) => queue.isEmpty ? null : queue[startAt]),
    weeklyCheckinServiceProvider.overrideWithValue(_service),
    // Without this the screen's `ref.read(currentUserDisplayNameProvider)`
    // reaches Supabase auth, which is not initialised in a widget test, and
    // `_submit` throws before it ever calls the service.
    currentUserDisplayNameProvider.overrideWithValue('Coach Nadia'),
  ]);
  addTearDown(container.dispose);

  final router = GoRouter(
    initialLocation: '/coach-checkin-review',
    routes: [
      GoRoute(
        path: '/coach-checkin-review',
        builder: (_, __) => const CoachCheckinReviewScreen(),
      ),
      GoRoute(
        path: '/program-builder',
        builder: (_, __) => const Scaffold(body: Text('AT /program-builder')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return container;
}

/// Scroll a control into view, then tap it.
///
/// FIT-033's actions sit at the bottom of a scrolling body, below the fold at
/// the harness's default size. `tester.tap` on an off-screen widget **misses
/// silently** — it warns, it does not throw — so three tests here reported
/// "the service was never called" when the truth was "the button was never
/// pressed". Not a product defect, but it looked exactly like one.
Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

List<Map<String, dynamic>> _six() => [
      _checkin('a', first: 'Amara', extra: {'compliance_percent': 92}),
      _checkin('b', first: 'Tomas'),
      _checkin('c', first: 'Priya'),
      _checkin('d', first: 'Lena'),
      _checkin('e', first: 'Nadia'),
      _checkin('f', first: 'Sam'),
    ];

void main() {
  testWidgets('the header is paged — Week 14 · 1 of 6', (tester) async {
    await _pump(tester, _six());
    expect(find.text('Amara Osei'), findsOneWidget);
    expect(find.text('Week 14 · 1 of 6'), findsOneWidget);
  });

  testWidgets('Next advances the queue WITHOUT sending', (tester) async {
    await _pump(tester, _six());
    expect(find.text('Week 14 · 1 of 6'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Tomas Osei'), findsOneWidget);
    expect(find.text('Week 14 · 2 of 6'), findsOneWidget);
    expect(_service.submitted, isEmpty,
        reason: 'Next moves through the queue; it does not reply for the coach');
  });

  testWidgets('the last of the queue offers no Next', (tester) async {
    await _pump(tester, _six(), startAt: 5);
    expect(find.text('Week 14 · 6 of 6'), findsOneWidget);
    expect(find.bySemanticsLabel('Next'), findsNothing,
        reason: 'a control that promises a next when there is none');
  });

  testWidgets('the primary action names what it will do', (tester) async {
    await _pump(tester, _six());
    expect(find.text('Send and open next'), findsOneWidget);
    expect(find.text('Send'), findsNothing);
  });

  testWidgets('on the last one it reads Send, not Send and open next',
      (tester) async {
    await _pump(tester, _six(), startAt: 5);
    expect(find.text('Send'), findsOneWidget);
    expect(find.text('Send and open next'), findsNothing);
  });

  testWidgets('sending opens the next one without leaving the screen',
      (tester) async {
    final container = await _pump(tester, _six());

    await tester.enterText(
        find.byType(TextField).first, 'Two is fine. Leave the conditioning.');
    await tester.pumpAndSettle();

    await _tap(tester, find.text('Send and open next'));

    expect(_service.submitted, ['a']);
    expect(container.read(selectedCoachCheckinProvider)?['id'], 'b',
        reason: 'the flow is the feature — the coach must not be returned to '
            'a list between each of six');
    expect(find.text('Week 14 · 2 of 6'), findsOneWidget);
  });

  testWidgets('the reply box is cleared for the next client', (tester) async {
    await _pump(tester, _six());
    await tester.enterText(find.byType(TextField).first, 'A reply for Amara.');
    await tester.pumpAndSettle();

    await _tap(tester, find.text('Send and open next'));

    expect(find.text('A reply for Amara.'), findsNothing,
        reason: "one client's reply must not be pre-filled into the next");
  });

  testWidgets('a refused send keeps the coach where they are', (tester) async {
    final container = await _pump(tester, _six());
    _service.result = false;

    await tester.enterText(find.byType(TextField).first, 'A reply.');
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Send and open next'));

    expect(container.read(selectedCoachCheckinProvider)?['id'], 'a',
        reason: 'advancing past a reply that never saved loses it silently');
    expect(find.textContaining('Failed to submit'), findsOneWidget);
  });

  testWidgets('an empty reply is refused before anything is sent',
      (tester) async {
    await _pump(tester, _six());
    await _tap(tester, find.text('Send and open next'));
    expect(_service.submitted, isEmpty);
  });

  group('the board copy', () {
    testWidgets('carries no pronoun over the client\'s own words',
        (tester) async {
      await _pump(tester, [
        _checkin('a', first: 'Amara', extra: {'notes': 'Travel next week.'}),
      ]);
      expect(find.text('They wrote'), findsOneWidget);
      expect(find.text('She wrote'), findsNothing);
      expect(find.text('Travel next week.'), findsOneWidget);
    });

    testWidgets('uses the board\'s words for the reply', (tester) async {
      await _pump(tester, _six());
      expect(find.text('Your reply'), findsOneWidget);
      expect(find.text('Your Feedback'), findsNothing);
    });
  });

  group('the stats', () {
    testWidgets('Nutrition renders, and Sessions does not', (tester) async {
      await _pump(tester, [
        _checkin('a', first: 'Amara', extra: {
          'compliance_percent': 92,
          'energy_level': 3,
          'sleep_hours': 7.2,
        }),
      ]);
      expect(find.text('92%'), findsOneWidget);
      expect(find.text('Nutrition'), findsOneWidget);
      expect(find.text('7.2 h avg'), findsOneWidget);
      // OD-24 — completed-against-prescribed is on no column of this row.
      expect(find.text('Sessions'), findsNothing);
    });

    testWidgets('OD-16 — Energy states its value, never Steady',
        (tester) async {
      await _pump(tester, [
        _checkin('a', first: 'Amara', extra: {'energy_level': 3}),
      ]);
      expect(find.text('3 of 5'), findsOneWidget);
      for (final w in const ['Low', 'Steady', 'Strong']) {
        expect(find.text(w), findsNothing);
      }
    });
  });

  // EC-G8's whole argument, on a real screen: a queue that FAILED is not a
  // queue that is empty. Hidden, the coach silently loses `Send and open next`
  // and is never told why.
  testWidgets('a failed queue read is stated, not rendered as an empty queue',
      (tester) async {
    _service = _FakeCheckinService();
    final container = ProviderContainer(overrides: [
      coachSubmittedCheckinsProvider
          .overrideWith((ref) => Future<List<Map<String, dynamic>>>.error(
                Exception('network'),
              )),
      selectedCoachCheckinProvider
          .overrideWith((ref) => _checkin('a', first: 'Amara')),
      weeklyCheckinServiceProvider.overrideWithValue(_service),
      currentUserDisplayNameProvider.overrideWithValue('Coach Nadia'),
    ]);
    addTearDown(container.dispose);
    final router = GoRouter(initialLocation: '/coach-checkin-review', routes: [
      GoRoute(
        path: '/coach-checkin-review',
        builder: (_, __) => const CoachCheckinReviewScreen(),
      ),
    ]);
    addTearDown(router.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining("couldn't load your review queue"), findsOneWidget);
    // The week is still known, so it is still shown.
    expect(find.textContaining('Week 14'), findsOneWidget);
    // And nothing promises a next it cannot reach.
    expect(find.text('Send and open next'), findsNothing);
    expect(find.bySemanticsLabel('Next'), findsNothing);
  });

  group('accessibility', () {
    testWidgets('every declared control is named and activatable',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, _six());

      for (final label in const ['Back', 'Next', 'Adjust plan']) {
        final f = find.bySemanticsLabel(label);
        expect(f, findsOneWidget, reason: '$label is not named');
        final d = tester.getSemantics(f).getSemanticsData();
        expect(d.hasFlag(SemanticsFlag.isButton), isTrue, reason: label);
        expect(d.hasAction(SemanticsAction.tap), isTrue,
            reason: '$label announces a button it cannot perform (F-20)');
      }
      handle.dispose();
    });

    // OD-25 — `coach_video_responses` exists but nothing in this app captures,
    // uploads or plays a video (QA_EVIDENCE §3ad). Drawn, and honestly
    // disabled rather than wired to a flow that does not exist.
    testWidgets('Record is drawn and says it is unavailable', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, _six());

      final d =
          tester.getSemantics(find.bySemanticsLabel('Record')).getSemanticsData();
      expect(d.hasFlag(SemanticsFlag.isButton), isTrue);

      // Both halves, and the first is the one that matters. `isEnabled` alone
      // is false when a control declares NO enabled-state at all, so a
      // mutation removing `enabled: false` survived against it. The claim
      // being made is "this control HAS an enabled state, and it is off" —
      // which is what a screen reader announces as "dimmed".
      expect(d.hasFlag(SemanticsFlag.hasEnabledState), isTrue,
          reason: 'without an enabled state a screen reader says nothing about '
              'availability, and the control reads as ordinary');
      expect(d.hasFlag(SemanticsFlag.isEnabled), isFalse,
          reason: 'OD-25: there is no capture path, so it must not claim one');
      expect(d.hasAction(SemanticsAction.tap), isFalse);
      handle.dispose();
    });
  });
}
