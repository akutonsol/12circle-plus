import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/core/realtime/realtime.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/checkins/domain/checkin_provider.dart';
import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart';
import 'package:circle_fitness/features/dashboard/domain/coach_triage_provider.dart';
import 'package:circle_fitness/features/dashboard/domain/still_reading.dart';
import 'package:circle_fitness/features/dashboard/presentation/client_detail_screen.dart';
import 'package:circle_fitness/features/dashboard/presentation/coach_dashboard_screen.dart';
import 'package:circle_fitness/features/messaging/domain/messaging_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../support/pump_until.dart';
import '../support/two_coach_postgrest.dart';

// P0-FL-59f · the coach dashboard stays mounted across a sign-in switch (web),
// and Riverpod keeps the previous coach's rows through the next one's read and
// its failure. So coach B was shown coach A's clients — names, emails, risk —
// and their check-ins, workouts and notifications; B's tap on Message could be
// answered into A's conversation; and A's typed invite went out as B.
//
// The screen is mounted WITHOUT the app-root account scope and kept mounted.
//
// HOW TO SEE IT FAIL: `git checkout a82f993 -- lib/features`.

/// The realtime end of the socket: answers joins, pushes nothing.
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

const _rels = 'GET coach_client_relationships';

/// A live change to a table: the reads that watch it run again.
final _tick = StateProvider<int>((ref) => 0);

