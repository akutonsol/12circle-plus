import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/coach/data/coach_program_service.dart';
import 'package:circle_fitness/features/coach/presentation/coach_copilot_screen.dart';
import 'package:circle_fitness/features/dashboard/presentation/coach_dashboard_screen.dart'
    show coachClientsProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// P0-FL-43 — the copilot's engine calls report failures honestly.
//
// 1. `CoachProgramService.predictClient` swallowed every failure into `null`
//    — the same value as a genuine "no outlook" — so a failed prediction
//    showed NO outlook card and nothing said it had failed. It now records the
//    failure and rethrows; the copilot shows "Couldn't load this client's
//    outlook — <next step>" with a busy-aware Try again. A genuine null answer
//    still shows nothing (as before).
// 2. A failed `generate_workout` showed "Couldn't generate a recommendation —
//    try again." with nothing recorded and no network/other next step. The
//    service's `lastError` is now reported (origin
//    `CoachCopilotScreen.generate`) and the copy follows `isNetworkFailure`.
//
// HOW TO SEE IT FAIL: `git checkout df35d5f -- lib/features/coach/data/
// coach_program_service.dart lib/features/coach/presentation/
// coach_copilot_screen.dart`, run this file, then `git checkout HEAD -- …`.
// Every test except the genuine-null guard fails.
//
// The harness mirrors coach_copilot_health_context_test.dart (private there).

const _uid = '00000000-0000-4000-8000-0000000c0f43';
const _clientId = '00000000-0000-4000-8000-00000000cf43';
const _clientB = '00000000-0000-4000-8000-00000000cb43';

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

String _jwt() {
  final exp =
      DateTime.now().add(const Duration(days: 3650)).millisecondsSinceEpoch ~/
          1000;
  return '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${_b64({
        'sub': _uid,
        'role': 'authenticated',
        'exp': exp,
        'aud': 'authenticated'
      })}.'
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

/// How an engine RPC answers.
enum _Ans { ok, nullBody, http500, network }

class _Server extends http.BaseClient {
  _Ans predict = _Ans.nullBody;
  _Ans generate = _Ans.ok;
  Completer<void>? holdPredict;
  final holdPredictFor = <String, Completer<void>>{};
  final predictFor = <String, _Ans>{};
  final predictBodies = <String>[];
  final generateBodies = <String>[];

  void reset() {
    predict = _Ans.nullBody;
    generate = _Ans.ok;
    holdPredict = null;
    holdPredictFor.clear();
    predictFor.clear();
    predictBodies.clear();
    generateBodies.clear();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final body = request is http.Request ? request.body : '';
    if (path.endsWith('/rpc/get_client_assessment')) {
      return _json(request, 200, [
        {
          'client_id': _clientId, 'has_assessment': true,
          'fitness_goal': 'lose_fat', 'experience_level': 'Beginner',
          'training_location': 'home', 'has_injuries': false,
          'injury_locations': '',
        },
      ]);
    }
    if (path.endsWith('/rpc/predict_client') ||
        path.endsWith('/rpc/record_prediction')) {
      predictBodies.add(body);
      final subject = (jsonDecode(body) as Map)['p_subject'] as String?;
      final h = holdPredictFor[subject] ?? holdPredict;
      if (h != null) await h.future;
      return _answer(request, predictFor[subject] ?? predict, {
        'status': 'ok', 'weeks_completed': 2, 'duration_weeks': 8,
        'goal': {'progress_pct': 25, 'confidence': 90},
        'plateau_risk': 'low', 'injury_risk': {'general': 'low'},
        'recovery': {'trend': 'stable'}, 'alerts': [],
      });
    }
    if (path.endsWith('/rpc/generate_workout')) {
      generateBodies.add(body);
      return _answer(request, generate, {
        'selected': [
          {'name': 'Goblet squat', 'score': 80, 'pattern': 'squat'},
        ],
        'trace': [],
      });
    }
    return _json(request, 200, []);
  }

  http.StreamedResponse _answer(
      http.BaseRequest request, _Ans a, Map<String, Object?> ok) {
    switch (a) {
      case _Ans.ok:
        return _json(request, 200, ok);
      case _Ans.nullBody:
        return _json(request, 200, null);
      case _Ans.http500:
        return _json(request, 500,
            {'code': 'XX000', 'message': 'boom', 'details': null, 'hint': null});
      case _Ans.network:
        throw http.ClientException('Connection refused', request.url);
    }
  }

