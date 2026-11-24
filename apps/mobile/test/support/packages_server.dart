import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// P0-FL-56b · a fake PostgREST for coach packages, schedules, the marketplace
/// and cancel-subscription, with a REAL in-memory `coach_packages` table so a
/// partial save leaves exactly the rows it would leave.
///
/// Like PostgREST, a write answers with rows only when `select=` asks for them
/// (`204` with no body otherwise) — so code that does not ask cannot tell
/// "changed" from "changed nothing".
enum Answer {
  ok,

  /// RLS (or a wrong id) filtered the write to nothing.
  zeroRows,

  /// The server refused it: 500.
  fails,

  /// The database refused a delete: a client schedule references the row.
  foreignKey,

  /// The request never reached the server.
  network,
}

const userA = 'c0ac0000-0000-4000-8000-00000000000a';
const userB = 'c0ac0000-0000-4000-8000-00000000000b';

/// Never shown to anyone.
const secret = 'SECRET_BACKEND_TEXT';

class PackagesServer extends http.BaseClient {
  final packages = <Map<String, Object?>>[];

  /// `client_schedules` by client id.
  final schedules = <String, Map<String, Object?>>{};

  /// Relationships by client id.
  final relationships = <String, List<Map<String, Object?>>>{};
  List<Map<String, Object?>> coaches = [];
  Object? trainingDays = 3;
  Object? pricingMonthly;
  Object? cancelReply = {'ok': true};
  int cancelStatus = 200;

  /// How a read of `<table>` (or `rpc/<fn>`) answers; default ok.
  final readMode = <String, Answer>{};

  /// How a write (given its recorded line) answers; default ok.
  Answer Function(String line)? writeMode;

  /// Holds reads of a table / writes until completed.
  final readGate = <String, Completer<void>>{};
  Completer<void>? writeGate;

  /// `METHOD table?query body` of every write; every read's `table?query`.
  final writes = <String>[];
  final reads = <String>[];
  var _next = 0;

  void reset() {
    packages.clear();
    schedules.clear();
    relationships.clear();
    coaches = [];
    trainingDays = 3;
    pricingMonthly = null;
    cancelReply = {'ok': true};
    cancelStatus = 200;
    readMode.clear();
    writeMode = null;
    readGate.clear();
    writeGate = null;
    writes.clear();
    reads.clear();
  }

  int readsOf(String table) => reads.where((r) => r.startsWith('$table?')).length;

  static String? _eq(Uri u, String col) {
    final v = u.queryParameters[col];
    return v != null && v.startsWith('eq.') ? v.substring(3) : null;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final u = request.url;
    final path = u.path;
    if (path.startsWith('/auth/v1/')) {
      return http.StreamedResponse(const Stream.empty(), 204, request: request);
    }
    if (path.endsWith('/functions/v1/cancel-subscription')) {
      if (cancelStatus != 200) return _json({'error': secret}, cancelStatus, request);
      return _json(cancelReply, 200, request);
    }
    final isRpc = path.contains('/rpc/');
    final table = isRpc ? 'rpc/${path.split('/').last}' : path.split('/').last;
    if (request.method == 'GET' || isRpc) {
      reads.add('$table?${u.query}');
      final gate = readGate[table];
      if (gate != null) await gate.future;
      switch (readMode[table] ?? Answer.ok) {
        case Answer.network:
          throw http.ClientException('Connection refused', u);
        case Answer.fails:
          return _json({'message': secret, 'code': 'XX000'}, 500, request);
        default:
      }
      return _read(table, u, request);
    }
    final body = request is http.Request ? request.body : '';
    final line = '${request.method} $table?${u.query} $body';
    writes.add(line);
    if (writeGate != null) await writeGate!.future;
    final wantsRows = u.queryParameters.containsKey('select');
    switch (writeMode?.call(line) ?? Answer.ok) {
      case Answer.network:
        throw http.ClientException('Connection refused', u);
      case Answer.fails:
        return _json({'message': secret, 'code': 'XX000'}, 500, request);
      case Answer.foreignKey:
        return _json({'message': secret, 'code': '23503'}, 409, request);
      case Answer.zeroRows:
        return _rows(const [], wantsRows, request);
      case Answer.ok:
    }
    return _rows(_write(request.method, table, u, body), wantsRows, request);
  }

