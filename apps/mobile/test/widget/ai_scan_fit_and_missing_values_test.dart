import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Tristate;

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/nutrition/presentation/widgets/ai_scan_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/fake_image_picker.dart';
import '../support/fit_matrix.dart';
import '../support/pump_until.dart';
import '../support/row_checking_postgrest.dart';

// P0-FL-61 (c)(d) · Log Meal › Scan.
//
// (c) At a82f993 the idle view's fixed-height frame and buttons overflowed at
// large text, as did the analysing and result stages; the analyse button had
// no name and the description field lost its only name once typed in.
// (d) A calorie/macro value the analysis did not give was read as 0, shown as
// "0 kcal" / "0g" and saved as 0.
//
// HOW TO SEE IT FAIL: run against a82f993's ai_scan_view.dart.

const _uid = '00000000-0000-4000-8000-00000000d61c';

const _whole = <String, Object?>{
  'name': 'Chicken, rice and mixed greens',
  'calories': 640,
  'protein_g': 45,
  'carbs_g': 60,
  'fat_g': 18,
  'confidence': 88,
  'items': [
    {'name': 'Grilled chicken breast', 'calories': 280},
    {'name': 'Steamed rice', 'calories': 360},
  ],
};

Map<String, Object?> _without(Iterable<String> keys, {bool nulled = false}) {
  final out = Map<String, Object?>.of(_whole);
  for (final k in keys) {
    nulled ? out[k] = null : out.remove(k);
  }
  return out;
}

class _Server extends RowCheckingPostgrest {
  _Server() : super(_uid);
  Map<String, Object?> result = _whole;
  Completer<void>? hold;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!request.url.path.endsWith('/analyze-food-image')) {
      return super.send(request);
    }
    await hold?.future;
    return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({'result': result}))), 200,
        request: request, headers: {'content-type': 'application/json'});
  }
}

