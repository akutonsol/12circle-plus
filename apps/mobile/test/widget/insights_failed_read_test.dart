import 'dart:convert';

import 'package:circle_fitness/features/insights/presentation/insights_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// /insights has a failure state — "Could not load insights." — that could not
// be reached: `insightsProvider` caught every error and returned
// `InsightsData.empty()`, which renders under "Real numbers from your 12
// Circle activity." as today's score 0, no workouts this week, every category
// at 0 and "No score history yet". Kept for the session, that stayed until the
// app restarted.

const _uid = '00000000-0000-4000-8000-00000000a51d';

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

/// `daily_scores`, which can be told to fail.
class _Server extends http.BaseClient {
  bool fails = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path.endsWith('/daily_scores') && fails) {
      return _json({'message': 'offline'}, 500, request);
    }
    final single =
        request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
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

  setUp(() => server.fails = false);

  Future<void> show(WidgetTester tester, Widget app) async {
    await tester.binding.setSurfaceSize(const Size(500, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Unmounts and lets the scaffold's bell-shake timer run out.
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  testWidgets('a FAILED read says so, not a page of zeros', (tester) async {
    server.fails = true;
    await show(tester,
        const ProviderScope(child: MaterialApp(home: InsightsScreen())));
    expect(find.text('No score history yet — log activity to see your trend.'),
        findsNothing,
        reason: 'THE defect: a failure shown as a real, empty history');
    expect(find.text('Could not load insights.'), findsOneWidget);
    await close(tester);
  });

  testWidgets('a failure clears on the next visit', (tester) async {
    server.fails = true;
    final app = ProviderContainer();
    Widget screen(Widget home) =>
        UncontrolledProviderScope(container: app, child: MaterialApp(home: home));
    await show(tester, screen(const InsightsScreen()));
    expect(find.text('Could not load insights.'), findsOneWidget);

    await show(tester, screen(const SizedBox())); // leave /insights
    server.fails = false;
    await show(tester, screen(const InsightsScreen())); // and come back
    expect(find.text('Could not load insights.'), findsNothing);
    // The session ends: its providers (the scaffold's notification stream
    // among them) go with it, and their timers run out.
    await tester.pumpWidget(const SizedBox());
    app.dispose();
    await tester.pump(const Duration(seconds: 15));
  });

  testWidgets('no history yet is still said plainly (control)', (tester) async {
    await show(tester,
        const ProviderScope(child: MaterialApp(home: InsightsScreen())));
    expect(find.text('No score history yet — log activity to see your trend.'),
        findsOneWidget);
    await close(tester);
  });
}
