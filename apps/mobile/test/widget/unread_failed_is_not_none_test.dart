import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/core/widgets/app_top_nav.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/notifications/data/notification_model.dart';
import 'package:circle_fitness/features/notifications/domain/notification_provider.dart';
import 'package:circle_fitness/shared/widgets/app_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase, User;

import '../support/pump_until.dart';
import '../support/pump_until_quiet.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-63c · a failed unread count is never presented as "no unread".
//
// Three states, end to end, for both header bells over the REAL
// `unreadCountProvider`, `fetchUnreadCount`, auth client and HTTP requests
// (only the live websocket feed is the test's):
//   CONFIRMED  the read answered → "Notifications, none unread" / "N unread";
//   LOADING    no answer yet for this account → plain "Notifications", no mark;
//   FAILED     the last read failed → plain "Notifications", no mark — never
//              the number before it, and never "none".
// At 7b9ce5c a failed RE-count kept the last confirmed number: after a 0 the
// bell went on saying "none unread", after a 4 it kept saying and drawing 4.
//
// HOW TO SEE IT FAIL: `git checkout 7b9ce5c -- lib/core/widgets/app_top_nav.dart`.
//
// No visible "count unknown" marker is drawn: that design is an owner decision
// (ledger: "bells' red dot and a visible 'count unknown'"), not this package's.

class _Server extends TwoMemberPostgrest {
  final unread = <String, int>{};
  final answered = <String>[];
  int _busy = 0;
  bool get quiet => _busy == 0;

  @override
  void reset() {
    super.reset();
    unread.clear();
    answered.clear();
    _busy = 0;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    _busy++;
    try {
      if (!request.url.path.endsWith('/rest/v1/notifications')) {
        return await super.send(request);
      }
      final who = TwoMemberPostgrest.who(request);
      final key = 'GET notifications:$who';
      calls.add(key);
      expect(request.method, 'GET', reason: 'the bell only reads');
      expect(request.url.queryParameters['read'], 'eq.false');
      final n = request.url.queryParameters['recipient_id'] == 'eq.$who'
          ? unread[who] ?? 0
          : 0; // RLS: nobody reads another member's.
      final hold = holds[key];
      if (hold != null && !hold.isCompleted) {
        _busy--;
        await hold.future;
        _busy++;
      }
      final fail = fails.contains(key);
      answered.add(key);
      return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode(fail
              ? {'message': 'refused SECRET', 'code': 'XX000'}
              : [for (var i = 0; i < n; i++) {'id': 'n$i'}]))),
          fail ? 500 : 200,
          request: request,
          headers: {'content-type': 'application/json'});
    } finally {
      _busy--;
    }
  }
}

const _readA = 'GET notifications:$memberA';
const _readB = 'GET notifications:$memberB';

