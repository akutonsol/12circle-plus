import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'two_member_postgrest.dart';

/// One REST request, as the server saw it.
class Asked {
  Asked(this.method, this.table, this.who, this.query, this.body);
  final String method;
  final String table;

  /// The member the bearer token names, or 'anon'.
  final String who;
  final Map<String, String> query;
  final Map<String, Object?> body;

  @override
  String toString() => '$method $table:$who $query $body';
}

/// A PostgREST over real rows with the app's own-row rules: a read or a change
/// reaches only the rows the asking member owns (RLS filters in silence), an
/// insert for somebody else is refused, and a unique key answers 23505. A write
/// that does not ask for its rows back gets an empty answer, as the real one
/// does. Auth (sign-in, refresh, sign-out) is [TwoMemberPostgrest]'s.
///
/// [holds] and [fails] work as there (`METHOD table:<who>`); an answer is the
/// one that was true when the request ARRIVED.
class OwnedRowsPostgrest extends TwoMemberPostgrest {
  final rows = <String, List<Map<String, Object?>>>{};
  final log = <Asked>[];

  /// Requests that never reach the server.
  final offline = <String>{};

  /// Writes RLS filters to no row, in silence.
  final filtered = <String>{};

  /// Requests not answered yet, with what holds them.
  final _open = <http.BaseRequest, Completer<void>?>{};
  StreamSubscription<AuthState>? _auth;
  String? _authTold;

  /// Requests that arrived, plus those answered: changes whenever either does.
  int activity = 0;

  // By id: `recoverSession` for the member already signed in emits no event.
  String? get _authNow => Supabase.instance.client.auth.currentUser?.id;

  /// What has not happened yet that nothing is holding back.
  List<String> get waitingFor => [
        for (final e in _open.entries)
          if (e.value == null || e.value!.isCompleted)
            'an answer to ${e.key.method} ${e.key.url.path}',
        if (_authTold != _authNow) 'an auth change to be delivered',
      ];
  bool get idle => waitingFor.isEmpty;

  static const _ownerOf = {
    'goals': 'client_id',
    'notifications': 'recipient_id',
    'event_registrations': 'user_id',
  };
  static const _unique = {
    'event_registrations': ['event_id', 'user_id'],
    'accountability_pod_members': ['pod_id', 'user_id'],
  };

  @override
  void reset() {
    super.reset();
    rows.clear();
    log.clear();
    offline.clear();
    filtered.clear();
    _open.clear(); // of a test that ended, and will not be answered
    // Heard in the real zone: every file resets from `setUp`.
    _auth ??= Supabase.instance.client.auth.onAuthStateChange.listen(
        (s) => _authTold = s.session?.user.id,
        onError: (Object _) {});
  }

  List<Asked> writes(String table) =>
      log.where((a) => a.table == table && a.method != 'GET').toList();

  bool asked(String key) => log.any((a) => '${a.method} ${a.table}:${a.who}' == key);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    activity++;
    _open[request] = holds['${request.method} '
        '${request.url.path.split('/').last}:${TwoMemberPostgrest.who(request)}'];
    try {
      return await _send(request);
    } finally {
      activity++;
      _open.remove(request);
    }
  }

  Future<http.StreamedResponse> _send(http.BaseRequest request) async {
    final u = request.url;
    if (!u.path.startsWith('/rest/v1/')) return super.send(request);
    final table = u.path.split('/').last;
    final who = TwoMemberPostgrest.who(request);
    final raw = request is http.Request ? request.body : '';
    final body = raw.isEmpty
        ? const <String, Object?>{}
        : (jsonDecode(raw) as Map).cast<String, Object?>();
    final key = '${request.method} $table:$who';
    log.add(Asked(request.method, table, who, u.queryParameters, body));
    if (offline.contains(key)) {
      throw http.ClientException('Connection refused', u);
    }
    final failing = fails.contains(key);
    final (status, answer) =
        failing ? (500, null) : _answer(request, table, who, body, key);
    final hold = holds[key];
    if (hold != null) await hold.future;
    if (failing) {
      return _json({'message': 'refused SECRET_TABLE', 'code': 'XX000'}, 500, request);
    }
    return _json(answer, status, request);
  }

  (int, Object?) _answer(http.BaseRequest r, String table, String who,
      Map<String, Object?> body, String key) {
    final q = r.url.queryParameters;
    final all = rows.putIfAbsent(table, () => []);
    final owner = _ownerOf[table];
    bool mine(Map<String, Object?> row) => owner == null || row[owner] == who;
    bool matches(Map<String, Object?> row) => q.entries.every((e) {
          if (!e.value.startsWith('eq.')) return true;
          final want = e.value.substring(3);
          if (e.key == 'accountability_pod_members.user_id') {
            return rows['accountability_pod_members']?.any((m) =>
                    m['pod_id'] == row['id'] && m['user_id'] == want) ??
                false;
          }
          return '${row[e.key]}' == want;
        });

    final single = r.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
    if (r.method == 'GET') {
      final hit = [for (final row in all) if (mine(row) && matches(row)) {...row}];
      return (200, single ? (hit.isEmpty ? null : hit.first) : hit);
    }
    final wantsRows = q.containsKey('select');
    if (r.method == 'POST') {
      final insertOwner = table == 'accountability_pod_members' ? 'user_id' : owner;
      if (insertOwner != null &&
          table != 'notifications' &&
          body[insertOwner] != who) {
        return (403, {'message': 'row-level security', 'code': '42501'});
      }
      final unique = _unique[table];
      if (unique != null &&
          all.any((row) => unique.every((c) => row[c] == body[c]))) {
        return (409, {'message': 'duplicate key', 'code': '23505'});
      }
      all.add({'id': '$table-${all.length + 1}', ...body});
      return (201, wantsRows ? [all.last] : null);
    }
    final hit = filtered.contains(key)
        ? const <Map<String, Object?>>[]
        : [for (final row in all) if (mine(row) && matches(row)) row];
    if (r.method == 'DELETE') {
      all.removeWhere(hit.contains);
    } else {
      for (final row in hit) {
        row.addAll(body);
      }
    }
    return wantsRows ? (200, [for (final row in hit) {...row}]) : (204, null);
  }

  http.StreamedResponse _json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(
          status == 204 || (status == 201 && body == null)
              ? const Stream.empty()
              : Stream.value(utf8.encode(jsonEncode(body))),
          status,
          request: r,
          headers: {'content-type': 'application/json'});
}
