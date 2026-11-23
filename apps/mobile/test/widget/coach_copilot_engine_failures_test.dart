import 'dart:convert';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/coach/presentation/coach_copilot_screen.dart';
import 'package:circle_fitness/features/dashboard/presentation/coach_dashboard_screen.dart'
    show coachClientsProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// P0-FL-43 — a failed copilot generate is reported honestly.
//
// A failed `generate_workout` showed "Couldn't generate a recommendation —
// try again." with nothing recorded and no network/other next step. The
// service's `lastError` is now reported (origin `CoachCopilotScreen.generate`),
// the copy follows the shared `isNetworkFailure`, and the notice is a live
// region. An answer that is not a recommendation is a failure, never empty.
//
// OUT OF SCOPE (lead scope correction): `predictClient` still swallows
// failures into null, so a failed outlook still shows no card. That is the
// recorded blocker pinned by tests/skills-agent/coordinator.test.mjs §15
// (Wave 3B-4, MASTER_REMEDIATION_REGISTRY §7.10) and is not changed here.
//
// HOW TO SEE IT FAIL: `git checkout df35d5f -- lib/features/coach/
// presentation/coach_copilot_screen.dart`, run this file, then
// `git checkout HEAD -- …`. Every test fails.
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
  final predictBodies = <String>[];
  final generateBodies = <String>[];

  void reset() {
    predict = _Ans.nullBody;
    generate = _Ans.ok;
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
          'client_id': _clientId,
          'has_assessment': true,
          'fitness_goal': 'lose_fat',
          'experience_level': 'Beginner',
          'training_location': 'home',
          'has_injuries': false,
          'injury_locations': '',
        },
      ]);
    }
    if (path.endsWith('/rpc/predict_client') ||
        path.endsWith('/rpc/record_prediction')) {
      predictBodies.add(body);
      return _answer(request, predict, {
        'status': 'ok',
        'weeks_completed': 2,
        'duration_weeks': 8,
        'goal': {'progress_pct': 25, 'confidence': 90},
        'plateau_risk': 'low',
        'injury_risk': {'general': 'low'},
        'recovery': {'trend': 'stable'},
        'alerts': [],
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
        return _json(request, 500, {
          'code': 'XX000',
          'message': 'boom',
          'details': null,
          'hint': null
        });
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
    await t
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
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
const _genOther = "Couldn't generate a recommendation — $_other";
const _genNetwork = "Couldn't generate a recommendation — $_network";

void main() {
  final server = _Server();
  final reported = <String>[];
  final failures = <AppFailure>[];

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
    failures.clear();
    setFailureSink((f) {
      reported.add(f.origin);
      failures.add(f);
    });
  });
  tearDown(resetFailureSink);

  // ── generate failure ─────────────────────────────────────────────────

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

  // ── lead mutant round: stale lastError, one report per tap ──────────

  List<AppFailure> generateFailures() =>
      failures.where((f) => f.origin == 'CoachCopilotScreen.generate').toList();

  testWidgets(
      'a stale lastError from an EARLIER failed generate is never used for a '
      'later failure: network then no-answer → the later copy is the other '
      'next step and the reported error is the StateError', (t) async {
    // Kills the mutant "remove `_svc.lastError = null;` before
    // generateWorkout": generateWorkout sets lastError only in its catch, so
    // a later null answer would otherwise re-report the earlier
    // ClientException and show the connection hint.
    server.generate = _Ans.network;
    await _pumpAndSelect(t);
    await t.tap(find.text('Generate recommendation'));
    await _io(t);
    expect(find.text(_genNetwork), findsOneWidget);
    expect(generateFailures().single.error, isA<http.ClientException>());

    server.generate = _Ans.nullBody;
    await t.tap(find.text('Generate recommendation'));
    await _io(t);
    expect(find.text(_genOther), findsOneWidget);
    expect(find.text(_genNetwork), findsNothing);
    expect(find.textContaining('connection'), findsNothing);
    final later = generateFailures();
    expect(later, hasLength(2));
    expect(later.last.error, isA<StateError>());
    expect(later.last.error, isNot(same(later.first.error)));
  });

  testWidgets('exactly one reportError per failed Generate tap', (t) async {
    server.generate = _Ans.http500;
    await _pumpAndSelect(t);
    expect(generateFailures(), isEmpty, reason: 'selecting reports nothing');

    await t.tap(find.text('Generate recommendation'));
    await _io(t);
    expect(generateFailures(), hasLength(1));

    server.generate = _Ans.network;
    await t.tap(find.text('Generate recommendation'));
    await _io(t);
    expect(generateFailures(), hasLength(2));

    server.generate = _Ans.nullBody;
    await t.tap(find.text('Generate recommendation'));
    await _io(t);
    expect(generateFailures(), hasLength(3));

    // A success reports nothing.
    server.generate = _Ans.ok;
    await t.tap(find.text('Generate recommendation'));
    await _io(t);
    expect(generateFailures(), hasLength(3));
    expect(find.text('Goblet squat'), findsOneWidget);
  });
}
