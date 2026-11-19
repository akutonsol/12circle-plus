import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/dashboard/presentation/coach_dashboard_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// P0-FL-14 · the coach's notifications provider, run for real against a fake
// PostgREST and a fake realtime socket (the harness of
// notifications_stream_recovers_test.dart, the client-side twin).
//
// At 2ecd6e2 `coachNotificationsProvider` ended `.handleError((_) => [])`, so a
// failed fetch arrived as an EMPTY LIST: the bell read 0 unread and the sheet
// "No notifications yet". And supabase's `.stream()` ends for good after a
// failed fetch, so nothing ever corrected it.

const _uid = '00000000-0000-4000-8000-0000000c0b31';

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

/// The token is read, never verified client-side.
String _jwt() {
  final exp = DateTime.now().add(const Duration(days: 3650)).millisecondsSinceEpoch ~/ 1000;
  return '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${_b64({'sub': _uid, 'role': 'authenticated', 'exp': exp, 'aud': 'authenticated'})}.'
      'not-verified-client-side';
}

class _SeededSession extends LocalStorage {
  @override
  Future<void> initialize() async {}
  @override
  Future<String?> accessToken() async => jsonEncode({
        'access_token': _jwt(),
        'token_type': 'bearer',
        'expires_in': 315360000,
        'refresh_token': 'test-refresh',
        'user': {
          'id': _uid,
          'app_metadata': {},
          'user_metadata': {},
          'aud': 'authenticated',
          'created_at': '2026-01-01T00:00:00Z',
        },
      });
  @override
  Future<bool> hasAccessToken() async => true;
  @override
  Future<void> persistSession(String persistSessionString) async {}
  @override
  Future<void> removePersistedSession() async {}
}

class _MemoryStore extends GotrueAsyncStorage {
  final Map<String, String> _m = {};
  @override
  Future<String?> getItem({required String key}) async => _m[key];
  @override
  Future<void> setItem({required String key, required String value}) async =>
      _m[key] = value;
  @override
  Future<void> removeItem({required String key}) async => _m.remove(key);
}

/// PostgREST: the user's notifications, or a failure.
class _Server extends http.BaseClient {
  bool notificationsFail = false;
  int notificationReads = 0;
  final rows = <Map<String, Object?>>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path.endsWith('/notifications')) {
      notificationReads++;
      if (notificationsFail) return _json({'message': 'offline'}, 500, request);
      return _json(rows, 200, request);
    }
    return _json([], 200, request);
  }

  http.StreamedResponse _json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

/// The realtime server end of the socket: answers joins, heartbeats and
/// leaves, and pushes `postgres_changes` to every channel still joined.
class _Realtime {
  _FakeSocket? _socket;
  final joined = <String, List<Map<String, dynamic>>>{};

  /// A fresh socket per connection, as a real one would be.
  WebSocketChannel connect(String url, Map<String, String> headers) {
    joined.clear();
    return _socket = _FakeSocket(this);
  }

  void _receive(String raw) {
    final msg = jsonDecode(raw) as Map<String, dynamic>;
    final topic = msg['topic'] as String;
    final event = msg['event'] as String;
    final ref = msg['ref'];
    Map<String, dynamic> response = {};
    if (event == 'phx_join') {
      final config = (msg['payload'] as Map)['config'] as Map;
      final filters = [
        for (final (i, f) in (config['postgres_changes'] as List).indexed)
          {...(f as Map<String, dynamic>), 'id': 100 + i},
      ];
      joined[topic] = filters;
      response = {'postgres_changes': filters};
    } else if (event == 'phx_leave') {
      joined.remove(topic);
    } else if (event != 'heartbeat') {
      return; // access_token and the like need no answer
    }
    _send({
      'topic': topic,
      'event': 'phx_reply',
      'payload': {'status': 'ok', 'response': response},
      'ref': ref,
    });
  }

  void _send(Map<String, dynamic> m) {
    final socket = _socket;
    if (socket != null && !socket.toClient.isClosed) {
      socket.toClient.add(jsonEncode(m));
    }
  }

