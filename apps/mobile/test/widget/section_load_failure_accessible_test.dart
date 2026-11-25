import 'dart:ui' show Tristate;

import 'package:circle_fitness/features/workout/presentation/widgets/section_load_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fit_matrix.dart';

// P0-FL-61 (a) · the shared "Try again" (34 call sites).
//
// At a82f993 the retry's Semantics node said "button" but excluded the
// TextButton's own semantics without giving the tap back: a screen reader
// found "Try again: load …" and could not press it, and busy was not announced
// as disabled.
//
// HOW TO SEE IT FAIL: run against a82f993's section_load_failure.dart.

const _what = 'your coaching for this exercise';
const _label = 'Try again: load $_what';

void main() {
  var retries = 0;
  setUp(() => retries = 0);

  Future<void> mount(WidgetTester t, {bool busy = false}) =>
      t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: SectionLoadFailure(
              what: _what,
              error: StateError('SECRET'),
              detail: 'Editing is paused until it loads.',
              busy: busy,
              onRetry: () => retries++,
            ),
          ),
        ),
      ));

  /// Every node in the tree carrying a label that mentions the retry.
  List<SemanticsNode> retryNodes(WidgetTester t) {
    final out = <SemanticsNode>[];
    bool visit(SemanticsNode n) {
      if (n.label.contains('Try again: ') ||
          n.label.contains('Retrying') ||
          n.label == 'Try again') {
        out.add(n);
      }
      n.visitChildren(visit);
      return true;
    }

    visit(t.getSemantics(find.byType(Scaffold)));
    return out;
  }

  testWidgets('a screen reader can press Try again, and pressing it retries '
      'once', (t) async {
    final handle = t.ensureSemantics();
    await mount(t);
    final node = t.getSemantics(find.bySemanticsLabel(_label));
    final d = node.getSemanticsData();
    expect(d.label, startsWith('Try again'),
        reason: 'the visible words come first (voice control)');
    expect(d.flagsCollection.isButton, isTrue);
    expect(d.hasAction(SemanticsAction.tap), isTrue,
        reason: 'THE defect: a button with no tap action');
    expect(d.flagsCollection.isEnabled, Tristate.isTrue);
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await t.pump();
    expect(retries, 1);
    handle.dispose();
  });

  testWidgets('busy: one node, announced disabled, with no tap action',
      (t) async {
    final handle = t.ensureSemantics();
    await mount(t, busy: true);
    final d =
        t.getSemantics(find.bySemanticsLabel('Retrying')).getSemanticsData();
    expect(d.flagsCollection.isButton, isTrue);
    expect(d.flagsCollection.isEnabled, Tristate.isFalse,
        reason: 'disabled is said, not only unpressable');
    expect(d.hasAction(SemanticsAction.tap), isFalse);
    await t.tap(find.byType(TextButton), warnIfMissed: false);
    expect(retries, 0, reason: 'no double fire');
    expect(retryNodes(t), hasLength(1));
    handle.dispose();
  });

  testWidgets('NEGATIVE CONTROL: exactly one node names the retry, and the '
      'live region is the message only', (t) async {
    final handle = t.ensureSemantics();
    await mount(t);
    final nodes = retryNodes(t);
    expect(nodes.map((n) => n.label), [_label]);
    expect(
        nodes.single.getSemanticsData().flagsCollection.isLiveRegion, isFalse);
    final live = t.getSemantics(find.text("Couldn't load $_what"));
    expect(live.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
    expect(
        live.label,
        "Couldn't load $_what. ${SectionLoadFailure.otherwiseHint} "
        'Editing is paused until it loads.');
    expect(live.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    expect(find.textContaining('SECRET'), findsNothing);
    handle.dispose();
  });

  testWidgets('POSITIVE CONTROL: a touch still retries', (t) async {
    await mount(t);
    await t.tap(find.text('Try again'));
    expect(retries, 1);
  });

  for (final MapEntry(key: width, value: height) in fitPhones.entries) {
    for (final scale in fitScales) {
      for (final busy in [false, true]) {
        testWidgets(
            '${width}dp, text $scale×${busy ? ', busy' : ''}: full-size '
            'text, nothing overflows, the retry >= 44', (t) async {
          final handle = t.ensureSemantics();
          final seen = recordOverflows();
          // (A consumer's own list scrolls; here the card gets the room.)
          fitWindow(t, width, height + 2000, scale);
          await mount(t, busy: busy);
          expect(seen, isEmpty);
          final card = find.byType(SectionLoadFailure);
          expectTextNotShrunk(t, card, scale);
          expect(renderedFontSize(t, find.text("Couldn't load $_what")),
              closeTo(13 * scale, 0.01));
          if (!busy) {
            expect(renderedFontSize(t, find.text('Try again')),
                closeTo(12 * scale, 0.01));
          }
          final node =
              t.getSemantics(find.bySemanticsLabel(busy ? 'Retrying' : _label));
          expect(node.rect.width, greaterThanOrEqualTo(44));
          expect(node.rect.height, greaterThanOrEqualTo(44));
          expect(t.getRect(find.byType(TextButton)).right,
              lessThanOrEqualTo(width.toDouble()));
          handle.dispose();
        });
      }
    }
  }
}
