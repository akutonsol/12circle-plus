import 'dart:convert';

import 'package:circle_fitness/core/realtime/realtime.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/dashboard/presentation/coach_dashboard_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// The coach dashboard's Client Intelligence figures read fields the roster read
// never fetched.
//
// `coachClientsProvider` selected `id, first_name, last_name, email, avatar_url,
// role`. The dashboard then counted `risk_level` (High Risk, At-Risk, the
// "HIGH RISK — review PAR-Q" recommendation), `created_at` (Retention),
// `coaching_mode` and `program_name` (Program Rate, "still unassigned a
// program"). None arrived, so those were always 0 / 0%: a coach with a high-risk
// client was never told. `program_name` is no column at all, and the
// "unassigned" rule compared `coaching_mode` with 'coached', a value the column's
// CHECK (007) does not allow — it is 'coach_guided'.
//
// The fake below answers like PostgREST: a row carries ONLY the columns the
// request selects, so a field the read does not ask for is absent here too.

const _uid = '00000000-0000-4000-8000-0000000c0ac4';

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

class _Server extends http.BaseClient {
  final profiles = <Map<String, Object?>>[
    {'id': 'c1', 'first_name': 'Ana', 'last_name': 'Ruiz', 'email': 'a@x', 'avatar_url': null,
     'role': 'client', 'risk_level': 'high', 'coaching_mode': 'coach_guided',
     'created_at': '2026-01-05T00:00:00+00:00'},
    {'id': 'c2', 'first_name': 'Ben', 'last_name': 'Ode', 'email': 'b@x', 'avatar_url': null,
     'role': 'client', 'risk_level': 'low', 'coaching_mode': 'coach_guided',
     'created_at': '2026-11-10T00:00:00+00:00'},
  ];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final select = request.url.queryParameters['select'] ?? '*';
    if (path.endsWith('/coach_client_relationships')) {
      return _json([{'client_id': 'c1'}, {'client_id': 'c2'}], request);
    }
    if (path.endsWith('/user_profiles')) {
      return _json([for (final p in profiles) _project(p, select)], request);
    }
    if (path.endsWith('/workout_program_assignments')) {
      return _json([
        {'client_id': 'c1', 'workout_programs': {'name': 'Strength Base'}},
      ], request);
    }
    return _json([], request);
  }

  /// Only the selected columns, as PostgREST returns them.
  static Map<String, Object?> _project(Map<String, Object?> row, String select) {
    if (select.trim() == '*') return row;
    final cols = select.split(',').map((c) => c.trim()).toSet();
    return {for (final e in row.entries) if (cols.contains(e.key)) e.key: e.value};
  }

  http.StreamedResponse _json(Object? body, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), 200,
          request: r, headers: {'content-type': 'application/json'});
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

  Future<List<Map<String, dynamic>>> roster() async {
    final c = ProviderContainer(overrides: [
      currentUserProvider.overrideWithValue(Supabase.instance.client.auth.currentUser),
      // One tick, no socket: the live re-read is not what is under test.
      tableTickerProvider.overrideWith((ref, table) => Stream.value(0)),
    ]);
    addTearDown(c.dispose);
    c.listen(coachClientsProvider, (_, __) {});
    for (var i = 0; i < 50 && !c.read(coachClientsProvider).hasValue; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return c.read(coachClientsProvider).requireValue;
  }

  test('the roster carries every field the dashboard counts', () async {
    final rows = await roster();
    final ana = rows.firstWhere((r) => r['id'] == 'c1');
    expect(ana['risk_level'], 'high',
        reason: 'THE defect: High Risk / At-Risk were always 0');
    expect(ana['created_at'], isNotNull, reason: 'Retention was always 0%');
    expect(ana['coaching_mode'], 'coach_guided');
    expect(ana['program_name'], 'Strength Base',
        reason: 'Program Rate was always 0%: program_name is no column');
    expect(rows.firstWhere((r) => r['id'] == 'c2')['program_name'], isNull);
  });

  test('a high-risk client and an unassigned coached client are both raised', () async {
    final recs = generateCoachRecs(await roster(), const [], const []);
    expect(recs.any((r) => r.contains('HIGH RISK')), isTrue,
        reason: 'the PAR-Q warning never fired');
    expect(recs.any((r) => r.contains('still unassigned a program')), isTrue,
        reason: "'coached' is not a coaching_mode value; 'coach_guided' is");
  });
}
