import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/classes/domain/whats_on.dart';
import 'package:circle_fitness/features/community/data/models/post_model.dart';
import 'package:circle_fitness/features/messaging/domain/connect_sections.dart';

/// FIT-005 · Connect — "Coach, community and pods in one relationship layer".
///
/// `/messages` was a conversation list. The anchor makes it the place a client
/// sees every relationship they have, which means three more reads behind one
/// screen — and therefore the same rule FIT-027 is built around, for the same
/// reason:
///
/// **A section whose source failed must never be drawn as a section with
/// nothing in it.** A relationship layer that quietly omits your groups when
/// the read fails is telling you that you have none. Under a heading that says
/// "Groups", an absence is an answer.
void main() {
  CommunityPost post({
    String user = 'Priya',
    String content = 'Hit 70 kg on the hinge today',
    DateTime? at,
  }) =>
      CommunityPost(
        id: 'p1',
        userId: 'u1',
        userName: user,
        userRole: 'client',
        content: content,
        type: PostType.text,
        imageUrls: const [],
        reactions: const [],
        comments: const [],
        createdAt: at ?? DateTime(2026, 9, 23, 6),
      );

  // Named `aGroup` because `group` is the test framework's own.
  CommunityGroup aGroup({String name = 'Tues Lifters', int members = 12}) =>
      CommunityGroup(
        id: 'g1',
        name: name,
        description: '',
        emoji: '🏋️',
        memberCount: members,
        isJoined: true,
      );

  group('FIT-005 a failed section is never an empty one', () {
    test('a failed read is `failed`, not `empty`', () {
      final r = teaserFrom(
          AsyncError<List<CommunityPost>>(Exception('x'), StackTrace.empty));
      expect(r.state, ConnectSectionState.failed);
      expect(r.items, isEmpty);
    });

    test('a failure carrying stale rows contributes none of them', () {
      // Riverpod hands an AsyncError its previous value during a refresh, so
      // `.valueOrNull` returns last week's posts. Showing those under a live
      // heading is a quieter version of the same lie — and reaching for
      // `.valueOrNull` is exactly how the /profile collapse worked.
      final stale =
          AsyncError<List<CommunityPost>>(Exception('x'), StackTrace.empty)
              .copyWithPrevious(AsyncData([post()]));
      expect(stale.valueOrNull, isNotNull, reason: 'guard the premise');

      final r = teaserFrom(stale);
      expect(r.state, ConnectSectionState.failed);
      expect(r.items, isEmpty);
    });

    test('a genuinely empty read is `empty`, which is a real answer', () {
      expect(teaserFrom(const AsyncData<List<CommunityPost>>([])).state,
          ConnectSectionState.empty);
    });

    test('still loading is neither', () {
      expect(teaserFrom(const AsyncLoading<List<CommunityPost>>()).state,
          ConnectSectionState.loading);
    });

    test('a refresh in flight keeps showing what it already has', () {
      final refreshing = const AsyncLoading<List<CommunityPost>>()
          .copyWithPrevious(AsyncData([post()]));
      final r = teaserFrom(refreshing);
      expect(r.state, ConnectSectionState.data);
      expect(r.items, hasLength(1));
    });

    test('a teaser shows at most two rows, in order', () {
      final r = teaserFrom(AsyncData([
        post(user: 'A'),
        post(user: 'B'),
        post(user: 'C'),
      ]));
      expect(r.items, hasLength(2));
      expect(r.items.map((p) => p.userName), ['A', 'B']);
    });
  });

  group('FIT-005 the What\'s on teaser reuses FIT-027', () {
    WhatsOnItem item(String id, DateTime when) => WhatsOnItem(
          id: id,
          kind: WhatsOnKind.classes,
          when: when,
          title: 'Reformer',
          detail: 'Class · Studio 2 · 4 places left',
        );

    test('rows pass through, capped at two', () {
      final r = whatsOnTeaser(AsyncData((
        items: [
          item('a', DateTime(2026, 9, 11)),
          item('b', DateTime(2026, 9, 12)),
          item('c', DateTime(2026, 9, 13)),
        ],
        failed: <WhatsOnKind>{},
      )));
      expect(r.state, ConnectSectionState.data);
      expect(r.items.map((i) => i.id), ['a', 'b']);
    });

    test('a partial failure with NO surviving rows is a failure, not empty', () {
      // All three sources behind the merged list failed, or the ones that
      // worked had nothing. Either way the teaser knows nothing, and "What's
      // on" with nothing under it says there is nothing on.
      final r = whatsOnTeaser(AsyncData((
        items: <WhatsOnItem>[],
        failed: {WhatsOnKind.classes},
      )));
      expect(r.state, ConnectSectionState.failed);
    });

    test('a partial failure WITH surviving rows still shows them', () {
      // The full screen names which source failed; the teaser shows what it
      // has and sends the client there. Hiding working rows would be the
      // over-correction.
      final r = whatsOnTeaser(AsyncData((
        items: [item('a', DateTime(2026, 9, 11))],
        failed: {WhatsOnKind.events},
      )));
      expect(r.state, ConnectSectionState.data);
      expect(r.items, hasLength(1));
    });

    test('genuinely nothing on is empty, not failed', () {
      final r = whatsOnTeaser(AsyncData((
        items: <WhatsOnItem>[],
        failed: <WhatsOnKind>{},
      )));
      expect(r.state, ConnectSectionState.empty);
    });
  });

  group('FIT-005 row lines follow the anchor', () {
    final now = DateTime(2026, 9, 23, 8);

    test('a post reads "<name> <content> · <age>"', () {
      // The anchor draws "Priya Hit 70 kg on the hinge today 🙂 2h".
      expect(postLine(post(at: DateTime(2026, 9, 23, 6)), now: now),
          'Priya Hit 70 kg on the hinge today · 2h');
    });

    test('a long post is truncated rather than allowed to run', () {
      final line = postLine(
          post(content: 'x' * 200, at: now.subtract(const Duration(hours: 1))),
          now: now);
      expect(line.length, lessThan(90));
      expect(line, contains('…'));
    });

    test('a group reads "<name> · <n> members", singular at one', () {
      expect(groupLine(aGroup()), 'Tues Lifters · 12 members');
      expect(groupLine(aGroup(members: 1)), 'Tues Lifters · 1 member');
    });

    test('ages use the anchor\'s shorthand', () {
      expect(relativeAge(now, now: now), 'now');
      expect(relativeAge(now.subtract(const Duration(minutes: 5)), now: now), '5m');
      expect(relativeAge(now.subtract(const Duration(hours: 2)), now: now), '2h');
      expect(relativeAge(now.subtract(const Duration(days: 3)), now: now), '3d');
    });

    test('a zero-member group still reads as members, not "0 member"', () {
      expect(groupLine(aGroup(members: 0)), 'Tues Lifters · 0 members');
    });
  });

  test('FIT-005 the failure lines are strings the repository already ships', () {
    // `community_screen.dart:246` renders the first verbatim; the second
    // follows the "Could not load [noun]" pattern used in fifteen files, with
    // the noun taken from the package's own declared label "Groups".
    expect(connectFeedFailure, 'Could not load posts');
    expect(connectGroupsFailure, 'Could not load groups');
    for (final line in [connectFeedFailure, connectGroupsFailure]) {
      expect(line, isNot(contains('Exception')));
    }
  });
}
