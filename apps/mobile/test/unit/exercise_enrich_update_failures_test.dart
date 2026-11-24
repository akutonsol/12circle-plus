import 'dart:convert';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/exercise_database/data/custom_exercise_service.dart';
import 'package:circle_fitness/features/workout/presentation/widgets/section_load_failure.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/row_checking_postgrest.dart';

// P0-FL-57a · enrichWithAI returned the backend's own text (or the exception
// stringified) and recorded nothing; updateExercise recorded nothing.
//
// HOW TO SEE IT FAIL: `git checkout f191d48 -- apps/mobile/lib/features/
// exercise_database/data/custom_exercise_service.dart`.

const _uid = '00000000-0000-4000-8000-0000000f5058';
const _leak = 'upstream 429: quota exceeded for key SECRET';

class _Server extends RowCheckingPostgrest {
  _Server() : super(_uid);

  /// How the edge function answers: an HTTP status, or null = unreachable.
  int? status = 200;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path.endsWith('/functions/v1/enrich-exercise')) {
      final s = status;
      if (s == null) throw http.ClientException('Failed host SECRET', request.url);
      return http.StreamedResponse(
          Stream.value(utf8.encode(
              jsonEncode(s == 200 ? {'ok': true} : {'error': _leak}))),
          s,
          request: request,
          headers: {'content-type': 'application/json'});
    }
    return super.send(request);
  }
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
    server.status = 200;
    reported.clear();
    setFailureSink(reported.add);
    svc = CustomExerciseService()..lastError = 'stale';
  });
  tearDown(resetFailureSink);

  List<String> origins() => reported.map((f) => f.origin).toList();

  group('enrichWithAI', () {
    // 202: a 2xx that is not the function's 200 does not throw.
    for (final s in [202, 400, 403, 500, 502]) {
      test('$s: recorded, and none of its text is returned', () async {
        server.status = s;
        final r = await svc.enrichWithAI('goblet-squat');
        expect(r.ok, isFalse);
        expect('${r.error}', isNot(contains('SECRET')),
            reason: "THE defect: the backend's text was returned for display");
        expect(origins(), ['CustomExerciseService.enrichWithAI'],
            reason: 'THE defect: nothing was recorded');
        expect('${(reported.single.error as FunctionException).details}',
            contains(_leak), reason: 'kept only in the record');
        expect(svc.lastError, isA<FunctionException>());
        expect(
            couldntMessage('generate coaching content', r.error),
            "Couldn't generate coaching content — try again in a moment. If it "
            'keeps happening, contact support.');
      });
    }

    test('no connection: the connection hint, recorded', () async {
      server.status = null;
      final r = await svc.enrichWithAI('goblet-squat');
      expect(r.ok, isFalse);
      expect(origins(), ['CustomExerciseService.enrichWithAI']);
      final said = couldntMessage('generate coaching content', r.error);
      expect(
          said,
          "Couldn't generate coaching content — check your connection and try "
          'again.',
          reason: 'THE defect: stringified, it was never seen as the connection');
      expect(said, isNot(contains('SECRET')));
    });

    test('positive control: a 200 is ok; an earlier error is cleared', () async {
      final r = await svc.enrichWithAI('goblet-squat');
      expect(r.ok, isTrue);
      expect(r.error, isNull);
      expect(svc.lastError, isNull);
      expect(reported, isEmpty);
    });
  });

  group('updateExercise', () {
    test('0 rows is a failure, recorded', () async {
      server.mode = WriteMode.zeroRows;
      expect(await svc.updateExercise('ex-1', {'name': 'x'}), isFalse);
      expect(origins(), ['CustomExerciseService.updateExercise'],
          reason: 'THE defect: nothing was recorded');
      expect(svc.lastError, "You don't have permission to edit this exercise");
      expect(server.writes.single, contains('select=id'));
    });

    test('a refused update is a failure, recorded', () async {
      server.mode = WriteMode.serverError;
      expect(await svc.updateExercise('ex-1', {'name': 'x'}), isFalse);
      expect(origins(), ['CustomExerciseService.updateExercise']);
      expect(svc.lastError, isA<PostgrestException>());
    });

    test('no connection is recorded and kept as itself', () async {
      server.mode = WriteMode.network;
      expect(await svc.updateExercise('ex-1', {'name': 'x'}), isFalse);
      expect(origins(), ['CustomExerciseService.updateExercise']);
      expect(svc.lastError, isA<http.ClientException>());
    });

    test('positive control: one row is success; an earlier error is cleared',
        () async {
      expect(await svc.updateExercise('ex-1', {'name': 'x'}), isTrue);
      expect(svc.lastError, isNull);
      expect(reported, isEmpty);
    });
  });
}
