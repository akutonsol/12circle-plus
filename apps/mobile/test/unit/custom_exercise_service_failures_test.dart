import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/exercise_database/data/custom_exercise_service.dart';
import 'package:circle_fitness/features/exercise_database/data/models/exercise_detail_model.dart';
import 'package:circle_fitness/features/exercise_database/domain/custom_exercise_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/failing_reads_postgrest.dart';
import '../support/row_checking_postgrest.dart';

// P0-FL-50a · CustomExerciseService reads stop turning a failure into
// "nothing there".
//
// Every site below caught EVERYTHING and returned the value that also means
// legitimate absence — `catch (_) { return []; }` / `return null` / `return 0`
// / the default flags — with nothing recorded. Writes (delete / approve /
// reject) returned false with no lastError, and a 0-row result (RLS filters
// silently) counted as done.
//
// Each site is now one of:
//   * a READ whose failure is recorded (precise origin) and RETHROWN, so the
//     caller can say "Couldn't load …" — getSubstitutes, getCoachingPacks,
//     getRawById, getExerciseBySlug, getPendingGlobalSubmissions;
//   * a best-effort ENRICHMENT that keeps its safe default but records the
//     failure — metaForName, findVideoForName, findEnrichedVideo;
//   * platformObservability: a failed count/average is null + listed as
//     failed (never 0);
//   * a WRITE that asks for its row back, so a 0-row result is a failure, and
//     that sets lastError and records — deleteExercise, deleteCoachingPack,
//     approveGlobalExercise, rejectGlobalExercise.
// And the legitimate-absence answers are unchanged.
//
// HOW TO SEE THEM FAIL: `git checkout 1b94044 -- apps/mobile/lib/features/
// exercise_database/data/custom_exercise_service.dart apps/mobile/lib/features/
// exercise_database/domain/custom_exercise_provider.dart` — no failure is
// recorded, reads return []/null/0, 0-row writes return true.

const _uid = '00000000-0000-4000-8000-0000000f5050';

