import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/checkins/presentation/widgets/checkin_pickers.dart';

/// F-22 · `/daily-checkin` — the two choice rows announced nothing.
///
/// ── THE DEFECT ─────────────────────────────────────────────────────────────
/// The weekly check-in is five mood faces and two rows of five numbers. All
/// fifteen were bare `GestureDetector`s. A screen reader read five emoji and
/// the words "Rough Meh Good Great Amazing", then "1 2 3 4 5", then "1 2 3 4
/// 5" again — **no role, no group, and no indication of which one was
/// chosen**, on a form whose entire purpose is to report how the client feels
/// and which their coach reads.
///
/// Worse than an unnamed button: a blind client could fill this form, submit
/// it, and have no way to know what they had said.
///
/// ── NOTHING HERE IS INVENTED ───────────────────────────────────────────────
/// The mood options are named by the label **already drawn under each face**.
/// The number options are named from the **section heading already drawn above
/// the row** plus the number already drawn inside it — "Energy Level 3 of 5" —
/// because a screen reader announces one option at a time and "3" alone says
/// nothing about what was rated. `inMutuallyExclusiveGroup` and `selected` are
/// facts about the widget, not copy.
void main() {
  const moodLabels = ['Rough', 'Meh', 'Good', 'Great', 'Amazing'];
  const moodEmojis = ['😞', '😐', '😊', '😄', '🤩'];

  Widget host(Widget child) => MaterialApp(
        home: Scaffold(
          body: Column(mainAxisSize: MainAxisSize.min, children: [child]),
        ),
      );

  group('F-22 the mood row', () {
    testWidgets('every option announces its own drawn label', (t) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(host(MoodPicker(
        selected: 3,
        emojis: moodEmojis,
        labels: moodLabels,
        onTap: (_) {},
      )));

      for (final label in moodLabels) {
        expect(find.bySemanticsLabel(label), findsOneWidget,
            reason: '"$label" is already printed under the face — the name '
                'costs no new copy');
      }
      handle.dispose();
    });

    testWidgets('the chosen option is the only one reported as selected',
        (t) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(host(MoodPicker(
        selected: 3, // "Good"
        emojis: moodEmojis,
        labels: moodLabels,
        onTap: (_) {},
      )));

      for (var i = 0; i < moodLabels.length; i++) {
        final d = t
            .getSemantics(find.bySemanticsLabel(moodLabels[i]))
            .getSemanticsData();
        expect(d.hasFlag(SemanticsFlag.isSelected), i == 2,
            reason: '${moodLabels[i]} selected state is wrong');
        expect(d.hasFlag(SemanticsFlag.isInMutuallyExclusiveGroup), isTrue,
            reason: 'these five are one choice, not five independent buttons');
      }
      handle.dispose();
    });

    testWidgets('the emoji does not leak into the announcement', (t) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(host(MoodPicker(
        selected: 1,
        emojis: moodEmojis,
        labels: moodLabels,
        onTap: (_) {},
      )));

      // "😞 Rough" is not a name. Doubling an announcement is a mistake this
      // repository has already made once (auth_design.dart).
      expect(find.bySemanticsLabel('😞'), findsNothing);
      expect(find.bySemanticsLabel('😞\nRough'), findsNothing);
      handle.dispose();
    });

    testWidgets('each option is still pressable from the tree', (t) async {
      // `excludeSemantics: true` drops the child's ACTIONS along with its
      // labels — the defect F-9's device probe found in the intake back
      // button. Assert the action, not just the name.
      final handle = t.ensureSemantics();
      var picked = 0;
      await t.pumpWidget(host(MoodPicker(
        selected: 1,
        emojis: moodEmojis,
        labels: moodLabels,
        onTap: (v) => picked = v,
      )));

      final d = t.getSemantics(find.bySemanticsLabel('Great')).getSemanticsData();
      expect(d.hasAction(SemanticsAction.tap), isTrue,
          reason: 'announced as a button it cannot press is worse than unnamed');

      await t.tap(find.bySemanticsLabel('Great'));
      expect(picked, 4);
      handle.dispose();
    });
  });

  group('F-22 the number rows', () {
    testWidgets('options say WHAT they are rating, not just a digit',
        (t) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(host(NumberPicker(
        scale: 'Energy Level',
        value: 3,
        onChanged: (_) {},
      )));

      for (var n = 1; n <= 5; n++) {
        expect(find.bySemanticsLabel('Energy Level $n of 5'), findsOneWidget);
      }
      // A bare digit is what shipped, and it is what must not come back.
      expect(find.bySemanticsLabel('3'), findsNothing);
      handle.dispose();
    });

    testWidgets('two rows on one screen stay distinguishable', (t) async {
      // Energy and Stress are identical rows of 1-5. Without the scale in the
      // name a screen reader gives the same ten announcements twice and the
      // client cannot tell which row they are in.
      final handle = t.ensureSemantics();
      await t.pumpWidget(host(Column(mainAxisSize: MainAxisSize.min, children: [
        NumberPicker(scale: 'Energy Level', value: 3, onChanged: (_) {}),
        NumberPicker(scale: 'Stress Level', value: 2, onChanged: (_) {}),
      ])));

      expect(find.bySemanticsLabel('Energy Level 3 of 5'), findsOneWidget);
      expect(find.bySemanticsLabel('Stress Level 2 of 5'), findsOneWidget);

      expect(
          t
              .getSemantics(find.bySemanticsLabel('Energy Level 3 of 5'))
              .getSemanticsData()
              .hasFlag(SemanticsFlag.isSelected),
          isTrue);
      expect(
          t
              .getSemantics(find.bySemanticsLabel('Energy Level 2 of 5'))
              .getSemanticsData()
              .hasFlag(SemanticsFlag.isSelected),
          isFalse,
          reason: 'the Stress row\'s selection must not bleed into Energy');
      handle.dispose();
    });

    testWidgets('the selected number is reported, and only that one', (t) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(host(NumberPicker(
        scale: 'Stress Level',
        value: 4,
        onChanged: (_) {},
      )));

      for (var n = 1; n <= 5; n++) {
        final d = t
            .getSemantics(find.bySemanticsLabel('Stress Level $n of 5'))
            .getSemanticsData();
        expect(d.hasFlag(SemanticsFlag.isSelected), n == 4);
        expect(d.hasFlag(SemanticsFlag.isInMutuallyExclusiveGroup), isTrue);
      }
      handle.dispose();
    });

    testWidgets('each number is pressable from the tree', (t) async {
      final handle = t.ensureSemantics();
      var picked = 0;
      await t.pumpWidget(host(NumberPicker(
        scale: 'Energy Level',
        value: 1,
        onChanged: (v) => picked = v,
      )));

      await t.tap(find.bySemanticsLabel('Energy Level 5 of 5'));
      expect(picked, 5);
      handle.dispose();
    });
  });
}
