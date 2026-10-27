import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/coach/domain/engine_generation.dart';

class _PgLike implements Exception {
  _PgLike(this.message, [this.code]);
  final String message;
  final String? code;
  @override
  String toString() => 'PostgrestException(message: $message, code: $code)';
}

void main() {
  group('classifyEngineError — matches the stable ENGINE_* prefixes of migration 186', () {
    test('each prefix maps to its failure', () {
      expect(classifyEngineError(_PgLike('ENGINE_NO_SELECTION: the coaching engine selected no exercises …', 'P0001')),
          EngineFailure.noSelection);
      expect(classifyEngineError(_PgLike('ENGINE_WEEK_EXISTS: week 1 … already has 3 training day(s).', 'P0001')),
          EngineFailure.weekExists);
      expect(classifyEngineError(_PgLike('ENGINE_BAD_PRESCRIPTION: sets, reps …', 'P0001')),
          EngineFailure.badPrescription);
      expect(classifyEngineError(_PgLike('ENGINE_NO_PLAN: programme x has no plan', 'P0001')), EngineFailure.noPlan);
      expect(classifyEngineError(_PgLike('ENGINE_NO_WEEK: week 9 is not in the plan', 'P0001')), EngineFailure.noPlan);
    });

    test('188: an unknown session label is unsupportedSplit; an unknown module is never success', () {
      expect(classifyEngineError(_PgLike('ENGINE_UNKNOWN_FOCUS: the engine has no movement-pattern mapping for session "Arms"', '22023')),
          EngineFailure.unsupportedSplit);
      expect(classifyEngineError(_PgLike('ENGINE_UNKNOWN_MODULE: build_workout needs "module" …', '22023')),
          EngineFailure.unknown);
      expect(classifyEngineError(_PgLike(
              'ENGINE_NO_SELECTION: … (status NO_ELIGIBLE_EXERCISES, rejected {"NOT_CERTIFIED_FOR_MODULE": 604})', 'P0001')),
          EngineFailure.noSelection);
    });

    test('188/189: insufficient compound and an uncleared assigned client have their own failures', () {
      expect(classifyEngineError(_PgLike('ENGINE_INSUFFICIENT_ELIGIBLE: week 1, session "Push" … has no eligible compound lift', 'P0001')),
          EngineFailure.insufficientEligible);
      // Raised as 42501 — must not be mistaken for "you can't act on this programme".
      expect(classifyEngineError(_PgLike('ENGINE_CLIENT_NOT_CLEARED: programme x is assigned to a client who is not cleared', '42501')),
          EngineFailure.clientNotCleared);
      expect(classifyEngineError(_PgLike('not authorized for this program', '42501')), EngineFailure.notAuthorized);
    });

    test('42501 from the authorization wrapper is notAuthorized, whatever the text', () {
      expect(classifyEngineError(_PgLike('not authorized for this program', '42501')), EngineFailure.notAuthorized);
    });

    test('anything else — including the pre-186 23514 — is unknown, never success', () {
      expect(classifyEngineError(_PgLike('violates check constraint "program_workouts_exercises_canonical"', '23514')),
          EngineFailure.unknown);
      expect(classifyEngineError(Exception('SocketException')), EngineFailure.unknown);
    });
  });

  group('summarizeMaterialization — a result is trusted only if every session reports exercises', () {
    test('a 186 result is summarized', () {
      final r = {
        'week': 1, 'sessions_created': 3,
        'sessions': [
          {'session': 'Push', 'exercises': 5},
          {'session': 'Pull', 'exercises': 5},
          {'session': 'Legs', 'exercises': 4},
        ],
      };
      expect(summarizeMaterialization(r), (days: 3, exercises: 14));
    });

    test('a pre-186 result (no exercise counts) is NOT success', () {
      final r = {'week': 1, 'sessions_created': 3, 'sessions': [
        {'session': 'Push', 'trace_id': 'x'}, {'session': 'Pull', 'trace_id': 'y'}]};
      expect(summarizeMaterialization(r), isNull,
          reason: 'this is exactly the shape that saved empty days and called it success');
    });

    test('a session with zero exercises, no sessions, or a non-map is NOT success', () {
      expect(summarizeMaterialization({'sessions': [{'exercises': 0}]}), isNull);
      expect(summarizeMaterialization({'sessions': []}), isNull);
      expect(summarizeMaterialization(null), isNull);
      expect(summarizeMaterialization('ok'), isNull);
    });
  });

  group('engineContextFor', () {
    test('uses Copilot\'s goal vocabulary and no equipment filter', () {
      expect(engineContextFor(programType: 'Fat Loss')['goal'], 'fat_loss');
      expect(engineContextFor(programType: 'Strength')['goal'], 'strength');
      expect(engineContextFor(programType: 'Athletic')['goal'], 'strength');
      expect(engineContextFor(programType: 'Hypertrophy')['goal'], 'hypertrophy');
      expect(engineContextFor(programType: 'General Fitness')['goal'], 'hypertrophy');
      expect(engineContextFor(programType: 'Strength').containsKey('equipment'), isFalse);
    });

    test('never sends a module or focus: the engine sets both, so a caller cannot widen the gate', () {
      final c = engineContextFor(programType: 'Strength');
      expect(c.containsKey('module'), isFalse);
      expect(c.containsKey('focus'), isFalse);
    });

    test('replace_existing is absent by default and a JSON true only when asked', () {
      expect(engineContextFor(programType: 'Strength').containsKey('replace_existing'), isFalse);
      expect(engineContextFor(programType: 'Strength', replaceExisting: true)['replace_existing'], isTrue);
    });
  });

  test('every failure has a coach-facing sentence that does not leak internals', () {
    for (final f in EngineFailure.values) {
      final m = coachMessageFor(f);
      expect(m, isNotEmpty);
      expect(m, isNot(matches(RegExp(r'ENGINE_|migration|SQL|substrate|23514', caseSensitive: false))),
          reason: '$f leaks implementation detail to a coach: "$m"');
    }
  });

  test('the integration flag is OFF unless explicitly defined', () {
    expect(kEngineWeekGeneration, isFalse,
        reason: 'must stay off until the target database has migration 186');
  });
}
