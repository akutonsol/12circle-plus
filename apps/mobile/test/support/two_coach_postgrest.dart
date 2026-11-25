import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'two_member_postgrest.dart';

export 'two_member_postgrest.dart'
    show
        memberA,
        memberB,
        signInAs,
        signOut,
        refreshSession,
        initTwoMemberSupabase;

/// RPCs that only read.
const _readRpcs = {
  'rpc/get_client_assessment',
  'rpc/coach_client_ai_signals',
};

/// One write as it reached the server: who asked, what, and with which row.
typedef CoachWrite = ({String who, String method, String path, Map body});

/// Two coaches (A and B) sharing one device, through the REAL auth client
/// (P0-FL-59f). Every read answers with what RLS would show the coach the
/// bearer token names; every write is recorded with that coach.
class TwoCoachPostgrest extends TwoMemberPostgrest {
  /// `table` (or `rpc/<name>`) → coach → rows.
  final data = <String, Map<String, List<Map<String, Object?>>>>{};

  final writes = <CoachWrite>[];

  void seed(String table, String who, List<Map<String, Object?>> rows) =>
      (data[table] ??= {})[who] = rows;

  /// How many requests matched `METHOD table:<who>`.
  int count(String key) => calls.where((c) => c == key).length;

  List<CoachWrite> writesTo(String table) => [
        for (final w in writes)
          if (w.path.endsWith('/$table')) w
      ];

  @override
  void reset() {
    super.reset();
    data.clear();
    writes.clear();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (path.startsWith('/auth/v1/')) return super.send(request);
    final who = TwoMemberPostgrest.who(request);
    final table = path.contains('/rpc/')
        ? 'rpc/${path.split('/').last}'
        : path.split('/').last;
    final key = '${request.method} $table:$who';
    calls.add(key);
    final isRead = request.method == 'GET' || _readRpcs.contains(table);
    final single =
        request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
    // What is true when the request ARRIVES, whenever it is answered.
    // `col=eq.x` filters the rows that carry `col`.
    final rows = [
      for (final row in data[table]?[who] ?? const <Map<String, Object?>>[])
        if (request.url.queryParameters.entries.every((q) =>
            !row.containsKey(q.key) ||
            !q.value.startsWith('eq.') ||
            '${row[q.key]}' == q.value.substring(3)))
          row
    ];
    if (!isRead) {
      final raw = request is http.Request ? request.body : '';
      final Object? body = raw.isEmpty ? null : jsonDecode(raw);
      writes.add((
        who: who,
        method: request.method,
        path: path,
        body: body is Map ? body : <String, Object?>{'rows': body},
      ));
    }
    final hold = holds[key];
    if (hold != null) await hold.future;
    if (fails.contains(key)) {
      return _json(
          {'message': 'refused SECRET_TABLE', 'code': 'XX000'}, 500, request);
    }
    if (path.startsWith('/storage/')) {
      return _json({'message': 'not found', 'statusCode': '404'}, 400, request);
    }
    if (path.startsWith('/functions/')) {
      return _json({'sent': true}, 200, request);
    }
    if (table == 'rpc/get_or_create_conversation') {
      return _json('conv-of-$who', 200, request);
    }
    if (table.startsWith('rpc/')) return _json(rows, 200, request);
    if (isRead) {
      return _json(
          single ? (rows.isEmpty ? null : rows.first) : rows, 200, request);
    }
    if (!request.url.queryParameters.containsKey('select')) {
      return http.StreamedResponse(const Stream.empty(), 204, request: request);
    }
    const row = {'id': 'row-1', 'token': 'tok-1'};
    return _json(single ? row : [row], 200, request);
  }

  http.StreamedResponse _json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}
