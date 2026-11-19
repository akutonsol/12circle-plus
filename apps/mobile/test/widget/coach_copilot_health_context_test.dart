import 'dart:async';
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

// P0-FL-38 — Coach Copilot reads a client's health context (goal, experience,
// training location, injuries) ONLY through the logged route.
//
// Selecting a client read `user_profiles` for `fitness_goal, experience_level,
// training_location, injury_locations` directly — unlogged health data, with
// no error handling: a failed or refused read silently fell back to the roster
// row, and the engine was asked for a session as if the client were an
// uninjured intermediate hypertrophy lifter. Worse, `injury_locations` is
// comma-joined TEXT, and the copilot only read it when it was a List — so even
// a SUCCESSFUL read sent every client to the engine as uninjured.
//
// The fake below answers both routes: `user_profiles` with the stored row (so
// the old code "works"), and `get_client_assessment` per the test's choice.
//
// Generate is disabled ONLY while the context is unknown (loading / failed
// read). Every answered read — not the active coach, no row, an intake never
// completed, an injury with no area — keeps Generate enabled as before, with a
// live-region notice; blocking those clients is the owner's decision.
//
// HOW TO SEE IT FAIL: `git checkout 6f8918f -- lib/features/coach/
// presentation/coach_copilot_screen.dart` — it reads user_profiles, never
// calls the RPC, sends `injuries: []`, and shows no state for a failure.
// Against 3bc0a80 (the blocking version) the answered-read tests fail: no
// request reaches generate_workout.

const _uid = '00000000-0000-4000-8000-0000000c0f38';
const _clientId = '00000000-0000-4000-8000-00000000cf38';

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

/// The client's stored health context, as both routes would return it.
/// `injury_locations` is TEXT, comma-joined (migration 013).
Map<String, Object?> _health({bool injuryArea = true}) => {
      'fitness_goal': 'lose_fat',
      'experience_level': 'Beginner',
      'training_location': 'home',
      'has_injuries': true,
      'injury_locations': injuryArea ? 'Knee, Shoulder' : '',
    };

enum _Rpc { row, notCompleted, injuryNoArea, empty, denied, http500, network }

class _Server extends http.BaseClient {
  _Rpc rpc = _Rpc.row;
  Completer<void>? holdRpc;
  final assessmentBodies = <String>[];
  final generateBodies = <Map<String, dynamic>>[];
  final profileReads = <Uri>[];

  void reset() {
    rpc = _Rpc.row;
    holdRpc = null;
    assessmentBodies.clear();
    generateBodies.clear();
    profileReads.clear();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final body = request is http.Request ? request.body : '';
    if (path.endsWith('/rpc/get_client_assessment')) {
      assessmentBodies.add(body);
      final h = holdRpc;
      if (h != null) await h.future;
      switch (rpc) {
        case _Rpc.row:
          return _json(request, 200, [
            {'client_id': _clientId, 'has_assessment': true,
              'first_name': 'Jordan', ..._health()},
          ]);
        case _Rpc.injuryNoArea:
          return _json(request, 200, [
            {'client_id': _clientId, 'has_assessment': true,
              ..._health(injuryArea: false)},
          ]);
        case _Rpc.notCompleted:
          // A half-finished intake: some answers saved, never completed.
          return _json(request, 200, [
            {'client_id': _clientId, 'has_assessment': false,
              'fitness_goal': 'lose_fat'},
          ]);
        case _Rpc.empty:
          return _json(request, 200, []);
        case _Rpc.denied:
          return _json(request, 403, {'code': '42501',
            'message': 'not authorized to read this assessment',
            'details': null, 'hint': null});
        case _Rpc.http500:
          return _json(request, 500,
              {'code': 'XX000', 'message': 'boom', 'details': null, 'hint': null});
        case _Rpc.network:
          throw http.ClientException('Connection refused', request.url);
      }
    }
    if (path.endsWith('/rpc/generate_workout')) {
      generateBodies.add(
          Map<String, dynamic>.from(jsonDecode(body) as Map));
      return _json(request, 200, {
        'selected': [
          {'name': 'Goblet squat', 'score': 80, 'pattern': 'squat'},
        ],
        'trace': [],
      });
    }
    if (path.endsWith('/rpc/predict_client')) {
      return _json(request, 200, null);
    }
    if (path.endsWith('/user_profiles')) {
      profileReads.add(request.url);
      // The stored row: what the OLD direct read would have been handed.
      final row = {'id': _clientId, 'first_name': 'Jordan', ..._health()};
      final single =
          request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
      return _json(request, 200, single ? row : [row]);
    }
    return _json(request, 200, []);
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
      // The roster row: id + name only (the non-health source of the name).
      coachClientsProvider.overrideWith((ref) async => [
            {'id': _clientId, 'first_name': 'Jordan', 'last_name': 'Test'},
          ]),
    ],
    child: const MaterialApp(home: CoachCopilotScreen()),
  ));
  await _io(t);
  await t.tap(find.text('Jordan Test'));
  await _io(t);
}

