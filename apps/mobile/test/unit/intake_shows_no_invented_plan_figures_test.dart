import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Intake's "Your Plan Is Ready" page showed figures nobody had measured.
//
//   * "2,450 KCAL/DAY" for every new member, whatever they entered — the real
//     targets are set afterwards by the plan.
//   * "4 Days/Wk" when no training days had been chosen.
//   * '"This helps Coach Sarah know…"' — a placeholder coach, quoted to every
//     member, self-guided ones included.
//
// SOURCE GUARD. The page is a private widget deep inside the intake flow; this
// proves only that these literals are gone from it, not how the page renders.

void main() {
  final src = File('lib/features/onboarding/presentation/intake_flow_screen.dart')
      .readAsStringSync();

  test('no fixed calorie figure on the plan page', () {
    expect(src.contains("Text('2,450'"), isFalse);
  });

  test('unchosen training days are not shown as four', () {
    expect(src.contains(": '4 Days/Wk'"), isFalse);
  });

  test('no placeholder coach is named to members', () {
    expect(src.contains('Coach Sarah'), isFalse);
  });
}
