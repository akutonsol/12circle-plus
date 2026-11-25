import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/core/realtime/realtime.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/challenges/domain/challenge_provider.dart';
import 'package:circle_fitness/features/classes/domain/class_provider.dart';
import 'package:circle_fitness/features/classes/domain/whats_on.dart';
import 'package:circle_fitness/features/classes/domain/whats_on_provider.dart';
import 'package:circle_fitness/features/dashboard/domain/still_reading.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/two_coach_postgrest.dart';

// P0-FL-59f (A-25) · "What's on" folds three reads into one list and counted a
// read that is loading over an earlier answer as settled — so the next member's
// list was the previous member's, with their "Booked" and "Joined", until the
// next member's own read landed.
//
// HOW TO SEE IT FAIL: `git checkout bde92ae -- lib/features/classes`.

void main() {
  late TwoCoachPostgrest server;
  late ProviderContainer c;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = TwoCoachPostgrest();
    await initTwoMemberSupabase(server);
  });

  Future<void> until(bool Function() ok, String what) async {
    for (var i = 0; i < 400 && !ok(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(ok(), isTrue, reason: 'never: $what');
  }

  AsyncValue<WhatsOn> now() => c.read(whatsOnProvider);
  bool settled() =>
      now() is AsyncData &&
      !c.read(liveClassesFromDbProvider).isLoading &&
      !c.read(liveChallengesProvider).isLoading &&
      !c.read(whatsOnEventsProvider).isLoading;
  List<String?> actions() => now().hasValue
      ? [for (final i in now().requireValue.items) i.action]
      : const [];

  setUp(() async {
    server.reset();
    setFailureSink((_) {});
    final day = DateTime.now().toUtc();
    for (final who in [memberA, memberB]) {
      server
        ..seed('classes', who, [
          {
            'id': 'k-1',
            'title': 'Spin',
            'type': 'hiit',
            'is_online': true,
            'capacity': 10,
            'scheduled_at': day.add(const Duration(days: 1)).toIso8601String(),
          }
        ])
        ..seed('challenges', who, [
          {
            'id': 'ch-1',
            'title': 'Steps',
            'type': 'steps',
            'status': 'active',
            'is_active': true,
            'start_date': day
                .subtract(const Duration(days: 1))
                .toIso8601String()
                .split('T')[0],
            'end_date':
                day.add(const Duration(days: 9)).toIso8601String().split('T')[0],
          }
        ]);
    }
    server
      ..seed('class_bookings', memberA, [
        {'class_id': 'k-1', 'user_id': memberA, 'status': 'confirmed'}
      ])
      ..seed('challenge_participants', memberA, [
        {'challenge_id': 'ch-1', 'user_id': memberA, 'progress': 1}
      ]);
    await signInAs(memberA);
    c = ProviderContainer(overrides: [
      tableTickerProvider.overrideWith((ref, t) => Stream.value(0)),
    ]);
    c.listen(currentUserProvider, (_, __) {});
    await until(() => c.read(currentUserProvider)?.id == memberA, 'A');
    c.listen(whatsOnProvider, (_, __) {});
    await until(settled, "A's list");
    expect(actions(), containsAll(['Booked', 'Joined']), reason: 'premise');
  });

  tearDown(() {
    resetFailureSink();
    c.dispose();
  });

  Future<void> becomes(String? uid) async {
    await (uid == null ? signOut() : signInAs(uid));
    await until(() => c.read(currentUserProvider)?.id == uid, 'signed in $uid');
    await pumpEventQueue();
  }

  for (final (source, theirs) in [
    ('classes', 'Booked'),
    ('challenges', 'Joined'),
  ]) {
    group(source, () {
      test("B's read out: nothing of A's, and no settled list", () async {
        final seen = <String?>{};
        c.listen(whatsOnProvider, (_, __) => seen.addAll(actions()));
        final hold = server.holds['GET $source:$memberB'] = Completer<void>();
        await becomes(memberB);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(actions(), isNot(contains(theirs)),
            reason: "THE defect: A's rows were B's What's on");
        expect(now(), isA<AsyncLoading<WhatsOn>>());
        hold.complete();
        await until(settled, "B's own");
        expect(actions(), hasLength(2));
        expect(actions(), isNot(contains(theirs)));
        expect(seen, isNot(contains(theirs)), reason: 'not for one build');
      });

      test("B's read fails: B's failure, none of A's rows", () async {
        server.fails.add('GET $source:$memberB');
        await becomes(memberB);
        await until(settled, 'B');
        expect(now().requireValue.failed, hasLength(1));
        expect(actions(), isNot(contains(theirs)));
      });

      test("A's failure is not B's while B's read is out", () async {
        server.fails.add('GET $source:$memberA');
        c
          ..invalidate(liveClassesFromDbProvider)
          ..invalidate(liveChallengesProvider);
        await until(
            () => settled() && now().requireValue.failed.isNotEmpty, 'A fails');
        server.holds['GET $source:$memberB'] = Completer<void>();
        await becomes(memberB);
        expect(now(), isA<AsyncLoading<WhatsOn>>(),
            reason: "THE defect: A's failure was said to B");
      });

      test('signed out, then B: nothing of A\'s', () async {
        await becomes(null);
        server.holds['GET $source:$memberB'] = Completer<void>();
        await becomes(memberB);
        expect(actions(), isNot(contains(theirs)));
      });

      test("control: the member's own re-read holds the list, and a failed one "
          'says so', () async {
        final hold = server.holds['GET $source:$memberA'] = Completer<void>();
        c
          ..invalidate(liveClassesFromDbProvider)
          ..invalidate(liveChallengesProvider);
        c.read(refreshClassesProvider.notifier).state++; // after a booking
        await pumpEventQueue();
        expect(actions(), containsAll(['Booked', 'Joined']),
            reason: 'no flash back to a spinner');
        server.fails.add('GET $source:$memberA');
        hold.complete();
        await until(settled, 'failed');
        expect(now().requireValue.failed, hasLength(1));
      });
    });
  }

  test("settled class rows marked for A are not B's, however they came; rows "
      "nobody marked are nobody's; their own are theirs", () async {
    final rows = c.read(liveClassesFromDbProvider).requireValue;
    await becomes(memberB);
    for (final (held, shown) in [
      (ownedBy(memberA, rows), false),
      (rows.toList(), false),
      (ownedBy(memberB, rows), true),
    ]) {
      final other = ProviderContainer(overrides: [
        liveClassesFromDbProvider.overrideWith((ref) async => held),
        tableTickerProvider.overrideWith((ref, t) => Stream.value(0)),
      ]);
      other.listen(whatsOnProvider, (_, __) {});
      await until(
          () =>
              other.read(liveClassesFromDbProvider) is AsyncData &&
              !other.read(liveChallengesProvider).isLoading &&
              !other.read(whatsOnEventsProvider).isLoading,
          'read');
      final v = other.read(whatsOnProvider);
      expect(
          v.hasValue && v.requireValue.items.any((i) => i.action == 'Booked'),
          shown);
      other.dispose();
    }
  });

  // Round 3: the guard at 956c12e asked who last SETTLED, not whose rows.
  for (final (source, theirs) in [
    ('classes', 'Booked'),
    ('challenges', 'Joined'),
  ]) {
    void reread() {
      c.read(refreshClassesProvider.notifier).state++;
      c.invalidate(liveChallengesProvider);
    }

    test("SEC1/SEC6 $source: B failed, then B's own re-read is out: the "
        "failure stays, none of A's rows", () async {
      server.fails.add('GET $source:$memberB');
      await becomes(memberB);
      await until(settled, 'B failed');
      server.fails.clear();
      final hold = server.holds['GET $source:$memberB'] = Completer<void>();
      reread();
      await pumpEventQueue();
      expect(actions(), isNot(contains(theirs)),
          reason: "THE defect: A's rows were B's after one Try again");
      expect(now().hasValue && now().requireValue.failed.length == 1, isTrue,
          reason: "B's own failure stays until B's read answers");
      hold.complete();
      await until(() => settled() && now().requireValue.failed.isEmpty, 'B');
      expect(actions(), isNot(contains(theirs)));
    });

    test('SEC2 $source: B failed, then a token refresh', () async {
      server.fails.add('GET $source:$memberB');
      await becomes(memberB);
      await until(settled, 'B failed');
      server.holds['GET $source:$memberB'] = Completer<void>();
      final user = c.read(currentUserProvider);
      await refreshSession();
      await until(() => c.read(currentUserProvider) != user, 'a new User');
      await pumpEventQueue();
      expect(actions(), isNot(contains(theirs)));
    });

    test('$source invalidated as the account changes, before anything is '
        "flushed: an AsyncData of A's is not B's", () async {
      server.holds['GET $source:$memberB'] = Completer<void>();
      final seen = <String?>{};
      c.listen(whatsOnProvider, (_, __) => seen.addAll(actions()));
      c.listen(currentUserProvider, (_, u) {
        if (u?.id != memberB) return;
        c
          ..invalidate(liveClassesFromDbProvider)
          ..invalidate(liveChallengesProvider);
      });
      await becomes(memberB);
      expect(actions(), isNot(contains(theirs)));
      expect(seen, isNot(contains(theirs)));
    });
  }

  test('SEC3: B settled and closed the list, A settled elsewhere, B is back',
      () async {
    c.dispose();
    c = ProviderContainer(overrides: [
      tableTickerProvider.overrideWith((ref, t) => Stream.value(0)),
    ]);
    c.listen(currentUserProvider, (_, __) {});
    await becomes(memberB);
    final screen = c.listen(whatsOnProvider, (_, __) {});
    await until(settled, 'B');
    screen.close();
    await becomes(memberA);
    c.listen(liveChallengesProvider, (_, __) {});
    c.listen(liveClassesFromDbProvider, (_, __) {});
    await until(
        () =>
            c.read(liveChallengesProvider) is AsyncData &&
            !c.read(liveChallengesProvider).isLoading &&
            c.read(liveClassesFromDbProvider) is AsyncData &&
            !c.read(liveClassesFromDbProvider).isLoading,
        'A elsewhere');
    server.holds['GET challenges:$memberB'] = Completer<void>();
    server.holds['GET classes:$memberB'] = Completer<void>();
    await becomes(memberB);
    c.listen(whatsOnProvider, (_, __) {});
    await pumpEventQueue();
    expect(actions(), isNot(contains('Joined')));
    expect(actions(), isNot(contains('Booked')));
  });

  test("control: the member's own failed refresh, then a good one", () async {
    server.fails.addAll(['GET classes:$memberA', 'GET challenges:$memberA']);
    c.read(refreshClassesProvider.notifier).state++;
    c.invalidate(liveChallengesProvider);
    await until(() => settled() && now().requireValue.failed.length == 2, 'f');
    server.fails.clear();
    c.read(refreshClassesProvider.notifier).state++;
    c.invalidate(liveChallengesProvider);
    await until(() => settled() && now().requireValue.failed.isEmpty, 'ok');
    expect(actions(), containsAll(['Booked', 'Joined']));
  });

  test('control: a refreshed token holds the list, and re-reads no classes',
      () async {
    final before = server.count('GET classes:$memberA');
    final user = c.read(currentUserProvider);
    final states = <AsyncValue<WhatsOn>>[];
    c.listen(whatsOnProvider, (_, v) => states.add(v));
    await refreshSession();
    await until(() => c.read(currentUserProvider) != user, 'a new User');
    await until(settled, 'settled');
    expect(server.count('GET classes:$memberA'), before);
    expect(states.where((v) => !v.hasValue), isEmpty);
    expect(actions(), containsAll(['Booked', 'Joined']));
  });

  test('control: the same member signing out and back in reads their own',
      () async {
    await becomes(null);
    await becomes(memberA);
    await until(settled, 'A');
    expect(actions(), containsAll(['Booked', 'Joined']));
  });
}
