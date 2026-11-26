import 'dart:async';

import 'package:circle_fitness/features/challenges/domain/challenge_provider.dart';
import 'package:circle_fitness/features/classes/domain/class_provider.dart';
import 'package:circle_fitness/features/community/domain/community_provider.dart';
import 'package:circle_fitness/features/messaging/presentation/connect_sections_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/owned_writes_postgrest.dart';
import '../support/owner_harness.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-59c round 3 · A-25, the Messages teasers (Feed, Groups). Their lists do
// not say who read them, and riverpod keeps the last member's through the next
// one's read: A's feed and groups were drawn for B while B's read was pending,
// had failed, or was asked again before the switch reached the screen. The
// providers are the real ones (community_provider.dart is not changed here);
// only the server is fake, and it answers by who asks.
//
// HOW TO SEE IT FAIL: run against ddce829's connect_sections.dart and
// connect_sections_view.dart.

const _postA = 'Priya private post of A';
const _groupA = 'Group of A';
const _postB = 'Bo post of B';
const _groupB = 'Group of B';

void main() {
  late OwnedWritesPostgrest server;
  late ProviderContainer container;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = OwnedWritesPostgrest();
    await initTwoMemberSupabase(server);
  });

  Map<String, Object?> post(String id, String first, String content) => {
        'id': id,
        'user_id': 'u-$id',
        'content': content,
        'post_type': 'general',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'public_profiles': {'first_name': first, 'last_name': ''},
      };

  setUp(() async {
    await signInAs(memberA);
    server.reset();
    server.rows['community_posts:$memberA'] = [
      post('pa', 'Priya', 'private post of A')
    ];
    server.rows['community_posts:$memberB'] = [post('pb', 'Bo', 'post of B')];
    server.rows['community_groups:$memberA'] = [
      {'id': 'ga', 'name': _groupA}
    ];
    server.rows['community_groups:$memberB'] = [
      {'id': 'gb', 'name': _groupB}
    ];
  });

  Future<void> open(WidgetTester t) async {
    tallView(t);
    container = ProviderContainer();
    addTearDown(container.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: ConnectSectionsView()))),
    ));
    await settleReal(t);
    expect(find.textContaining(_postA), findsOneWidget, reason: 'premise');
    expect(find.textContaining(_groupA), findsOneWidget, reason: 'premise');
  }

  void nothingOfA() {
    expect(find.textContaining(_postA), findsNothing);
    expect(find.textContaining(_groupA), findsNothing);
  }

  /// A's feed and groups asked for again, and held on the wire.
  Future<List<Completer<void>>> refreshInFlight(WidgetTester t) async {
    final holds = [
      server.holds['GET community_posts:$memberA'] = Completer<void>(),
      server.holds['GET community_groups:$memberA'] = Completer<void>(),
    ];
    container
      ..invalidate(livePostsProvider)
      ..invalidate(liveGroupsProvider);
    await settleReal(t);
    expect(container.read(livePostsProvider).isLoading, isTrue,
        reason: 'premise: in flight');
    expect(find.textContaining(_postA), findsOneWidget,
        reason: 'premise: the same member keeps them meanwhile');
    return holds;
  }

  void release(List<Completer<void>> holds) {
    for (final h in holds) {
      if (!h.isCompleted) h.complete();
    }
  }

  group("A's refresh in flight at the switch, frames pumped", () {
    testWidgets("B's reads pending: nothing of A; A's late answers are not "
        "drawn; then B's own", (t) async {
      await open(t);
      final holdsA = await refreshInFlight(t);
      final holdsB = [
        server.holds['GET community_posts:$memberB'] = Completer<void>(),
        server.holds['GET community_groups:$memberB'] = Completer<void>(),
      ];
      await switchNoFrame(t, memberB);
      await settleReal(t);
      expect(container.read(livePostsProvider).hasValue, isTrue,
          reason: "premise: riverpod still holds A's feed");
      nothingOfA();
      release(holdsA);
      await settleReal(t);
      nothingOfA();
      release(holdsB);
      await settleReal(t);
      expect(find.textContaining(_postB), findsOneWidget);
      expect(find.textContaining(_groupB), findsOneWidget);
      nothingOfA();
      await closeApp(t);
    });

    testWidgets("B's reads failed: B's failure lines, nothing of A", (t) async {
      await open(t);
      final holdsA = await refreshInFlight(t);
      server.fails
        ..add('GET community_posts:$memberB')
        ..add('GET community_groups:$memberB');
      await switchNoFrame(t, memberB);
      await settleReal(t);
      release(holdsA);
      await settleReal(t);
      nothingOfA();
      expect(find.text('Could not load posts'), findsOneWidget);
      expect(find.text('Could not load groups'), findsOneWidget);
      await closeApp(t);
    });

    testWidgets("sign-out: nothing of A", (t) async {
      await open(t);
      final holdsA = await refreshInFlight(t);
      await signOutNoFrame(t);
      await settleReal(t);
      nothingOfA();
      release(holdsA);
      await settleReal(t);
      nothingOfA();
      await closeApp(t);
    });
  });

  // Round 4 (lead mutant N4: the view READS the uid instead of watching it).
  // With every source that follows the account already being read again, the
  // switch replaces one loading state with another, and riverpod 2.6.1 tells no
  // one: the uid the view watches is then the only thing that redraws it, so
  // without it A's feed and groups stay on B's screen while B's reads are out.
  testWidgets('every source in flight at the switch, frames pumped: the uid '
      'alone redraws the view, nothing of A while B is read', (t) async {
    await open(t);
    final holdsA = [
      for (final table in [
        'community_posts',
        'community_groups',
        'classes',
        'challenges'
      ])
        server.holds['GET $table:$memberA'] = Completer<void>(),
    ];
    container
      ..invalidate(livePostsProvider)
      ..invalidate(liveGroupsProvider)
      ..invalidate(liveClassesFromDbProvider)
      ..invalidate(liveChallengesProvider);
    await settleReal(t);
    for (final p in [
      livePostsProvider,
      liveGroupsProvider,
      liveClassesFromDbProvider,
      liveChallengesProvider,
    ]) {
      expect(container.read(p).isLoading, isTrue, reason: 'premise: in flight');
    }
    expect(find.textContaining(_postA), findsOneWidget,
        reason: 'premise: the same member keeps them meanwhile');
    final holdsB = [
      for (final table in [
        'community_posts',
        'community_groups',
        'classes',
        'challenges'
      ])
        server.holds['GET $table:$memberB'] = Completer<void>(),
    ];
    await switchNoFrame(t, memberB);
    await settleReal(t);
    nothingOfA();
    release(holdsA);
    await settleReal(t);
    nothingOfA();
    release(holdsB);
    await settleReal(t);
    expect(find.textContaining(_postB), findsOneWidget);
    expect(find.textContaining(_groupB), findsOneWidget);
    nothingOfA();
    await closeApp(t);
  });

  group('no refresh in flight', () {
    testWidgets("B's reads pending: nothing of A", (t) async {
      await open(t);
      final holdsB = [
        server.holds['GET community_posts:$memberB'] = Completer<void>(),
        server.holds['GET community_groups:$memberB'] = Completer<void>(),
      ];
      await switchNoFrame(t, memberB);
      await settleReal(t);
      nothingOfA();
      release(holdsB);
      await settleReal(t);
      expect(find.textContaining(_postB), findsOneWidget);
      await closeApp(t);
    });

    testWidgets('asked again before the switch is flushed (no frame): nothing '
        'of A', (t) async {
      await open(t);
      final holdsB = [
        server.holds['GET community_posts:$memberB'] = Completer<void>(),
        server.holds['GET community_groups:$memberB'] = Completer<void>(),
      ];
      await switchNoFrame(t, memberB);
      container
        ..invalidate(livePostsProvider)
        ..invalidate(liveGroupsProvider)
        ..read(livePostsProvider)
        ..read(liveGroupsProvider);
      await t.pump();
      nothingOfA();
      await settleReal(t);
      nothingOfA();
      release(holdsB);
      await settleReal(t);
      expect(find.textContaining(_groupB), findsOneWidget);
      await closeApp(t);
    });
  });

  group('the same member', () {
    testWidgets('CONTROL: a token refresh keeps the teasers while they are read '
        'again', (t) async {
      await open(t);
      final holds = [
        server.holds['GET community_posts:$memberA'] = Completer<void>(),
        server.holds['GET community_groups:$memberA'] = Completer<void>(),
      ];
      await refreshToken(t);
      await settleReal(t);
      expect(find.textContaining(_postA), findsOneWidget);
      expect(find.textContaining(_groupA), findsOneWidget);
      release(holds);
      await settleReal(t);
      expect(find.textContaining(_postA), findsOneWidget);
      await closeApp(t);
    });

    testWidgets('a failed refresh keeps the teasers under the failure',
        (t) async {
      await open(t);
      server.fails
        ..add('GET community_posts:$memberA')
        ..add('GET community_groups:$memberA');
      container
        ..invalidate(livePostsProvider)
        ..invalidate(liveGroupsProvider);
      await settleReal(t);
      expect(find.text('Could not load posts'), findsOneWidget);
      expect(find.text('Could not load groups'), findsOneWidget);
      expect(find.textContaining(_postA), findsOneWidget,
          reason: 'kept for the same member');
      expect(find.textContaining(_groupA), findsOneWidget);
      server.fails.clear();
      container.invalidate(livePostsProvider);
      await settleReal(t);
      expect(find.text('Could not load posts'), findsNothing);
      expect(find.textContaining(_postA), findsOneWidget);
      await closeApp(t);
    });

    testWidgets('NEGATIVE CONTROL: a refresh that answers nothing is empty, '
        'not the old rows', (t) async {
      await open(t);
      server.rows['community_posts:$memberA'] = const [];
      container.invalidate(livePostsProvider);
      await settleReal(t);
      expect(find.textContaining(_postA), findsNothing);
      expect(find.text('Could not load posts'), findsNothing);
      expect(find.text('Open Feed'), findsOneWidget);
      await closeApp(t);
    });
  });
}
