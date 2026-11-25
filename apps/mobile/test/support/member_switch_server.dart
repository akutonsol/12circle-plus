import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'two_member_postgrest.dart' hide refreshSession;

export 'two_member_postgrest.dart'
    show initTwoMemberSupabase, memberA, memberB, signInAs, signOut;

/// Refreshes the signed-in member's session: the same member, as a new [User].
/// Fails unless the event really reached the listeners (`recoverSession` for
/// the same uid sends none, so a control built on it controls nothing).
Future<void> refreshSession() async {
  final auth = Supabase.instance.client.auth;
  final uid = auth.currentUser?.id;
  final heard = <AuthChangeEvent>[];
  final sub = auth.onAuthStateChange.listen((s) => heard.add(s.event));
  await Future<void>.delayed(Duration.zero); // the replayed last event
  heard.clear();
  await auth.refreshSession();
  await Future<void>.delayed(Duration.zero);
  await sub.cancel();
  if (!heard.contains(AuthChangeEvent.tokenRefreshed) ||
      auth.currentUser?.id != uid) {
    throw StateError('no token refresh was heard: $heard');
  }
}

/// Signs [uid] in (null: out) and runs [act] the instant the auth client says
/// so: BEFORE any screen's own listener has heard it, so [act] meets only the
/// guard inside what it calls. [watchAuthChanges] must come first.
Future<void> switchAnd(String? uid, void Function() act) async {
  _atChange = act;
  await (uid == null ? signOut() : signInAs(uid));
  await Future<void>.delayed(const Duration(milliseconds: 20));
  if (_atChange != null) throw StateError('no auth change was heard');
}

void Function()? _atChange;

/// Once, in setUpAll: events reach listeners in the order they were made.
void watchAuthChanges() =>
    Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      final act = _atChange;
      _atChange = null;
      act?.call();
    });

/// One request the fake server saw, with the member whose token it carried.
class SeenRequest {
  SeenRequest(this.method, this.target, this.who, this.query, this.body);
  final String method;

  /// The table / RPC name, or the storage path after `/object/`.
  final String target;
  final String who;
  final Map<String, String> query;
  final Object? body;

  bool get isRead => method == 'GET';
  Map<String, dynamic> get row => body is List
      ? (body as List).single as Map<String, dynamic>
      : body as Map<String, dynamic>;
  String get key => '$method $target:$who';
  @override
  String toString() => '$key $query $body';
}

/// P0-FL-59e · two members on one device, real auth client: every request is
/// logged with WHO asked, and answered from [rows] — by table and member, as
/// row-level security would.
class MemberSwitchServer extends TwoMemberPostgrest {
  final seen = <SeenRequest>[];

  /// The requests in the order they were ANSWERED (a held one answers late).
  final answered = <SeenRequest>[];

  /// `table` → member → that member's rows (a missing one answers none).
  final rows = <String, Map<String, List<Map<String, Object?>>>>{};

  /// Keyed `METHOD target:who`: these writes match no row.
  final zeroRows = <String>{};

  /// Keyed `METHOD target:who`: these never reach the server.
  final offline = <String>{};

  /// What an Edge Function answers, by its name.
  final functions = <String, Object>{};

  /// Storage objects that exist (`uid/front.jpg`).
  final objects = <String>{};

  /// Storage objects whose signing answers 500.
  final unsignable = <String>{};

  /// Uploads by this member wait for [uploadGate] (their paths are not known).
  String? holdUploadsOf;
  Completer<void>? uploadGate;

  @override
  void reset() {
    super.reset();
    seen.clear();
    answered.clear();
    rows.clear();
    zeroRows.clear();
    offline.clear();
    functions.clear();
    objects.clear();
    unsignable.clear();
    holdUploadsOf = null;
    uploadGate = null;
  }

  Iterable<SeenRequest> writes([String? target]) => seen.where((r) =>
      !r.isRead &&
      !r.target.startsWith('sign/') &&
      (target == null || r.target == target));

  Iterable<SeenRequest> reads(String target, [String? who]) => seen.where((r) =>
      r.isRead && r.target == target && (who == null || r.who == who));

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (path.startsWith('/auth/v1/')) return super.send(request);
    final storage = path.startsWith('/storage/v1/object/');
    final target = storage
        ? path.substring('/storage/v1/object/'.length)
        : path.split('/').last;
    Object? body;
    if (request is http.Request && request.body.isNotEmpty) {
      try {
        body = jsonDecode(request.body);
      } catch (_) {
        body = 'binary';
      }
    } else if (request is http.MultipartRequest) {
      body = 'binary';
    }
    final r = SeenRequest(request.method, target,
        TwoMemberPostgrest.who(request), request.url.queryParameters, body);
    seen.add(r);
    // Decided when the request ARRIVES, as a server would.
    final (Object? answer, int status) =
        storage ? _storage(r) : _rest(r, request);
    final hold = holds[r.key];
    if (hold != null) await hold.future;
    if (r.target.startsWith('progress-photos/') && r.who == holdUploadsOf) {
      await uploadGate?.future;
    }
    answered.add(r);
    if (offline.contains(r.key)) {
      throw http.ClientException('no connection SECRET', request.url);
    }
    if (fails.contains(r.key)) {
      return _send(
          {'message': 'refused SECRET', 'code': 'XX000'}, 500, request);
    }
    return status == 204
        ? http.StreamedResponse(const Stream.empty(), 204, request: request)
        : _send(answer, status, request);
  }

  (Object?, int) _storage(SeenRequest r) {
    if (r.target.startsWith('sign/')) {
      final object = r.target.substring('sign/progress-photos/'.length);
      if (unsignable.contains(object)) {
        return ({'statusCode': '500', 'error': 'x', 'message': 'SECRET'}, 500);
      }
      return objects.contains(object) && object.startsWith(r.who)
          ? ({'signedURL': '/object/sign/progress-photos/$object?token=t'}, 200)
          : ({'statusCode': '404', 'error': 'not_found', 'message': 'no'}, 400);
    }
    if (r.target.startsWith('list/') || r.method == 'DELETE') {
      return (const [], 200);
    }
    return ({'Key': 'k'}, 200);
  }

  (Object?, int) _rest(SeenRequest r, http.BaseRequest request) {
    final function = functions[r.target];
    if (function != null) return (function, 200);
    final single =
        request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
    if (r.method == 'GET') {
      final mine = rows[r.target]?[r.who] ?? const [];
      return (single ? (mine.isEmpty ? null : mine.first) : mine, 200);
    }
    if (!r.query.containsKey('select')) return (null, 204);
    final out = zeroRows.contains(r.key)
        ? const <Map<String, Object?>>[]
        : [
            {
              'id': 'row-1',
              if (r.body is Map) ...r.body as Map<String, dynamic>,
              // An embed asked for is answered, as PostgREST would.
              if ('${r.query['select']}'.contains('public_profiles'))
                'public_profiles': {'first_name': 'Me', 'last_name': 'Myself'},
            }
          ];
    return (single ? (out.isEmpty ? null : out.first) : out, 200);
  }

  http.StreamedResponse _send(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}
