import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/core/realtime/realtime.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/checkins/domain/checkin_provider.dart';
import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart';
import 'package:circle_fitness/features/dashboard/domain/coach_triage_provider.dart';
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
      tableTickerProvider.overrideWith((ref, t) => Stream.value(0)),
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

/// B's own high-risk client is B's to see.
void nothingOfAButBs() {
  expect(find.text('Alma Stone'), findsNothing);
  expect(find.text('alma@client.example'), findsNothing);
  expect(find.text('boris@client.example'), findsOneWidget);
}