void main() {
  late _Server server;
  final picker = FakeImagePicker();
  final reported = <AppFailure>[];
  final accepted = <ScanResult>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = _Server();
    await initSignedInSupabase(server);
    picker.install();
  });
  tearDownAll(picker.dispose);
  setUp(() {
    server
      ..reset()
      ..result = _whole
      ..hold = null;
    picker.reset();
    reported.clear();
    accepted.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  final view = find.byType(AiScanView);

  Future<void> mount(WidgetTester t, {String mealType = 'Lunch'}) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AiScanView(
          onAccept: accepted.add,
          mealType: mealType,
          onSearchInstead: () {},
        ),
      ),
    ));
    await t.pump();
  }

  Future<void> start(WidgetTester t) async {
    await t.enterText(find.byType(TextField), 'chicken salad');
    await t.testTextInput.receiveAction(TextInputAction.send);
    await t.pump();
  }

  /// Through the real service to the result stage.
  Future<void> analyse(WidgetTester t) async {
    await start(t);
    await pumpUntil(t, () => find.text('Retake').evaluate().isNotEmpty,
        what: 'the result stage');
    // Until its entrance has finished drawing (round 3: no fixed wait).
    await t.pumpAndSettle();
  }

  void tall(WidgetTester t) => fitWindow(t, 400, 2400, 1);

  /// Every tap/adjust node of the result stage is >= 44 and named, and the
  /// ones it must have are there.
  void expectResultTargets(WidgetTester t) {
    final found = <String>[];
    void visit(SemanticsNode n) {
      final d = n.getSemanticsData();
      final adjusts = d.hasAction(SemanticsAction.increase);
      if (!n.isMergedIntoParent && (adjusts || d.hasAction(SemanticsAction.tap))) {
        found.add(d.label);
        expect(d.label.trim(), isNotEmpty, reason: 'a target with no name');
        expect(n.rect.width, greaterThanOrEqualTo(44), reason: d.label);
        expect(n.rect.height, greaterThanOrEqualTo(44), reason: d.label);
      }
      n.visitChildren((c) {
        visit(c);
        return true;
      });
    }

    visit(t.getSemantics(view));
    expect(found, containsAll(['Smaller', 'As shown', 'Larger', 'Portion',
      'Retake', 'Search instead']));
  }

  /// [text] lies inside the box of the button named [label].
  void expectInsideItsButton(WidgetTester t, String label) {
    final box = t.getRect(find
        .ancestor(of: find.text(label), matching: find.byType(GestureDetector))
        .first);
    final text = t.getRect(find.text(label));
    expect(box.top <= text.top && text.bottom <= box.bottom, isTrue,
        reason: '"$label" $text is cut off by its own button $box');
  }

  // ── (c) ────────────────────────────────────────────────────────────────
  for (final width in fitPhones.keys) {
    for (final scale in fitScales) {
      final at = '${width}dp, text $scale×';

      testWidgets('idle, $at: nothing overflows, full-size text', (t) async {
        final seen = recordOverflows();
        fitWindow(t, width, 5000, scale);
        await mount(t);
        expect(seen, isEmpty);
        expectTextNotShrunk(t, view, scale);
        for (final (text, size) in [
          ('Take or upload a photo of your meal', 13.0),
          ('Scan Meal', 15.0),
          ('Choose from Gallery', 14.0),
          ('or describe it', 12.0),
        ]) {
          expect(renderedFontSize(t, find.text(text)),
              closeTo(size * scale, 0.01), reason: text);
          expect(
              t.getRect(find.text(text)).right, lessThanOrEqualTo(width - 20));
        }
        expectInsideItsButton(t, 'Scan Meal');
        expectInsideItsButton(t, 'Choose from Gallery');
      });

      testWidgets('idle, $at: every target >= 44 and named', (t) async {
        final handle = t.ensureSemantics();
        fitWindow(t, width, 5000, scale);
        await mount(t);
        expectTargets(t, view, atLeast: 4);
        handle.dispose();
      });

      testWidgets('a failure notice, $at: nothing overflows', (t) async {
        final seen = recordOverflows();
        fitWindow(t, width, 5000, scale);
        await mount(t);
        picker.fails('photo_access_denied');
        await t.tap(find.text('Choose from Gallery'));
        await pumpUntil(
            t,
            () => find
                .textContaining("Couldn't open your photos")
                .evaluate()
                .isNotEmpty,
            what: 'the notice');
        expect(
            find.textContaining("Couldn't open your photos"), findsOneWidget);
        expect(seen, isEmpty);
        expectTextNotShrunk(t, view, scale);
      });

      testWidgets('analysing, $at: nothing overflows in a short sheet',
          (t) async {
        final seen = recordOverflows();
        fitWindow(t, width, 5000, scale);
        server.hold = Completer<void>();
        await mount(t);
        await start(t);
        await pumpUntil(
            t, () => find.text('Analyzing your meal...').evaluate().isNotEmpty,
            what: 'the analysing stage');
        seen.clear(); // the idle stage has its own test
        // Re-lay the stage in the room a Log Meal sheet leaves it.
        t.view.physicalSize = Size(width.toDouble(), 340);
        await t.pump(); // one frame lays it out again
        expect(find.text('Analyzing your meal...'), findsOneWidget);
        expect(seen, isEmpty);
        expectTextNotShrunk(t, view, scale);
        server.hold!.complete();
        t.view.physicalSize = Size(width.toDouble(), 6000);
        await pumpUntil(t, () => find.text('Retake').evaluate().isNotEmpty,
            what: 'the result');
      });

      for (final (what, result) in [
        ('whole', _whole),
        ('incomplete', _without(['calories', 'protein_g', 'carbs_g', 'fat_g'])),
      ]) {
        testWidgets('$what result, $at: nothing overflows, full-size text',
            (t) async {
          final seen = recordOverflows();
          fitWindow(t, width, 6000, scale);
          server.result = result;
          await mount(t, mealType: 'protein_shake');
          seen.clear(); // the idle stage has its own test
          await analyse(t);
          // (The analysing stage it passes through is in [seen] too.)
          expect(seen, isEmpty);
          expectTextNotShrunk(t, view, scale);
          expect(renderedFontSize(t, find.text('Retake')),
              closeTo(14 * scale, 0.01));
          expect(find.text('Chicken, rice and mixed greens'), findsOneWidget);
          expectInsideItsButton(t, 'Retake');
          expectInsideItsButton(t, 'Save to protein shake');
        });

        testWidgets('$what result, $at: every target >= 44 and named',
            (t) async {
          final handle = t.ensureSemantics();
          fitWindow(t, width, 6000, scale);
          server.result = result;
          await mount(t, mealType: 'protein_shake');
          await analyse(t);
          expectResultTargets(t);
          handle.dispose();
        });
      }
    }
  }

  testWidgets('idle at 2× on a small phone: everything can be scrolled to',
      (t) async {
    final seen = recordOverflows();
    fitWindow(t, 320, 568, 2);
    await mount(t);
    await t.scrollUntilVisible(find.byType(TextField), 100,
        scrollable: find.byType(Scrollable).first);
    await t.drag(find.byType(SingleChildScrollView), const Offset(0, -2000));
    await t.pump();
    expect(t.getRect(find.byType(TextField)).bottom, lessThanOrEqualTo(568));
    expect(seen, isEmpty);
  });

  testWidgets('the description field and its button have names', (t) async {
    final handle = t.ensureSemantics();
    tall(t);
    await mount(t);
    await expectFieldNamed(t, find.byType(TextField), 'Describe your meal');
    expect(find.byTooltip('Analyze description'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('POSITIVE CONTROL: at 1× the frame and the buttons keep their '
      'size', (t) async {
    tall(t);
    await mount(t);
    double boxHeight(Finder f) => t
        .getSize(
            find.ancestor(of: f, matching: find.byType(DecoratedBox)).first)
        .height;
    expect(boxHeight(find.text('Scan Meal')), 54);
    expect(boxHeight(find.text('Choose from Gallery')), 50);
    expect(
        boxHeight(find.text('Take or upload a photo of your meal')), 230);
  });

  testWidgets('Retake and Save are named buttons a screen reader can press',
      (t) async {
    final handle = t.ensureSemantics();
    tall(t);
    await mount(t);
    await analyse(t);
    void press(String label) {
      expectNamedButton(t, label);
      final n = t.getSemantics(find.bySemanticsLabel(label));
      n.owner!.performAction(n.id, SemanticsAction.tap);
    }

    press('Save to lunch');
    expect(accepted, hasLength(1));
    press('Retake');
    await t.pump();
    expect(find.text('Scan Meal'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the portion slider says what it moves', (t) async {
    final handle = t.ensureSemantics();
    tall(t);
    await mount(t);
    await analyse(t);
    final d = t.getSemantics(find.byType(Slider)).getSemanticsData();
    expect(d.label, 'Portion');
    expect(d.value, '1.00×');
    expect(d.hasAction(SemanticsAction.increase), isTrue);
    handle.dispose();
  });

  // ── (d) ────────────────────────────────────────────────────────────────
  for (final nulled in [false, true]) {
    for (final (keys, names) in [
      (['calories'], 'calories'),
      (['protein_g'], 'protein'),
      (['carbs_g'], 'carbs'),
      (['fat_g'], 'fat'),
      (['calories', 'fat_g'], 'calories and fat'),
      (
        ['calories', 'protein_g', 'carbs_g', 'fat_g'],
        'calories, protein, carbs and fat'
      ),
    ]) {
      testWidgets('$names ${nulled ? 'null' : 'absent'}: not known, said, and '
          'nothing is saved', (t) async {
        final handle = t.ensureSemantics();
        tall(t);
        server.result = _without(keys, nulled: nulled);
        await mount(t);
        await analyse(t);

        expect(find.text('0 kcal'), findsNothing, reason: 'THE defect');
        expect(find.text('0g'), findsNothing, reason: 'THE defect');
        expect(find.text('Calories not known'),
            keys.contains('calories') ? findsOneWidget : findsNothing);
        final macros = keys.where((k) => k != 'calories').length;
        expect(find.text('Not known'), findsNWidgets(macros));
        // What the analysis DID give is kept.
        expect(find.text('45g'),
            keys.contains('protein_g') ? findsNothing : findsOneWidget);

        // (Round 2: it names the control that is there, by its own words.)
        final msg = "Couldn't read the $names for this meal — retake it, or "
            'tap Search instead to add it yourself. Saving is off for this '
            'scan.';
        expect(find.text(msg), findsOneWidget);
        expect(liveRegionOver(msg), findsWidgets);
        expect(reported.map((f) => f.origin), ['nutrition.scan.incomplete']);

        final d = t
            .getSemantics(find.bySemanticsLabel('Save to lunch'))
            .getSemanticsData();
        expect(d.flagsCollection.isEnabled, Tristate.isFalse);
        expect(d.hasAction(SemanticsAction.tap), isFalse);
        await t.tap(find.text('Save to lunch'), warnIfMissed: false);
        await t.tap(find.text('Larger'));
        await t.pump();
        await t.tap(find.text('Save to lunch'), warnIfMissed: false);
        await t.pump();
        expect(accepted, isEmpty, reason: 'an invented 0 was saved');
        expect(server.writes, isEmpty);
        expect(reported, hasLength(1), reason: 'recorded once, not per frame');

        // The way out works: retake, and a whole answer saves.
        await t.tap(find.text('Retake'));
        await t.pump();
        server.result = _whole;
        await analyse(t);
        expect(find.textContaining("Couldn't"), findsNothing);
        await t.tap(find.text('Save to lunch'));
        expect(accepted.single.calories, 640);
        handle.dispose();
      });
    }
  }

  testWidgets('POSITIVE CONTROL: a whole answer is shown and saved, scaled',
      (t) async {
    tall(t);
    await mount(t);
    await analyse(t);
    expect(find.text('640 kcal'), findsOneWidget);
    expect(find.text('88% match'), findsOneWidget);
    expect(find.textContaining('ot known'), findsNothing);
    await t.tap(find.text('Larger'));
    await t.pump();
    await t.tap(find.text('Save to lunch'));
    final r = accepted.single;
    expect([r.calories, r.protein, r.carbs, r.fat], [800, 56.25, 75, 22.5]);
    expect(reported, isEmpty);
  });

  testWidgets('NEGATIVE CONTROL: a real 0 stays 0 and can be saved', (t) async {
    tall(t);
    server.result = {
      ..._whole,
      'name': 'Water',
      'calories': 0,
      'protein_g': 0,
      'carbs_g': 0,
      'fat_g': 0,
      'items': const <Object>[],
    };
    await mount(t);
    await analyse(t);
    expect(find.text('0 kcal'), findsOneWidget);
    expect(find.text('0g'), findsNWidgets(3));
    expect(find.textContaining('ot known'), findsNothing);
    await t.tap(find.text('Save to lunch'));
    final r = accepted.single;
    expect([r.calories, r.protein, r.carbs, r.fat], [0, 0, 0, 0]);
    expect(reported, isEmpty);
  });

  testWidgets("a component's missing calories are not 0 kcal; the meal's own "
      'total still saves', (t) async {
    tall(t);
    server.result = {
      ..._whole,
      'items': [
        {'name': 'Chicken', 'calories': 280},
        {'name': 'Dressing'},
        {'name': 'Ice', 'calories': 0},
      ],
    };
    await mount(t);
    await analyse(t);
    expect(find.text('280 kcal'), findsOneWidget);
    expect(find.text('0 kcal'), findsOneWidget, reason: 'the real 0 only');
    expect(find.text('kcal not known'), findsOneWidget);
    await t.tap(find.text('Save to lunch'));
    expect(accepted.single.calories, 640);
  });

  testWidgets('a missing confidence is not "0% match"; a real 0 is', (t) async {
    tall(t);
    server.result = _without(['confidence']);
    await mount(t);
    await analyse(t);
    expect(find.text('0% match'), findsNothing);
    expect(find.text('Match not known'), findsOneWidget);
    await t.tap(find.text('Save to lunch'));
    expect(accepted, hasLength(1), reason: 'it is not part of the meal');

    await t.tap(find.text('Retake'));
    await t.pump();
    server.result = {..._whole, 'confidence': 0};
    await analyse(t);
    expect(find.text('0% match'), findsOneWidget);
  });
}
