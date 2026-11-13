import 'dart:io';

import 'package:circle_fitness/features/checkins/data/weekly_checkin_service.dart';
import 'package:circle_fitness/features/checkins/domain/checkin_columns.dart';
import 'package:flutter_test/flutter_test.dart';

// The coach's screens judged 1–5 check-in answers as if they ran to 10.
//
// The check-in form asks energy and stress with a five-tile NumberPicker, the hub
// prints "of 5", and the form raises its own coach notice at stress 4
// (`needsCoachAttention`: stress >= 4, energy <= 2). The coach's client page
// raised "High chronic stress" only above an average of 7 and coloured stress red
// only at 7; the dashboard counted high stress at >= 7 and coloured Avg Energy
// green only at 6. None of those values exist, so a client answering 5 of 5 every
// week was shown "✓ No flags — client trending well", the dashboard's high-stress
// recommendation never fired, and Avg Energy was never green.

void main() {
  test('a client reporting 5 of 5 stress every week is flagged', () {
    final flags = checkinInsights(count: 4, avgEnergy: 3, avgStress: 5, avgMood: 3);
    expect(flags, contains('⚠ High chronic stress — consider deload week'),
        reason: 'THE defect: an average above 7 was required, on a 1–5 scale');
    expect(flags, isNot(contains('✓ No flags — client trending well')));
  });

  test('the flag starts where the form tells the client their coach will see it', () {
    expect(isHighStress(4), isTrue);
    expect(isHighStress(3.9), isFalse);
    expect(isHighStress(null), isFalse);
    for (var s = 1; s <= kCheckinScaleMax; s++) {
      expect(isHighStress(s), WeeklyCheckinService.needsCoachAttention(energy: 5, stress: s),
          reason: 'one threshold, the same as the review queue, at stress $s');
    }
  });

  test('control: a calm, well-rested client has no flags', () {
    expect(checkinInsights(count: 4, avgEnergy: 4, avgStress: 2, avgMood: 4),
        ['✓ No flags — client trending well']);
  });

  test('control: no check-ins, no verdict', () {
    expect(checkinInsights(count: 0, avgEnergy: 0, avgStress: 0, avgMood: 0), isEmpty);
  });

  test('guard: no coach screen judges stress or energy on a 1–10 scale', () {
    // Source guard: it proves only that these literal thresholds are gone from
    // CHECK-IN values (averages, and a check-in row's `stress_level`). The
    // intake's own stress (`user_profiles.stress_level`) is a 0–10 slider
    // (intake_flow_screen clamps it to 0..10), so `stress >= 7` on it is right.
    final offenders = <String>[];
    final tenScale = RegExp(
        r"(avgStress|avgEnergy|\['stress_level'\][^;\n]*\))\s*>=?\s*(6|7|8|9|10)\b");
    for (final p in [
      'lib/features/dashboard/presentation/client_detail_screen.dart',
      'lib/features/dashboard/presentation/coach_dashboard_screen.dart',
    ]) {
      final lines = File(p).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (tenScale.hasMatch(lines[i])) offenders.add('$p:${i + 1}: ${lines[i].trim()}');
      }
    }
    expect(offenders, isEmpty);
  });
}
