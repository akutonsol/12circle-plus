import 'dart:convert';

import 'package:circle_fitness/features/coach_notes/presentation/coach_notes_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// Deleting a coach note that the server refused escaped unhandled, with nothing
// said. The sheet's save and read report their failures (#78); its delete did
// not. It now says "Couldn't delete the note — try again." and keeps the note.



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

/// `coach_notes`, which can be told to fail its read or its insert.
class _Server extends http.BaseClient {
  bool readFails = false;
  bool insertFails = false;
  bool deleteFails = false;
  final notes = <Map<String, Object?>>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!request.url.path.endsWith('/coach_notes')) return _json([], 200, request);
    if (request.method == 'GET') {
      if (readFails) return _json({'message': 'offline'}, 500, request);
      return _json(notes, 200, request);
    }
    if (request.method == 'POST') {
      if (insertFails) return _json({'message': 'offline'}, 500, request);
      final row = jsonDecode((request as http.Request).body) as Map<String, dynamic>;
      notes.insert(0, {
        ...row,
        'id': 'n${notes.length + 1}',
        'created_at': '2026-11-12T10:00:00Z',
      });
      return _json(null, 201, request);
    }
    if (request.method == 'DELETE') {
      if (deleteFails) return _json({'message': 'offline'}, 500, request);
      notes.clear();
      return _json(null, 204, request);
    }
    return _json([], 200, request);
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
    server
      ..readFails = false
      ..insertFails = false
      ..deleteFails = false
      ..notes.clear();
  });

  /// Opens the sheet for client X, as client detail's Notes action does.
  Future<void> openSheet(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () =>
                  showCoachNotesSheet(context, ref, 'client-x', 'Ana Lee'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> write(WidgetTester tester, String note) async {
    await tester.enterText(find.byType(TextField), note);
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
  }

  testWidgets('a delete the server refused keeps the note and says so', (tester) async {
    await openSheet(tester);
    await write(tester, 'Watch left knee on squats');
    expect(find.text('Watch left knee on squats'), findsOneWidget);
    server.deleteFails = true;
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'THE defect: the failure escaped unhandled');
    expect(find.text("Couldn't delete the note — try again."), findsOneWidget);
    expect(find.text('Watch left knee on squats'), findsOneWidget);
  });

  testWidgets('control: a delete that worked removes the note', (tester) async {
    await openSheet(tester);
    await write(tester, 'Temporary');
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
    expect(find.text('Temporary'), findsNothing);
  });
}
