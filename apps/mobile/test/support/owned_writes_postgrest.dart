import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'two_member_postgrest.dart';

/// One request as the server saw it: WHO asked (the bearer token's subject),
/// and what they sent.
class Asked {
  Asked(this.method, this.table, this.who, this.query, this.body);
  final String method, table, who, body;
  final Map<String, String> query;

  Map<String, dynamic> get json => jsonDecode(body) as Map<String, dynamic>;

  @override
  String toString() => '$method $table as ${who == memberA ? 'A' : who == memberB ? 'B' : who} $query $body';
}

/// [TwoMemberPostgrest]'s two members and real auth client, with a full request
/// log and rows a test gives per table and per asker (P0-FL-59c).
class OwnedWritesPostgrest extends TwoMemberPostgrest {
  final log = <Asked>[];

  /// The rows of a GET, by `table:<who asked>` first, then by table.
  final rows = <String, List<Map<String, Object?>>>{};

  /// What an RPC answers, by name.
  final rpcs = <String, Object?>{};

  /// Holds one request of several to the same table, which [holds] cannot tell
  /// apart.
  Completer<void>? Function(Asked)? gate;

  @override
  void reset() {
    super.reset();
    log.clear();
    rows.clear();
    rpcs.clear();
    gate = null;
  }

  Iterable<Asked> sent(String method, String table, [String? who]) => log.where(
      (a) =>
          a.method == method &&
          a.table == table &&
          (who == null || a.who == who));

  Iterable<Asked> writesAs(String who) =>
      log.where((a) => a.method != 'GET' && a.who == who);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final u = request.url;
    if (u.path == '/auth/v1/user' && request.method == 'PUT') {
      // A profile edit: the same member, as a new User (`userUpdated`).
      return _json({
        'id': TwoMemberPostgrest.who(request),
        'app_metadata': {},
        'user_metadata': {'edited': ++_edits},
        'aud': 'authenticated',
        'created_at': '2026-01-01T00:00:00Z',
      }, 200, request);
    }
    if (u.path.startsWith('/storage/v1/')) {
      final who = TwoMemberPostgrest.who(request);
      log.add(Asked(request.method, 'storage', who, {'path': u.path}, ''));
      await holds['${request.method} storage:$who']?.future;
      return _json(
          request.method == 'POST'
              ? {'Key': 'k'}
              : [
                  {'name': 'removed'}
                ],
          200,
          request);
    }
    if (!u.path.startsWith('/rest/v1/')) return super.send(request);
    final table = u.path.split('/').last;
    final who = TwoMemberPostgrest.who(request);
    final body = request is http.Request ? request.body : '';
    final asked = Asked(request.method, table, who, u.queryParameters, body);
    log.add(asked);
    final gated = gate?.call(asked);
    final key = '${request.method} $table:$who';
    final single =
        request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
    // What was true when the request ARRIVED.
    final answer = [...?(rows['$table:$who'] ?? rows[table])];
    final failed = fails.contains(key);
    await holds[key]?.future;
    await gated?.future;
    if (failed) {
      return _json(
          {'message': 'refused SECRET_TABLE', 'code': 'XX000'}, 500, request);
    }
    if (u.path.contains('/rpc/')) return _json(rpcs[table], 200, request);
    if (request.method == 'GET') {
      return _json(single ? (answer.isEmpty ? null : answer.first) : answer,
          200, request);
    }
    if (!u.queryParameters.containsKey('select')) {
      return http.StreamedResponse(const Stream.empty(), 204, request: request);
    }
    final row = {'id': 'row-1', 'user_id': 'client-1'};
    return _json(single ? row : [row], 200, request);
  }

  var _edits = 0;

  http.StreamedResponse _json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}
