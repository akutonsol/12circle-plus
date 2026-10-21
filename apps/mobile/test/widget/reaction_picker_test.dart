import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/features/community/data/models/post_model.dart';
import 'package:circle_fitness/features/community/domain/reaction_choice.dart';
import 'package:circle_fitness/features/community/presentation/widgets/reaction_picker.dart';

// FIT-065 / FIT-066 · the five reactions.
//
// The same defect as the post type, one layer over. `ReactionType` declares
// five, `toggleReaction(postId, reactionType)` takes the type, and
// `_parseReaction` maps all five on the way back — but the provider hardcoded
// one:
//
//     Future<void> toggleLike(String postId) async {
//       await _svc.toggleReaction(postId, 'like');   // always
//
// So four of the five could be READ by this app and never written by it. The
// UI offered a single heart, and the tally was drawn as bare emoji — which a
// screen reader reads as emoji characters and a bare integer, saying nothing
// about what they are.

PostReaction _r(String uid, ReactionType t) =>
    PostReaction(userId: uid, type: t);

Future<List<ReactionType>> _pump(
  WidgetTester tester, {
  List<PostReaction> reactions = const [],
  String? uid = 'me',
}) async {
  final taps = <ReactionType>[];
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Column(mainAxisSize: MainAxisSize.min, children: [
        ReactionPicker(
            reactions: reactions, uid: uid, onReact: taps.add),
      ]),
    ),
  ));
  await tester.pump();
  return taps;
}

void main() {
  testWidgets('all five are reachable, and each one is named', (tester) async {
    final handle = tester.ensureSemantics();
    final taps = await _pump(tester);

    expect(ReactionType.values, hasLength(5));
    for (final t in ReactionType.values) {
      final node = tester
          .getSemantics(find.bySemanticsLabel(reactionLabel(t)))
          .getSemanticsData();
      expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
      expect(node.hasAction(SemanticsAction.tap), isTrue);
    }

    await tester.tap(find.bySemanticsLabel(reactionLabel(ReactionType.strong)));
    expect(taps, [ReactionType.strong],
        reason: 'four of the five could not be written at all before');

    handle.dispose();
  });

  testWidgets('the name carries the count, the way the board writes it',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, reactions: [
      for (var i = 0; i < 12; i++) _r('u$i', ReactionType.like),
      for (var i = 0; i < 3; i++) _r('v$i', ReactionType.strong),
    ]);

    // `Like, 12 so far` — and plain `Fire` where nobody has reacted, which is
    // the board's own asymmetry: no tally, nothing to announce.
    expect(find.bySemanticsLabel('Like, 12 so far'), findsOneWidget);
    expect(find.bySemanticsLabel('Strong, 3 so far'), findsOneWidget);
    expect(find.bySemanticsLabel('Fire'), findsOneWidget);
    expect(find.bySemanticsLabel('Clap'), findsOneWidget);

    handle.dispose();
  });

  testWidgets('mine is marked selected, and only mine', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, reactions: [
      _r('me', ReactionType.fire),
      _r('someone', ReactionType.like),
    ]);

    bool sel(ReactionType t) => tester
        .getSemantics(find.bySemanticsLabel(reactionSemanticLabel(
            t, t == ReactionType.fire || t == ReactionType.like ? 1 : 0)))
        .getSemanticsData()
        .hasFlag(SemanticsFlag.isSelected);

    expect(sel(ReactionType.fire), isTrue);
    expect(sel(ReactionType.like), isFalse,
        reason: 'someone else left that one');

    handle.dispose();
  });

  testWidgets('each control clears the 44 dp floor', (tester) async {
    await _pump(tester);
    for (final t in ReactionType.values) {
      final size = tester.getSize(find.byKey(ValueKey('reaction-${t.name}')));
      expect(size.height, greaterThanOrEqualTo(44.0));
      expect(size.width, greaterThanOrEqualTo(44.0));
      expect(size.height, lessThan(200.0),
          reason: 'a finder that has climbed out makes this meaningless');
    }
  });

  group('the rules', () {
    test('counts are per type, and zero is a real answer', () {
      final c = reactionCounts([
        _r('a', ReactionType.like),
        _r('b', ReactionType.like),
        _r('c', ReactionType.clap),
      ]);
      expect(c[ReactionType.like], 2);
      expect(c[ReactionType.clap], 1);
      expect(c[ReactionType.fire], 0,
          reason: 'every type must be present, so a missing one is not an '
              'absent key that reads as null downstream');
    });

    test('the name only carries a count when there is one', () {
      expect(reactionSemanticLabel(ReactionType.like, 12), 'Like, 12 so far');
      expect(reactionSemanticLabel(ReactionType.fire, 0), 'Fire');
    });

    test('state is not written into the name', () {
      // It rides on `selected`, so a reader announces it in the user's own
      // language — the rule habit_row and grocery_list follow.
      for (final t in ReactionType.values) {
        expect(reactionSemanticLabel(t, 3).toLowerCase(),
            isNot(contains('selected')));
      }
    });

    test('mine is found by uid, and nobody\'s when signed out', () {
      final rs = [_r('me', ReactionType.love), _r('other', ReactionType.fire)];
      expect(myReaction(rs, 'me'), ReactionType.love);
      expect(myReaction(rs, 'other'), ReactionType.fire);
      expect(myReaction(rs, 'nobody'), isNull);
      expect(myReaction(rs, null), isNull);
    });

    test('every type survives a write and a read', () {
      for (final t in ReactionType.values) {
        expect(parseReactionType(reactionWire(t)), t);
      }
      expect(parseReactionType(null), ReactionType.like);
      expect(parseReactionType('something new'), ReactionType.like);
    });
  });

  // The decision the service makes, lifted out so it can be tested. It had
  // two branches — row exists, delete; no row, insert — so choosing a
  // DIFFERENT reaction fell into the delete branch and removed the old one,
  // leaving nothing. Invisible with one reaction in the UI. With five it is
  // the common case: every change of mind silently became a removal.
  group('what a tap does to the stored row', () {
    test('nothing there yet is an insert', () {
      expect(
        reactionWriteFor(existingType: null, chosen: ReactionType.fire),
        ReactionWrite.insert,
      );
    });

    test('the same one again takes it back', () {
      expect(
        reactionWriteFor(existingType: 'fire', chosen: ReactionType.fire),
        ReactionWrite.remove,
      );
    });

    test('a DIFFERENT one switches — it does not delete', () {
      for (final from in ReactionType.values) {
        for (final to in ReactionType.values) {
          if (from == to) continue;
          expect(
            reactionWriteFor(existingType: reactionWire(from), chosen: to),
            ReactionWrite.change,
            reason: '${from.name} -> ${to.name} used to remove the ${from.name} '
                'and leave nothing; UNIQUE(post_id, user_id) means an insert '
                'could not have replaced it either',
          );
        }
      }
    });

    test('a legacy or unrecognised stored value still switches cleanly', () {
      // Rows written before the type was wired carry whatever the default
      // was. Treating one as "the same" would make the first tap a no-op.
      expect(
        reactionWriteFor(existingType: 'general', chosen: ReactionType.like),
        ReactionWrite.change,
      );
    });
  });
}
