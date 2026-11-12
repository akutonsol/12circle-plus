import 'dart:convert';

import 'package:circle_fitness/features/action_items/presentation/action_center_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// /action-items has a failure state — "Could not load your action items" —
// that could not be reached: `ActionItemService.getMyActionItems` caught every
// error and returned `[]`, so a failed read told a client with tasks waiting
// "No action items yet / Your coach will assign tasks here." And
// `myActionItemsProvider` was kept for the session, so that answer stayed —
// as did the list from before the coach assigned anything new — until the
// app restarted.
//
// The read now throws, and the provider is read again on each visit.

const _uid = '00000000-0000-4000-8000-0000000ac71e';

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

/// `action_items`, which can be told to fail.
class _Server extends http.BaseClient {
  bool fails = false;
  final items = <Map<String, Object?>>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path.endsWith('/action_items')) {
      if (fails) return _json({'message': 'offline'}, 500, request);
      return _json(items, 200, request);
    }
    return _json([], 200, request);
  }

  http.StreamedResponse _json(Object body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

final _item = <String, Object?>{
  'id': 'a1', 'client_id': _uid, 'coach_id': 'coach-a',
  'title': 'Log three meals today', 'description': '', 'category': 'daily',
  'status': 'pending', 'points': 10, 'created_by': 'coach',
  'created_at': '2026-11-12T08:00:00Z',
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
      ..items.clear();
  });

  Future<void> show(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(home);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('a FAILED read says so, not "No action items yet"', (tester) async {
    server.items.add(_item);
    server.fails = true;
    await show(tester,
        const ProviderScope(child: MaterialApp(home: ActionCenterScreen())));
    expect(find.text('No action items yet'), findsNothing,
        reason: 'THE defect: a client with a task was told they have none');
    expect(find.text('Could not load your action items'), findsOneWidget);
  });

  testWidgets('a failure clears on the next visit', (tester) async {
    server.items.add(_item);
    server.fails = true;
    // One app session: the scope outlives the screen.
    final app = ProviderContainer();
    addTearDown(app.dispose);
    Widget screen(Widget home) =>
        UncontrolledProviderScope(container: app, child: MaterialApp(home: home));
    await show(tester, screen(const ActionCenterScreen()));
    expect(find.text('Could not load your action items'), findsOneWidget);

    await show(tester, screen(const SizedBox())); // leave /action-items
    server.fails = false;
    await show(tester, screen(const ActionCenterScreen())); // and come back

    expect(find.text('Log three meals today'), findsOneWidget);
  });

  testWidgets('a task assigned since the last visit shows on the next one',
      (tester) async {
    final app = ProviderContainer();
    addTearDown(app.dispose);
    Widget screen(Widget home) =>
        UncontrolledProviderScope(container: app, child: MaterialApp(home: home));
    await show(tester, screen(const ActionCenterScreen()));
    expect(find.text('No action items yet'), findsOneWidget);

    await show(tester, screen(const SizedBox()));
    server.items.add(_item); // the coach assigned one
    await show(tester, screen(const ActionCenterScreen()));

    expect(find.text('Log three meals today'), findsOneWidget,
        reason: 'kept for the session, the first answer stayed');
  });

  testWidgets('no action items is still said plainly (control)', (tester) async {
    await show(tester,
        const ProviderScope(child: MaterialApp(home: ActionCenterScreen())));
    expect(find.text('No action items yet'), findsOneWidget);
    expect(find.text('Could not load your action items'), findsNothing);
  });
}
