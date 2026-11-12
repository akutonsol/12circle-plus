import 'dart:convert';

import 'package:circle_fitness/features/dashboard/domain/coach_triage.dart';
import 'package:circle_fitness/features/dashboard/domain/coach_triage_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// FIT-032 · "Needs you today" on the coach dashboard was read once a session.
//
// `coachTriageSignalsProvider` was a kept FutureProvider that nothing ever
// invalidates: the dashboard's refresh-on-load, its Refresh tile and its
// pull-to-refresh name the roster, check-ins and logs, and the review screen
// names the review queue — none of them this. So after the coach reviewed a
// client's check-in (the row's own `Review` action), came back, and looked
// again, the client was still waiting for a review; answered messages still
// said "Reply"; a new client never appeared — until the app restarted.
//
// Every row leaves the dashboard with `context.go`, so a return is a new
// visit, and the provider is now read again on each one.

const _uid = '00000000-0000-4000-8000-0000000c7ea6';

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

/// One active client with a submitted check-in, until the coach reviews it.
class _Server extends http.BaseClient {
  bool reviewed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (path.endsWith('/coach_client_relationships')) {
      return _json([{'client_id': 'client-x'}], request);
    }
    if (path.endsWith('/user_profiles')) {
      return _json([{'id': 'client-x', 'first_name': 'Ana', 'last_name': 'Lee'}], request);
    }
    if (path.endsWith('/weekly_checkins')) {
      return _json([
        if (!reviewed)
          {'user_id': 'client-x', 'week_number': 3, 'notes': 'Knee felt better',
           'submitted_at': '2026-11-11T18:00:00Z', 'reviewed_at': null},
      ], request);
    }
    return _json([], request);
  }

  http.StreamedResponse _json(Object body, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), 200,
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

  setUp(() => server.reviewed = false);

  /// One visit to the dashboard: it watches the triage while it is open, and
  /// stops when the coach leaves (`context.go` unmounts it).
  Future<List<ClientSignals>> visit(ProviderContainer app) async {
    final sub = app.listen(coachTriageSignalsProvider, (_, __) {});
    final signals = await app.read(coachTriageSignalsProvider.future);
    sub.close();
    await pumpEventQueue();
    return signals;
  }

  bool waitingForReview(List<ClientSignals> s) =>
      s.any((c) => c.clientId == 'client-x' && c.unrepliedCheckinWeek != null);

  test('a check-in reviewed since the last visit no longer asks for review',
      () async {
    final app = ProviderContainer();
    addTearDown(app.dispose);

    expect(waitingForReview(await visit(app)), isTrue,
        reason: 'guard the premise: the submitted check-in shows');

    server.reviewed = true; // the coach followed the row and sent the review
    expect(waitingForReview(await visit(app)), isFalse,
        reason: 'THE defect: the reviewed client still read "Review"');
  });

  test('within one visit the answer holds (control)', () async {
    final app = ProviderContainer();
    addTearDown(app.dispose);
    final sub = app.listen(coachTriageSignalsProvider, (_, __) {});
    addTearDown(sub.close);
    final first = await app.read(coachTriageSignalsProvider.future);
    server.reviewed = true;
    final again = await app.read(coachTriageSignalsProvider.future);
    expect(identical(first, again), isTrue,
        reason: 'no re-read while the dashboard stays open');
  });
}