void main() {
  final server = _Server();
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(server);
  });

  setUp(() async {
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
    await signInAs(memberA);
  });

  tearDown(resetFailureSink);

  List<AppFailure> countFailures() =>
      reported.where((f) => f.origin == 'unreadCountProvider').toList();

  // ── provider level ─────────────────────────────────────────────────────────
  group('unreadCountProvider', () {
    late ProviderContainer c;
    late StreamController<List<AppNotification>> live;

    /// Until the count's current read has answered (or failed), and the
    /// server is quiet.
    Future<void> quiet() async {
      // Let a live event or invalidation start the re-read first.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await c
          .read(unreadCountProvider.future)
          .then((_) {}, onError: (Object _) {});
      for (var i = 0; i < 200 && !server.quiet; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    setUp(() async {
      live = StreamController.broadcast();
      final feed = StreamProvider<List<AppNotification>>((ref) => live.stream);
      c = ProviderContainer(overrides: [
        notificationsStreamProvider.overrideWith((ref) {
          ref.watch(currentUserProvider.select((User? u) => u?.id));
          return ref.watch(feed);
        }),
      ]);
    });

    // Listened only once the test has set up the server's answer.
    void start() =>
        c.listen(unreadCountProvider, (_, __) {}, fireImmediately: true);

    tearDown(() {
      c.dispose();
      unawaited(live.close());
    });

    test('a failed read is an error, recorded once — never AsyncData(0)',
        () async {
      server.fails.add(_readA);
      start();
      await quiet();
      final s = c.read(unreadCountProvider);
      expect(server.calls, [_readA], reason: "premise: A's count was read");
      expect(s, isA<AsyncError<int?>>());
      expect(s.hasValue && s.requireValue == 0, isFalse,
          reason: 'a failure is not "0 unread"');
      expect(countFailures(), hasLength(1), reason: 'recorded once');
    });

    test('after a confirmed 0, a failed re-count is an error, not 0; the next '
        'good read is the true count', () async {
      await quiet();
      expect(c.read(unreadCountProvider), const AsyncData<int?>(0),
          reason: 'premise: confirmed 0');
      server.fails.add(_readA);
      c.invalidate(unreadCountProvider);
      await quiet();
      expect(c.read(unreadCountProvider).hasError, isTrue);
      expect(countFailures(), hasLength(1), reason: 'once per failure');
      server.fails.clear();
      server.unread[memberA] = 2;
      live.add(const []); // a live event re-counts
      await quiet();
      expect(c.read(unreadCountProvider), const AsyncData<int?>(2));
      expect(countFailures(), hasLength(1), reason: 'the success adds none');
      expect(server.calls, [_readA, _readA, _readA]);
    });
  });

  // ── both bells ─────────────────────────────────────────────────────────────
  for (final (name, iconData, screen) in <(String, IconData, Widget)>[
    (
      "the app shell's bell",
      Icons.notifications_none_rounded,
      const Scaffold(body: Column(children: [AppTopNav()])),
    ),
    (
      "the AppScaffold's bell",
      Icons.notifications,
      const AppScaffold(title: 'PLAN', body: SizedBox.expand()),
    ),
  ]) {
    group(name, () {
      final icon = find.byIcon(iconData);
      final mark = find.descendant(
          of: find.ancestor(of: icon, matching: find.byType(Stack)).first,
          matching: find.byType(Positioned));

      late ProviderContainer container;
      late StreamController<List<AppNotification>> live;

      Future<void> settle(WidgetTester t) =>
          pumpUntilQuiet(t, () => server.quiet, what: 'the server to be quiet');

      Future<void> until(WidgetTester t, bool Function() c, String what) async {
        await pumpUntil(t, c, what: what);
        await settle(t);
      }

      int answers(String key) => server.answered.where((k) => k == key).length;

      // Mounted WITHOUT AccountScope: the bell carries its own owner check.
      Future<void> mount(WidgetTester t) async {
        live = StreamController.broadcast();
        final feed =
            StreamProvider<List<AppNotification>>((ref) => live.stream);
        container = ProviderContainer(overrides: [
          confirmedCurrentProfileProvider.overrideWith((ref) => null),
          notificationsStreamProvider.overrideWith((ref) {
            ref.watch(currentUserProvider.select((User? u) => u?.id));
            return ref.watch(feed);
          }),
        ]);
        addTearDown(container.dispose);
        addTearDown(() => unawaited(live.close()));
        final router = GoRouter(routes: [
          GoRoute(path: '/', builder: (_, __) => screen),
          GoRoute(
              path: '/notifications',
              builder: (_, __) => const Text('the list')),
        ]);
        addTearDown(router.dispose);
        await t.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
          ),
        ));
        await settle(t);
      }

      Future<void> close(WidgetTester t) async {
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 5));
      }

      String said(WidgetTester t) => t.getSemantics(icon).label;

      /// Nothing in the bell says or draws a count.
      void unknown(WidgetTester t, {String? reason}) {
        expect(said(t), 'Notifications', reason: reason);
        expect(said(t), isNot(contains('none')));
        expect(said(t), isNot(contains('0')));
        expect(said(t), isNot(contains('SECRET')), reason: 'no raw error');
        expect(mark, findsNothing, reason: reason);
        expect(find.descendant(of: find.byType(Stack), matching: find.text('0')),
            findsNothing);
      }

      Future<void> failRecount(WidgetTester t, String key) async {
        server.fails.add(key);
        final n = answers(key);
        container.invalidate(unreadCountProvider);
        await until(t, () => answers(key) > n, 'the failed re-count');
      }

      for (final (before, beforeLabel) in [
        (0, 'Notifications, none unread'),
        (4, 'Notifications, 4 unread'),
      ]) {
        testWidgets(
            'confirmed $before, then a FAILED re-count: unknown — not '
            '"$beforeLabel", nothing drawn', (t) async {
          final handle = t.ensureSemantics();
          server.unread[memberA] = before;
          await mount(t);
          expect(said(t), beforeLabel, reason: 'premise: confirmed');
          expect(mark, before > 0 ? findsOneWidget : findsNothing);
          reported.clear();
          await failRecount(t, _readA);
          expect(container.read(unreadCountProvider).hasError, isTrue,
              reason: 'premise: the re-count failed');
          unknown(t, reason: 'THE defect: the failed count kept $before');
          expect(countFailures(), hasLength(1), reason: 'recorded once');
          handle.dispose();
          await close(t);
        });
      }

      testWidgets('first read pending, then failed: unknown throughout',
          (t) async {
        final handle = t.ensureSemantics();
        final hold = server.holds[_readA] = Completer<void>();
        server.fails.add(_readA);
        await mount(t);
        expect(server.calls, [_readA], reason: 'premise: it is being read');
        unknown(t, reason: 'loading');
        hold.complete();
        await until(t, () => answers(_readA) == 1, 'the failure');
        unknown(t, reason: 'failed');
        expect(countFailures(), hasLength(1));
        handle.dispose();
        await close(t);
      });

      testWidgets('after a failure, a retry still in flight stays unknown',
          (t) async {
        final handle = t.ensureSemantics();
        server.unread[memberA] = 0;
        await mount(t);
        await failRecount(t, _readA);
        server.fails.clear();
        final hold = server.holds[_readA] = Completer<void>();
        container.invalidate(unreadCountProvider);
        await until(t, () => server.calls.length == 3, 'the retry');
        expect(container.read(unreadCountProvider).isLoading, isTrue,
            reason: 'premise: the retry is pending');
        unknown(t, reason: 'a pending retry after a failure is not the 0');
        hold.complete();
        await until(t, () => answers(_readA) == 3, 'the retry answer');
        expect(said(t), 'Notifications, none unread');
        handle.dispose();
        await close(t);
      });

      testWidgets('RECOVERY: after a failure, a live event shows the true '
          'count; a revisit (re-read) shows a true 0', (t) async {
        final handle = t.ensureSemantics();
        server.unread[memberA] = 0;
        await mount(t);
        await failRecount(t, _readA);
        unknown(t);
        server.fails.clear();
        server.unread[memberA] = 7;
        live.add(const []);
        await until(t, () => answers(_readA) == 3, 'the live re-count');
        expect(said(t), 'Notifications, 7 unread');
        expect(mark, findsOneWidget);
        await failRecount(t, _readA);
        unknown(t);
        server.fails.clear();
        server.unread[memberA] = 0;
        container.invalidate(unreadCountProvider);
        await until(t, () => answers(_readA) == 5, 'the re-read');
        expect(said(t), 'Notifications, none unread');
        expect(mark, findsNothing);
        expect(server.calls, everyElement(_readA),
            reason: "only A's count was ever read");
        expect(countFailures(), hasLength(2), reason: 'one per failure');
        handle.dispose();
        await close(t);
      });

      testWidgets('CONTROL, same account: a re-count still running after a '
          'confirmed count keeps it (no flicker per live event)', (t) async {
        final handle = t.ensureSemantics();
        server.unread[memberA] = 3;
        await mount(t);
        final hold = server.holds[_readA] = Completer<void>();
        server.unread[memberA] = 5;
        live.add(const []);
        await until(t, () => server.calls.length == 2, 'the re-count');
        expect(said(t), 'Notifications, 3 unread');
        expect(mark, findsOneWidget);
        hold.complete();
        await until(t, () => answers(_readA) == 2, 'the answer');
        expect(said(t), 'Notifications, 5 unread');
        expect(countFailures(), isEmpty);
        handle.dispose();
        await close(t);
      });

      testWidgets("A's re-count failed, then A → B with A's next count in "
          "flight: B is unknown until B's own answers; A's never shown",
          (t) async {
        final handle = t.ensureSemantics();
        server.unread.addAll({memberA: 0, memberB: 2});
        await mount(t);
        await failRecount(t, _readA);
        server.fails.clear();
        server.unread[memberA] = 9;
        final a = server.holds[_readA] = Completer<void>();
        final b = server.holds[_readB] = Completer<void>();
        container.invalidate(unreadCountProvider);
        await until(t, () => server.calls.length == 3, "A's next count");
        await t.runAsync(() => signInAs(memberB));
        await until(t, () => server.calls.contains(_readB), "B's read");
        unknown(t, reason: "B's read pending");
        a.complete();
        await until(t, () => answers(_readA) == 3, "A's late answer");
        unknown(t, reason: "A's late 9 is not B's");
        b.complete();
        await until(t, () => answers(_readB) == 1, "B's answer");
        expect(said(t), 'Notifications, 2 unread');
        expect(Supabase.instance.client.auth.currentUser?.id, memberB);
        expect(server.calls.where((k) => k == _readB), hasLength(1));
        handle.dispose();
        await close(t);
      });

      testWidgets("A confirmed, A → B, B's read FAILS: unknown, then B's "
          'retry shows B\'s true 0', (t) async {
        final handle = t.ensureSemantics();
        server.unread.addAll({memberA: 4, memberB: 0});
        await mount(t);
        expect(said(t), 'Notifications, 4 unread', reason: 'premise');
        server.fails.add(_readB);
        await t.runAsync(() => signInAs(memberB));
        await until(t, () => answers(_readB) == 1, "B's failed read");
        unknown(t, reason: "B's failed read is neither A's 4 nor 0");
        server.fails.clear();
        container.invalidate(unreadCountProvider);
        await until(t, () => answers(_readB) == 2, "B's retry");
        expect(said(t), 'Notifications, none unread');
        handle.dispose();
        await close(t);
      });

      testWidgets('signed out after a failure, then the same member back in: '
          'their true count', (t) async {
        final handle = t.ensureSemantics();
        server.unread[memberA] = 0;
        await mount(t);
        await failRecount(t, _readA);
        server.fails.clear();
        server.unread[memberA] = 1;
        await t.runAsync(signOut);
        await until(t, () => container.read(currentUserProvider) == null,
            'the sign-out');
        unknown(t, reason: 'signed out');
        final n = answers(_readA);
        await t.runAsync(() => signInAs(memberA));
        await until(t, () => answers(_readA) > n, "A's read");
        expect(said(t), 'Notifications, 1 unread');
        handle.dispose();
        await close(t);
      });
    });
  }
}
