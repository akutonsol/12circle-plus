import 'dart:typed_data';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/coach/data/coach_relationship_service.dart';
import 'package:circle_fitness/features/exercise_database/data/custom_exercise_service.dart';
import 'package:circle_fitness/features/exercise_database/data/models/exercise_detail_model.dart';
import 'package:circle_fitness/features/exercise_database/domain/exercise_database_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
    test('a token refresh keeps it (control)', () async {
      await refreshSession();
      await Future<void>.delayed(Duration.zero);
      expect(c.read(selectedExerciseDetailProvider), same(ex));
    });
  });
}
