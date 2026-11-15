import 'dart:convert';

import 'package:circle_fitness/features/coach/data/pending_invite.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// OWNER DECISION 4, 2026-11-15: signing up from a coach's invite link links the
// client to that coach. The link is /#/signup?invite=<token>; until now nothing
// read the token, so an invite never linked anyone.
//
// The token is remembered when the link is opened and redeemed once signed in
// through accept_coach_invite (migration 194, which checks email / expiry /
// single use and tells both parties). These pin the client half: what is kept,
// what is forgotten, and that two overlapping redemptions are ONE attempt (the
// invite is single use, so a second attempt would call a just-used invite
// invalid).

const _uid = '00000000-0000-4000-8000-0000000000e1';

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
  int status = 200;
  Map<String, Object?> error = {};
  int calls = 0;
  String? lastToken;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path.endsWith('/rpc/accept_coach_invite')) {
      calls++;
      lastToken = (jsonDecode(await request.finalize().bytesToString()) as Map)['p_token'] as String?;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final body = status == 200 ? 'coach-1' : error;
      return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: request, headers: {'content-type': 'application/json'});
    }
    return http.StreamedResponse(Stream.value(utf8.encode('[]')), 200,
        request: request, headers: {'content-type': 'application/json'});
  }
}

void main() {
  final server = _Server();

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
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

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    server
      ..status = 200
      ..error = {}
      ..calls = 0
      ..lastToken = null;
  });

  Future<String?> stored() async =>
      (await SharedPreferences.getInstance()).getString(PendingInvite.storageKey);

  test('opening the invite link remembers the token; a blank one is ignored', () async {
    await PendingInvite.capture('  ');
    expect(await stored(), isNull);
    await PendingInvite.capture('tok-123');
    expect(await stored(), 'tok-123');
  });

  test('a valid invite links the client and is forgotten', () async {
    await PendingInvite.capture('tok-123');
    expect(await PendingInvite.redeem(Supabase.instance.client), InviteOutcome.linked);
    expect(server.lastToken, 'tok-123');
    expect(await stored(), isNull, reason: 'single use: nothing left to redeem');
  });

  test('an invite the server refuses (42501) is forgotten, not retried forever', () async {
    server
      ..status = 403
      ..error = {'code': '42501', 'message': 'invite not valid'};
    await PendingInvite.capture('tok-old');
    expect(await PendingInvite.redeem(Supabase.instance.client), InviteOutcome.invalid);
    expect(await stored(), isNull);
  });

  test('a failure that is not a refusal keeps the invite for the next sign-in', () async {
    server
      ..status = 404
      ..error = {'code': 'PGRST202', 'message': 'function not found'};
    await PendingInvite.capture('tok-123');
    expect(await PendingInvite.redeem(Supabase.instance.client), InviteOutcome.notYet);
    expect(await stored(), 'tok-123', reason: 'the server cannot redeem yet; keep it');
  });

  test('no remembered invite: nothing is called', () async {
    expect(await PendingInvite.redeem(Supabase.instance.client), InviteOutcome.none);
    expect(server.calls, 0);
  });

  test('overlapping redemptions are ONE attempt', () async {
    await PendingInvite.capture('tok-123');
    final a = PendingInvite.redeem(Supabase.instance.client);
    final b = PendingInvite.redeem(Supabase.instance.client);
    expect(await a, InviteOutcome.linked);
    expect(await b, InviteOutcome.linked,
        reason: 'a second attempt would call the invite just used invalid');
    expect(server.calls, 1);
  });
}
