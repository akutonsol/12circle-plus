import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/core/notifications/notification_watcher.dart';
import 'package:circle_fitness/features/workout/data/models/workout_model.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// NotificationWatcher wraps the signed-in app. It listens to the user's
// `notifications` and, for each new one, re-reads what it says has changed
// (`refreshForNotification`): a coach assigning a program, nutrition or
// habits, approving a request, answering a check-in.
//
// It listened through supabase's `.stream()`, and that stream ENDS for good
// when one of its reads fails: `SupabaseStreamBuilder._getPostgrestData`
// unsubscribes the channel and closes the stream on any failed fetch, at
// start or on a reconnect. The watcher ignored the error and the end, and
// `_subscribe` returns early while the user is unchanged (`uid == _uid`), so
// nothing ever opened another. One offline moment, an expired token after a
// laptop sleeps, one 5xx — and for the rest of that tab's life a client read
// "Coach assigned you a program" elsewhere while Home still said there was
// none, until a reload.
//
// These run the real watcher and the real realtime client against a fake
// PostgREST and a fake realtime socket that speaks the channel protocol, and
// count how often a program refresh actually happens.

const _uid = '00000000-0000-4000-8000-0000000a7c4e';

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

  /// Mounts the watcher over a Home that reads the assigned program, and
  /// returns how many times that program has been read.
  Future<int Function()> mount(WidgetTester tester) async {
    var programReads = 0;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        assignedWorkoutsProvider.overrideWith((ref) async {
          programReads++;
          return const <Workout>[];
        }),
      ],
      child: MaterialApp(
        home: NotificationWatcher(
          child: Consumer(builder: (_, ref, __) {
            ref.watch(assignedWorkoutsProvider);
            return const SizedBox();
          }),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    return () => programReads;
  }

  /// Lets a pushed change reach the watcher, and the invalidated read run.
  Future<void> deliver(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Unmounts, leaves the channels and lets every timer run out.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await Supabase.instance.client.removeAllChannels();
    await Supabase.instance.client.realtime.disconnect();
    await tester.pump(const Duration(minutes: 2));
  }

  testWidgets('after a FAILED first read, a new assignment still refreshes Home',
      (tester) async {
    try {
      server.notificationsFail = true;
      final programReads = await mount(tester);
      expect(server.notificationReads, 1, reason: 'guard the premise: it read once');

      // The connection comes back.
      server.notificationsFail = false;
      await tester.pump(const Duration(seconds: 5));

      final before = programReads();
      realtime.insert(_notification('n-1', 'program_assigned'));
      await deliver(tester);

      expect(programReads() - before, 1,
          reason: 'THE defect: the stream had ended for good, so the coach\'s '
              'assignment never reached Home');
    } finally {
      await unmount(tester);
    }
  });

  testWidgets('it keeps trying while the reads keep failing, then recovers',
      (tester) async {
    try {
      server.notificationsFail = true;
      final programReads = await mount(tester);
      await tester.pump(const Duration(seconds: 30));
      expect(server.notificationReads, greaterThan(2),
          reason: 'read again, and again, while it fails');

      server.notificationsFail = false;
      await tester.pump(const Duration(minutes: 1));
      final before = programReads();
      realtime.insert(_notification('n-2', 'program_assigned'));
      await deliver(tester);
      expect(programReads() - before, 1);
    } finally {
      await unmount(tester);
    }
  });

  testWidgets('one that arrived while it was down is acted on', (tester) async {
    try {
      // Primed, then the server closes the channel: the stream ends, as it does
      // on a failed read.
      server.rows.add(_notification('n-old', 'checkin'));
      final programReads = await mount(tester);
      final before = programReads();
      final chan = realtime.joined.keys.single;
      realtime._send({
        'topic': chan,
        'event': 'phx_close',
        'payload': {},
        'ref': null,
      });
      await tester.pump(const Duration(milliseconds: 100));

      // Assigned while it was down; the connection comes back.
      server.rows.add(_notification('n-missed', 'program_assigned'));
      await tester.pump(const Duration(seconds: 5));

      expect(programReads() - before, 1,
          reason: 'the assignment made while it was down is new, not history');
    } finally {
      await unmount(tester);
    }
  });

  // ── Controls ──────────────────────────────────────────────────────────────

  testWidgets('a healthy stream refreshes on a new assignment', (tester) async {
    try {
      final programReads = await mount(tester);
      final before = programReads();
      realtime.insert(_notification('n-3', 'program_assigned'));
      await deliver(tester);
      expect(programReads() - before, 1);
    } finally {
      await unmount(tester);
    }
  });

  testWidgets('history is not replayed: what was there on load refreshes '
      'nothing', (tester) async {
    try {
      server.rows.add(_notification('n-old', 'program_assigned'));
      final programReads = await mount(tester);
      final atLoad = programReads();
      await tester.pump(const Duration(seconds: 5));
      expect(programReads(), atLoad);
      expect(server.notificationReads, 1, reason: 'a healthy stream reads once');
    } finally {
      await unmount(tester);
    }
  });
}
