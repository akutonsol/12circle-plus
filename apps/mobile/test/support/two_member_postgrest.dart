import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Two members (A and B) sharing one device, through the REAL Supabase auth
/// client: the fake server answers by WHO the request's bearer token says is
/// asking, and a test can hold or fail one member's requests (P0-FL-57a).
const memberA = 'c0ac0000-0000-4000-8000-00000000000a';
const memberB = 'c0ac0000-0000-4000-8000-00000000000b';

class TwoMemberPostgrest extends http.BaseClient {
  /// `challenges` rows (the same for everybody signed in).
  final challenges = <Map<String, Object?>>[];

  /// `challenge_participants` rows.
  final participants = <Map<String, Object?>>[];

  /// `custom_exercises` rows.
  final exercises = <Map<String, Object?>>[];

  /// Requests held until completed, keyed `METHOD table:<who asked>`. A held
  /// answer is the one that was true when the request ARRIVED.
  final holds = <String, Completer<void>>{};

  /// Requests that answer 500, keyed the same way.
  final fails = <String>{};

  /// `METHOD table:<who asked>` of every REST request.
  final calls = <String>[];

  void reset() {
    challenges.clear();
    participants.clear();
    exercises.clear();
    holds.clear();
    fails.clear();
    calls.clear();
  }

  static String? _eq(Uri u, String col) {
    final v = u.queryParameters[col];
    return v != null && v.startsWith('eq.') ? v.substring(3) : null;
  }

  /// The signed-in user the bearer token names, or 'anon'.
  static String who(http.BaseRequest r) {
    final parts = (r.headers['Authorization'] ?? '').split('.');
    if (parts.length != 3) return 'anon';
    final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
    return (claims as Map)['sub'] as String;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final u = request.url;
    if (u.path == '/auth/v1/token') {
      final body = jsonDecode((request as http.Request).body) as Map;
      final uid = '${body['refresh_token']}'.contains(memberA) ? memberA : memberB;
      return _json(jsonDecode(_session(uid, ++_refresh)), 200, request);
    }
    if (u.path.startsWith('/auth/v1/')) {
      return http.StreamedResponse(const Stream.empty(), 204, request: request);
    }
    final table = u.path.split('/').last;
    final key = '${request.method} $table:${who(request)}';
    calls.add(key);
    final answer = _answer(table, request);
    final hold = holds[key];
    if (hold != null) await hold.future;
    if (fails.contains(key)) {
      return _json(
          {'message': 'refused SECRET_TABLE', 'code': 'XX000'}, 500, request);
    }
    return answer();
  }

  http.StreamedResponse Function() _answer(String table, http.BaseRequest r) {
    final u = r.url;
    final single = r.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
    if (r.method != 'GET') {
      final asksForRows = u.queryParameters.containsKey('select');
      if (table == 'custom_exercises' && r.method == 'POST') {
        final row = {
          ...jsonDecode((r as http.Request).body) as Map<String, Object?>,
          'id': 'ex-new',
        };
        exercises.add(row);
        return () => _json(single ? row : [row], 201, r);
      }
      if (table == 'custom_exercises' && r.method == 'DELETE') {
        exercises.removeWhere((e) => e['id'] == _eq(u, 'id'));
      }
      return () => asksForRows
          ? _json([
              {'id': 'row-1'}
            ], 200, r)
          : http.StreamedResponse(const Stream.empty(), 204, request: r);
    }
    bool matches(Map<String, Object?> row, String col) {
      final want = _eq(u, col);
      return want == null || row[col] == want;
    }

    final List<Map<String, Object?>> rows = switch (table) {
      'challenges' => [...challenges],
      'challenge_participants' => [
          for (final p in participants)
            if (matches(p, 'user_id')) p
        ],
      'custom_exercises' => [
          for (final e in exercises)
            if (matches(e, 'coach_id') && matches(e, 'id') && matches(e, 'slug'))
              e
        ],
      _ => const [],
    };
    return () =>
        _json(single ? (rows.isEmpty ? null : rows.first) : rows, 200, r);
  }

  http.StreamedResponse _json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

/// A Supabase session for [uid] (the JWT is never verified client-side).
String _session(String uid, int refresh) {
  final exp =
      DateTime.now().add(const Duration(days: 3650)).millisecondsSinceEpoch ~/
          1000;
  final jwt = [
    _b64({'alg': 'HS256', 'typ': 'JWT'}),
    _b64({
      'sub': uid,
      'role': 'authenticated',
      'exp': exp,
      'aud': 'authenticated',
      'n': refresh,
    }),
    'not-verified-client-side',
  ].join('.');
  return jsonEncode({
    'access_token': jwt,
    'token_type': 'bearer',
    'expires_in': 315360000,
    'expires_at': exp,
    'refresh_token': 'test-refresh-$uid-$refresh',
    'user': {
      'id': uid,
      'app_metadata': {},
      // Differs per session, so a same-member refresh is a DIFFERENT User.
      'user_metadata': {'n': refresh},
      'aud': 'authenticated',
      'created_at': '2026-01-01T00:00:00Z',
    },
  });
}

var _refresh = 0;

/// Refreshes the signed-in member's session: the same member, as a new [User].
Future<void> refreshSession() =>
    Supabase.instance.client.auth.refreshSession();

/// Signs [uid] in on the real auth stream.
Future<void> signInAs(String uid) =>
    Supabase.instance.client.auth.recoverSession(_session(uid, ++_refresh));

Future<void> signOut() => Supabase.instance.client.auth.signOut();

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

/// Unroutable URL: nothing can reach a real service.
Future<void> initTwoMemberSupabase(http.BaseClient server) =>
    Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: server,
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryStore(),
        detectSessionInUri: false,
      ),
      debug: false,
    );
