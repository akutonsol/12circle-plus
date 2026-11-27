import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/core/realtime/realtime.dart';
import 'package:circle_fitness/features/messaging/domain/messaging_provider.dart';
import 'package:circle_fitness/features/messaging/presentation/chat_screen.dart';
import 'package:circle_fitness/features/messaging/presentation/messaging_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/owned_writes_postgrest.dart';
import '../support/owner_harness.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-59c round 3 · the Messages inbox with a read IN FLIGHT when the account
// changes. Riverpod 2.6.1 does not notify when `AsyncData(isLoading)` becomes
// `AsyncLoading` (both loading), so a screen watching only the inbox was never
// rebuilt, and A's contacts and previews stayed drawn for B — with frames.
//
// HOW TO SEE IT FAIL: run against ddce829's messaging_screen.dart and
// messaging_provider.dart.

const _nameA = 'Nadia Rahman';
const _previewA = 'private preview of A';
const _nameB = 'Bea Coach';
const _failed = "Couldn't load your messages";

void main() {
  late OwnedWritesPostgrest server;
  late ProviderContainer container;
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = OwnedWritesPostgrest();
    await initTwoMemberSupabase(server);
  });

  setUp(() async {
    await signInAs(memberA);
    server.reset();
    server.rows['conversations:$memberA'] = [
      {
        'id': 'conv-A',
        'participant_1': memberA,
        'participant_2': 'coach-1',
        'last_message': _previewA,
        'last_message_at': '2026-11-01T10:00:00Z',
      }
    ];
    server.rows['conversation_participant_profiles:$memberA'] = [
      {'id': 'coach-1', 'first_name': 'Nadia', 'last_name': 'Rahman', 'role': 'coach'}
    ];
    server.rows['conversations:$memberB'] = [
      {
        'id': 'conv-B',
        'participant_1': memberB,
        'participant_2': 'coach-2',
        'last_message': 'preview of B',
        'last_message_at': '2026-11-02T10:00:00Z',
      }
    ];
    server.rows['conversation_participant_profiles:$memberB'] = [
      {'id': 'coach-2', 'first_name': 'Bea', 'last_name': 'Coach', 'role': 'coach'}
    ];
    reported.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  int readsOf(String who) => server.sent('GET', 'conversations', who).length;

  Future<GoRouter> openInbox(WidgetTester t) async {
    tallView(t);
    container = ProviderContainer(overrides: [
      tableTickerProvider.overrideWith((ref, table) => Stream.value(0)),
    ]);
    addTearDown(container.dispose);
    final router = GoRouter(initialLocation: '/messages', routes: [
      GoRoute(path: '/messages', builder: (_, __) => const MessagingScreen()),
      GoRoute(path: '/chat', builder: (_, __) => const ChatScreen()),
    ]);
    addTearDown(router.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await settleReal(t);
    expect(find.text(_nameA), findsOneWidget, reason: 'premise');
    return router;
  }

  /// A's Refresh, held on the wire.
  Future<Completer<void>> refreshInFlight(WidgetTester t) async {
    final hold = server.holds['GET conversations:$memberA'] = Completer<void>();
    final before = readsOf(memberA);
    await t.tap(find.byIcon(Icons.refresh));
    await settleReal(t);
    expect(readsOf(memberA), before + 1, reason: 'premise: A refreshed');
    expect(container.read(conversationsProvider).isLoading, isTrue,
        reason: 'premise: in flight');
    expect(find.text(_nameA), findsOneWidget,
        reason: 'premise: the same member keeps the rows meanwhile');
    return hold;
  }

  void nothingOfA() {
    expect(find.text(_nameA), findsNothing);
    expect(find.text(_previewA), findsNothing);
  }

  group("A's refresh in flight at the switch, frames pumped", () {
    testWidgets("B's read pending: none of A's threads; A's late answer is not "
        "drawn; then B's own", (t) async {
      await openInbox(t);
      final holdA = await refreshInFlight(t);
      final holdB =
          server.holds['GET conversations:$memberB'] = Completer<void>();
      await switchNoFrame(t, memberB);
      await settleReal(t);
      expect(container.read(conversationsProvider).hasValue, isTrue,
          reason: "premise: riverpod still holds A's threads");
      nothingOfA();
      holdA.complete();
      await settleReal(t);
      nothingOfA();
      holdB.complete();
      await settleReal(t);
      expect(find.text(_nameB), findsOneWidget);
      nothingOfA();
      await closeApp(t);
    });

    testWidgets("B's read hangs: still none of A's threads", (t) async {
      await openInbox(t);
      final holdA = await refreshInFlight(t);
      server.holds['GET conversations:$memberB'] = Completer<void>();
      await switchNoFrame(t, memberB);
      for (var i = 0; i < 3; i++) {
        await settleReal(t);
      }
      nothingOfA();
      holdA.complete();
      await closeApp(t);
    });

    testWidgets("B's read failed: B's failure, none of A's threads", (t) async {
      await openInbox(t);
      final holdA = await refreshInFlight(t);
      server.fails.add('GET conversations:$memberB');
      await switchNoFrame(t, memberB);
      await settleReal(t);
      holdA.complete();
      await settleReal(t);
      nothingOfA();
      expect(find.textContaining(_failed), findsOneWidget);
      await closeApp(t);
    });

    testWidgets("B's read answered: B's threads only", (t) async {
      await openInbox(t);
      final holdA = await refreshInFlight(t);
      await switchNoFrame(t, memberB);
      await settleReal(t);
      expect(find.text(_nameB), findsOneWidget);
      nothingOfA();
      holdA.complete();
      await settleReal(t);
      expect(find.text(_nameB), findsOneWidget);
      nothingOfA();
      await closeApp(t);
    });

    testWidgets('invalidated again before the switch is flushed (no frame): '
        "none of A's threads", (t) async {
      await openInbox(t);
      final holdA = await refreshInFlight(t);
      final holdB =
          server.holds['GET conversations:$memberB'] = Completer<void>();
      await switchNoFrame(t, memberB);
      container.invalidate(conversationsProvider);
      container.read(conversationsProvider);
      await t.pump();
      nothingOfA();
      await settleReal(t);
      nothingOfA();
      holdA.complete();
      holdB.complete();
      await settleReal(t);
      expect(find.text(_nameB), findsOneWidget);
      await closeApp(t);
    });

    testWidgets("sign-out: none of A's threads", (t) async {
      await openInbox(t);
      final holdA = await refreshInFlight(t);
      await signOutNoFrame(t);
      await settleReal(t);
      nothingOfA();
      holdA.complete();
      await settleReal(t);
      nothingOfA();
      await closeApp(t);
    });
  });

  group('bound to the account they were drawn for', () {
    testWidgets("Refresh drawn for A, tapped with no frame since A->B: recorded, "
        'nothing said', (t) async {
      await openInbox(t);
      final refresh = t
          .widget<GestureDetector>(find
              .ancestor(
                  of: find.byIcon(Icons.refresh),
                  matching: find.byType(GestureDetector))
              .first)
          .onTap!;
      await switchNoFrame(t, memberB);
      refresh();
      expect(reported.map((f) => f.origin), ['MessagingScreen'],
          reason: 'THE defect: a read asked for on behalf of A, as B');
      await settleReal(t);
      expect(find.byType(SnackBar), findsNothing);
      nothingOfA();
      await closeApp(t);
    });

    testWidgets('pull to refresh drawn for A, pulled after A->B with no frame: '
        'recorded', (t) async {
      await openInbox(t);
      final pull = t.widget<RefreshIndicator>(find.byType(RefreshIndicator));
      await switchNoFrame(t, memberB);
      await pull.onRefresh();
      expect(reported.map((f) => f.origin), ['MessagingScreen']);
      await closeApp(t);
    });
  });

  group('the same member', () {
    testWidgets('CONTROL: Refresh and pull to refresh read the inbox again',
        (t) async {
      await openInbox(t);
      final before = readsOf(memberA);
      await t.tap(find.byIcon(Icons.refresh));
      await settleReal(t);
      expect(readsOf(memberA), before + 1);
      await t.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh();
      await settleReal(t);
      expect(readsOf(memberA), before + 2);
      expect(find.text(_nameA), findsOneWidget);
      expect(reported, isEmpty);
      await closeApp(t);
    });

    testWidgets('CONTROL: a token refresh with a refresh in flight keeps the '
        'threads', (t) async {
      await openInbox(t);
      final holdA = await refreshInFlight(t);
      await refreshToken(t);
      await settleReal(t);
      expect(find.text(_nameA), findsOneWidget);
      holdA.complete();
      await settleReal(t);
      expect(find.text(_nameA), findsOneWidget);
      expect(reported, isEmpty);
      await closeApp(t);
    });

    testWidgets('a failed refresh keeps the threads, says so, and Try again '
        'reads once while busy', (t) async {
      final handle = t.ensureSemantics();
      await openInbox(t);
      server.fails.add('GET conversations:$memberA');
      await t.tap(find.byIcon(Icons.refresh));
      await settleReal(t);
      expect(find.text(_nameA), findsOneWidget,
          reason: 'THE defect: the threads went for a failed refresh');
      expect(find.text(_failed), findsOneWidget);
      expect(liveRegion(_failed), findsOneWidget);
      server.fails.clear();
      final hold =
          server.holds['GET conversations:$memberA'] = Completer<void>();
      final before = readsOf(memberA);
      await t.tap(find.text('Try again'));
      await settleReal(t);
      expect(readsOf(memberA), before + 1);
      expect(find.bySemanticsLabel('Retrying'), findsOneWidget);
      expect(find.text(_nameA), findsOneWidget);
      hold.complete();
      await settleReal(t);
      expect(find.text(_failed), findsNothing);
      expect(find.text(_nameA), findsOneWidget);
      handle.dispose();
      await closeApp(t);
    });

    testWidgets('NEGATIVE CONTROL: a failed first read is the failure, not an '
        'empty inbox', (t) async {
      server.fails.add('GET conversations:$memberA');
      tallView(t);
      container = ProviderContainer(overrides: [
        tableTickerProvider.overrideWith((ref, table) => Stream.value(0)),
      ]);
      addTearDown(container.dispose);
      await t.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MessagingScreen()),
      ));
      await settleReal(t);
      expect(find.textContaining(_failed), findsOneWidget);
      expect(find.text('No conversations yet'), findsNothing);
      expect(find.text('No coach yet'), findsNothing);
      await closeApp(t);
    });

    testWidgets("CONTROL: the member's own row opens their thread", (t) async {
      final router = await openInbox(t);
      await t.tap(find.text(_nameA));
      await settleReal(t);
      expect(router.routerDelegate.currentConfiguration.uri.path, '/chat');
      expect(container.read(selectedConversationProvider)?['id'], 'conv-A');
      await closeApp(t);
    });
  });
}
