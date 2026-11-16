import 'dart:convert';

import 'package:circle_fitness/features/coach/domain/coach_provider.dart';
import 'package:circle_fitness/features/payments/domain/entitlements.dart';
import 'package:circle_fitness/features/profile/presentation/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// Ending coaching from Profile left the coaching features unlocked.
//
// An active relationship is also a plan: `client_plan()` answers coach_guided
// for one, and `PaywallGate` reads `clientPlanProvider`. Profile's "Cancel
// Coach" refreshed the coach card and the relationship but not the plan, so a
// client who had just ended an (unpaid, coach-approved) relationship still saw
// Messages, Bookings and Action Items open on the cached coach_guided plan
// until something else re-read it. Settings' and Manage Subscription's paths
// already re-read it; this one did not.

const _uid = '00000000-0000-4000-8000-0000000c0ad5';

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
  bool failNext = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'PATCH' &&
        request.url.path.endsWith('/coach_client_relationships')) {
      if (failNext) {
        failNext = false;
        return _json({'message': 'boom'}, 500, request);
      }
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

  testWidgets('ending coaching re-reads the plan and the coach list', (tester) async {
    var planReads = 0, coachReads = 0;
    final c = ProviderContainer(overrides: [
      assignedCoachProvider.overrideWith((ref) async => _coachA),
      clientRelationshipProvider.overrideWith((ref) async => null),
      clientPlanProvider.overrideWith((ref) async {
        planReads++;
        return ClientPlan.coachGuided;
      }),
      myCoachesProvider.overrideWith((ref) async {
        coachReads++;
        return const [];
      }),
    ]);
    addTearDown(c.dispose);
    // Mounted screens (PaywallGate, the coach list) keep these alive.
    c.listen(clientPlanProvider, (_, __) {});
    c.listen(myCoachesProvider, (_, __) {});

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: MyCoachSection(onCoachCancelled: () {})),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Coach Avery Stone'), findsOneWidget, reason: 'guard the premise');
    expect(planReads, 1);

    await tester.tap(find.text('Cancel Coach'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not a good fit'));
    await tester.pump();
    await tester.tap(find.text('Cancel Coach').last);
    await tester.pumpAndSettle();

    expect(server.patches, hasLength(1), reason: 'guard the premise: coaching was ended');
    expect(planReads, 2,
        reason: 'THE defect: the plan stayed coach_guided after coaching ended');
    expect(coachReads, 2, reason: 'the coach list is re-read too');
  });

  testWidgets('a failed end changes nothing, so nothing is re-read', (tester) async {
    var planReads = 0;
    server.failNext = true;
    final c = ProviderContainer(overrides: [
      assignedCoachProvider.overrideWith((ref) async => _coachA),
      clientRelationshipProvider.overrideWith((ref) async => null),
      clientPlanProvider.overrideWith((ref) async {
        planReads++;
        return ClientPlan.coachGuided;
      }),
    ]);
    addTearDown(c.dispose);
    c.listen(clientPlanProvider, (_, __) {});

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: MyCoachSection(onCoachCancelled: () {})),
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

    expect(find.textContaining('Could not end coaching'), findsOneWidget,
        reason: 'guard the premise: the end failed');
    expect(planReads, 1);
  });
}
