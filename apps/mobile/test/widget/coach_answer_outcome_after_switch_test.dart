import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/core/realtime/realtime.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/checkins/domain/checkin_provider.dart';
import 'package:circle_fitness/features/coach/data/coach_relationship_service.dart';
import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart';
import 'package:circle_fitness/features/dashboard/domain/coach_triage_provider.dart';
import 'package:circle_fitness/features/dashboard/presentation/coach_dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../support/pump_until.dart';
import '../support/two_coach_postgrest.dart';
import '../support/two_member_postgrest.dart' show TwoMemberPostgrest;

// P0-RM-1 (C15-63b-03, C14-62b-04) · the coach dashboard's Accept / Decline
// after an account change: an answer that WAS made (the relationship update
// matched A's row) and then dropped because another account (or nobody) is
// signed in is recorded once as the outcome not shown — in the FL-63b form,
// never as a stop "before anything was sent"; an answer that changed nothing
// (0 rows) keeps the single stop record; and no fallback says a refusal that
// only reports the account change.
//
// Harness copied from coach_request_answer_keeps_its_coach_test.dart (the REAL
// dashboard and service, a fake PostgREST answering by bearer token, no
// account scope, the screen STAYS mounted across the switch).
//
// HOW TO SEE IT FAIL: `git checkout 6d1611d --
// lib/features/dashboard/presentation/coach_dashboard_screen.dart
// lib/features/coach/data/coach_relationship_service.dart`.

