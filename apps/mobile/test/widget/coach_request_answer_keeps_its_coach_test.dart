import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/core/realtime/realtime.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/checkins/domain/checkin_provider.dart';
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

// P0-FL-62b / FL-62d · the coach dashboard's Accept / Decline answer a request
// as the coach whose list the row was on, at every step: the service is given
// that coach (`expectedUid`), and its refusal for a changed account is said to
// nobody and recorded once.
//
// Coaches A and B each have a pending request from the same prospect (their
// own relationship row). The REAL dashboard and service run against a fake
// PostgREST that answers by the bearer token; nothing mounts an account
// scope, and the screen STAYS mounted across the switch.
//
//  (1) control, the same coach: one PATCH of A's row, as A, guarded on
//      `status=eq.pending` and asking for the row back; one notice to the
//      prospect, as A; A is told — through a token refresh too;
//  (2) B signs in and A's tap lands before any frame: nothing is sent;
//  (3) B signs in while A's answer is in flight and it lands: no notice from
//      anyone, nothing said to B;
//  (4) B signs in (or A signs out) while A's answer is in flight and it
//      matched no row: nothing said to B, the stop recorded ONCE.

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

  @override
  void reset() {
    super.reset();
    noRows.clear();
    queries.clear();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final who = path.startsWith('/auth/v1/') ? '' : TwoMemberPostgrest.who(request);
    final key = '${request.method} ${path.split('/').last}:$who';
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

  Future<void> show(WidgetTester tester) async {
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

  Iterable<AppFailure> accountChanges() =>
      reported.where((f) => '${f.error}'.contains('the signed-in account changed'));

  for (final (label, status, done) in [
    ('Accept', 'active', 'Client accepted!'),
    ('Decline', 'rejected', 'Request declined'),
  ]) {
    group(label, () {
      Future<void> pending(WidgetTester tester) async {
        await show(tester);
        await pumpUntil(tester, () => seen(find.text(label)), what: label);
        await frames(tester);
        server.writes.clear();
        server.queries.clear();
        server.calls.clear();
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

      for (final refresh in [false, true]) {
        testWidgets('(1) control, the same coach${refresh ? ' through a token '
            'refresh while it is sent' : ''}: one answer of A\'s row, as A, and '
            'one notice, as A', (tester) async {
          await pending(tester);
          final hold = refresh
              ? server.holds['PATCH coach_client_relationships:$memberA'] =
                  Completer<void>()
              : null;
          await tester.tap(find.text(label));
          if (hold != null) {
            await pumpUntil(tester, () => patches().isNotEmpty, what: 'sent');
            await tester.runAsync(refreshSession);
            hold.complete();
          }
          await pumpUntil(tester, () => seen(find.text(done)), what: done);
          final patch = patches().single;
          expect((patch.who, patch.body['status']), (memberA, status));
          final q = server.queries
              .singleWhere((w) => w.table == 'coach_client_relationships')
              .q;
          expect(q['id'], 'eq.rel-$memberA');
          expect(q['status'], 'eq.pending');
          expect(q['select'], 'id', reason: 'a 0-row answer must be seen');
          final notice = server.writesTo('notifications').single;
          expect((notice.who, notice.body['recipient_id']), (memberA, 'cl-p'));
          expect(server.writes.where((w) => w.who == memberB), isEmpty);
          expect(accountChanges(), isEmpty);
          await unmount(tester);
        });
      }

      testWidgets("(2) B signs in and A's tap lands before any frame: nothing "
          'is sent, recorded once', (tester) async {
        await pending(tester);
        final tap = tapOf(tester);
        await tester.runAsync(() => signInAs(memberB));
        tap();
        await frames(tester, 10);
        expect(server.writes, isEmpty);
        nothingSaidToB();
        expect(accountChanges(), hasLength(1));
        await unmount(tester);
      });

      testWidgets("(3) B signs in while A's answer is in flight, and it lands: "
          'no notice from anyone, nothing said to B', (tester) async {
        await pending(tester);
        final hold = server.holds['PATCH coach_client_relationships:$memberA'] =
            Completer<void>();
        tapOf(tester)();
        await pumpUntil(tester, () => patches().isNotEmpty, what: 'sent');
        await become(tester, memberB);
        hold.complete();
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await frames(tester, 10);
        expect(patches().map((w) => w.who), [memberA]);
        expect(server.writesTo('notifications'), isEmpty,
            reason: "A's notice went out as B");
        nothingSaidToB();
        expect(accountChanges(), isNotEmpty);
        await unmount(tester);
      });

      for (final (what, next) in [('B signs in', memberB), ('A signs out', null)]) {
        testWidgets("(4) $what while A's answer is in flight, and it matched no "
            'row: nothing said, the stop recorded once', (tester) async {
          await pending(tester);
          final hold = server.holds['PATCH coach_client_relationships:$memberA'] =
              Completer<void>();
          server.noRows.add('PATCH coach_client_relationships:$memberA');
          tapOf(tester)();
          await pumpUntil(tester, () => patches().isNotEmpty, what: 'sent');
          await become(tester, next);
          hold.complete();
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          await frames(tester, 10);
          expect(server.writes.map((w) => (w.who, w.method)), [(memberA, 'PATCH')]);
          nothingSaidToB();
          expect(accountChanges(), hasLength(1),
              reason: 'THE defect: the one stop was recorded '
                  '${accountChanges().length} times');
          await unmount(tester);
        });
      }

      testWidgets('control: A stays and the answer matched no row: A is told',
          (tester) async {
        await pending(tester);
        server.noRows.add('PATCH coach_client_relationships:$memberA');
        await tester.tap(find.text(label));
        await pumpUntil(tester,
            () => seen(find.text('That request is no longer pending — nothing was changed.')),
            what: 'the refusal');
        expect(find.text(done), findsNothing);
        expect(server.writesTo('notifications'), isEmpty);
        await unmount(tester);
      });
    });
  }
}
