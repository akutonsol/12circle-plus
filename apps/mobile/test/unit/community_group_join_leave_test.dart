import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/community/data/live_community_service.dart';
import 'package:circle_fitness/features/community/data/models/post_model.dart';
import 'package:circle_fitness/features/community/domain/community_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// P0-FL-10 follow-up — the join/leave path.
//
// L1 · leaveGroup awaited a bare delete and answered true. RLS filters a delete
//      it does not allow to ZERO rows with no error, so the member was told
//      they had left while their membership row was still there.
// L2 · joinGroup's `catch (_) → false` dropped the cause of a failed join.
// L3 · a quick double-tap on Join sent two requests for the same group.

const _uid = '00000000-0000-4000-8000-0000000000c9';
const _gid = '11111111-1111-4111-8111-1111111111aa';

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

String _jwt() {
  final exp = DateTime.now().add(const Duration(days: 3650)).millisecondsSinceEpoch ~/ 1000;
  return '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${_b64({'sub': _uid, 'role': 'authenticated', 'exp': exp, 'aud': 'authenticated'})}.'
      'not-verified-client-side';
}

class _SeededSession extends LocalStorage {
  @override
  Future<void> initialize() async {}
  @override
  Future<String?> accessToken() async => jsonEncode({
        'access_token': _jwt(),
        'token_type': 'bearer',
        'expires_in': 315360000,
        'refresh_token': 'test-refresh',
        'user': {
          'id': _uid,
          'app_metadata': {},
          'user_metadata': {},
          'aud': 'authenticated',
          'created_at': '2026-01-01T00:00:00Z',
        },
      });
  @override
  Future<bool> hasAccessToken() async => true;
  @override
  Future<void> persistSession(String persistSessionString) async {}
  @override
  Future<void> removePersistedSession() async {}
}

class _MemoryStore extends GotrueAsyncStorage {
  final Map<String, String> _m = {};
  @override
  Future<String?> getItem({required String key}) async => _m[key];
  @override
  Future<void> setItem({required String key, required String value}) async =>
      _m[key] = value;
  @override
  Future<void> removeItem({required String key}) async => _m.remove(key);
}

class _Server extends http.BaseClient {
  /// Rows a DELETE on community_group_members hands back.
  List<Map<String, Object?>> deleted = [];

  /// Status + body for an INSERT on community_group_members.
  int insertStatus = 201;
  Object? insertBody = [];

  final requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    var status = 200;
    Object? body = [];
    if (request.url.path.endsWith('/community_group_members')) {
      if (request.method == 'DELETE') {
        body = deleted;
      } else if (request.method == 'POST') {
        status = insertStatus;
        body = insertBody;
      }
    }
    return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
        request: request, headers: {'content-type': 'application/json'});
  }
}

/// A service whose join/leave stay open until the test lets them finish.
class _SlowService extends LiveCommunityService {
  int joins = 0;
  int leaves = 0;
  final gate = Completer<bool>();
  @override
  Future<bool> joinGroup(String groupId) {
    joins++;
    return gate.future;
  }

  @override
  Future<bool> leaveGroup(String groupId) {
    leaves++;
    return gate.future;
  }
}

CommunityGroup _group({required bool joined}) => CommunityGroup(
    id: _gid, name: 'Alpha Lifters', description: '', emoji: '💪',
    memberCount: 3, isJoined: joined);

void main() {
  late _Server server;
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = _Server();
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: server,
      authOptions: FlutterAuthClientOptions(
        localStorage: _SeededSession(),
        pkceAsyncStorage: _MemoryStore(),
        detectSessionInUri: false,
      ),
      debug: false,
    );
  });

  setUp(() {
    server
      ..deleted = []
      ..insertStatus = 201
      ..insertBody = []
      ..requests.clear();
    reported.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  group('L1 · leaveGroup', () {
    test('a delete RLS filtered to zero rows is not "left"', () async {
      server.deleted = [];
      final ok = await LiveCommunityService().leaveGroup(_gid);
      expect(ok, isFalse,
          reason: 'THE defect: no error was taken as the row being removed');
      final del = server.requests.singleWhere((r) => r.method == 'DELETE');
      expect(del.url.queryParameters['select'], 'id',
          reason: 'the delete must ask for the removed rows back');
    });

    test('a removed row is "left"', () async {
      server.deleted = [
        {'id': '22222222-2222-4222-8222-222222222222'},
      ];
      expect(await LiveCommunityService().leaveGroup(_gid), isTrue);
    });
  });

  group('L2 · joinGroup', () {
    test('a failed join is recorded with its cause', () async {
      server
        ..insertStatus = 500
        ..insertBody = {'code': 'XX000', 'message': 'upstream down'};
      expect(await LiveCommunityService().joinGroup(_gid), isFalse);
      expect(reported, hasLength(1),
          reason: 'THE defect: catch (_) dropped the cause');
      expect(reported.single.origin, 'community.joinGroup');
      expect(reported.single.error.toString(), contains('upstream down'));
    });

    test('already a member (23505) is still a join, and not a failure', () async {
      server
        ..insertStatus = 409
        ..insertBody = {
          'code': '23505',
          'message': 'duplicate key value violates unique constraint',
        };
      expect(await LiveCommunityService().joinGroup(_gid), isTrue);
      expect(reported, isEmpty);
    });
  });

  group('L3 · one request per group at a time', () {
    test('a second Join tap while the first is in flight sends nothing', () async {
      final svc = _SlowService();
      final n = GroupNotifier(svc);
      addTearDown(n.dispose);
      final first = n.toggleJoin(_group(joined: false));
      final second = n.toggleJoin(_group(joined: false));
      expect(svc.joins, 1, reason: 'THE defect: a double-tap sent two joins');
      expect(await second, isNull, reason: 'ignored, not reported as failed');
      svc.gate.complete(true);
      expect(await first, isTrue);
    });

    test('a second Leave tap while the first is in flight sends nothing', () async {
      final svc = _SlowService();
      final n = GroupNotifier(svc);
      addTearDown(n.dispose);
      final first = n.toggleJoin(_group(joined: true));
      final second = n.toggleJoin(_group(joined: true));
      expect(svc.leaves, 1, reason: 'THE defect: a double-tap sent two leaves');
      expect(await second, isNull);
      svc.gate.complete(true);
      expect(await first, isTrue);
    });

    test('once the first finishes, the next tap goes through', () async {
      final svc = _SlowService();
      final n = GroupNotifier(svc);
      addTearDown(n.dispose);
      svc.gate.complete(false);
      expect(await n.toggleJoin(_group(joined: false)), isFalse);
      await n.toggleJoin(_group(joined: false));
      expect(svc.joins, 2, reason: 'a failed join must not lock the button');
    });
  });
}
