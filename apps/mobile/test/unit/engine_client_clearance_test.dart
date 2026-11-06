import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/coach/domain/engine_client_clearance.dart';

// Verdict shapes are the engine_client_clearance results asserted on the local
// replay (supabase/tests/local/assignment_guard_replay.sql K01–K06).
void main() {
  group('readClearance — only an explicit, reason-free verdict is cleared', () {
    test('K01 shape: cleared with no reasons', () {
      final c = readClearance({'cleared': true, 'reasons': []});
      expect(c.cleared, isTrue);
      expect(copilotClearanceRefusal(c), isNull);
    });

    test('K02–K06 shapes are refused, each with its reason', () {
      for (final r in [
        ['INJURY_REPORTED'],
        ['INTAKE_INCOMPLETE', 'PARQ_INCOMPLETE'],
        ['PARQ_RISK_NOT_LOW'],
        ['PARQ_RISK_NOT_LOW', 'MEDICAL_ADVICE'],
        ['PARQ_INCOMPLETE'],
      ]) {
        final c = readClearance({'cleared': false, 'reasons': r});
        expect(c.cleared, isFalse);
        expect(c.reasons, r);
        expect(copilotClearanceRefusal(c), contains('by hand'));
      }
    });

    test('fail-closed: errors, missing RPC, odd shapes and contradictions are NOT cleared', () {
      for (final bad in [
        null, 'ok', <dynamic>[], <String, dynamic>{},
        {'cleared': 'true', 'reasons': []},
        {'cleared': true},
        {'cleared': true, 'reasons': ['INJURY_REPORTED']},
        {'cleared': false, 'reasons': []},
      ]) {
        expect(readClearance(bad).cleared, isFalse, reason: '$bad');
      }
    });
  });

  group('wording', () {
    test('names the reason a coach can act on', () {
      expect(copilotClearanceRefusal(readClearance({'cleared': false, 'reasons': ['INJURY_REPORTED']})),
          contains('reported an injury'));
      expect(copilotClearanceRefusal(readClearance({'cleared': false, 'reasons': ['PARQ_INCOMPLETE']})),
          contains('health-screening question'));
    });

    test('never claims safety or clinical clearance, never leaks internals', () {
      final msgs = [
        copilotClearanceRefusal(readClearance({'cleared': false, 'reasons': ['MEDICAL_ADVICE']}))!,
        copilotClearanceRefusal(readClearance(null))!,
        kAssignNotClearedMessage,
      ];
      for (final m in msgs) {
        expect(m, isNot(matches(RegExp(r'\bsafe|clinic|ENGINE_|migration|SQL|PAR-Q', caseSensitive: false))));
      }
    });

    test('isNotClearedError recognises the database refusal only', () {
      expect(isNotClearedError(Exception('ENGINE_CLIENT_NOT_CLEARED: programme …')), isTrue);
      expect(isNotClearedError(Exception('not authorized for this program')), isFalse);
    });
  });
}
