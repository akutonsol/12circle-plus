import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// A signed-in Supabase backed by a fake PostgREST that behaves like the real
/// one about WRITES: a PATCH/POST that does not ask for rows back
/// (`select=` absent) gets `204` with no body — exactly what a 0-row update
/// looks like too. So code that does not request its row back cannot tell
/// "changed" from "changed nothing", and the tests can see that.
///
/// P0-FL-9 (updates that report success without verifying a changed row).

enum WriteMode {
  /// The write matched one row and returns it when asked.
  oneRow,

  /// RLS (or a wrong id) filtered the write to nothing: `200 []` when rows
  /// were asked for, `204` otherwise.
  zeroRows,

  /// The server refused it: `500` (a PostgrestException, NOT a network error).
  serverError,

  /// The request never reached the server (http.ClientException).
  network,
}

class RowCheckingPostgrest extends http.BaseClient {
  RowCheckingPostgrest(this.uid);

  final String uid;
  WriteMode mode = WriteMode.oneRow;

  /// Answers to reads, by table name (`/rest/v1/<table>`). A map answers a
  /// single-object read; it is wrapped in a list for a list read.
  final Map<String, Object> reads = {};

  /// Every non-GET request: `METHOD /path?query body`.
  final writes = <String>[];

  void reset() {
    mode = WriteMode.oneRow;
    reads.clear();
    writes.clear();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final body = request is http.Request ? request.body : '';
    if (path.contains('/auth/v1/logout')) {
      return http.StreamedResponse(const Stream.empty(), 204, request: request);
    }
    if (request.method == 'PATCH' || request.method == 'POST') {
      writes.add('${request.method} $path?${request.url.query} $body');
      final asksForRows = request.url.queryParameters.containsKey('select');
      switch (mode) {
        case WriteMode.network:
          throw http.ClientException('Connection refused', request.url);
        case WriteMode.serverError:
          return _json({'message': 'refused', 'code': 'XX000'}, 500, request);
        case WriteMode.zeroRows:
          return asksForRows
              ? _json([], 200, request)
              : http.StreamedResponse(const Stream.empty(), 204,
                  request: request);
        case WriteMode.oneRow:
          return asksForRows
              ? _json([
                  {'id': 'row-1'}
                ], 200, request)
              : http.StreamedResponse(const Stream.empty(), 204,
                  request: request);
      }
    }
    final single =
        request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
    final table = path.split('/').last;
    final answer = reads[table];
    if (answer is Map) return _json(single ? answer : [answer], 200, request);
    if (answer is List) return _json(answer, 200, request);
    return _json(single ? null : [], 200, request);
  }

  http.StreamedResponse _json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

class _SeededSession extends LocalStorage {
  _SeededSession(this.uid);
  final String uid;

  String _jwt() {
    final exp =
        DateTime.now().add(const Duration(days: 3650)).millisecondsSinceEpoch ~/
            1000;
    return '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.'
        '${_b64({
          'sub': uid,
          'role': 'authenticated',
          'exp': exp,
          'aud': 'authenticated'
        })}.'
        'not-verified-client-side';
  }

  @override
  Future<void> initialize() async {}
  @override
  Future<String?> accessToken() async => jsonEncode({
        'access_token': _jwt(),
        'token_type': 'bearer',
        'expires_in': 315360000,
        'refresh_token': 'test-refresh',
        'user': {
          'id': uid,
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

/// Initialises the Supabase singleton against [server] with a seeded session.
/// Unroutable URL: nothing can reach a real service.
Future<void> initSignedInSupabase(RowCheckingPostgrest server) =>
    Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: server,
      authOptions: FlutterAuthClientOptions(
        localStorage: _SeededSession(server.uid),
        pkceAsyncStorage: _MemoryStore(),
        detectSessionInUri: false,
      ),
      debug: false,
    );
