// P0-FL-59e · W23: a post or comment one member wrote is never published under
// another's name, and one that was not saved is said and kept.
//
// The Create Post sheet and the comment box asked for "the feed's notifier" at
// the TAP: after a switch that is the next member's, whose owner check passes.
// Neither awaited the write: a post that failed closed its sheet with a success
// haptic, and a comment that failed was cleared.
//
// The real CommunityScreen, sheet and card; real auth transitions; no
// AccountScope. The request log says whose token wrote which row.
//
// HOW TO SEE IT FAIL: put back 5f8b7f3's community_screen, create_post_sheet,
// post_card and live_community_service. The POSITIVE CONTROLs pass there, and
// so do "a second tap" and "A's reaction is stored after B signed in" (they
// guard what is already right).
import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/community/data/live_community_service.dart';
import 'package:circle_fitness/features/community/domain/community_provider.dart';
import 'package:circle_fitness/features/community/domain/post_type_choice.dart';
import 'package:circle_fitness/features/community/presentation/community_screen.dart';
import 'package:circle_fitness/features/community/presentation/widgets/create_post_sheet.dart';
import 'package:circle_fitness/features/community/presentation/widgets/reaction_bar.dart';
import 'package:circle_fitness/features/workout/presentation/widgets/section_load_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/member_switch_server.dart';

const _draft = 'Leg day, all 5 sets';
const _comment = 'Great work Sam';

