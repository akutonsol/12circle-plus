import 'dart:convert';

import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/checkins/data/models/checkin_model.dart';
import 'package:circle_fitness/features/checkins/domain/checkin_provider.dart';
import 'package:circle_fitness/features/habits/domain/habit_provider.dart';
import 'package:circle_fitness/features/notifications/domain/notification_provider.dart';
import 'package:circle_fitness/features/payments/domain/entitlements.dart';
import 'package:circle_fitness/features/payments/domain/payment_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// On mobile, signing out only navigates to /login: the root ProviderScope lives
// on, and anything cached for the session is served to whoever signs in next.
// QAX-SES-01 made providers that read `auth.currentUser` watch the signed-in
// user, and guards that shape. These slipped past it because the user is read
// somewhere it cannot see — inside a notifier's constructor, or by the server
// (`auth.uid()` in an RPC or an edge function):
//
//   * the plan and membership a screen gates paid features on;
//   * a coach's plan tier, Stripe Connect status and balance;
//   * the notification list, the Habits screen, and the check-in a client had
//     open.
//
// So the next account on the device was shown the previous account's tier,
// notifications and habits until the app restarted. The server still enforces
// access; what was wrong is what the screen said.

const _uid = '00000000-0000-4000-8000-0000000010a1';

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

/// See workout_finish_truth's sibling harnesses: the token is read, never verified.
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

class _CountingServer extends http.BaseClient {
  int requests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests++;
    // Habits answer with a failure so the Habits notifier stops before it
    // schedules device reminders, which a unit test cannot host.
    final failed = request.url.path.contains('client_habits');
    return http.StreamedResponse(
      Stream.value(utf8.encode(failed ? '{"message":"no"}' : '[]')),
      failed ? 500 : 200,
      request: request,
      headers: {'content-type': 'application/json'},
    );
  }
}

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

User _user(String id) => User(
      id: id,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-01-01T00:00:00Z',
    );

/// Who is signed in, changeable mid-test, standing in for the auth stream.
final _signedIn = StateProvider<User?>((ref) => _user('account-a'));

void main() {
  late _CountingServer server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = _CountingServer();
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

  ProviderContainer signedInContainer() {
    final c = ProviderContainer(overrides: [
      currentUserProvider.overrideWith((ref) => ref.watch(_signedIn)),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  group('another account signing in reads it again', () {
    final perAccount = <String, ProviderListenable<Object?>>{
      'the client\'s plan (what paid features are gated on)': clientPlanProvider,
      'the platform membership tier': membershipTierProvider,
      'the coach\'s plan tier': coachPlanTierProvider,
      'the coach\'s Stripe Connect status': coachConnectStatusProvider,
      'the coach\'s balance': coachBalanceProvider,
      'the notification list': notificationsProvider,
      'the Habits screen': liveHabitNotifierProvider,
    };

    perAccount.forEach((name, provider) {
      test(name, () async {
        final c = signedInContainer();
        c.listen<Object?>(provider, (_, __) {});
        await _settle();
        final asA = server.requests;

        c.read(_signedIn.notifier).state = _user('account-b');
        await _settle();
        expect(server.requests, greaterThan(asA),
            reason: 'account B must not be shown what was read for account A');
      });
    });
  });

  test('the check-in a client had open is not kept for the next account', () {
    final c = signedInContainer();
    c.listen<Object?>(selectedCheckinProvider, (_, __) {});
    c.read(selectedCheckinProvider.notifier).state = WeeklyCheckin(
      id: 'a-week',
      weekNumber: 46,
      weekStartDate: DateTime(2026, 11, 9),
      status: CheckinStatus.submitted,
      responses: const [],
      overallScore: 0,
    );

    c.read(_signedIn.notifier).state = null;
    expect(c.read(selectedCheckinProvider), isNull,
        reason: 'signing out must not leave account A\'s check-in selected');
  });
}
