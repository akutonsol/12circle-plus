import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/features/ai_coach/presentation/ai_coach_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/pump_until.dart';

// P0-FL-55(a) — the AI Coach "COACH STYLE" persona chips and "COACHING MEMORY"
// chips (cycle 10 reviewers' findings, confirmed on b7ec6ef):
//  * persona chips were bare GestureDetectors ~31px tall (7+7 padding around
//    12px text): below the 44px minimum, announced only as text — no button,
//    no "selected", no group — so a screen-reader user could not tell which
//    style was theirs or that a chip could be chosen;
//  * a memory could be deleted ONLY by long-pressing its ~30px chip: nothing
//    visible said so, and there was no labelled delete and no semantic action,
//    so a screen-reader user could not remove a remembered fact (injuries
//    included) at all.
// Kept from FL-50b: chips appear only after a confirmed read (pinned in
// ai_coach_reads_report_failures_test.dart, which must stay green).

const _uid = '00000000-0000-4000-8000-0000000f1055';

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

/// PostgREST stand-in: reads by table (ai_insights by `table:type`); writes
/// that ask for rows back get one row (a confirmed write) and, for a DELETE
/// on ai_memories, remove it from the next read.
class _Server extends http.BaseClient {
  final reads = <String, Object?>{};
  final failing = <String>{};
  final writes = <String>[];

  /// While set, every write waits for it — a save "in flight".
  Completer<void>? writeGate;

  void reset() {
    reads.clear();
    failing.clear();
    writes.clear();
    writeGate = null;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (path.contains('/functions/v1/')) {
      return _json({'error': 'unavailable'}, 500, request);
    }
    final table = path.split('/').last;
    final q = request.url.queryParameters;
    if (request.method != 'GET') {
      writes.add('${request.method} $table ${request.url.query}');
      if (writeGate != null) await writeGate!.future;
      if (request.method == 'DELETE' && table == 'ai_memories') {
        final id = (q['id'] ?? '').replaceFirst('eq.', '');
        (reads['ai_memories'] as List?)?.removeWhere((m) => (m as Map)['id'] == id);
      }
      return q.containsKey('select')
          ? _json([{'id': 'row-1', 'user_id': _uid}], 200, request)
          : http.StreamedResponse(const Stream.empty(), 204, request: request);
    }
    final type = (q['type'] ?? '').replaceFirst('eq.', '');
    final key = table == 'ai_insights' ? '$table:$type' : table;
    if (failing.contains(key)) {
      return _json({'message': 'internal error', 'code': 'XX000'}, 500, request);
    }
    final single = request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
    final answer = reads[key];
    if (answer is List) {
      return _json(single ? (answer.isEmpty ? null : answer.first) : answer, 200, request);
    }
    if (answer is Map) return _json(single ? answer : [answer], 200, request);
    return _json(single ? null : [], 200, request);
  }

