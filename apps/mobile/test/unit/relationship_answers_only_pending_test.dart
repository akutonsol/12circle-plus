import 'dart:convert';

import 'package:circle_fitness/features/coach/data/coach_relationship_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// A coach's Approve / Decline updated the relationship by id alone.
//
//   approveRequest  .update({status: active, ...}).eq('id', id)
//   declineRequest  .update({status: rejected}).eq('id', id)
//
// Both are "answer a PENDING request", and the empty-result check after them
// assumed the update would skip a row that was no longer pending -- but nothing
// told the update so. Approving from a stale request list therefore set a
// relationship the CLIENT had since cancelled back to 'active' (the RLS update
// policy lets a coach activate a client-initiated row), and Decline could end a
// live one. Both now answer only a row that is still pending.
//
// The same service, the profile's Cancel Coach and the intake's coach switch
// wrote pending_at / activated_at / cancelled_at -- all timestamptz -- as zoneless
// local time, which Postgres reads as UTC: hours off west or east of UTC.
//
// HOW TO SEE IT FAIL: on main the approve succeeds and reactivates the cancelled
// row, and every timestamp on the wire has no zone.

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

bool _zoned(String v) => v.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(v);

/// One relationship row; PATCH applies PostgREST's eq. filters to it.
class _Server extends http.BaseClient {
  Map<String, Object?> row = {};
  final List<Map<String, Object?>> written = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final q = request.url.queryParameters;
    Object? body = [];
    var status = 200;
    if (path.endsWith('/coach_client_relationships')) {
      final text = await request.finalize().bytesToString();
      if (request.method == 'PATCH' || request.method == 'POST') {
        final patch = Map<String, Object?>.from(jsonDecode(text) as Map);
        written.add(patch);
        if (request.method == 'POST') {
          status = 201;
          body = null;
        } else {
          final matches = q.entries.every((e) {
            if (!e.value.startsWith('eq.')) return true;
            return '${row[e.key]}' == e.value.substring(3);
          });
          if (matches) row.addAll(patch);
          body = matches ? [{'id': row['id']}] : [];
        }
      } else {
        body = [];
      }
    }
    return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
        request: request, headers: {'content-type': 'application/json'});
  }
}

void main() {
  final server = _Server();

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
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

  setUp(server.written.clear);

  test('approving a request the client has since cancelled changes nothing', () async {
    server.row = {'id': 'rel-1', 'client_id': 'client-1', 'coach_id': _uid,
                  'status': 'cancelled', 'initiated_by': 'client'};
    await expectLater(
        CoachRelationshipService().approveRequest('rel-1', 'client-1'),
        throwsA(isA<StateError>()),
        reason: 'the coach is told the request is no longer pending');
    expect(server.row['status'], 'cancelled',
        reason: 'THE defect: a stale Approve reactivated a relationship the client ended');
  });

  test('declining a relationship that is already active changes nothing', () async {
    server.row = {'id': 'rel-2', 'client_id': 'client-2', 'coach_id': _uid,
                  'status': 'active', 'initiated_by': 'client'};
    await expectLater(CoachRelationshipService().declineRequest('rel-2', 'client-2'),
        throwsA(isA<StateError>()));
    expect(server.row['status'], 'active', reason: 'Decline ended a live relationship');
  });

  test('approving a pending request works, and activated_at carries a zone', () async {
    server.row = {'id': 'rel-3', 'client_id': 'client-3', 'coach_id': _uid,
                  'status': 'pending', 'initiated_by': 'client'};
    await CoachRelationshipService().approveRequest('rel-3', 'client-3');
    expect(server.row['status'], 'active', reason: 'positive control');
    final at = server.written.single['activated_at'] as String;
    expect(_zoned(at), isTrue, reason: '`$at` has no zone; Postgres stores it as UTC');
  });

  test('a request and a cancellation are stamped with real instants', () async {
    server.row = {'id': 'rel-4', 'client_id': _uid, 'coach_id': 'coach-9',
                  'status': 'active', 'initiated_by': 'client'};
    await CoachRelationshipService().cancelCoach('coach-9', 'other', null);
    final cancelled = server.written.last['cancelled_at'] as String;
    expect(_zoned(cancelled), isTrue, reason: '`$cancelled` has no zone');

    await CoachRelationshipService().requestCoach('coach-8');
    final pending = server.written.last['pending_at'] as String;
    expect(_zoned(pending), isTrue, reason: '`$pending` has no zone');
  });
}
