import 'package:circle_fitness/features/onboarding/domain/intake_data.dart';
import 'package:flutter_test/flutter_test.dart';

// user_profiles.consent_date (timestamptz) is the record of WHEN the member
// agreed to the health consent. Intake wrote it as DateTime.now().toIso8601String()
// -- local wall time with no zone, which Postgres reads as UTC -- so the consent
// record was off by the device's UTC offset (in the future for anyone east of
// UTC). goals.completed_at and action_items.completed_at had the same write.
//
// The wire value must carry a zone, which CI can check in any time zone.
//
// HOW TO SEE IT FAIL: on main both serialisers send a zoneless timestamp.

bool _zoned(String v) => v.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(v);

void main() {
  test('the full intake save stamps consent with a real instant', () {
    final at = IntakeData(consentAgreed: true).toSupabase()['consent_date'] as String;
    expect(_zoned(at), isTrue, reason: '`$at` has no zone; Postgres stores it as UTC');
    expect(DateTime.parse(at).difference(DateTime.now()).abs(),
        lessThan(const Duration(minutes: 1)),
        reason: 'and it is the moment of agreement');
  });

  test('the step-by-step intake save stamps consent with a real instant', () {
    final at = IntakeData(consentAgreed: true).toSupabasePartial(1)['consent_date'] as String;
    expect(_zoned(at), isTrue, reason: '`$at` has no zone');
  });

  test('no consent, no consent date', () {
    expect(IntakeData().toSupabase()['consent_date'], isNull);
    expect(IntakeData().toSupabasePartial(1).containsKey('consent_date'), isFalse);
  });
}
