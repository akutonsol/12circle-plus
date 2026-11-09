import 'dart:convert';

import 'package:circle_fitness/features/checkins/data/weekly_checkin_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// A week the coach has replied to is still a week the client checked in.
//
// `getCheckinStreak` asked for `status = submitted`. Replying moves a check-in
// to `reviewed`, so the coach answering a client's check-in took that week out
// of the client's streak: three weeks running, the middle one answered, read as
// a streak of one.

const _uid = '00000000-0000-4000-8000-0000000010c7';

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

/// See workout_finish_truth's sibling harnesses: the token is read, never verified.
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

/// Answers `weekly_checkins` the way PostgREST would: only the rows whose
/// status the request's own `status` filter admits.
class _StatusFilteringServer extends http.BaseClient {
  _StatusFilteringServer(this.rows);
  final List<Map<String, String>> rows;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final filter = request.url.queryParameters['status'] ?? '';
    final Set<String> admitted;
    if (filter.startsWith('eq.')) {
      admitted = {filter.substring(3)};
    } else if (filter.startsWith('in.(') && filter.endsWith(')')) {
      // postgrest-dart quotes each value; PostgREST reads them unquoted.
      admitted = {
        for (final v in filter.substring(4, filter.length - 1).split(','))
          v.replaceAll('"', ''),
      };
    } else {
      admitted = rows.map((r) => r['status']!).toSet();
    }
    final body = [
      for (final r in rows)
        if (admitted.contains(r['status'])) {'week_start_date': r['week']},
    ];
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      200,
      request: request,
      headers: {'content-type': 'application/json'},
    );
  }
}

String _monday(int weeksAgo) {
  final n = DateTime.now();
  final d = DateTime(n.year, n.month, n.day - (n.weekday - 1) - 7 * weeksAgo);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _StatusFilteringServer([
        {'week': _monday(0), 'status': 'submitted'},
        {'week': _monday(1), 'status': 'reviewed'},
        {'week': _monday(2), 'status': 'submitted'},
        // Created and never sent: not a check-in, and it must not count.
        {'week': _monday(3), 'status': 'pending'},
      ]),
      authOptions: FlutterAuthClientOptions(
        localStorage: _SeededSession(),
        pkceAsyncStorage: _MemoryStore(),
      ),
      debug: false,
    );
  });

  test('a replied-to week keeps the streak running', () async {
    expect(await WeeklyCheckinService().getCheckinStreak(), 3,
        reason: 'last week was answered by the coach, not skipped');
  });
}
