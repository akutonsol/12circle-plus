import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/ai_coach/data/ai_coach_service.dart';
import 'package:circle_fitness/features/ai_coach/presentation/ai_coach_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// P0-FL-50b — the member-facing AI Coach ("Nova") turned a failed read into
// "nothing there".
//
// Every read in AICoachService ended `catch (_) { return <nothing>; }`:
//  * getMemories → [] : the member's ONLY view of the health facts the coach
//    keeps (injuries included) said "nothing remembered" — also right after a
//    delete whose reload failed;
//  * getConversationHistory → [] : the chat reopened as a brand-new
//    conversation with the welcome message;
//  * getTodayInsight / getLatestReview → null : the brief / weekly review card
//    took "none yet" and GENERATED a new one over whatever was stored;
//  * getLatestInsight / getLatestPrediction → null : "none yet" copy;
//  * getPersona → the default Nova persona, shown as the member's setting —
//    and one tap on a style chip then saved over their real persona.
// The writes (setPersona, addMemory, deleteMemory) answered false/true without
// recording, and without asking their row back (RLS filtering a write to
// nothing is a 204, same as success).
//
// Per site: a THROWN failure is recorded with its origin and shown as
// "Couldn't load …" with a busy-aware Try again; a legitimate absence keeps
// today's behaviour exactly.

const _uid = '00000000-0000-4000-8000-0000000050b0';

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

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

enum _Write { oneRow, zeroRows, serverError }

/// PostgREST + Functions stand-in.
///
/// Reads are keyed by table, and for `ai_insights` by `table:type`
/// (`ai_insights:risk`). A key in [failing] answers 500 (or, with [network],
/// the request never arrives). Writes follow [write]; a write that does not
/// ask for rows back gets 204 whatever happened — like the real thing.
class _Server extends http.BaseClient {
  final failing = <String>{};
  bool network = false;
  final reads = <String, Object?>{};
  _Write write = _Write.oneRow;
  final writes = <String>[];
  var functionCalls = 0;

  /// While set, every read waits for it — a retry "in flight".
  Completer<void>? gate;

  void reset() {
    failing.clear();
    network = false;
    reads.clear();
    write = _Write.oneRow;
    writes.clear();
    functionCalls = 0;
    gate = null;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (path.contains('/functions/v1/')) {
      functionCalls++;
      return _json({'error': 'unavailable'}, 500, request);
    }
    final table = path.split('/').last;
    final q = request.url.queryParameters;
    final asksForRows = q.containsKey('select');
    if (request.method != 'GET') {
      writes.add('${request.method} $table');
      switch (write) {
        case _Write.serverError:
          return _json({'message': 'refused', 'code': 'XX000'}, 500, request);
        case _Write.zeroRows:
          return asksForRows
              ? _json([], 200, request)
              : http.StreamedResponse(const Stream.empty(), 204, request: request);
        case _Write.oneRow:
          return asksForRows
              ? _json([
                  {'id': 'row-1', 'user_id': _uid}
                ], 200, request)
              : http.StreamedResponse(const Stream.empty(), 204, request: request);
      }
    }
    final type = (q['type'] ?? '').replaceFirst('eq.', '');
    final key = table == 'ai_insights' ? '$table:$type' : table;
    if (gate != null) await gate!.future;
    if (failing.contains(key)) {
      if (network) throw http.ClientException('Connection refused', request.url);
      return _json({'message': 'internal error', 'code': 'XX000'}, 500, request);
    }
    final single = request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
    final answer = reads[key];
    if (answer is List) return _json(single ? (answer.isEmpty ? null : answer.first) : answer, 200, request);
    if (answer is Map) return _json(single ? answer : [answer], 200, request);
    return _json(single ? null : [], 200, request);
  }

