import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/core/router/app_router.dart';
import 'package:circle_fitness/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Two members (A and B) on one device through the REAL Supabase auth client,
/// for tests that mount the real app (P0-FL-59a). The fake server answers by
/// WHO the request's bearer token names, filters by the `eq.` filters it was
/// sent, and records every request; a fake realtime socket speaks the channel
/// protocol, so channels really join and leave.
const acctA = 'acc7a000-0000-4000-8000-00000000000a';
const acctB = 'acc7b000-0000-4000-8000-00000000000b';

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

var _n = 0;

/// A session for [uid]; a new access token and a new [User] every time.
Map<String, Object?> sessionOf(String uid, {bool expired = false}) {
  final n = ++_n;
  final at = DateTime.now().add(Duration(days: expired ? -1 : 3650));
  final exp = at.millisecondsSinceEpoch ~/ 1000;
  return {
    'access_token': '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.${_b64({
          'sub': uid,
          'role': 'authenticated',
          'aud': 'authenticated',
          'exp': exp,
          'n': n,
        })}.unsigned',
    'token_type': 'bearer',
    'expires_in': expired ? -86400 : 315360000,
    'expires_at': exp,
    'refresh_token': 'refresh-$uid-$n',
    'user': userOf(uid, n: n),
  };
}

Map<String, Object?> userOf(String uid, {int n = 0}) => {
      'id': uid,
      'app_metadata': {},
      'user_metadata': {'n': n},
      'aud': 'authenticated',
      'created_at': '2026-01-01T00:00:00Z',
    };

/// One request, as the server saw it.
class Sent {
  Sent(this.who, this.method, this.url, this.body);
  final String who;
  final String method;
  final Uri url;
  final String body;

  /// Last path segment: the table, the RPC or the auth endpoint.
  String get name => url.path.split('/').last;

  /// `METHOD name:who`.
  String get key => '$method $name:$who';
  @override
  String toString() => '$key ${url.query} $body';
}

class AccountServer extends http.BaseClient {
  /// Rows by `name:who` (`user_profiles:<uid>`), else by `name`.
  final rows = <String, List<Map<String, Object?>>>{};

  /// Held until completed, by [Sent.key] (or `METHOD name` for anyone).
  final holds = <String, Completer<void>>{};

  /// Keys that answer with this status.
  final fails = <String, int>{};

  /// Members all of whose REST reads (bar `user_profiles`, which routes them)
  /// are held, or fail.
  final holdAll = <String, Completer<void>>{};

  /// REST writes match no row.
  bool emptyWrites = false;

  /// Keys whose request throws this.
  final throws = <String, Object>{};

  /// Keys whose connection drops.
  final drops = <String>{};
  final failAll = <String>{};

  /// What exchanging an auth code answers: a session, or null to refuse it.
  Map<String, Object?>? codeSession;

  final sent = <Sent>[];

  void reset() {
    rows.clear();
    holds.clear();
    fails.clear();
    holdAll.clear();
    drops.clear();
    throws.clear();
    emptyWrites = false;
    failAll.clear();
    codeSession = null;
    sent.clear();
  }

  static String who(http.BaseRequest r) =>
      sub((r.headers['Authorization'] ?? '').replaceFirst('Bearer ', ''));

  /// Whom an access token names, or 'anon'.
  static String sub(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return 'anon';
    final claims =
        jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
    return (claims as Map)['sub'] as String;
  }

