import 'dart:convert';

import 'package:circle_fitness/features/admin/domain/admin_provider.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/payments/domain/payment_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// The admin surfaces' answers were kept for whoever signed in next.
//
// Every admin read (`admin_provider.dart`) is a non-autoDispose FutureProvider
// over one of three service providers, and none of them depended on who is
// signed in: the server answers each for `auth.uid()` (`admin_can`), so the
// QAX-SES-01 guard, which looks for `auth.currentUser`, cannot see that they are
// per-user. The admin routes are deliberately not role-gated client-side
// (`app_router.dart`: "every surface it reads gates on admin_can server-side").
//
// So the server's gate was never asked again. An admin who signed out from the
// admin dashboard — its logout icon only calls `auth.signOut()` and goes to
// /login, without the reload Settings and Profile do — left the user directory
// (names, emails, roles), the audit and security events and the capability
// flags in memory, and the next account to sign in on that device or tab was
// shown them on /admin-people and /admin-trust.
//
// The three service providers now watch `currentUserProvider`, so every admin
// read is asked again for the account that is signed in.

class _EmptyClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream.value(utf8.encode('[]')),
        200,
        request: request,
        headers: {'content-type': 'application/json'},
      );
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

User _user(String id) => User(
      id: id,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-11-01T00:00:00Z',
    );

final _signedIn = StateProvider<User?>((ref) => null);

ProviderContainer _container() {
  final c = ProviderContainer(overrides: [
    currentUserProvider.overrideWith((ref) => ref.watch(_signedIn)),
  ]);
  addTearDown(c.dispose);
  return c;
}

Future<int> _emissionsAfterUserChange(
    ProviderContainer c, ProviderListenable<AsyncValue<Object?>> provider) async {
  c.read(_signedIn.notifier).state = _user('admin-a');
  var emissions = 0;
  c.listen<AsyncValue<Object?>>(provider, (_, __) => emissions++,
      fireImmediately: true);
  await pumpEventQueue();
  final before = emissions;

  c.read(_signedIn.notifier).state = _user('client-b');
  await pumpEventQueue();
  return emissions - before;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _EmptyClient(),
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryStore(),
      ),
      debug: false,
    );
  });

  test('control: a per-user read that watches the user already re-reads', () async {
    expect(await _emissionsAfterUserChange(_container(), mySubscriptionsProvider),
        greaterThan(0));
  });

  final perAccount = <String, ProviderListenable<AsyncValue<Object?>>>{
    'the user directory (names, emails, roles)': adminUserDirectoryProvider,
    'the audit events': adminAuditEventsProvider,
    'the security events': adminSecurityEventsProvider,
    'the user-edit capability': adminCanUpdateUsersProvider,
    'the legacy platform stats': platformStatsProvider,
  };

  for (final entry in perAccount.entries) {
    test('${entry.key}: a change of account re-asks the server', () async {
      final emitted = await _emissionsAfterUserChange(_container(), entry.value);
      expect(emitted, greaterThan(0),
          reason: "THE defect: the next account would be shown the previous "
              "admin's answer");
    });
  }
}
