// INT-300 … INT-305 — Onboarding intake contract (Workstream N).
//
// Before this file the onboarding domain had ZERO test coverage, despite being
// the parent of four findings:
//
//   CON-02  onboarding marks itself complete after the profile save fails
//   CON-03  `dietary_restrictions` has two conflicting serializers
//   CON-04  PAR-Q risk is computed here and consumed by nothing
//   CON-06  naive local timestamps written into a `timestamptz` column
//
// `IntakeData` has no imports at all — it is pure Dart — so the serializers and
// the risk engine are directly testable today, with no seam and no refactor.
// That is the whole reason this gap is worth closing first.
//
// These are CHARACTERIZATION tests in the same shape as
// `cycle_phase_logic_test.dart`: several expectations below assert behaviour the
// QA reports classify as DEFECTIVE. They are marked `DEFECT:` and are expected
// to flip when the corresponding remediation lands. That is the point — today
// the defects are invisible to `flutter test`; after this file, changing them
// is a deliberate act with a failing test attached.
//
// Nothing here asserts a fix that has not been made.
import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/onboarding/domain/intake_data.dart';

/// A fully-populated intake — the shape the final save actually sends.
IntakeData _complete() => IntakeData(
      firstName: 'Ada',
      lastName: 'Lovelace',
      gender: 'female',
      dateOfBirth: DateTime(1990, 4, 12),
      primaryGoal: 'fat_loss',
      activities: const ['running', 'lifting'],
      activityLevel: 'moderate',
      trainingDays: 4,
      trainingLocation: 'gym',
      nutritionGoal: 'deficit',
      proteinConfidence: 'medium',
      biggestChallenges: const ['time', 'motivation'],
      heightCm: 168,
      weightKg: 64.5,
      weightGoalKg: 60.0,
      coachingMode: 'coached',
      parqAnswers: const {1: false, 2: false, 5: true},
      medicalConditions: const ['Asthma'],
      hasInjuries: true,
      injuryLocations: const ['left knee'],
      injuryDescription: 'ACL reconstruction 2024',
      experienceLevel: 'intermediate',
      workedWithCoachBefore: true,
      sleepHours: '6-7',
      stressLevel: 3,
      occupation: 'engineer',
      dietaryRestrictions: const ['vegetarian', 'gluten-free'],
      foodAllergies: 'peanuts, shellfish',
      targetTimeline: '12_weeks',
      consentAgreed: true,
    );