  Iterable<Sent> of(String name, {String? method, String? by}) => sent.where(
      (s) =>
          s.name == name &&
          (method == null || s.method == method) &&
          (by == null || s.who == by));

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final s = Sent(who(request), request.method, request.url,
        request is http.Request ? request.body : '');
    sent.add(s);
    final hold = holds[s.key] ?? holds['${s.method} ${s.name}'];
    if (hold != null) await hold.future;
    if (drops.contains(s.key) || drops.contains('${s.method} ${s.name}')) {
      throw http.ClientException('Connection closed', request.url);
    }
    final thrown = throws[s.key];
    if (thrown != null) throw thrown;
    final fail = fails[s.key] ?? fails['${s.method} ${s.name}'];
    if (fail != null) {
      return _json({'message': 'refused', 'code': 'XX000'}, fail, request);
    }
    if (s.url.path.startsWith('/auth/v1/')) return _auth(s, request);
    if (s.name != 'user_profiles') {
      await holdAll[s.who]?.future;
      if (failAll.contains(s.who)) {
        return _json({'message': 'refused', 'code': 'XX000'}, 403, request);
      }
    }
    if (s.url.path.startsWith('/storage/v1/object/sign/')) {
      return _json(
          {'signedURL': s.url.path.replaceFirst('/storage/v1', '')}, 200, request);
    }
    if (s.url.path.startsWith('/storage/')) {
      return _json({'statusCode': '404', 'message': 'not found'}, 400, request);
    }
    if (s.url.path.startsWith('/functions/')) {
      return _json({'error': 'unavailable'}, 500, request);
    }
    final single =
        request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
    if (s.method != 'GET' && !s.url.path.contains('/rpc/')) {
      if (emptyWrites && !single && s.url.queryParameters.containsKey('select')) {
        return _json([], 200, request);
      }
      return s.url.queryParameters.containsKey('select')
          ? _json(
              single
                  ? {'id': 'row-1'}
                  : [
                      {'id': 'row-1'}
                    ],
              200,
              request)
          : http.StreamedResponse(const Stream.empty(), 204, request: request);
    }
    final found = [
      for (final r in rows['${s.name}:${s.who}'] ?? rows[s.name] ?? const [])
        if (s.url.queryParameters.entries.every((q) =>
            !q.value.startsWith('eq.') ||
            !r.containsKey(q.key) ||
            '${r[q.key]}' == q.value.substring(3)))
          r
    ];
    return _json(
        single ? (found.isEmpty ? null : found.first) : found, 200, request);
  }

  http.StreamedResponse _auth(Sent s, http.BaseRequest r) {
    switch (s.name) {
      case 'token':
        if (s.url.queryParameters['grant_type'] == 'pkce') {
          final session = codeSession;
          return session == null
              ? _json({'error_code': 'flow_state_expired', 'msg': 'expired'},
                  403, r)
              : _json(session, 200, r);
        }
        final body = jsonDecode(s.body) as Map;
        final uid = body['email'] as String? ??
            ('${body['refresh_token']}'.contains(acctA) ? acctA : acctB);
        return _json(sessionOf(uid), 200, r);
      case 'signup': // no email confirmation: signed in at once
        return _json(sessionOf((jsonDecode(s.body) as Map)['email'] as String),
            200, r);
      case 'user':
        return _json(userOf(s.who, n: ++_n), 200, r);
      default:
        return http.StreamedResponse(const Stream.empty(), 204, request: r);
    }
  }

  http.StreamedResponse _json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

/// The realtime server's end of the socket.
class FakeRealtime {
  _FakeSocket? _socket;

  /// Joined channels and their postgres_changes filters.
  final joined = <String, List<Map<String, dynamic>>>{};

  WebSocketChannel connect(String url, Map<String, String> headers) {
    joined.clear();
    return _socket = _FakeSocket(this);
  }

  /// Channels joined with a filter that mentions [uid].
  Iterable<String> joinedFor(String uid) => joined.entries
      .where((e) => e.value.any((f) => '${f['filter']}'.contains(uid)))
      .map((e) => e.key);

