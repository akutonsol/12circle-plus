// The coach's nutrition targets were invented when they could not be read.
//
// nutritionGoalsProvider caught every failure and returned the defaults
// (2000 kcal, 120 g protein, 220 g carbs, 65 g fat), and both nutrition screens
// fell back to the same numbers. A client whose coach set 1500 kcal and 160 g
// protein was shown "x / 2000 kcal", a 120 g protein ring and "You still need
// ...g protein" advice built on 120 g -- with nothing saying the plan had not
// loaded. A failed read is never shown as data (error contract), so the screens
// now say the targets could not be loaded, and offer Try again.
//
// "No plan assigned" (no row) still shows the defaults: whether it should is a
// product decision this does not touch.
//
// HOW TO SEE IT FAIL: on main the provider resolves to the defaults and both
// screens print 2000.

import 'dart:convert';

import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/nutrition/domain/nutrition_provider.dart';
import 'package:circle_fitness/features/nutrition/presentation/meals_dashboard_screen.dart';
import 'package:circle_fitness/features/nutrition/presentation/nutrition_screen.dart';
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
  bool planFails = false;
  Map<String, Object?>? plan;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final single = request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
    if (path.endsWith('/client_nutrition_plans') && request.method == 'GET') {
      if (planFails) return _json({'message': 'offline'}, 500, request);
      return _json(single ? plan : [if (plan != null) plan], 200, request);
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

  setUp(() {
    server.planFails = false;
    server.plan = null;
  });

  Future<void> open(WidgetTester t, Widget screen) async {
    t.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 3000);
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(Supabase.instance.client.auth.currentUser),
      ],
      child: MaterialApp(home: screen),
    ));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  test('a failed read of the plan is an error, not the default targets', () async {
    server.planFails = true;
    final c = ProviderContainer(overrides: [
      currentUserProvider.overrideWithValue(Supabase.instance.client.auth.currentUser),
    ]);
    addTearDown(c.dispose);
    await expectLater(c.read(nutritionGoalsProvider.future), throwsA(anything),
        reason: 'THE defect: the read failed and the defaults came back as the plan');
  });

  for (final (name, screen) in [
    ('Meals', const MealsDashboardScreen()),
    ('Nutrition', const NutritionScreen()),
  ]) {
    testWidgets('$name: targets that failed to load are said, never invented', (t) async {
      server.planFails = true;
      await open(t, screen);
      expect(find.text("Couldn't load your targets"), findsOneWidget);
      expect(find.textContaining('2000'), findsNothing,
          reason: 'the default 2000 kcal read as the coach\'s target');
      expect(find.textContaining('120g'), findsNothing,
          reason: 'the default 120 g protein read as the coach\'s target');
      expect(find.textContaining('still need'), findsNothing,
          reason: 'protein advice was built on the invented 120 g');
    });

    testWidgets('$name: the coach\'s real targets are shown (positive control)', (t) async {
      server.plan = {'calories_target': 1500, 'protein_g': 160, 'carbs_g': 150, 'fat_g': 50};
      await open(t, screen);
      expect(find.textContaining('160g'), findsWidgets,
          reason: 'the coach\'s 160 g protein target is the one shown');
      expect(find.text("Couldn't load your targets"), findsNothing);
    });
  }
}
