import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/features/messaging/data/messaging_service.dart';
import 'package:circle_fitness/features/messaging/domain/messaging_provider.dart';
import 'package:circle_fitness/features/messaging/presentation/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// A chat whose messages did not load said "Start the conversation!" (EC-13).
//
// `MessagingService.getMessages` ended `catch (e) { return []; }`, so a failed
// read reached the chat as a thread with nothing in it. A client opening their
// coach thread offline was told it was empty — that their coach had never
// replied — and the screen's own failure state ("Couldn't open this
// conversation · This is a connection problem, not an empty thread · Try
// again") was never shown for it. EC-13 in docs/QA_WORKSTREAM_B_ERROR_CONTRACT_
// REPORT.md: "Expected: propagate; the thread shows couldn't load messages —
// retry." (`getConversations`' swallow is the sanctioned §5.1 one; untouched.)

const _uid = '00000000-0000-4000-8000-0000000000c5';

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

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

/// Every read fails with a 500 (a 503 is retried by postgrest with a timer).
class _Down extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode({'message': 'upstream down'}))), 500,
          request: request, headers: {'content-type': 'application/json'});
}

class _FailingThread extends Fake implements MessagingService {
  @override
  Future<String?> getOrCreateClientCoachConversation() async => 'conv-1';
  @override
  Future<String?> getOrCreateConversationWith(String otherUserId) async => 'conv-1';
  @override
  Future<List<Map<String, dynamic>>> getMessages(String conversationId) async =>
      throw const PostgrestException(message: 'upstream down', code: '500');
  @override
  Future<void> markAsRead(String conversationId) async {}
  @override
  Stream<List<Map<String, dynamic>>> messagesStream(String conversationId) =>
      const Stream.empty();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _Down(),
      authOptions: FlutterAuthClientOptions(
        localStorage: _SeededSession(),
        pkceAsyncStorage: _MemoryStore(),
        detectSessionInUri: false,
      ),
      debug: false,
    );
  });

  test('a failed message read is a failure, not an empty thread', () async {
    await expectLater(MessagingService().getMessages('conv-1'), throwsA(anything),
        reason: 'THE defect: it answered [] — "nothing here" — for a read that failed');
  });

  testWidgets('the chat says it could not load, and offers to try again', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1200, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [messagingServiceProvider.overrideWithValue(_FailingThread())],
      child: const MaterialApp(home: ChatScreen()),
    ));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text("Couldn't open this conversation"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('Start the conversation'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