void main() {
  late FailingReadsPostgrest server;
  final reported = <AppFailure>[];
  late CustomExerciseService svc;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = FailingReadsPostgrest(_uid);
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

  // ── best-effort enrichments: default kept, failure recorded ───────────────
  group('best-effort enrichments record a failed read', () {
    test('metaForName keeps the safe default and records the failure', () async {
      server.failReads['custom_exercises'] = ReadFailure.server;
      final meta = await svc.metaForName('Goblet Squat');
      expect(meta.rpe, isTrue);
      expect(meta.pr, isTrue);
      expect(origins(), ['CustomExerciseService.metaForName']);
      expect(reported.single.error, isA<PostgrestException>());
    });

    test('metaForName with no library record: default, nothing recorded', () async {
      final meta = await svc.metaForName('Goblet Squat');
      expect((meta.rpe, meta.pr), (true, true));
      expect(reported, isEmpty);
    });

    test('metaForName reads a real record', () async {
      server.reads['custom_exercises'] = [
        {'supports_rpe_tracking': false, 'supports_pr_tracking': true}
      ];
      final meta = await svc.metaForName('Plank');
      expect(meta.rpe, isFalse);
      expect(reported, isEmpty);
    });

    test('findVideoForName records a failure (null = fall back)', () async {
      server.failReads['custom_exercises'] = ReadFailure.network;
      expect(await svc.findVideoForName('Goblet Squat'), isNull);
      expect(origins(), ['CustomExerciseService.findVideoForName']);
    });

    test('findVideoForName with no video: null, nothing recorded', () async {
      expect(await svc.findVideoForName('Goblet Squat'), isNull);
      expect(reported, isEmpty);
    });

    test('findEnrichedVideo records a failure (null = fall back)', () async {
      server.failReads['exercise_videos'] = ReadFailure.server;
      expect(await svc.findEnrichedVideo('Goblet Squat'), isNull);
      expect(origins(), ['CustomExerciseService.findEnrichedVideo']);
    });

    test('findEnrichedVideo with no row: null, nothing recorded', () async {
      expect(await svc.findEnrichedVideo('Goblet Squat'), isNull);
      expect(reported, isEmpty);
    });
  });

  // ── reads that rethrow ─────────────────────────────────────────────────────
  group('a failed read is recorded and rethrown, never "nothing"', () {
    test('getSubstitutes', () async {
      server.failReads['custom_exercises'] = ReadFailure.server;
      await expectLater(
          svc.getSubstitutes('Goblet Squat', 'Legs'), throwsA(isA<PostgrestException>()));
      expect(origins(), ['CustomExerciseService.getSubstitutes']);
    });

    test('getSubstitutes with none: [], nothing recorded', () async {
      expect(await svc.getSubstitutes('Goblet Squat', 'Legs'), isEmpty);
      expect(reported, isEmpty);
    });

    test('getCoachingPacks', () async {
      server.failReads['coach_coaching_packs'] = ReadFailure.server;
      await expectLater(svc.getCoachingPacks(), throwsA(anything));
      expect(origins(), ['CustomExerciseService.getCoachingPacks']);
    });

    test('getCoachingPacks with none: [], nothing recorded', () async {
      expect(await svc.getCoachingPacks(), isEmpty);
      expect(reported, isEmpty);
    });

    test('getRawById', () async {
      server.failReads['custom_exercises'] = ReadFailure.server;
      await expectLater(svc.getRawById('ex-1'), throwsA(isA<PostgrestException>()));
      expect(origins(), ['CustomExerciseService.getRawById']);
    });

    test('getRawById with no such row: null, nothing recorded', () async {
      expect(await svc.getRawById('ex-1'), isNull);
      expect(reported, isEmpty);
    });

    test('getExerciseBySlug', () async {
      server.failReads['custom_exercises'] = ReadFailure.server;
      await expectLater(
          svc.getExerciseBySlug('goblet-squat'), throwsA(isA<PostgrestException>()));
      expect(origins(), ['CustomExerciseService.getExerciseBySlug']);
    });

    test('getExerciseBySlug with no such row: null, nothing recorded', () async {
      expect(await svc.getExerciseBySlug('goblet-squat'), isNull);
      expect(reported, isEmpty);
    });

    test('getPendingGlobalSubmissions', () async {
      server.failReads['custom_exercises'] = ReadFailure.server;
      await expectLater(
          svc.getPendingGlobalSubmissions(), throwsA(isA<PostgrestException>()));
      expect(origins(), ['CustomExerciseService.getPendingGlobalSubmissions']);
    });

    test('getPendingGlobalSubmissions with none: [], nothing recorded', () async {
      expect(await svc.getPendingGlobalSubmissions(), isEmpty);
      expect(reported, isEmpty);
    });
  });

  // ── platformObservability ─────────────────────────────────────────────────
  group('platformObservability: a failed figure is unknown, never 0', () {
    test('a failed count is null and listed as failed, and recorded', () async {
      server.failReads['workout_programs'] = ReadFailure.server;
      server.failReads['weekly_feedback'] = ReadFailure.server;
      server.reads['decision_traces'] = [
        {'id': 't1'},
        {'id': 't2'}
      ];
      final d = await svc.platformObservability();
      expect(d['programs_generated'], isNull, reason: 'a failed count is not 0');
      expect(d['decision_traces'], 2);
      expect(d['predictions'], 0, reason: 'a count that answered empty IS 0');
      expect(d['avg_adherence'], isNull);
      expect(d[CustomExerciseService.observabilityFailedKey],
          unorderedEquals(['programs_generated', 'avg_adherence']));
      expect(d[CustomExerciseService.observabilityErrorKey], isA<PostgrestException>());
      expect(
          origins(),
          unorderedEquals([
            'CustomExerciseService.platformObservability.programs_generated',
            'CustomExerciseService.platformObservability.avg_adherence',
          ]));
    });

    test('all answered: nothing failed, nothing recorded, empty counts are 0',
        () async {
      final d = await svc.platformObservability();
      expect(d['programs_generated'], 0);
      expect(d['avg_adherence'], isNull, reason: 'no data, not a failure');
      expect(d[CustomExerciseService.observabilityFailedKey], isEmpty);
      expect(reported, isEmpty);
    });
  });

  // ── writes: 0 rows is a failure; failures set lastError and are recorded ───
  group('writes ask for their row back and report a failure', () {
    final cases = <String, Future<bool> Function(CustomExerciseService)>{
      'deleteExercise': (s) => s.deleteExercise('ex-1'),
      'deleteCoachingPack': (s) => s.deleteCoachingPack('pack-1'),
      'approveGlobalExercise': (s) => s.approveGlobalExercise('ex-1'),
      'rejectGlobalExercise': (s) => s.rejectGlobalExercise('ex-1'),
    };
    void setMode(String name, WriteMode m) {
      if (name.startsWith('delete')) {
        server.deleteMode = m;
      } else {
        server.mode = m;
      }
    }

    for (final c in cases.entries) {
      test('${c.key}: a 0-row result is a failure', () async {
        setMode(c.key, WriteMode.zeroRows);
        expect(await c.value(svc), isFalse);
        expect(svc.lastError, isNotNull);
        expect(origins(), ['CustomExerciseService.${c.key}']);
        expect(server.writes.single, contains('select=id'));
      });

      test('${c.key}: a refused write sets lastError and is recorded', () async {
        setMode(c.key, WriteMode.serverError);
        expect(await c.value(svc), isFalse);
        expect(svc.lastError, isA<PostgrestException>());
        expect(origins(), ['CustomExerciseService.${c.key}']);
      });

      test('${c.key}: one row changed is success; an earlier error is cleared',
          () async {
        svc.lastError = 'stale';
        setMode(c.key, WriteMode.oneRow);
        expect(await c.value(svc), isTrue);
        expect(svc.lastError, isNull);
        expect(reported, isEmpty);
      });
    }
  });

  // ── the notifier: a failed delete does not drop the exercise ──────────────
  group('MyExercisesNotifier.delete', () {
    test('keeps the exercise when the delete failed', () async {
      final s = _ListSvc(deleteOk: false);
      final n = MyExercisesNotifier(s);
      await Future<void>.delayed(Duration.zero);
      expect(await n.delete('ex-1'), isFalse);
      expect(n.state.value!.map((e) => e.id), ['ex-1']);
    });

    test('removes it when the delete happened', () async {
      final s = _ListSvc(deleteOk: true);
      final n = MyExercisesNotifier(s);
      await Future<void>.delayed(Duration.zero);
      expect(await n.delete('ex-1'), isTrue);
      expect(n.state.value, isEmpty);
    });
  });
}

class _ListSvc extends CustomExerciseService {
  _ListSvc({required this.deleteOk});
  final bool deleteOk;
  @override
  Future<List<ExerciseDetail>> getMyExercises() async =>
      [ExerciseDetail.fromJson({'id': 'ex-1', 'name': 'Goblet Squat'})];
  @override
  Future<bool> deleteExercise(String id) async => deleteOk;
}
