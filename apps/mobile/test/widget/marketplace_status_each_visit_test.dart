import 'dart:convert';

import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/coach/presentation/coach_marketplace_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// /coach-marketplace marks each coach card "Your Coach", "Request Sent" or
// "Request to Connect" from `_myRelationshipStatusProvider`. That provider was
// kept for the whole session: it is private to the screen, so nothing that
// changes a relationship elsewhere could invalidate it, and it was not
// autoDispose, so it was read once and never again.
//
//   * A client who ended coaching (Profile, Manage Subscription, Settings) and
//     came back still saw "Your Coach" on that card, with no way to request
//     the coach again until the app restarted.
//   * A request the coach approved still read "Request Sent"; one the coach
//     declined could not be made again.
//
// The status is now read on each visit.

const _uid = '00000000-0000-4000-8000-0000000a4e75';

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

/// Answers like PostgREST with the client's relationships, which the test
/// changes between visits.
class _Server extends http.BaseClient {
  List<Map<String, Object?>> relationships = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (path.endsWith('/coach_client_relationships')) {
      return _json(relationships, 200, request);
    }
    return _json([], 200, request);
  }

  http.StreamedResponse _json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

const _coach = {
  'id': 'coach-a', 'first_name': 'Avery', 'last_name': 'Stone',
  'coach_title': 'Strength Coach', 'specialties': <String>[],
  'rating_avg': 4.8, 'review_count': 3, 'pricing_monthly': 99,
  'years_experience': 5,
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

  /// Opens the marketplace, then leaves it, in one app session.
  Future<void> visit(WidgetTester tester, ProviderContainer app) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: app,
      child: const MaterialApp(home: CoachMarketplaceScreen()),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> leave(WidgetTester tester, ProviderContainer app) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: app,
      child: const MaterialApp(home: SizedBox()),
    ));
    await tester.pumpAndSettle();
  }

  ProviderContainer session() {
    final app = ProviderContainer(overrides: [
      currentUserProvider.overrideWithValue(Supabase.instance.client.auth.currentUser),
      coachMarketplaceProvider.overrideWith((ref) async => [Map<String, dynamic>.from(_coach)]),
    ]);
    addTearDown(app.dispose);
    return app;
  }

  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('a coach the client has left can be requested again', (tester) async {
    tall(tester);
    final app = session();
    server.relationships = [{'coach_id': 'coach-a', 'status': 'active'}];
    await visit(tester, app);
    expect(find.text('Your Coach'), findsOneWidget, reason: 'premise');

    await leave(tester, app);
    server.relationships = []; // ended elsewhere: Profile, Manage Subscription…
    await visit(tester, app);

    expect(find.text('Your Coach'), findsNothing,
        reason: 'THE defect: the status read once per app session, so an '
            'ended coach still read "Your Coach"');
    expect(find.text('Request to Connect'), findsOneWidget);
  });

  testWidgets('a request the coach approved reads "Your Coach"', (tester) async {
    tall(tester);
    final app = session();
    server.relationships = [{'coach_id': 'coach-a', 'status': 'pending'}];
    await visit(tester, app);
    expect(find.text('Request Sent'), findsOneWidget, reason: 'premise');

    await leave(tester, app);
    server.relationships = [{'coach_id': 'coach-a', 'status': 'active'}];
    await visit(tester, app);

    expect(find.text('Request Sent'), findsNothing);
    expect(find.text('Your Coach'), findsOneWidget);
  });

  testWidgets('control: a first visit shows the status as read', (tester) async {
    tall(tester);
    final app = session();
    server.relationships = [{'coach_id': 'coach-a', 'status': 'pending'}];
    await visit(tester, app);
    expect(find.text('Request Sent'), findsOneWidget);
  });
}
