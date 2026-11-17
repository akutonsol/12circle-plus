import 'dart:convert';

import 'package:circle_fitness/features/coach/domain/coach_provider.dart';
import 'package:circle_fitness/features/profile/presentation/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// Profile's "Cancel Coach" said "Could not end coaching. Nothing was changed.
// Try again." for every failure, discarding what cancelCoach said happened
// ("No active coaching with this coach — nothing was changed."). Retrying a
// relationship that is already over cannot work; the client was told to.
// The marketplace already shows a StateError's message; this follows it
// (P0-FL-1 follow-up F2).

const _uid = '00000000-0000-4000-8000-0000000c0ac5';

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

/// The token is read, never verified client-side.
String _jwt() {
  final exp =
      DateTime.now().add(const Duration(days: 3650)).millisecondsSinceEpoch ~/
          1000;
  return '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${_b64({
        'sub': _uid,
        'role': 'authenticated',
        'exp': exp,
        'aud': 'authenticated'
      })}.'
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

/// The relationship update matches no row, or fails outright.
class _Server extends http.BaseClient {
  bool matchesNoRow = false;
  bool fails = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'PATCH' &&
        request.url.path.endsWith('/coach_client_relationships')) {
      if (fails) return _json({'message': 'offline'}, 503, request);
      return _json(
          matchesNoRow
              ? []
              : [
                  {'id': 'rel-a'}
                ],
          200,
          request);
    }
    return _json([], 200, request);
  }

  http.StreamedResponse _json(Object body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

const _coachA = {'id': 'coach-a', 'first_name': 'Avery', 'last_name': 'Stone'};
const _generic = 'Could not end coaching. Nothing was changed. Try again.';
const _noActive = 'No active coaching with this coach — nothing was changed.';

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
        detectSessionInUri: false,
      ),
      debug: false,
    );
  });

  setUp(() {
    server
      ..matchesNoRow = false
      ..fails = false;
  });

  Future<void> cancelFromCard(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        assignedCoachProvider.overrideWith((ref) async => _coachA),
        clientRelationshipProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MyCoachSection(onCoachCancelled: () {}),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel Coach'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not a good fit'));
    await tester.pump();
    await tester.tap(find.text('Cancel Coach').last);
    await tester.pumpAndSettle();
  }

  testWidgets("a relationship that matched no row says why, verbatim",
      (tester) async {
    server.matchesNoRow = true;
    await cancelFromCard(tester);

    expect(find.text(_noActive), findsOneWidget);
    expect(find.text(_generic), findsNothing);
  });

  testWidgets('any other failure keeps the generic text', (tester) async {
    server.fails = true; // a 503: PostgrestException, not a StateError
    await cancelFromCard(tester);

    expect(find.text(_generic), findsOneWidget);
    expect(find.text(_noActive), findsNothing);
  });
}