  void _receive(String raw) {
    final msg = jsonDecode(raw) as Map<String, dynamic>;
    final topic = msg['topic'] as String;
    Map<String, dynamic> response = {};
    switch (msg['event']) {
      case 'phx_join':
        final config = (msg['payload'] as Map)['config'] as Map;
        final filters = [
          for (final (i, f)
              in ((config['postgres_changes'] as List?) ?? const []).indexed)
            {...(f as Map<String, dynamic>), 'id': 100 + i},
        ];
        joined[topic] = filters;
        response = {'postgres_changes': filters};
      case 'phx_leave':
        joined.remove(topic);
      case 'heartbeat':
        break;
      default:
        return;
    }
    _send({
      'topic': topic,
      'event': 'phx_reply',
      'payload': {'status': 'ok', 'response': response},
      'ref': msg['ref'],
    });
  }

  void _send(Map<String, dynamic> m) {
    final socket = _socket;
    if (socket != null && !socket.toClient.isClosed) {
      socket.toClient.add(jsonEncode(m));
    }
  }

  /// An INSERT into `notifications`, to every channel still listening to it.
  void notify(Map<String, Object?> record) {
    for (final e in joined.entries.toList()) {
      if (!e.value.any((f) => f['table'] == 'notifications')) continue;
      _send({
        'topic': e.key,
        'event': 'postgres_changes',
        'payload': {
          'ids': [for (final f in e.value) f['id']],
          'data': {
            'type': 'INSERT',
            'schema': 'public',
            'table': 'notifications',
            'commit_timestamp': '2026-11-12T10:00:00Z',
            'columns': [
              for (final k in record.keys) {'name': k, 'type': 'text'},
            ],
            'record': record,
            'errors': null,
          },
        },
        'ref': null,
      });
    }
  }
}

