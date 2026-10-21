// QAX-ERR-01 (+ F-06 / F-22) — what the Women's Health sheets do when a write
// does not land.
//
// Before the fix: `logPeriod` / `logSymptoms` were awaited inside `onPressed`
// with no handler and the app installs no global error handler, so a failed
// write escaped as an unhandled async error, `Navigator.pop` never ran, and the
// user saw a sheet that simply did nothing. After migration 131 a re-logged
// start date fails with 23505 on exactly this path. "Period ended" with no open
// period closed the sheet as if it had worked.
//
// These drive the real screen through a fake service: a failure must keep the
// sheet open AND say so; success must still close it (the positive control —
// a "fix" that never closes the sheet would pass the failure tests alone).
import 'package:circle_fitness/features/womens_health/data/cycle_service.dart';
import 'package:circle_fitness/features/womens_health/domain/cycle_provider.dart';
import 'package:circle_fitness/features/womens_health/presentation/womens_health_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeCycleService implements CycleService {
  _FakeCycleService({this.failWrites = false, this.hasOpenPeriod = true,
      this.today, this.failTodayRead = false});

  final bool failWrites;
  final bool hasOpenPeriod;
  final Map<String, dynamic>? today;
  final bool failTodayRead;
  int logPeriodCalls = 0;
  int logSymptomsCalls = 0;
  Map<String, Object?>? lastSymptoms;

  Never _fail() => throw Exception('simulated write failure');

  @override
  Future<Map<String, dynamic>?> getSettings() async => null;
  @override
  Future<void> saveSettings({int? cycleLength, int? periodLength}) async {
    if (failWrites) _fail();
  }

  @override
  Future<List<Map<String, dynamic>>> getPeriods({int limit = 12}) async => [];
  @override
  Future<void> logPeriod({required DateTime start, DateTime? end}) async {
    logPeriodCalls++;
    if (failWrites) _fail();
  }

  @override
  Future<bool> endCurrentPeriod(DateTime end) async {
    if (failWrites) _fail();
    return hasOpenPeriod;
  }

  @override
  Future<void> logSymptoms({
    required DateTime date,
    required List<String> symptoms,
    int? energy,
    int? mood,
    String? flow,
    String? notes,
  }) async {
    logSymptomsCalls++;
    lastSymptoms = {'symptoms': symptoms, 'energy': energy, 'mood': mood};
    if (failWrites) _fail();
  }

  @override
  Future<Map<String, dynamic>?> getSymptomsForDate(DateTime date) async {
    if (failTodayRead) _fail();
    return today;
  }
  @override
  Future<List<Map<String, dynamic>>> getRecentSymptoms({int limit = 14}) async => [];
}

Widget _screen(CycleService svc) => ProviderScope(
      overrides: [cycleServiceProvider.overrideWithValue(svc)],
      child: const MaterialApp(home: WomensHealthScreen()),
    );

Future<void> _openPeriodSheet(WidgetTester tester) async {
  await tester.tap(find.text('Log period'));
  await tester.pumpAndSettle();
  expect(find.text('Log your period'), findsOneWidget);
}

Future<void> _openSymptomSheet(WidgetTester tester) async {
  await tester.tap(find.text('Log symptoms'));
  await tester.pumpAndSettle();
  expect(find.text('How are you feeling?'), findsOneWidget);
}