  http.StreamedResponse _json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

const _otherwise = 'Try again in a moment. If it keeps happening, contact support.';
const _network = 'Check your connection and try again.';

/// What a member with some history has: today's brief and a fresh weekly
/// review (so neither card generates on open), nothing else yet.
void _seedOrdinary(_Server s) {
  final today = DateTime.now();
  s.reads['ai_insights:daily_insight'] = {
    'id': 'i1', 'title': 'Brief title', 'body': 'Brief body', 'data': {},
  };
  s.reads['ai_reviews'] = {
    'id': 'r1', 'summary': 'Review summary',
    'period_end': DateTime(today.year, today.month, today.day).toIso8601String(),
    'metrics': {},
  };
}

void main() {
  late _Server server;
  late List<AppFailure> seen;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = _Server();
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
    seen = <AppFailure>[];
    setFailureSink(seen.add);
  });

  tearDown(resetFailureSink);

  // ── Service: a failed read is recorded and propagates ───────────────────
  group('AICoachService reads', () {
    final reads = <String, (String, Future<Object?> Function(), Object?)>{
      'getPersona': ('ai_profiles', () => AICoachService().getPersona(),
          {'name': 'Nova', 'style': 'motivational', 'tone': 'supportive'}),
      'getTodayInsight': ('ai_insights:daily_insight', () => AICoachService().getTodayInsight(), null),
      'getLatestInsight': ('ai_insights:risk', () => AICoachService().getLatestInsight('risk'), null),
      'getLatestReview': ('ai_reviews', () => AICoachService().getLatestReview(), null),
      'getLatestPrediction': ('ai_goal_predictions', () => AICoachService().getLatestPrediction(), null),
      'getMemories': ('ai_memories', () => AICoachService().getMemories(), <Object?>[]),
      'getConversationHistory': ('ai_conversations',
          () => AICoachService().getConversationHistory(limit: 10), <Object?>[]),
    };
    reads.forEach((method, spec) {
      final (key, read, empty) = spec;
      test('$method: a failed read throws and is recorded — not "nothing"', () async {
        server.failing.add(key);
        await expectLater(read(), throwsA(isA<PostgrestException>()),
            reason: 'THE defect: the failure was answered as nothing there');
        expect(seen.map((f) => f.origin), ['AICoachService.$method']);
      });
      test('$method: legitimately nothing is still nothing, unrecorded', () async {
        expect(await read(), empty);
        expect(seen, isEmpty);
      });
    });
  });

  // ── Service: writes say what happened, and record a failure ─────────────
  group('AICoachService writes', () {
    final writes = <String, Future<bool> Function()>{
      'setPersona': () => AICoachService().setPersona(style: 'calm', tone: 'calm'),
      'addMemory': () => AICoachService().addMemory('injury', 'left knee'),
      'deleteMemory': () => AICoachService().deleteMemory('m1'),
    };
    writes.forEach((method, run) {
      test('$method: a write that changed no row is a failure, recorded', () async {
        server.write = _Write.zeroRows;
        expect(await run(), isFalse,
            reason: 'RLS filtering the write to nothing was reported as saved');
        expect(seen.map((f) => f.origin), ['AICoachService.$method']);
      });
      test('$method: a refused write is false and recorded', () async {
        server.write = _Write.serverError;
        expect(await run(), isFalse);
        expect(seen.map((f) => f.origin), ['AICoachService.$method']);
      });
      test('$method: a confirmed write is true, nothing recorded', () async {
        expect(await run(), isTrue);
        expect(seen, isEmpty);
      });
    });
  });

  // ── The screen ──────────────────────────────────────────────────────────
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
      await tester.pump();
    }
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 6000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: AICoachScreen())));
    await settle(tester);
  }

  /// Let any SnackBar timer run out before the test ends.
  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  final cards = <String, (String, String)>{
    // key: (what, the card's empty copy)
    'ai_goal_predictions': ('your goal prediction', 'Project your goal date from your current pace.'),
    'ai_insights:meal_suggestion': ('your meal ideas', 'Get meals that fit your remaining macros for today.'),
    'ai_insights:progress': ('your progress insight',
        'Surface your biggest win from the data — strength, streaks, trends.'),
    'ai_insights:risk': ('your risk assessment', 'Spot plateau, drop-off, and injury risk before they happen.'),
    'ai_memories': ('what your coach remembers',
        'Tell your coach what you like, dislike, and any injuries — it remembers and adapts your plan.'),
  };

  group('a card whose read fails says so; Try again recovers', () {
    cards.forEach((key, spec) {
      final (what, emptyCopy) = spec;
      testWidgets('$key → "Couldn\'t load $what", not "$emptyCopy"', (tester) async {
        _seedOrdinary(server);
        server.failing.add(key);
        await pumpScreen(tester);

        expect(find.text("Couldn't load $what"), findsOneWidget);
        expect(find.text(_otherwise), findsOneWidget);
        expect(find.text(emptyCopy), findsNothing,
            reason: 'THE defect: the failed read was drawn as "none yet"');
        expect(seen.map((f) => f.origin), hasLength(1));

        server.failing.clear();
        await tester.tap(find.widgetWithText(TextButton, 'Try again'));
        await settle(tester);
        expect(find.text("Couldn't load $what"), findsNothing);
        expect(find.text(emptyCopy), findsOneWidget,
            reason: 'after a confirmed read, nothing is shown as nothing');
        await drain(tester);
      });
    });
  });

  testWidgets('legitimately nothing: every card keeps today\'s empty copy', (tester) async {
    _seedOrdinary(server);
    await pumpScreen(tester);
    for (final (_, emptyCopy) in cards.values) {
      expect(find.text(emptyCopy), findsOneWidget);
    }
    expect(find.textContaining("Couldn't load"), findsNothing);
    expect(find.text('Brief title'), findsOneWidget);
    expect(find.text('Review summary'), findsOneWidget);
    expect(server.functionCalls, 0);
    expect(seen, isEmpty);
    await drain(tester);
  });

  group('the brief and the weekly review do not generate on a failed read', () {
    testWidgets('daily brief', (tester) async {
      _seedOrdinary(server);
      server.failing.add('ai_insights:daily_insight');
      await pumpScreen(tester);
      expect(find.text("Couldn't load today's brief"), findsOneWidget);
      expect(server.functionCalls, 0,
          reason: 'THE defect: a failed read was "no brief yet" and a new one '
              'was generated over the stored brief');
      expect(seen.map((f) => f.origin), ['AICoachService.getTodayInsight']);

      server.failing.clear();
      await tester.tap(find.widgetWithText(TextButton, 'Try again'));
      await settle(tester);
      expect(find.text('Brief title'), findsOneWidget);
      expect(server.functionCalls, 0);
      await drain(tester);
    });

    testWidgets('weekly review', (tester) async {
      _seedOrdinary(server);
      server.failing.add('ai_reviews');
      await pumpScreen(tester);
      expect(find.text("Couldn't load your weekly review"), findsOneWidget);
      expect(server.functionCalls, 0);
      expect(seen.map((f) => f.origin), ['AICoachService.getLatestReview']);
      await drain(tester);
    });

    testWidgets('legitimately no brief still generates one (unchanged)', (tester) async {
      _seedOrdinary(server);
      server.reads.remove('ai_insights:daily_insight');
      await pumpScreen(tester);
      expect(server.functionCalls, 1);
      expect(find.text("Couldn't load today's brief"), findsNothing);
      await drain(tester);
    });
  });

  testWidgets('a connection failure names the connection', (tester) async {
    _seedOrdinary(server);
    server
      ..failing.add('ai_goal_predictions')
      ..network = true;
    await pumpScreen(tester);
    // The client may retry a request that never arrived; wait it out.
    final notice = find.text("Couldn't load your goal prediction");
    // Its backoff timers run on the test clock, so advance that too.
    for (var i = 0; i < 60 && notice.evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(seconds: 1));
    }
    expect(notice, findsOneWidget);
    expect(find.text(_network), findsOneWidget);
    expect(find.text(_otherwise), findsNothing);
    await drain(tester);
  });

  group('coach style', () {
    testWidgets('a failed read offers no style to save over the real one', (tester) async {
      _seedOrdinary(server);
      server.failing.add('ai_profiles');
      await pumpScreen(tester);

      expect(find.text("Couldn't load your coach style"), findsOneWidget);
      for (final label in ['Supportive', 'Motivational', 'Calm']) {
        expect(find.text(label), findsNothing,
            reason: 'THE defect: the default persona was shown as the '
                "member's, and tapping a chip saved it over their real one");
      }
      expect(seen.map((f) => f.origin), ['AICoachService.getPersona']);

      // Busy-aware, >= 44px retry: in flight it is disabled.
      final gate = server.gate = Completer<void>();
      server.failing.clear();
      final button = find.widgetWithText(TextButton, 'Try again');
      expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
      await tester.tap(button);
      await tester.pump();
      expect(tester.widget<TextButton>(find.byType(TextButton)).onPressed, isNull,
          reason: 'a retry in flight cannot be fired again');
      expect(find.text("Couldn't load your coach style"), findsOneWidget);

      server.reads['ai_profiles'] = {
        'coach_persona': {'name': 'Nova', 'style': 'calm', 'tone': 'calm'},
      };
      gate.complete();
      server.gate = null;
      await settle(tester);
      expect(find.text("Couldn't load your coach style"), findsNothing);
      expect(find.text('Calm'), findsOneWidget);
      expect(server.writes, isEmpty, reason: 'nothing was saved by loading');
      await drain(tester);
    });

    testWidgets('never chosen → the default, as today', (tester) async {
      _seedOrdinary(server);
      await pumpScreen(tester);
      expect(find.text('Motivational'), findsOneWidget);
      expect(find.text("Couldn't load your coach style"), findsNothing);
      await drain(tester);
    });
  });

  group('coaching memory', () {
    testWidgets('a failed reload after a delete is not "nothing remembered"', (tester) async {
      _seedOrdinary(server);
      server.reads['ai_memories'] = [
        {'id': 'm1', 'kind': 'injury', 'content': 'left knee'},
      ];
      await pumpScreen(tester);
      expect(find.text('left knee'), findsOneWidget);

      server.failing.add('ai_memories');
      await tester.longPress(find.text('left knee'));
      await settle(tester);

      expect(find.text("Couldn't load what your coach remembers"), findsOneWidget);
      expect(find.text(cards['ai_memories']!.$2), findsNothing,
          reason: 'THE defect: the failed reload said nothing is remembered');
      expect(seen.map((f) => f.origin), ['AICoachService.getMemories']);
      await drain(tester);
    });

    testWidgets('a memory that was not saved says so', (tester) async {
      _seedOrdinary(server);
      server.write = _Write.serverError;
      await pumpScreen(tester);

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'left knee');
      await tester.tap(find.text('Save'));
      await settle(tester);

      expect(find.text("Couldn't save that for your coach — try again."), findsOneWidget,
          reason: 'addMemory answered false and the screen ignored it');
      expect(seen.map((f) => f.origin), ['AICoachService.addMemory']);
      await drain(tester);
    });
  });

  group('conversation', () {
    const welcome =
        'Hey! I\'m your AI Coach. Ask me anything about nutrition, workouts, recovery, or your progress. What\'s on your mind? 💪';

    testWidgets('a failed history read is not a brand-new chat', (tester) async {
      _seedOrdinary(server);
      server.failing.add('ai_conversations');
      await pumpScreen(tester);
      await tester.tap(find.text('Conversation'));
      await settle(tester);

      expect(find.text("Couldn't load your conversation"), findsOneWidget);
      expect(find.text(welcome), findsNothing,
          reason: 'THE defect: the failure reopened the chat as if the member '
              'had never talked to the coach');
      expect(seen.map((f) => f.origin), ['AICoachService.getConversationHistory']);

      server.failing.clear();
      server.reads['ai_conversations'] = [
        {'id': 'c1', 'user_message': 'earlier question', 'ai_response': 'earlier answer',
         'created_at': '2026-11-01T09:00:00Z'},
      ];
      await tester.tap(find.widgetWithText(TextButton, 'Try again'));
      await settle(tester);
      expect(find.text("Couldn't load your conversation"), findsNothing);
      expect(find.text('earlier question'), findsOneWidget);
      expect(find.text('earlier answer'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('no history → the welcome, as today', (tester) async {
      _seedOrdinary(server);
      await pumpScreen(tester);
      await tester.tap(find.text('Conversation'));
      await settle(tester);
      expect(find.text(welcome), findsOneWidget);
      expect(find.textContaining("Couldn't load"), findsNothing);
      await drain(tester);
    });
  });
}