  http.StreamedResponse _json(
          http.BaseRequest request, int status, Object? body) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: request, headers: {'content-type': 'application/json'});
}

Future<void> _io(WidgetTester t) async {
  for (var i = 0; i < 3; i++) {
    await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pump();
  }
}

Future<void> _pumpAndSelect(WidgetTester t) async {
  t.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(800, 2400);
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      currentUserProfileProvider
          .overrideWith((ref) async => {'id': _uid, 'role': 'coach'}),
      coachClientsProvider.overrideWith((ref) async => [
            {'id': _clientId, 'first_name': 'Jordan', 'last_name': 'Test'},
            {'id': _clientB, 'first_name': 'Sam', 'last_name': 'Other'},
          ]),
    ],
    child: const MaterialApp(home: CoachCopilotScreen()),
  ));
  await _io(t);
  await t.tap(find.text('Jordan Test'));
  await _io(t);
}

bool _inLiveRegion(Finder text) => find
    .ancestor(
        of: text,
        matching: find.byWidgetPredicate((w) =>
            w is Semantics && w.properties.liveRegion == true && w.container))
    .evaluate()
    .isNotEmpty;

const _other = 'try again in a moment. If it keeps happening, contact support.';
const _network = 'check your connection, then try again.';
const _outlookOther = "Couldn't load this client's outlook — $_other";
const _outlookNetwork = "Couldn't load this client's outlook — $_network";
const _genOther = "Couldn't generate a recommendation — $_other";
const _genNetwork = "Couldn't generate a recommendation — $_network";
const _retryLabel = "Try again, load this client's outlook";

