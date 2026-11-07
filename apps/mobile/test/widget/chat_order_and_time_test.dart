import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:circle_fitness/features/messaging/data/messaging_service.dart';
import 'package:circle_fitness/features/messaging/domain/messaging_provider.dart';
import 'package:circle_fitness/features/messaging/presentation/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// Real-build QA, TEST 8, found two things wrong with a message that DID send:
//   * The thread ran upside down. `getMessages` asked for oldest first and the
//     stream, which replaces it a moment later, did not say: the SDK's `.order()`
//     defaults to descending. The list then showed newest first while the
//     auto-scroll went to the end of the list, so a client landed on the oldest
//     message and could not see what they had just sent.
//   * The time was wrong. `sent_at` went out as local time with no zone, and a
//     `timestamptz` column reads that as UTC. Sent at about 9:21 AM in UTC-5, it
//     came back as 4:21 AM and the conversation list said "5h ago".
//
// The screen tests drive the real chat with a fake thread. The service tests drive
// the real service, signed in, with only the network substituted.

const _uid = '00000000-0000-4000-8000-0000000c4a71';
const _conv = 'conv-1';

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

/// gotrue reads `sub` and `exp` from the body without a round-trip while the
/// token is unexpired, and never verifies the signature on the client.
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

/// Answers every request and remembers what was asked.
class _RecordingClient extends http.BaseClient {
  final requests = <http.Request>[];

  http.Request? last(String method, String path) {
    for (final r in requests.reversed) {
      if (r.method == method && r.url.path == path) return r;
    }
    return null;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request) requests.add(request);
    return http.StreamedResponse(
      Stream.value(utf8.encode('[]')),
      200,
      request: request,
      headers: {'content-type': 'application/json'},
    );
  }
}

/// A long thread, oldest first, as the corrected service delivers it. Bubbles get
/// taller towards the newest, because a lazy list estimates its full length from
/// what it has built: a thread like this one is what stopped the auto-scroll short.
List<Map<String, dynamic>> _thread(int count) => [
      for (var i = 0; i < count; i++)
        {
          'id': 'm$i',
          'sender_id': i.isEven ? _uid : 'coach',
          'content': i < count - 12
              ? 'old $i'
              : 'recent $i ${List.filled(40, 'word').join(' ')}',
          'is_read': true,
          'sent_at': DateTime.utc(2026, 11, 1).add(Duration(minutes: i)).toIso8601String(),
        },
    ];

class _FakeThread extends Fake implements MessagingService {
  _FakeThread(this.rows);
  final List<Map<String, dynamic>> rows;
  late final StreamController<List<Map<String, dynamic>>> _stream =
      StreamController(onListen: () => _stream.add(List.of(rows)));

  @override
  Future<String?> getOrCreateClientCoachConversation() async => _conv;

  @override
  Future<String?> getOrCreateConversationWith(String otherUserId) async => _conv;

  @override
  Future<List<Map<String, dynamic>>> getMessages(String conversationId) async =>
      List.of(rows);

  @override
  Future<void> markAsRead(String conversationId) async {}

  @override
  Stream<List<Map<String, dynamic>>> messagesStream(String conversationId) =>
      _stream.stream;

  @override
  Future<bool> sendMessage({
    required String conversationId,
    required String content,
    Map<String, dynamic>? metadata,
  }) async {
    rows.add({
      'id': 'sent-${rows.length}',
      'sender_id': _uid,
      'content': content,
      'is_read': false,
      'sent_at': DateTime.now().toUtc().toIso8601String(),
    });
    _stream.add(List.of(rows));
    return true;
  }
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 30; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _openChat(WidgetTester t, _FakeThread svc) async {
  t.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(390, 844);
  addTearDown(t.view.reset);

  await t.pumpWidget(ProviderScope(
    overrides: [messagingServiceProvider.overrideWithValue(svc)],
    child: const MaterialApp(home: ChatScreen()),
  ));
  await _settle(t);
}

/// In the message list, and inside what the list is actually showing. A lazy list
/// builds items beyond its edge, so existing in the tree is not being on screen.
void _expectVisible(WidgetTester t, String text, {required String reason}) {
  final inList = find.descendant(of: find.byType(ListView), matching: find.text(text));
  expect(inList, findsOneWidget, reason: reason);
  final list = t.getRect(find.byType(ListView));
  final bubble = t.getRect(inList);
  expect(bubble.bottom, lessThanOrEqualTo(list.bottom + 1), reason: reason);
  expect(bubble.top, greaterThanOrEqualTo(list.top - 1), reason: reason);
}

late _RecordingClient _http;

void main() {
  setUpAll(() async {
    _http = _RecordingClient();
    await Supabase.initialize(
      // Unroutable, and every request answered and recorded by the client above.
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _http,
      authOptions: FlutterAuthClientOptions(
        localStorage: _SeededSession(),
        pkceAsyncStorage: _MemoryStore(),
        autoRefreshToken: false,
      ),
      debug: false,
    );
  });

  setUp(() => _http.requests.clear());

  group('D1 oldest first, newest at the bottom', () {
    test('the history load asks for oldest first', () async {
      await MessagingService().getMessages(_conv);

      final read = _http.last('GET', '/rest/v1/messages');
      expect(read, isNotNull);
      expect(read!.url.queryParameters['order'], startsWith('sent_at.asc'));
    });

    // A static guard, because the stream's ordering cannot be observed without a
    // realtime socket: the SDK keeps it private, and sorts every later event by it.
    // It is the half that was wrong, and the SDK's default is the bug.
    test('the live stream states oldest first, not the SDK default', () {
      final source =
          File('lib/features/messaging/data/messaging_service.dart').readAsStringSync();
      final stream =
          RegExp(r'messagesStream\(.*?\n  \}', dotAll: true).firstMatch(source)![0]!;

      expect(stream, contains("order('sent_at', ascending: true)"));
    });

    testWidgets('opening a long thread lands on the newest message', (t) async {
      final rows = _thread(40);
      await _openChat(t, _FakeThread(rows));

      _expectVisible(t, rows.last['content'] as String,
          reason: 'the newest message must be on screen when the thread opens');
    });

    testWidgets('a sent message is on screen, from anywhere in a long thread',
        (t) async {
      await _openChat(t, _FakeThread(_thread(40)));
      t.widget<ListView>(find.byType(ListView)).controller!.jumpTo(0);
      await t.pump();

      await t.enterText(find.byType(TextField), 'QA just sent this');
      await t.pump();
      await t.tap(find.byIcon(Icons.send_rounded));
      await _settle(t);

      _expectVisible(t, 'QA just sent this',
          reason: 'what was just sent must be visible without scrolling');
    });
  });

  group('D2 a message carries its real moment', () {
    test('sent_at and last_message_at go out as UTC', () async {
      final before = DateTime.now().toUtc();

      final ok = await MessagingService().sendMessage(conversationId: _conv, content: 'hi');
      expect(ok, isTrue);

      final sentAt = jsonDecode(_http.last('POST', '/rest/v1/messages')!.body)['sent_at'] as String;
      final lastAt = jsonDecode(_http.last('PATCH', '/rest/v1/conversations')!.body)['last_message_at']
          as String;

      for (final value in [sentAt, lastAt]) {
        expect(value, endsWith('Z'),
            reason: 'a timestamp with no zone is read as UTC by a timestamptz column, '
                'so anywhere but UTC it records the wrong moment: $value');
        final at = DateTime.parse(value);
        expect(at.isUtc, isTrue);
        expect(at.difference(before).inSeconds.abs(), lessThan(60));
      }
    });
  });
}
