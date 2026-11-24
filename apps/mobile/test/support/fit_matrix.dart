import 'package:flutter/foundation.dart' show describeIdentity;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// Screen-fit helpers (P0-FL-58): overflow, text size, target size, labels.

/// The phones a fit matrix covers, each with a phone-like height.
const fitPhones = {320: 568.0, 360: 640.0, 390: 844.0, 430: 932.0};

/// Text scales a fit matrix covers. 3.0 is included because all the surfaces
/// tested with this list are primary member / coach flows.
const fitScales = [1.0, 1.3, 2.0, 3.0];

/// Sets the window and the text scale for one test.
///
/// [height] is usually far taller than a phone: everything in a scroll view
/// is then laid out AND painted (a RenderFlex reports its overflow when it
/// paints), and no tap target is skipped for touching the screen edge.
///
/// Overflows are recorded from here on ([recordOverflows]): only the fit tests
/// assert on them, so a target or behaviour test fails for its own reason and
/// a control passes on a base that overflows.
void fitWindow(WidgetTester tester, num width, double height, double scale) {
  recordOverflows();
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = Size(width.toDouble(), height);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Collects RenderFlex overflow reports — and ONLY those.
///
/// Everything else (a failed `expect` among them, whose message may quote an
/// overflow report) is forwarded to the test binding: swallowing it would
/// hang the test until its timeout.
///
/// Asking again in the same test returns the same list.
List<String> recordOverflows() {
  final current = _recording;
  if (current != null) return current;
  final seen = _recording = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (d) {
    final text = d.toString();
    if (d.exception is FlutterError &&
        d.library == 'rendering library' &&
        text.contains('A RenderFlex overflowed by')) {
      seen.add(text.split('\n').take(14).join('\n'));
    } else {
      previous?.call(d);
    }
  };
  addTearDown(() {
    FlutterError.onError = previous;
    _recording = null;
  });
  return seen;
}

List<String>? _recording;

/// The overflow reports in [seen] that name a Row/Column inside [surface].
/// (`bySubtype`: `byType(Flex)` never matches a Row or a Column.)
List<String> overflowsIn(WidgetTester tester, List<String> seen, Finder surface) {
  final ids = tester
      .renderObjectList(find.descendant(of: surface, matching: find.bySubtype<Flex>()))
      .map(describeIdentity)
      .toSet();
  return [
    for (final e in seen)
      if (ids.any((id) => e.contains('$id ') || e.contains('$id\n') || e.contains('$id:'))) e
  ];
}

/// No text inside [surface] is rendered smaller than its own font size times
/// [scale], and nothing scales a subtree down.
///
/// Not checked: icon glyphs (never text-scaled), the AppBar title (Flutter
/// itself caps it at 1.34×) and a CircleAvatar's initial (Flutter never
/// scales it).
void expectTextNotShrunk(WidgetTester tester, Finder surface, double scale) {
  expect(find.descendant(of: surface, matching: find.byType(FittedBox)), findsNothing,
      reason: 'text must wrap or grow, never be scaled down');
  var checked = 0;
  for (final e in find.descendant(of: surface, matching: find.byType(RichText)).evaluate()) {
    final p = e.renderObject! as RenderParagraph;
    final family = p.text.style?.fontFamily ?? '';
    if (family.contains('Icons')) continue;
    var exempt = false;
    e.visitAncestorElements((a) {
      if (a.widget is AppBar || a.widget is CircleAvatar) exempt = true;
      return !exempt;
    });
    if (exempt) continue;
    expect(p.textScaler.scale(10), closeTo(10 * scale, 0.01),
        reason: '"${p.text.toPlainText()}" was shrunk');
    checked++;
  }
  expect(checked, greaterThan(0), reason: 'premise: some text was measured');
}

/// The font size [text] is rendered at (its own size times the text scale).
double renderedFontSize(WidgetTester tester, Finder text) {
  final p = tester.renderObject<RenderParagraph>(
      find.descendant(of: text, matching: find.byType(RichText)).first);
  double? size;
  p.text.visitChildren((s) {
    size ??= s.style?.fontSize;
    return size == null;
  });
  return p.textScaler.scale(size ?? p.text.style!.fontSize!);
}

/// Every node a person can tap (or adjust) in the semantics tree under
/// [surface]: its label and its size.
List<({String label, Size size, bool isField})> tapNodes(
    WidgetTester tester, Finder surface) {
  final out = <({String label, Size size, bool isField})>[];
  void visit(SemanticsNode n, Matrix4 to) {
    final d = n.getSemanticsData();
    final t = n.transform == null ? to : to.multiplied(n.transform!);
    final act = d.hasAction(SemanticsAction.tap) ||
        d.hasAction(SemanticsAction.increase) ||
        d.hasAction(SemanticsAction.decrease) ||
        d.hasAction(SemanticsAction.longPress);
    if (act && !d.flagsCollection.isHidden) {
      out.add((
        label: [d.label, d.tooltip].where((s) => s.isNotEmpty).join('\n'),
        size: MatrixUtils.transformRect(t, n.rect).size,
        isField: d.flagsCollection.isTextField,
      ));
    }
    n.visitChildren((c) {
      visit(c, t);
      return true;
    });
  }

  final root = tester.getSemantics(surface);
  visit(root, Matrix4.identity());
  return out;
}

/// Every tap node under [surface] is at least 44×44 and has a label.
/// [fieldsMayBeUnnamed]: a filled text field's own name is not checked.
void expectTargets(WidgetTester tester, Finder surface,
    {int atLeast = 1, bool fieldsMayBeUnnamed = false}) {
  final nodes = tapNodes(tester, surface);
  expect(nodes.length, greaterThanOrEqualTo(atLeast), reason: 'premise: tap nodes found');
  final bad = [
    for (final n in nodes)
      if (n.size.width < 43.99 || n.size.height < 43.99 ||
          (n.label.trim().isEmpty && !(fieldsMayBeUnnamed && n.isField)))
        '"${n.label.replaceAll('\n', ' / ')}" ${n.size.width.toStringAsFixed(1)}×'
            '${n.size.height.toStringAsFixed(1)}'
  ];
  expect(bad, isEmpty, reason: 'targets under 44×44 or with no label:\n${bad.join('\n')}');
}

/// The single semantics button labelled exactly [label]: it has the tap
/// action (a screen reader can press it) and is at least 44×44.
void expectNamedButton(WidgetTester tester, String label) {
  final f = find.bySemanticsLabel(label);
  expect(f, findsOneWidget, reason: 'no node labelled "$label"');
  final n = tester.getSemantics(f);
  final d = n.getSemanticsData();
  expect(d.flagsCollection.isButton, isTrue, reason: '"$label": no button role');
  expect(d.hasAction(SemanticsAction.tap), isTrue,
      reason: '"$label": a screen reader cannot press it');
  expect(n.rect.width, greaterThanOrEqualTo(44), reason: '"$label" width');
  expect(n.rect.height, greaterThanOrEqualTo(44), reason: '"$label" height');
}
