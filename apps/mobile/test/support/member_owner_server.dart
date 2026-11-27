import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'two_member_postgrest.dart';

export 'two_member_postgrest.dart'
    show memberA, memberB, initTwoMemberSupabase, refreshSession, signInAs, signOut;

/// P0-FL-62a1 · PostgREST + Edge Functions for two members on one device,
/// answering by WHO the bearer token says is asking (the real auth client
/// signs A and B in). Every request is logged with its body, so a test can see
/// which member a write or an invoke went out as, and with whose data.
///
/// Writes behave like the real server: a PATCH/POST/DELETE that does not ask
/// for rows back (`select=` absent) gets 204, and one that does gets a row
/// unless its key is in [zeroRows].
class MemberOwnerServer extends TwoMemberPostgrest {
  /// GET answers, keyed `table:who`, or `table:type:who` for a read filtered
  /// by `type=eq.<type>` (ai_insights). A Map answers a single-row read; a
  /// List a list read. Absent: no row / [].
  final answers = <String, Object?>{};

  /// Edge Function answers, keyed `function:who` (the decoded JSON body).
  final functions = <String, Object?>{};

  /// Keys (`METHOD table:who`) whose write matched no row.
  final zeroRows = <String>{};

  /// Keys whose request never reaches the server (http.ClientException).
  final offline = <String>{};

  /// `METHOD table:who ?query body` of every REST and function request.
  final log = <String>[];

  @override
  void reset() {
    super.reset();
    answers.clear();
    functions.clear();
    zeroRows.clear();
    offline.clear();
    log.clear();
  }

  /// The logged requests to [table] (or function) by [method], optionally
  /// only those [by] one member.
  List<String> of(String method, String table, {String? by}) => [
        for (final l in log)
          if (l.startsWith('$method $table:${by ?? ''}')) l
      ];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final u = request.url;
    if (u.path.startsWith('/auth/v1/')) return super.send(request);
    final table = u.path.split('/').last;
    final who = TwoMemberPostgrest.who(request);
    final key = '${request.method} $table:$who';
    final body = request is http.Request ? request.body : '';
    calls.add(key);
    log.add('$key ?${u.query} $body');
    final hold = holds[key];
    if (hold != null) await hold.future;
    if (offline.contains(key)) {
      throw http.ClientException('Connection refused', u);
    }
    if (fails.contains(key)) {
      return _json({'message': 'refused', 'code': 'XX000'}, 500, request);
    }
    if (u.path.contains('/functions/v1/')) {
      return _json(functions['$table:$who'] ?? {'reply': 'reply for $who'},
          200, request);
    }
    if (request.method != 'GET') {
      final asksForRows = u.queryParameters.containsKey('select');
      if (!asksForRows) {
        return http.StreamedResponse(const Stream.empty(), 204,
            request: request);
      }
      return _json(
          zeroRows.contains(key)
              ? []
              : [
                  {'id': 'row-1', 'user_id': who}
                ],
          200,
          request);
    }
    final single =
        request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
    final type = u.queryParameters['type'];
    final answer = (type != null && type.startsWith('eq.')
            ? answers['$table:${type.substring(3)}:$who']
            : null) ??
        answers['$table:$who'];
    if (answer is Map) return _json(single ? answer : [answer], 200, request);
    if (answer is List) {
      return _json(
          single ? (answer.isEmpty ? null : answer.first) : answer, 200, request);
    }
    return _json(single ? null : [], 200, request);
  }

  http.StreamedResponse _json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

/// Holds [key]'s requests until the returned completer completes.
Completer<void> holdOn(MemberOwnerServer s, String key) =>
    s.holds[key] = Completer<void>();
