import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/coach/domain/coach_provider.dart';
import 'package:circle_fitness/features/payments/domain/payment_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/coach_change_server.dart';
import '../support/two_member_postgrest.dart';

// P0-RM-1 (C14-62b-03) · `assignedCoachProvider` watched the whole User and
// held the last member's coach through the next one's read.
//
//  * B's read pending / failed: A's coach was still the value every
//    `valueOrNull` reader drew (name, avatar, Cancel);
//  * a token refresh (a new User, the same member) re-read it;
//  * A's answer landing after B signed in must never become anybody's coach.
//
// No ProviderContainer per account (no AccountScope): one container across the
// real A -> B switch on the real auth client.
//
// HOW TO SEE IT FAIL: `git checkout 6d1611d --
// lib/features/coach/domain/coach_provider.dart` (the `ownedAssigned…` cases
// then do not compile: run the others by name).

const _a = memberA;
const _b = memberB;
const _rel = 'coach_client_relationships';

void main() {
  final server = CoachChangeServer();
  final reported = <AppFailure>[];
  late ProviderContainer c;
  late List<AsyncValue<Map<String, dynamic>?>> seenStates;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(server);
  });

  setUp(() async {
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
    server.coachOf[_a] = 'c-a';
    server.coachOf[_b] = 'c-b';
    server.profiles['c-a'] = {'id': 'c-a', 'first_name': 'Anna'};
    server.profiles['c-b'] = {'id': 'c-b', 'first_name': 'Bea'};
    await signInAs(_a);
    c = ProviderContainer();
    seenStates = [];
    c.listen(assignedCoachProvider, (_, v) => seenStates.add(v),
        fireImmediately: true);
  });

  tearDown(() async {
    for (final g in server.gates.values) {
      if (!g.isCompleted) g.complete();
    }
    c.dispose();
    resetFailureSink();
    await signOut();
  });

  Future<void> turns([int n = 40]) async {
    for (var i = 0; i < n; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> until(bool Function() ok, String what) async {
    final clock = Stopwatch()..start();
    while (!ok()) {
      if (clock.elapsed > const Duration(seconds: 20)) fail('never: $what');
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
  }

  String? name(AsyncValue<Map<String, dynamic>?> v) =>
      v.hasValue ? (v.value?['first_name'] as String?) : null;

  Future<void> aLoaded() async {
    await until(() => name(c.read(assignedCoachProvider)) == 'Anna', "A's coach");
    seenStates.clear();
  }

  int relReads(String who) =>
      server.named(_rel, method: 'GET', who: who).length;

  test("B's read pending: A's coach is no value at all, not even a held one",
      () async {
    await aLoaded();
    server.gates['GET $_rel:$_b'] = Completer();
    await signInAs(_b);
    await until(() => relReads(_b) == 1, "B's read");
    await turns();
    final now = c.read(assignedCoachProvider);
    expect(name(now), isNull,
        reason: "THE defect: A's coach (Anna) was held while B's read ran");
    expect(now.isLoading, isTrue, reason: 'not read is not "no coach"');
    expect(seenStates.map(name), everyElement(isNot('Anna')));
    server.gates['GET $_rel:$_b']!.complete();
    await until(() => name(c.read(assignedCoachProvider)) == 'Bea', "B's coach");
  });

  test("B's read failed: an error, with nothing of A's in it", () async {
    await aLoaded();
    server.failing.add('GET $_rel:$_b');
    await signInAs(_b);
    await until(() => c.read(assignedCoachProvider).hasError, "B's failure");
    final now = c.read(assignedCoachProvider);
    expect(name(now), isNull, reason: "THE defect: B's failure carried A's coach");
    expect(seenStates.map(name), everyElement(isNot('Anna')));
  });

  test("A's answer landing after B signed in is never anybody's coach",
      () async {
    await aLoaded();
    // A re-reads (a refresh), and its profile answer is held …
    final hold = server.gates['GET public_profiles:$_a'] = Completer();
    c.invalidate(assignedCoachProvider);
    await until(() => server.named('public_profiles', who: _a).length == 2,
        "A's second read");
    // … while B signs in and is answered.
    await signInAs(_b);
    await until(() => name(c.read(assignedCoachProvider)) == 'Bea', "B's coach");
    hold.complete();
    await turns();
    expect(name(c.read(assignedCoachProvider)), 'Bea');
    expect(seenStates.skipWhile((v) => name(v) != 'Bea').map(name),
        everyElement(isNot('Anna')));
  });

  test('signed out: no coach, and nothing of A held', () async {
    await aLoaded();
    await signOut();
    await until(() => c.read(assignedCoachProvider).hasValue &&
        !c.read(assignedCoachProvider).isLoading &&
        name(c.read(assignedCoachProvider)) == null, 'signed out');
    expect(seenStates.map(name), everyElement(isNot('Anna')));
  });

  test('control: a token refresh (same member, new User) reads nothing again '
      'and the coach stays, never loading', () async {
    await aLoaded();
    final before = relReads(_a);
    await refreshSession();
    await turns();
    expect(relReads(_a), before,
        reason: 'THE defect: a token refresh re-read the coach');
    expect(name(c.read(assignedCoachProvider)), 'Anna');
    expect(seenStates.where((v) => v.isLoading), isEmpty, reason: 'flicker');
  });

  test('control: the same member out and back in reads it again, as them',
      () async {
    await aLoaded();
    await signOut();
    await turns();
    await signInAs(_a);
    await until(() => name(c.read(assignedCoachProvider)) == 'Anna', 'again');
    expect(server.named(_rel, method: 'GET').map((r) => r.who),
        everyElement(_a));
  });

  group('ownedAssignedCoachProvider (what screens draw)', () {
    setUp(() => c.listen(ownedAssignedCoachProvider, (_, __) {}));

    OwnedRead<Map<String, dynamic>?> owned() => c.read(ownedAssignedCoachProvider);

    test("B pending, then B failed: A's coach never in it; B's failure is, "
        'recorded once', () async {
      await aLoaded();
      expect(owned().value?['first_name'], 'Anna');
      final gate = server.gates['GET $_rel:$_b'] = Completer();
      server.failing.add('GET $_rel:$_b');
      await signInAs(_b);
      await until(() => relReads(_b) == 1, "B's read");
      await turns();
      expect(owned().hasValue, isFalse);
      expect(owned().value, isNull);
      gate.complete();
      await until(() => owned().error != null, "B's failure");
      expect(owned().value, isNull);
      expect(reported.where((f) => f.origin == 'assignedCoach'), hasLength(1));
    });

    test("control: the member's own coach stays through a token refresh", () async {
      await aLoaded();
      await refreshSession();
      await turns();
      expect(owned().value?['first_name'], 'Anna');
      expect(reported, isEmpty);
    });
  });
}