class _FakeSocket implements WebSocketChannel {
  _FakeSocket(this.server);
  final FakeRealtime server;
  final toClient = StreamController<String>();
  late final WebSocketSink _sink = _FakeSink(server, this);
  @override
  Stream<dynamic> get stream => toClient.stream;
  @override
  WebSocketSink get sink => _sink;
  @override
  Future<void> get ready => Future.value();
  @override
  String? get protocol => null;
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSink implements WebSocketSink {
  _FakeSink(this.server, this.socket);
  final FakeRealtime server;
  final _FakeSocket socket;
  @override
  void add(dynamic data) => server._receive(data as String);
  @override
  Future<void> close([int? closeCode, String? closeReason]) =>
      socket.toClient.close();
  @override
  Future<void> get done => Completer<void>().future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// gotrue's store for the PKCE code verifier.
class MemoryStore extends GotrueAsyncStorage {
  final m = <String, String>{};

  /// The device refuses removals (as a failing secure store or a full disk).
  bool refuseRemoval = false;

  /// After each refusal.
  void Function()? onRefused;
  @override
  Future<String?> getItem({required String key}) async => m[key];
  @override
  Future<void> setItem({required String key, required String value}) async =>
      m[key] = value;
  @override
  Future<void> removeItem({required String key}) async {
    if (refuseRemoval) {
      onRefused?.call();
      throw StateError('storage: cannot remove $key');
    }
    m.remove(key);
  }

  /// As if this device had asked for a reset email.
  void askedForReset() =>
      m['supabase.auth.token-code-verifier'] = 'verifier/passwordRecovery';
}

/// The session supabase_flutter keeps for the next start.
class MemorySession extends LocalStorage {
  String? stored;
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> hasAccessToken() async => stored != null;
  @override
  Future<String?> accessToken() async => stored;
  @override
  Future<void> persistSession(String persistSessionString) async =>
      stored = persistSessionString;
  @override
  Future<void> removePersistedSession() async => stored = null;

  /// Whose user, on whose token.
  (String user, String token)? get who {
    final s = stored;
    if (s == null) return null;
    final m = jsonDecode(s) as Map;
    return (
      (m['user'] as Map)['id'] as String,
      AccountServer.sub(m['access_token'] as String)
    );
  }
}

/// Unroutable URL: nothing can reach a real service.
Future<void> initAccountSupabase(
        AccountServer server, FakeRealtime realtime, MemoryStore store,
        {LocalStorage session = const EmptyLocalStorage()}) =>
    Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: server,
      realtimeClientOptions: RealtimeClientOptions(transport: realtime.connect),
      authOptions: FlutterAuthClientOptions(
        localStorage: session,
        pkceAsyncStorage: store,
        detectSessionInUri: false,
        autoRefreshToken: true,
      ),
      debug: false,
    );

GoTrueClient get _auth => Supabase.instance.client.auth;

/// Signs [uid] in on the real auth stream, as another web tab's session does.
Future<void> signInAs(String uid) =>
    _auth.recoverSession(jsonEncode(sessionOf(uid)));

Future<void> signOut() => _auth.signOut();

/// The same member's session renewed in this tab: an event really fires
/// (`recoverSession` of the same uid fires none).
Future<void> renewToken() =>
    _expectEvent(_auth.refreshSession, AuthChangeEvent.tokenRefreshed);

/// The same member, with a newer session, from another tab (a broadcast).
Future<void> sameMemberInAnotherTab(String uid) => _expectEvent(() async {
      final session = await _auth.recoverSession(jsonEncode(sessionOf(uid)));
      // What gotrue's broadcast channel does with a message.
      // ignore: invalid_use_of_internal_member
      _auth.notifyAllSubscribers(AuthChangeEvent.signedIn,
          session: session.session, broadcast: false);
      return null;
    }, AuthChangeEvent.signedIn);

/// Runs [f] and checks that [event], for whoever was signed in, arrived.
Future<void> _expectEvent(
    Future<Object?> Function() f, AuthChangeEvent event) async {
  final uid = _auth.currentUser!.id;
  final heard = <AuthState>[];
  final sub = _auth.onAuthStateChange
      .listen(heard.add, onError: (Object _, StackTrace __) {});
  await Future<void>.delayed(Duration.zero);
  heard.clear(); // the replayed one
  await f();
  await Future<void>.delayed(Duration.zero);
  await sub.cancel();
  expect(heard.map((s) => (s.event, s.session?.user.id)), [(event, uid)],
      reason: 'premise: the same account\'s event arrives');
}

/// The session ends remotely: the refresh token is refused.
Future<void> expire(AccountServer server) async {
  server.fails['POST token'] = 400;
  try {
    await _auth.refreshSession();
  } catch (_) {/* refused, as intended */}
  server.fails.remove('POST token');
}

// ── The real app root, mounted ──────────────────────────────────────────────

ProviderContainer appContainer(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(MaterialApp)),
        listen: false);

GoRouter appRouter(WidgetTester t) => appContainer(t).read(routerProvider);

String appPath(WidgetTester t) =>
    appRouter(t).routerDelegate.currentConfiguration.uri.path;

Future<void> settleApp(WidgetTester t, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await t
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
    await t.pump(const Duration(milliseconds: 50));
  }
}

/// Mounts the app signed in as [as] (or signed out) and goes to [at].
Future<void> mountApp(WidgetTester t,
    {required String? as,
    String? at,
    List<Override> overrides = const []}) async {
  t.view.physicalSize = const Size(900, 2600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.runAsync(signOut);
  if (as != null) await t.runAsync(() => signInAs(as));
  await t.pumpWidget(
      CircleFitnessRoot(theme: ThemeData.dark(), overrides: overrides));
  await settleApp(t, 4);
  if (at != null) {
    appRouter(t).go(at);
    await settleApp(t);
    expect(appPath(t), at, reason: 'premise: on $at');
  }
}

/// Unmounts and lets every channel and timer run out.
Future<void> unmountApp(WidgetTester t, AccountServer server) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 1));
  await Supabase.instance.client.removeAllChannels();
  await Supabase.instance.client.realtime.disconnect();
  await t.pump(const Duration(minutes: 3));
  server.fails.clear();
  await t.runAsync(signOut);
  await t.pump(const Duration(seconds: 1));
}
