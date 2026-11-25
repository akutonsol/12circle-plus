import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'two_member_postgrest.dart' show TwoMemberPostgrest, memberA, memberB;

/// One request, with who asked (the uid the bearer token names).
typedef Asked = ({String method, String table, String who, String query, String body});

/// The workout tables, as two members on one device see them (P0-FL-59b).
///
/// Row security as the live policies have it: a member reads and updates only
/// rows whose `user_id` is theirs (anything else matches NOTHING, silently),
/// and an insert is checked on `user_id` alone — a set log naming another
/// member's `session_id` is accepted, and occupies `(session_id, set_id)`.
class WorkoutMembersServer extends http.BaseClient {
  final sessions = <Map<String, Object?>>[];
  final setLogs = <Map<String, Object?>>[];

  /// Other reads, keyed `table:<who>`.
  final rows = <String, List<Map<String, Object?>>>{};

  /// Requests held until completed / answering 500, keyed `METHOD table:<who>`.
  /// A held request has already been decided — and, when it is a write, made.
  final holds = <String, Completer<void>>{};
  final fails = <String>{};

  /// The same, for the requests [holdWhere] picks out of one table's.
  bool Function(Asked)? holdWhere;
  Completer<void>? heldByWhere;

  /// What an RPC or an Edge Function answers, keyed `name:<who>`.
  final answers = <String, Object?>{};

  /// Rows that stop matching updates — as a row the caller may no longer touch.
  final locked = <Object?>{};

  final asked = <Asked>[];
  int _ids = 0;

  void reset() {
    sessions.clear();
    setLogs.clear();
    rows.clear();
    holds.clear();
    fails.clear();
    holdWhere = null;
    heldByWhere = null;
    answers.clear();
    locked.clear();
    asked.clear();
    _ids = 0;
  }

  /// Every write (anything but GET, and not the auth server), optionally by one
  /// member and to one table.
  List<Asked> writes({String? by, String? to}) => [
        for (final a in asked)
          if (a.method != 'GET' &&
              (by == null || a.who == by) &&
              (to == null || a.table == to))
            a
      ];

  Map<String, Object?> seedSession(String uid,
      {required String workoutId, required String title, Map<String, Object?>? snapshot}) {
    final row = <String, Object?>{
      'id': 'session-${++_ids}',
      'user_id': uid,
      'workout_id': workoutId,
      'workout_title': title,
      'workout_snapshot': snapshot,
      'status': 'in_progress',
      'elapsed_seconds': 0,
      'started_at': '2026-11-25T10:00:00Z',
      'warmup_acknowledged_at': '2026-11-25T10:00:30Z',
    };
    sessions.add(row);
    return row;
  }

  static bool _matches(Map<String, Object?> row, Uri u) {
    for (final e in u.queryParameters.entries) {
      final v = e.value;
      if (const {'select', 'order', 'limit', 'on_conflict', 'columns'}.contains(e.key)) continue;
      final have = row[e.key]?.toString();
      if (v.startsWith('eq.') && have != v.substring(3)) return false;
      if (v.startsWith('in.') &&
          !v.substring(4, v.length - 1).split(',').map((s) => s.replaceAll('"', '')).contains(have)) {
        return false;
      }
      if (v == 'is.null' && have != null) return false;
    }
    return true;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final u = request.url;
    if (u.path == '/auth/v1/token') {
      final body = jsonDecode((request as http.Request).body) as Map;
      final uid = '${body['refresh_token']}'.contains(memberA) ? memberA : memberB;
      return _json(_refreshed(uid), 200, request);
    }
    if (u.path.startsWith('/auth/v1/')) return _empty(request);
    final table = u.path.split('/').last;
    final who = TwoMemberPostgrest.who(request);
    final body = request is http.Request ? request.body : '';
    final Asked ask =
        (method: request.method, table: table, who: who, query: u.query, body: body);
    asked.add(ask);
    final key = '${request.method} $table:$who';
    final failing = fails.contains(key);
    final answer = failing ? null : _answer(request, table, who, body);
    final hold = holds[key];
    if (hold != null) await hold.future;
    if (holdWhere?.call(ask) ?? false) await heldByWhere!.future;
    if (failing) return _json({'message': 'refused SECRET', 'code': 'XX000'}, 500, request);
    return answer!;
  }

  http.StreamedResponse _answer(http.BaseRequest r, String table, String who, String body) {
    final u = r.url;
    final wantsRows = u.queryParameters.containsKey('select');
    final single = r.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
    final store = switch (table) {
      'workout_sessions' => sessions,
      'workout_set_logs' => setLogs,
      _ => null,
    };
    if (r.method == 'GET') {
      final found = [
        if (store != null)
          for (final row in store)
            if (row['user_id'] == who && _matches(row, u)) row
      ];
      if (store == null) found.addAll(rows['$table:$who'] ?? const []);
      if (single) return _json(found.isEmpty ? null : found.first, 200, r);
      return _json(found, 200, r);
    }
    if (answers.containsKey('$table:$who')) return _json(answers['$table:$who'], 200, r);
    if (store == null) return wantsRows ? _json([{'id': 'row'}], 200, r) : _empty(r);
    final sent = Map<String, Object?>.from(jsonDecode(body) as Map);
    if (r.method == 'PATCH') {
      final hit = [
        for (final row in store)
          if (row['user_id'] == who && !locked.contains(row['id']) && _matches(row, u)) row
      ];
      for (final row in hit) {
        row.addAll(sent);
      }
      return wantsRows ? _json([for (final h in hit) {'id': h['id']}], 200, r) : _empty(r);
    }
    if (sent['user_id'] != who) {
      return _json({'message': 'row-level security', 'code': '42501'}, 403, r);
    }
    if (table == 'workout_set_logs' &&
        store.any((x) => x['session_id'] == sent['session_id'] && x['set_id'] == sent['set_id'])) {
      return _json({'message': 'duplicate key', 'code': '23505'}, 409, r);
    }
    final row = {'id': '$table-${++_ids}', 'started_at': '2026-11-25T11:00:00Z', ...sent};
    store.add(row);
    if (!wantsRows) return http.StreamedResponse(const Stream.empty(), 201, request: r);
    return _json(single ? row : [row], 201, r);
  }

  /// A refreshed session for [uid]: the same member, as a different `User`.
  Map<String, Object?> _refreshed(String uid) {
    String b64(Map<String, Object?> m) =>
        base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
    final exp = DateTime.now().add(const Duration(days: 3650)).millisecondsSinceEpoch ~/ 1000;
    final n = ++_ids;
    return {
      'access_token': '${b64({'alg': 'HS256', 'typ': 'JWT'})}.'
          '${b64({'sub': uid, 'role': 'authenticated', 'exp': exp, 'aud': 'authenticated', 'n': n})}.x',
      'token_type': 'bearer',
      'expires_in': 315360000,
      'expires_at': exp,
      'refresh_token': 'test-refresh-$uid-r$n',
      'user': {
        'id': uid,
        'app_metadata': {},
        'user_metadata': {'refreshed': n},
        'aud': 'authenticated',
        'created_at': '2026-01-01T00:00:00Z',
      },
    };
  }

  http.StreamedResponse _empty(http.BaseRequest r) =>
      http.StreamedResponse(const Stream.empty(), 204, request: r);

  http.StreamedResponse _json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}
