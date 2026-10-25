import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ENG-H1 · coach-facing engine screens tell the truth about what was built.
///
/// Verified on a local replay of migrations 000–181 (QA's declared state):
///   * the engine behind `/program-designer` saves a program with a plan and NO
///     training days, and the step that would fill them has no caller in the app;
///   * with 0 intelligence profiles Copilot gets an empty selection, and with a
///     populated substrate `materialize_program_week` fails the canonical
///     prescription check.
/// These assertions keep the three coach-facing promises honest until the engine
/// itself is fixed by migration.
void main() {
  String strip(String s) =>
      s.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '').replaceAll(RegExp(r'//[^\n]*'), '');
  final builder = strip(File('lib/features/coach/presentation/dynamic_program_builder_screen.dart')
      .readAsStringSync());
  final copilot = strip(File('lib/features/coach/presentation/coach_copilot_screen.dart')
      .readAsStringSync());
  final assign = strip(File('lib/features/dashboard/presentation/client_detail_screen.dart')
      .readAsStringSync());

  test('Program Builder does not send coaches to a materialize step that does not exist', () {
    expect(builder, isNot(contains('materialize week 1')));
    expect(builder, contains('no training days yet'),
        reason: 'the coach must be told the saved program is empty');
  });

  test('Copilot shows coach-facing copy, not deployment instructions', () {
    expect(copilot, isNot(contains('MIE migrations')));
    expect(copilot, contains("Couldn't generate a recommendation"),
        reason: 'a failed call must say so instead of leaving the panel blank');
    expect(copilot, contains('_rec == null && _status != null'),
        reason: 'the failure line must render when there is no recommendation');
  });

  test('a program known to have no training days cannot be assigned', () {
    expect(assign, contains('isKnownEmptyProgram(p)'));
    expect(assign, contains('onTap: empty ? null'),
        reason: 'an empty program must not be selectable in the Assign sheet');
    expect(assign, contains("reportError('AssignProgramSheet._assign'"));
  });
}
