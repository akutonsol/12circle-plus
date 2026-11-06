import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/messaging/data/messaging_service.dart';
import 'package:circle_fitness/features/messaging/domain/messaging_provider.dart';
import 'package:circle_fitness/features/messaging/presentation/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// The chat's send did four things wrong when a message did not go:
//   * it cleared the input before the write, so the typed text was gone;
//   * it showed the message as a sent bubble and kept it there;
//   * it ignored the `bool` `sendMessage` returns, so a failure said nothing;
//   * it awarded the "message your coach" score whether or not anything was sent.
// With no conversation yet (still resolving, or none could be found) it did
// nothing at all: the input cleared, and no bubble, no message, no word.
//
// These drive the real screen. The messaging service is a fake the test answers
// through `messagingServiceProvider`; the score engine is real and its HTTP calls
// are recorded, because an award is a request to `award_points`.

const _sendFailed = "Couldn't send your message — check your connection and try again.";
const _notReady = "This conversation isn't ready yet — try again in a moment.";
const _text = 'Hello coach';

class _FakeMessaging extends Fake implements MessagingService {
  String? conversationId = 'conv-1';
  bool sendResult = true;
  final sent = <String>[];

  /// When set, a send waits on this, so a test can act while it is in flight.
  Completer<void>? gate;
  final _stream = StreamController<List<Map<String, dynamic>>>();

  @override
  Future<String?> getOrCreateClientCoachConversation() async => conversationId;

  @override
  Future<String?> getOrCreateConversationWith(String otherUserId) async =>
      conversationId;

  @override
  Future<List<Map<String, dynamic>>> getMessages(String conversationId) async =>
      const [];

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
    sent.add(content);
    await gate?.future;
    return sendResult;
  }
}

/// Answers every request and remembers which ones were made.
class _RecordingClient extends http.BaseClient {
  final requests = <String>[];

  bool get awardedPoints => requests.any((r) => r.contains('/rpc/award_points'));

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add('${request.method} ${request.url.path}');
    return http.StreamedResponse(
      Stream.value(utf8.encode('[]')),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
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

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

late _RecordingClient _http;

Future<void> _openChat(WidgetTester t, _FakeMessaging svc) async {
  t.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(1200, 2400);
  addTearDown(t.view.reset);
  _http.requests.clear();

  await t.pumpWidget(ProviderScope(
    overrides: [messagingServiceProvider.overrideWithValue(svc)],
    child: const MaterialApp(home: ChatScreen()),
  ));
  await _settle(t);
}

Future<void> _type(WidgetTester t, String text) async {
  await t.enterText(find.byType(TextField), text);
  await t.pump();
}

Future<void> _tapSend(WidgetTester t) async {
  await t.tap(find.byIcon(Icons.send_rounded));
  await _settle(t);
}

String _input(WidgetTester t) =>
    t.widget<TextField>(find.byType(TextField)).controller!.text;

/// The sent bubble, which lives in the message list and not in the composer.
Finder _bubble() =>
    find.descendant(of: find.byType(ListView), matching: find.text(_text));

void main() {
  setUpAll(() async {
    _http = _RecordingClient();
    await Supabase.initialize(
      // Unroutable, and every request answered and recorded by the client below.
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _http,
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryStore(),
      ),
      debug: false,
    );
  });

  late List<AppFailure> reported;

  setUp(() {
    reported = [];
    setFailureSink(reported.add);
    addTearDown(resetFailureSink);
  });

  testWidgets('a message that goes: shown once, input cleared, score awarded',
      (t) async {
    final svc = _FakeMessaging();
    await _openChat(t, svc);

    await _type(t, _text);
    await _tapSend(t);

    expect(svc.sent, [_text]);
    expect(_bubble(), findsOneWidget);
    expect(_input(t), isEmpty);
    expect(find.text(_sendFailed), findsNothing);
    expect(_http.awardedPoints, isTrue);
  });

  testWidgets('a message that fails: no sent bubble, the text is kept, no score',
      (t) async {
    final svc = _FakeMessaging()..sendResult = false;
    await _openChat(t, svc);

    await _type(t, _text);
    await _tapSend(t);

    expect(svc.sent, [_text], reason: 'it was attempted');
    expect(_bubble(), findsNothing,
        reason: 'a message that did not go must not sit in the thread as sent');
    expect(_input(t), _text, reason: 'the coach must not have to retype it');
    expect(find.text(_sendFailed), findsOneWidget);
    expect(_http.awardedPoints, isFalse,
        reason: 'no points for a message nobody received');
    expect(reported, isNotEmpty, reason: 'the failure is reported');
  });

  testWidgets('a failed send does not overwrite what was typed meanwhile',
      (t) async {
    final svc = _FakeMessaging()
      ..sendResult = false
      ..gate = Completer<void>();
    await _openChat(t, svc);

    await _type(t, _text);
    await _tapSend(t);
    expect(_input(t), isEmpty, reason: 'cleared while the send is in flight');
    await _type(t, 'second thought');
    svc.gate!.complete();
    await _settle(t);

    expect(_input(t), 'second thought');
    expect(_bubble(), findsNothing);
    expect(find.text(_sendFailed), findsOneWidget);
  });

  testWidgets('no conversation: nothing is sent, the text is kept, and it says so',
      (t) async {
    final svc = _FakeMessaging()..conversationId = null;
    await _openChat(t, svc);
    expect(find.text("Couldn't open this conversation"), findsOneWidget);

    await _type(t, _text);
    await _tapSend(t);

    expect(svc.sent, isEmpty);
    expect(_input(t), _text);
    expect(find.text(_notReady), findsOneWidget);
    expect(_http.awardedPoints, isFalse);
  });
}
