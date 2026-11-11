import 'dart:convert';

import 'package:circle_fitness/core/realtime/realtime.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/dashboard/presentation/coach_dashboard_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// Three of the coach dashboard's reads were kept for whoever signed in next.
//
// On mobile, signing out only navigates to /login: the root ProviderScope
// lives on, and a FutureProvider is re-read for the next account only if it
// watches the signed-in user (QAX-SES-01). These three read the coach through
// `auth.currentUser` / `auth.uid()` and did not watch it:
//
//   * `coachAiSignalsProvider` — the "AI Coach signals" card: the previous
//     coach's clients by name, with their churn and injury risk. It is not in
//     the screen's first-frame refresh either, so coach B was shown coach A's
//     flagged clients until some relationship row happened to change;
//   * `clientCheckinsProvider` and `clientWorkoutLogsProvider` — this week's
//     check-ins and workouts. The screen re-reads these after its first frame,
//     but the previous coach's rows were drawn until that read returned.
//
// The harness is coach_per_user_providers_test's: the auth stream is replaced
// by a value the test changes, and emissions are counted.

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
    // No realtime socket in a unit test; one tick, as on subscribe.
    tableTickerProvider.overrideWith((ref, table) => Stream.value(0)),
  ]);
  addTearDown(c.dispose);
  return c;
}

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

  test('control: the roster already follows the signed-in coach', () async {
    expect(await _emissionsAfterUserChange(_container(), coachClientsProvider),
        greaterThan(0));
  });

  final perCoach = <String, ProviderListenable<AsyncValue<Object?>>>{
    "the AI Coach signals card (clients' churn and injury risk)":
        coachAiSignalsProvider,
    "this week's check-ins (Check-Ins tab, summary strip)":
        clientCheckinsProvider,
    "this week's workouts (Workouts tab, summary strip)":
        clientWorkoutLogsProvider,
  };

  for (final entry in perCoach.entries) {
    test('${entry.key}: a change of coach re-reads it', () async {
      final emitted =
          await _emissionsAfterUserChange(_container(), entry.value);
      expect(emitted, greaterThan(0),
          reason: "the next coach to sign in would be shown the previous "
              "coach's answer");
    });
  }
}
