import 'package:circle_fitness/features/scoring/domain/score_provider.dart';
import 'package:circle_fitness/features/scoring/presentation/score_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// A score read that failed (or had not finished) was shown as data:
//   * My Score: "0 points", Level 1, Bronze;
//   * the Badges stat: 0;
//   * Leaderboard: "No scores this month yet — be the first on the board!".
// Error contract: a failed read is never shown as data. They now say the read
// failed and offer Try again; a member with no score row yet still sees zeros.
//
// HOW TO SEE IT FAIL: on main the failed reads render as zeros / an empty board.

class _MemoryStore extends GotrueAsyncStorage {
  final Map<String, String> _m = {};
  @override
  Future<String?> getItem({required String key}) async => _m[key];
  @override
  Future<void> setItem({required String key, required String value}) async => _m[key] = value;
  @override
  Future<void> removeItem({required String key}) async => _m.remove(key);
}

Widget _screen(List<Override> overrides) => ProviderScope(
      overrides: [
        recentScoreEventsProvider.overrideWith((ref) async => const []),
        allBadgesProvider.overrideWith((ref) async => const []),
        ...overrides,
      ],
      child: const MaterialApp(home: ScoreScreen()),
    );

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryStore(),
        detectSessionInUri: false,
      ),
      debug: false,
    );
  });

  testWidgets('a failed score read is said, not shown as zero', (t) async {
    await t.pumpWidget(_screen([
      myScoreProvider.overrideWith((ref) async => throw Exception('offline')),
      myBadgeIdsProvider.overrideWith((ref) async => throw Exception('offline')),
      globalLeaderboardProvider.overrideWith((ref) async => throw Exception('offline')),
    ]));
    await _settle(t);
    expect(find.text("Couldn't load your score."), findsOneWidget,
        reason: 'THE defect: a failed read read "0 points, Level 1, Bronze"');
    await t.tap(find.text('Leaderboard'));
    await _settle(t);
    expect(find.textContaining('be the first on the board'), findsNothing,
        reason: 'a failed read is not an empty leaderboard');
    expect(find.text("Couldn't load the leaderboard."), findsOneWidget);
  });

  testWidgets('a member with no score yet sees real zeros (positive control)', (t) async {
    await t.pumpWidget(_screen([
      myScoreProvider.overrideWith((ref) async => null),
      myBadgeIdsProvider.overrideWith((ref) async => <String>{}),
      globalLeaderboardProvider.overrideWith((ref) async => const []),
    ]));
    await _settle(t);
    expect(find.text("Couldn't load your score."), findsNothing);
    await t.tap(find.text('Leaderboard'));
    await _settle(t);
    expect(find.textContaining('be the first on the board'), findsOneWidget);
  });
}