  http.StreamedResponse _json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

const _styles = [
  'Supportive', 'Motivational', 'Tough Love', 'Educational', 'Scientific', 'Calm', 'High Energy',
];
const _longMemory =
    'Left knee — old ACL reconstruction, no deep lunges or jumping on hard floors please';

void _seed(_Server s, {List<Map<String, Object?>>? memories}) {
  final today = DateTime.now();
  s.reads['ai_insights:daily_insight'] = {
    'id': 'i1', 'title': 'Brief title', 'body': 'Brief body', 'data': {},
  };
  s.reads['ai_reviews'] = {
    'id': 'r1', 'summary': 'Review summary',
    'period_end': DateTime(today.year, today.month, today.day).toIso8601String(),
    'metrics': {},
  };
  s.reads['ai_memories'] = memories ??
      [
        {'id': 'm1', 'kind': 'injury', 'content': 'left knee'},
        {'id': 'm2', 'kind': 'like', 'content': _longMemory},
      ];
}

void main() {
  late _Server server;

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

  setUp(() => server.reset());

  Future<void> pumpScreen(WidgetTester tester,
      {double width = 900, double scale = 1.0}) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = Size(width, 9000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
      builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: const AICoachScreen(),
    )));
    await pumpUntil(tester, () => find.text('Motivational').evaluate().isNotEmpty,
        what: 'the coach style card to load');
    await pumpUntil(
        tester,
        () =>
            find.text('left knee').evaluate().isNotEmpty ||
            find.textContaining('Tell your coach what you like').evaluate().isNotEmpty ||
            find.text("Couldn't load what your coach remembers").evaluate().isNotEmpty,
        what: 'the coaching memory card to load');
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  Finder style(String label) => find.bySemanticsLabel('Coach style: $label');
  Finder deleteOf(String text) => find.bySemanticsLabel('Delete memory: $text');

  group('coach style chips', () {
    testWidgets('each chip is a >= 44px button naming the style; the member\'s is selected',
        (tester) async {
      final handle = tester.ensureSemantics();
      _seed(server);
      server.reads['ai_profiles'] = {
        'coach_persona': {'name': 'Nova', 'style': 'calm', 'tone': 'calm'},
      };
      await pumpScreen(tester);

      for (final label in _styles) {
        expect(style(label), findsOneWidget,
            reason: 'THE defect: the chip was announced as bare text');
        expect(
            tester.getSemantics(style(label)),
            isSemantics(
              label: 'Coach style: $label',
              isButton: true,
              hasTapAction: true,
              isInMutuallyExclusiveGroup: true,
              isSelected: label == 'Calm',
            ));
        final chip = find.ancestor(of: find.text(label), matching: find.byType(GestureDetector)).first;
        expect(tester.getSize(chip).height, greaterThanOrEqualTo(44),
            reason: 'THE defect: the chip was ~31px tall');
      }
      handle.dispose();
      await drain(tester);
    });

    testWidgets('positive control: choosing a style saves it and moves "selected"',
        (tester) async {
      final handle = tester.ensureSemantics();
      _seed(server);
      await pumpScreen(tester);
      expect(tester.getSemantics(style('Motivational')), isSemantics(isSelected: true));

      await tester.tap(find.text('Scientific'));
      await pumpUntil(tester, () => find.text('Coach style updated — your next brief will match.').evaluate().isNotEmpty,
          what: 'the style save to be confirmed');
      expect(server.writes.where((w) => w.startsWith('POST ai_profiles')), hasLength(1));
      expect(tester.getSemantics(style('Scientific')), isSemantics(isSelected: true));
      expect(tester.getSemantics(style('Motivational')), isSemantics(isSelected: false));
      handle.dispose();
      await drain(tester);
    });

    testWidgets('a second tap while a save is in flight does not fire a second save',
        (tester) async {
      _seed(server);
      await pumpScreen(tester);
      final gate = server.writeGate = Completer<void>();
      await tester.tap(find.text('Scientific'));
      await pumpUntil(tester, () => server.writes.isNotEmpty, what: 'the first save to be sent');
      await tester.tap(find.text('Calm'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(server.writes, hasLength(1),
          reason: 'two saves in flight race the revert on failure');
      gate.complete();
      server.writeGate = null;
      await pumpUntil(tester, () => find.text('Coach style updated — your next brief will match.').evaluate().isNotEmpty,
          what: 'the save to finish');
      await drain(tester);
    });
  });

  group('coaching memory chips', () {
    testWidgets('each memory has a labelled >= 44px delete button and a semantic delete action',
        (tester) async {
      final handle = tester.ensureSemantics();
      _seed(server);
      await pumpScreen(tester);

      for (final text in ['left knee', _longMemory]) {
        expect(deleteOf(text), findsOneWidget,
            reason: 'THE defect: delete was an unlabelled long-press only');
        expect(tester.getSemantics(deleteOf(text)),
            isSemantics(isButton: true, hasTapAction: true, label: 'Delete memory: $text'));
        final size = tester.getSize(deleteOf(text));
        expect(size.width, greaterThanOrEqualTo(44));
        expect(size.height, greaterThanOrEqualTo(44));
      }
      final chip = tester.getSemantics(find.text('left knee'));
      expect(chip,
          isSemantics(customActions: const [CustomSemanticsAction(label: 'Delete memory')]),
          reason: 'a screen reader offers "Delete memory" on the chip itself');
      handle.dispose();
      await drain(tester);
    });

    testWidgets('positive control: the delete button removes the memory', (tester) async {
      final handle = tester.ensureSemantics();
      _seed(server);
      await pumpScreen(tester);
      await tester.tap(deleteOf('left knee'));
      await pumpUntil(tester, () => find.text('left knee').evaluate().isEmpty,
          what: 'the deleted memory to disappear');
      expect(server.writes.single, startsWith('DELETE ai_memories'));
      expect(server.writes.single, contains('id=eq.m1'));
      expect(find.text(_longMemory), findsOneWidget);
      expect(find.text("Couldn't remove that — try again."), findsNothing);
      handle.dispose();
      await drain(tester);
    });

    testWidgets('the semantic custom action deletes the memory', (tester) async {
      final handle = tester.ensureSemantics();
      _seed(server);
      await pumpScreen(tester);
      final node = tester.getSemantics(find.text('left knee'));
      const action = CustomSemanticsAction(label: 'Delete memory');
      node.owner!.performAction(
          node.id, SemanticsAction.customAction, CustomSemanticsAction.getIdentifier(action));
      await pumpUntil(tester, () => find.text('left knee').evaluate().isEmpty,
          what: 'the custom action to delete the memory');
      expect(server.writes.single, contains('id=eq.m1'));
      handle.dispose();
      await drain(tester);
    });

    testWidgets('a delete in flight cannot be fired again', (tester) async {
      final handle = tester.ensureSemantics();
      _seed(server);
      await pumpScreen(tester);
      final gate = server.writeGate = Completer<void>();
      await tester.tap(deleteOf('left knee'));
      await pumpUntil(tester, () => server.writes.isNotEmpty, what: 'the delete to be sent');
      await tester.pump(); // the request can be sent before any frame
      expect(tester.widget<IconButton>(
              find.descendant(of: deleteOf('left knee'), matching: find.byType(IconButton))).onPressed,
          isNull);
      await tester.longPress(find.text('left knee'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(server.writes, hasLength(1));
      gate.complete();
      server.writeGate = null;
      await pumpUntil(tester, () => find.text('left knee').evaluate().isEmpty,
          what: 'the delete to finish');
      handle.dispose();
      await drain(tester);
    });

    testWidgets('negative control: nothing remembered stays the empty copy, no delete offered',
        (tester) async {
      final handle = tester.ensureSemantics();
      _seed(server, memories: []);
      await pumpScreen(tester);
      expect(find.textContaining('Tell your coach what you like'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^Delete memory')), findsNothing);
      expect(find.text("Couldn't load what your coach remembers"), findsNothing);
      handle.dispose();
      await drain(tester);
    });

    testWidgets('a failed read offers no delete (nothing to act on)', (tester) async {
      final handle = tester.ensureSemantics();
      _seed(server);
      server.failing.add('ai_memories');
      await pumpScreen(tester);
      expect(find.text("Couldn't load what your coach remembers"), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^Delete memory')), findsNothing);
      handle.dispose();
      await drain(tester);
    });
  });

  group('no overflow, no text shrinking', () {
    for (final scale in [1.0, 1.3, 2.0]) {
      for (final width in [320.0, 360.0, 390.0, 430.0]) {
        testWidgets('${width.toInt()}dp at ${scale}x', (tester) async {
          _seed(server);
          // Other cards on this screen (the daily brief header, outside this
          // package) overflow at these sizes; their errors are collected here
          // so the two cards in scope can be measured on their own.
          final elsewhere = <FlutterErrorDetails>[];
          final previous = FlutterError.onError;
          FlutterError.onError = elsewhere.add;
          try {
            await pumpScreen(tester, width: width, scale: scale);
          } finally {
            FlutterError.onError = previous;
          }
          expect(elsewhere.where((e) => !e.toString().contains('overflowed')), isEmpty);

          for (final card in ['_CoachPersonaCard', '_CoachingMemoryCard']) {
            final root = tester.renderObject(
                find.byWidgetPredicate((w) => w.runtimeType.toString() == card));
            void visit(RenderObject o) {
              if (o is RenderFlex) {
                o.visitChildren((c) {
                  final box = c as RenderBox;
                  final at = (box.parentData! as FlexParentData).offset;
                  final fits = at.dx >= -0.01 &&
                      at.dy >= -0.01 &&
                      at.dx + box.size.width <= o.size.width + 0.01 &&
                      at.dy + box.size.height <= o.size.height + 0.01;
                  expect(fits, isTrue,
                      reason: '$card: a ${o.direction.name} flex child overflows '
                          '(${box.runtimeType} at $at, ${box.size} in ${o.size})');
                });
              }
              o.visitChildren(visit);
            }

            visit(root);
          }

          for (final (t, size) in [
            ('COACH STYLE', 11.0), ('COACHING MEMORY', 11.0),
            ('High Energy', 12.0), ('Tough Love', 12.0), ('left knee', 12.0), (_longMemory, 12.0),
          ]) {
            final f = find.text(t);
            expect(f, findsOneWidget);
            final p = tester.renderObject<RenderParagraph>(f);
            expect(p.text.style?.fontSize, size);
            expect(p.textScaler.scale(size), closeTo(size * scale, 0.001),
                reason: 'the text keeps the member\'s text size');
            expect(find.ancestor(of: f, matching: find.byType(FittedBox)), findsNothing);
            expect(tester.getRect(f).right, lessThanOrEqualTo(width));
          }
          // The long memory wraps instead of overflowing; its delete stays 44px.
          final del = find.descendant(
              of: find.ancestor(of: find.text(_longMemory), matching: find.byType(Row)).first,
              matching: find.byType(IconButton));
          expect(tester.getSize(del).width, greaterThanOrEqualTo(44));
          expect(tester.getRect(del).right, lessThanOrEqualTo(width));
          await drain(tester);
        });
      }
    }
  });
}