Future<void> _tapGenerate(WidgetTester t) async {
  await t.tap(find.text('Generate recommendation'));
  await _io(t);
}

bool _inLiveRegion(Finder text) => find
    .ancestor(
        of: text,
        matching: find.byWidgetPredicate((w) =>
            w is Semantics && w.properties.liveRegion == true && w.container))
    .evaluate()
    .isNotEmpty;

const _defaults = 'Recommendations use defaults — their goal, experience and '
    'injuries are unknown. Review the session before assigning it.';
const _injuryNoArea = 'This client reported an injury without saying where.';

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

  testWidgets(
      'selecting a client reads NO user_profiles row and sends the logged RPC '
      'once — not again on rebuilds or a recommendation', (t) async {
    await _pumpAndSelect(t);
    expect(server.profileReads, isEmpty,
        reason: 'health context must not be read from user_profiles unlogged');
    expect(server.assessmentBodies, hasLength(1));
    expect(jsonDecode(server.assessmentBodies.single), {'p_client': _clientId});

    // Rebuilds (the recovery slider) and a recommendation do not re-read it.
    await t.drag(find.byType(Slider), const Offset(-80, 0));
    await t.pump();
    await _tapGenerate(t);
    expect(server.assessmentBodies, hasLength(1));
  });

  testWidgets(
      'the recommendation is built from the RPC row — injuries included '
      '(TEXT, comma-joined), not sent as none', (t) async {
    await _pumpAndSelect(t);
    await _tapGenerate(t);
    expect(server.generateBodies, hasLength(1));
    final ctx = server.generateBodies.single['p_context'] as Map;
    expect(ctx['injuries'], ['Knee', 'Shoulder'],
        reason: 'a client with injuries must not reach the engine as uninjured');
    expect(ctx['goal'], 'fat_loss');
    expect(ctx['experience'], 'beginner');
    expect(ctx['equipment'], ['dumbbell', 'bodyweight', 'band'],
        reason: 'training_location home');
    expect(server.generateBodies.single['p_subject'], _clientId);
    expect(find.text('Goblet squat'), findsOneWidget);
  });

  testWidgets(
      'a FAILED read (500) says so in a live region, records it, shows no raw '
      'error, and generates nothing', (t) async {
    server.rpc = _Rpc.http500;
    await _pumpAndSelect(t);
    const failed = "Couldn't load this client's health context — try again in "
        'a moment. If it keeps happening, contact support.';
    expect(find.text(failed), findsOneWidget);
    expect(_inLiveRegion(find.text(failed)), isTrue);
    expect(find.textContaining('connection'), findsNothing,
        reason: 'a server answer is not a connection problem');
    expect(find.textContaining('boom'), findsNothing, reason: 'no raw error');
    expect(reported, contains('clientAssessmentProvider'));

    await _tapGenerate(t);
    expect(server.generateBodies, isEmpty,
        reason: 'no recommendation from a context that did not load');
    expect(server.profileReads, isEmpty);
  });

  testWidgets(
      'a network failure says check your connection; Try again is >=44px, '
      'labelled, busy-aware, and a retry that answers enables Generate',
      (t) async {
    final handle = t.ensureSemantics();
    server.rpc = _Rpc.network;
    await _pumpAndSelect(t);
    expect(
        find.text("Couldn't load this client's health context — check your "
            'connection, then try again.'),
        findsOneWidget);
    final retry = find.widgetWithText(TextButton, 'Try again');
    expect(retry, findsOneWidget);
    expect(t.getSize(retry).height, greaterThanOrEqualTo(44));
    expect(find.bySemanticsLabel("Try again, load this client's health context"),
        findsOneWidget);
    final sent = server.assessmentBodies.length;

    server
      ..rpc = _Rpc.row
      ..holdRpc = Completer<void>();
    await t.tap(retry);
    await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pump();
    expect(find.text("Loading this client's health context…"), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Try again'), findsNothing,
        reason: 'no second button to fire a second read');
    expect(server.assessmentBodies.length, sent + 1);

    server.holdRpc!.complete();
    await _io(t);
    expect(server.assessmentBodies.length, sent + 1);
    await _tapGenerate(t);
    expect(server.generateBodies, hasLength(1));
    handle.dispose();
  });

  testWidgets('a completed assessment with injury areas shows no notice',
      (t) async {
    await _pumpAndSelect(t);
    expect(find.textContaining(_defaults), findsNothing);
    expect(find.text(_injuryNoArea), findsNothing);
    expect(find.textContaining("Couldn't"), findsNothing);
  });

  // An ANSWERED read never blocks Generate — whether to block these clients
  // is the owner's decision (P0-FL-38 adjustment). It is honest instead: a
  // live-region notice says the recommendation uses defaults, and the engine
  // gets the roster row's defaults (as before P0-FL-38), not half an intake.
  final defaultsAnswers = <_Rpc, String>{
    _Rpc.denied:
        "This client's health context is available once coaching is active.",
    _Rpc.empty: 'No assessment on file for this client yet.',
    _Rpc.notCompleted: "This client hasn't completed their assessment yet.",
  };
  defaultsAnswers.forEach((state, copy) {
    testWidgets(
        '${state.name}: Generate stays ENABLED (defaults) and a live-region '
        'notice says the goal, experience and injuries are unknown', (t) async {
      server.rpc = state;
      await _pumpAndSelect(t);
      expect(find.text(copy), findsOneWidget);
      expect(_inLiveRegion(find.text(copy)), isTrue);
      expect(find.text(_defaults), findsOneWidget);
      expect(_inLiveRegion(find.text(_defaults)), isTrue);
      expect(find.textContaining("Couldn't"), findsNothing,
          reason: 'an answer is not an outage');

      await _tapGenerate(t);
      expect(server.generateBodies, hasLength(1),
          reason: 'an answered read does not block generation');
      final ctx = server.generateBodies.single['p_context'] as Map;
      expect(ctx['goal'], 'hypertrophy', reason: 'defaults, as the notice says');
      expect(ctx['experience'], 'intermediate');
      expect(ctx['injuries'], isEmpty);
      expect(find.text('Goblet squat'), findsOneWidget);
      expect(find.text(_defaults), findsOneWidget,
          reason: 'the notice stays visible beside the recommendation');
      expect(server.profileReads, isEmpty);
    });
  });

  testWidgets(
      'injury reported with no area: Generate stays ENABLED with a prominent '
      'live-region notice to review before assigning', (t) async {
    server.rpc = _Rpc.injuryNoArea;
    await _pumpAndSelect(t);
    expect(find.text(_injuryNoArea), findsOneWidget);
    expect(_inLiveRegion(find.text(_injuryNoArea)), isTrue);
    expect(find.textContaining('review the session before assigning'),
        findsOneWidget);
    expect(find.textContaining("Couldn't"), findsNothing);

    await _tapGenerate(t);
    expect(server.generateBodies, hasLength(1));
    final ctx = server.generateBodies.single['p_context'] as Map;
    expect(ctx['goal'], 'fat_loss', reason: 'the completed assessment is used');
    expect(ctx['experience'], 'beginner');
    expect(find.text(_injuryNoArea), findsOneWidget,
        reason: 'the warning stays visible beside the recommendation');
  });
}
