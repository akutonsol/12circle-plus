import 'dart:convert';

import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/dashboard/domain/coach_triage.dart';
import 'package:circle_fitness/features/dashboard/domain/coach_triage_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// "Needs you today" was missing two of the signals its own rules define.
//
//   * Drop-off risk. `ClientSignals.churnRisk` and `churnRiskThreshold` (50,
//     the dashboard AI panel's threshold) exist, but the provider never fed the
//     score, so a client the engine rated 80% likely to drop off was raised only
//     if they had also gone silent.
//   * Block ending. The block length was read only from `plan.duration_weeks`;
//     a Program Builder program has no plan (093 fills it for generated ones)
//     and states its length in the `duration_weeks` column — the one the
//     client's own page counts weeks from. Hand-built programs never raised
//     "Block ends · needs next".
//
// The fake answers like PostgREST, returning ONLY the selected columns.

const _uid = '00000000-0000-4000-8000-0000000c0ac7';

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
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final select = request.url.queryParameters['select'] ?? '*';
    final start = DateTime.now().subtract(const Duration(days: 6));
    Object? body = [];
    if (path.endsWith('/coach_client_relationships')) {
      body = [{'client_id': 'c1'}, {'client_id': 'c2'}];
    } else if (path.endsWith('/user_profiles')) {
      body = [
        {'id': 'c1', 'first_name': 'Ana', 'last_name': 'Ruiz'},
        {'id': 'c2', 'first_name': 'Ben', 'last_name': 'Ode'},
      ];
    } else if (path.endsWith('/workout_program_assignments')) {
      body = [{'client_id': 'c1', 'program_id': 'p1', 'status': 'active',
               'start_date': start.toIso8601String().split('T')[0]}];
    } else if (path.endsWith('/workout_programs')) {
      // A Program Builder program: one week long, no engine plan.
      body = [_project({'id': 'p1', 'plan': null, 'duration_weeks': 1}, select)];
    } else if (path.endsWith('/rpc/coach_client_ai_signals')) {
      body = [{'client_id': 'c2', 'client_name': 'Ben Ode', 'churn_risk': 80,
               'plateau_risk': 10, 'injury_risk': 5}];
    }
    return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), 200,
        request: request, headers: {'content-type': 'application/json'});
  }

  static Map<String, Object?> _project(Map<String, Object?> row, String select) {
    final cols = select.split(',').map((c) => c.trim()).toSet();
    return {for (final e in row.entries) if (cols.contains(e.key)) e.key: e.value};
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

  Future<Map<String, ClientSignals>> signals() async {
    final c = ProviderContainer(overrides: [
      currentUserProvider.overrideWithValue(Supabase.instance.client.auth.currentUser),
    ]);
    addTearDown(c.dispose);
    c.listen(coachTriageSignalsProvider, (_, __) {});
    final list = await c.read(coachTriageSignalsProvider.future);
    return {for (final s in list) s.clientId: s};
  }

  test('a client the engine rates likely to drop off carries that score', () async {
    final s = await signals();
    expect(s['c2']!.churnRisk, 80,
        reason: 'THE defect: churnRisk was never fed, so the rule could not fire');
  });

  test("a hand-built program's block end is known from its own length", () async {
    final s = await signals();
    expect(s['c1']!.daysUntilBlockEnds, 1,
        reason: 'plan.duration_weeks only: a Program Builder program had no end');
  });
}