  List<Map<String, Object?>> _write(String method, String table, Uri u, String body) {
    final Map<String, Object?> data =
        body.isEmpty ? {} : Map<String, Object?>.from(jsonDecode(body) as Map);
    if (table == 'client_schedules') {
      final client = data['client_id'] as String;
      schedules[client] = data;
      return [{'id': 'schedule-$client'}];
    }
    if (table != 'coach_packages') return [{'id': 'row-1'}];
    final id = _eq(u, 'id');
    final hit = [for (final p in packages) if (p['id'] == id) p];
    switch (method) {
      case 'DELETE':
        packages.removeWhere((p) => p['id'] == id);
        return hit;
      case 'PATCH':
        for (final p in hit) {
          p.addAll(data);
        }
        return hit;
      default:
        final row = {'id': 'new-${_next++}', 'active': true, ...data};
        packages.add(row);
        return [row];
    }
  }

  http.StreamedResponse _read(String table, Uri u, http.BaseRequest r) {
    switch (table) {
      case 'coach_packages':
        final coach = _eq(u, 'coach_id');
        final type = _eq(u, 'type');
        final active = _eq(u, 'active');
        return _json([
          for (final p in packages)
            if ((coach == null || p['coach_id'] == coach) &&
                (type == null || p['type'] == type) &&
                (active == null || '${p['active']}' == active))
              p,
        ], 200, r);
      case 'client_schedules':
        return _single(schedules[_eq(u, 'client_id')], r);
      case 'user_profiles':
        return _single({
          'training_days_per_week': trainingDays,
          'pricing_monthly': pricingMonthly,
        }, r);
      case 'coach_client_relationships':
        final withCoach = _eq(u, 'coach_id');
        return _json([
          for (final rel in relationships[_eq(u, 'client_id')] ?? const [])
            if (withCoach == null || rel['coach_id'] == withCoach) rel,
        ], 200, r);
      case 'rpc/marketplace_coaches' || 'public_profiles':
        return _json(coaches, 200, r);
    }
    return _json([], 200, r);
  }

  /// `maybeSingle()` asks for a list here (postgrest-dart) or an object.
  http.StreamedResponse _single(Object? row, http.BaseRequest r) {
    final object = r.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
    if (object) return _json(row, 200, r);
    return _json([if (row != null) row], 200, r);
  }

  http.StreamedResponse _rows(List<Object?> rows, bool wanted, http.BaseRequest r) =>
      wanted
          ? _json(rows, 200, r)
          : http.StreamedResponse(const Stream.empty(), 204, request: r);

  http.StreamedResponse _json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

/// A session for [uid], as the auth client stores it (the JWT is not verified
/// client-side).
String sessionFor(String uid) {
  final exp =
      DateTime.now().add(const Duration(days: 3650)).millisecondsSinceEpoch ~/ 1000;
  return jsonEncode({
    'access_token': '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.'
        '${_b64({'sub': uid, 'role': 'authenticated', 'exp': exp, 'aud': 'authenticated'})}.'
        'not-verified-client-side',
    'token_type': 'bearer',
    'expires_in': 315360000,
    'expires_at': exp,
    'refresh_token': 'test-refresh-$uid',
    'user': {
      'id': uid,
      'app_metadata': {},
      'user_metadata': {},
      'aud': 'authenticated',
      'created_at': '2026-01-01T00:00:00Z',
    },
  });
}

class _Seeded extends LocalStorage {
  @override
  Future<void> initialize() async {}
  @override
  Future<String?> accessToken() async => sessionFor(userA);
  @override
  Future<bool> hasAccessToken() async => true;
  @override
  Future<void> persistSession(String persistSessionString) async {}
  @override
  Future<void> removePersistedSession() async {}
}

class _Memory extends GotrueAsyncStorage {
  final Map<String, String> _m = {};
  @override
  Future<String?> getItem({required String key}) async => _m[key];
  @override
  Future<void> setItem({required String key, required String value}) async =>
      _m[key] = value;
  @override
  Future<void> removeItem({required String key}) async => _m.remove(key);
}

/// Initialises Supabase on [server], signed in as [userA]. Unroutable URL.
Future<void> initPackagesSupabase(PackagesServer server) => Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: server,
      authOptions: FlutterAuthClientOptions(
        localStorage: _Seeded(),
        pkceAsyncStorage: _Memory(),
        detectSessionInUri: false,
      ),
      debug: false,
    );
