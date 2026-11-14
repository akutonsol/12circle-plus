import 'dart:convert';

import 'package:circle_fitness/features/workout/data/workout_service.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:circle_fitness/features/workout/presentation/active_workout_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// A circuit's round counter could never leave "Round 1".
//
// The round was a local declared INSIDE the circuit's StatefulBuilder builder:
//   return StatefulBuilder(builder: (ctx, setSB) {
//     int currentRound = 1;
// The +/- taps called setSB(() => currentRound++), which re-runs that builder --
// and the first thing it does is set the round back to 1. A client doing a
// 3-round circuit could not track their rounds.
//
// HOW TO SEE IT FAIL: on main the tap leaves "Round 1" on screen.

class _EmptyClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(Stream.value(utf8.encode('[]')), 200,
          headers: {'content-type': 'application/json'});
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

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
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

  Finder roundPlus(String label) => find.descendant(
        of: find.ancestor(of: find.text(label), matching: find.byType(Row)).first,
        matching: find.byIcon(Icons.add_rounded),
      );

  testWidgets('the circuit round counter advances, and stops at the last round',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final circuit = WorkoutService()
        .getSampleWorkouts()
        .firstWhere((w) => w.exercises.any((e) => e.isCircuit));
    final rounds = circuit.exercises.firstWhere((e) => e.isCircuit).circuitRounds;
    expect(rounds, greaterThanOrEqualTo(2), reason: 'fixture: a multi-round circuit');

    await tester.pumpWidget(ProviderScope(
      overrides: [selectedWorkoutProvider.overrideWith((ref) => circuit)],
      child: const MaterialApp(home: ActiveWorkoutScreen()),
    ));
    await _settle(tester);

    await tester.ensureVisible(find.text('Round 1'));
    await tester.tap(roundPlus('Round 1'));
    await tester.pump();
    expect(find.text('Round 2'), findsOneWidget,
        reason: 'THE defect: the rebuild reset the round to 1');

    for (var r = 2; r < rounds; r++) {
      await tester.tap(roundPlus('Round $r'));
      await tester.pump();
    }
    expect(find.text('Round $rounds'), findsOneWidget);
    await tester.tap(roundPlus('Round $rounds'));
    await tester.pump();
    expect(find.text('Round $rounds'), findsOneWidget,
        reason: 'the counter stops at the circuit\'s last round');
  });
}
