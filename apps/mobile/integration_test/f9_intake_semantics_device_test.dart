// F-9 · the intake flow's whole-screen accessibility node — re-measured.
//
// WHAT WAS MEASURED BEFORE
// ------------------------
// `docs/QA_EVIDENCE.md` §0d records a `uiautomator` dump of `/intake` on
// `emulator-5554` showing the page collapsed to **one merged node**, and a
// second dump showing the same whole-screen clickable node still present on
// page 2:
//
//   411.4 × 914.3 dp, clickable=true,
//   'Your Profile\nTell us a little about yourself.'
//
// A screen reader was offering the entire page as a single button named after
// the header. The page-1 fix did not address it, and that was recorded rather
// than papered over.
//
// WHY THIS FILE EXISTS RATHER THAN ANOTHER uiautomator DUMP
// ----------------------------------------------------------
// Two reasons. `uiautomator` returns an empty tree unless an accessibility
// service is enabled on the emulator, which it is not. And reaching page 2 as a
// signed-in user needs a fixture with no intake data — `p1-victim` carries a
// name, so the flow resumes past the welcome page — and manufacturing one means
// writing intake rows to QA. F-21 is open and the standing instruction is not
// to exercise it through unnecessary mutation.
//
// So the page is mounted directly, on the device, and the REAL semantics tree
// is read through the embedder: real text metrics, real density, the same tree
// Flutter hands to the platform. `ProfileInfoPage` takes plain values and
// callbacks, so it needs no session and touches no backend.
//
//   flutter test integration_test/f9_intake_semantics_device_test.dart \
//     -d emulator-5554 --dart-define-from-file=dart_defines/qa.json

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:circle_fitness/features/onboarding/presentation/intake_flow_screen.dart';

void _mark(String line) => print('F9-MARK $line');

/// Every node in the tree, flattened.
List<SemanticsNode> _all(SemanticsNode root) {
  final out = <SemanticsNode>[root];
  root.visitChildren((c) {
    out.addAll(_all(c));
    return true;
  });
  return out;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('F-9 page 2 is no longer one whole-screen clickable node',
      (t) async {
    final handle = t.ensureSemantics();

    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProfileInfoPage(
          firstName: '',
          lastName: '',
          // Pre-set so the ONLY thing standing between the page and a valid
          // form is the two names — which a test can type. The date field opens
          // a platform picker, which is not what this probe is measuring.
          gender: 'male',
          dateOfBirth: DateTime(1990, 1, 1),
          onChanged: (_, __, ___, ____) {},
          onContinue: () {},
          onBack: () {},
        ),
      ),
    ));
    await t.pump();

    final view = t.binding.renderViews.first;
    final screen = view.size;
    _mark('DEVICE dpr=${t.view.devicePixelRatio} '
        'screen=${screen.width.toStringAsFixed(1)}x${screen.height.toStringAsFixed(1)}dp');

    final root = view.debugSemantics!;
    final nodes = _all(root);
    _mark('TREE nodes=${nodes.length}');

    for (final n in nodes) {
      _mark('NODE rect=${n.rect.width.toStringAsFixed(0)}x${n.rect.height.toStringAsFixed(0)} '
          'tap=${n.getSemanticsData().hasAction(SemanticsAction.tap)} '
          'label="${n.label.replaceAll('\n', ' / ')}"');
    }

    // ── The defect, stated as an assertion ───────────────────────────────────
    // A node that is BOTH tappable and covers most of the screen is the thing
    // that was measured. One that merely covers the screen is fine — the root
    // does, and it has no action.
    final screenArea = screen.width * screen.height;
    final offenders = nodes.where((n) {
      final tappable = n.getSemanticsData().hasAction(SemanticsAction.tap);
      final area = n.rect.width * n.rect.height;
      return tappable && area > screenArea * 0.5;
    }).toList();

    for (final n in offenders) {
      _mark('OFFENDER rect=${n.rect.width.toStringAsFixed(1)}x'
          '${n.rect.height.toStringAsFixed(1)}dp label="${n.label.replaceAll('\n', ' / ')}"');
    }
    _mark('OFFENDERS count=${offenders.length}');

    expect(offenders, isEmpty,
        reason: 'A tappable node covering more than half the screen is the '
            'F-9 merge: a screen reader offers the whole page as one control.');

    // ── And the parts that were being swallowed now stand on their own ───────
    final back = nodes.where((n) => n.label == 'Back').toList();
    expect(back, hasLength(1),
        reason: 'the back control must be its own named node');
    expect(back.first.getSemanticsData().hasAction(SemanticsAction.tap), isTrue,
        reason: 'a node announced as a button that carries no tap action is a '
            'button a screen reader cannot press. `excludeSemantics: true` '
            'drops the child\'s actions along with its labels, and the first '
            'version of this fix shipped exactly that — measured here as '
            '`44x44 tap=false label="Back"`.');
    final b = back.first;
    _mark('BACK rect=${b.rect.width.toStringAsFixed(1)}x'
        '${b.rect.height.toStringAsFixed(1)}dp label="${b.label}"');
    expect(b.rect.width, greaterThanOrEqualTo(44.0));
    expect(b.rect.height, greaterThanOrEqualTo(44.0));

    for (final text in ['Your Profile', 'Tell us a little about yourself.']) {
      final found = nodes.where((n) => n.label == text).toList();
      expect(found, hasLength(1),
          reason: '"$text" must be its own node, not part of a control');
      final n = found.first;
      expect(n.getSemanticsData().hasAction(SemanticsAction.tap), isFalse,
          reason: '"$text" is a heading, not a button');
      _mark('TEXT "$text" rect=${n.rect.width.toStringAsFixed(1)}x'
          '${n.rect.height.toStringAsFixed(1)}dp');
    }

    // ── The primary action announces its state ──────────────────────────────
    // Not a claim about a fix — this page's Continue is an `ElevatedButton`,
    // which carries its own semantics. It is here because the page's central
    // rule ("you cannot continue until the form is valid") is only useful if it
    // reaches the accessibility tree, and because the F-9 merge would have
    // hidden this too: a swallowed button reports nothing about its state.
    SemanticsNode continueNode() =>
        _all(view.debugSemantics!).firstWhere((n) => n.label == 'Continue');

    final before = continueNode().getSemanticsData();
    _mark('CONTINUE(empty) button=${before.hasFlag(SemanticsFlag.isButton)} '
        'enabled=${before.hasFlag(SemanticsFlag.isEnabled)} '
        'tap=${before.hasAction(SemanticsAction.tap)}');
    expect(before.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(before.hasFlag(SemanticsFlag.isEnabled), isFalse,
        reason: 'the form is empty — say the button is disabled rather than '
            'leaving the user to guess why it does nothing');

    await t.enterText(find.byType(TextField).first, 'Ada');
    await t.pump();
    await t.enterText(find.byType(TextField).at(1), 'Lovelace');
    await t.pump();

    final after = continueNode().getSemanticsData();
    _mark('CONTINUE(filled) button=${after.hasFlag(SemanticsFlag.isButton)} '
        'enabled=${after.hasFlag(SemanticsFlag.isEnabled)} '
        'tap=${after.hasAction(SemanticsAction.tap)}');
    expect(after.hasFlag(SemanticsFlag.isEnabled), isTrue);
    expect(after.hasAction(SemanticsAction.tap), isTrue,
        reason: 'once enabled it must be pressable from the accessibility tree, '
            'not only by a sighted tap');

    _mark('PASS page 2 exposes discrete nodes; no whole-screen control');
    handle.dispose();
  });
}
