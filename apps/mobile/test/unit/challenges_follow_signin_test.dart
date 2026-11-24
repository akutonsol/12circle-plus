import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/challenges/data/models/challenge_model.dart';
import 'package:circle_fitness/features/challenges/domain/challenge_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/two_member_postgrest.dart';

// P0-FL-57a (a) · the challenge list belongs to the member signed in NOW.
//
// `challengeNotifierProvider` was built once for the app's lifetime. After A
// signed out and B signed in it kept A's list — A's joined state, progress and
// "You" on the board — until B's read landed, and for good if it failed. A
// join A had in flight marked B's list joined. The opened challenge
// (`selectedChallengeProvider`) outlived the switch too.
//
// Every transition here is a REAL one on the Supabase auth stream, through the
// real `currentUserProvider` and the real services.
//
// HOW TO SEE IT FAIL: `git checkout f191d48 -- apps/mobile/lib/features/
// challenges/domain/challenge_provider.dart`.

Map<String, Object?> _row(String id) => {
      'id': id,
      'title': 'Challenge $id',
      'description': '',
      'type': 'steps',
      'status': 'active',
      'target_value': 1000,
      'unit': 'steps',
    };

void main() {
  late TwoMemberPostgrest server;
  late ProviderContainer c;
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = TwoMemberPostgrest();
    await initTwoMemberSupabase(server);
  });

  setUp(() async {
    server.reset();
    server.challenges.addAll([_row('ch-1'), _row('ch-2')]);
    server.participants.addAll([
      {'challenge_id': 'ch-1', 'user_id': memberA, 'current_progress': 500},
      {'challenge_id': 'ch-2', 'user_id': memberB, 'current_progress': 42},
    ]);
    reported.clear();
    setFailureSink(reported.add);
    await signInAs(memberA);
    c = ProviderContainer();
    c.listen(challengeNotifierProvider, (_, __) {});
  });

  tearDown(() async {
    for (final h in server.holds.values) {
      if (!h.isCompleted) h.complete();
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
    c.dispose();
    resetFailureSink();
  });

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 60));
  List<Challenge> list() => c.read(challengeNotifierProvider);
  Challenge of(String id) => list().firstWhere((x) => x.id == id);
  List<String> joined() => [
        for (final x in list())
          if (x.isJoined) '${x.id}:${x.myProgress.toInt()}'
      ];

  Future<void> asA() async {
    await settle();
    expect(joined(), ['ch-1:500'], reason: "premise: A's own list");
  }

  test("B's read pending: nothing of A; then B's own list", () async {
    await asA();
    final hold = server.holds['GET challenges:$memberB'] = Completer<void>();
    await signInAs(memberB);
    await settle();
    expect(server.calls, contains('GET challenges:$memberB'));
    expect(list(), isEmpty, reason: "THE defect: A's list was shown to B");
    expect(c.read(activeChallengesProvider), isEmpty);
    hold.complete();
    await settle();
    expect(joined(), ['ch-2:42'], reason: "B's own data shows");
    expect(of('ch-2').leaderboard.single.isMe, isTrue);
  });

  test("B's read fails: nothing of A, ever", () async {
    await asA();
    server.fails.add('GET challenges:$memberB');
    await signInAs(memberB);
    await settle();
    expect(list(), isEmpty, reason: "THE defect: A's list stayed for good");
    expect(c.read(liveChallengesProvider), isA<AsyncError<List<Challenge>>>(),
        reason: 'the screens say it failed');
    // …and a retry shows B's.
    server.fails.clear();
    c.invalidate(liveChallengesProvider);
    await settle();
    expect(joined(), ['ch-2:42']);
  });

  test('sign-out drops the list; signing in again shows the member theirs',
      () async {
    await asA();
    server.holds['GET challenges:anon'] = Completer<void>();
    await signOut();
    await settle();
    expect(list(), isEmpty, reason: "THE defect: A's list outlived sign-out");
    await signInAs(memberB);
    await settle();
    expect(joined(), ['ch-2:42']);
    await signOut();
    await signInAs(memberA);
    await settle();
    expect(joined(), ['ch-1:500']);
  });

  test("A's held response landing after B signs in is dropped", () async {
    await asA();
    final holdA = server.holds['GET challenges:$memberA'] = Completer<void>();
    final holdB = server.holds['GET challenges:$memberB'] = Completer<void>();
    c.invalidate(liveChallengesProvider); // A's refresh, in flight
    await settle();
    await signInAs(memberB);
    await settle();
    holdA.complete(); // A's answer, late, while B's is pending
    await settle();
    expect(list(), isEmpty, reason: "A's late answer re-filled the list");
    holdB.complete();
    await settle();
    expect(joined(), ['ch-2:42']);
  });

  test("A's held response landing after B's list does not replace it",
      () async {
    await asA();
    final holdA = server.holds['GET challenges:$memberA'] = Completer<void>();
    c.invalidate(liveChallengesProvider);
    await settle();
    await signInAs(memberB);
    await settle();
    expect(joined(), ['ch-2:42']);
    holdA.complete();
    await settle();
    expect(joined(), ['ch-2:42']);
  });

  test("A's join completing after B signs in does not mark B's list", () async {
    await asA();
    final hold = server.holds['POST challenge_participants:$memberA'] =
        Completer<void>();
    final join =
        c.read(challengeNotifierProvider.notifier).joinChallenge('ch-1');
    await settle();
    await signInAs(memberB);
    await settle();
    expect(joined(), ['ch-2:42']);
    hold.complete();
    expect(await join, isTrue, reason: 'the join itself was made, for A');
    await settle();
    expect(joined(), ['ch-2:42'], reason: 'THE defect: B was shown as joined');
    expect(of('ch-1').participantCount, 1);
  });

  test("A's progress landing after B signs in does not change B's", () async {
    await asA();
    final hold = server.holds['POST challenge_participants:$memberA'] =
        Completer<void>();
    final update =
        c.read(challengeNotifierProvider.notifier).updateProgress('ch-2', 0.5);
    await settle();
    await signInAs(memberB);
    await settle();
    hold.complete();
    await update;
    expect(joined(), ['ch-2:42'],
        reason: "THE defect: A's progress on B's list");
  });

  test("A's join failing after B signs in is recorded and leaves B alone",
      () async {
    await asA();
    final hold = server.holds['POST challenge_participants:$memberA'] =
        Completer<void>();
    server.fails.add('POST challenge_participants:$memberA');
    final join =
        c.read(challengeNotifierProvider.notifier).joinChallenge('ch-1');
    await settle();
    await signInAs(memberB);
    await settle();
    hold.complete();
    expect(await join, isFalse);
    expect(reported.map((f) => f.origin),
        contains('ChallengeNotifier.joinChallenge'));
    expect(c.read(challengeNotifierProvider.notifier).lastJoinError, isNull,
        reason: "THE defect: A's error was B's last join error");
    expect(joined(), ['ch-2:42']);
  });

  test('positive control: the same member joining is shown at once', () async {
    await asA();
    final ok =
        await c.read(challengeNotifierProvider.notifier).joinChallenge('ch-2');
    expect(ok, isTrue);
    expect(joined(), ['ch-1:500', 'ch-2:0']);
    expect(of('ch-2').participantCount, 2);
  });

  test(
      'control: a session refresh is the same member — nothing is dropped, '
      'and a join across it is shown', () async {
    await asA();
    final before = c.read(currentUserProvider);
    final hold = server.holds['POST challenge_participants:$memberA'] =
        Completer<void>();
    // The re-read a changed User triggers must not be what shows the join.
    server.holds['GET challenges:$memberA'] = Completer<void>();
    final notifier = c.read(challengeNotifierProvider.notifier);
    final join = notifier.joinChallenge('ch-2');
    await settle();
    await refreshSession();
    await settle();
    expect(c.read(currentUserProvider) == before, isFalse, reason: 'premise');
    expect(joined(), ['ch-1:500']);
    hold.complete();
    expect(await join, isTrue);
    expect(joined(), ['ch-1:500', 'ch-2:0']);
    expect(identical(c.read(challengeNotifierProvider.notifier), notifier),
        isTrue);
  });

  test('control: a failed refresh for the same member keeps their list',
      () async {
    await asA();
    server.fails.add('GET challenges:$memberA');
    c.invalidate(liveChallengesProvider);
    await settle();
    expect(c.read(liveChallengesProvider).hasError, isTrue);
    expect(joined(), ['ch-1:500']);
  });

  test('negative control: B genuinely has no challenges — empty, no error',
      () async {
    await asA();
    server.challenges.clear();
    await signInAs(memberB);
    await settle();
    expect(list(), isEmpty);
    expect(c.read(liveChallengesProvider), isA<AsyncData<List<Challenge>>>());
    expect(reported, isEmpty);
  });

  group('the opened challenge', () {
    test('is not kept for the next member, nor through sign-out', () async {
      await asA();
      c.read(selectedChallengeProvider.notifier).state = of('ch-1');
      await signInAs(memberB);
      await settle();
      expect(c.read(selectedChallengeProvider), isNull,
          reason: "THE defect: B's challenge page was A's, with A's progress");
      c.read(selectedChallengeProvider.notifier).state = of('ch-2');
      expect(c.read(selectedChallengeProvider)!.myProgress, 42);
      await signOut();
      await settle();
      expect(c.read(selectedChallengeProvider), isNull);
    });

    test('control: is kept for the same member through a session refresh',
        () async {
      await asA();
      c.read(selectedChallengeProvider.notifier).state = of('ch-1');
      await refreshSession();
      await settle();
      expect(c.read(selectedChallengeProvider)!.myProgress, 500);
    });
  });
}
