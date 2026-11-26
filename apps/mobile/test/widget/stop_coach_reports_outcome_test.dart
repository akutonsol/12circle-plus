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

import '../support/pump_until.dart';

// "Stop" on /manage-subscription said "Coaching ended. Your coach has been
// notified." whatever happened.
//
//   * A PAID coach is stopped by cancelling the subscription. That call
//     returns false on failure, and the result was ignored: a client whose
//     cancellation failed was told coaching had ended, and was still billed.
//   * An unpaid coach is stopped by `cancelCoach`, which threw on any failure
//     — including a failed NOTIFICATION after the relationship had already
//     ended (N3's shape). The exception escaped the button: no message, no
//     refresh, and the client could not tell whether it had worked.
//
// The membership cancel on the same screen already reports its outcome
// ("Could not cancel. Try again."); this follows it.

const _uid = '00000000-0000-4000-8000-00000000057c';
const _ended = 'Coaching ended. Your coach has been notified.';
const _failed = 'Could not end coaching. Nothing was changed. Try again.';
/// cancelCoach's own StateError for a 0-row update, shown verbatim.
const _noActive = 'No active coaching with this coach — nothing was changed.';
/// Owner decision 2: a paid coach continues to the end of the paid period.
const _continues = 'continues until';

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

/// Answers like PostgREST. The relationship update and the notification
/// insert each succeed or fail on request.
class _Server extends http.BaseClient {
  bool relationshipFails = false;
  bool relationshipMatches = true;
  bool notificationFails = false;
  bool paid = false;
  bool cancelFails = false;
  final writes = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (request.method != 'GET') writes.add('${request.method} $path');
    if (path.endsWith('/subscriptions') && request.method == 'GET') {
      return _json(_filtered([
        if (paid) {'id': 'sub-1', 'user_id': _uid, 'kind': 'coach', 'coach_id': 'coach-a', 'status': 'active',
                    'current_period_end': '2026-12-01T00:00:00Z'},
      ], request.url.queryParameters), 200, request);
    }
    if (path.endsWith('/functions/v1/cancel-subscription')) {
      return cancelFails
          ? _json({'error': 'stripe_cancel_failed'}, 502, request)
          : _json({'ok': true, 'endsAt': '2026-12-01T00:00:00Z'}, 200, request);
    }
    if (request.method == 'PATCH' && path.endsWith('/coach_client_relationships')) {
      // cancelCoach checks the update matched a row (P0-FL-1).
      return relationshipFails
          // As PostgREST fails (P0-FL-60a r4): PGRST000, no database
          // connection, so nothing was written. A codeless 503 is a gateway's
          // and is "couldn't confirm" (payment_failures_recorded_and_owned_test).
          ? _json({'message': 'offline', 'code': 'PGRST000'}, 503, request)
          : _json(relationshipMatches ? [{'id': 'rel-a'}] : [], 200, request);
    }
    if (path.endsWith('/notifications')) {
      return notificationFails
          ? _json({'message': 'notification insert failed'}, 500, request)
          : _json([], 201, request);
    }
    final single =
        request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
    return _json(single ? {'first_name': 'Ana', 'last_name': 'Lee'} : [], 200,
        request);
  }

  http.StreamedResponse _json(Object body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

class _Payments extends PaymentService {
  bool cancels = true;
  @override
  Future<bool> cancelSubscription(String subscriptionRowId) async => cancels;
}

const _coach = {
  'coach_id': 'coach-a',
  'coach': {'first_name': 'Avery', 'last_name': 'Stone'},
};

const _paidSub = {
  'id': 'sub-1',
  'kind': 'coach',
  'coach_id': 'coach-a',
  'status': 'active',
};

/// PostgREST's `eq.` / `in.(…)` filters, applied to a list of rows.
List<Map<String, Object?>> _filtered(List<Map<String, Object?>> rows, Map<String, String> q) =>
    rows.where((r) => q.entries.every((e) {
          final v = e.value;
          if (v.startsWith('eq.')) return '${r[e.key]}' == v.substring(3);
          if (v.startsWith('in.(') && v.endsWith(')')) {
            return v.substring(4, v.length - 1).split(',')
                .map((x) => x.replaceAll('"', '')).contains('${r[e.key]}');
          }
          return true;
        })).toList();

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
        detectSessionInUri: false,
      ),
      debug: false,
    );
  });

  setUp(() {
    server
      ..relationshipFails = false
      ..relationshipMatches = true
      ..notificationFails = false
      ..paid = false
      ..cancelFails = false
      ..writes.clear();
    payments = _Payments();
  });

  Future<void> stop(WidgetTester tester, {required bool paid}) async {
    server.paid = paid;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        paymentServiceProvider.overrideWithValue(payments),
        clientPlanProvider.overrideWith((ref) async => ClientPlan.free),
        mySubscriptionsProvider
            .overrideWith((ref) async => paid ? const [_paidSub] : const []),
        myCoachesProvider.overrideWith((ref) async => const [_coach]),
      ],
      child: const MaterialApp(home: ManageSubscriptionScreen()),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Stop'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes, stop'));
    // Ending a PAID coach now goes through the cancel-subscription function.
    // The functions client encodes/decodes in an isolate, which does not run
    // under the widget test's fake clock. A fixed budget of real-time waits
    // raced it under load (P0-FL-51): wait for the SnackBar every outcome
    // (ended, continues until, could not end) is reported in, then settle.
    await pumpUntil(tester, () => find.byType(SnackBar).evaluate().isNotEmpty,
        what: 'the Stop outcome (a SnackBar)');
    await tester.pumpAndSettle();
  }

  group('a paid coach', () {
    testWidgets('a failed cancellation is not "Coaching ended"', (tester) async {
      server.cancelFails = true; // cancel-subscription answers 502
      await stop(tester, paid: true);

      expect(find.text(_ended), findsNothing,
          reason: 'the subscription is still active, and still billed');
      expect(find.text(_failed), findsOneWidget);
    });

    testWidgets('a cancellation that worked says so', (tester) async {
      await stop(tester, paid: true);
      // Owner decision 2: it says WHEN coaching ends -- the end of the paid
      // period -- and the relationship is not ended now.
      expect(find.textContaining(_continues), findsOneWidget);
      expect(server.writes, isNot(contains('PATCH /rest/v1/coach_client_relationships')));
    });
  });

  group('an unpaid coach', () {
    testWidgets('a failed notification does not undo "ended"', (tester) async {
      // The relationship IS ended; only the notice to the coach failed.
      server.notificationFails = true;
      await stop(tester, paid: false);

      expect(server.writes, contains('PATCH /rest/v1/coach_client_relationships'));
      expect(find.text(_ended), findsOneWidget);
    });

    testWidgets('a failed update says it failed', (tester) async {
      server.relationshipFails = true;
      await stop(tester, paid: false);

      expect(find.text(_ended), findsNothing);
      // Not a StateError (a 503): the generic text.
      expect(find.text(_failed), findsOneWidget);
      expect(find.text(_noActive), findsNothing);
    });

    testWidgets('an update that matched no row says nothing was changed', (tester) async {
      // RLS refusal / already ended: PostgREST answers 200 with no rows.
      server.relationshipMatches = false;
      await stop(tester, paid: false);

      expect(find.text(_ended), findsNothing);
      // F2: the specific reason, not the generic text that discarded it.
      expect(find.text(_noActive), findsOneWidget);
      expect(find.text(_failed), findsNothing);
      expect(server.writes, isNot(contains('POST /rest/v1/notifications')),
          reason: 'the coach must not be told a client ended coaching');
    });

    testWidgets('an update that worked says so', (tester) async {
      await stop(tester, paid: false);
      expect(find.text(_ended), findsOneWidget);
    });
  });
}
