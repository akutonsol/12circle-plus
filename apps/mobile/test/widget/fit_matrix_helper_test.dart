import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fit_matrix.dart';

// P0-FL-61 round 2 · the fit helpers themselves.
//
// At 924bbf0 `recordOverflows` kept 14 lines of each report, and the name of
// the overflowing Flex — which `overflowsIn` looks for — comes later whenever
// the report is longer, so `overflowsIn` answered "none" for a real overflow;
// it answered "none" for a surface that is not there, too. `tapNodes` counted
// a node merged into its parent as a target of its own.
//
// HOW TO SEE IT FAIL: run against 924bbf0's test/support/fit_matrix.dart.

const _in = Key('surface');

/// A Row that overflows, deep enough that its report names it late.
Widget _tooWide({int deep = 8}) {
  Widget w = const SizedBox(
    width: 100,
    child: Row(children: [SizedBox(width: 300, height: 10)]),
  );
  for (var i = 0; i < deep; i++) {
    w = Padding(padding: const EdgeInsets.all(1), child: w);
  }
  return w;
}

Future<void> _mount(WidgetTester t, {Widget? inside, Widget? outside}) =>
    t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (outside != null) outside,
          KeyedSubtree(
              key: _in,
              child: inside ?? const Column(children: [Text('fits')])),
        ]),
      ),
    ));

void main() {
  final surface = find.byKey(_in);

  group('overflowsIn', () {
    testWidgets('finds an overflow inside the surface, however long its report',
        (t) async {
      final seen = recordOverflows();
      await _mount(t, inside: _tooWide());
      expect(seen, hasLength(1), reason: 'premise: it was reported');
      expect(overflowsIn(t, seen, surface), hasLength(1),
          reason: 'THE defect: a real overflow was not found');
    });

    testWidgets('a surface that IS the overflowing Row', (t) async {
      final seen = recordOverflows();
      await t.pumpWidget(const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 100,
            child: Row(key: _in, children: [SizedBox(width: 300, height: 10)]),
          ),
        ),
      ));
      expect(overflowsIn(t, seen, surface), hasLength(1));
    });

    testWidgets('an overflow whose Row has since left the tree is kept',
        (t) async {
      final seen = recordOverflows();
      await _mount(t, inside: _tooWide());
      await _mount(t);
      expect(overflowsIn(t, seen, surface), hasLength(1),
          reason: 'nobody can say it was not inside the surface');
    });

    testWidgets('a surface that is not there fails, instead of "none"',
        (t) async {
      final seen = recordOverflows();
      await _mount(t, outside: _tooWide());
      expect(() => overflowsIn(t, seen, find.byType(AlertDialog)),
          throwsA(isA<TestFailure>()));
    });

    testWidgets('a surface with no Row or Column fails, instead of "none"',
        (t) async {
      final seen = recordOverflows();
      await _mount(t, inside: const Text('no flex'));
      expect(() => overflowsIn(t, seen, surface), throwsA(isA<TestFailure>()));
    });

    testWidgets('CONTROL: an overflow elsewhere on screen is not the surface\'s',
        (t) async {
      final seen = recordOverflows();
      await _mount(t, outside: _tooWide());
      expect(seen, hasLength(1), reason: 'premise');
      expect(overflowsIn(t, seen, surface), isEmpty);
    });

    testWidgets('CONTROL: nothing overflows: none', (t) async {
      final seen = recordOverflows();
      await _mount(t);
      expect(overflowsIn(t, seen, surface), isEmpty);
    });
  });

  group('tapNodes', () {
    testWidgets('a merged child is its parent, counted once, with its size',
        (t) async {
      final handle = t.ensureSemantics();
      await _mount(t,
          inside: MergeSemantics(
            child: Semantics(
              label: 'Portion',
              child: Slider(value: .5, onChanged: (_) {}),
            ),
          ));
      final nodes = tapNodes(t, surface);
      expect(nodes.map((n) => n.label), ['Portion']);
      expectTargets(t, surface);
      handle.dispose();
    });

    testWidgets('CONTROL: two separate buttons are two nodes', (t) async {
      final handle = t.ensureSemantics();
      await _mount(t,
          inside: Column(children: [
            TextButton(onPressed: () {}, child: const Text('One')),
            TextButton(onPressed: () {}, child: const Text('Two')),
          ]));
      expect(tapNodes(t, surface).map((n) => n.label), ['One', 'Two']);
      handle.dispose();
    });

    testWidgets('CONTROL: a small or unnamed target still fails', (t) async {
      final handle = t.ensureSemantics();
      await _mount(t,
          inside: Column(children: [
            Semantics(
              container: true,
              child: GestureDetector(
                  onTap: () {}, child: const SizedBox(width: 20, height: 20, child: Text('x'))),
            ),
          ]));
      expect(() => expectTargets(t, surface), throwsA(isA<TestFailure>()));
      handle.dispose();
    });

    testWidgets('CONTROL: a surface with no target fails', (t) async {
      final handle = t.ensureSemantics();
      await _mount(t);
      expect(() => expectTargets(t, surface), throwsA(isA<TestFailure>()));
      handle.dispose();
    });
  });
}
