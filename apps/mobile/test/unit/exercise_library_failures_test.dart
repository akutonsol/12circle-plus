import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/exercise_database/data/custom_exercise_service.dart';
import 'package:circle_fitness/features/exercise_database/data/models/exercise_detail_model.dart';
import 'package:circle_fitness/features/exercise_database/domain/custom_exercise_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/failing_reads_postgrest.dart';
import '../support/held_reads_postgrest.dart';
import '../support/row_checking_postgrest.dart';

// P0-FL-53a · Coach Focus reads, cue-pack saves and global-library
// submission stop turning a failure into "nothing there" / "done".
//
//  * getCoachOverlay / resolveExerciseMedia caught everything and returned
//    null — the same answer as "no overlay" — with nothing recorded.
//  * createCoachingPack's insert never asked for its row back and nothing
//    was recorded on failure.
//  * submitForGlobalLibrary's update never asked for its row back: an
//    RLS-filtered update (0 rows, no error) counted as "submitted".
//
// HOW TO SEE THEM FAIL: `git checkout b7ec6ef -- apps/mobile/lib/features/
// exercise_database/data/custom_exercise_service.dart`.

const _uid = '00000000-0000-4000-8000-0000000f5053';

void main() {
  late HeldReadsPostgrest server;
  final reported = <AppFailure>[];
  late CustomExerciseService svc;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = HeldReadsPostgrest(_uid);
    await initSignedInSupabase(server);
  });

  setUp(() {
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
    svc = CustomExerciseService();
  });
  tearDown(resetFailureSink);

  List<String> origins() => reported.map((f) => f.origin).toList();

  group('getCoachOverlay', () {
    test('a failed read is recorded and rethrown — not "no overlay"', () async {
      server.failReads['coach_exercise_media'] = ReadFailure.server;
      await expectLater(
          svc.getCoachOverlay('ex-1'), throwsA(isA<PostgrestException>()));
      expect(origins(), ['CustomExerciseService.getCoachOverlay']);
    });

    test('a network failure is rethrown as itself (for the hint)', () async {
      server.failReads['coach_exercise_media'] = ReadFailure.network;
      await expectLater(
          svc.getCoachOverlay('ex-1'), throwsA(isA<http.ClientException>()));
    });

    test('negative control: no overlay is null, nothing recorded', () async {
      expect(await svc.getCoachOverlay('ex-1'), isNull);
      expect(reported, isEmpty);
    });

    test('positive control: an overlay is returned', () async {
      server.reads['coach_exercise_media'] = {
        'coach_id': _uid,
        'exercise_id': 'ex-1',
        'focus': ['Brace'],
      };
      expect((await svc.getCoachOverlay('ex-1'))!['focus'], ['Brace']);
      expect(reported, isEmpty);
    });
  });

  group('resolveExerciseMedia', () {
    test('a failed read is recorded and rethrown — not "no overlay"', () async {
      server.rpcFailures['resolve_exercise_media'] = ReadFailure.server;
      await expectLater(
          svc.resolveExerciseMedia('ex-1'), throwsA(isA<PostgrestException>()));
      expect(origins(), ['CustomExerciseService.resolveExerciseMedia']);
    });

    test('negative control: has_coach_overlay false is returned as is', () async {
      server.rpcAnswers['resolve_exercise_media'] = {'has_coach_overlay': false};
      expect(await svc.resolveExerciseMedia('ex-1'), {'has_coach_overlay': false});
      expect(reported, isEmpty);
    });

    test('positive control: an overlay is returned', () async {
      server.rpcAnswers['resolve_exercise_media'] = {
        'has_coach_overlay': true,
        'focus': ['Brace'],
      };
      expect((await svc.resolveExerciseMedia('ex-1'))!['has_coach_overlay'], isTrue);
      expect(reported, isEmpty);
    });
  });

  group('writes ask for their row back and report a failure', () {
    final cases = <String, Future<bool> Function(CustomExerciseService)>{
      'createCoachingPack': (s) => s.createCoachingPack('Squat cues', ['Brace']),
      'submitForGlobalLibrary': (s) => s.submitForGlobalLibrary('ex-1'),
    };
    for (final c in cases.entries) {
      test('${c.key}: a 0-row result is a failure', () async {
        server.mode = WriteMode.zeroRows;
        expect(await c.value(svc), isFalse);
        expect(svc.lastError, isNotNull);
        expect(origins(), ['CustomExerciseService.${c.key}']);
        expect(server.writes.single, contains('select=id'));
      });

      test('${c.key}: a refused write sets lastError and is recorded', () async {
        server.mode = WriteMode.serverError;
        expect(await c.value(svc), isFalse);
        expect(svc.lastError, isA<PostgrestException>());
        expect(origins(), ['CustomExerciseService.${c.key}']);
      });

      test('${c.key}: one row is success; an earlier error is cleared', () async {
        svc.lastError = 'stale';
        server.mode = WriteMode.oneRow;
        expect(await c.value(svc), isTrue);
        expect(svc.lastError, isNull);
        expect(reported, isEmpty);
      });
    }
  });

  group('MyExercisesNotifier.submitForGlobal', () {
    test('a 0-row submission is false and does not reload as if published',
        () async {
      final s = _CountingSvc();
      final n = MyExercisesNotifier(s);
      await Future<void>.delayed(Duration.zero);
      expect(s.loads, 1);
      server.mode = WriteMode.zeroRows;
      expect(await n.submitForGlobal('ex-1'), isFalse,
          reason: 'THE defect: an update that matched no row read as submitted');
      expect(s.loads, 1);
      expect(n.state.value!.map((e) => e.id), ['ex-1'],
          reason: 'the list shown is kept');
    });

    test('a thrown submission is false, recorded, and does not reload (QA gap)',
        () async {
      final s = _CountingSvc();
      final n = MyExercisesNotifier(s);
      await Future<void>.delayed(Duration.zero);
      server.mode = WriteMode.serverError;
      expect(await n.submitForGlobal('ex-1'), isFalse);
      expect(s.lastError, isA<PostgrestException>());
      expect(origins(), ['CustomExerciseService.submitForGlobalLibrary']);
      expect(s.loads, 1);
      expect(n.state.value!.map((e) => e.id), ['ex-1']);
    });

    test('positive control: a submitted exercise reloads the list', () async {
      final s = _CountingSvc();
      final n = MyExercisesNotifier(s);
      await Future<void>.delayed(Duration.zero);
      expect(await n.submitForGlobal('ex-1'), isTrue);
      expect(s.loads, 2);
    });
  });

  // P0-FL-53a round 2 · Save coaching and voice-note removal.
  group('upsertCoachOverlay', () {
    Future<bool> save() =>
        svc.upsertCoachOverlay('ex-1', note: 'Slow down', focus: ['Brace']);

    test('a 0-row upsert is a failure, recorded', () async {
      server.mode = WriteMode.zeroRows;
      expect(await save(), isFalse,
          reason: 'THE defect: an upsert that wrote no row read as saved');
      expect(svc.lastError, isNotNull);
      expect(origins(), ['CustomExerciseService.upsertCoachOverlay']);
      expect(server.writes.single, contains('select=exercise_id'));
    });

    test('a refused upsert sets lastError and is recorded', () async {
      server.mode = WriteMode.serverError;
      expect(await save(), isFalse);
      expect(svc.lastError, isA<PostgrestException>());
      expect(origins(), ['CustomExerciseService.upsertCoachOverlay'],
          reason: 'THE defect: the failure was caught and never recorded');
    });

    test('positive control: one row is success; an earlier error is cleared',
        () async {
      svc.lastError = 'stale';
      expect(await save(), isTrue);
      expect(svc.lastError, isNull);
      expect(reported, isEmpty);
    });
  });

  group('clearCoachVoice', () {
    const voice = 'voice/$_uid/ex-1-1.m4a';
    bool patch(String w) =>
        w.startsWith('PATCH') && w.contains('coach_exercise_media');

    test('a refused row update is false and recorded', () async {
      server.reads['coach_exercise_media'] = {'voice_url': voice};
      server.mode = WriteMode.serverError;
      server.modeAppliesTo = patch;
      expect(await svc.clearCoachVoice('ex-1'), isFalse);
      expect(svc.lastError, isA<PostgrestException>());
      expect(origins(), ['CustomExerciseService.clearCoachVoice'],
          reason: 'THE defect: the failure was never recorded');
    });

    test('a failed object removal is false, recorded, row untouched', () async {
      server.reads['coach_exercise_media'] = {'voice_url': voice};
      server.failStorageDelete = true;
      expect(await svc.clearCoachVoice('ex-1'), isFalse);
      expect(origins(), ['CustomExerciseService.clearCoachVoice']);
      expect(server.writes.where(patch), isEmpty);
    });

    test('a 0-row row update is a failure', () async {
      server.reads['coach_exercise_media'] = {'voice_url': voice};
      server.mode = WriteMode.zeroRows;
      server.modeAppliesTo = patch;
      expect(await svc.clearCoachVoice('ex-1'), isFalse);
      expect(origins(), ['CustomExerciseService.clearCoachVoice']);
      expect(server.writes.singleWhere(patch), contains('select=exercise_id'));
    });

    test('positive control: removed and cleared; an earlier error is cleared',
        () async {
      server.reads['coach_exercise_media'] = {'voice_url': voice};
      svc.lastError = 'stale';
      expect(await svc.clearCoachVoice('ex-1'), isTrue);
      expect(svc.lastError, isNull);
      expect(server.writes, contains(startsWith('DELETE /storage/v1/')));
      expect(reported, isEmpty);
    });

    test('negative control: no overlay row is nothing to clear — not a failure',
        () async {
      expect(await svc.clearCoachVoice('ex-1'), isTrue);
      expect(server.writes, isEmpty);
      expect(reported, isEmpty);
    });
  });
}

/// Real writes (through the fake server); the list read is canned.
class _CountingSvc extends CustomExerciseService {
  int loads = 0;
  @override
  Future<List<ExerciseDetail>> getMyExercises() async {
    loads++;
    return [ExerciseDetail.fromJson({'id': 'ex-1', 'name': 'Goblet Squat'})];
  }
}
