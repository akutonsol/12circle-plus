import 'dart:convert';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/action_items/data/action_item_service.dart';
import 'package:circle_fitness/features/ai_coach/data/ai_coach_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/two_member_postgrest.dart';

// RM-2 · C15-63d-03 and C14-62a1-02: two service calls that ended in
// `catch (_) { return false / null; }` — the failure vanished unrecorded, and
// `assignActionItem` never asked its row back, so an insert RLS filtered to
// nothing answered `true` ("assigned") for a row that does not exist.
//
//  * assignActionItem: true ONLY when the inserted row came back; 0 rows and a
//    refusal are `false` and recorded once; the request is the coach's own,
//    one write, with `select=id`.
//  * generate (the member-facing `ai-coaching-engine` function — not
//    predictClient / evaluateWeek / regenerateProgram / Copilot / a workout
//    build): null on failure as before, now recorded once, without the body.
//
// Through the real Supabase client against a fake that answers a POST with
// 204/empty unless `select=` is asked (so a dropped `.select('id')` shows).
//
// HOW TO SEE IT FAIL: `git checkout 6d1611d -- apps/mobile/lib/features/
// action_items/data apps/mobile/lib/features/ai_coach/data`; the 0-row test
// gets `true`, and every failure test finds nothing recorded.

class _Server extends TwoMemberPostgrest {
  /// What a POST to action_items answers with `select=`: null = one row.
  List<Object?>? insertedRows;
  int? insertStatus;

  /// The ai-coaching-engine answer.
  int functionStatus = 200;
  Object? functionBody;

  final requests = <String>[];
  final bodies = <String>[];

  @override
  void reset() {
    super.reset();
    insertedRows = null;
    insertStatus = null;
    functionStatus = 200;
    functionBody = null;
    requests.clear();
    bodies.clear();
  }

  http.StreamedResponse _out(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final u = request.url;
    if (u.path.startsWith('/auth/')) return super.send(request);
    final name = u.path.split('/').last;
    requests.add('${request.method} $name:${TwoMemberPostgrest.who(request)}'
        '${u.query.isEmpty ? '' : '?${u.query}'}');
    if (request is http.Request) bodies.add(request.body);
    if (name == 'ai-coaching-engine') {
      return _out(functionBody, functionStatus, request);
    }
    if (name == 'action_items' && request.method == 'POST') {
      if (insertStatus != null) {
        return _out({'message': 'refused SECRET_DETAIL', 'code': '42501'},
            insertStatus!, request);
      }
      if (!u.queryParameters.containsKey('select')) {
        return http.StreamedResponse(const Stream.empty(), 201,
            request: request);
      }
      return _out(insertedRows ?? [
        {'id': 'ai-1'}
      ], 201, request);
    }
    return super.send(request);
  }
}

void main() {
  final server = _Server();
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

  Iterable<AppFailure> from(String origin) =>
      reported.where((f) => f.origin == origin);

  group('ActionItemService.assignActionItem', () {
    Future<bool> assign() => ActionItemService().assignActionItem(
        clientId: 'client-1', title: 'Log all meals today');

    test('an insert that changed 0 rows is a failure, recorded once',
        () async {
      server.insertedRows = [];
      expect(await assign(), isFalse,
          reason: 'THE defect: a row RLS filtered away was "assigned"');
      expect(from('ActionItemService.assignActionItem'), hasLength(1));
      expect('${reported.single.error}', contains('0 rows'));
    });

    test('a refused insert is false and recorded once (it was dropped)',
        () async {
      server.insertStatus = 403;
      expect(await assign(), isFalse);
      expect(from('ActionItemService.assignActionItem'), hasLength(1),
          reason: 'THE defect: catch (_) recorded nothing');
      expect(reported, hasLength(1));
    });

    test('control: a saved row is true, nothing recorded, one write as the '
        'signed-in coach, the row asked back', () async {
      expect(await assign(), isTrue);
      expect(reported, isEmpty);
      final posts = server.requests.where((r) => r.startsWith('POST')).toList();
      expect(posts, hasLength(1));
      expect(posts.single, startsWith('POST action_items:$memberA?'));
      expect(posts.single, contains('select=id'));
      final body = jsonDecode(server.bodies.single) as Map;
      expect(body['coach_id'], memberA);
      expect(body['client_id'], 'client-1');
    });

    test('control: signed out sends nothing and records nothing', () async {
      await signOut();
      expect(await assign(), isFalse);
      expect(server.requests, isEmpty);
      expect(reported, isEmpty);
    });
  });

  group('AICoachService.generate (ai-coaching-engine)', () {
    test('a failed invoke is null and recorded once, without the body',
        () async {
      server
        ..functionStatus = 500
        ..functionBody = {'error': 'SECRET_MEMBER_DATA'};
      expect(await AICoachService(owner: memberA).generate('meal_suggestion'),
          isNull);
      expect(from('AICoachService.generate'), hasLength(1),
          reason: 'THE defect: catch (_) { return null; } recorded nothing');
      expect(reported, hasLength(1));
      expect(server.requests, ['POST ai-coaching-engine:$memberA']);
    });

    test('an answer that is not a result is null and recorded once', () async {
      server.functionBody = {'oops': true};
      expect(await AICoachService().generate('progress_insight'), isNull);
      expect(from('AICoachService.generate'), hasLength(1));
    });

    test('an unreadable answer is null and recorded once', () async {
      server.functionBody = 'not json object';
      expect(await AICoachService().generate('risk_assessment'), isNull);
      expect(from('AICoachService.generate'), hasLength(1));
    });

    test('control: a result comes back with its confidence, nothing recorded',
        () async {
      server.functionBody = {
        'result': {'title': 'Push day', 'body': 'Go'},
        'confidence': 80,
        'confidence_reasons': ['steady'],
      };
      final r = await AICoachService(owner: memberA).generate('daily_insight');
      expect(r, isNotNull);
      expect(r!['title'], 'Push day');
      expect(r['confidence'], 80);
      expect(reported, isEmpty);
      final body = jsonDecode(server.bodies.single) as Map;
      expect(body, {'type': 'daily_insight'});
    });

    test("control: the owner gone sends nothing (one record, the stop)",
        () async {
      await signInAs(memberB);
      expect(await AICoachService(owner: memberA).generate('daily_insight'),
          isNull);
      expect(server.requests, isEmpty);
      expect(reported, hasLength(1));
      expect('${reported.single.error}', contains('account'));
    });
  });
}
