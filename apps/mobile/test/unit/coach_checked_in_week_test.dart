import 'dart:convert';
import 'dart:io';

import 'package:circle_fitness/features/dashboard/presentation/coach_dashboard_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// C7 (owner, 2026-11-09): a reviewed week remains in "Checked In" but leaves
// "Needs Attention".
//
// The coach dashboard read only `status = 'submitted'`. The moment the coach
// replied, the week turned `reviewed`, so the client dropped out of "Checked
// In" and off the Check-ins tab as though they had never checked in. And a
// reviewed week, had it been read, would still have been flagged: no attention
// flag looked at the status at all.

const _uid = '00000000-0000-4000-8000-0000000000c7';
const _client = '00000000-0000-4000-8000-0000000c7c11';

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

/// See coach_first_day_truth_test.dart: the token is read, never verified.
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

/// The coach has one client, whose week's check-in is in [checkins]. Applies
/// the `status` filter the way PostgREST does (`eq.x`, `in.(x,y)`).
class _Server extends http.BaseClient {
  List<Map<String, dynamic>> checkins = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (path.endsWith('/coach_client_relationships')) {
      return _json([
        {'client_id': _client},
      ], request);
    }
    if (path.endsWith('/weekly_checkins')) {
      final f = request.url.queryParameters['status'];
      bool keep(Object? s) {
        if (f == null) return true;
        if (f.startsWith('eq.')) return s == f.substring(3);
        if (f.startsWith('in.(')) {
          return f
              .substring(4, f.length - 1)
              .split(',')
              .map((v) => v.replaceAll('"', ''))
              .contains(s);
        }
        return true;
      }

      return _json([for (final c in checkins) if (keep(c['status'])) c], request);
    }
    return _json([], request);
  }

  http.StreamedResponse _json(Object body, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), 200,
          request: r, headers: {'content-type': 'application/json'});
}

Map<String, dynamic> _week(String status) => {
      'user_id': _client,
      'status': status,
      'energy_level': 1,
      'stress_level': 5,
      'week_start_date': DateTime.now().toIso8601String().split('T')[0],
    };

void main() {
  late _Server server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = _Server();
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: server,
      authOptions: FlutterAuthClientOptions(
        localStorage: _SeededSession(),
        pkceAsyncStorage: _MemoryStore(),
      ),
      debug: false,
    );
  });

  Future<List<Map<String, dynamic>>> read() async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container.read(clientCheckinsProvider.future);
  }

  group('C7 a reviewed week stays checked in', () {
    test('a week the coach has replied to is still read', () async {
      server.checkins = [_week('reviewed')];

      expect(await read(), hasLength(1),
          reason: 'replying took the client out of "Checked In" and off the '
              'Check-ins tab');
    });

    test('a week awaiting review is still read', () async {
      server.checkins = [_week('submitted')];

      expect(await read(), hasLength(1));
    });
  });

  // The dashboard has no widget harness (coach_first_day_truth_test.dart says
  // why), so its three attention flags are held by their source: the stat, the
  // client row and the Check-ins tab.
  test('[SOURCE] C7 no attention flag counts a reviewed week', () {
    final src = File('lib/features/dashboard/presentation/coach_dashboard_screen.dart')
        .readAsStringSync();
    final flags = RegExp(r'needsAttention\s*=([^;]*);').allMatches(src).toList();

    expect(flags, hasLength(3), reason: 'an attention flag was added or removed');
    for (final f in flags) {
      expect(f.group(1), contains('reviewedByCoach('),
          reason: 'this flag would mark a week the coach already replied to: '
              '${f.group(0)}');
    }
  });
}