void main() {
  late TwoCoachPostgrest server;
  late ProviderContainer c;
  late GoRouter router;
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = TwoCoachPostgrest();
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

  void roster(String who, String id, String first, String last) {
    server
      ..seed('coach_client_relationships', who, [
        {'client_id': id, 'status': 'active'}
      ])
      ..seed('user_profiles', who, [
        {
          'id': id,
          'first_name': first,
          'last_name': last,
          'email': '$first@client.example'.toLowerCase(),
          'role': 'client',
          'risk_level': 'high',
        }
      ])
      ..seed('weekly_checkins', who, [
        {'user_id': id, 'status': 'submitted', 'mood': 3, 'stress_level': 4}
      ])
      ..seed('workout_sessions', who, [
        {
          'user_id': id,
          'workout_title': 'Squats of $first',
          'completed_at': DateTime.now().toUtc().toIso8601String(),
          'duration_seconds': 1800,
        }
      ]);
  }

  setUp(() async {
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
    roster(memberA, 'cl-a', 'Alma', 'Stone');
    roster(memberB, 'cl-b', 'Boris', 'Reed');
    await signInAs(memberA);
  });
  tearDown(resetFailureSink);

  Future<void> frames(WidgetTester tester, [int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Finder alma() => find.text('Alma Stone');
  Finder boris() => find.text('Boris Reed');
  bool seen(Finder f) => f.evaluate().isNotEmpty;

  void nothingOfA() {
    expect(alma(), findsNothing, reason: "THE defect: A's client was shown");
    expect(find.text('alma@client.example'), findsNothing);
    expect(find.textContaining('HIGH RISK'), findsNothing,
        reason: "A's clients' risk");
  }

  /// [realNotifications]: the real live stream (over the fake socket).
  Future<void> show(WidgetTester tester,
      {bool realNotifications = false, List<Override> more = const []}) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1200, 3000);
    addTearDown(tester.view.reset);
    c = ProviderContainer(overrides: [
      tableTickerProvider
          .overrideWith((ref, t) => Stream.value(ref.watch(_tick))),
      currentUserProfileProvider.overrideWith((ref) async => null),
      currentUserDisplayNameProvider.overrideWithValue('Coach'),
      if (!realNotifications)
        coachNotificationsProvider.overrideWith((ref) => Stream.value(const [])),
      coachSubmittedCheckinsProvider.overrideWith((ref) async => const []),
      coachLeaderboardProvider.overrideWith((ref) async => const []),
      coachTriageSignalsProvider.overrideWith((ref) async => const []),
      ...more,
    ]);
    router = GoRouter(initialLocation: '/', routes: [
      GoRoute(path: '/', builder: (_, __) => const CoachDashboardScreen()),
      GoRoute(
          path: '/chat',
          builder: (_, __) => const Scaffold(body: Text('THE CHAT'))),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c, child: MaterialApp.router(routerConfig: router)));
    await pumpUntil(tester, () => seen(alma()), what: "A's roster");
    await frames(tester);
    server.calls.clear();
  }

  Future<void> unmount(WidgetTester tester, {bool realtime = false}) async {
    if (realtime) {
      for (final h in server.holds.values) {
        if (!h.isCompleted) h.complete();
      }
      await frames(tester);
    }
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    router.dispose();
    await tester.pump(const Duration(seconds: 1));
    if (realtime) {
      for (var i = 0; i < 2; i++) {
        await Supabase.instance.client.removeAllChannels();
        await Supabase.instance.client.realtime.disconnect();
        await tester.pump(const Duration(minutes: 2));
      }
    }
    await tester.pump(const Duration(seconds: 5));
  }

  Future<void> become(WidgetTester tester, String? uid) async {
    await tester
        .runAsync(() => uid == null ? signOut() : signInAs(uid));
    await pumpUntil(tester, () => c.read(currentUserProvider)?.id == uid,
        what: 'signed in: $uid');
    await frames(tester, 2);
  }

  Future<void> openTab(WidgetTester tester, String tab) async {
    await tester.tap(find.text(tab).first);
    await frames(tester);
  }

  group('A-07 the roster', () {
    testWidgets("B's read pending: nothing of A, and no 'none'; then B's own",
        (tester) async {
      await show(tester);
      expect(find.textContaining('HIGH RISK'), findsWidgets,
          reason: 'premise');
      final hold = server.holds['$_rels:$memberB'] = Completer<void>();
      await become(tester, memberB);
      nothingOfA();
      expect(find.text('No clients found'), findsNothing);
      expect(find.text('—'), findsNWidgets(4),
          reason: 'no count is known for B yet');
      await openTab(tester, 'Check-Ins');
      expect(alma(), findsNothing);
      expect(find.text('No check-ins today'), findsNothing);
      await openTab(tester, 'Workouts');
      expect(alma(), findsNothing);
      expect(find.textContaining('Squats of Alma'), findsNothing);
      await openTab(tester, 'Clients');
      hold.complete();
      await pumpUntil(tester, () => seen(boris()), what: "B's roster");
      nothingOfAButBs();
      await unmount(tester);
    });

    testWidgets("B's read failed: B's failure, never A's data", (tester) async {
      await show(tester);
      server.fails.add('$_rels:$memberB');
      await become(tester, memberB);
      await pumpUntil(tester,
          () => seen(find.text('Could not load your clients')), what: 'failure');
      nothingOfA();
      expect(find.text('—'), findsNWidgets(4));
      expect(find.textContaining('SECRET_TABLE'), findsNothing);
      expect(find.textContaining('may be out of date'), findsNothing,
          reason: 'nothing of B is shown to be out of date');
      await unmount(tester);
    });

    testWidgets("A's late re-read lands on nobody: before B's own, and after",
        (tester) async {
      for (final afterB in [false, true]) {
        await tester.runAsync(() => signInAs(memberA));
        await show(tester);
        final late = server.holds['$_rels:$memberA'] = Completer<void>();
        c.invalidate(coachClientsProvider);
        await pumpUntil(tester, () => server.count('$_rels:$memberA') > 0,
            what: "A's re-read sent");
        final hold = server.holds['$_rels:$memberB'] = Completer<void>();
        await become(tester, memberB);
        if (afterB) {
          hold.complete();
          await pumpUntil(tester, () => seen(boris()), what: "B's roster");
        }
        late.complete();
        await frames(tester);
        expect(alma(), findsNothing, reason: 'afterB: $afterB');
        if (!afterB) hold.complete();
        await pumpUntil(tester, () => seen(boris()), what: "B's roster");
        expect(alma(), findsNothing);
        server.holds.clear();
        await unmount(tester);
      }
    });

    testWidgets('sign-out -> sign-in as B', (tester) async {
      await show(tester);
      await become(tester, null);
      nothingOfA();
      server.holds['$_rels:$memberB'] = Completer<void>();
      await become(tester, memberB);
      nothingOfA();
      expect(find.text('No clients found'), findsNothing);
      await unmount(tester);
    });

    testWidgets('signed out, B signs in and B\'s read fails: not "no clients"',
        (tester) async {
      await show(tester);
      await become(tester, null);
      server.fails.add('$_rels:$memberB');
      await become(tester, memberB);
      await pumpUntil(tester,
          () => seen(find.text('Could not load your clients')), what: 'failure');
      expect(find.text('No clients found'), findsNothing);
      await unmount(tester);
    });

    testWidgets('control: a coach with no clients is told so (a real empty)',
        (tester) async {
      server.seed('coach_client_relationships', memberB, []);
      await show(tester);
      await become(tester, memberB);
      await pumpUntil(tester, () => seen(find.text('No clients found')),
          what: 'the true answer');
      // A live tick re-reads it; an answered empty does not go back to loading.
      server.holds['$_rels:$memberB'] = Completer<void>();
      c.invalidate(coachClientsProvider);
      await frames(tester, 2);
      expect(find.text('No clients found'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('control: the same coach keeps their clients through a live '
        're-read, and through one that fails — and is told', (tester) async {
      await show(tester);
      final hold = server.holds['$_rels:$memberA'] = Completer<void>();
      c.invalidate(coachClientsProvider);
      await frames(tester, 2);
      expect(alma(), findsOneWidget, reason: 'no flicker');
      server.fails.add('$_rels:$memberA');
      hold.complete();
      await pumpUntil(tester,
          () => seen(find.textContaining('may be out of date')),
          what: 'the failed refresh said');
      expect(alma(), findsOneWidget,
          reason: "the coach's true rows were replaced by a failure");
      expect(find.text("Couldn't load the latest client activity"),
          findsOneWidget);
      expect(find.textContaining('SECRET_TABLE'), findsNothing);
      server
        ..fails.clear()
        ..holds.clear();
      await tester.tap(find.text('Try again'));
      await pumpUntil(tester,
          () => !seen(find.textContaining('may be out of date')),
          what: 'the retry');
      expect(alma(), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('the failed-refresh notice does not overflow at 2x on a small '
        'phone', (tester) async {
      await show(tester);
      tester.view.physicalSize = const Size(360, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final overflows = <String>[];
      final original = FlutterError.onError;
      FlutterError.onError = (d) => overflows.add(d.exceptionAsString());
      final bool said;
      try {
        server.fails.add('$_rels:$memberA');
        c.invalidate(coachClientsProvider);
        await frames(tester, 12);
        said = seen(find.textContaining('may be out of date'));
      } finally {
        FlutterError.onError = original;
      }
      expect(said, isTrue, reason: 'the notice');
      expect(overflows.where((e) => e.contains('on the bottom')), isEmpty);
      await unmount(tester);
    });

    Finder notice() => find.textContaining('may be out of date');
    Finder retry() => find.ancestor(
        of: find.byType(CircularProgressIndicator),
        matching: find.byType(TextButton));

    /// [request] fails for A from now on, over rows A holds.
    Future<void> failed(WidgetTester tester, String request,
        List<ProviderOrFamily> reads) async {
      server.fails.add('$request:$memberA');
      for (final r in reads) {
        c.invalidate(r);
      }
      await pumpUntil(tester,
          () => reported.any((f) => f.origin.startsWith('CoachDashboardScreen.')),
          what: 'the failure');
      await frames(tester);
    }

    for (final (how, reread) in [
      ('its own Try again', null),
      ('a live re-read', () => c.read(_tick.notifier).state++),
    ]) {
      testWidgets('the notice stays through $how, busy, and goes only when '
          'that answers', (tester) async {
        await show(tester);
        await failed(tester, 'GET user_profiles', [coachClientsProvider]);
        expect(notice(), findsOneWidget, reason: 'premise');
        final hold = server.holds[
            how == 'a live re-read' ? '$_rels:$memberA'
                : 'GET user_profiles:$memberA'] = Completer<void>();
        if (reread == null) {
          await tester.tap(find.text('Try again'));
        } else {
          reread();
        }
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          expect(notice(), findsOneWidget,
              reason: 'THE defect: it dropped out while it was read again');
        }
        expect(retry(), findsOneWidget, reason: 'it says it is busy');
        expect(tester.widget<TextButton>(retry()).onPressed, isNull,
            reason: 'and cannot fire twice');
        expect(find.bySemanticsLabel('Retrying'), findsOneWidget);
        expect(alma(), findsOneWidget);
        server.fails.clear();
        hold.complete();
        await pumpUntil(tester, () => !seen(notice()), what: 'the answer');
        expect(alma(), findsOneWidget);
        await unmount(tester);
      });
    }

    testWidgets('the notice is on the tabs that show those rows, only',
        (tester) async {
      await show(tester);
      await failed(tester, 'GET workout_sessions', [clientWorkoutLogsProvider]);
      const says = {
        'Clients': true,
        'Requests': false,
        'Check-Ins': false, // its rows and their names were read
        'Workouts': true,
        'Leaderboard': false,
      };
      for (final e in says.entries) {
        await tester.ensureVisible(find.text(e.key).first);
        await openTab(tester, e.key);
        expect(notice(), e.value ? findsOneWidget : findsNothing,
            reason: e.key);
      }
      server.fails.clear();
      await failedRosterIsSaid(tester, server, c, openTab, frames);
      await unmount(tester);
    });

    testWidgets('each failed read is recorded once, however often it is drawn',
        (tester) async {
      await show(tester);
      server.fails.add('$_rels:$memberA');
      c
        ..invalidate(coachClientsProvider)
        ..invalidate(clientCheckinsProvider)
        ..invalidate(clientWorkoutLogsProvider);
      int times(String name) => reported
          .where((f) => f.origin == 'CoachDashboardScreen.$name')
          .length;
      await pumpUntil(
          tester,
          () => ['clients', 'checkins', 'workouts'].every((n) => times(n) > 0),
          what: 'the three failures recorded');
      await frames(tester, 12);
      await openTab(tester, 'Workouts');
      for (final n in ['clients', 'checkins', 'workouts']) {
        expect(times(n), 1, reason: n);
      }
      await unmount(tester);
    });

    testWidgets("B's check-ins or workouts still out: none of A's stand in for "
        'them, though B coaches the same client', (tester) async {
      server
        ..seed('workout_sessions', memberA, [
          for (var i = 0; i < 3; i++)
            {
              'user_id': 'cl-a',
              'workout_title': 'Squats of Alma',
              'completed_at': DateTime.now().toUtc().toIso8601String(),
              'duration_seconds': 1800,
            }
        ])
        ..seed('coach_client_relationships', memberB, [
          {'client_id': 'cl-a', 'status': 'active'}
        ])
        ..seed('user_profiles', memberB, [
          {'id': 'cl-a', 'first_name': 'Boris', 'last_name': 'Reed',
            'email': 'boris@client.example', 'role': 'client'}
        ])
        ..seed('weekly_checkins', memberB, [
          {'user_id': 'cl-a', 'status': 'submitted', 'mood': 5,
            'stress_level': 1, 'energy_level': 5}
        ]);
      await show(tester);
      expect(find.text('⚠️ Needs Attention'), findsOneWidget,
          reason: "premise: A's answer about the client");
      expect(find.text('3'), findsWidgets, reason: 'premise: 3 workouts');
      final checkins =
          server.holds['GET weekly_checkins:$memberB'] = Completer<void>();
      server.holds['GET workout_sessions:$memberB'] = Completer<void>();
      await become(tester, memberB);
      await pumpUntil(tester, () => seen(boris()), what: "B's roster");
      await frames(tester);
      expect(find.text('No check-in'), findsOneWidget,
          reason: "THE defect: A's check-in was shown on B's client");
      await openTab(tester, 'Check-Ins');
      expect(find.text('4/5'), findsNothing, reason: "A's stress figure");
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      await openTab(tester, 'Workouts');
      expect(find.textContaining('Squats of Alma'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      await openTab(tester, 'Clients');
      checkins.complete();
      await pumpUntil(tester, () => seen(find.text('✓ Checked In')),
          what: "B's own check-in");
      expect(find.text('3'), findsNothing,
          reason: "THE defect: A's workouts were counted on B's client");
      await unmount(tester);
    });

    for (final (table, tab, message, others) in [
      ('weekly_checkins', 'Check-Ins', 'Could not load check-ins',
          {'Workouts': 'Squats of Boris'}),
      ('workout_sessions', 'Workouts', 'Could not load workouts',
          {'Check-Ins': 'Boris Reed'}),
      ('user_profiles', 'Clients', 'Could not load your clients',
          {'Workouts': 'Squats of Boris'}),
    ]) {
      testWidgets("only B's $table fails: its tab says so, the others are B's "
          'own, and nothing is A\'s', (tester) async {
        await show(tester);
        server.fails.add('GET $table:$memberB');
        await become(tester, memberB);
        await openTab(tester, tab);
        await pumpUntil(tester, () => seen(find.text(message)),
            what: "B's failure");
        expect(alma(), findsNothing);
        expect(find.textContaining('Squats of Alma'), findsNothing);
        expect(notice(), findsNothing,
            reason: 'nothing of B is shown to be out of date');
        for (final e in others.entries) {
          await openTab(tester, e.key);
          await pumpUntil(tester, () => seen(find.text(e.value)),
              what: "B's own ${e.key}");
          expect(alma(), findsNothing);
          expect(find.textContaining('Squats of Alma'), findsNothing);
        }
        await unmount(tester);
      });
    }

    testWidgets("A taps a client and B signs in before the page's first frame, "
        'or before the tap: it is never drawn, nothing is read', (tester) async {
      for (final tapFirst in [true, false]) {
        await tester.runAsync(() => signInAs(memberA));
        await show(tester);
        final tap = tester
            .widget<GestureDetector>(find
                .ancestor(of: alma(), matching: find.byType(GestureDetector))
                .first)
            .onTap!;
        if (tapFirst) tap();
        await tester.runAsync(() => signInAs(memberB));
        if (!tapFirst) tap();
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          expect(
              find.descendant(
                  of: find.byType(ClientDetailScreen), matching: alma()),
              findsNothing,
              reason: 'tapFirst: $tapFirst');
        }
        expect(server.calls.where((k) => k.contains('get_client_assessment')),
            isEmpty);
        if (!tapFirst) {
          expect(find.byType(ClientDetailScreen), findsNothing);
          expect(reported.map((f) => f.origin),
              contains('CoachDashboard.openClient'));
        }
        await unmount(tester);
      }
    });

    testWidgets('control: A taps a client and the page opens as A',
        (tester) async {
      await show(tester);
      await tester.tap(alma());
      await pumpUntil(
          tester,
          () => server.count('POST rpc/get_client_assessment:$memberA') == 1,
          what: "A's page");
      await frames(tester);
      expect(find.descendant(
          of: find.byType(ClientDetailScreen), matching: alma()), findsWidgets);
      await unmount(tester);
    });

    testWidgets('control: a refreshed token re-reads nothing and hides nothing',
        (tester) async {
      await show(tester);
      final before = c.read(currentUserProvider);
      await tester.runAsync(refreshSession);
      await pumpUntil(tester, () => c.read(currentUserProvider) != before,
          what: 'the same coach as a new User');
      await frames(tester);
      expect(alma(), findsOneWidget);
      expect(server.count('$_rels:$memberA'), 0,
          reason: 'a refreshed token is the same coach');
      await unmount(tester);
    });

    testWidgets('control: the same coach signing out and back in sees theirs',
        (tester) async {
      await show(tester);
      await become(tester, null);
      await become(tester, memberA);
      await pumpUntil(tester, () => seen(alma()), what: "A's own roster");
      await unmount(tester);
    });

    testWidgets("A's pending-request dot and A's failure are not B's",
        (tester) async {
      server
        ..seed('coach_client_relationships', memberA, [
          {'client_id': 'cl-a', 'status': 'active'},
          {'client_id': 'cl-p', 'id': 'rel-1', 'status': 'pending'},
        ])
        ..seed('public_profiles', memberA, [
          {'id': 'cl-a', 'first_name': 'Alma', 'last_name': 'Stone'}
        ]);
      await show(tester);
      expect(find.text('Requests ●'), findsOneWidget, reason: 'premise');
      server.holds['$_rels:$memberB'] = Completer<void>();
      await become(tester, memberB);
      expect(find.text('Requests ●'), findsNothing,
          reason: "THE defect: A's request shown on B's tab");
      await unmount(tester);
    });

    testWidgets("A's failed requests read is not B's, while B's is out",
        (tester) async {
      server
        ..seed('coach_client_relationships', memberA, [
          {'client_id': 'cl-a', 'status': 'active'},
          {'client_id': 'cl-p', 'id': 'rel-1', 'status': 'pending'},
        ])
        ..fails.add('GET public_profiles:$memberA'); // with nothing held
      await show(tester);
      Finder failedTab() => find.descendant(
          of: find.byType(TabBar), matching: find.byIcon(Icons.error_outline));
      expect(failedTab(), findsOneWidget, reason: 'premise');
      server.holds['$_rels:$memberB'] = Completer<void>();
      await become(tester, memberB);
      expect(failedTab(), findsNothing,
          reason: "THE defect: A's failure was said on B's tab");
      await openTab(tester, 'Requests');
      expect(find.text("Couldn't load requests"), findsNothing);
      await unmount(tester);
    });
  });

  group('A-07 answering a request', () {
    for (final (label, status, origin, done) in [
      ('Accept', 'active', 'CoachDashboard._approveRequest', 'Client accepted!'),
      ('Decline', 'rejected', 'CoachDashboard._declineRequest',
          'Request declined'),
    ]) {
      Future<void> pending(WidgetTester tester,
          {List<Override> more = const []}) async {
        for (final who in [memberA, memberB]) {
          server
            ..seed('coach_client_relationships', who, [
              {'client_id': who == memberA ? 'cl-a' : 'cl-b',
                'status': 'active'},
              {'client_id': 'cl-p', 'id': 'rel-$who', 'status': 'pending'},
            ])
            ..seed('public_profiles', who, [
              {'id': 'cl-p', 'first_name': 'Petra', 'last_name': 'Quill'}
            ]);
        }
        await show(tester, more: more);
        await openTab(tester, 'Requests ●');
        await pumpUntil(tester, () => seen(find.text(label)), what: label);
        await frames(tester);
      }

      VoidCallback tapOf(WidgetTester tester) => tester
          .widget<GestureDetector>(find
              .ancestor(
                  of: find.text(label), matching: find.byType(GestureDetector))
              .first)
          .onTap!;

      List<CoachWrite> patches() => [
            for (final w in server.writes) if (w.method == 'PATCH') w
          ];

      for (final next in [memberB, null]) {
        testWidgets(
            "$label on A's row, tapped after ${next == null ? 'A signed out' : 'B signed in'} "
            'and before any frame: nothing is sent', (tester) async {
          await pending(tester);
          final tap = tapOf(tester);
          await tester
              .runAsync(() => next == null ? signOut() : signInAs(next));
          tap();
          await frames(tester, 10);
          expect(server.writes, isEmpty,
              reason: "THE defect: A's request was answered by $next");
          expect(find.byType(SnackBar), findsNothing);
          expect(reported.map((f) => f.origin), contains(origin));
          await unmount(tester);
        });
      }

      testWidgets("$label on A's row once the list in hand is already B's, "
          'still undrawn: nothing is sent', (tester) async {
        await pending(tester);
        final tap = tapOf(tester);
        await tester.runAsync(() async {
          await signInAs(memberB);
          for (var i = 0;
              i < 400 &&
                  ownerOfHeld(c.read(pendingRequestsProvider)) != memberB;
              i++) {
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
        });
        expect(ownerOfHeld(c.read(pendingRequestsProvider)), memberB,
            reason: 'premise');
        tap();
        await frames(tester, 10);
        expect(server.writes, isEmpty);
        expect(find.byType(SnackBar), findsNothing);
        await unmount(tester);
      });

      testWidgets('$label on a row whose coach is not known: nothing is sent',
          (tester) async {
        await pending(tester, more: [
          pendingRequestsProvider.overrideWith((ref) async => [
                {
                  'id': 'rel-x',
                  'client_id': 'cl-p',
                  'profile': <String, dynamic>{},
                },
              ]),
        ]);
        for (final uid in [memberA, null]) {
          if (uid == null) await tester.runAsync(signOut);
          tapOf(tester)();
          await frames(tester);
          expect(server.writes, isEmpty, reason: 'as $uid');
        }
        expect(find.byType(SnackBar), findsNothing);
        await unmount(tester);
      });

      testWidgets('$label in flight when B signs in, then done: nothing is '
          'said to B, no list of B is re-read for it', (tester) async {
        await pending(tester);
        final hold =
            server.holds['PATCH coach_client_relationships:$memberA'] =
                Completer<void>();
        tapOf(tester)();
        await pumpUntil(tester, () => patches().isNotEmpty, what: 'sent');
        await become(tester, memberB);
        await pumpUntil(tester, () => seen(find.text('Petra Quill')),
            what: "B's own requests");
        await frames(tester);
        server.calls.clear();
        hold.complete();
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await frames(tester, 10);
        expect(patches().map((w) => w.who), [memberA]);
        expect(find.byType(SnackBar), findsNothing,
            reason: "THE defect: A's answer was said to B");
        expect(server.calls.where((k) => k.startsWith('GET')), isEmpty);
        // N1, the KNOWN gap (coach_relationship_service, P0-FL-59d's): the
        // client's notice that follows goes out as B. Nothing else may.
        expect(
            server.writes.where((w) => w.who == memberB).every(
                (w) => w.path.endsWith('/notifications')),
            isTrue);
        expect(reported.map((f) => f.origin), contains(origin));
        await unmount(tester);
      });

      testWidgets('$label in flight when B signs in, then refused: nothing is '
          'said to B, and it is recorded', (tester) async {
        await pending(tester);
        final hold =
            server.holds['PATCH coach_client_relationships:$memberA'] =
                Completer<void>();
        tapOf(tester)();
        await pumpUntil(tester, () => patches().isNotEmpty, what: 'sent');
        server.fails.add('PATCH coach_client_relationships:$memberA');
        await become(tester, memberB);
        await frames(tester);
        hold.complete();
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await frames(tester, 10);
        expect(find.byType(SnackBar), findsNothing,
            reason: "THE defect: A's failure was said to B");
        expect(server.writes.map((w) => w.who), [memberA]);
        expect(reported.map((f) => f.origin), contains(origin));
        await unmount(tester);
      });

      testWidgets('control: A stays (token refreshed): $label is sent once, as '
          'A, and said', (tester) async {
        await pending(tester);
        final before = c.read(currentUserProvider);
        await tester.runAsync(refreshSession);
        await pumpUntil(tester, () => c.read(currentUserProvider) != before,
            what: 'the same coach');
        await frames(tester);
        await tester.tap(find.text(label));
        await pumpUntil(tester, () => seen(find.text(done)), what: done);
        final w = patches().single;
        expect((w.who, w.body['status']), (memberA, status));
        expect(server.writesTo('notifications').single.who, memberA);
        await unmount(tester);
      });

      testWidgets('control: A stays and $label is refused: A is told',
          (tester) async {
        await pending(tester);
        server.fails.add('PATCH coach_client_relationships:$memberA');
        await tester.tap(find.text(label));
        await pumpUntil(tester, () => seen(find.byType(SnackBar)),
            what: 'the failure');
        expect(find.text(done), findsNothing);
        await unmount(tester);
      });
    }
  });

  group('A-07 notifications', () {
    void notes() {
      server
        ..seed('notifications', memberA, [
          {
            'id': 'n-a',
            'recipient_id': memberA,
            'title': 'Alma signed up',
            'body': '',
            'read': false,
            'created_at': '2026-11-25T10:00:00Z',
          }
        ])
        ..seed('notifications', memberB, []);
    }

    Future<void> openBell(WidgetTester tester) async {
      await pumpUntil(
          tester, () => c.read(unreadNotificationCountProvider) == 1,
          what: "A's unread");
      await frames(tester, 2);
      await tester.tap(find.byIcon(Icons.notifications_outlined));
      await frames(tester);
      expect(find.text('Alma signed up'), findsOneWidget, reason: 'premise');
    }

    testWidgets("A's bell count and open sheet are not B's", (tester) async {
      notes();
      await show(tester, realNotifications: true);
      await openBell(tester);
      server.holds['GET notifications:$memberB'] = Completer<void>();
      await become(tester, memberB);
      expect(find.text('Alma signed up'), findsNothing,
          reason: "THE defect: A's notification was shown to B");
      await frames(tester, 10);
      expect(find.text('Mark all read'), findsNothing);
      expect(find.text('Notifications'), findsNothing,
          reason: "A's sheet closes");
      expect(c.read(unreadNotificationCountProvider), 0);
      expect(server.writes, isEmpty);
      await unmount(tester, realtime: true);
    });

    testWidgets("'Clear all' on A's sheet, fired after B signed in and before "
        "any frame, clears nobody's", (tester) async {
      notes();
      await show(tester, realNotifications: true);
      await openBell(tester);
      final clear = tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Clear all'))
          .onPressed!;
      await tester.runAsync(() => signInAs(memberB));
      clear();
      await frames(tester);
      expect(server.writesTo('notifications'), isEmpty,
          reason: "THE defect: B's notifications were deleted from A's sheet");
      expect(reported.map((f) => f.origin),
          contains('CoachNotificationsSheet.clearAll'));
      await unmount(tester, realtime: true);
    });

    testWidgets('A signs out: the open sheet closes', (tester) async {
      notes();
      await show(tester, realNotifications: true);
      await openBell(tester);
      await become(tester, null);
      expect(find.text('Alma signed up'), findsNothing);
      await frames(tester, 10);
      expect(find.text('Notifications'), findsNothing);
      await unmount(tester, realtime: true);
    });

    for (final gone in ['B signs in', 'A swipes the sheet away']) {
      testWidgets("'Mark all read' in flight when $gone: one write, A's, and "
          'nothing is thrown', (tester) async {
        notes();
        await show(tester, realNotifications: true);
        await openBell(tester);
        final hold = server.holds['PATCH notifications:$memberA'] =
            Completer<void>();
        await tester.tap(find.text('Mark all read'));
        await pumpUntil(tester, () => server.writes.isNotEmpty, what: 'sent');
        if (gone == 'B signs in') {
          await become(tester, memberB);
        } else {
          Navigator.of(tester.element(find.text('Mark all read'))).pop();
        }
        await frames(tester, 10);
        expect(find.text('Notifications'), findsNothing, reason: 'premise');
        hold.complete();
        await frames(tester, 10);
        expect(tester.takeException(), isNull,
            reason: 'THE defect: the sheet was used after it was gone');
        expect(server.writes.map((w) => w.who), [memberA]);
        expect(
            reported.map((f) => f.origin),
            gone == 'B signs in'
                ? contains('CoachNotificationsSheet.markAllRead')
                : isNot(contains('CoachNotificationsSheet.markAllRead')));
        await unmount(tester, realtime: true);
      });
    }

    testWidgets("A's failed read is not 'couldn't check' for B while B's is out",
        (tester) async {
      notes();
      server.fails.add('GET notifications:$memberA');
      await show(tester, realNotifications: true);
      await pumpUntil(
          tester, () => c.read(unreadNotificationCountProvider) == null,
          what: "A's failure");
      server.holds['GET notifications:$memberB'] = Completer<void>();
      await become(tester, memberB);
      expect(c.read(unreadNotificationCountProvider), 0);
      await unmount(tester, realtime: true);
    });

    testWidgets("B's failed read is B's unknown", (tester) async {
      notes();
      await show(tester, realNotifications: true);
      await pumpUntil(
          tester, () => c.read(unreadNotificationCountProvider) == 1,
          what: "A's unread");
      server.fails.add('GET notifications:$memberB');
      await become(tester, memberB);
      await pumpUntil(
          tester, () => c.read(unreadNotificationCountProvider) == null,
          what: "B's failure");
      await unmount(tester, realtime: true);
    });

    testWidgets('control: a refreshed token keeps the sheet and its rows',
        (tester) async {
      notes();
      await show(tester, realNotifications: true);
      await openBell(tester);
      final before = c.read(currentUserProvider);
      await tester.runAsync(refreshSession);
      await pumpUntil(tester, () => c.read(currentUserProvider) != before,
          what: 'the same coach');
      await frames(tester);
      expect(find.text('Alma signed up'), findsOneWidget);
      await tester.tap(find.text('Mark all read'));
      await pumpUntil(tester, () => server.writes.isNotEmpty, what: 'the write');
      expect(server.writes.single.who, memberA);
      await unmount(tester, realtime: true);
    });
  });

  group('A-05 Message', () {
    const rpc = 'POST rpc/get_or_create_conversation';

    testWidgets('A taps Message and B signs in before the answer: no '
        'conversation is opened for B', (tester) async {
      await show(tester);
      final hold = server.holds['$rpc:$memberA'] = Completer<void>();
      await tester.tap(find.text('Message').first);
      await pumpUntil(tester, () => server.count('$rpc:$memberA') == 1,
          what: "A's request");
      server.holds['$_rels:$memberB'] = Completer<void>();
      await become(tester, memberB);
      hold.complete();
      await frames(tester);
      expect(c.read(selectedConversationProvider), isNull,
          reason: "THE defect: A's client and conversation became B's chat");
      expect(find.text('THE CHAT'), findsNothing);
      expect(reported.map((f) => f.origin), contains('CoachDashboard.message'));
      expect(server.count('$rpc:$memberB'), 0);
      await unmount(tester);
    });

    for (final listIsBs in [false, true]) {
      testWidgets(
          "tapped on A's row after B signed in and before any frame"
          "${listIsBs ? ", the list in hand already B's" : ''}: nothing is asked",
          (tester) async {
        await show(tester);
        final tap = tester
            .widget<GestureDetector>(find
                .ancestor(
                    of: find.text('Message').first,
                    matching: find.byType(GestureDetector))
                .first)
            .onTap!;
        await tester.runAsync(() async {
          await signInAs(memberB);
          for (var i = 0;
              listIsBs &&
                  i < 400 &&
                  ownerOfHeld(c.read(coachClientsProvider)) != memberB;
              i++) {
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
        });
        if (listIsBs) {
          expect(ownerOfHeld(c.read(coachClientsProvider)), memberB,
              reason: 'premise');
        }
        tap();
        await frames(tester, 10);
        expect(server.calls.where((k) => k.contains('get_or_create')), isEmpty,
            reason: "THE defect: A's client's conversation was asked for by B");
        expect(c.read(selectedConversationProvider), isNull);
        expect(reported.map((f) => f.origin),
            contains('CoachDashboard.message'));
        await unmount(tester);
      });
    }

    testWidgets('A taps Message, B signs in and the request then fails: no '
        'chat, nothing said', (tester) async {
      await show(tester);
      final hold = server.holds['$rpc:$memberA'] = Completer<void>();
      server.fails.add('$rpc:$memberA');
      await tester.tap(find.text('Message').first);
      await pumpUntil(tester, () => server.count('$rpc:$memberA') == 1,
          what: "A's request");
      await become(tester, memberB);
      hold.complete();
      await frames(tester, 10);
      expect(c.read(selectedConversationProvider), isNull);
      expect(find.text('THE CHAT'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
      expect(reported.map((f) => f.origin), contains('CoachDashboard.message'));
      await unmount(tester);
    });

    testWidgets('control: A stays, and the chat opens', (tester) async {
      await show(tester);
      await tester.tap(find.text('Message').first);
      await pumpUntil(tester, () => seen(find.text('THE CHAT')), what: 'chat');
      expect(c.read(selectedConversationProvider)?['id'], 'conv-of-$memberA');
      await unmount(tester);
    });
  });

  group('W22 the invite', () {
    Future<void> type(WidgetTester tester) async {
      await openTab(tester, 'Requests');
      await tester.tap(find.text('Invite Client by Email'));
      await frames(tester);
      await tester.enterText(
          find.byType(TextField).last, 'prospect@client.example');
    }

    testWidgets("A's typed invite: the sheet closes for B, nothing is sent",
        (tester) async {
      await show(tester);
      await type(tester);
      await become(tester, memberB);
      expect(find.text('prospect@client.example'), findsNothing,
          reason: "THE defect: A's draft stayed on screen for B");
      await frames(tester, 10);
      expect(find.text('Send Invite'), findsNothing);
      expect(server.writesTo('coach_invites'), isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      await unmount(tester);
    });

    testWidgets("A signs out: the sheet closes, nothing is sent",
        (tester) async {
      await show(tester);
      await type(tester);
      await become(tester, null);
      expect(find.text('prospect@client.example'), findsNothing);
      await frames(tester, 10);
      expect(find.text('Send Invite'), findsNothing);
      expect(server.writes, isEmpty);
      await unmount(tester);
    });

    for (final (fate, beforeFrame) in [
      ('done', false),
      ('done', true),
      ('refused', false),
      ('refused', true),
    ]) {
      testWidgets(
          'in flight when B signs in, then $fate'
          "${beforeFrame ? ' before any frame' : ''}: nothing is said to B, "
          'nothing of B is re-read for it', (tester) async {
        await show(tester);
        await type(tester);
        final hold = server.holds['POST coach_invites:$memberA'] =
            Completer<void>();
        await tester.tap(find.text('Send Invite'));
        await pumpUntil(
            tester, () => server.writesTo('coach_invites').isNotEmpty,
            what: 'sent');
        if (fate == 'refused') server.fails.add('POST coach_invites:$memberA');
        if (beforeFrame) {
          await tester.runAsync(() => signInAs(memberB));
        } else {
          await become(tester, memberB);
          await pumpUntil(tester,
              () => server.count('GET coach_invites:$memberB') > 0,
              what: "B's own invites");
          await frames(tester, 10);
        }
        final reads = server.count('GET coach_invites:$memberB');
        hold.complete();
        // The Functions client works on a real isolate.
        await pumpUntil(
            tester,
            () => reported.any((f) => f.origin == 'CoachDashboard.sendInvite'),
            what: 'recorded');
        await frames(tester, 10);
        expect(find.byType(SnackBar), findsNothing,
            reason: "THE defect: A's invite was said to B");
        expect(find.text('Send Invite'), findsNothing);
        expect(server.writesTo('coach_invites').map((w) => w.who), [memberA]);
        if (!beforeFrame) {
          expect(server.count('GET coach_invites:$memberB'), reads);
        }
        await unmount(tester);
      });
    }

    testWidgets('the switch and the tap in one frame: refused, recorded',
        (tester) async {
      await show(tester);
      await type(tester);
      final send = tester
          .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Send Invite'))
          .onPressed!;
      await tester.runAsync(() => signInAs(memberB));
      send(); // no frame has run since B signed in (a hidden tab)
      await frames(tester);
      expect(server.writesTo('coach_invites'), isEmpty,
          reason: "THE defect: A's prospect was invited by B");
      expect(server.calls.where((k) => k.contains('send-invite-email')),
          isEmpty);
      expect(
          reported.map((f) => f.origin), contains('CoachDashboard.sendInvite'));
      await unmount(tester);
    });

    testWidgets('control: A stays (token refreshed), sent once as A',
        (tester) async {
      await show(tester);
      await type(tester);
      final before = c.read(currentUserProvider);
      await tester.runAsync(refreshSession);
      await pumpUntil(tester, () => c.read(currentUserProvider) != before,
          what: 'the same coach');
      await frames(tester, 2);
      expect(find.text('prospect@client.example'), findsOneWidget,
          reason: 'the draft is kept');
      await tester.tap(find.text('Send Invite'));
      await pumpUntil(tester, () => seen(find.text('Invite sent!')),
          what: 'sent');
      final w = server.writesTo('coach_invites').single;
      expect((w.who, w.body['coach_id'], w.body['invitee_email']),
          (memberA, memberA, 'prospect@client.example'));
      await unmount(tester);
    });
  });
}

/// The roster's own failure is said on the three tabs that show it.
Future<void> failedRosterIsSaid(
    WidgetTester tester,
    TwoCoachPostgrest server,
    ProviderContainer c,
    Future<void> Function(WidgetTester, String) openTab,
    Future<void> Function(WidgetTester, [int]) frames) async {
  c.invalidate(clientWorkoutLogsProvider);
  server.fails.add('GET user_profiles:$memberA');
  c.invalidate(coachClientsProvider);
  await frames(tester, 12);
  for (final e in const {
    'Clients': true,
    'Requests': false,
    'Check-Ins': true,
    'Workouts': true,
  }.entries) {
    await tester.ensureVisible(find.text(e.key).first);
    await openTab(tester, e.key);
    expect(find.textContaining('may be out of date'),
        e.value ? findsOneWidget : findsNothing,
        reason: 'roster failed: ${e.key}');
  }
}

/// B's own high-risk client is B's to see.
void nothingOfAButBs() {
  expect(find.text('Alma Stone'), findsNothing);
  expect(find.text('alma@client.example'), findsNothing);
  expect(find.text('boris@client.example'), findsOneWidget);
}