void main() {
  // ── INT-300 · the PAR-Q risk engine ────────────────────────────────────────
  //
  // Risk is the strongest safety signal the product collects. CON-04 is that
  // nothing consumes it; the prerequisite for consuming it is that it is
  // computed correctly and survives serialisation. That half is pinned here.
  group('INT-300 PAR-Q risk classification', () {
    test('high risk is exactly Q1, Q2, Q3, Q4 or Q7 — one is enough', () {
      for (final q in [1, 2, 3, 4, 7]) {
        expect(IntakeData(parqAnswers: {q: true}).riskLevel, 'high',
            reason: 'Q$q is a cardiac / syncope / physician-advised flag');
      }
      for (final q in [5, 6, 8]) {
        expect(IntakeData(parqAnswers: {q: true}).riskLevel, 'moderate',
            reason: 'Q$q is a yes, but not a high-risk question');
      }
    });

    test('no yes answers and no listed condition is low risk', () {
      expect(IntakeData(parqAnswers: const {1: false, 5: false}).riskLevel, 'low');
      expect(IntakeData().riskLevel, 'low');
    });

    test('pregnancy, heart disease and hypertension raise risk without a PAR-Q yes', () {
      for (final c in ['Pregnancy', 'Heart Disease', 'High Blood Pressure']) {
        expect(IntakeData(medicalConditions: [c]).riskLevel, 'moderate', reason: c);
      }
    });

    test('riskScore counts yes answers, not questions asked', () {
      expect(IntakeData(parqAnswers: const {1: true, 2: true, 3: false}).riskScore, 2);
      expect(IntakeData(parqAnswers: const {1: false, 2: false}).riskScore, 0);
    });

    test('every yes answer produces a named flag, plus the non-PAR-Q flags', () {
      final d = IntakeData(
        parqAnswers: const {1: true, 6: true},
        medicalConditions: const ['Pregnancy', 'Postpartum'],
        hasInjuries: true,
        injuryLocations: const ['left knee'],
      );
      expect(d.riskFlags, [
        'heart_condition',
        'bp_heart_medication',
        'pregnancy',
        'postpartum',
        'active_injuries',
      ]);
    });

    test('an injury with no named location produces no active_injuries flag', () {
      // The engine's injury factor keys off locations, so a bare `hasInjuries`
      // with nothing behind it must not read as a constraint.
      expect(IntakeData(hasInjuries: true).riskFlags, isEmpty);
    });

    test('DEFECT CON-02: risk is only carried by the per-step save when at '
        'least one PAR-Q question was answered', () {
      // The whole `parq_answers` / `risk_*` block is behind `parqAnswers.isNotEmpty`.
      // A client who reaches the health step and answers "no" to everything by
      // leaving it untouched sends NO risk data at all — and the final save then
      // writes risk_level 'low' over the absence.
      expect(IntakeData().toSupabasePartial(3).containsKey('risk_level'), isFalse);
      expect(_complete().toSupabase()['risk_level'], 'moderate');
    });
  });

  // ── INT-301 · CON-03, the two dietary_restrictions serializers ─────────────
  //
  // The same column is written as a Dart List by the per-step save and as a
  // comma-joined String by the final save. Whichever type the live column is,
  // exactly one of the two writers is wrong — and the caller of the losing one
  // swallows the failure (`catch (_) {}`), discarding that entire step.
  group('INT-301 dietary_restrictions has two conflicting serializers', () {
    test('DEFECT CON-03: the two write paths emit different Dart types for '
        'the same column', () {
      final d = _complete();
      final partial = d.toSupabasePartial(4)['dietary_restrictions'];
      final full = d.toSupabase()['dietary_restrictions'];

      expect(partial, isA<List<String>>(),
          reason: 'toSupabasePartial sends a real array');
      expect(full, isA<String>(),
          reason: 'toSupabase sends a comma-joined string');
      expect(partial.runtimeType == full.runtimeType, isFalse,
          reason: 'one serializer, one type — when CON-03 is fixed these two '
              'become the same type and this expectation flips');
    });

    test('DEFECT CON-03: the string path destroys a restriction containing a '
        'comma; the array path preserves it', () {
      final d = IntakeData(dietaryRestrictions: const ['no shellfish, no crab']);

      // Round-tripping through the string writer splits one restriction in two.
      final viaString = IntakeData.fromSupabase(
          {'dietary_restrictions': d.toSupabase()['dietary_restrictions']});
      expect(viaString.dietaryRestrictions, ['no shellfish', ' no crab']);

      // The array writer keeps it intact.
      final viaList = IntakeData.fromSupabase(
          {'dietary_restrictions': d.toSupabasePartial(4)['dietary_restrictions']});
      expect(viaList.dietaryRestrictions, ['no shellfish, no crab']);
    });

    test('the reader tolerates both shapes, which is why the divergence is '
        'invisible on read', () {
      expect(
          IntakeData.fromSupabase({'dietary_restrictions': ['vegan']})
              .dietaryRestrictions,
          ['vegan']);
      expect(
          IntakeData.fromSupabase({'dietary_restrictions': 'vegan,halal'})
              .dietaryRestrictions,
          ['vegan', 'halal']);
      expect(IntakeData.fromSupabase({}).dietaryRestrictions, isEmpty);
    });

    test('an empty restriction list is omitted by the per-step save entirely', () {
      expect(IntakeData().toSupabasePartial(4).containsKey('dietary_restrictions'),
          isFalse);
      expect(IntakeData().toSupabase()['dietary_restrictions'], '');
    });
  });

  // ── INT-302 · the safety inputs the AI meal planner depends on ─────────────
  //
  // CON-08 / E-NUT-05: allergies and restrictions are the only deterministic
  // guard the nutrition path could ever have, and CON-02 is why they are often
  // absent. Their presence in BOTH payloads is the precondition for that guard,
  // so it is pinned before the guard is built rather than after.
  group('INT-302 allergies survive both write paths', () {
    test('food_allergies is carried verbatim by the final save', () {
      expect(_complete().toSupabase()['food_allergies'], 'peanuts, shellfish');
    });

    test('food_allergies is carried by the per-step save when present', () {
      expect(_complete().toSupabasePartial(4)['food_allergies'],
          'peanuts, shellfish');
    });

    test('food_allergies round-trips without being split on its commas', () {
      // Unlike dietary_restrictions this is a free-text field on both sides, so
      // a comma is data. A future "make it a list too" change must not silently
      // start splitting it.
      final back = IntakeData.fromSupabase(_complete().toSupabase());
      expect(back.foodAllergies, 'peanuts, shellfish');
    });

    test('DEFECT CON-02: an absent allergy is indistinguishable from "none" '
        'in the per-step payload', () {
      // The key is omitted, so a partial save can never clear a previously
      // recorded allergy either. Recorded, not asserted as correct.
      expect(IntakeData().toSupabasePartial(4).containsKey('food_allergies'),
          isFalse);
      expect(IntakeData().toSupabase()['food_allergies'], '');
    });
  });

  // ── INT-303 · CON-02, completion is asserted by the payload itself ─────────
  group('INT-303 the final payload always claims completion', () {
    test('DEFECT CON-02: toSupabase() hardcodes onboarding_complete = true', () {
      // Completion is a fact about the data, not about the navigation. Because
      // the flag lives in the same payload as the answers, the caller that
      // writes the flag after a FAILED answer-write is writing a claim the data
      // does not support.
      final m = IntakeData().toSupabase(); // an entirely empty intake
      expect(m['onboarding_complete'], isTrue);
      expect(m['onboarding_step'], 0);
      expect(m['first_name'], '');
      expect(m['fitness_goal'], '');
      expect(m['parq_answers'], isEmpty);
    });

    test('the per-step payload claims only the step it reached', () {
      final m = _complete().toSupabasePartial(3);
      expect(m['onboarding_step'], 3);
      expect(m.containsKey('onboarding_complete'), isFalse,
          reason: 'the resume-position write is the good half of the design '
              'and must stay separate from the completion claim');
    });
  });

  // ── INT-304 · CON-06, the timestamp that crosses the wire ─────────────────
  group('INT-304 consent_date is written as a naive local timestamp', () {
    test('DEFECT CON-06: consent_date carries no zone marker', () {
      final iso = _complete().toSupabase()['consent_date'] as String;
      expect(iso, isNotEmpty);
      expect(iso.endsWith('Z'), isFalse,
          reason: 'DateTime.now().toIso8601String() renders local time with no '
              'offset; Postgres reads it into timestamptz AS UTC, so a client '
              'at UTC-5 records consent five hours early. Migration 108 fixed '
              'exactly this for workout_sessions.started_at and nowhere else.');
      expect(RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(iso), isFalse);
      expect(DateTime.parse(iso).isUtc, isFalse);
    });

    test('both write paths share the defect, so a fix must cover both', () {
      final partial = _complete().toSupabasePartial(6)['consent_date'] as String;
      expect(DateTime.parse(partial).isUtc, isFalse);
    });

    test('no consent means no consent_date is claimed', () {
      expect(IntakeData().toSupabase()['consent_date'], isNull);
      expect(IntakeData().toSupabasePartial(6).containsKey('consent_date'), isFalse);
    });

    test('date_of_birth is a plain date and is not affected', () {
      // A date has no zone, and it is correctly truncated before the wire.
      expect(_complete().toSupabase()['date_of_birth'], '1990-04-12');
    });
  });

  // ── INT-305 · comma-joined list columns ───────────────────────────────────
  //
  // `dietary_restrictions` is the finding, but it is not the only column
  // serialised by joining on a comma. These pin the blast radius so a contract
  // fix is scoped correctly rather than applied to one column.
  group('INT-305 every comma-joined column shares the same fragility', () {
    test('the joined columns are exactly the ones recorded here', () {
      final m = _complete().toSupabase();
      for (final key in [
        'biggest_challenges',
        'medical_conditions',
        'injury_locations',
        'dietary_restrictions',
        'risk_flags',
      ]) {
        expect(m[key], isA<String>(), reason: '$key is comma-joined');
      }
      // `activities` is the control: it is sent as a real array by BOTH paths,
      // which is what a converged dietary_restrictions should look like.
      expect(m['activities'], isA<List<String>>());
      expect(_complete().toSupabasePartial(2)['activities'], isA<List<String>>());
    });

    test('a medical condition containing a comma does not survive a round trip',
        () {
      final d = IntakeData(medicalConditions: const ['Type 2 diabetes, diet controlled']);
      final back = IntakeData.fromSupabase(d.toSupabase());
      expect(back.medicalConditions, hasLength(2),
          reason: 'one condition became two — the same defect shape as CON-03, '
              'on a column that feeds the engine injury/contraindication path');
    });

    test('an ordinary round trip preserves the answers it was given', () {
      final back = IntakeData.fromSupabase(_complete().toSupabase());
      expect(back.firstName, 'Ada');
      expect(back.primaryGoal, 'fat_loss');
      expect(back.parqAnswers, {1: false, 2: false, 5: true});
      expect(back.riskLevel, 'moderate');
      expect(back.hasInjuries, isTrue);
      expect(back.injuryDescription, 'ACL reconstruction 2024');
      expect(back.consentAgreed, isTrue);
      expect(back.trainingDays, 4);
      expect(back.weightKg, 64.5);
    });
  });
}
