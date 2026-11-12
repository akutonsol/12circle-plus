import 'dart:convert';

import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/nutrition/presentation/meals_dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// FIT-022 built the meals dashboard a failure state for exactly this: "a
// client who had logged three meals was shown zero calories, and may well
// have logged them again." The screen shows `NutritionLoadFailed` when
// `nutritionTotalsProvider` is an `AsyncError`, and nothing in place of the
// meal list when its read fails.
//
// Neither could happen. `NutritionService.getTodayTotals` ended in
// `catch (e) { return {calories: 0, …}; }` and `getLogsForDate` /
// `getTodayLogs` in `catch (e) { return []; }`, so a failed read arrived as a
// day with nothing logged: 0 kcal, and "No breakfasts logged — + Log a meal".
// The A-G5/A-G6 shape again.
//
// These tests mount the real screen over the real service and a fake PostgREST.

const _uid = '00000000-0000-4000-8000-0000000f00d1';

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

class _Server extends http.BaseClient {
  bool logsFail = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final single = request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
    if (path.endsWith('/nutrition_logs') && request.method == 'GET') {
      return logsFail
          ? _json({'message': 'offline'}, 500, request)
          : _json([], 200, request);
    }
    return _json(single ? null : [], 200, request);
  }

  http.StreamedResponse _json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

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

  setUp(() => server.logsFail = false);

  Future<void> open(WidgetTester t) async {
    t.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 3000);
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(Supabase.instance.client.auth.currentUser),
      ],
      child: const MaterialApp(home: MealsDashboardScreen()),
    ));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets("a failed read shows FIT-022's failure, not a day of zero", (t) async {
    server.logsFail = true;
    await open(t);
    expect(find.text("Couldn't load today"), findsOneWidget,
        reason: 'THE defect: the service turned the failure into zeros, so '
            'the failure state could never be shown');
  });

  testWidgets('a failed read does not invite logging the meals again', (t) async {
    server.logsFail = true;
    await open(t);
    expect(find.text('No breakfasts logged'), findsNothing,
        reason: 'the read failed; nothing is known about breakfast');
    expect(find.text('+ Log a meal'), findsNothing);
  });

  testWidgets('control: a day with nothing logged says so', (t) async {
    await open(t);
    expect(find.text("Couldn't load today"), findsNothing);
    expect(find.text('No breakfasts logged'), findsOneWidget);
  });
}
