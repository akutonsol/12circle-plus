import 'package:circle_fitness/features/dashboard/presentation/client_detail_screen.dart';
import 'package:flutter_test/flutter_test.dart';

// A typo in a client's custom price cleared it.
//
// The dialog read the field with `double.tryParse`, which answers null for
// "150/mo" or "1,500"; null CLEARED the client's custom price (falling back to
// the coach's standard rate), and the coach was told "Custom price cleared —
// using your standard rate." Unreadable input now changes nothing and says why;
// blank still clears, as the dialog states.

void main() {
  test('a typo is refused, not read as "clear"', () {
    for (final typo in ['150/mo', '1,500', 'abc', '-20']) {
      final r = parseCustomPrice(typo);
      expect(r.error, isNotNull, reason: 'THE defect: "$typo" cleared the custom price');
      expect(r.price, isNull);
    }
  });

  test('blank clears, as the dialog says', () {
    final r = parseCustomPrice('   ');
    expect(r.error, isNull);
    expect(r.price, isNull);
  });

  test('a number sets the price', () {
    final r = parseCustomPrice(' 149.5 ');
    expect(r.error, isNull);
    expect(r.price, 149.5);
  });
}
