import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/core/widgets/app_top_nav.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/notifications/data/notification_model.dart';
import 'package:circle_fitness/features/notifications/data/notification_service.dart';
import 'package:circle_fitness/features/notifications/domain/notification_provider.dart';
import 'package:circle_fitness/shared/widgets/app_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent, Supabase;

import '../support/fit_matrix.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-61 round 2 · both header bells, over the REAL `unreadCountProvider`,
// `fetchUnreadCount`, auth client and HTTP requests. Only the live stream (a
// websocket) is the test's; each of its events makes the provider count again,
// as in the app.
//
// The app shell's bell (core/widgets/app_top_nav.dart): at 924bbf0 (and
// a82f993) its dot was never said, and A's dot stayed on while B's count was
// still being read or had failed. The AppScaffold's: the same at a82f993.
//
// HOW TO SEE IT FAIL: run against 924bbf0's app_top_nav.dart (the shell's
// bell) or a82f993's app_scaffold.dart (the other).

/// Answers the unread read of the member its bearer token names.
class _Server extends TwoMemberPostgrest {
  final unread = <String, int>{};

  @override
  void reset() {
    super.reset();
    unread.clear();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!request.url.path.endsWith('/rest/v1/notifications')) {
      return super.send(request);
    }
    final who = TwoMemberPostgrest.who(request);
    final key = 'GET notifications:$who';
    calls.add(key);
    expect(request.url.queryParameters['read'], 'eq.false');
    final n = request.url.queryParameters['recipient_id'] == 'eq.$who'
        ? unread[who] ?? 0
        : 0; // RLS: nobody reads another member's.
    await holds[key]?.future;
    final fail = fails.contains(key);
    return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(fail
            ? {'message': 'refused SECRET', 'code': 'XX000'}
            : [for (var i = 0; i < n; i++) {'id': 'n$i'}]))),
        fail ? 500 : 200,
        request: request,
        headers: {'content-type': 'application/json'});
  }
}

const _readA = 'GET notifications:$memberA';
const _readB = 'GET notifications:$memberB';

