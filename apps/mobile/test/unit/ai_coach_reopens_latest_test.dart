import 'dart:convert';

import 'package:circle_fitness/features/ai_coach/data/ai_coach_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// Reopening the AI Coach chat showed the first ten exchanges ever.
//
// `getConversationHistory(limit: 10)` read `ai_conversations` ordered ascending
// with `limit(10)`, which keeps the OLDEST ten. Every exchange becomes a row
// (ai-coach/index.ts), so from the eleventh on the chat reopened on the same
// opening ten and the latest conversation was never shown.

const _uid = '00000000-0000-4000-8000-0000000000a1';

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

/// Answers like PostgREST: sorts by `order=` and cuts to `limit=`.
class _Server extends http.BaseClient {
  final rows = [
    for (var i = 1; i <= 15; i++)
      {
        'id': 'x$i', 'user_id': _uid,
        'user_message': 'question $i', 'ai_response': 'answer $i',
        'created_at': DateTime.utc(2026, 11, 1, 9, i).toIso8601String(),
      },
  ];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final q = request.url.queryParameters;
    final asc = (q['order'] ?? '').contains('.asc');
    final sorted = [...rows]..sort((a, b) {
        final c = (a['created_at'] as String).compareTo(b['created_at'] as String);
        return asc ? c : -c;
      });
    final limit = int.tryParse(q['limit'] ?? '');
    final body = limit == null ? sorted : sorted.take(limit).toList();
    return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), 200,
        request: request, headers: {'content-type': 'application/json'});
  }
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

  test('the chat reopens on the latest ten exchanges, in order', () async {
    final h = await AICoachService().getConversationHistory(limit: 10);
    expect(h.map((r) => r['user_message']),
        [for (var i = 6; i <= 15; i++) 'question $i'],
        reason: 'THE defect: ascending + limit(10) kept questions 1–10 forever');
  });
}
