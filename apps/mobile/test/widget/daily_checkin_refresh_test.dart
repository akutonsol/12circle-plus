import 'dart:convert';

import 'package:circle_fitness/features/checkins/data/models/checkin_model.dart';
import 'package:circle_fitness/features/checkins/domain/checkin_hub.dart';
import 'package:circle_fitness/features/checkins/presentation/checkin_hub_sections.dart';
import 'package:circle_fitness/features/checkins/presentation/daily_checkin_screen.dart';
import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart'
    show todayScoreProvider, weekScoresProvider;
import 'package:circle_fitness/features/coach/domain/coach_provider.dart';
import 'package:circle_fitness/features/scoring/domain/score_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// A submitted check-in is written and awarded, and then nothing re-read either.
// The hub's history is not autoDispose, so the week just submitted was missing
// from it (and the score stayed where it was) until the app restarted.

const _uid = '00000000-0000-4000-8000-00000000c41c';

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

/// See workout_finish_truth_test.dart: the token is read, never verified.
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

class _Backend extends http.BaseClient {
  bool checkinFails = false;
  int checkinWrites = 0;

  /// This week's row as the server holds it; null is no row.
  String? weekStatus;

  http.StreamedResponse _reply(http.BaseRequest request, int status, Object body) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))),
        status,
        request: request,
        headers: {'content-type': 'application/json'},
      );

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path.endsWith('/weekly_checkins') && request.method == 'POST') {
      if (checkinFails) {
        return _reply(request, 500, {'message': 'simulated failure', 'code': 'XX000'});
      }
      checkinWrites++;
      return _reply(request, 201, []);
    }
    if (request.url.path.endsWith('/weekly_checkins') && weekStatus != null) {
      return _reply(request, 200, [
        {'id': 'this-week', 'status': weekStatus},
      ]);
    }
    return _reply(request, 200, []);
  }
}

late _Backend _backend;

void main() {
  setUpAll(() async {
    _backend = _Backend();
    await Supabase.initialize(
      // Unroutable, and every request is answered by the client below.
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _backend,
      authOptions: FlutterAuthClientOptions(
        localStorage: _SeededSession(),
        pkceAsyncStorage: _MemoryStore(),
      ),
      debug: false,
    );
  });

  late Map<String, int> reads;
  late List<Override> overrides;
  late List<ProviderListenable<Object?>> providers;

  void counted<T>(String name, FutureProvider<T> provider, T value) {
    overrides.add(provider.overrideWith((ref) async {
      reads[name] = (reads[name] ?? 0) + 1;
      return value;
    }));
    providers.add(provider);
  }

  setUp(() {
    _backend
      ..checkinFails = false
      ..checkinWrites = 0
      ..weekStatus = null;
    reads = {};
    overrides = [assignedCoachProvider.overrideWith((ref) async => null)];
    providers = [];
    // autoDispose (each visit re-reads it), so not a `FutureProvider`; counted
    // exactly as `counted` would.
    overrides.add(checkinHistoryProvider.overrideWith((ref) async {
      reads['check-in history'] = (reads['check-in history'] ?? 0) + 1;
      return const <WeeklyCheckin>[];
    }));
    providers.add(checkinHistoryProvider);
    counted('today\'s score', todayScoreProvider, const <String, dynamic>{});
    counted('week scores', weekScoresProvider, const <Map<String, dynamic>>[]);
    counted('score', myScoreProvider, null);
    counted('score events', recentScoreEventsProvider, const <Map<String, dynamic>>[]);
  });

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> submit(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(700, 2200));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);
    for (final p in providers) {
      container.listen<Object?>(p, (_, __) {});
    }
    await t.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: DailyCheckinScreen()),
    ));
    await settle(t);
    expect(reads.length, providers.length, reason: 'all are being watched');
  }

  Future<void> tapSubmit(WidgetTester t) async {
    await t.tap(find.text(checkinSubmitLabel(const AsyncData(null))));
    await settle(t);
  }

  testWidgets('after a check-in is saved, its history and the score are read again',
      (t) async {
    await submit(t);
    final before = Map.of(reads);

    await tapSubmit(t);

    expect(_backend.checkinWrites, 1);
    expect(find.text('Weekly Check-In Complete!'), findsOneWidget);
    for (final name in before.keys) {
      expect(reads[name], greaterThan(before[name]!), reason: '$name is stale');
    }
  });

  testWidgets('after a check-in fails, nothing is re-read', (t) async {
    _backend.checkinFails = true;
    await submit(t);
    final before = Map.of(reads);

    await tapSubmit(t);

    expect(find.text('Failed to save. Please try again.'), findsOneWidget);
    expect(reads, before);
  });

  // C3/PD8: a reviewed week is done and is not resubmitted.
  testWidgets('a week the coach has reviewed opens as already checked in', (t) async {
    _backend.weekStatus = 'reviewed';
    await submit(t);

    expect(find.text('Already Checked In!'), findsOneWidget,
        reason: 'a reviewed week reopened the form');
    expect(find.text(checkinSubmitLabel(const AsyncData(null))), findsNothing);
  });

  testWidgets('a review landing while the form is open: the send writes nothing '
      'and says why', (t) async {
    await submit(t);
    _backend.weekStatus = 'reviewed';

    await tapSubmit(t);

    expect(_backend.checkinWrites, 0);
    expect(
        find.text("Your coach has already reviewed this week's check-in — "
            'nothing was changed.'),
        findsOneWidget);
    expect(find.text('Failed to save. Please try again.'), findsNothing,
        reason: 'trying again cannot succeed');
    expect(find.text('Already Checked In!'), findsOneWidget);
  });
}
