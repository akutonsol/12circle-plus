import 'dart:convert';

import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart';
import 'package:circle_fitness/features/coach/domain/package_provider.dart';
import 'package:circle_fitness/features/dashboard/presentation/client_detail_screen.dart';
import 'package:circle_fitness/features/scoring/domain/score_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// The coach's Progress tab lists RECENT SESSIONS from `clientDetailProvider`'s
// `workout_logs`. That key is a `workout_sessions` read, which selects
// `workout_title`, `completed_at` and `duration_seconds`. The row read
// `workout_name`, `program_name` and `duration_minutes`, none of which that query
// returns, so every session showed as "Workout" with no duration.
//
// This hands the page rows shaped exactly as the provider returns them and reads
// what the coach sees. Only the providers are substituted.

const _clientId = 'client-1';

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

/// Client detail runs repeating animations, so `pumpAndSettle` would not return.
Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// A completed `workout_sessions` row, as `clientDetailProvider` selects it.
Map<String, dynamic> _session(String title, String completedAt, Object? seconds) => {
      'user_id': _clientId,
      'workout_title': title,
      'completed_at': completedAt,
      'duration_seconds': seconds,
    };

Future<void> _openProgressTab(
    WidgetTester t, List<Map<String, dynamic>> sessions) async {
  t.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(1200, 4000);
  addTearDown(t.view.reset);

  final router = GoRouter(
    initialLocation: '/client',
    routes: [
      GoRoute(
        path: '/client',
        builder: (_, __) =>
            const ClientDetailScreen(clientId: _clientId, clientName: 'Jordan'),
      ),
    ],
  );
  addTearDown(router.dispose);

  await t.pumpWidget(ProviderScope(
    overrides: [
      clientDetailProvider(_clientId).overrideWith((ref) async => {
            'id': _clientId,
            'first_name': 'Jordan',
            'last_name': 'Test',
            'role': 'client',
            'workout_logs': sessions,
          }),
      clientHasPaidPlanProvider(_clientId).overrideWith((ref) async => true),
      clientScheduleProvider(_clientId).overrideWith((ref) async => null),
      clientScoreProvider(_clientId).overrideWith((ref) async => null),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await _settle(t);
  await t.tap(find.text('Progress'));
  await _settle(t);
}

void main() {
  setUpAll(() async {
    await Supabase.initialize(
      // Unroutable, so the page's other reads cannot touch QA.
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

  testWidgets('a session shows its real title and its recorded duration',
      (t) async {
    await _openProgressTab(t, [
      _session('Upper Body Push', '2026-11-04T19:56:12+00:00', 2700),
      _session('Leg Day', '2026-11-03T13:35:00+00:00', 1830),
    ]);

    expect(find.text('RECENT SESSIONS'), findsOneWidget);
    expect(find.text('Upper Body Push'), findsOneWidget);
    expect(find.text('Leg Day'), findsOneWidget);
    expect(find.text('45m'), findsOneWidget, reason: '2700 seconds');
    expect(find.text('31m'), findsOneWidget, reason: '1830 seconds, rounded');
  });

  testWidgets('a session with no recorded duration shows none, not "0m"',
      (t) async {
    await _openProgressTab(t, [
      _session('Mobility Flow', '2026-11-04T09:00:00+00:00', null),
      _session('Quick Core', '2026-11-03T09:00:00+00:00', 0),
    ]);

    expect(find.text('Mobility Flow'), findsOneWidget);
    expect(find.text('Quick Core'), findsOneWidget);
    expect(find.text('0m'), findsNothing,
        reason: 'a row must not state a length nobody measured');
  });

  // D7 · "Current Streak" counted back from the client's latest workout and
  // never compared it with today: three days in a row a month ago read "3d".
  group('D7 Current Streak is a run that is still going', () {
    // A completed_at for local noon `daysAgo` days back (or a given hour), as
    // the database returns it: a UTC instant.
    String at(int daysAgo, {int hour = 12, int minute = 0}) {
      final n = DateTime.now();
      return DateTime(n.year, n.month, n.day - daysAgo, hour, minute)
          .toUtc()
          .toIso8601String();
    }

    testWidgets('a run that ended a month ago is not a current streak',
        (t) async {
      await _openProgressTab(t, [
        _session('Leg Day', at(30), 1800),
        _session('Push', at(31), 1800),
        _session('Pull', at(32), 1800),
      ]);
      expect(find.text('3d'), findsNothing,
          reason: 'the run stopped 30 days ago');
      expect(find.text('0d'), findsOneWidget);
    });

    testWidgets('a run through today counts every day of it', (t) async {
      await _openProgressTab(t, [
        _session('Leg Day', at(0), 1800),
        _session('Push', at(1), 1800),
        _session('Pull', at(2), 1800),
        _session('Old', at(9), 1800),
      ]);
      expect(find.text('3d'), findsOneWidget);
    });

    testWidgets('not having trained yet today does not break the run',
        (t) async {
      await _openProgressTab(t, [
        _session('Push', at(1), 1800),
        _session('Pull', at(2), 1800),
      ]);
      expect(find.text('2d'), findsOneWidget);
    });

    testWidgets('a run that stopped the day before yesterday is over',
        (t) async {
      await _openProgressTab(t, [
        _session('Push', at(2), 1800),
        _session('Pull', at(3), 1800),
      ]);
      expect(find.text('0d'), findsOneWidget);
    });

    testWidgets('a late-evening workout counts on its local day', (t) async {
      // West of UTC this instant falls on TOMORROW's UTC date; a comparison of
      // that date with today would drop it. In a UTC zone (CI) it is simply
      // today, so this guards the conversion where it can and costs nothing
      // where it cannot.
      await _openProgressTab(t, [
        _session('Late', at(0, hour: 23, minute: 30), 1800),
        _session('Push', at(1, hour: 23, minute: 30), 1800),
      ]);
      expect(find.text('2d'), findsOneWidget);
    });
  });
}
