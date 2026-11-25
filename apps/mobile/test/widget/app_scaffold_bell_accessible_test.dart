import 'dart:async';

import 'package:circle_fitness/core/realtime/realtime.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/notifications/domain/notification_provider.dart';
import 'package:circle_fitness/shared/widgets/app_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/fit_matrix.dart';
import '../support/row_checking_postgrest.dart';
import '../support/session_switch.dart';

// P0-FL-61 (b) · the AppScaffold header bell.
//
// At a82f993 it shook every 3 s whatever the device's reduce-motion setting
// said, its target was the 26×26 icon, and a screen reader found only the
// badge's digit (nothing at all with no badge) — no name, no button. The
// digit was also held from the previous account while the next one's count was
// still being read (or had failed).
//
// HOW TO SEE IT FAIL: run against a82f993's app_scaffold.dart.

const _a = '00000000-0000-4000-8000-00000000d61a';
const _b = '00000000-0000-4000-8000-00000000d61b';

void main() {
  late RowCheckingPostgrest server;

  /// The answer to each account's unread read.
  final answers = <String, Future<int> Function()>{};
  final reads = <String>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = RowCheckingPostgrest(_a);
    await initSignedInSupabase(server);
  });

  setUp(() async {
    server.reset();
    answers.clear();
    reads.clear();
    await signInAs(_a);
  });

  final icon = find.byIcon(Icons.notifications);
  final header = find.byType(AppScaffold);

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 20));
    }
  }

  /// Real auth; only the unread read itself is answered by the test (the real
  /// one is driven by a websocket).
  late ProviderContainer container;
  Future<void> mount(WidgetTester t,
      {ValueNotifier<bool>? reduceMotion}) async {
    container = ProviderContainer(overrides: [
      tableTickerProvider.overrideWith((ref, _) => Stream.value(0)),
      currentUserProfileProvider.overrideWith((ref) async => null),
      unreadCountProvider.overrideWith((ref) async {
        final uid = ref.watch(currentUserProvider)?.id;
        reads.add('$uid');
        return uid == null ? 0 : await answers[uid]!();
      }),
    ]);
    addTearDown(container.dispose);
    final reduce = reduceMotion ?? ValueNotifier(false);
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (_, __) =>
              const AppScaffold(title: 'PLAN', body: SizedBox.expand())),
      GoRoute(
          path: '/notifications', builder: (_, __) => const Text('the list')),
      GoRoute(path: '/profile', builder: (_, __) => const SizedBox()),
    ]);
    addTearDown(router.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: ValueListenableBuilder<bool>(
        valueListenable: reduce,
        builder: (_, off, __) => MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: off),
            child: child!,
          ),
        ),
      ),
    ));
    await settle(t);
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
  }

  /// The bell's own rotation (its innermost Transform).
  bool tilted(WidgetTester t) =>
      t
          .widget<Transform>(
              find.ancestor(of: icon, matching: find.byType(Transform)).first)
          .transform
          .entry(1, 0)
          .abs() >
      0.001;

  /// Whether the bell tilts at any moment of the next [seconds].
  Future<bool> shakes(WidgetTester t, {int seconds = 9}) async {
    var any = false;
    for (var i = 0; i < seconds * 20; i++) {
      await t.pump(const Duration(milliseconds: 50));
      any = any || tilted(t);
    }
    return any;
  }

  /// What a screen reader finds on the bell.
  SemanticsData bell(WidgetTester t) => t.getSemantics(icon).getSemanticsData();

  group('reduce motion', () {
    testWidgets('on: the bell never moves, and nothing is scheduled',
        (t) async {
      answers[_a] = () async => 3;
      await mount(t, reduceMotion: ValueNotifier(true));
      expect(await shakes(t), isFalse, reason: 'THE defect: it shook anyway');
      expect(t.binding.transientCallbackCount, 0);
      expect(find.text('3'), findsOneWidget, reason: 'the badge stays');
      await close(t);
    });

    testWidgets('turned on mid-shake: level at once; turned off again: it '
        'shakes again', (t) async {
      answers[_a] = () async => 3;
      final reduce = ValueNotifier(false);
      await mount(t, reduceMotion: reduce);
      for (var i = 0; i < 200 && !tilted(t); i++) {
        await t.pump(const Duration(milliseconds: 20));
      }
      expect(tilted(t), isTrue, reason: 'premise: mid-shake');
      reduce.value = true;
      await t.pump();
      expect(tilted(t), isFalse);
      expect(await shakes(t), isFalse);
      reduce.value = false;
      await t.pump();
      expect(await shakes(t), isTrue);
      await close(t);
    });

    testWidgets('POSITIVE CONTROL: off, unread: it shakes, and again',
        (t) async {
      answers[_a] = () async => 3;
      await mount(t);
      expect(await shakes(t, seconds: 3), isTrue);
      expect(await shakes(t, seconds: 5), isTrue);
      await close(t);
    });

    testWidgets('NEGATIVE CONTROL: nothing unread: it stays level', (t) async {
      answers[_a] = () async => 0;
      await mount(t);
      expect(await shakes(t), isFalse);
      await close(t);
    });
  });

  group('name, count, target', () {
    for (final (n, label, badge) in [
      (1, 'Notifications, 1 unread', '1'),
      (3, 'Notifications, 3 unread', '3'),
      (25, 'Notifications, 25 unread', '9+'),
    ]) {
      testWidgets('$n unread: "$label", one pressable button', (t) async {
        final handle = t.ensureSemantics();
        answers[_a] = () async => n;
        await mount(t);
        expect(find.text(badge), findsOneWidget);
        final node = t.getSemantics(icon);
        final d = node.getSemanticsData();
        expect(d.label, label,
            reason: 'named and counted, the badge not read a second time');
        expect(d.flagsCollection.isButton, isTrue);
        expect(d.hasAction(SemanticsAction.tap), isTrue);
        expect(
            tapNodes(t, header)
                .where((x) => x.label.contains('Notifications') || x.label == badge),
            hasLength(1));
        expect(find.bySemanticsLabel(badge), findsNothing);
        node.owner!.performAction(node.id, SemanticsAction.tap);
        await settle(t);
        expect(find.text('the list'), findsOneWidget);
        handle.dispose();
        await close(t);
      });
    }

    testWidgets('a real zero is said as none, with no badge', (t) async {
      final handle = t.ensureSemantics();
      answers[_a] = () async => 0;
      await mount(t);
      expect(bell(t).label, 'Notifications, none unread');
      expect(find.text('0'), findsNothing);
      handle.dispose();
      await close(t);
    });

    for (final (name, answer) in <(String, Future<int> Function())>[
      ('pending', () => Completer<int>().future),
      (
        'failed',
        () async =>
            throw const PostgrestException(message: 'SECRET', code: 'XX000')
      ),
    ]) {
      testWidgets('a $name count is not said as none', (t) async {
        final handle = t.ensureSemantics();
        answers[_a] = answer;
        await mount(t);
        expect(bell(t).label, 'Notifications',
            reason: 'named; no claim about a count nobody has read');
        expect(bell(t).flagsCollection.isButton, isTrue);
        handle.dispose();
        await close(t);
      });
    }

    for (final width in fitPhones.keys) {
      for (final scale in fitScales) {
        testWidgets('${width}dp, text $scale×: the target is >= 44 and takes '
            'the tap at its edge', (t) async {
          final handle = t.ensureSemantics();
          fitWindow(t, width, 700, scale);
          answers[_a] = () async => 3;
          await mount(t, reduceMotion: ValueNotifier(true));
          final node = t.getSemantics(icon);
          expect(node.rect.width, greaterThanOrEqualTo(44));
          expect(node.rect.height, greaterThanOrEqualTo(44));
          // The icon has not moved or shrunk: 26 wide, 20 from the right edge.
          final r = t.getRect(icon);
          expect(r.size, const Size(26, 26));
          expect(r.right, closeTo(width - 20, 0.01));
          // (Round 2: the target grows into the right margin, not the title.)
          await t.tapAt(Offset(r.left + 42, r.center.dy - 20));
          await settle(t);
          expect(find.text('the list'), findsOneWidget);
          handle.dispose();
          await close(t);
        });
      }
    }

    testWidgets('POSITIVE CONTROL: a touch on the icon opens the list',
        (t) async {
      answers[_a] = () async => 3;
      await mount(t, reduceMotion: ValueNotifier(true));
      await t.tap(icon);
      await settle(t);
      expect(find.text('the list'), findsOneWidget);
      await close(t);
    });
  });

  group("the count is the signed-in account's", () {
    Future<void> switchTo(WidgetTester t, String uid) async {
      await t.runAsync(() => signInAs(uid));
      await settle(t);
    }

    for (final (name, answer) in <(String, Future<int> Function())>[
      ('pending', () => Completer<int>().future),
      (
        'failed',
        () async =>
            throw const PostgrestException(message: 'SECRET', code: 'XX000')
      ),
    ]) {
      testWidgets("A → B, B's read $name: A's count is neither shown nor said",
          (t) async {
        final handle = t.ensureSemantics();
        answers[_a] = () async => 3;
        answers[_b] = answer;
        await mount(t);
        expect(find.text('3'), findsOneWidget, reason: 'premise');
        await switchTo(t, _b);
        expect(reads.last, _b, reason: 'premise: B was really read for');
        expect(find.text('3'), findsNothing);
        expect(bell(t).label, 'Notifications');
        handle.dispose();
        await close(t);
      });
    }

    testWidgets("A's delayed answer landing after B, before B's own: not said "
        "to B; then B's own is", (t) async {
      final handle = t.ensureSemantics();
      final aLate = Completer<int>(), bOwn = Completer<int>();
      answers[_a] = () => aLate.future;
      answers[_b] = () => bOwn.future;
      await mount(t);
      await switchTo(t, _b);
      aLate.complete(3);
      await settle(t);
      expect(bell(t).label, 'Notifications');
      bOwn.complete(5);
      await settle(t);
      expect(bell(t).label, 'Notifications, 5 unread');
      handle.dispose();
      await close(t);
    });

    testWidgets("CONTROL: A's delayed answer landing after B's own changes "
        'nothing', (t) async {
      final aLate = Completer<int>();
      answers[_a] = () => aLate.future;
      answers[_b] = () async => 5;
      await mount(t);
      await switchTo(t, _b);
      expect(find.text('5'), findsOneWidget);
      aLate.complete(3);
      await settle(t);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('3'), findsNothing);
      await close(t);
    });

    testWidgets("signed out: no count; A back in: A's own again", (t) async {
      final handle = t.ensureSemantics();
      answers[_a] = () async => 3;
      await mount(t);
      await t.runAsync(() => Supabase.instance.client.auth
          .signOut(scope: SignOutScope.local));
      await settle(t);
      expect(Supabase.instance.client.auth.currentUser, isNull,
          reason: 'premise');
      expect(bell(t).label, 'Notifications');
      expect(find.text('3'), findsNothing);
      await switchTo(t, _a);
      expect(bell(t).label, 'Notifications, 3 unread');
      handle.dispose();
      await close(t);
    });

    testWidgets('POSITIVE CONTROL: the same account refreshing (and failing '
        'to) keeps its badge', (t) async {
      var n = 0;
      answers[_a] = () async => n++ == 0
          ? 3
          : throw const PostgrestException(message: 'SECRET', code: 'XX000');
      await mount(t);
      expect(find.text('3'), findsOneWidget);
      // The same member's session again. (It emits no event — the literal
      // token refresh is in bells_real_unread_count_test.dart — so the
      // re-read is asked for.)
      await switchTo(t, _a);
      container.invalidate(unreadCountProvider);
      await settle(t);
      expect(reads.length, greaterThan(1), reason: 'premise: re-read');
      expect(reads.toSet(), {_a});
      expect(find.text('3'), findsOneWidget);
      await close(t);
    });

    testWidgets('POSITIVE CONTROL: a new count for the same account is shown',
        (t) async {
      var n = 3;
      answers[_a] = () async => n;
      await mount(t);
      n = 4;
      container.invalidate(unreadCountProvider);
      await settle(t);
      expect(find.text('4'), findsOneWidget);
      n = 0;
      container.invalidate(unreadCountProvider);
      await settle(t);
      expect(find.text('4'), findsNothing);
      await close(t);
    });
  });
}
