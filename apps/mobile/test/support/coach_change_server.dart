import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'two_member_postgrest.dart';

// P0-RM-1 · a fake PostgREST + functions server for the coach flows across an
// account change. It answers by WHO the bearer token names (RLS: each member
// sees their own rows), logs every non-auth request with who asked, and holds
// or fails a request by `METHOD name:<who>`. A write answers 204/empty unless
// it asks for its rows back (`select=`), so a dropped `.select('id')` shows.

/// One request as the server saw it.
typedef CoachReq = ({
  String who,
  String method,
  String name,
  Map<String, String> q,
  String body,
});

class CoachChangeServer extends TwoMemberPostgrest {
  final log = <CoachReq>[];

  /// Held until completed, keyed `METHOD name:<who>`. cancelCoach's own
  /// subscriptions read (it filters by `coach_id`) is
  /// `GET subscriptions/coach:<who>`. An answer is the one true on ARRIVAL.
  final gates = <String, Completer<void>>{};

  /// Answer 500, keyed the same way.
  final failing = <String>{};

  /// Each member's paid coaching subscriptions (ids), all with coach [coach].
  final paid = <String, List<String>>{};

  /// Each member's active coach id (none: no relationship row).
  final coachOf = <String, String>{};

  /// Coach profiles by id.
  final profiles = <String, Map<String, Object?>>{};

  /// PATCHes (`PATCH name:<who>`) that match no row.
  final noRows = <String>{};

  static const coach = 'c-1';
  static const endsAt = '2027-03-03T12:00:00Z';

  @override
  void reset() {
    super.reset();
    log.clear();
    gates.clear();
    failing.clear();
    paid.clear();
    coachOf.clear();
    profiles.clear();
    noRows.clear();
  }

  Iterable<CoachReq> named(String name, {String? method, String? who}) =>
      log.where((r) =>
          r.name == name &&
          (method == null || r.method == method) &&
          (who == null || r.who == who));

  Iterable<CoachReq> get invokes => named('cancel-subscription');

  /// REST writes (no functions, no rpc).
  Iterable<CoachReq> get restWrites => log.where((r) =>
      r.method != 'GET' &&
      r.name != 'cancel-subscription' &&
      !r.name.startsWith('rpc/'));

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final u = request.url;
    if (u.path.startsWith('/auth/v1/')) return super.send(request);
    final who = TwoMemberPostgrest.who(request);
    final name = u.path.contains('/rpc/')
        ? 'rpc/${u.path.split('/').last}'
        : u.path.split('/').last;
    final body = request is http.Request ? request.body : '';
    final r = (who: who, method: request.method, name: name, q: u.queryParameters, body: body);
    log.add(r);
    final key = name == 'subscriptions' && u.queryParameters.containsKey('coach_id')
        ? '${request.method} subscriptions/coach:$who'
        : '${request.method} $name:$who';
    final (status, answer) = _answer(r, request, key);
    final gate = gates[key];
    if (gate != null) await gate.future;
    if (failing.contains(key)) {
      return _json({'message': 'refused SECRET_TABLE', 'code': 'XX000'}, 500, request);
    }
    if (status == 204) {
      return http.StreamedResponse(const Stream.empty(), 204, request: request);
    }
    return _json(answer, status, request);
  }

  http.StreamedResponse _json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});

  (int, Object?) _answer(CoachReq r, http.BaseRequest request, String key) {
    final single = request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
    if (r.name == 'cancel-subscription') {
      return (200, {'ok': true, 'endsAt': endsAt});
    }
    if (r.name == 'rpc/client_plan') return (200, 'coach_guided');
    if (r.name.startsWith('rpc/')) return (200, null);
    if (r.method != 'GET') {
      if (!r.q.containsKey('select')) return (204, null);
      final rows = noRows.contains(key) ? const [] : [{'id': 'row-1'}];
      return (200, single ? (rows.isEmpty ? null : rows.first) : rows);
    }
    final rows = switch (r.name) {
      'subscriptions' => [
          for (final id in paid[r.who] ?? const <String>[])
            {
              'id': id,
              'user_id': r.who,
              'coach_id': coach,
              'kind': 'coach',
              'status': 'active',
              'current_period_end': endsAt,
            }
        ],
      'coach_client_relationships' => [
          if (coachOf[r.who] != null)
            {
              'id': 'rel-${r.who}',
              'coach_id': coachOf[r.who],
              'client_id': r.who,
              'status': 'active',
            }
        ],
      'public_profiles' => [...profiles.values],
      _ => const <Map<String, Object?>>[],
    };
    final found = [
      for (final row in rows)
        if (r.q.entries.every((f) => _matches(row, f.key, f.value))) row
    ];
    return (200, single ? (found.isEmpty ? null : found.first) : found);
  }

  static bool _matches(Map<String, Object?> row, String col, String v) {
    if (!row.containsKey(col)) return true;
    if (v.startsWith('eq.')) return '${row[col]}' == v.substring(3);
    if (v.startsWith('in.(') && v.endsWith(')')) {
      return v
          .substring(4, v.length - 1)
          .split(',')
          .map((x) => x.replaceAll('"', ''))
          .contains('${row[col]}');
    }
    return true;
  }
}
