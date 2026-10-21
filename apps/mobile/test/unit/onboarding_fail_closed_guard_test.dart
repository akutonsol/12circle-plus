import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// EC-03 · SEC-G7 — onboarding must not mark itself complete after the save fails.
///
/// The removed code caught the final upsert and then explicitly wrote
/// `{'onboarding_complete': true, 'onboarding_step': 0}`, with the comment "so the user
/// isn't looped back here on next login". The cost of not being looped back was
/// everything the flow had collected: PAR-Q answers, medical conditions, injuries,
/// allergies, dietary restrictions, goal, experience and **consent** — discarded, while
/// the person was recorded as fully onboarded and could never return to supply them.
///
/// It is ratcheted statically because the alternative — driving the whole intake flow
/// against a failing database in a widget test — tests the harness more than the rule,
/// and the rule is textual: no catch block in this feature may claim completion.
///
/// Being looped back is the CORRECT outcome of an unsaved intake. `_saveProgress`
/// Phase 1 already persists `onboarding_step` with `onboarding_complete: false`, so the
/// person resumes rather than restarting.
void main() {
  const feature = 'lib/features/onboarding';
  late Map<String, String> sources;

  setUpAll(() {
    sources = {
      for (final f in Directory(feature)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')))
        f.path: f.readAsStringSync(),
    };
    expect(sources.length, greaterThanOrEqualTo(3),
        reason: 'SEC-G7 scanned ${sources.length} files under $feature — too few; a '
            'scan that walks nothing reports every rule satisfied');
    final flow = sources.keys.where((k) => k.endsWith('intake_flow_screen.dart'));
    expect(flow, hasLength(1), reason: 'the file this guard exists for must be scanned');
    expect(sources[flow.single]!.contains('_finish'), isTrue,
        reason: 'the scan cannot see _finish, so it is broken, not the code');
  });

  /// Returns the body of the brace-balanced block that starts at [from].
  String blockAt(String src, int from) {
    final open = src.indexOf('{', from);
    var depth = 0, i = open;
    do {
      if (src[i] == '{') depth++;
      if (src[i] == '}') depth--;
      i++;
    } while (depth > 0 && i < src.length);
    return src.substring(open, i);
  }

  // A local FUNCTION, not a getter: Dart does not allow a getter declaration inside
  // a function body, which is what the first draft of this file tried.
  String flowSource() =>
      sources.entries.firstWhere((e) => e.key.endsWith('intake_flow_screen.dart')).value;

  test('NO catch block anywhere in onboarding claims the flow is complete', () {
    final offenders = <String>[];
    for (final e in sources.entries) {
      final src = e.value;
      for (final m in RegExp(r'catch\s*\([^)]*\)\s*\{').allMatches(src)) {
        final body = blockAt(src, m.start);
        if (RegExp(r"""onboarding_complete['"]?\s*:\s*true""").hasMatch(body)) {
          offenders.add('${e.key}: a catch block sets onboarding_complete: true');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'a failed save is not a completed intake:\n${offenders.join('\n')}');
  });

  group('_finish', () {
    String finishBody() {
      final src = flowSource();
      final at = src.indexOf('Future<void> _finish()');
      expect(at, isNot(-1), reason: '_finish must exist to be checked');
      return blockAt(src, at);
    }

    test('its catch RETURNS, so nothing downstream runs over a failed save', () {
      final body = finishBody();
      final c = body.indexOf('catch');
      expect(c, isNot(-1), reason: '_finish must still handle the failure');
      final catchBody = blockAt(body, c);
      expect(catchBody.contains('return'), isTrue,
          reason: 'without a return, the success path runs anyway:\n$catchBody');
      expect(RegExp(r'onboarding_complete').hasMatch(catchBody), isFalse,
          reason: 'the catch must not touch the completion flag:\n$catchBody');
    });

    test('it records the failure so the person is TOLD, rather than silently routed on',
        () {
      final catchBody = blockAt(finishBody(), finishBody().indexOf('catch'));
      expect(catchBody.contains('_saveError'), isTrue,
          reason: 'the old behaviour\'s real problem was that nobody was told');
    });

    test('the score award and the plan generation sit AFTER the catch, so neither runs '
        'over answers the database never received', () {
      final body = finishBody();
      final catchEnd = body.indexOf('catch') +
          blockAt(body, body.indexOf('catch')).length;
      final score = body.indexOf('assessmentComplete');
      final plan = body.indexOf('generate_client_plan');
      expect(score, isNot(-1));
      expect(plan, isNot(-1));
      expect(score, greaterThan(catchEnd),
          reason: 'a score for an assessment that was not stored');
      expect(plan, greaterThan(catchEnd),
          reason: 'a program generated from answers that were not stored');
    });

    test('_done is never set inside the catch', () {
      final catchBody = blockAt(finishBody(), finishBody().indexOf('catch'));
      expect(RegExp(r'_done\s*=\s*true').hasMatch(catchBody), isFalse,
          reason: 'the completion screen must not follow a failed save');
    });
  });

  test('the flow has a visible failed-save state with a retry', () {
    final src = flowSource();
    expect(src.contains('String? _saveError'), isTrue);
    expect(src.contains('Retry'), isTrue,
        reason: 'a dead end is only marginally better than a silent loss');
  });

  test('the scan can actually see a violating catch', () {
    const bad = """
      try { await save(); } catch (_) {
        await db.update({'onboarding_complete': true});
      }""";
    final m = RegExp(r'catch\s*\([^)]*\)\s*\{').firstMatch(bad)!;
    expect(
        RegExp(r"""onboarding_complete['"]?\s*:\s*true""")
            .hasMatch(blockAt(bad, m.start)),
        isTrue);
  });
}