void main() {
  group('QAX-ERR-01 a failed cycle write is surfaced, never silent', () {
    testWidgets('failed period save: sheet stays open and says it did not save',
        (tester) async {
      final svc = _FakeCycleService(failWrites: true);
      await tester.pumpWidget(_screen(svc));
      await tester.pumpAndSettle();
      await _openPeriodSheet(tester);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'the failure must be handled, not escape as an unhandled error');
      expect(svc.logPeriodCalls, 1);
      expect(find.text('Log your period'), findsOneWidget, reason: 'sheet stays open');
      expect(find.text(cycleSaveFailedMessage), findsOneWidget);
    });

    testWidgets('failed symptom save: sheet stays open and says it did not save',
        (tester) async {
      final svc = _FakeCycleService(failWrites: true);
      await tester.pumpWidget(_screen(svc));
      await tester.pumpAndSettle();
      await _openSymptomSheet(tester);

      await tester.ensureVisible(find.text('Save check-in'));
      await tester.tap(find.text('Save check-in'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(svc.logSymptomsCalls, 1);
      expect(find.text('How are you feeling?'), findsOneWidget);
      expect(find.text(cycleSaveFailedMessage), findsOneWidget);
    });

    testWidgets('"Period ended" with no open period says so instead of closing',
        (tester) async {
      await tester.pumpWidget(_screen(_FakeCycleService(hasOpenPeriod: false)));
      await tester.pumpAndSettle();
      await _openPeriodSheet(tester);

      await tester.tap(find.text('Period ended'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Log your period'), findsOneWidget);
      expect(find.text(noOpenPeriodMessage), findsOneWidget);
    });
  });

  group('QAX-ERR-01 positive controls — success still closes the sheet', () {
    testWidgets('successful period save closes the sheet', (tester) async {
      final svc = _FakeCycleService();
      await tester.pumpWidget(_screen(svc));
      await tester.pumpAndSettle();
      await _openPeriodSheet(tester);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(svc.logPeriodCalls, 1);
      expect(find.text('Log your period'), findsNothing);
      expect(find.text(cycleSaveFailedMessage), findsNothing);
    });

    testWidgets('successful "Period ended" closes the sheet', (tester) async {
      await tester.pumpWidget(_screen(_FakeCycleService(hasOpenPeriod: true)));
      await tester.pumpAndSettle();
      await _openPeriodSheet(tester);

      await tester.tap(find.text('Period ended'));
      await tester.pumpAndSettle();

      expect(find.text('Log your period'), findsNothing);
    });
  });

  group('F-03 re-opening the symptom sheet keeps today\'s saved check-in', () {
    testWidgets('saving without changes writes back exactly what was saved',
        (tester) async {
      final svc = _FakeCycleService(today: {
        'symptoms': ['Cramps', 'Migraine aura'], // the 2nd is not a chip option
        'energy': 2,
        'mood': 5,
      });
      await tester.pumpWidget(_screen(svc));
      await tester.pumpAndSettle();
      await _openSymptomSheet(tester);

      await tester.ensureVisible(find.text('Save check-in'));
      await tester.tap(find.text('Save check-in'));
      await tester.pumpAndSettle();

      expect(svc.lastSymptoms, isNotNull);
      expect((svc.lastSymptoms!['symptoms'] as List).toSet(),
          {'Cramps', 'Migraine aura'},
          reason: 'saved symptoms, including ones outside the chip list, survive');
      expect(svc.lastSymptoms!['energy'], 2);
      expect(svc.lastSymptoms!['mood'], 5);
    });

    testWidgets('if today\'s check-in cannot be read, no blank sheet opens',
        (tester) async {
      final svc = _FakeCycleService(failTodayRead: true);
      await tester.pumpWidget(_screen(svc));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log symptoms'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('How are you feeling?'), findsNothing,
          reason: 'a blank sheet would overwrite today\'s saved values on Save');
      expect(find.text(cycleLoadFailedMessage), findsOneWidget);
      expect(svc.logSymptomsCalls, 0);
    });
  });

  testWidgets('F-03 an out-of-range saved value (no DB constraint, F-01) '
      'still opens the sheet', (tester) async {
    final svc = _FakeCycleService(today: {'symptoms': <String>[], 'energy': 99, 'mood': -5});
    await tester.pumpWidget(_screen(svc));
    await tester.pumpAndSettle();
    await _openSymptomSheet(tester);
    expect(tester.takeException(), isNull);
  });
}
