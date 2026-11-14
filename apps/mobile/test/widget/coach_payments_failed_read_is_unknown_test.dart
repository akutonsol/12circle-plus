import 'dart:convert';

import 'package:circle_fitness/features/payments/data/coach_revenue_service.dart';
import 'package:circle_fitness/features/payments/data/payment_service.dart';
import 'package:circle_fitness/features/payments/domain/payment_provider.dart';
import 'package:circle_fitness/features/payments/presentation/coach_payments_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// A coach's money figures were invented when they could not be read (EC-14).
//
// `connectBalance()` answered {pending: 0, available: 0} for any failure,
// `connectStripeStatus()` answered {connected: false, …}, and
// `CoachRevenueService.getMetrics()` answered every figure as 0. On a bad
// connection a coach with money in Stripe read "$0" pending and lifetime
// revenue as fact, and a connected coach was told "Not connected" and offered
// onboarding again. EC-14 (docs/QA_WORKSTREAM_B_ERROR_CONTRACT_REPORT.md):
// "Financial figures are never defaulted… Connect status is tri-state:
// connected / not connected / unknown."

const _uid = '00000000-0000-4000-8000-0000000000d1';

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

/// Every request fails with a 500 (a 503 would be retried with a timer).
class _Down extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode({'message': 'upstream down'}))), 500,
          request: request, headers: {'content-type': 'application/json'});
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _Down(),
      authOptions: FlutterAuthClientOptions(
        localStorage: _SeededSession(),
        pkceAsyncStorage: _MemoryStore(),
        detectSessionInUri: false,
      ),
      debug: false,
    );
  });

  test('a balance that could not be read is not a zero balance', () async {
    await expectLater(PaymentService().connectBalance(), throwsA(anything),
        reason: 'THE defect: it answered {pending: 0, available: 0}');
  });

  test('a Connect status that could not be read is not "not connected"', () async {
    await expectLater(PaymentService().connectStripeStatus(), throwsA(anything),
        reason: 'THE defect: it answered connected: false');
  });

  test('revenue that could not be read is not zero', () async {
    await expectLater(CoachRevenueService().getMetrics(), throwsA(anything),
        reason: 'THE defect: every figure came back 0');
  });

  testWidgets('the Payments screen shows unread figures as unknown, never zero',
      (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 3000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        coachConnectStatusProvider.overrideWith((ref) async =>
            {'connected': true, 'charges_enabled': true, 'payouts_enabled': true}),
        coachRevenueProvider.overrideWith((ref) async => throw StateError('down')),
        coachBalanceProvider.overrideWith((ref) async => throw StateError('down')),
      ],
      child: const MaterialApp(home: CoachPaymentsScreen()),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text(r'$0'), findsNothing,
        reason: 'a read that failed was shown as a confident zero');
    expect(find.text('—'), findsWidgets);
  });
}
