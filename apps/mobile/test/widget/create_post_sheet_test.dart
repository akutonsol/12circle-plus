import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/features/community/data/models/post_model.dart';
import 'package:circle_fitness/features/community/domain/post_type_choice.dart';
import 'package:circle_fitness/features/community/presentation/widgets/create_post_sheet.dart';
import 'package:circle_fitness/features/community/presentation/widgets/post_type_selector.dart';

// FIT-067 · "Create post". The board marks this anchor `missing` and names the
// capability it should be using: `addPost(content, postType)`.
//
// `post_model.dart` already declares
// `enum PostType { text, photo, progress, workout, achievement }` — exactly
// the five the board draws as radios. Every layer between that enum and the
// database dropped it somewhere else:
//
//   1. the chips were dead — three of the five, each handed `() {}`;
//   2. the write ignored the type — `addPost(text)` with no `postType:`, so
//      every post this app created was stored as 'general';
//   3. the read could not recover it — `_parseType` mapped only 'progress'
//      and 'achievement', sending 'photo' and 'workout' to `text`, so two of
//      the five could not survive a write-and-read.

Future<List<(String, PostType)>> _pump(WidgetTester tester) async {
  final posted = <(String, PostType)>[];
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: CreatePostSheet(onPost: (c, t) => posted.add((c, t))),
      ),
    ),
  ));
  await tester.pump();
  return posted;
}

void main() {
  testWidgets('all five types are offered, as one mutually exclusive choice',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);

    expect(PostType.values, hasLength(5));
    for (final t in PostType.values) {
      final node = tester
          .getSemantics(find.bySemanticsLabel(postTypeLabel(t)))
          .getSemanticsData();
      expect(node.hasFlag(SemanticsFlag.isInMutuallyExclusiveGroup), isTrue,
          reason: '${postTypeLabel(t)} is role="radio" on the board; three '
              'unrelated buttons are not a choice');
      expect(node.hasAction(SemanticsAction.tap), isTrue,
          reason: 'the shipped chips were handed `() {}` — they looked '
              'selectable and were read by nothing');
    }

    handle.dispose();
  });

  testWidgets('exactly one is selected, and tapping moves it', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);

    bool sel(PostType t) => tester
        .getSemantics(find.bySemanticsLabel(postTypeLabel(t)))
        .getSemanticsData()
        .hasFlag(SemanticsFlag.isSelected);

    expect(PostType.values.where(sel), hasLength(1));
    expect(sel(PostType.text), isTrue);

    await tester.tap(find.bySemanticsLabel(postTypeLabel(PostType.workout)));
    await tester.pump();

    expect(sel(PostType.workout), isTrue);
    expect(sel(PostType.text), isFalse);
    expect(PostType.values.where(sel), hasLength(1));

    handle.dispose();
  });

  testWidgets('the chosen type reaches the caller', (tester) async {
    final posted = await _pump(tester);

    await tester.enterText(find.byType(TextField), 'Squat PB today');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel(postTypeLabel(PostType.achievement)));
    await tester.pump();
    await tester.tap(find.text(postSubmitLabel));
    await tester.pump();

    expect(posted, hasLength(1));
    expect(posted.single.$1, 'Squat PB today');
    expect(posted.single.$2, PostType.achievement,
        reason: 'the screen called addPost(content) with no postType, so '
            'every post it wrote was stored as the default');
  });

  testWidgets('an empty post cannot be published', (tester) async {
    final posted = await _pump(tester);

    await tester.tap(find.text(postSubmitLabel));
    await tester.pump();
    expect(posted, isEmpty);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    await tester.tap(find.text(postSubmitLabel));
    await tester.pump();
    expect(posted, isEmpty, reason: 'whitespace is not a post');

    await tester.enterText(find.byType(TextField), 'ok');
    await tester.pump();
    await tester.tap(find.text(postSubmitLabel));
    await tester.pump();
    expect(posted, hasLength(1));
  });

  testWidgets('each type chip clears the 44 dp floor', (tester) async {
    await _pump(tester);
    for (final t in PostType.values) {
      final size = tester.getSize(find.byKey(ValueKey('post-type-${t.name}')));
      expect(size.height, greaterThanOrEqualTo(44.0));
      expect(size.height, lessThan(200.0),
          reason: 'a finder that has climbed out of the chip makes the '
              'assertion above meaningless');
    }
  });

  testWidgets('the sheet carries the board\'s copy', (tester) async {
    await _pump(tester);
    expect(find.text(composerHint), findsOneWidget);
    expect(find.text(postSubmitLabel), findsOneWidget);
    expect(find.text(postCancelLabel), findsOneWidget);
    expect(find.byType(PostTypeSelector), findsOneWidget);
  });

  group('the type survives a write and a read', () {
    test('every value round-trips', () {
      // `_parseType` mapped only 'progress' and 'achievement'. A post saved as
      // a workout came back as text.
      for (final t in PostType.values) {
        expect(parsePostType(postTypeWire(t)), t,
            reason: '${t.name} does not survive write-then-read');
      }
    });

    test('existing rows are not re-typed', () {
      // Every post this app has written so far carries 'general'.
      expect(parsePostType('general'), PostType.text);
      expect(parsePostType(null), PostType.text);
      expect(parsePostType('something new'), PostType.text);
    });

    test('the board\'s words', () {
      expect(PostType.values.map(postTypeLabel),
          ['Text', 'Photo', 'Progress', 'Workout', 'Achievement']);
      expect(composerHint, 'What\'s on your mind?');
      expect(postSubmitLabel, 'Post');
    });
  });
}
