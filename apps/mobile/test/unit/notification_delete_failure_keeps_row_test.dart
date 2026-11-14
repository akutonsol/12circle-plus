import 'dart:convert';

import 'package:circle_fitness/features/notifications/domain/notification_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// A notification whose delete failed broke the list.
//
// The swipe dismissed the row first (`onDismissed`), then `delete` awaited the
// server and threw on failure before removing it from the list — leaving a
// dismissed Dismissible in the tree ("A dismissed Dismissible widget is still
// part of the tree"), the row still unread, the error unhandled. `markRead` and
// `markAllRead` likewise threw from a tap. Each now says whether the server
// took the change and changes the list only when it did; the screen deletes
// before it dismisses (`confirmDismiss`).

const _uid = '00000000-0000-4000-8000-0000000000f1';

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

/// Reads work; every write answers 500 (a 503 is retried with a timer).
class _Server extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final write = request.method == 'DELETE' || request.method == 'PATCH';
    final body = write
        ? {'message': 'upstream down'}
        : [
            {'id': 'n1', 'recipient_id': _uid, 'type': 'general', 'title': 'Hi',
             'body': 'There', 'read': false, 'created_at': '2026-11-13T09:00:00+00:00'},
          ];
    return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), write ? 500 : 200,
        request: request, headers: {'content-type': 'application/json'});
  }
}

Future<NotificationsNotifier> _loaded() async {
  final n = NotificationsNotifier();
  for (var i = 0; i < 50 && !n.state.hasValue; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return n;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _Server(),
      authOptions: FlutterAuthClientOptions(
        localStorage: _SeededSession(),
        pkceAsyncStorage: _MemoryStore(),
        detectSessionInUri: false,
      ),
      debug: false,
    );
  });

  test('a delete the server refused keeps the row and says so', () async {
    final n = await _loaded();
    addTearDown(n.dispose);
    final Object? ok = await (n.delete('n1') as Future<Object?>);
    expect(ok, false, reason: 'THE defect: it threw, after the row had been dismissed');
    expect(n.state.value!.map((x) => x.id), ['n1']);
  });

  test('a mark-read the server refused leaves it unread, without throwing', () async {
    final n = await _loaded();
    addTearDown(n.dispose);
    final Object? ok = await (n.markRead('n1') as Future<Object?>);
    expect(ok, false);
    expect(n.state.value!.single.read, isFalse);
    final Object? all = await (n.markAllRead() as Future<Object?>);
    expect(all, false);
  });
}