class _Socket implements WebSocketChannel {
  final _toClient = StreamController<String>();
  @override
  Stream<dynamic> get stream => _toClient.stream;
  @override
  WebSocketSink get sink => _Sink(_toClient);
  @override
  Future<void> get ready => Future.value();
  @override
  String? get protocol => null;
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sink implements WebSocketSink {
  final StreamController<String> toClient;
  _Sink(this.toClient);
  @override
  void add(dynamic raw) {
    final msg = jsonDecode(raw as String) as Map<String, dynamic>;
    final event = msg['event'];
    Map<String, dynamic> response = {};
    if (event == 'phx_join') {
      final config = (msg['payload'] as Map)['config'] as Map;
      response = {
        'postgres_changes': [
          for (final (i, f) in (config['postgres_changes'] as List).indexed)
            {...(f as Map<String, dynamic>), 'id': 100 + i},
        ]
      };
    } else if (event != 'heartbeat' && event != 'phx_leave') {
      return;
    }
    if (toClient.isClosed) return;
    toClient.add(jsonEncode({
      'topic': msg['topic'],
      'event': 'phx_reply',
      'payload': {'status': 'ok', 'response': response},
      'ref': msg['ref'],
    }));
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) => toClient.close();
  @override
  Future<void> get done => Completer<void>().future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

/// Also answers a write as PostgREST does when RLS (or another device) left
/// it no row to change: 200 with `[]`; and records each write's query.
class _Server extends TwoCoachPostgrest {
  final noRows = <String>{};
  final queries = <({String who, String method, String table, Map<String, String> q})>[];

  /// Every pending-requests read (`status=eq.pending`), by who asked.
  final pendingReads = <String>[];

  @override
  void reset() {
    super.reset();
    noRows.clear();
    queries.clear();
    pendingReads.clear();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final who = path.startsWith('/auth/v1/') ? '' : TwoMemberPostgrest.who(request);
    final key = '${request.method} ${path.split('/').last}:$who';
    if (request.method == 'GET' &&
        path.endsWith('/coach_client_relationships') &&
        request.url.queryParameters['status'] == 'eq.pending') {
      pendingReads.add(who);
    }
    if (request.method != 'GET' && !path.startsWith('/auth/v1/')) {
      queries.add((
        who: who,
        method: request.method,
        table: path.split('/').last,
        q: request.url.queryParameters,
      ));
    }
    final answer = await super.send(request);
    if (!noRows.contains(key) || answer.statusCode != 200) return answer;
    return http.StreamedResponse(Stream.value(utf8.encode('[]')), 200,
        request: request, headers: {'content-type': 'application/json'});
  }
}

/// A service whose answer is refused with a plain StateError that only says
/// the account changed (not an AccountChangedError): the shape a fallback
/// must not show.
class _RefusesPlainly extends CoachRelationshipService {
  @override
  Future<void> approveRequest(String relationshipId, String clientId,
          {String? expectedUid}) async =>
      throw StateError('Approving a request: the signed-in account changed');

  @override
  Future<void> declineRequest(String relationshipId, String clientId,
          {String? expectedUid}) async =>
      throw StateError('Declining a request: the signed-in account changed');
}

void main() {
  late _Server server;
  late ProviderContainer c;
  late GoRouter router;
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = _Server();
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: server,
      realtimeClientOptions: RealtimeClientOptions(
          transport: (String url, Map<String, String> headers) => _Socket()),
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryStore(),
        detectSessionInUri: false,
      ),
      debug: false,
    );
  });

  setUp(() async {
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
    for (final who in [memberA, memberB]) {
      server
        ..seed('coach_client_relationships', who, [
          {'client_id': who == memberA ? 'cl-a' : 'cl-b', 'status': 'active'},
          {'client_id': 'cl-p', 'id': 'rel-$who', 'status': 'pending'},
        ])
        ..seed('user_profiles', who, [
          {
            'id': who == memberA ? 'cl-a' : 'cl-b',
            'first_name': who == memberA ? 'Alma' : 'Boris',
            'last_name': 'Stone',
            'role': 'client',
          }
        ])
        ..seed('public_profiles', who, [
          {'id': 'cl-p', 'first_name': 'Petra', 'last_name': 'Quill'}
        ]);
    }
    await signInAs(memberA);
  });
  tearDown(resetFailureSink);

  bool seen(Finder f) => f.evaluate().isNotEmpty;

  Future<void> frames(WidgetTester tester, [int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> show(WidgetTester tester,
      {CoachRelationshipService? service}) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1200, 3000);
    addTearDown(tester.view.reset);
    c = ProviderContainer(overrides: [
      tableTickerProvider.overrideWith((ref, t) => Stream.value(0)),
      currentUserProfileProvider.overrideWith((ref) async => null),
      currentUserDisplayNameProvider.overrideWithValue('Coach'),
      coachNotificationsProvider.overrideWith((ref) => Stream.value(const [])),
      coachSubmittedCheckinsProvider.overrideWith((ref) async => const []),
      coachLeaderboardProvider.overrideWith((ref) async => const []),
      coachTriageSignalsProvider.overrideWith((ref) async => const []),
      if (service != null) coachRelServiceProvider.overrideWithValue(service),
    ]);
    router = GoRouter(initialLocation: '/', routes: [
      GoRoute(path: '/', builder: (_, __) => const CoachDashboardScreen()),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c, child: MaterialApp.router(routerConfig: router)));
    await pumpUntil(tester, () => seen(find.text('Alma Stone')), what: "A's roster");
    await frames(tester);
    await tester.tap(find.text('Requests ●').first);
    await frames(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    for (final h in server.holds.values) {
      if (!h.isCompleted) h.complete();
    }
    await frames(tester);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    router.dispose();
    await tester.pump(const Duration(seconds: 5));
  }

  Future<void> become(WidgetTester tester, String? uid) async {
    await tester.runAsync(() => uid == null ? signOut() : signInAs(uid));
    await pumpUntil(tester, () => c.read(currentUserProvider)?.id == uid,
        what: 'signed in: $uid');
    await frames(tester, 2);
  }


  for (final (label, status, done) in [
    ('Accept', 'active', 'Client accepted!'),
    ('Decline', 'rejected', 'Request declined'),
  ]) {
    group(label, () {
      Future<void> pending(WidgetTester tester,
          {CoachRelationshipService? service}) async {
        await show(tester, service: service);
        await pumpUntil(tester, () => seen(find.text(label)), what: label);
        await frames(tester);
        server.writes.clear();
        server.queries.clear();
        server.calls.clear();
        server.pendingReads.clear();
      }

      VoidCallback tapOf(WidgetTester tester) => tester
          .widget<GestureDetector>(find
              .ancestor(of: find.text(label), matching: find.byType(GestureDetector))
              .first)
          .onTap!;

      Iterable<CoachWrite> patches() =>
          server.writes.where((w) => w.method == 'PATCH');

      void nothingSaidToB() {
        expect(find.byType(SnackBar), findsNothing);
        expect(find.text(done), findsNothing);
        expect(find.textContaining('account changed'), findsNothing);
        expect(find.textContaining('no longer pending'), findsNothing);
      }

      final origin = label == 'Accept'
          ? 'CoachDashboard._approveRequest'
          : 'CoachDashboard._declineRequest';
      final flow = label == 'Accept' ? 'accept request' : 'decline request';
      final method = label == 'Accept' ? 'approveRequest' : 'declineRequest';

      /// Every record, as (origin, error text).
      List<(String, String)> records() =>
          [for (final f in reported) (f.origin, '${f.error}')];

      for (final (what, next) in [('B signs in', memberB), ('A signs out', null)]) {
        testWidgets('$what after A\'s answer was MADE (row matched), before it '
            'is said: recorded once as the outcome not shown, nothing said',
            (tester) async {
          await pending(tester);
          final hold = server.holds['PATCH coach_client_relationships:$memberA'] =
              Completer<void>();
          tapOf(tester)();
          await pumpUntil(tester, () => patches().isNotEmpty, what: 'sent');
          await become(tester, next);
          hold.complete();
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          await frames(tester, 10);
          // The request log: A's row, once, as A; no notice from anyone.
          expect(patches().map((w) => (w.who, w.body['status'])), [(memberA, status)]);
          expect(server.writesTo('notifications'), isEmpty);
          nothingSaidToB();
          expect(
              records(),
              [
                ('CoachRelationshipService.$method.notify',
                    contains('the signed-in account changed')),
                (origin, 'Bad state: $flow outcome not shown: the signed-in account changed'),
              ].map((r) => isA<(String, String)>()
                  .having((x) => x.$1, 'origin', r.$1)
                  .having((x) => x.$2, 'error', r.$2)).toList(),
              reason: 'THE defect: the answer that WAS made was recorded as a '
                  'stop ("report … : the signed-in account changed")');
          await unmount(tester);
        });
      }

      testWidgets('B signs in after A\'s answer matched NO row: the stop is the '
          'single record, no outcome-not-shown record', (tester) async {
        await pending(tester);
        final hold = server.holds['PATCH coach_client_relationships:$memberA'] =
            Completer<void>();
        server.noRows.add('PATCH coach_client_relationships:$memberA');
        tapOf(tester)();
        await pumpUntil(tester, () => patches().isNotEmpty, what: 'sent');
        await become(tester, memberB);
        hold.complete();
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await frames(tester, 10);
        nothingSaidToB();
        expect(records().where((r) => r.$2.contains('account changed')),
            hasLength(1));
        expect(records().where((r) => r.$2.contains('outcome not shown')), isEmpty);
        await unmount(tester);
      });

      testWidgets('A -> B -> A while A\'s answer is in flight: A is back, so A '
          'is told once, nothing recorded as not shown', (tester) async {
        await pending(tester);
        final hold = server.holds['PATCH coach_client_relationships:$memberA'] =
            Completer<void>();
        tapOf(tester)();
        await pumpUntil(tester, () => patches().isNotEmpty, what: 'sent');
        await become(tester, memberB);
        await become(tester, memberA);
        hold.complete();
        await pumpUntil(tester, () => seen(find.text(done)), what: done);
        expect(patches().map((w) => w.who), [memberA]);
        expect(records().where((r) => r.$2.contains('outcome not shown')), isEmpty);
        await unmount(tester);
      });

      testWidgets('fails closed: a refusal that only says the account changed '
          'is never shown, even by the fallback', (tester) async {
        await pending(tester, service: _RefusesPlainly());
        await tester.tap(find.text(label));
        await frames(tester, 10);
        expect(find.byType(SnackBar), findsNothing,
            reason: 'THE defect: the fallback showed StateError.message');
        expect(find.textContaining('account changed'), findsNothing);
        expect(records().where((r) => r.$1 == origin), hasLength(1),
            reason: 'recorded once');
        await unmount(tester);
      });
    });
  }
}
