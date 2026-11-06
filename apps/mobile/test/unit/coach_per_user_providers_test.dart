import 'dart:convert';

import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// On mobile, logout only navigates to /login: the root ProviderScope lives on, and
// a provider that is not rebuilt on a change of user serves the previous account's
// answer to whoever signs in next. The coach's Programs list and Assign sheet read
// `myProgramsProvider`; the client's Home reads the assigned program, today's
// workout, habits, nutrition plan and scores.
//
// per_user_provider_scope_test.dart guards the providers that read
// `auth.currentUser` in their own body. These do not: they hand the read to a
// service, so that guard cannot see them. This drives the real providers and only
// asks whether a change of user rebuilds them.

class _EmptyClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream.value(utf8.encode('[]')),
        200,
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
    // The auth stream is replaced by a value the test can change.
    currentUserProvider.overrideWith((ref) => ref.watch(_signedIn)),
  ]);
  addTearDown(c.dispose);
  return c;
}

/// How many times [provider] emitted after the user changed from `a` to `b`.
Future<int> _emissionsAfterUserChange(
    ProviderContainer c, ProviderListenable<AsyncValue<Object?>> provider) async {
  c.read(_signedIn.notifier).state = _user('coach-a');
  var emissions = 0;
  c.listen<AsyncValue<Object?>>(provider, (_, __) => emissions++,
      fireImmediately: true);
  await pumpEventQueue();
  final before = emissions;

  c.read(_signedIn.notifier).state = _user('coach-b');
  await pumpEventQueue();
  return emissions - before;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Supabase.initialize(
      // Unroutable, so nothing here can reach a real project.
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

  test('control: a provider that watches the user is rebuilt, one that does not is not',
      () async {
    final watching = FutureProvider<int>((ref) async {
      ref.watch(currentUserProvider);
      return 1;
    });
    final ignoring = FutureProvider<int>((ref) async => 1);
    final c = _container();

    expect(await _emissionsAfterUserChange(c, watching), greaterThan(0));
    expect(await _emissionsAfterUserChange(c, ignoring), 0);
  });

  final perUser = <String, ProviderListenable<AsyncValue<Object?>>>{
    'the coach\'s programs (Programs list, Assign sheet)': myProgramsProvider,
    'the client\'s assigned program': myAssignedProgramProvider,
    'the client\'s workout for today': todaysWorkoutProvider,
    'the client\'s nutrition plan': myNutritionPlanProvider,
    'the client\'s habits': myHabitsProvider,
    'the client\'s habit logs for today': todayHabitLogsProvider,
    'the client\'s score for today': todayScoreProvider,
    'the client\'s scores for the week': weekScoresProvider,
  };

  for (final entry in perUser.entries) {
    test('${entry.key}: a change of user rebuilds it', () async {
      final emitted = await _emissionsAfterUserChange(_container(), entry.value);
      expect(emitted, greaterThan(0),
          reason: 'the next account to sign in would be served the previous '
              'account\'s cached answer');
    });
  }
}
