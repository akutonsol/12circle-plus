import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/notifications/data/notification_model.dart';
import 'package:circle_fitness/features/notifications/domain/notification_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// The bell badge (`unreadCountProvider`) is re-counted when
// `notificationsStreamProvider` emits, and the open Notifications list
// (`NotificationsNotifier`) takes its live rows from the same
// `NotificationService.streamNotifications()`.
//
// That was supabase's `.stream()` as is, and it ENDS for good when one of its
// reads fails (`SupabaseStreamBuilder._getPostgrestData` unsubscribes and
// closes on a failed fetch, at start or on a reconnect). Nothing re-opened
// it: both providers live for the session and watch only the user. So after
// one offline moment the badge kept its number through "Mark all read" and
// never rose for a new notification, and the list stopped updating, until a
// reload.
//
// These run the real providers and realtime client against a fake PostgREST
// and a fake realtime socket that speaks the channel protocol.

const _uid = '00000000-0000-4000-8000-0000000b311e';

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

Map<String, Object?> _notification(String id, String type) => {
      'id': id,
      'recipient_id': _uid,
      'type': type,
      'title': 'Your coach assigned you a program',
      'body': '',
      'read': false,
      'created_at': '2026-11-12T10:00:00Z',
    };

void main() {
  late _Server server;
  late _Realtime realtime;

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
  });

  /// The app's providers, as the bell and the Notifications screen use them.
  ProviderContainer app() {
    final c = ProviderContainer(overrides: [
      currentUserProvider
          .overrideWithValue(Supabase.instance.client.auth.currentUser),
    ]);
    c.listen(notificationsStreamProvider, (_, __) {});
    c.listen(notificationsProvider, (_, __) {});
    return c;
  }

  Future<void> settle(WidgetTester tester, [Duration d = const Duration(milliseconds: 200)]) async {
    await tester.pump(d);
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Disposes the providers, leaves the channels and lets every timer run out.
  Future<void> done(WidgetTester tester, ProviderContainer c) async {
    c.dispose();
    await tester.pump(const Duration(seconds: 1));
    await Supabase.instance.client.removeAllChannels();
    await Supabase.instance.client.realtime.disconnect();
    await tester.pump(const Duration(minutes: 2));
  }

  List<String> streamed(ProviderContainer c) =>
      (c.read(notificationsStreamProvider).valueOrNull ?? const <AppNotification>[])
          .map((n) => n.id)
          .toList();

  List<String> listed(ProviderContainer c) =>
      (c.read(notificationsProvider).valueOrNull ?? const <AppNotification>[])
          .map((n) => n.id)
          .toList();

  testWidgets('after a FAILED first read, a new notification still reaches '
      'the badge and the list', (tester) async {
    server.notificationsFail = true;
    final c = app();
    try {
      await settle(tester);
      server.notificationsFail = false;
      await settle(tester, const Duration(seconds: 5));

      realtime.insert(_notification('n-1', 'program_assigned'));
      await settle(tester);

      expect(streamed(c), contains('n-1'),
          reason: 'THE defect: the badge is never re-counted again');
      expect(listed(c), contains('n-1'),
          reason: 'THE defect: the open list never updates again');
    } finally {
      await done(tester, c);
    }
  });

  testWidgets('a notification made while it was down appears once it is back',
      (tester) async {
    server.notificationsFail = true;
    final c = app();
    try {
      await settle(tester);
      server.rows.add(_notification('n-missed', 'checkin'));
      server.notificationsFail = false;
      await settle(tester, const Duration(seconds: 5));
      expect(streamed(c), contains('n-missed'));
    } finally {
      await done(tester, c);
    }
  });

  // ── Controls ──────────────────────────────────────────────────────────────

  testWidgets('a healthy stream delivers what is there, then what arrives',
      (tester) async {
    server.rows.add(_notification('n-old', 'checkin'));
    final c = app();
    try {
      await settle(tester);
      expect(streamed(c), ['n-old']);
      realtime.insert(_notification('n-2', 'checkin'));
      await settle(tester);
      expect(streamed(c), containsAll(['n-old', 'n-2']));
      expect(listed(c), containsAll(['n-old', 'n-2']));
    } finally {
      await done(tester, c);
    }
  });

  testWidgets('a healthy stream reads once and does not re-open', (tester) async {
    final c = app();
    try {
      await settle(tester, const Duration(seconds: 10));
      // One for the stream, one for the list's own first read; no retries.
      expect(server.notificationReads, lessThanOrEqualTo(3));
      final before = server.notificationReads;
      await settle(tester, const Duration(minutes: 1));
      expect(server.notificationReads, before);
    } finally {
      await done(tester, c);
    }
  });
}
