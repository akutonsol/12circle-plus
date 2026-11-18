import 'dart:convert';

import 'package:circle_fitness/features/coach/data/coach_relationship_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// OWNER DECISION 2, 2026-11-15: ending coaching cancels a PAID coaching
// subscription at the end of the period already paid for, and coaching lasts
// until then; an unpaid relationship ends now.
//
// cancelCoach -- used by Profile's Cancel Coach, Settings' switch to Self/AI and
// the intake coach switch -- ended only the relationship, so a client paying for
// a monthly package kept being billed for a coach they had left. (Manage
// Subscription's Stop looked for kind 'coach' only and missed the packages the
// app actually sells.)
//
// HOW TO SEE IT FAIL: on main the paid case PATCHes the relationship to
// cancelled and never calls cancel-subscription.

const _uid = '00000000-0000-4000-8000-0000000e0dc0';

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

class _Server extends http.BaseClient {
  List<Map<String, Object?>> paid = [];
  Map<String, Object?> cancelAnswer = {'ok': true, 'endsAt': '2026-12-01T00:00:00Z'};
  int cancelStatus = 200;
  final List<String> calls = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    Object? body = [];
    var status = 200;
    if (path.endsWith('/subscriptions') && request.method == 'GET') {
      body = paid;
    } else if (path.endsWith('/functions/v1/cancel-subscription')) {
      calls.add('cancel-subscription ${await request.finalize().bytesToString()}');
      status = cancelStatus;
      body = cancelStatus == 200 ? cancelAnswer : {'error': 'stripe_cancel_failed'};
    } else if (path.endsWith('/coach_client_relationships') && request.method == 'PATCH') {
      calls.add('PATCH relationship ${await request.finalize().bytesToString()}');
      // The update matched the active relationship (cancelCoach checks rows).
      body = [{'id': 'rel-1'}];
    } else if (request.method == 'POST') {
      status = 201;
      body = null;
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

  setUp(() {
    server.calls.clear();
    server.paid = [];
    server.cancelStatus = 200;
  });

  test('a paid monthly package is cancelled at period end; coaching continues', () async {
    server.paid = [
      {'id': 'sub-row-1', 'current_period_end': '2026-12-01T00:00:00Z'},
    ];
    await CoachRelationshipService().cancelCoach('coach-1', 'client_cancelled', null);
    expect(server.calls.where((c) => c.startsWith('cancel-subscription')), hasLength(1),
        reason: 'THE defect: the paid subscription was never cancelled -- it kept billing');
    expect(server.calls.where((c) => c.startsWith('PATCH relationship')), isEmpty,
        reason: 'coaching lasts until the end of the paid period');
  });

  test('no paid subscription: the relationship ends now (positive control)', () async {
    await CoachRelationshipService().cancelCoach('coach-1', 'client_cancelled', null);
    expect(server.calls.where((c) => c.startsWith('cancel-subscription')), isEmpty);
    expect(server.calls.single, contains('"status":"cancelled"'));
  });

  test('a failed cancellation changes nothing and is reported', () async {
    server.paid = [
      {'id': 'sub-row-1', 'current_period_end': '2026-12-01T00:00:00Z'},
    ];
    server.cancelStatus = 502;
    await expectLater(
        CoachRelationshipService().cancelCoach('coach-1', 'client_cancelled', null),
        throwsA(anything));
    expect(server.calls.where((c) => c.startsWith('PATCH relationship')), isEmpty,
        reason: 'the relationship must not end while the subscription still bills');
  });

  test('the client is told when coaching ends', () {
    final scheduled = CoachingEnd.at(DateTime(2026, 12, 1));
    expect(scheduled.scheduled, isTrue);
    expect(scheduled.describe(), contains('until Dec 1'));
    expect(const CoachingEnd.now().describe(), startsWith('Coaching ended'));
  });
}
