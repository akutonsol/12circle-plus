import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/challenges/domain/challenge_provider.dart';
import 'package:circle_fitness/features/challenges/presentation/challenge_detail_screen.dart';
import 'package:circle_fitness/features/challenges/presentation/challenges_screen.dart';
import 'package:circle_fitness/features/exercise_database/domain/custom_exercise_provider.dart';
import 'package:circle_fitness/features/exercise_database/presentation/create_exercise_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pump_until.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-57a · what the SCREENS show across a real sign-out / sign-in: the
// challenge list and the opened challenge, and the exercise edit prefill.
// (The providers themselves: test/unit/challenges_follow_signin_test.dart and
// my_exercises_follow_signin_test.dart.)
//
// HOW TO SEE IT FAIL: `git checkout f191d48 --` challenge_provider.dart and
// custom_exercise_provider.dart.

Map<String, Object?> _row(String id, String title) => {
      'id': id,
      'title': title,
      'description': 'Walk',
      'type': 'steps',
      'status': 'active',
      'target_value': 1000,
      'unit': 'steps',
    };

void main() {
  late TwoMemberPostgrest server;
  late ProviderContainer c;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = TwoMemberPostgrest();
    await initTwoMemberSupabase(server);
  });

  setUp(() async {
    server.reset();
    server.challenges
        .addAll([_row('ch-1', 'Ten K Steps'), _row('ch-2', 'Push-up Week')]);
    server.participants.addAll([
      {'challenge_id': 'ch-1', 'user_id': memberA, 'current_progress': 500},
      {'challenge_id': 'ch-2', 'user_id': memberB, 'current_progress': 420},
    ]);
    server.exercises.add({
      'id': 'a-1',
      'name': 'Alpha Press',
      'coach_id': memberA,
      'slug': 'alpha-press',
      'visibility': 'private',
    });
    setFailureSink((_) {});
    await signInAs(memberA);
    c = ProviderContainer(overrides: [
      currentUserProfileProvider.overrideWith((ref) async {
        final u = ref.watch(currentUserProvider);
        return u == null ? null : {'id': u.id, 'role': 'coach'};
      }),
    ]);
  });

  tearDown(() {
    resetFailureSink();
    c.dispose();
  });

  Future<void> show(WidgetTester tester, Widget screen) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1000, 2600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c, child: MaterialApp(home: screen)));
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> switchToB(WidgetTester tester) async {
    await tester.runAsync(() => signInAs(memberB));
    await pumpUntil(
        tester, () => c.read(currentUserProvider)?.id == memberB,
        what: 'B to be the signed-in member');
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  Finder activeCard() => find.text('My Active Challenges');

  Future<void> challengesAsA(WidgetTester tester) async {
    await show(tester, const ChallengesScreen());
    await pumpUntil(tester, () => activeCard().evaluate().isNotEmpty,
        what: "A's challenges");
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('1 active challenges'), findsOneWidget);
  }

  group('Challenges', () {
    testWidgets("B's read pending shows nothing of A; then B's own",
        (tester) async {
      await challengesAsA(tester);
      final hold = server.holds['GET challenges:$memberB'] = Completer<void>();
      await switchToB(tester);
      await pumpUntil(
          tester, () => server.calls.contains('GET challenges:$memberB'),
          what: "B's read");
      await tester.pump(const Duration(seconds: 1));
      expect(activeCard(), findsNothing,
          reason: "THE defect: A's joined challenge was shown to B");
      expect(find.text('Joined'), findsNothing);
      hold.complete();
      await pumpUntil(tester, () => activeCard().evaluate().isNotEmpty,
          what: "B's challenges");
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('1 active challenges'), findsOneWidget);
      expect(c.read(challengeNotifierProvider).where((x) => x.isJoined).single.id,
          'ch-2');
      await unmount(tester);
    });

    testWidgets("B's read failing shows the failure, and nothing of A",
        (tester) async {
      await challengesAsA(tester);
      server.fails.add('GET challenges:$memberB');
      await switchToB(tester);
      await pumpUntil(tester,
          () => find.text('Could not load challenges').evaluate().isNotEmpty,
          what: 'the failure');
      await tester.pump(const Duration(seconds: 1));
      expect(activeCard(), findsNothing);
      expect(find.text('Joined'), findsNothing,
          reason: "THE defect: A's list stayed under B");
      expect(find.text('— active challenges'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets("negative control: B's genuine empty list is said as empty",
        (tester) async {
      await challengesAsA(tester);
      server.challenges.clear();
      await switchToB(tester);
      await pumpUntil(
          tester, () => find.text('No challenges here').evaluate().isNotEmpty,
          what: 'the empty list');
      expect(find.text('Could not load challenges'), findsNothing);
      await unmount(tester);
    });
  });

  group('the opened challenge', () {
    Future<void> openAsA(WidgetTester tester) async {
      c.listen(challengeNotifierProvider, (_, __) {});
      await pumpUntil(
          tester, () => c.read(challengeNotifierProvider).isNotEmpty,
          what: "A's challenges");
      c.read(selectedChallengeProvider.notifier).state =
          c.read(challengeNotifierProvider).first;
      await show(tester, const ChallengeDetailScreen());
      expect(find.text('500 steps'), findsOneWidget,
          reason: "positive control: A's own progress");
    }

    testWidgets('does not stay on screen for the next member', (tester) async {
      await openAsA(tester);
      await switchToB(tester);
      expect(find.text('500 steps'), findsNothing,
          reason: "THE defect: A's progress was shown to B");
      expect(find.text('No challenge selected'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('control: stays through a session refresh', (tester) async {
      await openAsA(tester);
      await tester.runAsync(refreshSession);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('500 steps'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('the exercise opened to edit', () {
    testWidgets("B's create form is a create, not an edit of A's exercise",
        (tester) async {
      c.read(editingExerciseProvider.notifier).state = 'a-1'; // A taps Edit…
      await switchToB(tester); // …and B signs in before it opens.
      await show(tester, const CreateExerciseScreen());
      await pumpUntil(
          tester, () => find.text('Create Exercise').evaluate().isNotEmpty,
          what: 'a create form',
          timeout: const Duration(seconds: 5));
      expect(find.text('Edit Exercise'), findsNothing,
          reason: "THE defect: B was handed A's exercise to edit");
      expect(find.text('Alpha Press'), findsNothing);
      expect(server.calls, isNot(contains('GET custom_exercises:$memberB')),
          reason: "A's exercise is not read as B");
      await unmount(tester);
    });

    testWidgets('positive control: the right coach gets the prefilled edit',
        (tester) async {
      c.read(editingExerciseProvider.notifier).state = 'a-1';
      await tester.runAsync(refreshSession); // same coach, new session
      await tester.pump();
      await show(tester, const CreateExerciseScreen());
      await pumpUntil(
          tester, () => find.text('Alpha Press').evaluate().isNotEmpty,
          what: 'the prefill');
      expect(find.text('Edit Exercise'), findsOneWidget);
      expect(c.read(editingExerciseProvider), isNull,
          reason: 'consumed once, as before');
      await unmount(tester);
    });
  });
}
