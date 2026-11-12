import 'dart:convert';

import 'package:circle_fitness/features/coach_notes/presentation/coach_notes_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// The coach's private notes sheet, on a client's page. Both of its outcomes
// could be false:
//
//   * A failed save cleared what the coach had typed. `addNote` returns false
//     on failure and `_add` never looked: the text went, the list re-read
//     without it, and nothing said the note was never kept.
//   * A failed read said "No notes yet. Add your first below." `getNotes`
//     caught every error into an empty list, so the sheet's own
//     "Could not load notes" state could never be reached — for a client
//     whose injuries the coach had written down.
//
// These drive the real sheet and the real service against a fake PostgREST.

const _uid = '00000000-0000-4000-8000-0000000c0ac4';

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

/// `coach_notes`, which can be told to fail its read or its insert.
class _Server extends http.BaseClient {
  bool readFails = false;
  bool insertFails = false;
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

  testWidgets('a FAILED save keeps what the coach typed, and says so',
      (tester) async {
    await openSheet(tester);
    server.insertFails = true;
    await write(tester, 'Left knee: no deep squats until cleared');

    expect(find.text('Left knee: no deep squats until cleared'), findsOneWidget,
        reason: 'THE defect: the typed note was cleared though nothing was kept');
    expect(find.text('Could not save note. Try again.'), findsOneWidget);
  });

  testWidgets('a FAILED read is not "No notes yet"', (tester) async {
    server.notes.add({
      'id': 'n1', 'client_id': 'client-x', 'coach_id': _uid,
      'body': 'Left knee', 'tag': 'injury', 'created_at': '2026-11-01T10:00:00Z',
    });
    server.readFails = true;
    await openSheet(tester);

    expect(find.text('No notes yet. Add your first below.'), findsNothing,
        reason: 'THE defect: the client has a note the read failed to fetch');
    expect(find.text('Could not load notes'), findsOneWidget);
  });

  testWidgets('a failed read is not kept: opening the sheet again reads again',
      (tester) async {
    server.notes.add({
      'id': 'n1', 'client_id': 'client-x', 'coach_id': _uid,
      'body': 'Left knee', 'tag': 'injury', 'created_at': '2026-11-01T10:00:00Z',
    });
    server.readFails = true;
    await openSheet(tester);
    expect(find.text('Could not load notes'), findsOneWidget);

    // Close it, the connection comes back, open it again.
    await tester.tapAt(const Offset(250, 20));
    await tester.pumpAndSettle();
    server.readFails = false;
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Left knee'), findsOneWidget);
  });

  // ── Controls ──────────────────────────────────────────────────────────────

  testWidgets('a saved note clears the composer and is listed', (tester) async {
    await openSheet(tester);
    await write(tester, 'Prefers morning check-ins');

    expect(find.text('Could not save note. Try again.'), findsNothing);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isEmpty);
    expect(find.text('Prefers morning check-ins'), findsOneWidget,
        reason: 'listed after the re-read');
  });

  testWidgets('a client with no notes is still told so', (tester) async {
    await openSheet(tester);
    expect(find.text('No notes yet. Add your first below.'), findsOneWidget);
    expect(find.text('Could not load notes'), findsNothing);
  });
}
