import 'dart:convert';

import 'package:circle_fitness/features/coach/data/coach_relationship_service.dart';
import 'package:circle_fitness/features/payments/data/payment_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// P0-FL-55(b) — cycle 10's FL-51 left a surviving mutant: no test sent the
// cancel-subscription Edge Function a 200 reply WITHOUT `ok: true`.
//
// HTTP 200 is not "cancelled". The function answers 200 for a body it built,
// and only `{"ok": true}` says Stripe accepted the cancellation. If either
// client path took any 200 as success, a client stopping a paid coach would be
// told their coaching ends at period end while Stripe kept billing them.
//
// Both client paths that call the function are pinned:
//  * CoachRelationshipService.cancelCoach — every "stop coach" entry point
//    (Profile, Settings, Manage Subscription's Stop, the intake switch);
//  * PaymentService.cancelSubscription — Manage Subscription / downgrade.
//
// HOW TO SEE IT FAIL: the code on b7ec6ef already requires `ok == true`, so
// these pass there. Replace `d['ok'] != true` with `false` in cancelCoach (or
// `res.data['ok'] == true` with `true` in cancelSubscription) and the
// "not success" cases fail — the mutant FL-51 left alive.

const _uid = '00000000-0000-4000-8000-0000000f1055';

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

  /// The cancel-subscription reply body, always with HTTP 200.
  Object? cancelReply = {'ok': true, 'endsAt': '2026-12-01T12:00:00Z'};
  final List<String> calls = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    Object? body = [];
    var status = 200;
    if (path.endsWith('/subscriptions') && request.method == 'GET') {
      body = paid;
    } else if (path.endsWith('/functions/v1/cancel-subscription')) {
      calls.add('cancel-subscription');
      body = cancelReply;
    } else if (path.endsWith('/coach_client_relationships') && request.method == 'PATCH') {
      calls.add('PATCH relationship');
      body = [{'id': 'rel-1'}];
    } else if (path.endsWith('/notifications') && request.method == 'POST') {
      calls.add('POST notification');
      status = 201;
      body = null;
    } else if (request.headers['Accept']?.contains('vnd.pgrst.object') ?? false) {
      body = {'first_name': 'Ana', 'last_name': 'Lee'};
    }
    return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
        request: request, headers: {'content-type': 'application/json'});
  }
}

/// 200 replies that do NOT say the subscription was cancelled.
const _notOk = <String, Object?>{
  'empty object {}': <String, Object?>{},
  '{"ok": false}': {'ok': false},
  '{"error": "…"} with 200': {'error': 'stripe_cancel_failed'},
  '{"ok": "true"} (string, not true)': {'ok': 'true'},
  '{"ok": 1}': {'ok': 1},
  'a JSON array': <Object?>[],
  'JSON null': null,
};

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
    server.paid = [
      {'id': 'sub-row-1', 'current_period_end': '2026-12-01T00:00:00Z'},
    ];
    server.cancelReply = {'ok': true, 'endsAt': '2026-12-01T12:00:00Z'};
  });

  group('stop coach (cancelCoach): a 200 without ok:true is not success', () {
    for (final e in _notOk.entries) {
      test(e.key, () async {
        server.cancelReply = e.value;
        await expectLater(
            CoachRelationshipService().cancelCoach('coach-1', 'client_cancelled', null),
            throwsA(isA<StateError>()),
            reason: 'a 200 that does not say ok:true was reported as '
                '"coaching ends at period end" while Stripe kept billing');
        expect(server.calls, ['cancel-subscription'],
            reason: 'nothing else changes: the relationship stays, the coach '
                'is not told coaching ended');
      });
    }

    test('positive control: {"ok": true} schedules the end at endsAt', () async {
      final end = await CoachRelationshipService()
          .cancelCoach('coach-1', 'client_cancelled', null);
      expect(end.scheduled, isTrue);
      expect(end.describe(), contains('until Dec 1'));
      expect(server.calls, ['cancel-subscription']);
    });

    test('negative control: no paid subscription (a real absence) ends '
        'coaching now without calling the function', () async {
      server.paid = [];
      final end = await CoachRelationshipService()
          .cancelCoach('coach-1', 'client_cancelled', null);
      expect(end.scheduled, isFalse);
      expect(server.calls, isNot(contains('cancel-subscription')));
      expect(server.calls.first, 'PATCH relationship');
    });
  });

  group('PaymentService.cancelSubscription: a 200 without ok:true is false', () {
    for (final e in _notOk.entries) {
      test(e.key, () async {
        server.cancelReply = e.value;
        expect(await PaymentService().cancelSubscription('sub-row-1'), isFalse);
        expect(server.calls, ['cancel-subscription']);
      });
    }

    test('positive control: {"ok": true} is true', () async {
      expect(await PaymentService().cancelSubscription('sub-row-1'), isTrue);
    });
  });
}
