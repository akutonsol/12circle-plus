import 'dart:convert';

import 'package:circle_fitness/features/challenges/data/live_challenge_service.dart';
import 'package:circle_fitness/features/challenges/data/models/challenge_model.dart';
import 'package:circle_fitness/features/challenges/domain/challenge_provider.dart';
import 'package:circle_fitness/features/challenges/presentation/challenge_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// "Join Challenge" on the detail screen reported success when the join failed.
//
// It called `joinChallenge` without awaiting it, played the success haptic and
// popped the screen. `joinChallenge` returns false on failure, and the
// challenge card already says "Unable to join — please try again." for it; the
// detail screen ignored it, so the user left believing they had joined.

class _Join extends LiveChallengeService {
  _Join(this.fails);
  final bool fails;
  @override
  Future<void> joinChallenge(String challengeId) async {
    if (fails) throw const PostgrestException(message: 'offline', code: '500');
  }
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

class _Offline extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(Stream.value(utf8.encode('[]')), 200,
          request: request, headers: {'content-type': 'application/json'});
}

final _challenge = Challenge(
  id: 'ch-1', title: 'Ten K Steps', description: 'Walk', type: ChallengeType.steps,
  status: ChallengeStatus.active, startDate: DateTime(2026, 11, 1),
  endDate: DateTime(2026, 12, 1), targetValue: 10000, unit: 'steps', myProgress: 0,
  participantCount: 3, leaderboard: const [], rewards: const [], badges: const [],
  isJoined: false, coachName: 'Coach', emoji: '👟');

Future<void> _open(WidgetTester tester, {required bool fails}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(900, 3000);
  addTearDown(tester.view.reset);
  final router = GoRouter(initialLocation: '/', routes: [
    GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('Challenges list')),
        routes: [GoRoute(path: 'detail', builder: (_, __) => const ChallengeDetailScreen())]),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      selectedChallengeProvider.overrideWith((ref) => _challenge),
      challengeNotifierProvider.overrideWith((ref) => ChallengeNotifier([_challenge], _Join(fails))),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  router.push('/detail');
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.tap(find.text('Join Challenge'));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _Offline(),
      authOptions: FlutterAuthClientOptions(
          localStorage: const EmptyLocalStorage(),
          pkceAsyncStorage: _MemoryStore(),
          detectSessionInUri: false),
      debug: false,
    );
  });

  testWidgets('a join that failed says so and stays on the challenge', (tester) async {
    await _open(tester, fails: true);
    expect(find.text('Unable to join — please try again.'), findsOneWidget,
        reason: 'THE defect: nothing was said');
    expect(find.text('Join Challenge'), findsOneWidget,
        reason: 'the screen closed as if the join had worked');
  });

  testWidgets('control: a join that worked closes the screen', (tester) async {
    await _open(tester, fails: false);
    expect(find.text('Challenges list'), findsOneWidget);
    expect(find.text('Unable to join — please try again.'), findsNothing);
  });
}
