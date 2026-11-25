import 'dart:typed_data';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/coach/data/coach_relationship_service.dart';
import 'package:circle_fitness/features/exercise_database/data/custom_exercise_service.dart';
import 'package:circle_fitness/features/exercise_database/data/models/exercise_detail_model.dart';
import 'package:circle_fitness/features/exercise_database/domain/exercise_database_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../support/coach_tools_server.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-59d · the coach tools' services write as the account that started the
// write, at every step, or not at all (W8, W9, W10, W12, W21) — and the
// exercise being looked at goes with its account (A-26).
//
// HOW TO SEE IT FAIL: `git checkout a82f993 -- apps/mobile/lib/features/coach/
// data apps/mobile/lib/features/exercise_database/{data,domain}`; only the
// controls pass. (The `expectedUid` parameters: coach_tool_expected_uid_test.)

void main() {
  final server = CoachToolsServer();
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(server);
  });

  setUp(() async {
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
    await signInAs(memberA);
  });
  tearDown(resetFailureSink);

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(done(), isTrue, reason: 'premise: the request was sent');
  }

  /// Runs [start], switches to B while the request [at] is in flight, lets it
  /// answer, and returns what [start] returned (or threw).
  Future<Object?> switchDuring(
      Future<Object?> Function() start, bool Function(Sent) at) async {
    final hold = server.hold(at);
    Object? out;
    final done = start().then((v) => out = v, onError: (Object e) => out = e);
    await until(() => server.log.any(at));
    await signInAs(memberB);
    hold.complete();
    await done;
    return out;
  }

  Matcher accountChanged() => isA<StateError>().having(
      (e) => e.message, 'message', contains('the signed-in account changed'));
  final accountMessage = contains('the signed-in account changed');

  group('CoachRelationshipService', () {
    late CoachRelationshipService svc;
    setUp(() => svc = CoachRelationshipService());

    test("cancelCoach: a switch after the subscriptions read ends nobody's coaching",
        () async {
      final out = await switchDuring(
          () => svc.cancelCoach('coach-1', 'client_cancelled', null),
          (s) => s.table == 'subscriptions');
      expect(out, accountChanged());
      expect(server.writesBy(memberB), isEmpty);
    });

    test('cancelCoach: a switch between two cancellations stops the second', () async {
      server.tables['subscriptions'] = [
        {'id': 'sub-1', 'user_id': memberA, 'coach_id': 'coach-1'},
        {'id': 'sub-2', 'user_id': memberA, 'coach_id': 'coach-1'},
      ];
      server.answers['cancel-subscription'] = {'ok': true, 'endsAt': '2027-01-01T00:00:00Z'};
      final out = await switchDuring(
          () => svc.cancelCoach('coach-1', 'client_cancelled', null),
          (s) => s.table == 'cancel-subscription');
      expect(out, accountChanged());
      expect(server.to('cancel-subscription'), hasLength(1));
    });

    test("cancelCoach: a switch after it ended — the coach is not told by B", () async {
      final out = await switchDuring(
          () => svc.cancelCoach('coach-1', 'client_cancelled', null),
          (s) => s.table == 'coach_client_relationships');
      expect(out, isA<CoachingEnd>(), reason: "A's coaching did end");
      expect(server.writesBy(memberB), isEmpty);
      expect(server.to('notifications'), isEmpty);
      expect(reported.map((f) => f.origin), ['CoachRelationshipService.cancelCoach.notify']);
      expect('${reported.single.error}', accountMessage);
    });

    test("cancelCoach: a switch while the client's name is read — nobody is told by B",
        () async {
      final out = await switchDuring(
          () => svc.cancelCoach('coach-1', 'client_cancelled', null),
          (s) => s.table == 'user_profiles');
      expect(out, isA<CoachingEnd>(), reason: "A's coaching did end");
      expect(server.to('notifications'), isEmpty);
      expect(server.writesBy(memberB), isEmpty);
      expect(reported.map((f) => f.origin), ['CoachRelationshipService.cancelCoach.notify']);
    });

    // A refusal written to be shown ("No active coaching…") that arrives after
    // the switch is not shown to whoever is signed in by then.
    final late = <String, (Future<Object?> Function(), String)>{
      'cancelCoach (nothing to end)': (
          () => svc.cancelCoach('coach-1', null, null), 'coach_client_relationships'),
      'cancelCoach (not cancelled)': (
          () => svc.cancelCoach('coach-1', null, null), 'cancel-subscription'),
      'setGlobalPrice': (() => svc.setGlobalPrice(150), 'user_profiles'),
    };
    late.forEach((name, c) {
      for (final switches in [true, false]) {
        test('$name: ${switches ? 'a refusal that lands late is the account changing'
            : 'control: the same account is told why'}', () async {
          server.zeroRows = (s) => true;
          server.answers['cancel-subscription'] = {'ok': false};
          if (c.$2 == 'cancel-subscription') {
            server.tables['subscriptions'] = [
              {'id': 'sub-1', 'user_id': memberA, 'coach_id': 'coach-1'},
            ];
          }
          Object? out;
          if (switches) {
            out = await switchDuring(c.$1, (s) => s.table == c.$2);
          } else {
            try {
              await c.$1();
            } catch (e) {
              out = e;
            }
          }
          expect(out, isA<StateError>());
          expect((out! as StateError).message, switches ? accountMessage : isNot(accountMessage));
          expect(server.writesBy(memberB), isEmpty);
        });
      }
    });

    // ── sec N-3 / N-4 / N-5 ──
    test('sendInvite: a switch after the insert — no email goes out as B', () async {
      final out = await switchDuring(
          () => svc.sendInvite(memberA, 'x@example.com'), (s) => s.table == 'coach_invites');
      expect(out, accountChanged());
      expect(server.to('send-invite-email'), isEmpty,
          reason: "A's prospect got B's name, B's reply-to and A's token");
      expect(server.writes.map((s) => s.who), [memberA]);
      expect(reported.map((f) => f.origin), ['CoachRelationshipService.sendInvite']);
      expect('${reported.single.error}', accountMessage);
    });

    test("sendInvite: for a coach who is not signed in nothing is sent", () async {
      await signInAs(memberB);
      await expectLater(svc.sendInvite(memberA, 'x@example.com'), throwsA(accountChanged()));
      await signOut();
      await expectLater(svc.sendInvite(memberA, 'x@example.com'), throwsA(accountChanged()));
      expect(server.log, isEmpty);
      expect(reported, hasLength(2));
    });

    test('sendInvite: the same coach, after a token refresh (control)', () async {
      server.answers['send-invite-email'] = {'sent': true};
      await refreshSession();
      await svc.sendInvite(memberA, 'x@example.com');
      expect(server.writes.map((s) => s.table), ['coach_invites', 'send-invite-email']);
      expect(server.writes.map((s) => s.who).toSet(), {memberA});
      expect(server.writes.first.json, {'coach_id': memberA, 'invitee_email': 'x@example.com'});
      expect(reported, isEmpty);
    });

    final answers = <String, Future<void> Function()>{
      'approveRequest': () => svc.approveRequest('rel-1', memberB),
      'declineRequest': () => svc.declineRequest('rel-1', memberB),
    };
    answers.forEach((name, answer) {
      test('$name: a switch after the update — the client is not told by B', () async {
        final out = await switchDuring(
            answer, (s) => s.table == 'coach_client_relationships');
        expect(out, isNull, reason: 'the answer is saved');
        expect(server.to('notifications'), isEmpty);
        expect(server.writes.map((s) => s.who), [memberA]);
        expect(reported.map((f) => f.origin), ['CoachRelationshipService.$name.notify']);
      });

      test('$name: an answer that matched nothing is not said to B', () async {
        server.zeroRows = (s) => true;
        final out = await switchDuring(
            answer, (s) => s.table == 'coach_client_relationships');
        expect(out, accountChanged(), reason: '"That request is no longer pending"');
        expect('$out', isNot(contains('pending')));
      });

      test('$name: the same coach, after a token refresh (control)', () async {
        await refreshSession();
        await answer();
        expect(server.writes.map((s) => '${s.table} ${s.who == memberA}'),
            ['coach_client_relationships true', 'notifications true']);
        expect(reported, isEmpty);
      });
    });

    test('requestCoach: a switch after the read — no request is made', () async {
      final out = await switchDuring(() => svc.requestCoach('coach-1'),
          (s) => s.table == 'coach_client_relationships');
      expect(out, accountChanged());
      expect(server.writes, isEmpty, reason: "A's request went out on B's session");
      expect(reported.map((f) => f.origin), ['CoachRelationshipService.requestCoach']);
    });

    test('requestCoach: "already your coach" is not said to B', () async {
      server.tables['coach_client_relationships'] = [
        {'client_id': memberA, 'coach_id': 'coach-1', 'status': 'active'},
      ];
      final out = await switchDuring(() => svc.requestCoach('coach-1'),
          (s) => s.table == 'coach_client_relationships');
      expect(out, accountChanged());
      expect(server.writes, isEmpty);
    });

    test('requestCoach: a switch after the request — the coach is not told by B',
        () async {
      final out = await switchDuring(() => svc.requestCoach('coach-1'),
          (s) => s.table == 'coach_client_relationships' && s.isWrite);
      expect(out, isNull, reason: 'the request is saved');
      expect(server.to('notifications'), isEmpty,
          reason: "a notification naming A's client id went out as B");
      expect(reported.map((f) => f.origin), ['CoachRelationshipService.requestCoach.notify']);
    });

    test('requestCoach: the same client, after a token refresh (control)', () async {
      await refreshSession();
      await svc.requestCoach('coach-1');
      expect(server.writes.map((s) => '${s.table} ${s.who == memberA}'),
          ['coach_client_relationships true', 'notifications true']);
      expect(reported, isEmpty);
    });

    test('cancelCoach: the same client ends it and the coach is told (control)',
        () async {
      await refreshSession(); // the same account
      await svc.cancelCoach('coach-1', 'client_cancelled', null);
      expect(server.writes.map((s) => s.table), ['coach_client_relationships', 'notifications']);
      expect(server.writes.map((s) => s.who).toSet(), {memberA});
    });
  });

  group('CustomExerciseService', () {
    late CustomExerciseService svc;
    setUp(() => svc = CustomExerciseService());

    final voice = <String, Future<Object?> Function()>{
      'uploadCoachVoice': () => svc.uploadCoachVoice('ex-1', Uint8List(4)),
      'setCoachVoice': () => svc.setCoachVoice('ex-1', 'voice/$memberA/x.m4a', 900, null),
    };
    for (final call in voice.keys) {
      test('$call: signed out is recorded, not just null', () async {
        await signOut();
        svc.lastError = null;
        expect(await voice[call]!(), anyOf(isNull, isFalse));
        expect(svc.lastError, isNotNull);
        expect(reported.map((f) => f.origin), ['CustomExerciseService.$call']);
      });
    }

    test('setCoachVoice: a write that stored no row is not a saved note', () async {
      server.zeroRows = (s) => true;
      expect(await svc.setCoachVoice('ex-1', 'voice/$memberA/x.m4a', 900, null), isFalse);
      expect(reported.map((f) => f.origin), ['CustomExerciseService.setCoachVoice']);
    });

    group('clearCoachVoice', () {
      setUp(() => server.tables['coach_exercise_media'] = [
            for (final u in [memberA, memberB])
              {'coach_id': u, 'exercise_id': 'ex-1', 'voice_url': 'voice/$u/x.m4a'},
          ]);

      test('a switch after the read removes no recording', () async {
        final out = await switchDuring(() => svc.clearCoachVoice('ex-1'),
            (s) => s.table == 'coach_exercise_media');
        expect(out, isFalse);
        expect(server.writes, isEmpty);
        expect(reported, hasLength(1));
      });
      test('a switch after the removal clears no row as B', () async {
        final out = await switchDuring(
            () => svc.clearCoachVoice('ex-1'), (s) => s.method == 'DELETE');
        expect(out, isFalse);
        expect(server.writesBy(memberB), isEmpty);
        expect(reported, hasLength(1));
      });
      test('negative control: no overlay row is nothing to clear', () async {
        server.tables.clear();
        expect(await svc.clearCoachVoice('ex-1'), isTrue);
        expect(server.writes, isEmpty);
        expect(reported, isEmpty);
      });
    });

    group('createExercise', () {
      Future<String?> create() => svc.createExercise(
          name: 'Goblet Squat', category: 'Strength', muscleGroup: 'Quads',
          secondaryMuscles: const [], equipment: 'Kettlebell', difficulty: 'Beginner',
          description: '', instructions: const [], coachingCues: const [],
          commonMistakes: const [], alternatives: const [], tags: const [],
          videoVariants: const []);

      for (final exists in [false, true]) {
        test('a switch after the name check writes nothing as B '
            '(${exists ? 'update' : 'insert'})', () async {
          if (exists) {
            server.tables['custom_exercises'] = [
              {'id': 'ex-a', 'coach_id': memberA, 'slug': 'goblet-squat'}
            ];
          }
          final out =
              await switchDuring(create, (s) => s.table == 'custom_exercises');
          expect(out, isNull);
          expect(server.writes, isEmpty);
          expect(reported.map((f) => f.origin), ['CustomExerciseService.createExercise']);
        });
      }
      test('the same coach creates (control)', () async {
        expect(await create(), 'row-1');
        expect(server.writes.single.json, containsPair('coach_id', memberA));
        expect(reported, isEmpty);
      });
    });
  });

  group('A-26 · selectedExerciseDetailProvider', () {
    final ex = ExerciseDetail(
      id: 'a-private', name: 'A private', category: 'Strength', muscleGroup: 'Back',
      secondaryMuscles: [], equipment: 'Cable', difficulty: 'Intermediate',
      description: '', instructions: [], coachingCues: [], commonMistakes: [],
      alternatives: [], tags: [],
    );
    late ProviderContainer c;
    setUp(() async {
      c = ProviderContainer();
      c.listen(selectedExerciseDetailProvider, (_, __) {});
      c.listen(currentUserProvider, (_, __) {});
      await Future<void>.delayed(Duration.zero);
      c.read(selectedExerciseDetailProvider.notifier).state = ex;
    });
    tearDown(() => c.dispose());

    test("A→B: A's exercise is not B's", () async {
      await signInAs(memberB);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(selectedExerciseDetailProvider), isNull);
    });
    test('signed out: gone', () async {
      await signOut();
      await Future<void>.delayed(Duration.zero);
      expect(c.read(selectedExerciseDetailProvider), isNull);
    });
    // Round 3 · asked for, or invalidated, while the change has not been
    // flushed (no frame; this container never schedules one).
    for (final invalidated in [false, true]) {
      test("unflushed${invalidated ? ' and invalidated' : ''}: it is never A's for B",
          () async {
        final seen = <String?>[];
        final auth = Supabase.instance.client.auth;
        final sub = auth.onAuthStateChange.listen((_) {
          if (auth.currentUser?.id != memberB) return;
          // Riverpod's own listener on the stream came first; nothing is flushed.
          if (invalidated) c.invalidate(selectedExerciseDetailProvider);
          seen.add(c.read(selectedExerciseDetailProvider)?.id);
        });
        addTearDown(sub.cancel);
        await Future<void>.delayed(Duration.zero);
        c.listen(selectedExerciseDetailProvider, (_, v) => seen.add(v?.id));
        await signInAs(memberB);
        expect(seen, isNotEmpty, reason: 'premise');
        expect(seen.whereType<String>(), isEmpty);
        await Future<void>.delayed(Duration.zero);
        expect(c.read(selectedExerciseDetailProvider), isNull);
        // B's own stays through B's token refresh.
        c.read(selectedExerciseDetailProvider.notifier).state = ex;
        await refreshSession();
        expect(c.read(selectedExerciseDetailProvider), same(ex));
      });
    }
    test('a token refresh keeps it (control)', () async {
      await refreshSession();
      await Future<void>.delayed(Duration.zero);
      expect(c.read(selectedExerciseDetailProvider), same(ex));
    });
  });
}
