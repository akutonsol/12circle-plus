import 'dart:convert';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/exercise_database/data/custom_exercise_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/failing_reads_postgrest.dart';
import '../support/row_checking_postgrest.dart';

// P0-FL-57a (c) · a deleted voice note is really deleted.
//
// Storage `remove([path])` answers with the objects it removed and does NOT
// throw for one it may not delete. `clearCoachVoice` ignored that answer: a
// refused remove still nulled the row and the note was reported deleted while
// the recording stayed in the (public) bucket.
//
// HOW TO SEE IT FAIL: `git checkout f191d48 -- apps/mobile/lib/features/
// exercise_database/data/custom_exercise_service.dart`.

const _uid = '00000000-0000-4000-8000-0000000f5057';
const _name = 'ex-1-1700000000000.m4a';
const _path = 'voice/$_uid/$_name';

enum _Remove { removes, refuses, throws, network }

enum _List { answers, throws, network }

/// A bucket that behaves like Supabase Storage about removal and listing.
class _Bucket extends FailingReadsPostgrest {
  _Bucket() : super(_uid);

  final objects = <String>{};
  _Remove remove = _Remove.removes;
  _List list = _List.answers;

  /// The removal happens, but its reply is lost.
  bool loseRemoveReply = false;
  final listed = <Map<String, Object?>>[];

  @override
  void reset() {
    super.reset();
    objects.clear();
    remove = _Remove.removes;
    list = _List.answers;
    loseRemoveReply = false;
    listed.clear();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (path == '/storage/v1/object/coach-media' && request.method == 'DELETE') {
      final prefixes =
          (jsonDecode((request as http.Request).body) as Map)['prefixes'] as List;
      switch (remove) {
        case _Remove.throws:
          return _json({'message': 'refused', 'statusCode': '500'}, 500, request);
        case _Remove.network:
          throw http.ClientException('Connection refused', request.url);
        case _Remove.refuses:
          return _json([], 200, request);
        case _Remove.removes:
          final gone = [
            for (final p in prefixes)
              if (objects.remove(p)) {'name': p}
          ];
          if (loseRemoveReply) {
            throw http.ClientException('Connection closed', request.url);
          }
          return _json(gone, 200, request);
      }
    }
    if (path == '/storage/v1/object/list/coach-media') {
      final q = jsonDecode((request as http.Request).body) as Map<String, Object?>;
      listed.add(q);
      switch (list) {
        case _List.throws:
          return _json({'message': 'refused', 'statusCode': '500'}, 500, request);
        case _List.network:
          throw http.ClientException('Connection refused', request.url);
        case _List.answers:
          final folder = '${q['prefix']}/';
          return _json([
            for (final o in objects)
              if (o.startsWith(folder) &&
                  o.substring(folder.length).contains('${q['search'] ?? ''}'))
                {'name': o.substring(folder.length), 'id': 'obj'}
          ], 200, request);
      }
    }
    return super.send(request);
  }

  http.StreamedResponse _json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

void main() {
  late _Bucket server;
  final reported = <AppFailure>[];
  late CustomExerciseService svc;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = _Bucket();
    await initSignedInSupabase(server);
  });

  setUp(() {
    server.reset();
    server.objects.add(_path);
    server.reads['coach_exercise_media'] = {'voice_url': _path};
    reported.clear();
    setFailureSink(reported.add);
    svc = CustomExerciseService()..lastError = 'stale';
  });
  tearDown(resetFailureSink);

  Iterable<String> rowWrites() => server.writes
      .where((w) => w.startsWith('PATCH') && w.contains('coach_exercise_media'));

  void expectFailed() {
    expect(reported.map((f) => f.origin),
        ['CustomExerciseService.clearCoachVoice']);
    expect(svc.lastError, isNotNull);
    expect(rowWrites(), isEmpty, reason: 'the row still names the recording');
  }

  test('positive control: removed → the row is cleared, no second look',
      () async {
    expect(await svc.clearCoachVoice('ex-1'), isTrue);
    expect(server.objects, isEmpty);
    expect(rowWrites().single, contains('"voice_url":null'));
    expect(server.listed, isEmpty);
    expect(svc.lastError, isNull);
    expect(reported, isEmpty);
  });

  test('refused (nothing removed, still there) → a failure, row NOT nulled',
      () async {
    server.remove = _Remove.refuses;
    expect(await svc.clearCoachVoice('ex-1'), isFalse,
        reason: 'THE defect: reported deleted, the recording stayed');
    expectFailed();
    expect(server.listed.single,
        containsPair('prefix', 'voice/$_uid'));
    expect(server.listed.single, containsPair('search', _name));
  });

  test('a legacy public URL refused → the same failure', () async {
    server.reads['coach_exercise_media'] = {
      'voice_url': 'https://x.supabase.co/storage/v1/object/public/coach-media/$_path'
    };
    server.remove = _Remove.refuses;
    expect(await svc.clearCoachVoice('ex-1'), isFalse);
    expectFailed();
  });

  test('negative control: already absent → legitimate, the row is cleared',
      () async {
    server.objects.clear();
    expect(await svc.clearCoachVoice('ex-1'), isTrue);
    expect(rowWrites(), hasLength(1));
    expect(svc.lastError, isNull);
    expect(reported, isEmpty);
  });

  test('negative control: another note with a similar name is not this one',
      () async {
    server.objects
      ..clear()
      ..add('voice/$_uid/old-$_name')
      ..add('voice/someone-else/$_name');
    expect(await svc.clearCoachVoice('ex-1'), isTrue);
    expect(rowWrites(), hasLength(1));
  });

  test('a thrown removal → a failure, row NOT nulled', () async {
    server.remove = _Remove.throws;
    expect(await svc.clearCoachVoice('ex-1'), isFalse);
    expectFailed();
    expect(svc.lastError, isA<StorageException>());
  });

  test('no connection → a failure, kept as itself for the hint', () async {
    server.remove = _Remove.network;
    expect(await svc.clearCoachVoice('ex-1'), isFalse);
    expectFailed();
    expect(svc.lastError, isA<http.ClientException>());
  });

  for (final how in [_List.throws, _List.network]) {
    test('nothing removed and the check itself fails (${how.name}) → a failure',
        () async {
      server.remove = _Remove.refuses;
      server.list = how;
      expect(await svc.clearCoachVoice('ex-1'), isFalse,
          reason: 'an unknown is not proof of deletion');
      expectFailed();
    });
  }

  test('a lost removal reply is a failure; the retry then clears the row',
      () async {
    server.loseRemoveReply = true;
    expect(await svc.clearCoachVoice('ex-1'), isFalse);
    expectFailed();
    server.loseRemoveReply = false;
    reported.clear();
    expect(await svc.clearCoachVoice('ex-1'), isTrue,
        reason: 'S-53a-6: already absent must not block the retry');
    expect(rowWrites(), hasLength(1));
    expect(reported, isEmpty);
  });

  test('a lost row-update reply, then a retry on the cleared row, succeeds',
      () async {
    server.mode = WriteMode.network;
    expect(await svc.clearCoachVoice('ex-1'), isFalse);
    server.mode = WriteMode.oneRow;
    server.reads['coach_exercise_media'] = {'voice_url': null};
    expect(await svc.clearCoachVoice('ex-1'), isTrue);
  });
}
