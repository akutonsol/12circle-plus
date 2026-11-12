import 'dart:convert';

import 'package:circle_fitness/features/coach/domain/coach_provider.dart';
import 'package:circle_fitness/features/payments/data/payment_service.dart';
import 'package:circle_fitness/features/payments/domain/entitlements.dart';
import 'package:circle_fitness/features/payments/domain/payment_provider.dart';
import 'package:circle_fitness/features/payments/presentation/manage_subscription_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// "Stop" on /manage-subscription decides how to end coaching from the client's
// subscriptions: a PAID coach is stopped by cancelling the subscription (which
// ends the relationship server-side); an unpaid one by ending the relationship.
//
// `PaymentService.getMySubscriptions` turned a failed read into `[]`, and the
// button read `valueOrNull ?? []`. So whenever the subscriptions read had failed
// — or had not arrived yet — a paid coach looked unpaid: the relationship was
// ended directly, the Stripe subscription was never cancelled, and the client
// was told "Coaching ended" while still being billed for the coach.
//
// The same `[]` drew "You're on the Free plan" for a paying member whenever
// the read failed; the screen's own error branch could never be reached.

const _uid = '00000000-0000-4000-8000-0000000005b5';
const _ended = 'Coaching ended. Your coach has been notified.';
const _failed = 'Could not cancel. Try again.';
const _free = 'You’re on the Free plan. Upgrade any time to unlock more.';

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

/// Answers like PostgREST: the client's subscriptions (or a failure), the
/// relationship update and the coach notification.
class _Server extends http.BaseClient {
  bool subscriptionsFail = false;
  bool paid = true;
  final writes = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (request.method != 'GET') writes.add('${request.method} $path');
    if (path.endsWith('/subscriptions')) {
      if (subscriptionsFail) return _json({'message': 'offline'}, 500, request);
      return _json([
        {'id': 'sub-m', 'kind': 'ai_guided', 'status': 'active'},
        if (paid) {'id': 'sub-c', 'kind': 'coach', 'coach_id': 'coach-a', 'status': 'active'},
      ], 200, request);
    }
    if (path.endsWith('/notifications')) return _json([], 201, request);
    final single =
        request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
    return _json(single ? {'first_name': 'Ana', 'last_name': 'Lee'} : [], 200,
        request);
  }

  http.StreamedResponse _json(Object body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

/// The real service, so the real subscriptions read reaches the server; only
/// the Stripe call is recorded instead of made.
class _Payments extends PaymentService {
  final cancelled = <String>[];
  @override
  Future<bool> cancelSubscription(String subscriptionRowId) async {
    cancelled.add(subscriptionRowId);
    return true;
  }
}

const _coach = {
  'coach_id': 'coach-a',
  'coach': {'first_name': 'Avery', 'last_name': 'Stone'},
};

void main() {
  late _Server server;
  late _Payments payments;

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
      ..subscriptionsFail = false
      ..paid = true
      ..writes.clear();
    payments = _Payments();
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        paymentServiceProvider.overrideWithValue(payments),
        clientPlanProvider.overrideWith((ref) async => ClientPlan.coachGuided),
        myCoachesProvider.overrideWith((ref) async => const [_coach]),
      ],
      child: const MaterialApp(home: ManageSubscriptionScreen()),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> stop(WidgetTester tester) async {
    await open(tester);
    await tester.scrollUntilVisible(find.text('Stop'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes, stop'));
    await tester.pumpAndSettle();
  }

  group('the subscriptions read failed', () {
    testWidgets('Stop does not end a coach it cannot tell is paid', (tester) async {
      server.subscriptionsFail = true;
      await stop(tester);

      expect(server.writes, isNot(contains('PATCH /rest/v1/coach_client_relationships')),
          reason: 'THE defect: a paid coach read as unpaid, so the relationship '
              'was ended directly and the Stripe subscription kept billing');
      expect(find.text(_ended), findsNothing);
      expect(find.text(_failed), findsOneWidget);
    });

    testWidgets('the plan section does not say "Free plan"', (tester) async {
      server.subscriptionsFail = true;
      await open(tester);

      expect(find.text(_free), findsNothing,
          reason: 'a failed read is not "no subscriptions"');
    });
  });

  group('control: the subscriptions read worked', () {
    testWidgets('a paid coach is stopped by cancelling the subscription', (tester) async {
      await stop(tester);

      expect(payments.cancelled, ['sub-c']);
      expect(server.writes, isNot(contains('PATCH /rest/v1/coach_client_relationships')));
      expect(find.text(_ended), findsOneWidget);
    });

    testWidgets('an unpaid coach is stopped by ending the relationship', (tester) async {
      server.paid = false;
      await stop(tester);

      expect(payments.cancelled, isEmpty);
      expect(server.writes, contains('PATCH /rest/v1/coach_client_relationships'));
      expect(find.text(_ended), findsOneWidget);
    });

    testWidgets('a paying member is not told "Free plan"', (tester) async {
      server.paid = false;
      await open(tester);
      expect(find.text(_free), findsNothing);
    });
  });
}
