import 'dart:convert';

import 'package:circle_fitness/features/goals/presentation/goals_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// /goals has a failure state — "Could not load goals" — that could not be
// reached: `GoalService.getMyGoals` caught every error and returned `[]`, so a
// failed read told a client who had set goals "No goals yet / Tap "New Goal"
// to set your first target." And `myGoalsProvider` was kept for the session,
// so that answer stayed until the app restarted.
//
// The read now throws, and the provider is read again on each visit, so a
// stated failure can also clear.

const _uid = '00000000-0000-4000-8000-0000000609a1';

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

/// `goals`, which can be told to fail.
class _Server extends http.BaseClient {
  bool fails = false;
  final goals = <Map<String, Object?>>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path.endsWith('/goals')) {
      if (fails) return _json({'message': 'offline'}, 500, request);
      return _json(goals, 200, request);
    }
    return _json([], 200, request);
  }

  http.StreamedResponse _json(Object body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

final _goal = <String, Object?>{
  'id': 'g1', 'client_id': _uid, 'title': 'Bench 100 kg', 'type': 'strength',
  'start_value': 80, 'target_value': 100, 'current_value': 90, 'unit': 'kg',
  'status': 'active', 'created_at': '2026-11-01T10:00:00Z',
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

  setUp(() {
    server
      ..fails = false
      ..goals.clear();
  });

  Future<void> show(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(home);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('a FAILED read says so, not "No goals yet"', (tester) async {
    server.goals.add(_goal);
    server.fails = true;
    await show(tester,
        const ProviderScope(child: MaterialApp(home: GoalsScreen())));
    expect(find.text('No goals yet'), findsNothing,
        reason: 'THE defect: a client with a goal was told they have none');
    expect(find.text('Could not load goals'), findsOneWidget);
  });

  testWidgets('a failure clears on the next visit', (tester) async {
    server.goals.add(_goal);
    server.fails = true;
    // One app session: the scope outlives the screen.
    final app = ProviderContainer();
    addTearDown(app.dispose);
    Widget screen(Widget home) =>
        UncontrolledProviderScope(container: app, child: MaterialApp(home: home));
    await show(tester, screen(const GoalsScreen()));
    expect(find.text('Could not load goals'), findsOneWidget);

    await show(tester, screen(const SizedBox())); // leave /goals
    server.fails = false;
    await show(tester, screen(const GoalsScreen())); // and come back

    expect(find.text('Bench 100 kg'), findsOneWidget);
  });

  testWidgets('a goal set since the last visit shows on the next one',
      (tester) async {
    final app = ProviderContainer();
    addTearDown(app.dispose);
    Widget screen(Widget home) =>
        UncontrolledProviderScope(container: app, child: MaterialApp(home: home));
    await show(tester, screen(const GoalsScreen()));
    expect(find.text('No goals yet'), findsOneWidget);

    await show(tester, screen(const SizedBox()));
    server.goals.add(_goal); // e.g. set by the coach (goals.coach_id)
    await show(tester, screen(const GoalsScreen()));

    expect(find.text('Bench 100 kg'), findsOneWidget,
        reason: 'kept for the session, the first answer stayed');
  });

  testWidgets('no goals is still said plainly (control)', (tester) async {
    await show(tester,
        const ProviderScope(child: MaterialApp(home: GoalsScreen())));
    expect(find.text('No goals yet'), findsOneWidget);
    expect(find.text('Could not load goals'), findsNothing);
  });
}
