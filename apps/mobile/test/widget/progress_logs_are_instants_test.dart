import 'dart:io';

import 'package:circle_fitness/features/dashboard/presentation/client_detail_screen.dart';
import 'package:circle_fitness/features/progress/presentation/progress_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Weigh-ins, measurements and progress photos were dated in the wrong zone.
//
// `weight_logs`, `body_measurements` and `progress_photo_logs` store `logged_at`
// as timestamptz (000). Progress wrote `DateTime.now().toIso8601String()` —
// local time, no zone — which Postgres reads as UTC, and every reader on the
// client converts it back with `toLocal()`. So a New York weigh-in at 01:00 was
// listed under the day before, a Sydney one at 21:00 under tomorrow, and the
// measurements card said "Updated 5h ago" a moment after saving.
//
// The writes now send UTC instants. The coach's client page took the first ten
// characters of the stored string as the day (the weigh-in list and the
// timeline), which only matched because the stored time was local; it now
// converts the instant to the coach's own day (`localDayOf`).
//
// HOW TO SEE IT FAIL: the wire-format tests fail on the old code in any zone.

Widget _launcher(Widget Function() sheet) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => showModalBottomSheet(
              context: ctx, isScrollControlled: true, builder: (_) => sheet()),
            child: const Text('open'),
          ),
        ),
      ),
    );

bool _zoned(String v) => v.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(v);

Future<void> _openAndSave(WidgetTester tester, String label) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final previous = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exceptionAsString().contains('A RenderFlex overflowed')) return;
    previous?.call(d);
  };
  addTearDown(() => FlutterError.onError = previous);
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void _expectInstantNow(String? sent) {
  expect(sent, isNotNull);
  expect(_zoned(sent!), isTrue,
      reason: 'THE defect: `$sent` has no zone, so Postgres stores it as UTC');
  expect(DateTime.parse(sent).toUtc().difference(DateTime.now().toUtc()).inSeconds.abs(),
      lessThan(60));
}

void main() {
  testWidgets('a weigh-in is stored at the moment it was logged', (tester) async {
    String? sent;
    await tester.pumpWidget(_launcher(() => LogWeightSheet(
          initialKg: 70,
          onSaved: () {},
          writeRow: (t, row) async => sent = row['logged_at'] as String?,
        )));
    await _openAndSave(tester, 'Save Entry');
    _expectInstantNow(sent);
  });

  testWidgets('a measurement is stored at the moment it was logged', (tester) async {
    String? sent;
    await tester.pumpWidget(_launcher(() => LogMeasurementSheet(
          onSaved: () {},
          writeRow: (t, row) async => sent = row['logged_at'] as String?,
        )));
    await _openAndSave(tester, 'Save Measurements');
    tester.takeException(); // the points award has no Supabase here
    _expectInstantNow(sent);
  });

  test("the coach's client page dates an instant on the coach's own day", () {
    final now = DateTime.now();
    final evening = DateTime(now.year, now.month, now.day, 21);
    final day = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    expect(localDayOf(evening.toUtc().toIso8601String()), day,
        reason: 'the first ten characters of a UTC instant are the UTC date');
    expect(localDayOf('2026-11-09'), '2026-11-09', reason: 'a date-only value is kept');
    expect(localDayOf(null), '');
  });

  test('guard: no progress log is written with a zoneless logged_at', () {
    final src = File('lib/features/progress/presentation/progress_screen.dart').readAsStringSync();
    expect(src.contains("'logged_at': DateTime.now().toIso8601String()"), isFalse);
  });
}
