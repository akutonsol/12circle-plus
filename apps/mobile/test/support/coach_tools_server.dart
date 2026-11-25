import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import 'two_member_postgrest.dart';

/// One request, with the account its bearer token names.
class Sent {
  Sent(this.method, this.path, this.query, this.body, this.who);
  final String method;
  final String path;
  final String query;
  final String body;
  final String who;

  String get table => path.split('/').last;
  bool get isWrite => method != 'GET' && method != 'HEAD';
  Map<String, Object?> get json => jsonDecode(body) as Map<String, Object?>;

  @override
  String toString() => '$method $path?$query $body as ${who == memberA ? 'A' : who == memberB ? 'B' : who}';
}

/// [TwoMemberPostgrest]'s real auth (A and B on one device) with any table,
/// RPC, Storage object and Edge Function behind it, and a log of WHO sent WHAT
/// (P0-FL-59d). A test can hold, fail or 0-row any request.
class CoachToolsServer extends TwoMemberPostgrest {
  /// Rows by table; a GET's `eq` filters on `coach_id`, `user_id`, `client_id`,
  /// `exercise_id` and `id` are applied.
  final tables = <String, List<Map<String, Object?>>>{};

  /// Answers to `/rest/v1/rpc/<fn>` and `/functions/v1/<fn>`.
  final answers = <String, Object?>{};

  final log = <Sent>[];

  /// Held until completed: the first match whose completer is unfinished.
  final held = <(bool Function(Sent), Completer<void>)>[];
  bool Function(Sent) failing = (_) => false;
  bool Function(Sent) offline = (_) => false;
  bool Function(Sent) zeroRows = (_) => false;

  Iterable<Sent> get writes => log.where((s) => s.isWrite);
  Iterable<Sent> writesBy(String uid) => writes.where((s) => s.who == uid);
  Iterable<Sent> to(String table) => log.where((s) => s.table == table);

  Completer<void> hold(bool Function(Sent) match) {
    final c = Completer<void>();
    held.add((match, c));
    return c;
  }

  @override
  void reset() {
    super.reset();
    tables.clear();
    answers.clear();
    log.clear();
    held.clear();
    failing = offline = zeroRows = (_) => false;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final u = request.url;
    if (u.path.startsWith('/auth/v1/')) return super.send(request);
    final body = request is http.Request ? request.body : '';
    final sent = Sent(request.method, u.path, Uri.decodeFull(u.query), body,
        TwoMemberPostgrest.who(request));
    log.add(sent);
    for (final (match, c) in held) {
      if (match(sent)) {
        // The answer is the one that was true when the request arrived.
        final answer = _answer(sent, request);
        await c.future;
        return answer;
      }
    }
    if (offline(sent)) throw http.ClientException('Connection refused', u);
    return _answer(sent, request);
  }

  http.StreamedResponse _answer(Sent s, http.BaseRequest r) {
    if (failing(s)) {
      return _json({'message': 'SECRET_TABLE refused', 'code': 'XX000'}, 500, r);
    }
    if (s.path.startsWith('/storage/v1/')) {
      if (s.path.contains('/object/sign/')) {
        return _json({'signedURL': '/object/sign/x?token=t'}, 200, r);
      }
      if (s.method == 'DELETE') {
        return _json([
          for (final p in s.json['prefixes'] as List) {'name': p}
        ], 200, r);
      }
      if (s.path.contains('/object/list/')) return _json([], 200, r);
      return _json({'Key': s.path, 'Id': 'obj'}, 200, r);
    }
    if (s.path.startsWith('/functions/v1/') || s.path.contains('/rpc/')) {
      return _json(answers[s.table], 200, r);
    }
    final single = r.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
    if (s.isWrite) {
      if (!r.url.queryParameters.containsKey('select')) {
        return http.StreamedResponse(const Stream.empty(), 204, request: r);
      }
      final row = <String, Object?>{'id': 'row-1', 'provider': 'x', 'exercise_id': 'ex-1'};
      final rows = zeroRows(s) ? const [] : [row];
      return _json(single ? row : rows, s.method == 'POST' ? 201 : 200, r);
    }
    bool matches(Map<String, Object?> row, String col) {
      final v = r.url.queryParameters[col];
      return v == null || !v.startsWith('eq.') || !row.containsKey(col) ||
          '${row[col]}' == v.substring(3);
    }

    final rows = [
      for (final row in tables[s.table] ?? const <Map<String, Object?>>[])
        if (['coach_id', 'user_id', 'client_id', 'exercise_id', 'id', 'slug']
            .every((c) => matches(row, c)))
          row
    ];
    return _json(single ? (rows.isEmpty ? null : rows.first) : rows, 200, r);
  }

  http.StreamedResponse _json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

/// Real time for the fake server and the auth stream, then frames.
Future<void> settleReal(WidgetTester t, {int rounds = 5}) async {
  for (var i = 0; i < rounds; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await t.pump(const Duration(milliseconds: 80));
  }
}

/// Signs [uid] in on the real auth stream, over whoever was signed in.
Future<void> switchTo(WidgetTester t, String uid) async {
  await t.runAsync(() => signInAs(uid));
  expect(Supabase.instance.client.auth.currentUser?.id, uid, reason: 'premise');
  await settleReal(t);
}

Future<void> signOutNow(WidgetTester t) async {
  await t.runAsync(signOut);
  expect(Supabase.instance.client.auth.currentUser, isNull, reason: 'premise');
  await settleReal(t);
}

/// The same account, as a new [User]: what must keep everything on screen.
Future<void> refreshToken(WidgetTester t) async {
  final before = Supabase.instance.client.auth.currentSession?.accessToken;
  await t.runAsync(refreshSession);
  expect(Supabase.instance.client.auth.currentSession?.accessToken, isNot(before),
      reason: 'premise: a new token');
  await settleReal(t);
}

/// The callback of the button labelled [text], kept to be fired later: a tap
/// that beats the screen's own reaction to a switch.
VoidCallback tapOf(WidgetTester t, String text) => t
    .widget<ButtonStyleButton>(find.ancestor(
        of: find.text(text), matching: find.bySubtype<ButtonStyleButton>()).first)
    .onPressed!;

/// Unmounts everything and lets scaffold timers run out.
Future<void> unmountAll(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 6));
}
