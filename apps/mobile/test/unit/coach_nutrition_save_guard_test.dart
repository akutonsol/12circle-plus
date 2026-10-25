import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// COACH-N1 · saving a nutrition plan must not fail silently.
///
/// `_save()` in the coach's "Set Nutrition Targets" sheet awaited the RPC with no
/// handler: on any failure the exception escaped, the sheet kept spinning and the
/// coach was told nothing. Since migration 184 the RPC also refuses (SQLSTATE 42501)
/// when the relationship is no longer active, so the failure is no longer
/// hypothetical. The sibling Assign Habits sheet already had this shape.
void main() {
  final src = File('lib/features/dashboard/presentation/client_detail_screen.dart')
      .readAsStringSync();

  /// The body of the nutrition sheet's `_save`.
  String nutritionSave() {
    final start = src.indexOf('assignNutritionPlan(');
    expect(start, greaterThan(-1), reason: 'the nutrition save call moved or was removed');
    final from = src.lastIndexOf('Future<void> _save()', start);
    final to = src.indexOf('\n  }\n', start);
    return src.substring(from, to);
  }

  test('the RPC call sits inside a try block with a catch', () {
    final body = nutritionSave();
    expect(body.indexOf('try {'), lessThan(body.indexOf('assignNutritionPlan(')),
        reason: 'the call is outside the try — a failure escapes the sheet again');
    expect(body, contains('} catch ('));
  });

  test('the failure is reported, the spinner stops and the coach is told', () {
    final body = nutritionSave();
    expect(body, contains("reportError('AssignNutritionSheet._save'"));
    expect(body, contains('setState(() => _saving = false)'),
        reason: 'the sheet would keep spinning');
    expect(body, contains('showSnackBar'));
  });

  test('a refusal from migration 184 (42501) gets its own plain message', () {
    expect(src, contains("e.code == '42501'"));
    expect(nutritionSave(), contains("isn't active with you any more"));
  });
}
