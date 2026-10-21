// F-26 · the app's front door, measured on the device.
//
// The claim is physical and it is the whole finding: does the account CTA
// reach the platform's accessibility API as something that can be activated
// WITHOUT a drag? `excludeSemantics: true` drops the child's actions along with
// its labels, so a node can carry the right name and still be unpressable —
// that shipped once and was caught only by reading the real tree (F-9).
//
// `OnboardingScreen` is a leaf: no session, no backend.
//
//   flutter test integration_test/f26_onboarding_entry_device_test.dart \
//     -d emulator-5554 --dart-define-from-file=dart_defines/qa.json

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:circle_fitness/features/onboarding/presentation/onboarding_screen.dart';

void _mark(String line) => print('F26-MARK $line');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('F-26 the front door is reachable without a drag, on device',
      (t) async {
    final handle = t.ensureSemantics();
    await t.pumpWidget(const MaterialApp(home: OnboardingScreen()));
    await t.pump();

    _mark('DEVICE dpr=${t.view.devicePixelRatio} '
        'width=${t.binding.renderViews.first.size.width.toStringAsFixed(1)}dp');

    for (final label in ['Create your account', 'I already have one']) {
      final finder = find.bySemanticsLabel(label);
      expect(finder, findsOneWidget, reason: label);
      final d = t.getSemantics(finder).getSemanticsData();
      _mark('CONTROL "$label" button=${d.hasFlag(SemanticsFlag.isButton)} '
          'tap=${d.hasAction(SemanticsAction.tap)}');
      expect(d.hasFlag(SemanticsFlag.isButton), isTrue, reason: label);
      expect(d.hasAction(SemanticsAction.tap), isTrue,
          reason: '$label must be activatable by switch access and by a '
              'screen reader, not only by a precise horizontal drag');
    }

    final signIn = t.getSize(find
        .ancestor(
            of: find.text('I already have one'), matching: find.byType(GestureDetector))
        .first);
    _mark('SIGNIN target=${signIn.width.toStringAsFixed(1)}x'
        '${signIn.height.toStringAsFixed(1)}dp');
    expect(signIn.height, greaterThanOrEqualTo(44.0));

    _mark('PASS the front door has a non-drag path');
    handle.dispose();
  });
}
