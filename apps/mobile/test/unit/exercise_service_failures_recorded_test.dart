import 'dart:convert';
import 'dart:typed_data';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/exercise_database/data/custom_exercise_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/failing_reads_postgrest.dart';
import '../support/row_checking_postgrest.dart';

// P0-FL-57a round 2 (S-57a-3) · createExercise's update-by-slug returned the
// row's id as "saved" when RLS filtered the update to nothing; and a failed
// create, voice upload, voice save or voice signing was kept in `lastError`
// without being recorded.
//
// HOW TO SEE IT FAIL: `git checkout 136b745 -- apps/mobile/lib/features/
// exercise_database/data/custom_exercise_service.dart`.

const _uid = '00000000-0000-4000-8000-0000000f5059';
const _stored = 'voice/$_uid/ex-1-1700000000000.m4a';

class _Server extends FailingReadsPostgrest {
  _Server() : super(_uid);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (path.contains('/storage/v1/')) {
      switch (mode) {
        case WriteMode.network:
          throw http.ClientException('Connection refused', request.url);
        case WriteMode.serverError || WriteMode.zeroRows:
          return _json(
              {'message': 'refused', 'statusCode': '403'}, 403, request);
        case WriteMode.oneRow:
          return _json({
            'Key': 'coach-media/$_stored',
            'signedURL': '/object/sign/coach-media/$_stored?token=t',
          }, 200, request);
      }
    }
    // The insert asks for its one row back, as an object.
    if (path.endsWith('/custom_exercises') &&
        request.method == 'POST' &&
        mode == WriteMode.oneRow) {
      writes.add('POST $path');
      return _json({'id': 'ex-new'}, 201, request);
    }
    return super.send(request);
  }

  http.StreamedResponse _json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

void main() {
  late _Server server;
  final reported = <AppFailure>[];
  late CustomExerciseService svc;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = _Server();
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

  group('createExercise', () {
    Future<String?> create() => svc.createExercise(
          name: 'Goblet Squat',
          category: 'Strength',
          muscleGroup: 'Legs',
          secondaryMuscles: const [],
          equipment: 'Dumbbell',
          difficulty: 'Beginner',
          description: '',
          instructions: const [],
          coachingCues: const [],
          commonMistakes: const [],
          alternatives: const [],
          tags: const [],
          videoVariants: const [],
        );
    void expectFailed() {
      expect(svc.lastError, isNotNull);
      expect(origins(), ['CustomExerciseService.createExercise']);
      expect(reported.single.error, svc.lastError);
    }

    test('re-saving a name: a 0-row update is a failure', () async {
      server.reads['custom_exercises'] = {'id': 'ex-1'};
      server.mode = WriteMode.zeroRows;
      expect(await create(), isNull,
          reason: 'THE defect: a refused update was reported as saved');
      expectFailed();
      expect(svc.lastError, isA<String>(), reason: 'our own words, not SQL');
      expect(server.writes.single, startsWith('PATCH'),
          reason: 'and nothing is inserted beside the row it could not update');
    });

    for (final m in [WriteMode.serverError, WriteMode.network]) {
      test('re-saving a name, $m: recorded', () async {
        server.reads['custom_exercises'] = {'id': 'ex-1'};
        server.mode = m;
        expect(await create(), isNull);
        expectFailed();
      });
      test('a new name, $m: recorded', () async {
        server.mode = m;
        expect(await create(), isNull);
        expectFailed();
        expect(server.writes.single, startsWith('POST'));
      });
    }

    test('the lookup by name failing is recorded, and nothing is written',
        () async {
      server.failReads['custom_exercises'] = ReadFailure.server;
      expect(await create(), isNull);
      expectFailed();
      expect(server.writes, isEmpty);
    });

    test('positive control: re-saving a name updates that row', () async {
      server.reads['custom_exercises'] = {'id': 'ex-1'};
      expect(await create(), 'ex-1');
      expect(
          server.writes.single,
          allOf(startsWith('PATCH'), contains('id=eq.ex-1'),
              contains('select=id')));
      expect(svc.lastError, isNull);
      expect(reported, isEmpty);
    });

    test(
        'negative control: no row by that name is a new exercise, not an '
        'error', () async {
      expect(await create(), 'ex-new');
      expect(server.writes.single, startsWith('POST'));
      expect(svc.lastError, isNull);
      expect(reported, isEmpty);
    });
  });

  final voice = <String, Future<Object?> Function()>{
    'uploadCoachVoice': () => svc.uploadCoachVoice('ex-1', Uint8List(4)),
    'setCoachVoice': () => svc.setCoachVoice('ex-1', _stored, 1200, null),
    'signedCoachVoiceUrl': () => svc.signedCoachVoiceUrl(_stored),
  };
  for (final v in voice.entries) {
    group(v.key, () {
      for (final m in [WriteMode.serverError, WriteMode.network]) {
        test('$m: recorded; the answer is unchanged', () async {
          server.mode = m;
          expect(await v.value(), v.key == 'setCoachVoice' ? isFalse : isNull);
          expect(origins(), ['CustomExerciseService.${v.key}'],
              reason: 'THE defect: nothing was recorded');
          expect(reported.single.error, svc.lastError);
        });
      }
      test('positive control: it works, and nothing is recorded', () async {
        expect(await v.value(), v.key == 'setCoachVoice' ? isTrue : isNotNull);
        expect(reported, isEmpty);
      });
    });
  }

  test('negative control: a value that is not a voice note is not a failure',
      () async {
    expect(await svc.signedCoachVoiceUrl('https://example.com/a.m4a'), isNull);
    expect(reported, isEmpty);
  });
}
