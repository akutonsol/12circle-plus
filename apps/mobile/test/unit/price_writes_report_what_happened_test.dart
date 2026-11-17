import 'dart:convert';

import 'package:circle_fitness/features/coach/data/coach_relationship_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// P0-FL-3: the coach's price writes had no row check. A 0-row update (RLS
// refusal, no relationship with that client) returned normally, and the
// screens said "Pricing updated." / "Custom price set to $X/mo." while
// create-checkout kept charging the standard rate. Both writes now ask for
// the changed rows back and throw when none changed.
//
// HOW TO SEE IT FAIL: on a39435d (PR #172) the 0-row cases return normally
// and the PATCH carries no `select=id`.

const _uid = '00000000-0000-4000-8000-0000000b1ce1';

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

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

/// Every PATCH matches [patchRows] rows.
class _Server extends http.BaseClient {
  List<Map<String, Object?>> patchRows = [];
  final List<String> calls = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls.add('${request.method} ${request.url.path} ${request.url.query}');
    final body = request.method == 'PATCH' ? patchRows : <Object>[];
    return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))), 200,
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
    server.patchRows = [];
  });

  final nothingChanged = throwsA(isA<StateError>()
      .having((e) => e.message, 'message', contains('nothing was changed')));

  group('setGlobalPrice', () {
    test('a 0-row update throws', () async {
      await expectLater(
          CoachRelationshipService().setGlobalPrice(150), nothingChanged,
          reason: 'THE defect: nothing saved, and the sheet said '
              '"Pricing updated."');
      expect(server.calls.single, startsWith('PATCH /rest/v1/user_profiles'));
    });

    test('a 1-row update succeeds and asked for the row back (control)',
        () async {
      server.patchRows = [
        {'id': _uid},
      ];
      await CoachRelationshipService().setGlobalPrice(150);
      final patch = server.calls.single;
      expect(patch, contains('id=eq.$_uid'));
      expect(patch, contains('select=id'));
    });
  });

  group('setClientPrice', () {
    test('a 0-row update throws (no relationship / RLS refusal)', () async {
      await expectLater(
          CoachRelationshipService().setClientPrice('client-1', 150),
          nothingChanged,
          reason: 'THE defect: "Custom price set to \$150/mo." while checkout '
              'kept charging the standard rate');
      expect(server.calls.single,
          startsWith('PATCH /rest/v1/coach_client_relationships'));
    });

    test('clearing (null) with a 0-row update also throws', () async {
      await expectLater(
          CoachRelationshipService().setClientPrice('client-1', null),
          nothingChanged);
    });

    test('a 1-row update succeeds and asked for the row back (control)',
        () async {
      server.patchRows = [
        {'id': 'rel-1'},
      ];
      await CoachRelationshipService().setClientPrice('client-1', 150);
      final patch = server.calls.single;
      expect(patch, contains('coach_id=eq.$_uid'));
      expect(patch, contains('client_id=eq.client-1'));
      expect(patch, contains('select=id'));
    });
  });
}
