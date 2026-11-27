import 'package:circle_fitness/features/ai_nutrition/domain/ai_nutrition_provider.dart';
import 'package:circle_fitness/features/ai_nutrition/domain/chat_turn.dart';
import 'package:circle_fitness/features/ai_nutrition/presentation/widgets/ai_chat_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';

import '../support/fit_matrix.dart';

// P0-FL-60b (UX 1) · a failed turn in the nutrition chat. At d449142 it was
// added without being announced, "Send it again" was under 44px where the
// platform does not pad targets (web, desktop), and at large text the row
// overflowed.
//
// HOW TO SEE IT FAIL: `git checkout d449142 -- lib/features/ai_nutrition/
// presentation/widgets/ai_chat_bubble.dart`; the controls pass.

const _notice =
    "Couldn't get an answer from the AI coach — try again in a moment. If it "
    'keeps happening, contact support.';

void main() {
  var retries = 0;
  setUp(() => retries = 0);

  Future<void> show(WidgetTester t,
      {double width = 390,
      double scale = 1,
      bool failed = true,
      bool retry = true}) async {
    fitWindow(t, width, 2000, scale);
    await t.pumpWidget(MaterialApp(
        theme: ThemeData(
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
        home: Scaffold(
            body: Align(
                alignment: Alignment.topLeft,
                // The chat list's own padding.
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: AiChatBubble(
                        message: ChatMessage(
                            content: _notice,
                            isUser: false,
                            failed: failed,
                            timestamp: DateTime(2026)),
                        onRetry: retry ? () => retries++ : null))))));
  }

  testWidgets('announced: the sentence alone, once, as a live region',
      (t) async {
    final h = t.ensureSemantics();
    await show(t);
    expect(find.bySemanticsLabel(_notice), findsOneWidget);
    final node = t.getSemantics(find.bySemanticsLabel(_notice));
    expect(node.flagsCollection.isLiveRegion, isTrue,
        reason: 'THE defect: it appeared in silence');
    h.dispose();
  });

  testWidgets('Send it again: 44×44, named, its own button, pressable by a '
      'screen reader', (t) async {
    final h = t.ensureSemantics();
    await show(t);
    final size = t.getSize(find.byType(TextButton));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44), reason: 'THE defect');
    expectNamedButton(t, sendItAgainLabel);
    final node = t.getSemantics(find.bySemanticsLabel(sendItAgainLabel));
    expect(node.flagsCollection.isLiveRegion, isFalse);
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await t.pump();
    expect(retries, 1);
    h.dispose();
  });

  for (final w in fitPhones.keys) {
    for (final s in fitScales) {
      testWidgets('fits ${w}dp at ${s}x, not shrunk', (t) async {
        await show(t, width: w.toDouble(), scale: s);
        expect(recordOverflows(), isEmpty);
        expectTextNotShrunk(t, find.byType(AiChatBubble), s);
        for (final m in [_notice, sendItAgainLabel]) {
          expect(renderedFontSize(t, find.text(m)), closeTo(13 * s, 0.01));
        }
        expect(t.getSize(find.byType(TextButton)).height,
            greaterThanOrEqualTo(44));
      });
    }
  }

  testWidgets('CONTROL: an older failure offers no retry', (t) async {
    await show(t, retry: false);
    expect(find.text(_notice), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('NEGATIVE CONTROL: an answer is not a live region and has no '
      'retry', (t) async {
    final h = t.ensureSemantics();
    await show(t, failed: false);
    expect(find.byType(TextButton), findsNothing);
    expect(t.getSemantics(find.text(_notice)).flagsCollection.isLiveRegion,
        isFalse);
    h.dispose();
  });
}
