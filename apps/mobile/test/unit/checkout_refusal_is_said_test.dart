import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:circle_fitness/features/payments/data/payment_service.dart';

// create-checkout now refuses a second live subscription for what the user
// already pays for, with 409 { code: 'already_subscribed', error: <reason> }.
// That is an answer, not a fault: it must reach the user as the reason, never as
// "Could not start checkout. Try again." -- retrying would never work.
void main() {
  test('a 409 already_subscribed is a refusal carrying the server\'s reason', () {
    final r = checkoutRefusal(const FunctionException(status: 409, details: {
      'code': 'already_subscribed',
      'error': 'You already have a coach plan. Change or cancel it from Billing first.',
    }));
    expect(r, isNotNull);
    expect(r!.message, contains('already have a coach plan'));
  });

  test('anything else is not a refusal (it stays a plain failure)', () {
    expect(checkoutRefusal(const FunctionException(status: 500, details: {'error': 'x'})), isNull);
    expect(checkoutRefusal(const FunctionException(status: 409, details: {'error': 'x'})), isNull);
    expect(checkoutRefusal(const FunctionException(status: 409, details: 'text')), isNull);
  });

  test('a refusal with no reason still says what happened', () {
    final r = checkoutRefusal(
        const FunctionException(status: 409, details: {'code': 'already_subscribed'}));
    expect(r!.message, 'You already have this plan.');
  });
}
