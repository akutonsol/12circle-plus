import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/features/ai_coach/domain/coach_surface.dart';
import 'package:circle_fitness/features/ai_coach/presentation/widgets/coach_surface_tabs.dart';

// FIT-102 … FIT-110 · `/ai-coach` has two surfaces, and they are tabs.
//
// Nine anchors are drawn on this route and every one carries `Back`, a
// `Coaching` tab and a `Conversation` tab. There were no tabs. Both surfaces
// existed but were mutually exclusive on an implementation detail:
//
//     child: _messages.length <= 1 ? <the eight cards> : <the conversation>
//
// Send one message and the cards were gone — the daily brief, the weekly
// review, the goal projection, the risk card, the persona picker and the
// coaching memory, which are this screen's ONLY write surfaces — unreachable
// for the rest of the session, with no control anywhere that brought them
// back.
//
// The tab bar is tested here rather than through `AICoachScreen`, which
// reaches Supabase on build: a test of the whole screen would assert against
// the harness, not the tabs. See `CoachSurfaceTabs`' own note.

Future<CoachSurface> _pump(WidgetTester tester,
    {CoachSurface initial = CoachSurface.coaching}) async {
  var current = initial;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      // A Column, as the screen has it. In a full-height `body:` the tab's
      // Container has `alignment:` and BOUNDED constraints, so it expands to
      // fill and measures 590 dp whether or not it has a 44 dp floor — which
      // is exactly how the first version of the floor test passed against a
      // deleted constraint. Under a Column the height is unbounded and the
      // floor is what decides it, as in production.
      body: StatefulBuilder(
        builder: (context, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
          CoachSurfaceTabs(
          selected: current,
          onSelect: (s) => setState(() => current = s),
          background: const Color(0xFF15151A),
          accent: const Color(0xFF8B5CF6),
          border: const Color(0xFF2A2A31),
          selectedText: const Color(0xFFFFFFFF),
          unselectedText: const Color(0xFF8A8A94),
          ),
        ]),
      ),
    ),
  ));
  await tester.pump();
  return current;
}

void main() {
  testWidgets('both surfaces are offered, as a mutually exclusive pair',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);

    for (final s in CoachSurface.values) {
      final node = tester
          .getSemantics(find.bySemanticsLabel(s.label))
          .getSemanticsData();
      expect(node.hasFlag(SemanticsFlag.isInMutuallyExclusiveGroup), isTrue,
          reason: '${s.label} is drawn as a tab on all nine anchors');
      expect(node.hasAction(SemanticsAction.tap), isTrue,
          reason: 'excludeSemantics drops child actions — the tap must be '
              're-declared on the Semantics (F-20)');
    }

    handle.dispose();
  });

  testWidgets('the selected tab says so, and only one does', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);

    bool selected(CoachSurface s) => tester
        .getSemantics(find.bySemanticsLabel(s.label))
        .getSemanticsData()
        .hasFlag(SemanticsFlag.isSelected);

    expect(selected(CoachSurface.coaching), isTrue,
        reason: 'the screen opens on the coaching surface');
    expect(selected(CoachSurface.conversation), isFalse);

    await tester.tap(find.bySemanticsLabel(CoachSurface.conversation.label));
    await tester.pump();

    expect(selected(CoachSurface.conversation), isTrue);
    expect(selected(CoachSurface.coaching), isFalse,
        reason: 'two selected tabs is not a tab bar');

    handle.dispose();
  });

  testWidgets('each tab clears the 44 dp floor', (tester) async {
    await _pump(tester);
    for (final s in CoachSurface.values) {
      // Keyed, NOT `find.ancestor(… GestureDetector)`. That version measured
      // an enclosing detector at 590 dp and passed with the floor deleted —
      // the mutation K4 survived against it, which is how it was found.
      final size = tester.getSize(find.byKey(coachTabTargetKey(s)));
      expect(size.height, greaterThanOrEqualTo(44.0),
          reason: '${s.label} is below the 44 dp floor');
      expect(size.height, lessThan(200.0),
          reason: 'if this is hundreds of dp the finder has climbed out of '
              'the tab again and the assertion above means nothing');
    }
  });

  group('the rule itself', () {
    test('sending always lands the user where the answer appears', () {
      // A suggested prompt is tapped on the coaching surface and the reply
      // arrives on the other one.
      for (final s in CoachSurface.values) {
        expect(surfaceAfterSending(s), CoachSurface.conversation);
      }
    });

    test('only the conversation carries the composer', () {
      // FIT-108/109 declare the General/Nutrition/Workout chips and the input
      // on the conversation anchors. A composer beside a goal-projection card
      // answers nothing.
      expect(showsComposer(CoachSurface.conversation), isTrue);
      expect(showsComposer(CoachSurface.coaching), isFalse);
    });

    test('the board names both surfaces and the input', () {
      expect(CoachSurface.coaching.label, 'Coaching');
      expect(CoachSurface.conversation.label, 'Conversation');
      expect(askYourCoachHint, 'Ask your coach');
    });
  });

  // ── A SOURCE assertion, and labelled as one ───────────────────────────────
  //
  // The claim that matters is that the SCREEN no longer picks a body from the
  // message count. That is not reachable from a widget test: `AICoachScreen`
  // builds eight cards which each reach Supabase, and initialising Supabase in
  // a test would make this assert against the harness rather than the screen.
  //
  // So this reads the source, and is worth exactly what a source assertion is
  // worth — it proves the branch was removed, not that the tabs behave. The
  // behaviour is covered above, on the extracted widget. Recorded this way
  // rather than dressed up as runtime coverage.
  group('the screen no longer chooses for the user [SOURCE]', () {
    late String src;
    setUpAll(() {
      src = File('lib/features/ai_coach/presentation/ai_coach_screen.dart')
          .readAsStringSync()
          .split('\n')
          .map((l) {
            final i = l.indexOf('//');
            return i < 0 ? l : l.substring(0, i);
          })
          .join('\n');
    });

    test('the body is chosen by the surface, not by how many messages exist',
        () {
      expect(src.contains('_messages.length <= 1'), isFalse,
          reason: 'this single condition is what made the eight intelligence '
              'cards unreachable after one message');
      expect(src, contains('_surface == CoachSurface.coaching'));
    });

    test('the composer is gated on the surface', () {
      expect(src, contains('showsComposer(_surface)'));
    });

    test('sending moves the user to the conversation', () {
      expect(src, contains('_surface = surfaceAfterSending(_surface)'));
    });
  });
}
