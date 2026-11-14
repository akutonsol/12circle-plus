import 'dart:convert';

import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/community/domain/community_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// Members were shown five community groups that do not exist.
//
// `getGroups` answered [] for a failed read, and `liveGroupsProvider` replaced
// an empty answer with `getSampleGroups()` — "Transformation Squad · 248
// members", "Nutrition Warriors · 183"… with ids '1'–'5' that are not rows.
// `groupNotifierProvider` also STARTED with them, so Community and Activity
// showed them while loading. Joining one sent a non-uuid id and failed in
// silence. The read was also a bare `.order('name')` — descending — so the real
// groups listed Z to A.

const _uid = '00000000-0000-4000-8000-0000000000c9';

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
  String mode = 'ok'; // ok | empty | down
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    var status = 200;
    Object? body = [];
    if (path.endsWith('/community_groups')) {
      if (mode == 'down') {
        status = 500;
        body = {'message': 'upstream down'};
      } else if (mode == 'ok') {
        final rows = [
          {'id': '11111111-1111-4111-8111-1111111111aa', 'name': 'Alpha Lifters', 'description': '', 'emoji': '💪'},
          {'id': '11111111-1111-4111-8111-1111111111bb', 'name': 'Zen Runners', 'description': '', 'emoji': '🏃'},
        ];
        final desc = (request.url.queryParameters['order'] ?? '').contains('.desc');
        body = desc ? rows.reversed.toList() : rows;
      }
    }
    return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
        request: request, headers: {'content-type': 'application/json'});
  }
}

void main() {
  late _Server server;

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

  ProviderContainer container() {
    final c = ProviderContainer(overrides: [
      currentUserProvider.overrideWithValue(Supabase.instance.client.auth.currentUser),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('a failed read is a failure, not five invented groups', () async {
    server.mode = 'down';
    final c = container();
    c.listen(liveGroupsProvider, (_, __) {});
    await expectLater(c.read(liveGroupsProvider.future), throwsA(anything),
        reason: 'THE defect: the failure became the sample groups');
  });

  test('no groups is no groups', () async {
    server.mode = 'empty';
    final c = container();
    expect(await c.read(liveGroupsProvider.future), isEmpty);
  });

  test('nothing is shown as a group before the real ones arrive', () {
    server.mode = 'ok';
    final c = container();
    expect(c.read(groupNotifierProvider).map((g) => g.name), isEmpty,
        reason: 'the notifier started with the sample groups');
  });

  test('the real groups are listed A to Z', () async {
    server.mode = 'ok';
    final c = container();
    final groups = await c.read(liveGroupsProvider.future);
    expect(groups.map((g) => g.name), ['Alpha Lifters', 'Zen Runners']);
  });
}
