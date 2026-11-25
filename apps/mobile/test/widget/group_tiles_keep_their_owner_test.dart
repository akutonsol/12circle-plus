// P0-FL-59e round 3 · a group is joined or left by the member whose tile was
// tapped, and one member's memberships are never drawn for another.
//
// Join / Leave had no owner: the service asked "who is signed in?" at the tap,
// so A's "Joined" left B's group; A's late answer marked B's list; and A's
// leave that matched no row re-read the groups before the switch was flushed,
// which riverpod 2.6.1 treats as a refresh — `AsyncData(isLoading)` of A's.
//
// The real CommunityScreen / ActivityScreen; real auth transitions; no
// AccountScope; "no frame" tests never pump between the switch and the act.
//
// HOW TO SEE IT FAIL: put back 3a90049's community_provider and
// community_screen; every test fails but the POSITIVE / NEGATIVE CONTROLs, the
// feed's notifier (made anew there too) and "read failed … on Activity" (its
// failure card is drawn in front of the carried value there).
import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/core/realtime/realtime.dart';
import 'package:circle_fitness/features/activity/presentation/activity_screen.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/community/data/models/post_model.dart';
import 'package:circle_fitness/features/community/domain/community_provider.dart';
import 'package:circle_fitness/features/community/presentation/community_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/member_switch_server.dart';

const _members = 'community_group_members';

