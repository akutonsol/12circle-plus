import 'dart:convert';

import 'package:circle_fitness/features/coach/domain/coach_provider.dart';
import 'package:circle_fitness/features/profile/presentation/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// Profile's "Cancel Coach" cancelled a different relationship than the coach
// on the card.
//
// The card draws `assignedCoachProvider`: the newest ACTIVE relationship. The
// button cancelled `clientRelationshipProvider`'s row: the newest relationship
// of ANY status, by `created_at`. A client may hold several, so with coach A
// active and a later request to coach B pending, "Cancel Coach" under A's name
// cancelled the request to B — and A stayed their coach, still billed, with
// the card unchanged.

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

/// Records every relationship write's filters.
class _Server extends http.BaseClient {
  final patches = <Map<String, String>>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'PATCH' &&
        request.url.path.endsWith('/coach_client_relationships')) {
      patches.add(request.url.queryParameters);
      return _json([{'id': 'rel-a'}], 200, request);
    }
    return _json([], 200, request);
  }

  http.StreamedResponse _json(Object body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

const _coachA = {'id': 'coach-a', 'first_name': 'Avery', 'last_name': 'Stone'};

/// Coach B's request: newer than A's relationship, so it is the newest row.
const _pendingB = {
  'id': 'rel-b',
  'coach_id': 'coach-b',
  'status': 'pending',
  'created_at': '2026-11-09T12:00:00Z',
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

  Future<void> cancelFromCard(WidgetTester tester,
      {required Map<String, dynamic> newest}) async {
    server.patches.clear();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        assignedCoachProvider.overrideWith((ref) async => _coachA),
        clientRelationshipProvider.overrideWith((ref) async => newest),
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
    expect(find.text('Coach Avery Stone'), findsOneWidget, reason: 'guard the premise');

    await tester.tap(find.text('Cancel Coach'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not a good fit'));
    await tester.pump();
    await tester.tap(find.text('Cancel Coach').last);
    await tester.pumpAndSettle();
  }

  testWidgets("cancelling the coach on the card cancels THAT coach's relationship",
      (tester) async {
    await cancelFromCard(tester, newest: _pendingB);

    expect(server.patches, hasLength(1));
    final filters = server.patches.single;
    expect(filters['id'], isNot('eq.rel-b'),
        reason: "the request to coach B is not the coach on the card");
    expect(filters['coach_id'], 'eq.coach-a');
    expect(filters['client_id'], 'eq.$_uid');
    expect(filters['status'], 'eq.active',
        reason: 'only an active relationship is "your coach"');
  });

  testWidgets('it does not wait on the newest relationship to be read',
      (tester) async {
    // The button was dead while `clientRelationshipProvider` was null, though
    // the card it sits on had a coach.
    server.patches.clear();
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
    expect(find.text('Cancel Your Coach'), findsOneWidget);
  });

  testWidgets('a single active coach is still cancelled', (tester) async {
    // The common case keeps working: A's own row is also the newest.
    await cancelFromCard(tester, newest: const {
      'id': 'rel-a',
      'coach_id': 'coach-a',
      'status': 'active',
      'created_at': '2026-10-01T12:00:00Z',
    });

    expect(server.patches, hasLength(1));
    final f = server.patches.single;
    expect(f['id'] == 'eq.rel-a' || f['coach_id'] == 'eq.coach-a', isTrue,
        reason: "coach A's relationship, by either key");
  });
}