void main() {
  final server = _Server();
  final reported = <String>[];

  setUpAll(() async {
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: server,
      authOptions: FlutterAuthClientOptions(
        localStorage: _SeededSession(),
        pkceAsyncStorage: _MemoryStore(),
        detectSessionInUri: false,
      ),
      debug: false,
    );
  });

  setUp(() {
    server.reset();
    reported.clear();
    setFailureSink((f) => reported.add(f.origin));
  });
  tearDown(resetFailureSink);

  // ── 1. predictClient ────────────────────────────────────────────────────

  group('CoachProgramService.predictClient', () {
    test('a failed call is recorded and rethrown — never returned as null',
        () async {
      server.predict = _Ans.http500;
      await expectLater(CoachProgramService().predictClient(_clientId),
          throwsA(isA<PostgrestException>()));
      expect(reported, ['CoachProgramService.predictClient']);
    });

    test('a genuine null answer stays null and records nothing', () async {
      server.predict = _Ans.nullBody;
      expect(await CoachProgramService().predictClient(_clientId), isNull);
      expect(reported, isEmpty);
    });

    test('recordPrediction: a failed call is recorded and rethrown', () async {
      // No caller today (git grep); same contract as predictClient.
      server.predict = _Ans.network;
      await expectLater(CoachProgramService().recordPrediction(_clientId),
          throwsA(isA<http.ClientException>()));
      expect(reported, ['CoachProgramService.recordPrediction']);
    });
  });

  testWidgets(
      'a FAILED outlook (500) shows the failure in a live region with the '
      'other next step, records it, shows no raw error; Try again recovers',
      (t) async {
    final handle = t.ensureSemantics();
    server.predict = _Ans.http500;
    await _pumpAndSelect(t);
    expect(find.text(_outlookOther), findsOneWidget,
        reason: 'a failed prediction is not "no outlook"');
    expect(_inLiveRegion(find.text(_outlookOther)), isTrue);
    expect(find.textContaining('connection'), findsNothing,
        reason: 'a server answer is not a connection problem');
    expect(find.textContaining('boom'), findsNothing, reason: 'no raw error');
    expect(find.text('CLIENT OUTLOOK'), findsNothing);
    expect(reported, contains('CoachProgramService.predictClient'));

    final retry = find.widgetWithText(TextButton, 'Try again');
    expect(retry, findsOneWidget);
    expect(t.getSize(retry).height, greaterThanOrEqualTo(44));
    expect(find.bySemanticsLabel(_retryLabel), findsOneWidget);

    // Busy-aware: while the retry is in flight a second tap sends nothing.
    final sent = server.predictBodies.length;
    server
      ..predict = _Ans.ok
      ..holdPredict = Completer<void>();
    await t.tap(retry);
    await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pump();
    expect(server.predictBodies.length, sent + 1);
    final busyRetry = find.widgetWithText(TextButton, 'Trying again…');
    expect(busyRetry, findsOneWidget);
    expect(t.widget<TextButton>(busyRetry).onPressed, isNull,
        reason: 'no double fire while the retry runs');
    await t.tap(busyRetry, warnIfMissed: false);
    await t.pump();
    expect(server.predictBodies.length, sent + 1, reason: 'one retry request');

    server.holdPredict!.complete();
    await _io(t);
    expect(find.text('CLIENT OUTLOOK'), findsOneWidget,
        reason: 'the retry that answers shows the outlook');
    expect(find.text(_outlookOther), findsNothing);
    handle.dispose();
  });

  testWidgets('a NETWORK outlook failure says check your connection',
      (t) async {
    server.predict = _Ans.network;
    await _pumpAndSelect(t);
    expect(find.text(_outlookNetwork), findsOneWidget);
    expect(_inLiveRegion(find.text(_outlookNetwork)), isTrue);
    expect(reported, contains('CoachProgramService.predictClient'));
  });

  testWidgets('a genuine null outlook shows no card and no notice (as before)',
      (t) async {
    server.predict = _Ans.nullBody;
    await _pumpAndSelect(t);
    expect(server.predictBodies, hasLength(1));
    expect(find.text('CLIENT OUTLOOK'), findsNothing);
    expect(find.textContaining("Couldn't load this client's outlook"),
        findsNothing);
    expect(reported, isEmpty);
  });

  testWidgets(
      "a failed outlook for the previous client is not shown for the new one",
      (t) async {
    // Jordan's prediction fails, but only after the coach has moved on.
    final held = Completer<void>();
    server.predictFor[_clientId] = _Ans.http500;
    server.holdPredictFor[_clientId] = held;
    await _pumpAndSelect(t);
    await t.tap(find.text('Sam Other'));
    await _io(t);
    held.complete();
    await _io(t);
    expect(find.textContaining("Couldn't load this client's outlook"),
        findsNothing, reason: "Jordan's failure must not show under Sam");
    expect(find.text('Generate recommendation'), findsOneWidget);

    // Positive control: the same failure shows when the selection holds.
    server.holdPredictFor.remove(_clientId);
    await t.tap(find.text('Jordan Test'));
    await _io(t);
    expect(find.text(_outlookOther), findsOneWidget);
  });

  // ── 2. generate failure ─────────────────────────────────────────────────

  testWidgets(
      'generate fails on the server: the other next step, recorded as '
      'CoachCopilotScreen.generate, in a live region, no raw error', (t) async {
    server.generate = _Ans.http500;
    await _pumpAndSelect(t);
    await t.tap(find.text('Generate recommendation'));
    await _io(t);
    expect(find.text(_genOther), findsOneWidget);
    expect(_inLiveRegion(find.text(_genOther)), isTrue);
    expect(find.textContaining('connection'), findsNothing);
    expect(find.textContaining('boom'), findsNothing);
    expect(reported, contains('CoachCopilotScreen.generate'));
    expect(find.text('Approve & assign'), findsNothing);
  });

  testWidgets('generate fails on the network: check your connection',
      (t) async {
    server.generate = _Ans.network;
    await _pumpAndSelect(t);
    await t.tap(find.text('Generate recommendation'));
    await _io(t);
    expect(find.text(_genNetwork), findsOneWidget);
    expect(reported, contains('CoachCopilotScreen.generate'));

    // A later success clears the failure.
    server.generate = _Ans.ok;
    await t.tap(find.text('Generate recommendation'));
    await _io(t);
    expect(find.text(_genNetwork), findsNothing);
    expect(find.text('Goblet squat'), findsOneWidget);
  });

  testWidgets(
      'generate answers with no result: a failure (other copy), recorded — '
      'not an empty recommendation', (t) async {
    server.generate = _Ans.nullBody;
    await _pumpAndSelect(t);
    await t.tap(find.text('Generate recommendation'));
    await _io(t);
    expect(find.text(_genOther), findsOneWidget);
    expect(reported, contains('CoachCopilotScreen.generate'));
  });
}