void main() {
  final server = MemberSwitchServer();
  final reported = <AppFailure>[];
  late ProviderContainer container;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(server);
    watchAuthChanges();
  });

  /// A is in Alpha; B is in Beta.
  setUp(() async {
    server.reset();
    await signInAs(memberA);
    reported.clear();
    setFailureSink(reported.add);
    final groups = [
      for (final (id, name) in [('g-a', 'Alpha'), ('g-b', 'Beta')])
        {'id': id, 'name': name, 'description': 'd', 'emoji': '💪'},
    ];
    final memberships = [
      {'group_id': 'g-a', 'user_id': memberA},
      {'group_id': 'g-b', 'user_id': memberB},
    ];
    server.rows.addAll({
      'community_groups': {memberA: groups, memberB: groups},
      _members: {memberA: memberships, memberB: memberships},
    });
  });
  tearDown(resetFailureSink);

  Iterable<String> origins() => reported.map((f) => f.origin);
  Iterable<SeenRequest> asB() => server.writes().where((w) => w.who == memberB);

  Future<void> settle(WidgetTester t, [int n = 8]) async {
    for (var i = 0; i < n; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  /// Real time passes and no frame is drawn, as in a hidden tab.
  Future<void> noFrame(WidgetTester t) => t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)));

  Future<void> switchTo(WidgetTester t, String uid) =>
      t.runAsync(() => signInAs(uid));

  Future<void> mount(WidgetTester t, Widget screen) async {
    await t.binding.setSurfaceSize(const Size(600, 1800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    container = ProviderContainer(overrides: [
      // No socket here: realtime would only leave reconnect timers.
      tableTickerProvider.overrideWith((ref, t) => Stream.value(0)),
    ]);
    addTearDown(container.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
        container: container, child: MaterialApp(home: screen)));
    await settle(t);
  }

  Future<void> open(WidgetTester t) async {
    await mount(t, const CommunityScreen());
    await t.tap(find.text('Groups'));
    await settle(t, 12);
    expect(find.text('Joined'), findsOneWidget, reason: 'premise');
    expect(find.text('Join'), findsOneWidget, reason: 'premise');
    server.seen.clear();
    reported.clear();
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 12));
  }

  Finder pill(String group, String word) => find.descendant(
      of: find.ancestor(of: find.text(group), matching: find.byType(Row)).first,
      matching: find.text(word));

  /// B's own groups are loaded, by whatever reads them, and no frame is drawn.
  Future<void> bLoaded(WidgetTester t) async {
    await switchTo(t, memberB);
    await t.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await container.read(liveGroupsProvider.future);
      container.read(groupNotifierProvider);
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
  }

  List<CommunityGroup>? groups() {
    final s = container.read(groupNotifierProvider);
    return s.hasValue ? s.requireValue : null;
  }

  group('a tap in the undrawn tile', () {
    for (final (label, group, word) in [
      ('Joined', 'Alpha', 'Joined'),
      ('Join', 'Beta', 'Join'),
    ]) {
      for (final state in ['just signed in', 'with their groups loaded', 'out']) {
        final who = state == 'out' ? 'A signed out' : 'B $state';
        testWidgets("A's '$label' once $who: nothing is sent or said, recorded",
            (t) async {
          await open(t);
          switch (state) {
            case 'out':
              await t.runAsync(signOut);
            case 'just signed in':
              await switchTo(t, memberB);
            default:
              await bLoaded(t);
          }
          await t.tap(pill(group, word));
          await noFrame(t);
          expect(server.writes(), isEmpty,
              reason: "A's tap, as someone else: ${server.writes().toList()}");
          await settle(t);
          expect(server.writes(), isEmpty);
          expect(find.byType(SnackBar), findsNothing);
          expect(origins(), contains('GroupNotifier.identity'));
          expect(t.takeException(), isNull);
          await close(t);
        });
      }

      testWidgets("A's '$label' the instant the account changes: nothing is "
          'sent, recorded', (t) async {
        await open(t);
        final tap = t
            .widget<GestureDetector>(find
                .ancestor(of: pill(group, word), matching: find.byType(GestureDetector))
                .first)
            .onTap!;
        await t.runAsync(() => switchAnd(memberB, tap));
        await settle(t);
        expect(server.writes(), isEmpty);
        expect(origins(), contains('GroupNotifier.identity'));
        expect(find.byType(SnackBar), findsNothing);
        await close(t);
      });
    }
  });

  group("A's answer after the switch", () {
    testWidgets("a join, with B's groups loaded: not marked as B's, B is not "
        'told', (t) async {
      await open(t);
      final hold = server.holds['POST $_members:$memberA'] = Completer();
      await t.tap(pill('Beta', 'Join'));
      await noFrame(t);
      expect(server.writes(_members).single.row['user_id'], memberA,
          reason: 'premise');
      // B's: not in Beta any more, so a mark would show.
      server.rows[_members]![memberB] = [];
      await bLoaded(t);
      hold.complete();
      await noFrame(t);
      expect(groups()!.where((g) => g.isJoined), isEmpty,
          reason: "A's join is marked in B's list");
      await settle(t);
      expect(find.text('Joined'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(origins(), contains('GroupNotifier.identity'));
      expect(asB(), isEmpty);
      await close(t);
    });

    for (final (label, group, word, key) in [
      ('join', 'Beta', 'Join', 'POST $_members:$memberA'),
      ('leave', 'Alpha', 'Joined', 'DELETE $_members:$memberA'),
    ]) {
      testWidgets('a $label that fails: B is not told', (t) async {
        await open(t);
        final hold = server.holds[key] = Completer();
        server.fails.add(key);
        await t.tap(pill(group, word));
        await noFrame(t);
        await switchTo(t, memberB);
        hold.complete();
        await settle(t);
        expect(find.byType(SnackBar), findsNothing);
        expect(origins(), contains('community.${label}Group'));
        await close(t);
      });
    }

    for (final bRead in ['pending', 'failed']) {
      for (final activity in [false, true]) {
        testWidgets(
            "a leave that matched no row, B's read $bRead: A's groups are not "
            'drawn for B on ${activity ? 'Activity' : 'Community'}', (t) async {
          if (activity) {
            await mount(t, const ActivityScreen());
            await t.scrollUntilVisible(find.text('Explore'), 300,
                scrollable: find.byType(Scrollable).first);
            await settle(t);
            expect(find.text('JOINED'), findsOneWidget, reason: 'premise');
          } else {
            await open(t);
          }
          final delete = server.holds['DELETE $_members:$memberA'] = Completer();
          server.zeroRows.add('DELETE $_members:$memberA');
          final bGroups =
              server.holds['GET community_groups:$memberB'] = Completer();
          if (bRead == 'failed') server.fails.add('GET community_groups:$memberB');
          if (activity) {
            unawaited(container
                .read(groupNotifierProvider.notifier)
                .toggleJoin(groups()!.firstWhere((g) => g.isJoined)));
          } else {
            await t.tap(pill('Alpha', 'Joined'));
          }
          await noFrame(t);
          expect(server.writes(_members), hasLength(1), reason: 'premise');
          // The auth client has B; nothing is flushed; then A's answer.
          await t.runAsync(() => switchAnd(memberB, delete.complete));
          await noFrame(t);
          if (bRead == 'failed') bGroups.complete();
          await settle(t);
          expect(find.text('JOINED'), findsNothing);
          expect(find.text('Joined'), findsNothing);
          expect(find.text('Alpha'), findsNothing,
              reason: "A's groups are drawn for B");
          if (bRead == 'failed') {
            expect(find.textContaining("Couldn't load"), findsWidgets);
          }
          expect(find.textContaining("Couldn't leave"), findsNothing);
          expect(origins(), contains('GroupNotifier.identity'));
          if (bRead == 'pending') {
            bGroups.complete(); // B's own, when they come.
            await settle(t);
            expect(groups()!.where((g) => g.isJoined).single.name, 'Beta');
          }
          await close(t);
        });
      }
    }
  });

  group('invalidated before the account change is flushed', () {
    testWidgets("by anyone (Activity's Try again, Messages' pull): A's groups "
        "are not drawn while B's read is pending, or once it failed",
        (t) async {
      await open(t);
      await switchTo(t, memberB);
      final hold = server.holds['GET community_groups:$memberB'] = Completer();
      server.fails.add('GET community_groups:$memberB');
      container.invalidate(liveGroupsProvider);
      await settle(t);
      // The premise this test exists for (riverpod 2.6.1).
      final raw = container.read(liveGroupsProvider);
      expect(raw.hasValue, isTrue, reason: 'premise: A\'s value is carried');
      expect(find.text('Alpha'), findsNothing);
      expect(groups(), isNull);
      hold.complete();
      await settle(t);
      expect(find.text('Alpha'), findsNothing);
      expect(find.text("Couldn't load groups"), findsOneWidget);
      await close(t);
    });

    testWidgets("A's failure is not B's", (t) async {
      server.fails.add('GET community_groups:$memberA');
      await mount(t, const CommunityScreen());
      await t.tap(find.text('Groups'));
      await settle(t);
      expect(find.text("Couldn't load groups"), findsOneWidget,
          reason: 'premise');
      reported.clear();
      final hold = server.holds['GET community_groups:$memberB'] = Completer();
      await switchTo(t, memberB);
      container.invalidate(liveGroupsProvider);
      await settle(t);
      expect(find.text("Couldn't load groups"), findsNothing);
      expect(origins(), isEmpty);
      hold.complete();
      await settle(t);
      expect(find.text('Alpha'), findsOneWidget);
      await close(t);
    });

    testWidgets('A -> B -> A with no frame, read as B meanwhile: A is read '
        'again, not left waiting', (t) async {
      await open(t);
      await t.runAsync(() => switchAnd(memberB, () {
            container.invalidate(liveGroupsProvider);
            unawaited(container.read(liveGroupsProvider.future));
          }));
      await t.runAsync(() => signInAs(memberA));
      await settle(t);
      expect(pill('Alpha', 'Joined'), findsOneWidget);
      expect(pill('Beta', 'Join'), findsOneWidget);
      await close(t);
    });

    testWidgets("the feed's notifier is made anew: A's posts are not B's", (t) async {
      server.rows['community_posts'] = {
        memberA: [
          {
            'id': 'p1', 'user_id': memberA, 'content': "A's post",
            'post_type': 'text', 'created_at': '2026-11-20T08:00:00Z',
            'public_profiles': {'first_name': 'Al', 'last_name': 'Le'},
          }
        ],
      };
      await mount(t, const CommunityScreen());
      expect(find.text("A's post"), findsOneWidget, reason: 'premise');
      final hold = server.holds['GET community_posts:$memberB'] = Completer();
      await switchTo(t, memberB);
      container.invalidate(postNotifierProvider);
      await settle(t);
      expect(find.text("A's post"), findsNothing);
      expect(container.read(postNotifierProvider).hasValue, isFalse);
      hold.complete();
      await settle(t);
      expect(find.text('No posts yet. Be the first to share!'), findsOneWidget);
      await close(t);
    });
  });

  group('POSITIVE CONTROL: the same member', () {
    testWidgets('after a token refresh: the list stays, Join joins and Leave '
        'leaves as them', (t) async {
      await open(t);
      await t.runAsync(refreshSession);
      await settle(t);
      expect(server.reads('community_groups'), isEmpty,
          reason: 'a refresh is not a new member');
      await t.tap(pill('Beta', 'Join'));
      await settle(t);
      final join = server.writes(_members).single;
      expect((join.method, join.who, join.row['user_id'], join.row['group_id']),
          ('POST', memberA, memberA, 'g-b'));
      expect(find.text('Joined'), findsNWidgets(2));
      await t.tap(pill('Alpha', 'Joined'));
      await settle(t);
      final leave = server.writes(_members).last;
      expect((leave.method, leave.who, leave.query['user_id']),
          ('DELETE', memberA, 'eq.$memberA'));
      expect(pill('Alpha', 'Join'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(reported, isEmpty);
      await close(t);
    });

    testWidgets('a leave that matched no row is said, and the groups re-read '
        'with the list kept up meanwhile', (t) async {
      await open(t);
      server.zeroRows.add('DELETE $_members:$memberA');
      server.rows[_members]![memberA] = [];
      final hold = server.holds['GET community_groups:$memberA'] = Completer();
      await t.tap(pill('Alpha', 'Joined'));
      await settle(t, 4);
      expect(find.text("Couldn't leave Alpha. Try again."), findsOneWidget);
      expect(find.text('Alpha'), findsOneWidget);
      hold.complete();
      await settle(t);
      expect(find.text('Joined'), findsNothing);
      expect(origins(), isEmpty);
      await close(t);
    });

    testWidgets('a join that fails is said', (t) async {
      await open(t);
      server.fails.add('POST $_members:$memberA');
      await t.tap(pill('Beta', 'Join'));
      await settle(t);
      expect(find.text("Couldn't join Beta. Try again."), findsOneWidget);
      expect(origins(), ['community.joinGroup']);
      await close(t);
    });

    testWidgets('signing out and back in: their groups, and they can leave',
        (t) async {
      await open(t);
      await t.runAsync(signOut);
      await settle(t);
      await switchTo(t, memberA);
      await settle(t);
      await t.tap(pill('Alpha', 'Joined'));
      await settle(t);
      expect(server.writes(_members).single.who, memberA);
      await close(t);
    });

    testWidgets("B's own tile, once drawn, is B's", (t) async {
      await open(t);
      await switchTo(t, memberB);
      await settle(t);
      await t.tap(pill('Beta', 'Joined'));
      await settle(t);
      final w = server.writes(_members).single;
      expect((w.method, w.who, w.query['user_id']),
          ('DELETE', memberB, 'eq.$memberB'));
      await close(t);
    });

    testWidgets('a test container whose account never changes keeps the list '
        'through a refresh (a failed one keeps it too)', (t) async {
      await open(t);
      container.invalidate(liveGroupsProvider);
      await settle(t);
      expect(find.text('Joined'), findsOneWidget);
      server.fails.add('GET community_groups:$memberA');
      container.invalidate(liveGroupsProvider);
      await settle(t);
      expect(groups(), isNotNull, reason: 'what was read is kept');
      expect(container.read(currentUserProvider)?.id, memberA);
      await close(t);
    });
  });

  testWidgets('NEGATIVE CONTROL: no groups at all is still no groups',
      (t) async {
    server.rows['community_groups'] = {};
    await mount(t, const CommunityScreen());
    await t.tap(find.text('Groups'));
    await settle(t);
    expect(find.text('Accountability Pods'), findsOneWidget);
    expect(find.textContaining("Couldn't load"), findsNothing);
    expect(find.text('Join'), findsNothing);
    await close(t);
  });
}