  /// An INSERT into `notifications`, delivered as the realtime server would.
  void insert(Map<String, Object?> record) {
    for (final e in joined.entries) {
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

/// Only what the realtime client uses; anything else fails loudly.
class _FakeSocket implements WebSocketChannel {
  final _Realtime server;
  final toClient = StreamController<String>();
  late final WebSocketSink _sink = _FakeSink(server, this);
  _FakeSocket(this.server);

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
  final _Realtime server;
  final _FakeSocket socket;
  _FakeSink(this.server, this.socket);

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

Map<String, Object?> _notification(String id, {bool read = false}) => {
      'id': id,
      'recipient_id': _uid,
      'type': 'new_client',
      'title': 'New client $id',
      'body': '',
      'read': read,
      'created_at': '2026-11-18T10:00:00Z',
    };

void main() {
  late _Server server;
  late _Realtime realtime;
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = _Server();
    realtime = _Realtime();
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: server,
      realtimeClientOptions: RealtimeClientOptions(transport: realtime.connect),
      authOptions: FlutterAuthClientOptions(
        localStorage: _SeededSession(),
        pkceAsyncStorage: _MemoryStore(),
      ),
      debug: false,
    );
  });

  setUp(() {
    server
      ..notificationsFail = false
      ..notificationReads = 0
      ..rows.clear();
    reported.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  ProviderContainer app() {
    final c = ProviderContainer(overrides: [
      currentUserProvider
          .overrideWithValue(Supabase.instance.client.auth.currentUser),
    ]);
    c.listen(coachNotificationsProvider, (_, __) {});
    c.listen(unreadNotificationCountProvider, (_, __) {});
    return c;
  }

  Future<void> settle(WidgetTester tester, [Duration d = const Duration(milliseconds: 200)]) async {
    await tester.pump(d);
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> done(WidgetTester tester, ProviderContainer c) async {
    c.dispose();
    await tester.pump(const Duration(seconds: 1));
    await Supabase.instance.client.removeAllChannels();
    await Supabase.instance.client.realtime.disconnect();
    await tester.pump(const Duration(minutes: 2));
  }

  testWidgets('a failed fetch is an ERROR, not an empty list, and is reported',
      (tester) async {
    server.notificationsFail = true;
    final c = app();
    try {
      await settle(tester);
      final state = c.read(coachNotificationsProvider);
      expect(state.hasError, isTrue,
          reason: 'THE defect: handleError turned the failure into []');
      expect(reported.map((f) => f.origin), contains('coachNotificationsProvider'));
    } finally {
      await done(tester, c);
    }
  });

  testWidgets('the unread count is unknown (null), not 0, while it has failed',
      (tester) async {
    server.notificationsFail = true;
    final c = app();
    try {
      await settle(tester);
      expect(c.read(unreadNotificationCountProvider), isNull,
          reason: 'THE defect: the bell claimed 0 unread during a failure');
    } finally {
      await done(tester, c);
    }
  });

  testWidgets('Try again (invalidate) re-subscribes and delivers the rows',
      (tester) async {
    server.notificationsFail = true;
    final c = app();
    try {
      await settle(tester);
      expect(c.read(coachNotificationsProvider).hasError, isTrue);

      server
        ..notificationsFail = false
        ..rows.add(_notification('n-1'));
      final readsBefore = server.notificationReads;
      c.invalidate(coachNotificationsProvider);
      await settle(tester);

      expect(server.notificationReads, greaterThan(readsBefore),
          reason: 'the retry opened a fresh stream');
      final state = c.read(coachNotificationsProvider);
      expect(state.hasError, isFalse);
      expect(state.requireValue.map((n) => n['id']), ['n-1']);
      expect(c.read(unreadNotificationCountProvider), 1);

      // Still live after the re-subscription.
      realtime.insert(_notification('n-2'));
      await settle(tester);
      expect(c.read(coachNotificationsProvider).requireValue.map((n) => n['id']),
          containsAll(['n-1', 'n-2']));
      expect(c.read(unreadNotificationCountProvider), 2);
    } finally {
      await done(tester, c);
    }
  });

  testWidgets('with no retry tapped, the stream re-opens on its own once the '
      'server is back (as the client side does)', (tester) async {
    server.notificationsFail = true;
    final c = app();
    try {
      await settle(tester);
      server
        ..notificationsFail = false
        ..rows.add(_notification('n-missed'));
      await settle(tester, const Duration(seconds: 5));
      final state = c.read(coachNotificationsProvider);
      expect(state.hasError, isFalse);
      expect(state.requireValue.map((n) => n['id']), ['n-missed']);
    } finally {
      await done(tester, c);
    }
  });

  // ── Controls ──────────────────────────────────────────────────────────────

  testWidgets('control: a successful empty read is an empty list and 0 unread',
      (tester) async {
    final c = app();
    try {
      await settle(tester);
      expect(c.read(coachNotificationsProvider).requireValue, isEmpty);
      expect(c.read(unreadNotificationCountProvider), 0);
      expect(reported, isEmpty);
    } finally {
      await done(tester, c);
    }
  });

  testWidgets('control: a healthy stream reads once and does not re-open',
      (tester) async {
    server.rows.add(_notification('n-old', read: true));
    final c = app();
    try {
      await settle(tester, const Duration(seconds: 10));
      expect(server.notificationReads, 1);
      await settle(tester, const Duration(minutes: 1));
      expect(server.notificationReads, 1);
      expect(c.read(unreadNotificationCountProvider), 0);
    } finally {
      await done(tester, c);
    }
  });
}
