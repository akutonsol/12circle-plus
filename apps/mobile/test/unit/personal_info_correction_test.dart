// QAX-COR-01 — the Personal Info correction contract.
//
// Before the fix a cleared phone / height / weight / goal weight, or a
// deselected gender chip, was simply left out of the update, so the stored
// value survived while the screen said "Profile updated successfully". Input
// the number formatter allows but double.tryParse rejects ("." or "70..5") was
// written as 0. The database accepts NULL for all five columns (verified on the
// migration replay, QA_AUTONOMOUS_EXHAUSTION_FINAL_REPORT.md QAX-COR-01), so
// the defect was entirely in this payload.
import 'package:circle_fitness/features/profile/presentation/personal_info_screen.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _build({
  String phone = '555-0100',
  String? gender = 'Female',
  bool isCoach = false,
  String height = '170',
  String weight = '65.5',
  String goalWeight = '60',
}) =>
    buildPersonalInfoPayload(
      firstName: ' Ada ', lastName: 'Q',
      gender: gender, dateOfBirth: DateTime(1990, 1, 2), phone: phone,
      isCoach: isCoach,
      height: height, weight: weight, goalWeight: goalWeight,
      fitnessGoal: 'strength', activityLevel: 'sedentary',
      trainingDays: 3, trainingLocation: 'gym', nutritionGoal: 'maintain',
    );

void main() {
  group('QAX-COR-01 a cleared field is cleared, not silently kept', () {
    test('cleared phone is sent as null', () {
      final p = _build(phone: '   ');
      expect(p.containsKey('phone'), isTrue);
      expect(p['phone'], isNull);
    });

    for (final (field, column) in [
      ('height', 'height_cm'),
      ('weight', 'weight_kg'),
      ('goalWeight', 'weight_goal_kg'),
    ]) {
      test('cleared $field is sent as null ($column)', () {
        final p = switch (field) {
          'height' => _build(height: ''),
          'weight' => _build(weight: ''),
          _ => _build(goalWeight: ''),
        };
        expect(p.containsKey(column), isTrue);
        expect(p[column], isNull);
      });
    }

    test('a deselected gender chip is sent as null', () {
      final p = _build(gender: null);
      expect(p.containsKey('gender'), isTrue);
      expect(p['gender'], isNull);
    });
  });

  group('QAX-COR-01 an unreadable number is refused, never written as 0', () {
    for (final bad in ['.', '70..5', '1.2.3']) {
      test('"$bad" as weight throws a FormatException naming the field', () {
        expect(() => _build(weight: bad),
            throwsA(isA<FormatException>()
                .having((e) => e.message, 'message', contains('weight'))));
      });
    }
  });

  group('QAX-COR-01 positive controls', () {
    test('ordinary values pass through unchanged', () {
      final p = _build();
      expect(p['first_name'], 'Ada');
      expect(p['phone'], '555-0100');
      expect(p['gender'], 'Female');
      expect(p['date_of_birth'], '1990-01-02');
      expect(p['height_cm'], 170.0);
      expect(p['weight_kg'], 65.5);
      expect(p['weight_goal_kg'], 60.0);
      expect(p['training_days_per_week'], 3);
    });

    test('a coach never sends client fitness fields, cleared or not', () {
      final p = _build(isCoach: true, height: '', weight: '');
      for (final c in ['height_cm', 'weight_kg', 'weight_goal_kg',
                       'fitness_goal', 'training_days_per_week']) {
        expect(p.containsKey(c), isFalse, reason: c);
      }
    });
  });
}