void main() {
  final server = _Server();

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(server);
  });

  setUp(() async {
    server.reset();
    await signInAs(memberA);
  });

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

      /// The badge or dot over the icon.
      final mark = find.descendant(
          of: find.ancestor(of: icon, matching: find.byType(Stack)).first,
          matching: find.byType(Positioned));

      late ProviderContainer container;
      late StreamController<List<AppNotification>> live;

      Future<void> settle(WidgetTester t) async {
        for (var i = 0; i < 8; i++) {
          await t.pump(const Duration(milliseconds: 20));
        }
      }

      /// [bySelect]: the same read, watching only the uid — the shape riverpod
      /// 2.6.1 hands on as a REFRESH (AsyncData, the old value) when it is
      /// invalidated before the account change is flushed.
      Future<void> mount(WidgetTester t, {bool bySelect = false}) async {
        live = StreamController.broadcast();
        container = ProviderContainer(overrides: [
          confirmedCurrentProfileProvider.overrideWith((ref) => null),
          notificationsStreamProvider.overrideWith((ref) {
            ref.watch(currentUserProvider);
            return live.stream;
          }),
          if (bySelect)
            unreadCountProvider.overrideWith((ref) {
              ref.watch(currentUserProvider.select((u) => u?.id));
              return NotificationService().fetchUnreadCount();
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

      /// A real sign-in, delivered; NO frame is drawn.
      Future<void> switchNoFrame(WidgetTester t, String uid) =>
          t.runAsync(() => signInAs(uid));

      String said(WidgetTester t) => t.getSemantics(icon).label;

      // ── name, count, target ──────────────────────────────────────────────
      for (final (n, label) in [
        (1, 'Notifications, 1 unread'),
        (12, 'Notifications, 12 unread'),
        (0, 'Notifications, none unread'),
      ]) {
        testWidgets('$n unread: "$label", one pressable button', (t) async {
          final handle = t.ensureSemantics();
          server.unread[memberA] = n;
          await mount(t);
          expect(said(t), label);
          expect(mark, n > 0 ? findsOneWidget : findsNothing);
          final node = t.getSemantics(icon);
          final d = node.getSemanticsData();
          expect(d.flagsCollection.isButton, isTrue);
          expect(d.hasAction(SemanticsAction.tap), isTrue);
          expect(
              tapNodes(t, find.byType(Scaffold).first)
                  .where((x) => x.label.startsWith('Notifications')),
              hasLength(1));
          node.owner!.performAction(node.id, SemanticsAction.tap);
          await settle(t);
          expect(find.text('the list'), findsOneWidget);
          handle.dispose();
          await close(t);
        });
      }

      for (final pending in [true, false]) {
        testWidgets(
            'a ${pending ? 'pending' : 'failed'} first read: plain '
            '"Notifications", not "none"', (t) async {
          final handle = t.ensureSemantics();
          server.unread[memberA] = 3;
          final hold = Completer<void>();
          pending ? server.holds[_readA] = hold : server.fails.add(_readA);
          await mount(t);
          expect(server.calls, contains(_readA), reason: 'premise: it read');
          expect(said(t), 'Notifications');
          expect(mark, findsNothing);
          hold.complete();
          await settle(t);
          if (pending) expect(said(t), 'Notifications, 3 unread');
          handle.dispose();
          await close(t);
        });
      }

      for (final width in fitPhones.keys) {
        for (final scale in fitScales) {
          testWidgets('${width}dp, text $scale×: the target is >= 44',
              (t) async {
            final handle = t.ensureSemantics();
            fitWindow(t, width, 900, scale);
            server.unread[memberA] = 3;
            await mount(t);
            final node = t.getSemantics(icon);
            expect(node.rect.width, greaterThanOrEqualTo(44));
            expect(node.rect.height, greaterThanOrEqualTo(44));
            // (At large text the badge lies over the icon's centre.)
            await t.tapAt(t.getCenter(icon));
            await settle(t);
            expect(find.text('the list'), findsOneWidget);
            handle.dispose();
            await close(t);
          });
        }
      }

      // ── whose count it is ────────────────────────────────────────────────
      for (final pending in [true, false]) {
        testWidgets(
            "A → B, B's read ${pending ? 'pending' : 'failed'}: A's count is "
            'neither shown nor said', (t) async {
          final handle = t.ensureSemantics();
          server.unread[memberA] = 3;
          await mount(t);
          expect(mark, findsOneWidget, reason: 'premise');
          final hold = Completer<void>();
          pending ? server.holds[_readB] = hold : server.fails.add(_readB);
          await switchNoFrame(t, memberB);
          await settle(t);
          expect(server.calls, contains(_readB), reason: 'premise: B was read');
          expect(mark, findsNothing, reason: "THE defect: A's mark, to B");
          expect(said(t), 'Notifications');

          // B's own, when it comes.
          server.unread[memberB] = 5;
          server.fails.clear();
          hold.complete();
          if (!pending) container.invalidate(unreadCountProvider);
          await settle(t);
          expect(mark, pending ? findsNothing : findsOneWidget,
              reason: 'the held answer was true when it was asked: 0');
          handle.dispose();
          await close(t);
        });

        for (final bySelect in [false, true]) {
          testWidgets(
              'A → B, the count ${bySelect ? '(watching only the uid) ' : ''}'
              "invalidated before any frame, B's read "
              "${pending ? 'pending' : 'failed'}: A's number is not B's",
              (t) async {
            final handle = t.ensureSemantics();
            server.unread[memberA] = 3;
            await mount(t, bySelect: bySelect);
            final hold = Completer<void>();
            pending ? server.holds[_readB] = hold : server.fails.add(_readB);
            final states = <AsyncValue<int>>[];
            container.listen(unreadCountProvider, (_, s) => states.add(s));
            await switchNoFrame(t, memberB);
            // What a live notification, a pull to refresh or a retry does.
            container.invalidate(unreadCountProvider);
            await settle(t);
            expect(states.first,
                bySelect ? isA<AsyncData<int>>() : isA<AsyncLoading<int>>(),
                reason: 'premise: the trap, and only for a uid select');
            expect((states.first.isLoading, states.first.value), (true, 3),
                reason: "premise: A's value is carried into B's read");
            expect(server.calls, contains(_readB), reason: 'premise: B was read');
            expect(mark, findsNothing);
            expect(said(t), 'Notifications');
            hold.complete();
            handle.dispose();
            await close(t);
          });
        }
      }

      testWidgets("A's delayed answer landing after B, before B's own, is not "
          "B's; then B's own is shown", (t) async {
        final handle = t.ensureSemantics();
        server.unread.addAll({memberA: 3, memberB: 5});
        final a = server.holds[_readA] = Completer<void>();
        final b = server.holds[_readB] = Completer<void>();
        await mount(t);
        await switchNoFrame(t, memberB);
        a.complete();
        await settle(t);
        expect(mark, findsNothing);
        expect(said(t), 'Notifications');
        b.complete();
        await settle(t);
        expect(said(t), 'Notifications, 5 unread');
        handle.dispose();
        await close(t);
      });

      testWidgets("A's delayed answer landing after B's own changes nothing",
          (t) async {
        final handle = t.ensureSemantics();
        server.unread.addAll({memberA: 3, memberB: 5});
        final a = server.holds[_readA] = Completer<void>();
        await mount(t);
        await switchNoFrame(t, memberB);
        await settle(t);
        a.complete();
        await settle(t);
        expect(said(t), 'Notifications, 5 unread');
        handle.dispose();
        await close(t);
      });

      testWidgets('signed out: nothing shown or said; A back in: A\'s own',
          (t) async {
        final handle = t.ensureSemantics();
        server.unread[memberA] = 3;
        await mount(t);
        await t.runAsync(signOut);
        await settle(t);
        expect(Supabase.instance.client.auth.currentUser, isNull,
            reason: 'premise');
        expect(mark, findsNothing);
        expect(said(t), 'Notifications');
        await switchNoFrame(t, memberA);
        await settle(t);
        expect(said(t), 'Notifications, 3 unread');
        handle.dispose();
        await close(t);
      });

      for (final (how, held, fails) in [
        ('answered', false, false),
        ('pending', true, false),
        ('failed', false, true),
      ]) {
        testWidgets(
            'SAME ACCOUNT: a literal token refresh, its re-read $how: the '
            'count stays', (t) async {
          final handle = t.ensureSemantics();
          server.unread[memberA] = 3;
          await mount(t);
          expect(mark, findsOneWidget, reason: 'premise');
          final events = <AuthChangeEvent>[];
          final sub = Supabase.instance.client.auth.onAuthStateChange
              .listen((s) => events.add(s.event));
          final before = server.calls.where((c) => c == _readA).length;
          final hold = Completer<void>();
          if (held) server.holds[_readA] = hold;
          if (fails) server.fails.add(_readA);
          await t.runAsync(refreshSession);
          await settle(t);
          expect(events, contains(AuthChangeEvent.tokenRefreshed),
              reason: 'premise: the event really arrived');
          expect(server.calls.where((c) => c == _readA).length,
              greaterThan(before), reason: 'premise: re-read');
          expect(mark, findsOneWidget);
          expect(said(t), 'Notifications, 3 unread');
          hold.complete();
          unawaited(sub.cancel());
          handle.dispose();
          await close(t);
        });
      }

      testWidgets('SAME ACCOUNT: a live event re-counts; a failed re-count '
          'keeps the last one', (t) async {
        final handle = t.ensureSemantics();
        server.unread[memberA] = 3;
        await mount(t);
        server.unread[memberA] = 4;
        live.add(const []);
        await settle(t);
        expect(said(t), 'Notifications, 4 unread');
        server.fails.add(_readA);
        container.invalidate(unreadCountProvider);
        await settle(t);
        expect(said(t), 'Notifications, 4 unread');
        server.fails.clear();
        server.unread[memberA] = 0;
        container.invalidate(unreadCountProvider);
        await settle(t);
        expect(said(t), 'Notifications, none unread');
        expect(mark, findsNothing);
        handle.dispose();
        await close(t);
      });
    });
  }

  testWidgets("CONTROL: the app shell's bar at 1× on 390dp is laid out as "
      'before', (t) async {
    fitWindow(t, 390, 844, 1);
    final container = ProviderContainer(overrides: [
      confirmedCurrentProfileProvider.overrideWith((ref) => null),
      unreadCountProvider.overrideWith((ref) async => 3),
    ]);
    addTearDown(container.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
          home: Scaffold(body: Column(children: [AppTopNav()]))),
    ));
    await t.pump();
    final icon = find.byIcon(Icons.notifications_none_rounded);
    expect(t.getRect(find.byType(AppTopNav)), const Rect.fromLTWH(0, 0, 390, 63));
    expect(
        t.getRect(find.ancestor(of: icon, matching: find.byType(GestureDetector)).first),
        const Rect.fromLTWH(330, 8, 44, 44));
    expect(t.getRect(icon), const Rect.fromLTWH(343, 21, 18, 18));
    expect(
        t.getRect(find.descendant(
            of: find.ancestor(of: icon, matching: find.byType(Stack)).first,
            matching: find.byType(Positioned))),
        isNotNull);
    expect(t.getRect(find.byIcon(Icons.chat_bubble_outline_rounded)),
        const Rect.fromLTWH(299, 21, 18, 18));
  });
}