void main() {
  final server = MemberSwitchServer();
  final reported = <AppFailure>[];
  final haptics = <Object?>[];
  late ProviderContainer container;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(server);
    watchAuthChanges();
  });

  setUp(() async {
    server.reset();
    await signInAs(memberA);
    reported.clear();
    haptics.clear();
    setFailureSink(reported.add);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments);
      return null;
    });
    final post = {
      'id': 'p1',
      'user_id': 'author-1',
      'content': 'Hit a PR today',
      'post_type': 'text',
      'created_at': '2026-11-20T08:00:00Z',
      'public_profiles': {'first_name': 'Sam', 'last_name': 'Rae'},
    };
    server.rows['community_posts'] = {
      memberA: [post],
      memberB: [post],
    };
  });
  tearDown(resetFailureSink);

  const postDone = 'HapticFeedbackType.selectionClick';
  const commentDone = 'HapticFeedbackType.lightImpact';

  Iterable<String> origins() => reported.map((f) => f.origin);
  Iterable<SeenRequest> asB() => server.writes().where((w) => w.who == memberB);

  Future<void> settle(WidgetTester t, [int n = 8]) async {
    for (var i = 0; i < n; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  /// Real time passes and no frame is drawn: the auth event and everything
  /// that follows from it arrive, as in a hidden tab.
  Future<void> noFrame(WidgetTester t) => t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)));

  Future<void> switchTo(WidgetTester t, String uid) =>
      t.runAsync(() => signInAs(uid));

  Future<void> open(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(600, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    container = ProviderContainer();
    addTearDown(container.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CommunityScreen())));
    await settle(t);
    expect(find.text('Hit a PR today'), findsOneWidget, reason: 'premise');
    server.seen.clear();
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 12));
  }

  Future<void> writePost(WidgetTester t) async {
    await t.tap(find.text('Post'));
    await settle(t);
    await t.enterText(
        find.descendant(
            of: find.byType(CreatePostSheet), matching: find.byType(TextField)),
        _draft);
    await t.pump();
  }

  Finder submit() => find.descendant(
      of: find.byType(CreatePostSheet),
      matching: find.widgetWithText(ElevatedButton, postSubmitLabel));

  group('Create Post', () {
    for (final signedOut in [false, true]) {
      final who = signedOut ? 'nobody' : 'B';
      testWidgets(
          "A's draft submitted in the undrawn sheet once $who is signed in: not "
          'published, no points, the sheet goes', (t) async {
        await open(t);
        await writePost(t);
        await t.runAsync(() => signedOut ? signOut() : signInAs(memberB));
        await t.tap(submit(), warnIfMissed: false);
        await settle(t);
        expect(server.writes(), isEmpty,
            reason: "A's text under $who's name: ${server.writes().toList()}");
        expect(find.byType(CreatePostSheet), findsNothing);
        expect(find.text(_draft), findsNothing);
        expect(haptics, isNot(contains(postDone)));
        expect(find.textContaining("Couldn't"), findsNothing);
        await close(t);
      });
    }

    testWidgets('submitted the instant the account changes: nothing is sent, '
        'recorded, nothing is said', (t) async {
      await open(t);
      await writePost(t);
      final press = t.widget<ElevatedButton>(submit()).onPressed!;
      await t.runAsync(() => switchAnd(memberB, press));
      await settle(t);
      expect(server.writes(), isEmpty);
      expect(origins(), contains('CreatePostSheet.identity'));
      expect(origins(), isNot(contains('CreatePostSheet.post')),
          reason: 'it went on to the feed');
      expect(find.textContaining("Couldn't"), findsNothing);
      await close(t);
    });

    testWidgets("the screen's own check, B's feed "
        'already read: nothing is sent, recorded', (t) async {
      await open(t);
      await writePost(t);
      // (dynamic: on 5f8b7f3 it answered nothing to wait for)
      final dynamic onPost =
          t.widget<CreatePostSheet>(find.byType(CreatePostSheet)).onPost;
      await switchTo(t, memberB);
      await noFrame(t);
      await t.runAsync(() async {
        container.read(postNotifierProvider); // B's notifier, made
        await Future<void>.delayed(const Duration(milliseconds: 40));
        Object? refused;
        try {
          await onPost(_draft, parsePostType('workout'));
        } catch (e) {
          refused = e;
        }
        expect(refused, isA<StateError>());
      });
      await settle(t);
      expect(server.writes(), isEmpty);
      await close(t);
    });

    testWidgets('opened, and switched before its first frame: never drawn for '
        'B, and it goes', (t) async {
      await open(t);
      await t.tap(find.text('Post'));
      await t.runAsync(() => signInAs(memberB));
      await t.pump();
      expect(find.text('Create Post'), findsNothing);
      await settle(t);
      expect(find.byType(CreatePostSheet), findsNothing);
      await close(t);
    });

    testWidgets("A's post answers after B signed in: no haptic and no points "
        'for B; it is not in their feed as theirs', (t) async {
      await open(t);
      await writePost(t);
      final hold = server.holds['POST community_posts:$memberA'] = Completer();
      await t.tap(submit());
      await settle(t, 2);
      await switchTo(t, memberB);
      hold.complete();
      await settle(t);
      expect(server.writes('community_posts').single.row['user_id'], memberA);
      expect(asB(), isEmpty);
      expect(haptics, isNot(contains(postDone)));
      expect(find.text(_draft), findsNothing);
      await close(t);
    });

    testWidgets("A's post fails after B signed in: recorded, B is not told, no "
        'draft is left for them', (t) async {
      await open(t);
      await writePost(t);
      final hold = server.holds['POST community_posts:$memberA'] = Completer();
      server.fails.add('POST community_posts:$memberA');
      await t.tap(submit());
      await settle(t, 2);
      await switchTo(t, memberB);
      hold.complete();
      await settle(t);
      expect(origins(), contains('CreatePostSheet.post'));
      expect(find.textContaining("Couldn't"), findsNothing);
      await t.tap(find.text('Post'));
      await settle(t);
      expect(find.text(_draft), findsNothing);
      await close(t);
    });

    for (final offline in [false, true]) {
      testWidgets(
          'a post that fails (${offline ? 'no connection' : 'refused'}): said '
          'once, recorded, the sheet and draft stay, no success; posted again',
          (t) async {
        await open(t);
        await writePost(t);
        (offline ? server.offline : server.fails)
            .add('POST community_posts:$memberA');
        await t.tap(submit());
        await settle(t);
        final hint = offline
            ? 'check your connection and try again.'
            : 'try again in a moment. If it keeps happening, contact support.';
        expect(find.text("Couldn't post that — $hint"), findsOneWidget);
        expect(find.text("Couldn't post that — $hint").hitTestable(),
            findsOneWidget, reason: 'it must be on screen, not under the sheet');
        expect(find.text(_draft), findsOneWidget);
        expect(haptics, isNot(contains(postDone)));
        expect(origins(), contains('CreatePostSheet.post'));
        expect(find.textContaining('SECRET'), findsNothing);
        server.offline.clear();
        server.fails.clear();
        await t.tap(submit());
        await settle(t);
        expect(find.byType(CreatePostSheet), findsNothing);
        expect(haptics, contains(postDone));
        expect(server.writes('community_posts').last.row['content'], _draft);
        await close(t);
      });
    }

    testWidgets('it fails after the sheet was closed: said, and the draft is '
        'back the next time it is opened', (t) async {
      await open(t);
      await writePost(t);
      final hold = server.holds['POST community_posts:$memberA'] = Completer();
      server.fails.add('POST community_posts:$memberA');
      await t.tap(submit());
      await settle(t, 2);
      await t.tap(find.text(postCancelLabel));
      await settle(t);
      expect(find.byType(CreatePostSheet), findsNothing, reason: 'premise');
      hold.complete();
      await settle(t);
      expect(find.text(couldntMessage('post that', null)), findsOneWidget);
      await t.pump(const Duration(seconds: 6)); // the notice goes
      await settle(t);
      await t.tap(find.text('Post'));
      await settle(t);
      expect(find.text(_draft), findsOneWidget);
      // …and is dropped when its member leaves.
      await switchTo(t, memberB);
      await settle(t);
      await switchTo(t, memberA);
      await settle(t);
      await t.tap(find.text('Post'));
      await settle(t);
      expect(find.text(_draft), findsNothing);
      await close(t);
    });

    testWidgets('a second tap while it is out sends nothing more', (t) async {
      await open(t);
      await writePost(t);
      final hold = server.holds['POST community_posts:$memberA'] = Completer();
      await t.tap(submit());
      await t.pump();
      await t.tap(submit(), warnIfMissed: false);
      await settle(t, 2);
      hold.complete();
      await settle(t);
      expect(server.writes('community_posts'), hasLength(1));
      await close(t);
    });

    testWidgets('320 wide, 3x text: the failure is whole, at its size',
        (t) async {
      await open(t);
      await writePost(t);
      server.fails.add('POST community_posts:$memberA');
      await t.tap(submit());
      await settle(t);
      await t.binding.setSurfaceSize(const Size(320, 700));
      t.platformDispatcher.textScaleFactorTestValue = 3;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      final previous = FlutterError.onError;
      final inSheet = <String>[];
      FlutterError.onError = (d) {
        // The page behind the sheet overflows at this size on base too.
        if (d.exceptionAsString().contains('overflowed')) {
          if ('${d.informationCollector?.call()}'.contains('create_post_sheet')) {
            inSheet.add(d.exceptionAsString());
          }
          return;
        }
        previous?.call(d);
      };
      await settle(t, 3);
      FlutterError.onError = previous;
      final text = find.text(couldntMessage('post that', null));
      final p = t.renderObject(text) as RenderBox;
      expect(p.size.width, lessThanOrEqualTo(272));
      expect(t.widget<Text>(text).overflow, isNull);
      expect(inSheet.where((e) => e.contains('bottom')), isEmpty);
      await close(t);
    });

    testWidgets("POSITIVE CONTROL: after a token refresh A's draft is still "
        'there and is posted as A, with its points', (t) async {
      await open(t);
      await writePost(t);
      await t.runAsync(refreshSession);
      await settle(t);
      await t.tap(submit());
      await settle(t);
      final w = server.writes('community_posts').single;
      expect((w.who, w.row['user_id'], w.row['content']),
          (memberA, memberA, _draft));
      expect(server.writes('daily_scores').single.row['user_id'], memberA);
      expect(find.byType(CreatePostSheet), findsNothing);
      expect(haptics, contains(postDone));
      expect(reported, isEmpty);
      await close(t);
    });
  });

  group('comment', () {
    Future<void> write(WidgetTester t) async {
      await t.tap(find.text('Comment'));
      await settle(t);
      await t.enterText(find.byType(TextField), _comment);
      await t.pump();
      haptics.clear();
    }

    testWidgets("A's draft sent from the undrawn box once B is signed in: not "
        'published, cleared', (t) async {
      await open(t);
      await write(t);
      await switchTo(t, memberB);
      await t.tap(find.byIcon(Icons.send), warnIfMissed: false);
      await settle(t);
      expect(server.writes(), isEmpty,
          reason: "A's comment under B's name: ${server.writes().toList()}");
      expect(find.text(_comment), findsNothing);
      expect(haptics, isNot(contains(commentDone)));
      expect(find.textContaining("Couldn't"), findsNothing);
      await close(t);
    });

    testWidgets('sent the instant the account changes: nothing is sent, '
        'recorded, cleared', (t) async {
      await open(t);
      await write(t);
      final send = t
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
          .onPressed!;
      await t.runAsync(() => switchAnd(memberB, send));
      await settle(t);
      expect(server.writes(), isEmpty);
      expect(origins(), contains('PostCard.identity'));
      expect(origins(), isNot(contains('PostCard.comment')));
      expect(find.text(_comment), findsNothing);
      await close(t);
    });

    testWidgets("B's own feed read, the box not redrawn: still nothing",
        (t) async {
      await open(t);
      await write(t);
      final send = t
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
          .onPressed!;
      await switchTo(t, memberB);
      await t.runAsync(() async {
        container.read(postNotifierProvider);
        await Future<void>.delayed(const Duration(milliseconds: 60));
        send();
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      expect(server.writes(), isEmpty);
      await settle(t);
      await close(t);
    });

    testWidgets("A's comment is stored after B signed in: the author is not "
        'notified as B', (t) async {
      await open(t);
      await write(t);
      final hold = server.holds['POST post_comments:$memberA'] = Completer();
      await t.tap(find.byIcon(Icons.send));
      await settle(t, 2);
      await switchTo(t, memberB);
      hold.complete();
      await settle(t);
      expect(server.writes('post_comments').single.row['user_id'], memberA);
      expect(asB(), isEmpty);
      expect(origins(), contains('community.addComment.identity'));
      expect(haptics, isNot(contains(commentDone)));
      await close(t);
    });

    testWidgets("B signs in while the author is looked up: not notified as B",
        (t) async {
      await open(t);
      await write(t);
      // The author read; the feed's own read of the same table is later.
      final hold = server.holds['GET community_posts:$memberA'] = Completer();
      await t.tap(find.byIcon(Icons.send));
      await settle(t, 3);
      expect(server.reads('community_posts', memberA), isNotEmpty,
          reason: 'premise');
      await switchTo(t, memberB);
      hold.complete();
      await settle(t);
      expect(server.writes('notifications'), isEmpty);
      expect(origins(), contains('community.addComment.identity'));
      await close(t);
    });

    for (final offline in [false, true]) {
      testWidgets(
          'a comment that fails (${offline ? 'no connection' : 'refused'}): '
          'said once, recorded, the text is kept, no success', (t) async {
        await open(t);
        await write(t);
        (offline ? server.offline : server.fails)
            .add('POST post_comments:$memberA');
        await t.tap(find.byIcon(Icons.send));
        await settle(t);
        final hint = offline
            ? 'check your connection and try again.'
            : 'try again in a moment. If it keeps happening, contact support.';
        expect(find.text("Couldn't post that comment — $hint"), findsOneWidget);
        expect(find.text(_comment), findsOneWidget);
        expect(haptics, isNot(contains(commentDone)));
        expect(origins(), ['PostCard.comment']);
        await close(t);
      });
    }

    testWidgets("it fails after B signed in: B is not told", (t) async {
      await open(t);
      await write(t);
      final hold = server.holds['POST post_comments:$memberA'] = Completer();
      server.fails.add('POST post_comments:$memberA');
      await t.tap(find.byIcon(Icons.send));
      await settle(t, 2);
      await switchTo(t, memberB);
      hold.complete();
      await settle(t);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text(_comment), findsNothing);
      expect(origins(), contains('PostCard.comment'));
      await close(t);
    });

    test('signed out: a comment that cannot be sent is not taken for sent',
        () async {
      await signOut();
      await expectLater(
          LiveCommunityService().addComment('p1', 'hi'), throwsException);
      expect(server.writes(), isEmpty);
    });

    testWidgets('POSITIVE CONTROL: sent as its member after a token refresh, '
        'the author told, then the haptic', (t) async {
      await open(t);
      await write(t);
      await t.runAsync(refreshSession);
      await settle(t);
      expect(find.text(_comment), findsOneWidget);
      await t.tap(find.byIcon(Icons.send));
      await settle(t);
      final w = server.writes('post_comments').single;
      expect((w.who, w.row['user_id'], w.row['content']),
          (memberA, memberA, _comment));
      expect(server.writes('notifications').single.row['recipient_id'],
          'author-1');
      expect(find.text(_comment), findsNothing);
      expect(haptics, contains(commentDone));
      expect(reported, isEmpty);
      await close(t);
    });
  });

  group('reaction', () {
    testWidgets("tapped in A's undrawn card once B is signed in: nothing is "
        'sent, nothing is said, nothing is thrown', (t) async {
      await open(t);
      await switchTo(t, memberB);
      await t.tap(find.text('Like'), warnIfMissed: false);
      await settle(t);
      expect(server.writes(), isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      expect(t.takeException(), isNull);
      await close(t);
    });

    testWidgets("B signs in between A's look-up and the write: nothing is "
        'written, nothing is thrown', (t) async {
      await open(t);
      final hold = server.holds['GET post_reactions:$memberA'] = Completer();
      await t.tap(find.text('Like'));
      await settle(t, 2);
      await switchTo(t, memberB);
      hold.complete();
      await settle(t);
      expect(server.writes(), isEmpty,
          reason: 'sent as B: ${server.writes().toList()}');
      expect(find.byType(SnackBar), findsNothing);
      expect(t.takeException(), isNull);
      await close(t);
    });

    testWidgets("A's reaction is stored after B signed in: it is not counted "
        "in B's feed", (t) async {
      await open(t);
      final hold = server.holds['POST post_reactions:$memberA'] = Completer();
      await t.tap(find.text('Like'));
      await settle(t, 3);
      expect(server.writes('post_reactions'), hasLength(1), reason: 'premise');
      await switchTo(t, memberB);
      hold.complete();
      await settle(t);
      expect(find.text('Liked'), findsNothing);
      expect(
          container
              .read(postNotifierProvider)
              .requireValue
              .single
              .reactions
              .where((r) => r.userId == memberA),
          isEmpty);
      await close(t);
    });

    testWidgets('one that fails is said and recorded, not thrown', (t) async {
      await open(t);
      server.fails.add('POST post_reactions:$memberA');
      await t.tap(find.text('Like'));
      await settle(t);
      expect(find.text(couldntMessage('save your reaction', null)),
          findsOneWidget);
      expect(origins(), ['PostCard.reaction']);
      expect(find.text('Liked'), findsNothing);
      expect(t.takeException(), isNull);
      await close(t);
    });

    testWidgets('POSITIVE CONTROL: stored as its member', (t) async {
      await open(t);
      await t.tap(find.text('Like'));
      await settle(t);
      expect(server.writes('post_reactions').single.row['user_id'], memberA);
      expect(find.text('Liked'), findsOneWidget);
      expect(find.byType(ReactionBar), findsOneWidget);
      expect(reported, isEmpty);
      await close(t);
    });
  });
}
